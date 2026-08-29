import Foundation

/// Versioned, platform-neutral backup format shared by iOS and Android.
/// JSON field names are intentionally stable and must remain compatible across platforms.
struct PortableConfig: Codable, Sendable {
  static let currentVersion = 1
  var format: String = "quotapulse"
  var version: Int = currentVersion
  var exportedAt: Date = .now
  var accounts: [PortableAccount]
}

struct PortableAccount: Codable, Sendable {
  var id: UUID
  var provider: String
  var label: String
  var providerAccountID: String?
  var isEnabled: Bool
  var sortOrder: Int
  var createdAt: Date
  var credential: PortableCredential?
}

struct PortableCredential: Codable, Sendable {
  var accessToken: String
  var refreshToken: String?
  var idToken: String?
  var accountID: String?
  var expiresAt: Date?
  var clientID: String?
  var baseURL: String?
  var deviceHeaders: [String: String]?
  var authenticationMode: CredentialAuthenticationMode?

  init(_ value: Credential) {
    accessToken=value.accessToken;refreshToken=value.refreshToken;idToken=value.idToken;accountID=value.accountID;expiresAt=value.expiresAt;clientID=value.clientID;baseURL=value.baseURL;deviceHeaders=value.deviceHeaders;authenticationMode=value.authenticationMode
  }

  var credential: Credential { Credential(accessToken:accessToken,refreshToken:refreshToken,idToken:idToken,accountID:accountID,expiresAt:expiresAt,clientID:clientID,baseURL:baseURL,deviceHeaders:deviceHeaders,authenticationMode:authenticationMode) }
}

enum PortableConfigError: LocalizedError {
  case invalidFormat
  case unsupportedVersion(Int)
  case unsupportedSub2APIVersion(Int)
  case invalidProvider(String)
  case noSupportedSub2APIAccounts
  case multipleSub2APIProxies
  case invalidSub2APIProxy
  var errorDescription:String? { switch self { case .invalidFormat:"不是受支持的 QuotaPulse / Sub2API 配置文件";case .unsupportedVersion(let v):"暂不支持配置版本 \(v)";case .unsupportedSub2APIVersion(let v):"暂不支持 Sub2API 配置版本 \(v)";case .invalidProvider(let p):"未知 Provider：\(p)";case .noSupportedSub2APIAccounts:"Sub2API 文件中没有可导入的 OpenAI / Anthropic 账号";case .multipleSub2APIProxies:"Sub2API 文件引用了多个不同代理，当前 App 只能使用一个全局代理";case .invalidSub2APIProxy:"Sub2API 代理缺少受支持的协议、主机或端口" } }
}

struct PortableConfigCodec {
  static func encode(accounts:[AccountRecord],keychain:KeychainStore = .shared,includeCredentials:Bool = true) throws -> Data {
    let values=accounts.map { account in
      let credential = includeCredentials ? (try? keychain.credential(accountID:account.id)).flatMap{$0}.map(PortableCredential.init) : nil
      return PortableAccount(id:account.id,provider:account.provider.rawValue,label:account.label,providerAccountID:account.providerAccountID,isEnabled:account.isEnabled,sortOrder:account.sortOrder,createdAt:account.createdAt,credential:credential)
    }
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes];encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(PortableConfig(accounts:values))
  }

  static func decode(_ data:Data) throws -> PortableConfig {
    let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
    let config=try decoder.decode(PortableConfig.self,from:data)
    guard config.format == "quotapulse" else { throw PortableConfigError.invalidFormat }
    guard config.version <= PortableConfig.currentVersion else { throw PortableConfigError.unsupportedVersion(config.version) }
    return config
  }

  static func decodeForImport(_ data: Data) throws -> PortableDecodedImport {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw PortableConfigError.invalidFormat
    }
    if root["format"] as? String == "quotapulse" {
      return PortableDecodedImport(
        config: try decode(data),
        source: .quotaPulse,
        proxy: nil,
        skippedAccounts: 0
      )
    }
    return try Sub2APIConfigCodec.decode(data)
  }
}
