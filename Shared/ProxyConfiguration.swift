import CFNetwork
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

enum AppProxyTarget: String, CaseIterable, Codable, Identifiable, Sendable {
  case codex
  case claude

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    }
  }

  static func target(for url: URL) -> AppProxyTarget? {
    let host = url.host?.lowercased() ?? ""
    if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host.hasSuffix(".openai.com") { return .codex }
    if host.hasSuffix(".anthropic.com") || host.hasSuffix(".claude.com") { return .claude }
    return nil
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

  func connectionProxyDictionary(password: String = "") -> [AnyHashable: Any]? {
    guard isEnabled else { return nil }
    var values: [AnyHashable: Any]
    switch kind {
    case .disabled:
      return nil
    case .http:
      values = [
        "HTTPEnable": true,
        "HTTPProxy": normalizedHost,
        "HTTPPort": port,
        "HTTPSEnable": true,
        "HTTPSProxy": normalizedHost,
        "HTTPSPort": port,
      ]
    case .socks5:
      values = [
        "SOCKSEnable": true,
        "SOCKSProxy": normalizedHost,
        "SOCKSPort": port,
      ]
    }
    if !username.isEmpty {
      values["ProxyUsername"] = username
      values["ProxyPassword"] = password
      values["SOCKSUser"] = username
      values["SOCKSPassword"] = password
    }
    return values
  }
}

struct AppProxyProfile: Codable, Equatable, Identifiable, Sendable {
  static let legacyID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!

  var id: UUID
  var name: String
  var configuration: AppProxyConfiguration
  var targets: Set<AppProxyTarget>
  var isActive: Bool
  var createdAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    configuration: AppProxyConfiguration,
    targets: Set<AppProxyTarget> = Set(AppProxyTarget.allCases),
    isActive: Bool = false,
    createdAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.configuration = configuration
    self.targets = targets
    self.isActive = isActive
    self.createdAt = createdAt
  }

  var validationMessage: String? {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入代理名称" }
    if targets.isEmpty { return "请至少选择 Codex 或 Claude" }
    return configuration.validationMessage
  }
}

struct ParsedAppProxyLink: Sendable {
  let configuration: AppProxyConfiguration
  let password: String
}

enum AppProxyLinkError: LocalizedError {
  case unsupportedScheme
  case invalidAddress

  var errorDescription: String? {
    switch self {
    case .unsupportedScheme: "仅支持 http://、https://、socks5://、socks:// 或 socket://"
    case .invalidAddress: "代理链接缺少有效的主机或端口"
    }
  }
}

extension AppProxyConfiguration {
  static func parse(link: String) throws -> ParsedAppProxyLink {
    var raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "：//", with: "://")
      .replacingOccurrences(of: "\\@", with: "@")
    guard let separator = raw.range(of: "://") else { throw AppProxyLinkError.unsupportedScheme }
    let suppliedScheme = raw[..<separator.lowerBound].lowercased()
    let kind: AppProxyKind
    switch suppliedScheme {
    case "http", "https": kind = .http
    case "socks5", "socks", "socket": kind = .socks5
    default: throw AppProxyLinkError.unsupportedScheme
    }
    if suppliedScheme == "socks" || suppliedScheme == "socket" {
      raw = "socks5://" + String(raw[separator.upperBound...])
    }
    guard let components = URLComponents(string: raw),
      let host = components.host, !host.isEmpty,
      let port = components.port, (1...65_535).contains(port)
    else { throw AppProxyLinkError.invalidAddress }
    let username = components.percentEncodedUser?.removingPercentEncoding ?? components.user ?? ""
    let password = components.percentEncodedPassword?.removingPercentEncoding ?? components.password ?? ""
    return ParsedAppProxyLink(
      configuration: AppProxyConfiguration(kind: kind, host: host, port: port, username: username),
      password: password
    )
  }
}
