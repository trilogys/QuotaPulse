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

struct KeychainStore: Sendable {
  static let shared = KeychainStore()

  /// Resolve the Apple AppIdentifierPrefix at runtime instead of baking it into
  /// Info.plist. This matters for unsigned IPA -> re-sign workflows because the
  /// prefix is chosen by the provisioning profile at signing time.
  private var accessGroup: String? {
    guard
      let suffix = Bundle.main.object(forInfoDictionaryKey: AppConfig.keychainSuffixInfoKey) as? String,
      !suffix.isEmpty
    else { return nil }

    guard let defaultGroup = discoverDefaultAccessGroup() else { return nil }
    if defaultGroup == suffix || defaultGroup.hasSuffix(".\(suffix)") {
      return defaultGroup
    }

    if let bundleID = Bundle.main.bundleIdentifier {
      let bundleSuffix = ".\(bundleID)"
      if defaultGroup.hasSuffix(bundleSuffix) {
        let prefix = String(defaultGroup.dropLast(bundleSuffix.count))
        if !prefix.isEmpty { return "\(prefix).\(suffix)" }
      }
    }

    // Apple application identifier prefixes are normally a single component.
    if let dot = defaultGroup.firstIndex(of: ".") {
      let prefix = defaultGroup[..<dot]
      if !prefix.isEmpty { return "\(prefix).\(suffix)" }
    }
    return nil
  }

  /// Add a short-lived item without specifying kSecAttrAccessGroup, then read
  /// the access group assigned by the current code signature. No private API is
  /// needed and the probe is deleted immediately.
  private func discoverDefaultAccessGroup() -> String? {
    let account = "probe.\(UUID().uuidString)"
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "\(AppConfig.keychainService).AccessGroupProbe",
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)

    var add = base
    add[kSecValueData as String] = Data([0])
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { return nil }
    defer { SecItemDelete(base as CFDictionary) }

    var read = base
    read[kSecReturnAttributes as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess,
          let attrs = result as? [String: Any],
          let group = attrs[kSecAttrAccessGroup as String] as? String,
          !group.isEmpty
    else { return nil }
    return group
  }

  func saveCredential(_ credential: Credential, accountID: UUID) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(credential)
    let account = accountID.uuidString

    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConfig.keychainService,
      kSecAttrAccount as String: account,
    ]
    if let group = accessGroup, !group.isEmpty {
      query[kSecAttrAccessGroup as String] = group
    }

    SecItemDelete(query as CFDictionary)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
  }

  func credential(accountID: UUID) throws -> Credential? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConfig.keychainService,
      kSecAttrAccount as String: accountID.uuidString,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let group = accessGroup, !group.isEmpty {
      query[kSecAttrAccessGroup as String] = group
    }

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    guard let data = result as? Data else { throw KeychainError.invalidData }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Credential.self, from: data)
  }

  func deleteCredential(accountID: UUID) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConfig.keychainService,
      kSecAttrAccount as String: accountID.uuidString,
    ]
    if let group = accessGroup, !group.isEmpty {
      query[kSecAttrAccessGroup as String] = group
    }
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
