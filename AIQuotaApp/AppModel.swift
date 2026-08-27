import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
  @Published var accounts: [AccountRecord] = []
  @Published var snapshots: [UUID: UsageSnapshot] = [:]
  @Published var isBusy = false
  @Published var errorMessage: String?

  private let keychain = KeychainStore.shared

  func load() async {
    accounts = await SharedStore.shared.accounts()
    var map: [UUID: UsageSnapshot] = [:]
    for account in accounts {
      if let snapshot = await SharedStore.shared.snapshot(for: account.id) {
        map[account.id] = snapshot
      }
    }
    snapshots = map
  }

  func addCodex(presenter: UIViewController) async {
    await performBusy {
      let coordinator = CodexOAuthCoordinator()
      let credential = try await coordinator.login(presenting: presenter)
      try await saveCredential(credential, provider: .codex)
    }
  }

  func addClaude(presenter: UIViewController) async {
    await performBusy {
      let coordinator = ClaudeOAuthCoordinator()
      let credential = try await coordinator.login(presenting: presenter)
      try await saveCredential(credential, provider: .claude)
    }
  }

  func addKimi(presenter: UIViewController) async {
    await performBusy {
      let coordinator = KimiOAuthCoordinator()
      let credential = try await coordinator.login(presenting: presenter)
      try await saveCredential(credential, provider: .kimi)
    }
  }

  func addAPIKey(provider: ProviderID, key: String, baseURL: String? = nil) async {
    await performBusy {
      let credential = Credential(
        accessToken: key, baseURL: baseURL?.trimmingCharacters(in: .whitespacesAndNewlines))
      try await saveCredential(credential, provider: provider)
    }
  }

  func refresh(_ account: AccountRecord) async {
    do {
      let snapshot = try await UsageService.shared.refresh(accountID: account.id)
      snapshots[account.id] = snapshot
      WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    } catch {
      errorMessage = error.localizedDescription
      if let snapshot = await SharedStore.shared.snapshot(for: account.id) {
        snapshots[account.id] = snapshot
      }
    }
  }

  func refreshAll() async {
    isBusy = true
    let refreshed = await UsageService.shared.refresh(
      accountIDs: accounts.filter(\.isEnabled).map(\.id))
    for snapshot in refreshed { snapshots[snapshot.accountID] = snapshot }
    isBusy = false
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
  }

  func delete(_ account: AccountRecord) async {
    do { try keychain.deleteCredential(accountID: account.id) } catch {
      errorMessage = error.localizedDescription
    }
    await SharedStore.shared.removeAccount(account.id)
    accounts.removeAll { $0.id == account.id }
    snapshots[account.id] = nil
    await normalizeAndSaveOrder()
    WidgetCenter.shared.reloadAllTimelines()
  }

  func setEnabled(_ account: AccountRecord, enabled: Bool) async {
    var updated = account
    updated.isEnabled = enabled
    await SharedStore.shared.upsertAccount(updated)
    if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = updated }
    WidgetCenter.shared.reloadAllTimelines()
  }

  func rename(_ account: AccountRecord, label: String) async {
    var updated = account
    updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !updated.label.isEmpty else { return }
    await SharedStore.shared.upsertAccount(updated)
    if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = updated }
    WidgetCenter.shared.reloadAllTimelines()
  }

  func move(_ account: AccountRecord, offset: Int) async {
    guard offset != 0, let from = accounts.firstIndex(where: { $0.id == account.id }) else { return }
    let to = min(max(0, from + offset), accounts.count - 1)
    guard to != from else { return }
    var reordered = accounts
    let item = reordered.remove(at: from)
    reordered.insert(item, at: to)
    accounts = reordered.enumerated().map { index, record in
      var updated = record
      updated.sortOrder = index
      return updated
    }
    await SharedStore.shared.saveAccounts(accounts)
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func normalizeAndSaveOrder() async {
    accounts = accounts.enumerated().map { index, record in
      var updated = record
      updated.sortOrder = index
      return updated
    }
    await SharedStore.shared.saveAccounts(accounts)
  }

  private func saveCredential(_ credential: Credential, provider: ProviderID) async throws {
    let identity = identityForCredential(provider: provider, credential: credential)

    if let providerID = identity.providerAccountID,
      let existing = accounts.first(where: {
        $0.provider == provider && $0.providerAccountID == providerID
      })
    {
      try keychain.saveCredential(credential, accountID: existing.id)
      _ = try? await UsageService.shared.refresh(accountID: existing.id)
      await load()
      WidgetCenter.shared.reloadAllTimelines()
      return
    }

    if !provider.supportsMultipleAccounts,
      let existing = accounts.first(where: { $0.provider == provider })
    {
      try keychain.saveCredential(credential, accountID: existing.id)
      _ = try? await UsageService.shared.refresh(accountID: existing.id)
      await load()
      WidgetCenter.shared.reloadAllTimelines()
      return
    }

    let count = accounts.filter { $0.provider == provider }.count + 1
    let label = identity.email ?? identity.shortAccountLabel ?? "\(provider.title) \(count)"
    let record = AccountRecord(
      provider: provider,
      label: label,
      providerAccountID: identity.providerAccountID,
      sortOrder: accounts.count
    )
    try keychain.saveCredential(credential, accountID: record.id)
    await SharedStore.shared.upsertAccount(record)
    accounts.append(record)
    if let snapshot = try? await UsageService.shared.refresh(accountID: record.id) {
      snapshots[record.id] = snapshot
    }
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func identityForCredential(provider: ProviderID, credential: Credential) -> (
    email: String?, providerAccountID: String?, shortAccountLabel: String?
  ) {
    let claims = decodeJWTPayload(credential.idToken ?? credential.accessToken) ?? [:]
    let email = findNestedString(claims, key: "email")
    let accountID =
      credential.accountID ?? findNestedString(claims, key: "chatgpt_account_id")
      ?? findNestedString(claims, key: "sub")
    let short = accountID.map { "\(provider.title) · \(String($0.prefix(8)))" }
    return (email, accountID, short)
  }

  private func performBusy(_ operation: () async throws -> Void) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await operation()
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
