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

  init(
    id: UUID = UUID(),
    provider: ProviderID,
    label: String,
    providerAccountID: String? = nil,
    isEnabled: Bool = true,
    sortOrder: Int = 0,
    createdAt: Date = .now
  ) {
    self.id = id
    self.provider = provider
    self.label = label
    self.providerAccountID = providerAccountID
    self.isEnabled = isEnabled
    self.sortOrder = sortOrder
    self.createdAt = createdAt
  }
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

  init(
    accessToken: String,
    refreshToken: String? = nil,
    idToken: String? = nil,
    accountID: String? = nil,
    expiresAt: Date? = nil,
    clientID: String? = nil,
    baseURL: String? = nil,
    deviceHeaders: [String: String]? = nil
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.idToken = idToken
    self.accountID = accountID
    self.expiresAt = expiresAt
    self.clientID = clientID
    self.baseURL = baseURL
    self.deviceHeaders = deviceHeaders
  }
}

struct UsageWindow: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var label: String
  var remainingPercent: Double
  var resetAt: Date?
  var detail: String?

  init(
    id: String, label: String, remainingPercent: Double, resetAt: Date? = nil, detail: String? = nil
  ) {
    self.id = id
    self.label = label
    self.remainingPercent = min(100, max(0, remainingPercent))
    self.resetAt = resetAt
    self.detail = detail
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

struct UsageSnapshot: Codable, Hashable, Sendable, Identifiable {
  var id: UUID { accountID }
  var accountID: UUID
  var provider: ProviderID
  var fetchedAt: Date
  var windows: [UsageWindow]
  var metrics: [UsageMetric]
  var balance: BalanceSnapshot?
  var plan: String?
  var errorMessage: String?
  var stale: Bool

  init(
    accountID: UUID,
    provider: ProviderID,
    fetchedAt: Date = .now,
    windows: [UsageWindow] = [],
    metrics: [UsageMetric] = [],
    balance: BalanceSnapshot? = nil,
    plan: String? = nil,
    errorMessage: String? = nil,
    stale: Bool = false
  ) {
    self.accountID = accountID
    self.provider = provider
    self.fetchedAt = fetchedAt
    self.windows = windows
    self.metrics = metrics
    self.balance = balance
    self.plan = plan
    self.errorMessage = errorMessage
    self.stale = stale
  }
}

struct WidgetDisplayItem: Codable, Hashable, Sendable, Identifiable {
  var id: UUID { account.id }
  var account: AccountRecord
  var snapshot: UsageSnapshot?
}
