import Foundation

enum ProviderHealthState: Hashable, Sendable {
  case healthy
  case stale(ProviderErrorKind)
  case unavailable(ProviderErrorKind)

  var isHealthy: Bool {
    if case .healthy = self { return true }
    return false
  }
}

enum ProviderErrorClassifier {
  static func classify(message: String?) -> ProviderErrorKind {
    guard let raw = message?.lowercased(), !raw.isEmpty else { return .unknown }

    if raw.contains("401") || raw.contains("403") || raw.contains("unauthorized")
      || raw.contains("login expired") || raw.contains("token refresh")
      || raw.contains("credential not found") {
      return .authentication
    }
    if raw.contains("429") || raw.contains("rate limit") || raw.contains("too many requests") {
      return .rateLimited
    }
    if raw.contains("500") || raw.contains("502") || raw.contains("503") || raw.contains("504")
      || raw.contains("service unavailable") || raw.contains("bad gateway") {
      return .providerUnavailable
    }
    if raw.contains("timed out") || raw.contains("timeout") || raw.contains("network")
      || raw.contains("internet") || raw.contains("offline") || raw.contains("connection")
      || raw.contains("could not connect") || raw.contains("dns") {
      return .network
    }
    if raw.contains("invalid response") || raw.contains("missing rate_limit")
      || raw.contains("no codex quota") || raw.contains("no claude quota")
      || raw.contains("no kimi quota") || raw.contains("no balance_infos")
      || raw.contains("usage unavailable") {
      return .invalidResponse
    }
    if raw.contains("account not found") || raw.contains("configuration") || raw.contains("base url") {
      return .configuration
    }
    return .unknown
  }
}

extension UsageSnapshot {
  var effectiveErrorKind: ProviderErrorKind? {
    guard stale || errorMessage != nil else { return nil }
    return errorKind ?? ProviderErrorClassifier.classify(message: errorMessage)
  }

  var healthState: ProviderHealthState {
    guard let kind = effectiveErrorKind else { return .healthy }
    let hasCachedData = !windows.isEmpty || !metrics.isEmpty || balance != nil
    return hasCachedData ? .stale(kind) : .unavailable(kind)
  }
}
