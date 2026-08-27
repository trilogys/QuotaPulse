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
    func call(_ credential: Credential) async throws -> HTTPResult {
      var headers = ["Authorization": "Bearer \(credential.accessToken)", "User-Agent": "codex-cli", "Accept": "application/json"]
      if let accountID = credential.accountID, !accountID.isEmpty { headers["chatgpt-account-id"] = accountID }
      return try await http.send(URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: headers)
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
    return UsageSnapshot(accountID: account.id, provider: .codex, windows: windows)
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
    if let expires = credential.expiresAt, expires.timeIntervalSinceNow < 60, credential.refreshToken != nil { credential = try await refreshClaudeCredential(credential, accountID: account.id) }
    func call(_ credential: Credential) async throws -> HTTPResult { try await http.send(URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: ["Authorization": "Bearer \(credential.accessToken)", "anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-cli", "Accept": "application/json"]) }
    var result = try await call(credential)
    if result.statusCode == 401, credential.refreshToken != nil { credential = try await refreshClaudeCredential(credential, accountID: account.id); result = try await call(credential) }
    guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }
    let root = try result.jsonDictionary(); var windows: [UsageWindow] = []
    if let five = dictionary(root["five_hour"]) { windows.append(UsageWindow(id: "claude-5h", label: "5h", remainingPercent: 100 - (number(five["utilization"]) ?? 0), resetAt: parseISODate(string(five["resets_at"])))) }
    if let seven = dictionary(root["seven_day"]) { windows.append(UsageWindow(id: "claude-week", label: "周", remainingPercent: 100 - (number(seven["utilization"]) ?? 0), resetAt: parseISODate(string(seven["resets_at"])))) }
    guard !windows.isEmpty else { throw UsageError.invalidResponse("No Claude quota windows") }
    return UsageSnapshot(accountID: account.id, provider: .claude, windows: windows)
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
    if let expires = credential.expiresAt, expires.timeIntervalSinceNow < 60, credential.refreshToken != nil { credential = try await refreshKimiCredential(credential, accountID: account.id) }
    func call(_ credential: Credential) async throws -> HTTPResult { var headers = ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json"]; credential.deviceHeaders?.forEach { headers[$0.key] = $0.value }; return try await http.send(URL(string: "https://api.kimi.com/coding/v1/usages")!, headers: headers) }
    var result = try await call(credential)
    if [401, 403].contains(result.statusCode), credential.refreshToken != nil { credential = try await refreshKimiCredential(credential, accountID: account.id); result = try await call(credential) }
    guard (200..<300).contains(result.statusCode) else { throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "") }
    let root = try result.jsonDictionary(); var windows: [UsageWindow] = []
    if let limits = root["limits"] as? [[String: Any]] { for (index, entry) in limits.enumerated() { let window = dictionary(entry["window"]) ?? entry; let detail = dictionary(entry["detail"]) ?? entry; if let parsed = parseKimiDetail(detail, duration: kimiDurationSeconds(window), id: "kimi-\(index)") { windows.append(parsed) } } }
    if let usage = dictionary(root["usage"]), !windows.contains(where: { $0.label == "周" }), let weekly = parseKimiDetail(usage, duration: 604_800, id: "kimi-week-summary") { windows.append(weekly) }
    windows = uniqueWindows(windows); guard !windows.isEmpty else { throw UsageError.invalidResponse("No Kimi quota windows") }; return UsageSnapshot(accountID: account.id, provider: .kimi, windows: windows)
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
  private func normalizedBaseURL(_ value: String?, fallback: String) -> String { (value?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).flatMap { $0.isEmpty ? nil : $0 } ?? fallback }
  private func formBody(_ values: [String: String]) -> Data { values.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.sorted().joined(separator: "&").data(using: .utf8) ?? Data() }
  private func urlEncode(_ value: String) -> String { var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "+&="); return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
  private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
  private func string(_ value: Any?) -> String? { if let string = value as? String, !string.isEmpty { return string }; return nil }
  private func number(_ value: Any?) -> Double? { if let number = value as? NSNumber { return number.doubleValue }; if let string = value as? String { return Double(string) }; return nil }
  private func int64(_ value: Any?) -> Int64? { if let number = value as? NSNumber { return number.int64Value }; if let string = value as? String { return Int64(string) }; return nil }
  private func bool(_ value: Any?) -> Bool? { if let bool = value as? Bool { return bool }; if let number = value as? NSNumber { return number.boolValue }; return nil }
  private func parseISODate(_ value: String?) -> Date? { guard let value else { return nil }; return ISO8601DateFormatter().date(from: value) }
  private func flexibleDate(_ value: Any?) -> Date? { if let n = value as? NSNumber { let raw = n.doubleValue; return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw/1000 : raw) }; if let string = value as? String { return parseISODate(string) }; return nil }
  private func formatNumber(_ value: Double) -> String { if value.rounded() == value { return String(Int(value)) }; return String(format: "%.2f", value) }
  private func displayLabel(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
}
