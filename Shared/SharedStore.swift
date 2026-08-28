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
    static let dashboardTheme = "dashboardTheme.v1"
    static let proxyConfiguration = "proxyConfiguration.v1"
    static let aggregateHistory = "aggregateHistory.v1"
    static func snapshot(_ id: UUID) -> String { "snapshot.\(id.uuidString)" }
    static func history(_ id: UUID) -> String { "usageHistory.\(id.uuidString).v1" }
    static func historyInitialized(_ id: UUID) -> String { "usageHistoryInitialized.\(id.uuidString).v1" }
    static func cooldown(_ id: UUID) -> String { "cooldown.\(id.uuidString)" }
  }
  init() {
    let canShareCredentials: Bool
    if case .available = KeychainStore.shared.sharedAccessStatus() {
      canShareCredentials = true
    } else {
      canShareCredentials = false
    }
    if let appGroup = AppConfig.appGroup, AppConfig.isWidgetExtension || canShareCredentials {
      defaults = UserDefaults(suiteName: appGroup) ?? .standard
    } else {
      defaults = .standard
    }
    encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
  }
  func accounts() -> [AccountRecord] { guard let data=defaults.data(forKey:Key.accounts),let value=try? decoder.decode([AccountRecord].self,from:data) else{return []};return value.sorted{lhs,rhs in lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt} }
  func account(id:UUID)->AccountRecord?{accounts().first{$0.id==id}}
  func saveAccounts(_ accounts:[AccountRecord]){guard let data=try? encoder.encode(accounts)else{return};defaults.set(data,forKey:Key.accounts)}
  func upsertAccount(_ account:AccountRecord){var list=accounts();if let idx=list.firstIndex(where:{$0.id==account.id}){list[idx]=account}else{list.append(account)};saveAccounts(list)}
  func removeAccount(_ id:UUID){saveAccounts(accounts().filter{$0.id != id});defaults.removeObject(forKey:Key.snapshot(id));defaults.removeObject(forKey:Key.history(id));defaults.removeObject(forKey:Key.historyInitialized(id));defaults.removeObject(forKey:Key.cooldown(id));setVisibleAccountIDs(visibleAccountIDs().filter{$0 != id})}
  func snapshot(for id:UUID)->UsageSnapshot?{guard let data=defaults.data(forKey:Key.snapshot(id))else{return nil};return try? decoder.decode(UsageSnapshot.self,from:data)}
  func saveSnapshot(_ snapshot:UsageSnapshot){var normalized=snapshot;if normalized.errorMessage==nil{normalized.errorKind=nil;normalized.stale=false}else if normalized.errorKind==nil{normalized.errorKind=ProviderErrorClassifier.classify(message:normalized.errorMessage)};guard let data=try? encoder.encode(normalized)else{return};defaults.set(data,forKey:Key.snapshot(normalized.accountID));if normalized.errorMessage==nil && !normalized.stale,let sample=UsageHistorySample(snapshot:normalized){appendHistory(sample)}}
  func markSnapshotStale(accountID:UUID,message:String,kind:ProviderErrorKind?=nil){guard var cached=snapshot(for:accountID)else{return};cached.stale=true;cached.errorMessage=message;cached.errorKind=kind ?? ProviderErrorClassifier.classify(message:message);saveSnapshot(cached)}
  func setCooldown(accountID:UUID,until:Date){defaults.set(until.timeIntervalSince1970,forKey:Key.cooldown(accountID))}
  func cooldownUntil(accountID:UUID,now:Date=Date())->Date?{let value=defaults.double(forKey:Key.cooldown(accountID));guard value>now.timeIntervalSince1970 else{if value>0{defaults.removeObject(forKey:Key.cooldown(accountID))};return nil};return Date(timeIntervalSince1970:value)}
  func clearCooldown(accountID:UUID){defaults.removeObject(forKey:Key.cooldown(accountID))}
  func autoRefreshMinutes()->Int{let value=defaults.integer(forKey:Key.autoRefreshMinutes);return [10,15,30,60,120].contains(value) ? value : 15}
  func setAutoRefreshMinutes(_ minutes:Int){defaults.set(minutes,forKey:Key.autoRefreshMinutes)}
  func dashboardTheme()->DashboardTheme{DashboardTheme(rawValue:defaults.string(forKey:Key.dashboardTheme) ?? "") ?? .daylight}
  func setDashboardTheme(_ theme:DashboardTheme){defaults.set(theme.rawValue,forKey:Key.dashboardTheme)}
  func aggregateHistory()->Bool{defaults.bool(forKey:Key.aggregateHistory)}
  func setAggregateHistory(_ enabled:Bool){defaults.set(enabled,forKey:Key.aggregateHistory)}
  func proxyConfiguration()->AppProxyConfiguration{guard let data=defaults.data(forKey:Key.proxyConfiguration),let value=try? decoder.decode(AppProxyConfiguration.self,from:data)else{return .disabled};return value}
  func setProxyConfiguration(_ value:AppProxyConfiguration){guard let data=try? encoder.encode(value)else{return};defaults.set(data,forKey:Key.proxyConfiguration)}
  func visibleAccountIDs()->[UUID]{guard let strings=defaults.array(forKey:Key.visibleAccountIDs) as? [String]else{return []};return strings.compactMap(UUID.init(uuidString:))}
  func setVisibleAccountIDs(_ ids:[UUID]){defaults.set(ids.map(\.uuidString),forKey:Key.visibleAccountIDs)}
  func displayAccounts(limit:Int?=nil)->[AccountRecord]{let enabled=accounts().filter(\.isEnabled);let selected=visibleAccountIDs();let result:[AccountRecord];if selected.isEmpty{result=enabled}else{let map=Dictionary(uniqueKeysWithValues:enabled.map{($0.id,$0)});result=selected.compactMap{map[$0]}};if let limit{return Array(result.prefix(limit))};return result}
  func history(accountIDs:[UUID]?=nil)->[UsageHistorySample]{let ids=accountIDs ?? accounts().map(\.id);for id in ids where !defaults.bool(forKey:Key.historyInitialized(id)){if let cached=snapshot(for:id),cached.errorMessage==nil,!cached.stale,cached.fetchedAt >= Date().addingTimeInterval(-31*86_400),let sample=UsageHistorySample(snapshot:cached){appendHistory(sample)};defaults.set(true,forKey:Key.historyInitialized(id))};return ids.flatMap{history(for:$0)}.sorted{$0.recordedAt < $1.recordedAt}}
  func clearHistory(){for account in accounts(){defaults.removeObject(forKey:Key.history(account.id));defaults.set(true,forKey:Key.historyInitialized(account.id))}}

  private func history(for id:UUID)->[UsageHistorySample]{guard let data=defaults.data(forKey:Key.history(id)),let value=try? decoder.decode([UsageHistorySample].self,from:data)else{return []};return value}
  private func appendHistory(_ sample:UsageHistorySample){var values=history(for:sample.accountID).filter{$0.recordedAt >= Date().addingTimeInterval(-31*86_400)};if let last=values.last,last.kind==sample.kind,sample.recordedAt.timeIntervalSince(last.recordedAt)<300{values[values.count-1]=sample}else{values.append(sample)};if values.count>3000{values=Array(values.suffix(3000))};guard let data=try? encoder.encode(values)else{return};defaults.set(data,forKey:Key.history(sample.accountID));defaults.set(true,forKey:Key.historyInitialized(sample.accountID))}
}
