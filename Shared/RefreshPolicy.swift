import Foundation

/// Centralized refresh failure policy shared by the iOS app and WidgetKit refresh paths.
/// Cooldowns are account-scoped in SharedStore, so one provider/account failure never blocks others.
struct RefreshFailurePolicy: Sendable {
  let kind: ProviderErrorKind
  let message: String
  let cooldown: TimeInterval?

  static func classify(_ error: Error) -> RefreshFailurePolicy {
    let message = error.localizedDescription

    if let usageError = error as? UsageError {
      switch usageError {
      case .missingAccount:
        return .init(kind: .configuration, message: message, cooldown: nil)
      case .missingCredential, .unauthorized:
        return .init(kind: .authentication, message: message, cooldown: 6 * 60 * 60)
      case .http(let status, _):
        switch status {
        case 401, 403:
          return .init(kind: .authentication, message: message, cooldown: 6 * 60 * 60)
        case 429:
          return .init(kind: .rateLimited, message: message, cooldown: 15 * 60)
        case 500...599:
          return .init(kind: .providerUnavailable, message: message, cooldown: 5 * 60)
        default:
          return .init(kind: ProviderErrorClassifier.classify(message: message), message: message, cooldown: 5 * 60)
        }
      case .invalidResponse:
        return .init(kind: .invalidResponse, message: message, cooldown: 60 * 60)
      case .refreshFailed:
        return .init(kind: ProviderErrorClassifier.classify(message: message), message: message, cooldown: 60 * 60)
      }
    }

    let kind = ProviderErrorClassifier.classify(message: message)
    let cooldown: TimeInterval
    switch kind {
    case .network:
      cooldown = 60
    case .rateLimited:
      cooldown = 15 * 60
    case .providerUnavailable:
      cooldown = 5 * 60
    case .authentication:
      cooldown = 6 * 60 * 60
    case .invalidResponse, .configuration:
      cooldown = 60 * 60
    case .unknown:
      cooldown = 5 * 60
    }
    return .init(kind: kind, message: message, cooldown: cooldown)
  }
}

extension SharedStore {
  /// Applies a failure to only the affected account and preserves its last known quota as stale data.
  func applyRefreshFailure(account: AccountRecord, error: Error, now: Date = Date()) {
    let failure = RefreshFailurePolicy.classify(error)
    if let cooldown = failure.cooldown {
      setCooldown(accountID: account.id, until: now.addingTimeInterval(cooldown))
    }
    if snapshot(for: account.id) == nil {
      saveSnapshot(UsageSnapshot(
        accountID: account.id,
        provider: account.provider,
        errorMessage: failure.message,
        stale: true,
        errorKind: failure.kind
      ))
    } else {
      markSnapshotStale(accountID: account.id, message: failure.message, kind: failure.kind)
    }
  }
}
