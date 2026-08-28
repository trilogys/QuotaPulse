import CryptoKit
import Foundation

enum PortableImportSource: String, Sendable {
  case quotaPulse
  case sub2API

  var title: String {
    switch self {
    case .quotaPulse: "QuotaPulse"
    case .sub2API: "Sub2API"
    }
  }
}

struct ImportedProxyConfiguration: Sendable {
  let name: String
  let configuration: AppProxyConfiguration
  let targets: Set<AppProxyTarget>
  let password: String
}

struct PortableDecodedImport: Sendable {
  let config: PortableConfig
  let source: PortableImportSource
  let proxy: ImportedProxyConfiguration?
  let skippedAccounts: Int
}

enum Sub2APIConfigCodec {
  static func decode(_ data: Data) throws -> PortableDecodedImport {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawAccounts = root["accounts"] as? [[String: Any]],
      let rawProxies = root["proxies"] as? [[String: Any]]
    else { throw PortableConfigError.invalidFormat }

    if let type = string(root, keys: ["type"]),
      !type.isEmpty,
      !["sub2api-data", "sub2api-bundle"].contains(type)
    { throw PortableConfigError.invalidFormat }
    if let version = integer(root["version"]), version > 1 {
      throw PortableConfigError.unsupportedSub2APIVersion(version)
    }

    let exportedAt = parseDate(root["exported_at"] ?? root["exportedAt"]) ?? .now
    var accounts: [PortableAccount] = []
    var referencedProxyKeys = Set<String>()
    var skipped = 0

    for (index, raw) in rawAccounts.enumerated() {
      guard let provider = provider(raw),
        let credentials = raw["credentials"] as? [String: Any],
        let accessToken = string(credentials, keys: ["access_token", "accessToken", "setup_token", "api_key", "token"])
      else {
        skipped += 1
        continue
      }

      let providerAccountID = string(credentials, keys: [
        "chatgpt_account_id", "account_id", "accountId", "organization_id", "organizationId",
      ])
      let label = string(raw, keys: ["name"])
        ?? string(credentials, keys: ["email"])
        ?? "\(provider.title) \(index + 1)"
      let stableIdentity = providerAccountID
        ?? string(credentials, keys: ["chatgpt_user_id", "user_id", "email"])
        ?? accessToken
      let credential = Credential(
        accessToken: accessToken,
        refreshToken: string(credentials, keys: ["refresh_token", "refreshToken"]),
        idToken: string(credentials, keys: ["id_token", "idToken"]),
        accountID: providerAccountID,
        expiresAt: parseDate(credentials["expires_at"] ?? credentials["expiresAt"]),
        clientID: string(credentials, keys: ["client_id", "clientId"]),
        baseURL: string(credentials, keys: ["base_url", "baseUrl"]),
        authenticationMode: authenticationMode(raw)
      )
      accounts.append(PortableAccount(
        id: stableUUID("sub2api|\(provider.rawValue)|\(stableIdentity)"),
        provider: provider.rawValue,
        label: label,
        providerAccountID: providerAccountID,
        isEnabled: true,
        sortOrder: accounts.count,
        createdAt: exportedAt,
        credential: PortableCredential(credential)
      ))
      if let proxyKey = string(raw, keys: ["proxy_key", "proxyKey"]) {
        referencedProxyKeys.insert(proxyKey)
      }
    }

    guard !accounts.isEmpty else { throw PortableConfigError.noSupportedSub2APIAccounts }
    let importedProxy = try proxy(
      rawProxies,
      referencedKeys: referencedProxyKeys,
      targets: Set(accounts.compactMap { item in
        switch ProviderID(rawValue: item.provider) {
        case .some(.codex): AppProxyTarget.codex
        case .some(.claude): AppProxyTarget.claude
        default: nil
        }
      })
    )
    return PortableDecodedImport(
      config: PortableConfig(version: 1, exportedAt: exportedAt, accounts: accounts),
      source: .sub2API,
      proxy: importedProxy,
      skippedAccounts: skipped
    )
  }

  private static func provider(_ raw: [String: Any]) -> ProviderID? {
    let platform = string(raw, keys: ["platform"])?.lowercased()
    let type = string(raw, keys: ["type"])?.lowercased()
    switch (platform, type) {
    case ("openai", "oauth"): .codex
    case ("openai", "api-key"), ("openai", "apikey"), ("openai", "key"): .codex
    case ("anthropic", "oauth"), ("anthropic", "setup-token"): .claude
    case ("anthropic", "api-key"), ("anthropic", "apikey"), ("anthropic", "key"): .claude
    case ("kimi", "api-key"), ("kimi", "apikey"), ("moonshot", "api-key"), ("moonshot", "apikey"): .kimi
    default: nil
    }
  }

  private static func authenticationMode(_ raw: [String: Any]) -> CredentialAuthenticationMode {
    switch string(raw, keys: ["type"])?.lowercased() {
    case "api-key", "apikey", "key": .apiKey
    default: .oauth
    }
  }

  private static func proxy(
    _ rawProxies: [[String: Any]],
    referencedKeys: Set<String>,
    targets: Set<AppProxyTarget>
  ) throws -> ImportedProxyConfiguration? {
    let referenced = rawProxies.filter { raw in
      guard let key = string(raw, keys: ["proxy_key", "proxyKey"]) else { return false }
      return referencedKeys.contains(key)
    }
    let candidates = referenced.isEmpty && rawProxies.count == 1 ? rawProxies : referenced
    guard !candidates.isEmpty else { return nil }
    guard candidates.count == 1 else { throw PortableConfigError.multipleSub2APIProxies }
    let raw = candidates[0]
    let protocolName = string(raw, keys: ["protocol"])?.lowercased()
    let kind: AppProxyKind
    switch protocolName {
    case "http", "https": kind = .http
    case "socks", "socks5", "socket": kind = .socks5
    default: throw PortableConfigError.invalidSub2APIProxy
    }
    guard let host = string(raw, keys: ["host"]),
      let port = integer(raw["port"]),
      !host.isEmpty,
      (1...65_535).contains(port)
    else { throw PortableConfigError.invalidSub2APIProxy }
    return ImportedProxyConfiguration(
      name: string(raw, keys: ["name"]) ?? "Sub2API 代理",
      configuration: AppProxyConfiguration(
        kind: kind,
        host: host,
        port: port,
        username: string(raw, keys: ["username"]) ?? ""
      ),
      targets: targets.isEmpty ? Set(AppProxyTarget.allCases) : targets,
      password: string(raw, keys: ["password"]) ?? ""
    )
  }

  private static func string(_ value: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let text = value[key] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      { return text }
    }
    return nil
  }

  private static func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String { return Int(text) }
    return nil
  }

  private static func stableUUID(_ value: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
