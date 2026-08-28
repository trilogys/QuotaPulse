import Foundation

enum UsageHistoryMetricKind: String, Codable, Hashable, Sendable {
  case utilization
  case balance
}

struct UsageHistorySample: Codable, Hashable, Identifiable, Sendable {
  var id: String { "\(accountID.uuidString)-\(recordedAt.timeIntervalSince1970)" }
  var accountID: UUID
  var provider: ProviderID
  var recordedAt: Date
  var kind: UsageHistoryMetricKind
  var value: Double
  var unit: String
  var sourceLabel: String
  var resetAt: Date?

  init?(snapshot: UsageSnapshot) {
    accountID = snapshot.accountID
    provider = snapshot.provider
    recordedAt = snapshot.fetchedAt

    if let window = snapshot.windows.min(by: { $0.remainingPercent < $1.remainingPercent }) {
      kind = .utilization
      value = min(100, max(0, 100 - window.remainingPercent))
      unit = "%"
      sourceLabel = window.label
      resetAt = window.resetAt
    } else if let balance = snapshot.balance {
      kind = .balance
      value = balance.total
      unit = balance.symbol
      sourceLabel = "余额"
      resetAt = nil
    } else {
      return nil
    }
  }
}
