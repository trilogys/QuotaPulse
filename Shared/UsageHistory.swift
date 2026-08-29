import Foundation

enum UsageHistoryMetricKind: String, Codable, Hashable, Sendable {
  case utilization
  case balance
  case tokens
}

struct UsageHistorySample: Codable, Hashable, Identifiable, Sendable {
  var id: String { "\(accountID.uuidString)-\(kind.rawValue)-\(recordedAt.timeIntervalSince1970)" }
  var accountID: UUID
  var provider: ProviderID
  var recordedAt: Date
  var kind: UsageHistoryMetricKind
  var value: Double
  var unit: String
  var sourceLabel: String
  var resetAt: Date?

  init(
    accountID: UUID,
    provider: ProviderID,
    recordedAt: Date,
    kind: UsageHistoryMetricKind,
    value: Double,
    unit: String,
    sourceLabel: String,
    resetAt: Date? = nil
  ) {
    self.accountID = accountID
    self.provider = provider
    self.recordedAt = recordedAt
    self.kind = kind
    self.value = value
    self.unit = unit
    self.sourceLabel = sourceLabel
    self.resetAt = resetAt
  }

  static func samples(snapshot: UsageSnapshot) -> [UsageHistorySample] {
    var samples: [UsageHistorySample] = []
    if let window = snapshot.windows.min(by: { $0.remainingPercent < $1.remainingPercent }) {
      samples.append(UsageHistorySample(
        accountID: snapshot.accountID,
        provider: snapshot.provider,
        recordedAt: snapshot.fetchedAt,
        kind: .utilization,
        value: min(100, max(0, 100 - window.remainingPercent)),
        unit: "%",
        sourceLabel: window.label,
        resetAt: window.resetAt
      ))
    } else if let balance = snapshot.balance {
      samples.append(UsageHistorySample(
        accountID: snapshot.accountID,
        provider: snapshot.provider,
        recordedAt: snapshot.fetchedAt,
        kind: .balance,
        value: balance.total,
        unit: balance.symbol,
        sourceLabel: "余额"
      ))
    }
    if let tokenUsage = snapshot.codexTokenUsage {
      samples.append(contentsOf: tokenUsage.dailyUsageBuckets.map { bucket in
        UsageHistorySample(
          accountID: snapshot.accountID,
          provider: snapshot.provider,
          recordedAt: bucket.startDate,
          kind: .tokens,
          value: Double(bucket.tokens),
          unit: "Token",
          sourceLabel: "官方每日用量"
        )
      })
    }
    return samples
  }
}
