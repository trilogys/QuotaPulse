import Foundation

/// Storage used by the single-profile compatibility build. It deliberately uses
/// the app's own UserDefaults container so no App Group entitlement is needed.
actor SingleProfileStore {
  static let shared = SingleProfileStore()

  private let defaults = UserDefaults.standard
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private enum Key {
    static let accounts = "single.accounts.v1"
    static func snapshot(_ id: UUID) -> String { "single.snapshot.\(id.uuidString)" }
  }

  init() {
    encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
  }

  func accounts() -> [AccountRecord] {
    guard let data = defaults.data(forKey: Key.accounts),
          let value = try? decoder.decode([AccountRecord].self, from: data) else { return [] }
    return value.sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
  }

  func saveAccounts(_ accounts: [AccountRecord]) {
    if let data = try? encoder.encode(accounts) { defaults.set(data, forKey: Key.accounts) }
  }

  func upsert(_ account: AccountRecord) {
    var list = accounts()
    if let i = list.firstIndex(where: { $0.id == account.id }) { list[i] = account } else { list.append(account) }
    saveAccounts(list)
  }

  func remove(_ id: UUID) {
    saveAccounts(accounts().filter { $0.id != id })
    defaults.removeObject(forKey: Key.snapshot(id))
  }

  func snapshot(_ id: UUID) -> UsageSnapshot? {
    guard let data = defaults.data(forKey: Key.snapshot(id)) else { return nil }
    return try? decoder.decode(UsageSnapshot.self, from: data)
  }

  func save(_ snapshot: UsageSnapshot) {
    if let data = try? encoder.encode(snapshot) { defaults.set(data, forKey: Key.snapshot(snapshot.accountID)) }
  }
}
