import Foundation

/// Small facade around UsageService that adds account-scoped cooldown behavior
/// without modifying the provider implementations in UsageService.swift.
actor CooldownAwareRefresh {
  static let shared = CooldownAwareRefresh()

  @discardableResult
  func refresh(accountID: UUID, manual: Bool = false) async throws -> UsageSnapshot {
    guard let account = await SharedStore.shared.account(id: accountID) else {
      throw UsageError.missingAccount
    }

    if !manual, let _ = await SharedStore.shared.cooldownUntil(accountID: accountID) {
      if let cached = await SharedStore.shared.snapshot(for: accountID) {
        return cached
      }
      throw UsageError.refreshFailed("Account refresh is cooling down")
    }

    if manual {
      await SharedStore.shared.clearCooldown(accountID: accountID)
    }

    do {
      let snapshot = try await UsageService.shared.refresh(accountID: accountID)
      await SharedStore.shared.clearCooldown(accountID: accountID)
      return snapshot
    } catch {
      await SharedStore.shared.applyRefreshFailure(account: account, error: error)
      throw error
    }
  }

  func refresh(accountIDs: [UUID], manual: Bool = false) async -> [UsageSnapshot] {
    await withTaskGroup(of: UsageSnapshot?.self) { group in
      for id in accountIDs {
        group.addTask {
          try? await CooldownAwareRefresh.shared.refresh(accountID: id, manual: manual)
        }
      }
      var snapshots: [UsageSnapshot] = []
      for await value in group {
        if let value { snapshots.append(value) }
      }
      return snapshots
    }
  }

  func refreshVisible(limit: Int? = nil, manual: Bool = false) async -> [UsageSnapshot] {
    let accounts = await SharedStore.shared.displayAccounts(limit: limit)
    return await refresh(accountIDs: accounts.map(\.id), manual: manual)
  }
}
