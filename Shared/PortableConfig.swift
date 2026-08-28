import Foundation

/// Versioned, platform-neutral backup format shared by iOS and Android.
/// JSON field names are intentionally stable and must remain compatible across platforms.
struct PortableConfig: Codable, Sendable {
  static let currentVersion = 1
  var format: String = "ai-quota-native"
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

  init(_ value: Credential) {
    accessToken=value.accessToken;refreshToken=value.refreshToken;idToken=value.idToken;accountID=value.accountID;expiresAt=value.expiresAt;clientID=value.clientID;baseURL=value.baseURL;deviceHeaders=value.deviceHeaders
  }

  var credential: Credential { Credential(accessToken:accessToken,refreshToken:refreshToken,idToken:idToken,accountID:accountID,expiresAt:expiresAt,clientID:clientID,baseURL:baseURL,deviceHeaders:deviceHeaders) }
}

enum PortableConfigError: LocalizedError {
  case invalidFormat
  case unsupportedVersion(Int)
  case invalidProvider(String)
  var errorDescription:String? { switch self { case .invalidFormat:"不是 QuotaPulse 配置文件";case .unsupportedVersion(let v):"暂不支持配置版本 \(v)";case .invalidProvider(let p):"未知 Provider：\(p)" } }
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
    guard config.format == "ai-quota-native" else { throw PortableConfigError.invalidFormat }
    guard config.version <= PortableConfig.currentVersion else { throw PortableConfigError.unsupportedVersion(config.version) }
    return config
  }
}
