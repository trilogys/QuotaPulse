import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
  case codex
  case claude
  case kimi
  case deepseek
  case minimax
  case glm
  case copilot

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    case .kimi: "Kimi"
    case .deepseek: "DeepSeek"
    case .minimax: "MiniMax"
    case .glm: "GLM"
    case .copilot: "Copilot"
    }
  }

  var supportsMultipleAccounts: Bool {
    switch self {
    case .codex, .claude, .kimi: true
    default: false
    }
  }
}

struct AccountRecord: Codable, Identifiable, Hashable, Sendable {
  var id: UUID
  var provider: ProviderID
  var label: String
  var providerAccountID: String?
  var isEnabled: Bool
  var sortOrder: Int
  var createdAt: Date

  init(id: UUID = UUID(), provider: ProviderID, label: String, providerAccountID: String? = nil, isEnabled: Bool = true, sortOrder: Int = 0, createdAt: Date = .now) {
    self.id = id; self.provider = provider; self.label = label; self.providerAccountID = providerAccountID; self.isEnabled = isEnabled; self.sortOrder = sortOrder; self.createdAt = createdAt
  }
}

enum CredentialAuthenticationMode: String, Codable, Hashable, Sendable {
  case oauth
  case apiKey
}

struct Credential: Codable, Sendable {
  var accessToken: String
  var refreshToken: String?
  var idToken: String?
  var accountID: String?
  var expiresAt: Date?
  var clientID: String?
  var baseURL: String?
  var deviceHeaders: [String: String]?
  var authenticationMode: CredentialAuthenticationMode?

  init(accessToken: String, refreshToken: String? = nil, idToken: String? = nil, accountID: String? = nil, expiresAt: Date? = nil, clientID: String? = nil, baseURL: String? = nil, deviceHeaders: [String: String]? = nil, authenticationMode: CredentialAuthenticationMode? = nil) {
    self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken; self.accountID = accountID; self.expiresAt = expiresAt; self.clientID = clientID; self.baseURL = baseURL; self.deviceHeaders = deviceHeaders; self.authenticationMode = authenticationMode
  }
}

struct UsageWindow: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var label: String
  var remainingPercent: Double
  var resetAt: Date?
  var detail: String?

  init(id: String, label: String, remainingPercent: Double, resetAt: Date? = nil, detail: String? = nil) {
    self.id = id; self.label = label; self.remainingPercent = min(100, max(0, remainingPercent)); self.resetAt = resetAt; self.detail = detail
  }
}

struct UsageMetric: Codable, Hashable, Sendable, Identifiable {
  var id: String { label }
  var label: String
  var value: String
}

struct BalanceSnapshot: Codable, Hashable, Sendable {
  var currency: String
  var symbol: String
  var total: Double
  var granted: Double
  var toppedUp: Double
  var available: Bool
}

struct CodexResetCreditSummary: Codable, Hashable, Sendable {
  var availableCount: Int
  var expiresAt: [Date]
  var fetchedAt: Date

  init(availableCount: Int, expiresAt: [Date] = [], fetchedAt: Date = .now) {
    self.availableCount = max(0, availableCount)
    self.expiresAt = expiresAt.sorted()
    self.fetchedAt = fetchedAt
  }
}

struct CodexQuotaResetResult: Hashable, Sendable {
  var code: String
  var windowsReset: Int
}

struct CodexDailyTokenUsage: Codable, Hashable, Sendable, Identifiable {
  var id: Date { startDate }
  var startDate: Date
  var tokens: Int64
}

struct CodexTokenUsageSummary: Codable, Hashable, Sendable {
  var lifetimeTokens: Int64?
  var peakDailyTokens: Int64?
  var longestRunningTurnSeconds: Int64?
  var currentStreakDays: Int64?
  var longestStreakDays: Int64?
  var dailyUsageBuckets: [CodexDailyTokenUsage]

  var hasData: Bool {
    lifetimeTokens != nil
      || peakDailyTokens != nil
      || longestRunningTurnSeconds != nil
      || currentStreakDays != nil
      || longestStreakDays != nil
      || !dailyUsageBuckets.isEmpty
  }
}

struct CodexModelTokenUsage: Codable, Hashable, Sendable, Identifiable {
  var id: String { "\(model)|\(reasoningEffort ?? "")|\(speed ?? "")" }
  var model: String
  var reasoningEffort: String?
  var speed: String?
  var inputTokens: Int64
  var cachedInputTokens: Int64
  var outputTokens: Int64
  var totalTokens: Int64
  var estimatedUsageCreditsMicros: Int64
}

struct CodexModelUsageSummary: Codable, Hashable, Sendable {
  var groups: [CodexModelTokenUsage]
  var returnedThreadCount: Int
  var estimatedUsageUSDMicros: Int64?
  var isPartial: Bool
  var fetchedAt: Date
}

enum ProviderErrorKind: String, Codable, Hashable, Sendable {
  case authentication
  case rateLimited
  case providerUnavailable
  case network
  case invalidResponse
  case configuration
  case unknown

  var shortLabel: String {
    switch self {
    case .authentication: "登录失效"
    case .rateLimited: "限流"
    case .providerUnavailable: "服务异常"
    case .network: "网络异常"
    case .invalidResponse: "数据异常"
    case .configuration: "配置异常"
    case .unknown: "刷新失败"
    }
  }
}

struct UsageSnapshot: Codable, Hashable, Sendable, Identifiable {
  var id: UUID { accountID }
  var accountID: UUID
  var provider: ProviderID
  var fetchedAt: Date
  var windows: [UsageWindow]
  var metrics: [UsageMetric]
  var balance: BalanceSnapshot?
  var codexResetCredits: CodexResetCreditSummary?
  var codexTokenUsage: CodexTokenUsageSummary?
  var codexModelUsage: CodexModelUsageSummary?
  var authenticationMode: CredentialAuthenticationMode?
  var plan: String?
  var errorMessage: String?
  var errorKind: ProviderErrorKind?
  var stale: Bool

  init(accountID: UUID, provider: ProviderID, fetchedAt: Date = .now, windows: [UsageWindow] = [], metrics: [UsageMetric] = [], balance: BalanceSnapshot? = nil, codexResetCredits: CodexResetCreditSummary? = nil, codexTokenUsage: CodexTokenUsageSummary? = nil, codexModelUsage: CodexModelUsageSummary? = nil, authenticationMode: CredentialAuthenticationMode? = nil, plan: String? = nil, errorMessage: String? = nil, errorKind: ProviderErrorKind? = nil, stale: Bool = false) {
    self.accountID = accountID; self.provider = provider; self.fetchedAt = fetchedAt; self.windows = windows; self.metrics = metrics; self.balance = balance; self.codexResetCredits = codexResetCredits; self.codexTokenUsage = codexTokenUsage; self.codexModelUsage = codexModelUsage; self.authenticationMode = authenticationMode; self.plan = plan; self.errorMessage = errorMessage; self.errorKind = errorKind; self.stale = stale
  }

  private enum CodingKeys: String, CodingKey { case accountID, provider, fetchedAt, windows, metrics, balance, codexResetCredits, codexTokenUsage, codexModelUsage, authenticationMode, plan, errorMessage, errorKind, stale }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    accountID = try c.decode(UUID.self, forKey: .accountID)
    provider = try c.decode(ProviderID.self, forKey: .provider)
    fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
    windows = try c.decodeIfPresent([UsageWindow].self, forKey: .windows) ?? []
    metrics = try c.decodeIfPresent([UsageMetric].self, forKey: .metrics) ?? []
    balance = try c.decodeIfPresent(BalanceSnapshot.self, forKey: .balance)
    codexResetCredits = try c.decodeIfPresent(CodexResetCreditSummary.self, forKey: .codexResetCredits)
    codexTokenUsage = try c.decodeIfPresent(CodexTokenUsageSummary.self, forKey: .codexTokenUsage)
    codexModelUsage = try c.decodeIfPresent(CodexModelUsageSummary.self, forKey: .codexModelUsage)
    authenticationMode = try c.decodeIfPresent(CredentialAuthenticationMode.self, forKey: .authenticationMode)
    plan = try c.decodeIfPresent(String.self, forKey: .plan)
    errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    errorKind = try c.decodeIfPresent(ProviderErrorKind.self, forKey: .errorKind)
    stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
  }
}

struct WidgetDisplayItem: Codable, Hashable, Sendable, Identifiable {
  var id: UUID { account.id }
  var account: AccountRecord
  var snapshot: UsageSnapshot?
}
