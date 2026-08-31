import Foundation
import WidgetKit

struct PortableImportResult: Sendable {
  let added: Int
  let updated: Int
  let credentialsImported: Int
  let skippedAccounts: Int
  let proxyImported: Bool
  let source: PortableImportSource
}

enum PortableImportMode: Sendable {
  case merge
  case replace
}

actor PortableConfigImporter {
  static let shared = PortableConfigImporter()

  func importData(_ data: Data, mode: PortableImportMode = .merge) async throws -> PortableImportResult {
    let decoded = try PortableConfigCodec.decodeForImport(data)
    let config = decoded.config
    let keychain = KeychainStore.shared
    let existing = await SharedStore.shared.accounts()
    var resultAccounts = mode == .replace ? [] : existing
    var added = 0
    var updated = 0
    var credentialsImported = 0

    if mode == .replace {
      for account in existing { try? keychain.deleteCredential(accountID: account.id) }
    }

    for item in config.accounts {
      guard let provider = ProviderID(rawValue: item.provider) else { throw PortableConfigError.invalidProvider(item.provider) }
      let record = AccountRecord(id:item.id,provider:provider,label:item.label,providerAccountID:item.providerAccountID,isEnabled:item.isEnabled,sortOrder:item.sortOrder,createdAt:item.createdAt)
      if let index = resultAccounts.firstIndex(where: { $0.id == record.id || ($0.provider == provider && item.providerAccountID != nil && $0.providerAccountID == item.providerAccountID) }) {
        let targetID = resultAccounts[index].id
        var merged = record
        if targetID != record.id { merged = AccountRecord(id:targetID,provider:provider,label:record.label,providerAccountID:record.providerAccountID,isEnabled:record.isEnabled,sortOrder:record.sortOrder,createdAt:resultAccounts[index].createdAt) }
        resultAccounts[index] = merged
        if let credential = item.credential {
          try saveCredential(credential, accountID: targetID, label: item.label, keychain: keychain)
          credentialsImported += 1
        }
        updated += 1
      } else {
        resultAccounts.append(record)
        if let credential = item.credential {
          try saveCredential(credential, accountID: record.id, label: item.label, keychain: keychain)
          credentialsImported += 1
        }
        added += 1
      }
    }

    resultAccounts = resultAccounts.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, value in var copy=value;copy.sortOrder=index;return copy }
    await SharedStore.shared.saveAccounts(resultAccounts)
    if let proxy = decoded.proxy {
      let existingProfiles = await SharedStore.shared.proxyProfiles()
      let existingProxy = existingProfiles.first {
        $0.name == proxy.name && $0.configuration == proxy.configuration && $0.targets == proxy.targets
      }
      let profile = AppProxyProfile(
        id: existingProxy?.id ?? UUID(),
        name: proxy.name,
        configuration: proxy.configuration,
        targets: proxy.targets,
        isActive: true,
        createdAt: existingProxy?.createdAt ?? .now
      )
      await SharedStore.shared.upsertProxyProfile(profile)
      try keychain.saveProxyPassword(proxy.password, profileID: profile.id)
    }
    for account in resultAccounts { await SharedStore.shared.clearCooldown(accountID: account.id) }
    WidgetCenter.shared.reloadAllTimelines()
    return PortableImportResult(added:added,updated:updated,credentialsImported:credentialsImported,skippedAccounts:decoded.skippedAccounts,proxyImported:decoded.proxy != nil,source:decoded.source)
  }

  private func saveCredential(
    _ credential: PortableCredential,
    accountID: UUID,
    label: String,
    keychain: KeychainStore
  ) throws {
    do {
      try keychain.saveCredential(credential.credential, accountID: accountID)
    } catch {
      throw PortableConfigError.credentialImportFailed(label, error.localizedDescription)
    }
  }
}
