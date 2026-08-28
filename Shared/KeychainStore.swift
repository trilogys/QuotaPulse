import Foundation
import Security

enum KeychainError: LocalizedError {
  case missingAccessGroup
  case unexpectedStatus(OSStatus)
  case invalidData

  var errorDescription: String? {
    switch self {
    case .missingAccessGroup: "Shared Keychain access group could not be resolved."
    case .unexpectedStatus(let status): "Keychain error: \(status)"
    case .invalidData: "Keychain item could not be decoded."
    }
  }
}

enum SharedCredentialAccessStatus: Sendable, Equatable {
  case available(accessGroup: String)
  case unavailable(reason: String)
}

struct KeychainStore: Sendable {
  static let shared = KeychainStore()

  private var accessGroup: String? {
    guard let suffix = Bundle.main.object(forInfoDictionaryKey: AppConfig.keychainSuffixInfoKey) as? String, !suffix.isEmpty else { return nil }
    guard let defaultGroup = discoverDefaultAccessGroup() else { return nil }
    if defaultGroup == suffix || defaultGroup.hasSuffix(".\(suffix)") { return defaultGroup }
    if let bundleID = Bundle.main.bundleIdentifier {
      let bundleSuffix = ".\(bundleID)"
      if defaultGroup.hasSuffix(bundleSuffix) {
        let prefix = String(defaultGroup.dropLast(bundleSuffix.count))
        if !prefix.isEmpty { return "\(prefix).\(suffix)" }
      }
    }
    if let dot = defaultGroup.firstIndex(of: ".") {
      let prefix = defaultGroup[..<dot]
      if !prefix.isEmpty { return "\(prefix).\(suffix)" }
    }
    return nil
  }

  func sharedAccessStatus() -> SharedCredentialAccessStatus {
    guard let suffix = Bundle.main.object(forInfoDictionaryKey: AppConfig.keychainSuffixInfoKey) as? String, !suffix.isEmpty else { return .unavailable(reason: "缺少 Keychain 共享配置") }
    guard let group = accessGroup, !group.isEmpty else { return .unavailable(reason: "无法解析共享 Keychain；请检查 IPA 重签权限") }
    guard group == suffix || group.hasSuffix(".\(suffix)") else { return .unavailable(reason: "Keychain Access Group 与应用配置不匹配") }
    guard canAccess(group: group) else { return .unavailable(reason: "当前签名未授权共享 Keychain；主 App 将使用本地凭据") }
    return .available(accessGroup: group)
  }

  private func credentialQuery(_ base: [String: Any]) throws -> [String: Any] {
    if AppConfig.isAppOnlyBuild { return base }
    if case .available(let group) = sharedAccessStatus() {
      var query = base
      query[kSecAttrAccessGroup as String] = group
      return query
    }
    if !AppConfig.isWidgetExtension { return base }
    throw KeychainError.missingAccessGroup
  }

  private func discoverDefaultAccessGroup() -> String? {
    let account = "probe.\(UUID().uuidString)"
    let base: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"\(AppConfig.keychainService).AccessGroupProbe",kSecAttrAccount as String:account]
    SecItemDelete(base as CFDictionary)
    var add=base;add[kSecValueData as String]=Data([0]);add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus=SecItemAdd(add as CFDictionary,nil);guard addStatus==errSecSuccess else{return nil};defer{SecItemDelete(base as CFDictionary)}
    var read=base;read[kSecReturnAttributes as String]=true;read[kSecMatchLimit as String]=kSecMatchLimitOne;var result:CFTypeRef?
    guard SecItemCopyMatching(read as CFDictionary,&result)==errSecSuccess,let attrs=result as? [String:Any],let group=attrs[kSecAttrAccessGroup as String] as? String,!group.isEmpty else{return nil};return group
  }

  private func canAccess(group: String) -> Bool {
    let account = "probe.\(UUID().uuidString)"
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "\(AppConfig.keychainService).SharedGroupProbe",
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: group,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = Data([0])
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(add as CFDictionary, nil)
    if status == errSecSuccess { SecItemDelete(base as CFDictionary) }
    return status == errSecSuccess
  }

  func saveCredential(_ credential: Credential, accountID: UUID) throws {
    let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601;let data=try encoder.encode(credential);let account=accountID.uuidString
    var query=try credentialQuery([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:AppConfig.keychainService,kSecAttrAccount as String:account])
    SecItemDelete(query as CFDictionary);query[kSecValueData as String]=data;query[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status=SecItemAdd(query as CFDictionary,nil);guard status==errSecSuccess else{throw KeychainError.unexpectedStatus(status)}
  }

  func credential(accountID: UUID) throws -> Credential? {
    let query=try credentialQuery([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:AppConfig.keychainService,kSecAttrAccount as String:accountID.uuidString,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne])
    var result:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&result);if status==errSecItemNotFound{return nil};guard status==errSecSuccess else{throw KeychainError.unexpectedStatus(status)};guard let data=result as? Data else{throw KeychainError.invalidData}
    let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601;return try decoder.decode(Credential.self,from:data)
  }

  func deleteCredential(accountID: UUID) throws {
    let query=try credentialQuery([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:AppConfig.keychainService,kSecAttrAccount as String:accountID.uuidString])
    let status=SecItemDelete(query as CFDictionary);guard status==errSecSuccess||status==errSecItemNotFound else{throw KeychainError.unexpectedStatus(status)}
  }
}
