import Foundation

private struct ScriptableConfigPayload: Encodable {
  let format = "quotapulse-scriptable"
  let version = 1
  let exportedAt = Date()
  let refreshMinutes: Int
  let accounts: [ScriptableAccountPayload]
}

private struct ScriptableAccountPayload: Encodable {
  let id: UUID
  let provider: String
  let label: String
  let providerAccountID: String?
  let credential: PortableCredential
}

enum ScriptableExportError: LocalizedError {
  case noEnabledAccounts
  case missingCredential(String)
  case bundledScriptMissing

  var errorDescription: String? {
    switch self {
    case .noEnabledAccounts:
      "没有可导出到 Scriptable 的启用账号"
    case .missingCredential(let label):
      "账号 \(label) 缺少可导出的凭据，请先重新认证"
    case .bundledScriptMissing:
      "App 内未找到 QuotaPulseWidget.js"
    }
  }
}

enum ScriptableConfigExporter {
  static func configData(
    accounts: [AccountRecord],
    refreshMinutes: Int,
    keychain: KeychainStore = .shared
  ) throws -> Data {
    let enabled = accounts.filter(\.isEnabled)
    guard !enabled.isEmpty else { throw ScriptableExportError.noEnabledAccounts }
    let values = try enabled.map { account -> ScriptableAccountPayload in
      guard let credential = try keychain.credential(accountID: account.id) else {
        throw ScriptableExportError.missingCredential(account.label)
      }
      return ScriptableAccountPayload(
        id: account.id,
        provider: account.provider.rawValue,
        label: account.label,
        providerAccountID: account.providerAccountID,
        credential: PortableCredential(credential)
      )
    }
    let payload = ScriptableConfigPayload(
      refreshMinutes: min(1_440, max(5, refreshMinutes)),
      accounts: values
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(payload)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          root["format"] as? String == "quotapulse-scriptable" else {
      throw PortableConfigError.invalidFormat
    }
    return data
  }

  static func scriptData() throws -> Data {
    guard let url = Bundle.main.url(forResource: "QuotaPulseWidget", withExtension: "js") else {
      throw ScriptableExportError.bundledScriptMissing
    }
    return try Data(contentsOf: url)
  }
}
