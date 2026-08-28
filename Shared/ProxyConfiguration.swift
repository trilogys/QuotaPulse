import Foundation

enum AppProxyKind: String, CaseIterable, Codable, Identifiable, Sendable {
  case disabled
  case http
  case socks5

  var id: String { rawValue }

  var title: String {
    switch self {
    case .disabled: "关闭"
    case .http: "HTTP(S)"
    case .socks5: "SOCKS5"
    }
  }
}

struct AppProxyConfiguration: Codable, Equatable, Sendable {
  var kind: AppProxyKind = .disabled
  var host: String = ""
  var port: Int = 0
  var username: String = ""

  static let disabled = AppProxyConfiguration()

  var normalizedHost: String {
    host.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  var validationMessage: String? {
    guard kind != .disabled else { return nil }
    if normalizedHost.isEmpty { return "请输入代理服务器地址" }
    if !(1...65_535).contains(port) { return "端口必须在 1–65535 之间" }
    return nil
  }

  var isEnabled: Bool { kind != .disabled && validationMessage == nil }

  func connectionProxyDictionary() -> [AnyHashable: Any]? {
    guard isEnabled else { return nil }
    switch kind {
    case .disabled:
      return nil
    case .http:
      return [
        "HTTPEnable": true,
        "HTTPProxy": normalizedHost,
        "HTTPPort": port,
        "HTTPSEnable": true,
        "HTTPSProxy": normalizedHost,
        "HTTPSPort": port,
      ]
    case .socks5:
      return [
        "SOCKSEnable": true,
        "SOCKSProxy": normalizedHost,
        "SOCKSPort": port,
      ]
    }
  }
}
