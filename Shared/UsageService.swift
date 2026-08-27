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

  @discardableResult
  func refresh(accountID: UUID) async throws -> UsageSnapshot {
    guard let account = await SharedStore.shared.account(id: accountID) else {
      throw UsageError.missingAccount
    }
    do {
      let snapshot = try await fetch(account: account)
      await SharedStore.shared.saveSnapshot(snapshot)
      return snapshot
    } catch {
      if await SharedStore.shared.snapshot(for: accountID) == nil {
        await SharedStore.shared.saveSnapshot(
          UsageSnapshot(
            accountID: account.id,
            provider: account.provider,
            errorMessage: error.localizedDescription,
            stale: true
          )
        )
      } else {
        await SharedStore.shared.markSnapshotStale(
          accountID: accountID, message: error.localizedDescription)
      }
      throw error
    }
  }

  func refresh(accountIDs: [UUID]) async -> [UsageSnapshot] {
    await withTaskGroup(of: UsageSnapshot?.self) { group in
      for id in accountIDs {
        group.addTask {
          try? await UsageService.shared.refresh(accountID: id)
        }
      }
      var snapshots: [UsageSnapshot] = []
      for await value in group {
        if let value { snapshots.append(value) }
      }
      return snapshots
    }
  }

  func refreshVisible(limit: Int? = nil) async -> [UsageSnapshot] {
    let accounts = await SharedStore.shared.displayAccounts(limit: limit)
    return await refresh(accountIDs: accounts.map(\.id))
  }

  private func fetch(account: AccountRecord) async throws -> UsageSnapshot {
    guard var credential = try keychain.credential(accountID: account.id) else {
      throw UsageError.missingCredential
    }
    switch account.provider {
    case .codex:
      return try await fetchCodex(account: account, credential: &credential)
    case .claude:
      return try await fetchClaude(account: account, credential: &credential)
    case .kimi:
      return try await fetchKimi(account: account, credential: &credential)
    case .deepseek:
      return try await fetchDeepSeek(account: account, credential: credential)
    case .minimax:
      return try await fetchMiniMax(account: account, credential: credential)
    case .glm:
      return try await fetchGLM(account: account, credential: credential)
    case .copilot:
      return try await fetchCopilot(account: account, credential: credential)
    }
  }

  // MARK: Codex

  private func fetchCodex(account: AccountRecord, credential: inout Credential) async throws
    -> UsageSnapshot
  {
    func call(_ credential: Credential) async throws -> HTTPResult {
      var headers = [
        "Authorization": "Bearer \(credential.accessToken)",
        "User-Agent": "codex-cli",
        "Accept": "application/json",
      ]
      if let accountID = credential.accountID, !accountID.isEmpty {
        headers["chatgpt-account-id"] = accountID
      }
      return try await http.send(
        URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        headers: headers
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
    guard let rateLimit = dictionary(root["rate_limit"]) else {
      throw UsageError.invalidResponse("Missing rate_limit")
    }

    var windows: [UsageWindow] = []
    for (key, value) in rateLimit where key.hasSuffix("_window") {
      guard let raw = dictionary(value), let used = number(raw["used_percent"]) else { continue }
      let duration = number(raw["limit_window_seconds"])
      let resetAt: Date?
      if let epoch = number(raw["reset_at"]), epoch > 0 {
        resetAt = Date(timeIntervalSince1970: epoch)
      } else if let after = number(raw["reset_after_seconds"]), after >= 0 {
        resetAt = Date().addingTimeInterval(after)
      } else {
        resetAt = nil
      }
      windows.append(
        UsageWindow(
          id: "codex-\(key)",
          label: durationLabel(seconds: duration),
          remainingPercent: 100 - used,
          resetAt: resetAt
        )
      )
    }
    windows = dedupe(windows)
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Codex quota windows") }
    return UsageSnapshot(accountID: account.id, provider: .codex, windows: windows)
  }

  private func refreshCodexCredential(_ credential: Credential, accountID: UUID) async throws
    -> Credential
  {
    guard let refresh = credential.refreshToken, !refresh.isEmpty else {
      throw UsageError.refreshFailed("Missing refresh token")
    }
    let result = try await http.send(
      URL(string: "https://auth.openai.com/oauth/token")!,
      method: "POST",
      headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
      body: formURLEncoded([
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": credential.clientID ?? AppConfig.codexClientID,
      ])
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.refreshFailed(
        String(data: result.data, encoding: .utf8) ?? "HTTP \(result.statusCode)")
    }
    let json = try result.jsonDictionary()
    guard let access = json["access_token"] as? String else {
      throw UsageError.refreshFailed("No access_token")
    }
    var updated = credential
    updated.accessToken = access
    updated.refreshToken = (json["refresh_token"] as? String) ?? refresh
    if let idToken = json["id_token"] as? String { updated.idToken = idToken }
    try keychain.saveCredential(updated, accountID: accountID)
    return updated
  }

  // MARK: Claude

  private func fetchClaude(account: AccountRecord, credential: inout Credential) async throws
    -> UsageSnapshot
  {
    if let expiry = credential.expiresAt, expiry.timeIntervalSinceNow < 60,
      credential.refreshToken != nil
    {
      credential = try await refreshClaudeCredential(credential, accountID: account.id)
    }
    func call(_ credential: Credential) async throws -> HTTPResult {
      try await http.send(
        URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        headers: [
          "Authorization": "Bearer \(credential.accessToken)",
          "anthropic-beta": "oauth-2025-04-20",
          "User-Agent": "claude-cli",
          "Accept": "application/json",
        ]
      )
    }
    var result = try await call(credential)
    if result.statusCode == 401, credential.refreshToken != nil {
      credential = try await refreshClaudeCredential(credential, accountID: account.id)
      result = try await call(credential)
    }
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    var windows: [UsageWindow] = []
    if let five = dictionary(root["five_hour"]), let used = number(five["utilization"]) {
      windows.append(
        UsageWindow(
          id: "claude-5h",
          label: "5h",
          remainingPercent: 100 - used,
          resetAt: parseDate(five["resets_at"])
        ))
    }
    if let week = dictionary(root["seven_day"]), let used = number(week["utilization"]) {
      windows.append(
        UsageWindow(
          id: "claude-week",
          label: "周",
          remainingPercent: 100 - used,
          resetAt: parseDate(week["resets_at"])
        ))
    }
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Claude quota windows") }
    return UsageSnapshot(accountID: account.id, provider: .claude, windows: windows)
  }

  private func refreshClaudeCredential(_ credential: Credential, accountID: UUID) async throws
    -> Credential
  {
    guard let refresh = credential.refreshToken, !refresh.isEmpty else {
      throw UsageError.refreshFailed("Missing refresh token")
    }
    let body = try JSONSerialization.data(withJSONObject: [
      "grant_type": "refresh_token",
      "refresh_token": refresh,
      "client_id": credential.clientID ?? AppConfig.claudeClientID,
    ])
    let result = try await http.send(
      URL(string: "https://platform.claude.com/v1/oauth/token")!,
      method: "POST",
      headers: ["Content-Type": "application/json", "Accept": "application/json"],
      body: body
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.refreshFailed(
        String(data: result.data, encoding: .utf8) ?? "HTTP \(result.statusCode)")
    }
    let json = try result.jsonDictionary()
    guard let access = json["access_token"] as? String else {
      throw UsageError.refreshFailed("No access_token")
    }
    var updated = credential
    updated.accessToken = access
    updated.refreshToken = (json["refresh_token"] as? String) ?? refresh
    if let expires = number(json["expires_in"]) {
      updated.expiresAt = Date().addingTimeInterval(expires)
    }
    try keychain.saveCredential(updated, accountID: accountID)
    return updated
  }

  // MARK: Kimi

  private func fetchKimi(account: AccountRecord, credential: inout Credential) async throws
    -> UsageSnapshot
  {
    if let expiry = credential.expiresAt, expiry.timeIntervalSinceNow < 60,
      credential.refreshToken != nil
    {
      credential = try await refreshKimiCredential(credential, accountID: account.id)
    }
    func call(_ credential: Credential) async throws -> HTTPResult {
      try await http.send(
        URL(string: "https://api.kimi.com/coding/v1/usages")!,
        headers: [
          "Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json",
        ]
      )
    }
    var result = try await call(credential)
    if [401, 403].contains(result.statusCode), credential.refreshToken != nil {
      credential = try await refreshKimiCredential(credential, accountID: account.id)
      result = try await call(credential)
    }
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    var windows: [UsageWindow] = []

    if let limits = root["limits"] as? [Any] {
      for (index, item) in limits.enumerated() {
        guard let entry = item as? [String: Any] else { continue }
        let window = dictionary(entry["window"]) ?? entry
        let detail = dictionary(entry["detail"]) ?? entry
        let duration = kimiDurationSeconds(window)
        if let parsed = parseKimiDetail(detail, duration: duration, id: "kimi-\(index)") {
          windows.append(parsed)
        }
      }
    }
    if let usage = dictionary(root["usage"]),
      let weekly = parseKimiDetail(usage, duration: 604_800, id: "kimi-week-summary"),
      !windows.contains(where: { $0.label == "周" })
    {
      windows.append(weekly)
    }
    windows = dedupe(windows)
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Kimi quota windows") }
    return UsageSnapshot(accountID: account.id, provider: .kimi, windows: windows)
  }

  private func refreshKimiCredential(_ credential: Credential, accountID: UUID) async throws
    -> Credential
  {
    guard let refresh = credential.refreshToken, !refresh.isEmpty else {
      throw UsageError.refreshFailed("Missing refresh token")
    }
    var headers = credential.deviceHeaders ?? [:]
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    headers["Accept"] = "application/json"
    let result = try await http.send(
      URL(string: "https://auth.kimi.com/api/oauth/token")!,
      method: "POST",
      headers: headers,
      body: formURLEncoded([
        "client_id": credential.clientID ?? AppConfig.kimiClientID,
        "grant_type": "refresh_token",
        "refresh_token": refresh,
      ])
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.refreshFailed(
        String(data: result.data, encoding: .utf8) ?? "HTTP \(result.statusCode)")
    }
    let json = try result.jsonDictionary()
    guard let access = json["access_token"] as? String else {
      throw UsageError.refreshFailed("No access_token")
    }
    var updated = credential
    updated.accessToken = access
    updated.refreshToken = (json["refresh_token"] as? String) ?? refresh
    if let expires = number(json["expires_in"]) {
      updated.expiresAt = Date().addingTimeInterval(expires)
    }
    try keychain.saveCredential(updated, accountID: accountID)
    return updated
  }

  private func kimiDurationSeconds(_ window: [String: Any]) -> Double {
    guard let duration = number(window["duration"]), duration > 0 else { return 0 }
    let raw = String(describing: window["timeUnit"] ?? window["time_unit"] ?? "").uppercased()
    let unit = raw.replacingOccurrences(of: "TIME_UNIT_", with: "")
    if unit.hasPrefix("SECOND") { return duration }
    if unit.hasPrefix("MINUTE") { return duration * 60 }
    if unit.hasPrefix("HOUR") { return duration * 3_600 }
    if unit.hasPrefix("DAY") { return duration * 86_400 }
    return 0
  }

  private func parseKimiDetail(_ detail: [String: Any], duration: Double, id: String)
    -> UsageWindow?
  {
    guard let limit = number(detail["limit"]), limit > 0 else { return nil }
    var used = number(detail["used"])
    let remaining = number(detail["remaining"])
    if used == nil, let remaining { used = limit - remaining }
    guard let used, used >= 0 else { return nil }

    var resetAt: Date?
    for key in ["resetAt", "reset_at", "resetTime", "reset_time"] {
      if let date = parseDate(detail[key]) {
        resetAt = date
        break
      }
    }
    if resetAt == nil {
      for key in ["resetIn", "reset_in", "ttl"] {
        if let seconds = number(detail[key]), seconds >= 0 {
          resetAt = Date().addingTimeInterval(seconds)
          break
        }
      }
    }
    return UsageWindow(
      id: id,
      label: durationLabel(seconds: duration),
      remainingPercent: ((limit - used) / limit) * 100,
      resetAt: resetAt
    )
  }

  // MARK: API-key providers

  private func fetchDeepSeek(account: AccountRecord, credential: Credential) async throws
    -> UsageSnapshot
  {
    let result = try await http.send(
      URL(string: "https://api.deepseek.com/user/balance")!,
      headers: ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    guard let rawInfos = root["balance_infos"] as? [Any], !rawInfos.isEmpty else {
      throw UsageError.invalidResponse("No balance_infos")
    }
    let infos = rawInfos.compactMap { $0 as? [String: Any] }
    guard
      let info = infos.first(where: { ($0["currency"] as? String) == "CNY" })
        ?? infos.first(where: { ($0["currency"] as? String) == "USD" })
        ?? infos.first,
      let total = number(info["total_balance"])
    else { throw UsageError.invalidResponse("Unknown balance format") }
    let currency = (info["currency"] as? String) ?? ""
    let symbol = currency == "CNY" ? "¥" : currency == "USD" ? "$" : currency + " "
    let balance = BalanceSnapshot(
      currency: currency,
      symbol: symbol,
      total: total,
      granted: number(info["granted_balance"]) ?? 0,
      toppedUp: number(info["topped_up_balance"]) ?? 0,
      available: boolValue(root["is_available"]) != false
    )
    return UsageSnapshot(accountID: account.id, provider: .deepseek, balance: balance)
  }

  private func fetchMiniMax(account: AccountRecord, credential: Credential) async throws
    -> UsageSnapshot
  {
    let base = normalizedBaseURL(credential.baseURL, fallback: "https://api.minimax.io")
    let url = URL(string: "\(base)/v1/api/openplatform/coding_plan/remains")!
    let result = try await http.send(
      url, headers: ["Authorization": "Bearer \(credential.accessToken)"])
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    if let baseResp = dictionary(root["base_resp"]), let status = number(baseResp["status_code"]),
      status != 0
    {
      throw UsageError.invalidResponse("MiniMax status \(Int(status))")
    }
    guard let rows = root["model_remains"] as? [Any] else {
      throw UsageError.invalidResponse("Missing model_remains")
    }

    struct Candidate {
      var name: String
      var short: UsageWindow?
      var weekly: UsageWindow?
      var highestConsumed: Double
      var totalCapacity: Double
    }

    var candidates: [Candidate] = []
    for value in rows {
      guard let row = value as? [String: Any] else { continue }
      let short = miniMaxWindow(row: row, weekly: false)
      let weekly = miniMaxWindow(row: row, weekly: true)
      guard short.window != nil || weekly.window != nil else { continue }
      candidates.append(
        Candidate(
          name: (row["model_name"] as? String) ?? "",
          short: short.window,
          weekly: weekly.window,
          highestConsumed: max(short.consumed, weekly.consumed),
          totalCapacity: short.total + weekly.total
        ))
    }
    candidates.sort {
      if $0.highestConsumed != $1.highestConsumed { return $0.highestConsumed > $1.highestConsumed }
      return $0.totalCapacity > $1.totalCapacity
    }
    guard let chosen = candidates.first else {
      throw UsageError.invalidResponse("No MiniMax quota windows")
    }
    let windows = [chosen.short, chosen.weekly].compactMap { $0 }
    return UsageSnapshot(
      accountID: account.id, provider: .minimax, windows: windows, plan: chosen.name)
  }

  private func miniMaxWindow(row: [String: Any], weekly: Bool) -> (
    window: UsageWindow?, consumed: Double, total: Double
  ) {
    let totalKey = weekly ? "current_weekly_total_count" : "current_interval_total_count"
    let remainingKey = weekly ? "current_weekly_usage_count" : "current_interval_usage_count"
    let resetKey = weekly ? "weekly_end_time" : "end_time"
    guard let total = number(row[totalKey]), total > 0,
      let remaining = number(row[remainingKey]),
      let reset = parseDate(row[resetKey])
    else { return (nil, 0, 0) }
    let clamped = min(total, max(0, remaining))
    let remain = clamped / total * 100
    return (
      UsageWindow(
        id: weekly ? "minimax-week" : "minimax-5h",
        label: weekly ? "周" : "5h",
        remainingPercent: remain,
        resetAt: reset
      ),
      1 - remain / 100,
      total
    )
  }

  private func fetchGLM(account: AccountRecord, credential: Credential) async throws
    -> UsageSnapshot
  {
    let base = normalizedBaseURL(credential.baseURL, fallback: "https://api.z.ai")
    let url = URL(string: "\(base)/api/monitor/usage/quota/limit")!
    let result = try await http.send(url, headers: ["Authorization": credential.accessToken])
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    if [401, 403].contains(Int(number(root["code"]) ?? 0)) { throw UsageError.unauthorized }
    guard boolValue(root["success"]) != false,
      let data = dictionary(root["data"]),
      let rawLimits = data["limits"] as? [Any]
    else { throw UsageError.invalidResponse("Missing GLM limits") }
    var windows: [UsageWindow] = []
    for (index, raw) in rawLimits.enumerated() {
      guard let limit = raw as? [String: Any], (limit["type"] as? String) == "TOKENS_LIMIT" else {
        continue
      }
      let unit = number(limit["unit"])
      let count = number(limit["number"])
      let label: String
      if unit == 3, count == 5 {
        label = "5h"
      } else if unit == 6, count == 1 {
        label = "周"
      } else {
        continue
      }
      guard let used = number(limit["percentage"]), (0...100).contains(used) else { continue }
      windows.append(
        UsageWindow(
          id: "glm-\(index)",
          label: label,
          remainingPercent: 100 - used,
          resetAt: parseDate(limit["nextResetTime"] ?? limit["next_reset_time"])
        ))
    }
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No GLM quota windows") }
    return UsageSnapshot(
      accountID: account.id,
      provider: .glm,
      windows: windows,
      plan: data["level"] as? String
    )
  }

  private func fetchCopilot(account: AccountRecord, credential: Credential) async throws
    -> UsageSnapshot
  {
    let result = try await http.send(
      URL(string: "https://api.github.com/copilot_internal/user")!,
      headers: [
        "Authorization": "token \(credential.accessToken)",
        "Accept": "application/json",
        "Editor-Version": "vscode/1.96.2",
        "X-GitHub-Api-Version": "2025-04-01",
      ]
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    let resetAt = parseDate(
      root["quota_reset_date_utc"] ?? root["quota_reset_date"] ?? root["limited_user_reset_date"])
    guard let quotas = dictionary(root["quota_snapshots"]) else {
      throw UsageError.invalidResponse("Missing quota_snapshots")
    }
    var windows: [UsageWindow] = []
    var unlimited: [String] = []
    for (key, raw) in quotas {
      guard let quota = dictionary(raw) else { continue }
      if boolValue(quota["unlimited"]) == true {
        unlimited.append(copilotLabel(key))
        continue
      }
      guard let entitlement = number(quota["entitlement"]), entitlement > 0,
        let remaining = number(quota["remaining"])
      else { continue }
      let clamped = min(entitlement, max(0, remaining))
      windows.append(
        UsageWindow(
          id: "copilot-\(key)",
          label: copilotLabel(key),
          remainingPercent: clamped / entitlement * 100,
          resetAt: resetAt,
          detail: "\(Int(clamped.rounded()))/\(Int(entitlement.rounded()))"
        ))
    }
    let plan = (root["copilot_plan"] as? String) ?? (root["plan"] as? String)
    if windows.isEmpty, !unlimited.isEmpty {
      return UsageSnapshot(
        accountID: account.id,
        provider: .copilot,
        metrics: [
          UsageMetric(label: "额度", value: "无限"),
          UsageMetric(label: "套餐", value: plan ?? "Copilot"),
        ],
        plan: plan
      )
    }
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Copilot quota snapshots") }
    return UsageSnapshot(accountID: account.id, provider: .copilot, windows: windows, plan: plan)
  }

  // MARK: Helpers

  private func dedupe(_ windows: [UsageWindow]) -> [UsageWindow] {
    var seen = Set<String>()
    return windows.filter { window in
      let key = "\(window.label):\(Int(window.resetAt?.timeIntervalSince1970 ?? 0) / 60)"
      return seen.insert(key).inserted
    }
  }

  private func normalizedBaseURL(_ raw: String?, fallback: String) -> String {
    var value = (raw?.isEmpty == false ? raw! : fallback).trimmingCharacters(
      in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    for suffix in ["/api/anthropic", "/api/coding/paas/v4", "/api/paas/v4"]
    where value.hasSuffix(suffix) {
      value.removeLast(suffix.count)
    }
    return value
  }

  private func copilotLabel(_ key: String) -> String {
    switch key {
    case "premium_interactions": "Premium"
    case "chat": "Chat"
    case "completions": "补全"
    case "code_review": "Review"
    default: key.replacingOccurrences(of: "_", with: " ")
    }
  }
}
