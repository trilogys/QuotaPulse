import Foundation

public enum UsageError: LocalizedError {
  case missingAccount
  case missingCredential
  case unauthorized
  case http(Int, String)
  case invalidResponse(String)
  case refreshFailed(String)

  public var errorDescription: String? {
    switch self {
    case .missingAccount: "Account not found"
    case .missingCredential: "Credential not found"
    case .unauthorized: "Login expired"
    case .http(let code, let message): "HTTP \(code): \(message)"
    case .invalidResponse(let message): "Invalid response: \(message)"
    case .refreshFailed(let message): "Token refresh failed: \(message)"
    }
  }
}

actor UsageService {
  static let shared = UsageService()
  private let http = HTTPClient.shared
  private let keychain = KeychainStore.shared

  private struct CodexResetCreditCandidate {
    let id: String
    let expiresAt: Date?
  }

  private struct CodexResetCreditPayload {
    let summary: CodexResetCreditSummary
    let candidates: [CodexResetCreditCandidate]
  }

  private struct CodexModelUsageKey: Hashable {
    let model: String
    let reasoningEffort: String?
    let speed: String?
  }

  private struct OpenAIAdminUsagePayload {
    let tokenUsage: CodexTokenUsageSummary
    let modelUsage: CodexModelUsageSummary
  }

  @discardableResult
  func refresh(accountID: UUID) async throws -> UsageSnapshot {
    guard let account = await SharedStore.shared.account(id: accountID) else { throw UsageError.missingAccount }
    do {
      let snapshot = try await fetch(account: account)
      await SharedStore.shared.saveSnapshot(snapshot)
      await QuotaNotifier.shared.evaluate(account: account, snapshot: snapshot)
      return snapshot
    } catch {
      if await SharedStore.shared.snapshot(for: accountID) == nil {
        await SharedStore.shared.saveSnapshot(UsageSnapshot(accountID: account.id, provider: account.provider, errorMessage: error.localizedDescription, stale: true))
      } else {
        await SharedStore.shared.markSnapshotStale(accountID: accountID, message: error.localizedDescription)
      }
      throw error
    }
  }

  func refresh(accountIDs: [UUID]) async -> [UsageSnapshot] {
    await withTaskGroup(of: UsageSnapshot?.self) { group in
      for id in accountIDs { group.addTask { try? await UsageService.shared.refresh(accountID: id) } }
      var snapshots: [UsageSnapshot] = []
      for await value in group { if let value { snapshots.append(value) } }
      return snapshots
    }
  }

  func refreshVisible(limit: Int? = nil) async -> [UsageSnapshot] {
    let accounts = await SharedStore.shared.displayAccounts(limit: limit)
    return await refresh(accountIDs: accounts.map(\.id))
  }

  func queryCodexResetCredits(accountID: UUID) async throws -> CodexResetCreditSummary {
    guard let account = await SharedStore.shared.account(id: accountID), account.provider == .codex else {
      throw UsageError.missingAccount
    }
    guard var credential = try keychain.credential(accountID: accountID) else {
      throw UsageError.missingCredential
    }
    guard credential.authenticationMode != .apiKey else {
      throw UsageError.invalidResponse("Codex reset credits require ChatGPT OAuth")
    }
    let payload = try await fetchCodexResetCreditPayload(account: account, credential: &credential)
    var snapshot = await SharedStore.shared.snapshot(for: accountID)
      ?? UsageSnapshot(accountID: accountID, provider: .codex)
    snapshot.codexResetCredits = payload.summary
    await SharedStore.shared.saveSnapshot(snapshot)
    return payload.summary
  }

  func consumeCodexResetCredit(accountID: UUID) async throws -> CodexQuotaResetResult {
    guard let account = await SharedStore.shared.account(id: accountID), account.provider == .codex else {
      throw UsageError.missingAccount
    }
    guard var credential = try keychain.credential(accountID: accountID) else {
      throw UsageError.missingCredential
    }

    guard credential.authenticationMode != .apiKey else {
      throw UsageError.invalidResponse("Codex quota reset requires ChatGPT OAuth")
    }
    let payload = try await fetchCodexResetCreditPayload(account: account, credential: &credential)
    guard payload.summary.availableCount > 0 else {
      throw UsageError.invalidResponse("No Codex reset credits available")
    }
    let candidate = payload.candidates.sorted {
      ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
    }.first
    guard let creditID = candidate?.id, !creditID.isEmpty else {
      throw UsageError.invalidResponse("Reset credit details did not include credit_id")
    }

    let requestID = UUID().uuidString.lowercased()
    let body = try JSONSerialization.data(withJSONObject: [
      "credit_id": creditID,
      "redeem_request_id": requestID,
    ])
    func call(_ credential: Credential) async throws -> HTTPResult {
      var headers = codexQuotaHeaders(credential)
      headers["Content-Type"] = "application/json"
      return try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!,
        method: "POST",
        headers: headers,
        body: body,
        timeout: 20
      )
    }
    let result: HTTPResult
    do {
      var response = try await call(credential)
      if response.statusCode == 401, credential.refreshToken != nil {
        credential = try await refreshCodexCredential(credential, accountID: accountID)
        response = try await call(credential)
      }
      result = response
    } catch {
      await invalidateCodexResetCredits(accountID: accountID)
      throw UsageError.refreshFailed("Reset result unknown; query reset credits before retrying: \(error.localizedDescription)")
    }
    guard (200..<300).contains(result.statusCode) else {
      await invalidateCodexResetCredits(accountID: accountID)
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    return CodexQuotaResetResult(
      code: string(root["code"]) ?? "ok",
      windowsReset: Int(number(root["windows_reset"]) ?? 0)
    )
  }

  func queryCodexModelUsage(accountID: UUID) async throws -> CodexModelUsageSummary {
    guard let account = await SharedStore.shared.account(id: accountID), account.provider == .codex else {
      throw UsageError.missingAccount
    }
    guard var credential = try keychain.credential(accountID: accountID) else {
      throw UsageError.missingCredential
    }
    guard credential.authenticationMode != .apiKey else {
      throw UsageError.invalidResponse("Codex thread usage requires ChatGPT OAuth")
    }
    let summary = try await fetchCodexModelUsage(
      account: account,
      credential: &credential
    )
    var snapshot = await SharedStore.shared.snapshot(for: accountID)
      ?? UsageSnapshot(accountID: accountID, provider: .codex)
    snapshot.codexModelUsage = summary
    await SharedStore.shared.saveSnapshot(snapshot)
    return summary
  }

  private func fetch(account: AccountRecord) async throws -> UsageSnapshot {
    guard var credential = try keychain.credential(accountID: account.id) else { throw UsageError.missingCredential }
    switch account.provider {
    case .codex: return try await fetchCodex(account: account, credential: &credential)
    case .claude: return try await fetchClaude(account: account, credential: &credential)
    case .kimi: return try await fetchKimi(account: account, credential: &credential)
    case .deepseek: return try await fetchDeepSeek(account: account, credential: credential)
    case .minimax: return try await fetchMiniMax(account: account, credential: credential)
    case .glm: return try await fetchGLM(account: account, credential: credential)
    case .copilot: return try await fetchCopilot(account: account, credential: credential)
    }
  }

  private func fetchCodex(account: AccountRecord, credential: inout Credential) async throws -> UsageSnapshot {
    if credential.authenticationMode == .apiKey {
      return try await fetchOpenAIAPIKey(account: account, credential: credential)
    }
    func call(_ credential: Credential) async throws -> HTTPResult {
      try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        headers: codexQuotaHeaders(credential)
      )
    }
    var result = try await call(credential)
    if result.statusCode == 401, credential.refreshToken != nil { credential = try await refreshCodexCredential(credential, accountID: account.id); result = try await call(credential) }
    guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }
    let root = try result.jsonDictionary()
    guard let rateLimit = dictionary(root["rate_limit"]) else { throw UsageError.invalidResponse("Missing rate_limit") }
    var windows: [UsageWindow] = []
    for (key, rawAny) in rateLimit {
      guard key.hasSuffix("_window"), let raw = dictionary(rawAny), number(raw["used_percent"]) != nil else { continue }
      let duration = int64(raw["limit_window_seconds"]) ?? 0
      let used = number(raw["used_percent"]) ?? 0
      let resetAt: Date?
      if let epoch = int64(raw["reset_at"]), epoch > 0 { resetAt = Date(timeIntervalSince1970: TimeInterval(epoch)) }
      else if let seconds = int64(raw["reset_after_seconds"]), seconds >= 0 { resetAt = Date().addingTimeInterval(TimeInterval(seconds)) }
      else { resetAt = nil }
      windows.append(UsageWindow(id: "codex-\(key)", label: durationLabel(seconds: duration), remainingPercent: 100 - used, resetAt: resetAt))
    }
    windows = uniqueWindows(windows)
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Codex quota windows") }
    let resetCredits: CodexResetCreditSummary?
    if let current = codexResetCreditPayload(from: root)?.summary {
      resetCredits = current
    } else {
      let cached = await SharedStore.shared.snapshot(for: account.id)
      resetCredits = cached?.codexResetCredits
    }
    let cachedSnapshot = await SharedStore.shared.snapshot(for: account.id)
    let cachedTokenUsage = cachedSnapshot?.codexTokenUsage
    let tokenUsage = (try? await fetchCodexTokenUsage(credential: credential)) ?? cachedTokenUsage
    return UsageSnapshot(
      accountID: account.id,
      provider: .codex,
      windows: windows,
      codexResetCredits: resetCredits,
      codexTokenUsage: tokenUsage,
      codexModelUsage: cachedSnapshot?.codexModelUsage,
      authenticationMode: .oauth
    )
  }

  private func fetchOpenAIAPIKey(
    account: AccountRecord,
    credential: Credential
  ) async throws -> UsageSnapshot {
    let base = apiV1BaseURL(credential.baseURL, fallback: "https://api.openai.com")
    let result = try await http.send(
      URL(string: "\(base)/models")!,
      headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    let models = availableModelIDs(root)
    let modelCount = models.count
    let adminUsage = try? await fetchOpenAIAdminUsage(base: base, credential: credential)
    return UsageSnapshot(
      accountID: account.id,
      provider: .codex,
      metrics: [
        UsageMetric(label: "认证", value: "API Key"),
        UsageMetric(label: "可用模型", value: "\(modelCount)"),
      ],
      availableModels: models,
      codexTokenUsage: adminUsage?.tokenUsage,
      codexModelUsage: adminUsage?.modelUsage,
      authenticationMode: .apiKey,
      plan: "OpenAI API"
    )
  }

  private func fetchOpenAIAdminUsage(
    base: String,
    credential: Credential
  ) async throws -> OpenAIAdminUsagePayload? {
    var components = URLComponents(string: "\(base)/organization/usage/completions")!
    components.queryItems = [
      URLQueryItem(name: "start_time", value: "\(Int(Date().addingTimeInterval(-30 * 86_400).timeIntervalSince1970))"),
      URLQueryItem(name: "bucket_width", value: "1d"),
      URLQueryItem(name: "limit", value: "31"),
      URLQueryItem(name: "group_by", value: "model"),
    ]
    guard let url = components.url else { return nil }
    let result = try await http.send(
      url,
      headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"],
      timeout: 20
    )
    guard (200..<300).contains(result.statusCode) else { return nil }
    let root = try result.jsonDictionary()
    let buckets = (root["data"] as? [[String: Any]]) ?? []
    var daily: [CodexDailyTokenUsage] = []
    var groups: [CodexModelUsageKey: CodexModelTokenUsage] = [:]
    var requestCount: Int64 = 0
    for bucket in buckets {
      guard let start = int64(bucket["start_time"]) else { continue }
      let results = (bucket["results"] as? [[String: Any]]) ?? []
      var dailyTotal: Int64 = 0
      for raw in results {
        let input = int64(raw["input_tokens"]) ?? 0
        let cached = int64(raw["input_cached_tokens"]) ?? 0
        let output = int64(raw["output_tokens"]) ?? 0
        let total = input + output
        dailyTotal += total
        requestCount += int64(raw["num_model_requests"]) ?? 0
        let key = CodexModelUsageKey(
          model: string(raw["model"]) ?? "未分组模型",
          reasoningEffort: nil,
          speed: string(raw["service_tier"])
        )
        let current = groups[key] ?? CodexModelTokenUsage(
          model: key.model,
          reasoningEffort: nil,
          speed: key.speed,
          inputTokens: 0,
          cachedInputTokens: 0,
          outputTokens: 0,
          totalTokens: 0,
          estimatedUsageCreditsMicros: 0
        )
        groups[key] = CodexModelTokenUsage(
          model: current.model,
          reasoningEffort: current.reasoningEffort,
          speed: current.speed,
          inputTokens: current.inputTokens + input,
          cachedInputTokens: current.cachedInputTokens + cached,
          outputTokens: current.outputTokens + output,
          totalTokens: current.totalTokens + total,
          estimatedUsageCreditsMicros: 0
        )
      }
      daily.append(CodexDailyTokenUsage(
        startDate: Date(timeIntervalSince1970: TimeInterval(start)),
        tokens: dailyTotal
      ))
    }
    let tokenUsage = CodexTokenUsageSummary(
      lifetimeTokens: nil,
      peakDailyTokens: daily.map(\.tokens).max(),
      longestRunningTurnSeconds: nil,
      currentStreakDays: nil,
      longestStreakDays: nil,
      dailyUsageBuckets: daily.sorted { $0.startDate < $1.startDate }
    )
    guard tokenUsage.hasData || !groups.isEmpty else { return nil }
    return OpenAIAdminUsagePayload(
      tokenUsage: tokenUsage,
      modelUsage: CodexModelUsageSummary(
        groups: groups.values.sorted { $0.totalTokens > $1.totalTokens },
        returnedThreadCount: Int(requestCount),
        estimatedUsageUSDMicros: nil,
        isPartial: bool(root["has_more"]) ?? false,
        fetchedAt: .now
      )
    )
  }

  private func fetchCodexTokenUsage(credential: Credential) async throws -> CodexTokenUsageSummary? {
    let result = try await http.send(
      URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!,
      headers: codexQuotaHeaders(credential),
      timeout: 20
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    let profile = dictionary(root["profile"]) ?? root
    let stats = dictionary(profile["stats"])
      ?? dictionary(root["summary"])
      ?? profile
    let rawBuckets = (stats["daily_usage_buckets"] as? [[String: Any]])
      ?? (stats["dailyUsageBuckets"] as? [[String: Any]])
      ?? (root["dailyUsageBuckets"] as? [[String: Any]])
      ?? []
    let buckets = rawBuckets.compactMap { item -> CodexDailyTokenUsage? in
      let dateValue = string(item["start_date"] ?? item["startDate"])
      guard let startDate = parseCodexDay(dateValue),
            let tokens = int64(item["tokens"]) else { return nil }
      return CodexDailyTokenUsage(startDate: startDate, tokens: max(0, tokens))
    }.sorted { $0.startDate < $1.startDate }
    let summary = CodexTokenUsageSummary(
      lifetimeTokens: int64(stats["lifetime_tokens"] ?? stats["lifetimeTokens"]),
      peakDailyTokens: int64(stats["peak_daily_tokens"] ?? stats["peakDailyTokens"]),
      longestRunningTurnSeconds: int64(stats["longest_running_turn_sec"] ?? stats["longestRunningTurnSec"]),
      currentStreakDays: int64(stats["current_streak_days"] ?? stats["currentStreakDays"]),
      longestStreakDays: int64(stats["longest_streak_days"] ?? stats["longestStreakDays"]),
      dailyUsageBuckets: buckets
    )
    return summary.hasData ? summary : nil
  }

  private func fetchCodexModelUsage(
    account: AccountRecord,
    credential: inout Credential
  ) async throws -> CodexModelUsageSummary {
    func listTasks(_ credential: Credential) async throws -> HTTPResult {
      try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/tasks?limit=50")!,
        headers: codexQuotaHeaders(credential),
        timeout: 20
      )
    }
    var taskResult = try await listTasks(credential)
    if taskResult.statusCode == 401, credential.refreshToken != nil {
      credential = try await refreshCodexCredential(credential, accountID: account.id)
      taskResult = try await listTasks(credential)
    }
    guard (200..<300).contains(taskResult.statusCode) else {
      throw UsageError.http(taskResult.statusCode, String(data: taskResult.data, encoding: .utf8) ?? "")
    }
    let taskRoot = try taskResult.jsonDictionary()
    let taskItems = (taskRoot["items"] as? [[String: Any]])
      ?? (taskRoot["data"] as? [[String: Any]])
      ?? []
    let threadIDs = taskItems.compactMap { string($0["thread_id"] ?? $0["threadId"] ?? $0["id"]) }
    guard !threadIDs.isEmpty else {
      throw UsageError.invalidResponse("No Codex cloud tasks returned")
    }

    var groups: [CodexModelUsageKey: CodexModelTokenUsage] = [:]
    var returnedThreadCount = 0
    var totalUSDMicros: Int64?
    for start in stride(from: 0, to: threadIDs.count, by: 20) {
      let ids = Array(threadIDs[start..<min(start + 20, threadIDs.count)])
      let body = try JSONSerialization.data(withJSONObject: ["thread_ids": ids])
      var headers = codexQuotaHeaders(credential)
      headers["Content-Type"] = "application/json"
      let result = try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/usage/thread_usage/query")!,
        method: "POST",
        headers: headers,
        body: body,
        timeout: 25
      )
      guard (200..<300).contains(result.statusCode) else {
        throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
      }
      let root = try result.jsonDictionary()
      let threads = (root["threads"] as? [[String: Any]]) ?? []
      returnedThreadCount += threads.count
      for thread in threads {
        if let usd = int64(thread["estimated_usage_usd_micros"] ?? thread["estimatedUsageUsdMicros"]) {
          totalUSDMicros = (totalUSDMicros ?? 0) + usd
        }
        let rawGroups = (thread["groups"] as? [[String: Any]]) ?? []
        for raw in rawGroups {
          let key = CodexModelUsageKey(
            model: string(raw["model"]) ?? "未知模型",
            reasoningEffort: string(raw["reasoning_effort"] ?? raw["reasoningEffort"]),
            speed: string(raw["speed"])
          )
          let input = int64(raw["input_tokens"] ?? raw["inputTokens"]) ?? 0
          let cached = int64(raw["cached_input_tokens"] ?? raw["cachedInputTokens"]) ?? 0
          let output = int64(raw["output_tokens"] ?? raw["outputTokens"]) ?? 0
          let total = int64(raw["total_tokens"] ?? raw["totalTokens"]) ?? (input + output)
          let credits = int64(raw["estimated_usage_credits_micros"] ?? raw["estimatedUsageCreditsMicros"]) ?? 0
          let current = groups[key] ?? CodexModelTokenUsage(
            model: key.model,
            reasoningEffort: key.reasoningEffort,
            speed: key.speed,
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
            estimatedUsageCreditsMicros: 0
          )
          groups[key] = CodexModelTokenUsage(
            model: current.model,
            reasoningEffort: current.reasoningEffort,
            speed: current.speed,
            inputTokens: current.inputTokens + input,
            cachedInputTokens: current.cachedInputTokens + cached,
            outputTokens: current.outputTokens + output,
            totalTokens: current.totalTokens + total,
            estimatedUsageCreditsMicros: current.estimatedUsageCreditsMicros + credits
          )
        }
      }
    }
    guard returnedThreadCount > 0 else {
      throw UsageError.invalidResponse("Codex did not return thread usage")
    }
    return CodexModelUsageSummary(
      groups: groups.values.sorted { $0.totalTokens > $1.totalTokens },
      returnedThreadCount: returnedThreadCount,
      estimatedUsageUSDMicros: totalUSDMicros,
      isPartial: string(taskRoot["cursor"] ?? taskRoot["next_cursor"] ?? taskRoot["nextCursor"]) != nil,
      fetchedAt: .now
    )
  }

  private func fetchCodexResetCreditPayload(
    account: AccountRecord,
    credential: inout Credential
  ) async throws -> CodexResetCreditPayload {
    func call(_ credential: Credential) async throws -> HTTPResult {
      try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
        headers: codexQuotaHeaders(credential),
        timeout: 20
      )
    }
    var result = try await call(credential)
    if result.statusCode == 401, credential.refreshToken != nil {
      credential = try await refreshCodexCredential(credential, accountID: account.id)
      result = try await call(credential)
    }
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    guard let payload = codexResetCreditPayload(from: root) else {
      throw UsageError.invalidResponse("Missing Codex reset credit data")
    }
    return payload
  }

  private func invalidateCodexResetCredits(accountID: UUID) async {
    guard var snapshot = await SharedStore.shared.snapshot(for: accountID) else { return }
    snapshot.codexResetCredits = nil
    await SharedStore.shared.saveSnapshot(snapshot)
  }

  private func codexQuotaHeaders(_ credential: Credential) -> [String: String] {
    var headers = [
      "Authorization": "Bearer \(credential.accessToken)",
      "Accept": "application/json",
      "Accept-Language": "zh-CN",
      "User-Agent": "codex-cli",
      "openai-beta": "codex-1",
      "originator": "Codex Desktop",
      "Sec-Fetch-Site": "none",
      "Sec-Fetch-Mode": "no-cors",
      "Sec-Fetch-Dest": "empty",
    ]
    if let accountID = credential.accountID, !accountID.isEmpty {
      headers["chatgpt-account-id"] = accountID
    }
    return headers
  }

  private func codexResetCreditPayload(from root: [String: Any]) -> CodexResetCreditPayload? {
    var containers: [[String: Any]] = []
    if let nested = dictionary(root["rate_limit_reset_credits"]) { containers.append(nested) }
    if let data = dictionary(root["data"]) {
      if let nested = dictionary(data["rate_limit_reset_credits"]) { containers.append(nested) }
      containers.append(data)
    }
    containers.append(root)

    var directRecords: [[String: Any]] = []
    if let records = root["rate_limit_reset_credits"] as? [[String: Any]] { directRecords = records }

    for container in containers {
      let records = (container["credits"] as? [[String: Any]])
        ?? (container["items"] as? [[String: Any]])
        ?? directRecords
      let explicitCount = number(container["available_count"] ?? container["availableCount"])
      guard explicitCount != nil || !records.isEmpty else { continue }

      let candidates = records.compactMap { item -> CodexResetCreditCandidate? in
        let id = string(item["id"] ?? item["credit_id"] ?? item["creditId"])
        guard let id else { return nil }
        let expiresAt = parseDate(item["expires_at"] ?? item["expiresAt"])
        return CodexResetCreditCandidate(id: id, expiresAt: expiresAt)
      }
      let expirations = records.compactMap {
        parseDate($0["expires_at"] ?? $0["expiresAt"])
      }
      let count = Int(explicitCount ?? Double(records.count))
      return CodexResetCreditPayload(
        summary: CodexResetCreditSummary(availableCount: count, expiresAt: expirations),
        candidates: candidates
      )
    }
    return nil
  }

  private func refreshCodexCredential(_ credential: Credential, accountID: UUID) async throws -> Credential {
    guard let refreshToken = credential.refreshToken else { throw UsageError.unauthorized }
    let body = formBody(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": credential.clientID ?? "app_EMoamEEZ73f0CkXaXp7hrann"])
    let result = try await http.send(URL(string: "https://auth.openai.com/oauth/token")!, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"], body: body)
    guard (200..<300).contains(result.statusCode) else { throw UsageError.refreshFailed("Codex HTTP \(result.statusCode)") }
    let json = try result.jsonDictionary()
    guard let access = string(json["access_token"]) else { throw UsageError.refreshFailed("Codex missing access_token") }
    var updated = credential; updated.accessToken = access; updated.refreshToken = string(json["refresh_token"]) ?? refreshToken; updated.idToken = string(json["id_token"]) ?? credential.idToken
    try keychain.saveCredential(updated, accountID: accountID); return updated
  }

  private func fetchClaude(account: AccountRecord, credential: inout Credential) async throws -> UsageSnapshot {
    if credential.authenticationMode == .apiKey {
      return try await fetchClaudeAPIKey(account: account, credential: credential)
    }
    if let expires = credential.expiresAt, expires.timeIntervalSinceNow < 60, credential.refreshToken != nil { credential = try await refreshClaudeCredential(credential, accountID: account.id) }
    func call(_ credential: Credential) async throws -> HTTPResult { try await http.send(URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: ["Authorization": "Bearer \(credential.accessToken)", "anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-cli", "Accept": "application/json"]) }
    var result = try await call(credential)
    if result.statusCode == 401, credential.refreshToken != nil { credential = try await refreshClaudeCredential(credential, accountID: account.id); result = try await call(credential) }
    guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }
    let root = try result.jsonDictionary(); var windows: [UsageWindow] = []
    if let five = dictionary(root["five_hour"]) { windows.append(UsageWindow(id: "claude-5h", label: "5h", remainingPercent: 100 - (number(five["utilization"]) ?? 0), resetAt: parseISODate(string(five["resets_at"])))) }
    if let seven = dictionary(root["seven_day"]) { windows.append(UsageWindow(id: "claude-week", label: "周", remainingPercent: 100 - (number(seven["utilization"]) ?? 0), resetAt: parseISODate(string(seven["resets_at"])))) }
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Claude quota windows") }
    return UsageSnapshot(accountID: account.id, provider: .claude, windows: windows, authenticationMode: .oauth)
  }

  private func fetchClaudeAPIKey(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let base = apiV1BaseURL(credential.baseURL, fallback: "https://api.anthropic.com")
    let result = try await http.send(
      URL(string: "\(base)/models")!,
      headers: [
        "x-api-key": credential.accessToken,
        "anthropic-version": "2023-06-01",
        "Accept": "application/json",
      ]
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    let models = availableModelIDs(root)
    let modelCount = models.count
    return UsageSnapshot(
      accountID: account.id,
      provider: .claude,
      metrics: [
        UsageMetric(label: "认证", value: "API Key"),
        UsageMetric(label: "可用模型", value: "\(modelCount)"),
      ],
      availableModels: models,
      authenticationMode: .apiKey,
      plan: "Anthropic API"
    )
  }

  private func refreshClaudeCredential(_ credential: Credential, accountID: UUID) async throws -> Credential {
    guard let refreshToken = credential.refreshToken else { throw UsageError.unauthorized }
    let body = try JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": credential.clientID ?? "9d1c250a-e61b-44d9-88ed-5944d1962f5e"])
    let result = try await http.send(URL(string: "https://platform.claude.com/v1/oauth/token")!, method: "POST", headers: ["Content-Type": "application/json", "Accept": "application/json"], body: body)
    guard (200..<300).contains(result.statusCode) else { throw UsageError.refreshFailed("Claude HTTP \(result.statusCode)") }
    let json = try result.jsonDictionary(); guard let access = string(json["access_token"]) else { throw UsageError.refreshFailed("Claude missing access_token") }
    var updated = credential; updated.accessToken = access; updated.refreshToken = string(json["refresh_token"]) ?? refreshToken; if let seconds = number(json["expires_in"]) { updated.expiresAt = Date().addingTimeInterval(seconds) }; try keychain.saveCredential(updated, accountID: accountID); return updated
  }

  private func fetchKimi(account: AccountRecord, credential: inout Credential) async throws -> UsageSnapshot {
    if credential.authenticationMode == .apiKey {
      return try await fetchKimiAPIKey(account: account, credential: credential)
    }
    if let expires = credential.expiresAt, expires.timeIntervalSinceNow < 60, credential.refreshToken != nil { credential = try await refreshKimiCredential(credential, accountID: account.id) }
    func call(_ credential: Credential) async throws -> HTTPResult { var headers = ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]; credential.deviceHeaders?.forEach { headers[$0.key] = $0.value }; return try await http.send(URL(string: "https://api.kimi.com/coding/v1/usages")!, headers: headers) }
    var result = try await call(credential)
    if [401, 403].contains(result.statusCode), credential.refreshToken != nil { credential = try await refreshKimiCredential(credential, accountID: account.id); result = try await call(credential) }
    guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }
    let root = try result.jsonDictionary(); var windows: [UsageWindow] = []
    if let limits = root["limits"] as? [[String: Any]] { for (index, entry) in limits.enumerated() { let window = dictionary(entry["window"]) ?? entry; let detail = dictionary(entry["detail"]) ?? entry; if let parsed = parseKimiDetail(detail, duration: kimiDurationSeconds(window), id: "kimi-\(index)") { windows.append(parsed) } } }
    if let usage = dictionary(root["usage"]), !windows.contains(where: { $0.label == "周" }), let weekly = parseKimiDetail(usage, duration: 604_800, id: "kimi-week-summary") { windows.append(weekly) }
    windows = uniqueWindows(windows); guard !windows.isEmpty else { throw UsageError.invalidResponse("No Kimi quota windows") }; return UsageSnapshot(accountID: account.id, provider: .kimi, windows: windows, authenticationMode: .oauth)
  }

  private func fetchKimiAPIKey(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let base = apiV1BaseURL(credential.baseURL, fallback: "https://api.moonshot.cn")
    let result = try await http.send(
      URL(string: "\(base)/models")!,
      headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    let models = availableModelIDs(root)
    let modelCount = models.count
    let balanceResult = try? await http.send(
      URL(string: "\(base)/users/me/balance")!,
      headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]
    )
    let balance: BalanceSnapshot?
    if let balanceResult,
      (200..<300).contains(balanceResult.statusCode),
      let root = try? balanceResult.jsonDictionary(),
      let data = dictionary(root["data"]),
      let available = number(data["available_balance"] ?? data["availableBalance"]) {
      balance = BalanceSnapshot(
        currency: "CNY",
        symbol: "¥",
        total: available,
        granted: number(data["voucher_balance"] ?? data["voucherBalance"]) ?? 0,
        toppedUp: number(data["cash_balance"] ?? data["cashBalance"]) ?? 0,
        available: true
      )
    } else {
      balance = nil
    }
    return UsageSnapshot(
      accountID: account.id,
      provider: .kimi,
      metrics: [
        UsageMetric(label: "认证", value: "API Key"),
        UsageMetric(label: "可用模型", value: "\(modelCount)"),
      ],
      availableModels: models,
      balance: balance,
      authenticationMode: .apiKey,
      plan: "Kimi API"
    )
  }

  private func refreshKimiCredential(_ credential: Credential, accountID: UUID) async throws -> Credential {
    guard let refreshToken = credential.refreshToken else { throw UsageError.unauthorized }
    let body = formBody(["client_id": credential.clientID ?? "17e5f671-d194-4dfb-9706-5516cb48c098", "grant_type": "refresh_token", "refresh_token": refreshToken]); var headers = ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"]; credential.deviceHeaders?.forEach { headers[$0.key] = $0.value }
    let result = try await http.send(URL(string: "https://auth.kimi.com/api/oauth/token")!, method: "POST", headers: headers, body: body); guard (200..<300).contains(result.statusCode) else { throw UsageError.refreshFailed("Kimi HTTP \(result.statusCode)") }; let json = try result.jsonDictionary(); guard let access = string(json["access_token"]) else { throw UsageError.refreshFailed("Kimi missing access_token") }; var updated = credential; updated.accessToken = access; updated.refreshToken = string(json["refresh_token"]) ?? refreshToken; if let seconds = number(json["expires_in"]) { updated.expiresAt = Date().addingTimeInterval(seconds) }; try keychain.saveCredential(updated, accountID: accountID); return updated
  }

  private func fetchDeepSeek(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let result = try await http.send(URL(string: "https://api.deepseek.com/user/balance")!, headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]); guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }; let root = try result.jsonDictionary(); guard let infos = root["balance_infos"] as? [[String: Any]], !infos.isEmpty else { throw UsageError.invalidResponse("No balance_infos") }; let preferred = infos.first(where: { string($0["currency"]) == "CNY" }) ?? infos.first(where: { string($0["currency"]) == "USD" }) ?? infos[0]; let currency = string(preferred["currency"]) ?? ""; let symbol = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : "\(currency) "); let balance = BalanceSnapshot(currency: currency, symbol: symbol, total: number(preferred["total_balance"]) ?? 0, granted: number(preferred["granted_balance"]) ?? 0, toppedUp: number(preferred["topped_up_balance"]) ?? 0, available: bool(root["is_available"]) ?? true); return UsageSnapshot(accountID: account.id, provider: .deepseek, balance: balance)
  }

  private func fetchMiniMax(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let base = normalizedBaseURL(credential.baseURL, fallback: "https://api.minimax.io"); let result = try await http.send(URL(string: "\(base)/v1/api/openplatform/coding_plan/remains")!, headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json", "Content-Type": "application/json"]); guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }; let root = try result.jsonDictionary(); let data = dictionary(root["data"]) ?? root; let current = number(data["currentUsage"] ?? data["current_usage"] ?? data["used"]); let total = number(data["totalUsage"] ?? data["total_usage"] ?? data["limit"]); if let current, let total, total > 0 { return UsageSnapshot(accountID: account.id, provider: .minimax, windows: [UsageWindow(id: "minimax-plan", label: "计划", remainingPercent: ((total-current)/total)*100)], metrics: [UsageMetric(label: "已用", value: formatNumber(current)), UsageMetric(label: "总量", value: formatNumber(total))]) }; return UsageSnapshot(accountID: account.id, provider: .minimax, metrics: [UsageMetric(label: "状态", value: "已连接")])
  }

  private func fetchGLM(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let base = normalizedBaseURL(credential.baseURL, fallback: "https://open.bigmodel.cn"); var lastFailure = ""; for endpoint in ["\(base)/api/monitor/usage/quota/limit", "\(base)/api/paas/v4/usage/quota"] { guard let url = URL(string: endpoint) else { continue }; let result = try await http.send(url, headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]); guard (200..<300).contains(result.statusCode) else { lastFailure = "HTTP \(result.statusCode)"; continue }; let root = try result.jsonDictionary(); let data = dictionary(root["data"]) ?? dictionary(root["result"]) ?? root; if let percentage = number(data["remainingPercent"] ?? data["remaining_percent"] ?? data["percentage"]) { return UsageSnapshot(accountID: account.id, provider: .glm, windows: [UsageWindow(id: "glm-plan", label: "计划", remainingPercent: percentage)]) }; let metrics = numericMetrics(data, keys: ["usage", "used", "limit", "quota", "remaining", "balance"]); if !metrics.isEmpty { return UsageSnapshot(accountID: account.id, provider: .glm, metrics: metrics) } }; throw UsageError.invalidResponse("GLM usage unavailable \(lastFailure)")
  }

  private func fetchCopilot(account: AccountRecord, credential: Credential) async throws -> UsageSnapshot {
    let result = try await http.send(URL(string: "https://api.github.com/copilot_internal/user")!, headers: ["Authorization": "token \(credential.accessToken)", "Accept": "application/json", "Editor-Version": "vscode/1.96.0", "Editor-Plugin-Version": "copilot-chat/0.23.2", "User-Agent": "GitHubCopilotChat/0.23.2"]); guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }; let root = try result.jsonDictionary(); var windows: [UsageWindow] = []; var metrics: [UsageMetric] = []; if let snapshots = dictionary(root["quota_snapshots"]) { for (key, raw) in snapshots { guard let item = dictionary(raw) else { continue }; if let percent = number(item["percent_remaining"]) { windows.append(UsageWindow(id: "copilot-\(key)", label: displayLabel(key), remainingPercent: percent)) } else if let remaining = number(item["remaining"]), let entitlement = number(item["entitlement"]), entitlement > 0 { windows.append(UsageWindow(id: "copilot-\(key)", label: displayLabel(key), remainingPercent: (remaining/entitlement)*100)); metrics.append(UsageMetric(label: displayLabel(key), value: "\(formatNumber(remaining))/\(formatNumber(entitlement))")) } } }; if windows.isEmpty { metrics.append(contentsOf: numericMetrics(root, keys: ["quota", "remaining", "usage", "limit"])) }; return UsageSnapshot(accountID: account.id, provider: .copilot, windows: windows, metrics: metrics)
  }

  private func uniqueWindows(_ windows: [UsageWindow]) -> [UsageWindow] { var labels = Set<String>(); return windows.filter { labels.insert($0.label).inserted } }
  private func durationLabel(seconds: Int64) -> String { switch seconds { case 1...21_600: return "\(max(1, seconds / 3600))h"; case 21_601...691_200: return seconds >= 518_400 ? "周" : "\(max(1, seconds / 86_400))d"; default: return "额度" } }
  private func kimiDurationSeconds(_ value: [String: Any]) -> Int64 { let duration = int64(value["duration"]) ?? 0; let unit = (string(value["timeUnit"] ?? value["time_unit"]) ?? "").uppercased().replacingOccurrences(of: "TIME_UNIT_", with: ""); if unit.hasPrefix("SECOND") { return duration }; if unit.hasPrefix("MINUTE") { return duration*60 }; if unit.hasPrefix("HOUR") { return duration*3600 }; if unit.hasPrefix("DAY") { return duration*86_400 }; return 0 }
  private func parseKimiDetail(_ value: [String: Any], duration: Int64, id: String) -> UsageWindow? { guard let limit = number(value["limit"]), limit > 0 else { return nil }; let used = number(value["used"]) ?? (limit - (number(value["remaining"]) ?? limit)); var resetAt: Date?; for key in ["resetAt", "reset_at", "resetTime", "reset_time"] { if let parsed = flexibleDate(value[key]) { resetAt = parsed; break } }; if resetAt == nil { for key in ["resetIn", "reset_in", "ttl"] { if let seconds = int64(value[key]), seconds >= 0 { resetAt = Date().addingTimeInterval(TimeInterval(seconds)); break } } }; return UsageWindow(id: id, label: durationLabel(seconds: duration), remainingPercent: ((limit-used)/limit)*100, resetAt: resetAt) }
  private func numericMetrics(_ value: [String: Any], keys: [String]) -> [UsageMetric] { keys.compactMap { key in guard let value = number(value[key]) else { return nil }; return UsageMetric(label: displayLabel(key), value: formatNumber(value)) } }
  private func availableModelIDs(_ root: [String: Any]) -> [String] { ((root["data"] as? [[String: Any]]) ?? []).compactMap { string($0["id"] ?? $0["name"]) }.sorted() }
  private func normalizedBaseURL(_ value: String?, fallback: String) -> String { (value?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).flatMap { $0.isEmpty ? nil : $0 } ?? fallback }
  private func apiV1BaseURL(_ value: String?, fallback: String) -> String { let base=normalizedBaseURL(value,fallback:fallback);return base.lowercased().hasSuffix("/v1") ? base:"\(base)/v1" }
  private func formBody(_ values: [String: String]) -> Data { values.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.sorted().joined(separator: "&").data(using: .utf8) ?? Data() }
  private func urlEncode(_ value: String) -> String { var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "+&="); return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
  private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
  private func string(_ value: Any?) -> String? { if let string = value as? String, !string.isEmpty { return string }; return nil }
  private func number(_ value: Any?) -> Double? { if let number = value as? NSNumber { return number.doubleValue }; if let string = value as? String { return Double(string) }; return nil }
  private func int64(_ value: Any?) -> Int64? { if let number = value as? NSNumber { return number.int64Value }; if let string = value as? String { return Int64(string) }; return nil }
  private func bool(_ value: Any?) -> Bool? { if let bool = value as? Bool { return bool }; if let number = value as? NSNumber { return number.boolValue }; return nil }
  private func parseISODate(_ value: String?) -> Date? { guard let value else { return nil }; return ISO8601DateFormatter().date(from: value) }
  private func parseCodexDay(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }
  private func flexibleDate(_ value: Any?) -> Date? { if let n = value as? NSNumber { let raw = n.doubleValue; return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw/1000 : raw) }; if let string = value as? String { return parseISODate(string) }; return nil }
  private func formatNumber(_ value: Double) -> String { if value.rounded() == value { return String(Int(value)) }; return String(format: "%.2f", value) }
  private func displayLabel(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
}
