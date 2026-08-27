import Foundation

actor SharedStore {
  static let shared = SharedStore()
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private enum Key {
    static let accounts = "accounts.v1"
    static let autoRefreshMinutes = "autoRefreshMinutes.v1"
    static let visibleAccountIDs = "visibleAccountIDs.v1"
    static func snapshot(_ id: UUID) -> String { "snapshot.\(id.uuidString)" }
    static func cooldown(_ id: UUID) -> String { "cooldown.\(id.uuidString)" }
  }
  init() { defaults = UserDefaults(suiteName: AppConfig.appGroup) ?? .standard; encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601 }
  func accounts() -> [AccountRecord] { guard let data=defaults.data(forKey:Key.accounts),let value=try? decoder.decode([AccountRecord].self,from:data) else{return []};return value.sorted{lhs,rhs in lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt} }
  func account(id:UUID)->AccountRecord?{accounts().first{$0.id==id}}
  func saveAccounts(_ accounts:[AccountRecord]){guard let data=try? encoder.encode(accounts)else{return};defaults.set(data,forKey:Key.accounts)}
  func upsertAccount(_ account:AccountRecord){var list=accounts();if let idx=list.firstIndex(where:{$0.id==account.id}){list[idx]=account}else{list.append(account)};saveAccounts(list)}
  func removeAccount(_ id:UUID){saveAccounts(accounts().filter{$0.id != id});defaults.removeObject(forKey:Key.snapshot(id));defaults.removeObject(forKey:Key.cooldown(id));setVisibleAccountIDs(visibleAccountIDs().filter{$0 != id})}
  func snapshot(for id:UUID)->UsageSnapshot?{guard let data=defaults.data(forKey:Key.snapshot(id))else{return nil};return try? decoder.decode(UsageSnapshot.self,from:data)}
  func saveSnapshot(_ snapshot:UsageSnapshot){var normalized=snapshot;if normalized.errorMessage==nil{normalized.errorKind=nil;normalized.stale=false}else if normalized.errorKind==nil{normalized.errorKind=ProviderErrorClassifier.classify(message:normalized.errorMessage)};guard let data=try? encoder.encode(normalized)else{return};defaults.set(data,forKey:Key.snapshot(normalized.accountID))}
  func markSnapshotStale(accountID:UUID,message:String,kind:ProviderErrorKind?=nil){guard var cached=snapshot(for:accountID)else{return};cached.stale=true;cached.errorMessage=message;cached.errorKind=kind ?? ProviderErrorClassifier.classify(message:message);saveSnapshot(cached)}
  func setCooldown(accountID:UUID,until:Date){defaults.set(until.timeIntervalSince1970,forKey:Key.cooldown(accountID))}
  func cooldownUntil(accountID:UUID,now:Date=Date())->Date?{let value=defaults.double(forKey:Key.cooldown(accountID));guard value>now.timeIntervalSince1970 else{if value>0{defaults.removeObject(forKey:Key.cooldown(accountID))};return nil};return Date(timeIntervalSince1970:value)}
  func clearCooldown(accountID:UUID){defaults.removeObject(forKey:Key.cooldown(accountID))}
  func autoRefreshMinutes()->Int{let value=defaults.integer(forKey:Key.autoRefreshMinutes);return [10,15,30,60,120].contains(value) ? value : 15}
  func setAutoRefreshMinutes(_ minutes:Int){defaults.set(minutes,forKey:Key.autoRefreshMinutes)}
  func visibleAccountIDs()->[UUID]{guard let strings=defaults.array(forKey:Key.visibleAccountIDs) as? [String]else{return []};return strings.compactMap(UUID.init(uuidString:))}
  func setVisibleAccountIDs(_ ids:[UUID]){defaults.set(ids.map(\.uuidString),forKey:Key.visibleAccountIDs)}
  func displayAccounts(limit:Int?=nil)->[AccountRecord]{let enabled=accounts().filter(\.isEnabled);let selected=visibleAccountIDs();let result:[AccountRecord];if selected.isEmpty{result=enabled}else{let map=Dictionary(uniqueKeysWithValues:enabled.map{($0.id,$0)});result=selected.compactMap{map[$0]}};if let limit{return Array(result.prefix(limit))};return result}
}
