import Foundation
import WidgetKit

struct PortableImportResult: Sendable {
  let added: Int
  let updated: Int
  let credentialsImported: Int
}

enum PortableImportMode: Sendable {
  case merge
  case replace
}

actor PortableConfigImporter {
  static let shared = PortableConfigImporter()

  func importData(_ data: Data, mode: PortableImportMode = .merge) async throws -> PortableImportResult {
    let config = try PortableConfigCodec.decode(data)
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
        if let credential = item.credential { try keychain.saveCredential(credential.credential,accountID:targetID);credentialsImported += 1 }
        updated += 1
      } else {
        resultAccounts.append(record)
        if let credential = item.credential { try keychain.saveCredential(credential.credential,accountID:record.id);credentialsImported += 1 }
        added += 1
      }
    }

    resultAccounts = resultAccounts.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, value in var copy=value;copy.sortOrder=index;return copy }
    await SharedStore.shared.saveAccounts(resultAccounts)
    for account in resultAccounts { await SharedStore.shared.clearCooldown(accountID: account.id) }
    WidgetCenter.shared.reloadAllTimelines()
    return PortableImportResult(added:added,updated:updated,credentialsImported:credentialsImported)
  }
}
