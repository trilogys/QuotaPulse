#!/usr/bin/env swift

import Foundation

// Lightweight contract validation kept independent from Xcode so CI can catch
// provider-health regressions before a simulator runner is needed.
enum ProviderErrorKind: String {
  case authentication, rateLimited, providerUnavailable, network, invalidResponse, configuration, unknown
}

enum ProviderErrorClassifier {
  static func classify(message: String?) -> ProviderErrorKind {
    guard let raw = message?.lowercased(), !raw.isEmpty else { return .unknown }
    if raw.contains("401") || raw.contains("403") || raw.contains("unauthorized") || raw.contains("login expired") || raw.contains("token refresh") || raw.contains("credential not found") { return .authentication }
    if raw.contains("429") || raw.contains("rate limit") || raw.contains("too many requests") { return .rateLimited }
    if raw.contains("500") || raw.contains("502") || raw.contains("503") || raw.contains("504") || raw.contains("service unavailable") || raw.contains("bad gateway") { return .providerUnavailable }
    if raw.contains("timed out") || raw.contains("timeout") || raw.contains("network") || raw.contains("internet") || raw.contains("offline") || raw.contains("connection") || raw.contains("could not connect") || raw.contains("dns") { return .network }
    if raw.contains("invalid response") || raw.contains("missing rate_limit") || raw.contains("no codex quota") || raw.contains("no claude quota") || raw.contains("no kimi quota") || raw.contains("no balance_infos") || raw.contains("usage unavailable") { return .invalidResponse }
    if raw.contains("account not found") || raw.contains("configuration") || raw.contains("base url") { return .configuration }
    return .unknown
  }
}

let cases: [(String?, ProviderErrorKind)] = [
  ("HTTP 401 unauthorized", .authentication),
  ("login expired", .authentication),
  ("HTTP 429 too many requests", .rateLimited),
  ("503 service unavailable", .providerUnavailable),
  ("request timed out", .network),
  ("DNS connection failed", .network),
  ("invalid response: missing rate_limit", .invalidResponse),
  ("no claude quota found", .invalidResponse),
  ("base url configuration invalid", .configuration),
  ("something unexpected", .unknown),
  (nil, .unknown),
]

var failures = 0
for (message, expected) in cases {
  let actual = ProviderErrorClassifier.classify(message: message)
  if actual != expected {
    failures += 1
    fputs("FAIL: \(message ?? "nil") => \(actual.rawValue), expected \(expected.rawValue)\n", stderr)
  }
}

if failures > 0 {
  fputs("Provider health contract failed: \(failures) case(s)\n", stderr)
  exit(1)
}
print("Provider health contract passed: \(cases.count) cases")
