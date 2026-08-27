import AppIntents
import SwiftUI
import WidgetKit

struct AIQuotaEntry: TimelineEntry {
  let date: Date
  let items: [WidgetDisplayItem]
  let selectedAccountIDs: [UUID]
  let cooldowns: [UUID: Date]
  let lastAttemptAt: Date
  let credentialAccessIssue: String?
}

struct AIQuotaProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> AIQuotaEntry {
    let account = AccountRecord(provider: .codex, label: "Codex · Work")
    return AIQuotaEntry(date: .now, items: [WidgetDisplayItem(account: account, snapshot: UsageSnapshot(accountID: account.id, provider: .codex, windows: [UsageWindow(id: "5h", label: "5h", remainingPercent: 72, resetAt: .now.addingTimeInterval(7200)), UsageWindow(id: "week", label: "周", remainingPercent: 48, resetAt: .now.addingTimeInterval(172800))]))], selectedAccountIDs: [account.id], cooldowns: [:], lastAttemptAt: .now, credentialAccessIssue: nil)
  }

  func snapshot(for configuration: AIQuotaWidgetConfigurationIntent, in context: Context) async -> AIQuotaEntry { await makeEntry(configuration: configuration, family: context.family) }

  func timeline(for configuration: AIQuotaWidgetConfigurationIntent, in context: Context) async -> Timeline<AIQuotaEntry> {
    let accounts = await configuredAccounts(configuration, family: context.family)
    if case .available = KeychainStore.shared.sharedAccessStatus() { _ = await CooldownAwareRefresh.shared.refresh(accountIDs: accounts.map(\.id), manual: false) }
    let entry = await makeEntry(configuration: configuration, family: context.family, accounts: accounts)
    let minutes = await SharedStore.shared.autoRefreshMinutes()
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(minutes * 60))))
  }

  private func makeEntry(configuration: AIQuotaWidgetConfigurationIntent, family: WidgetFamily, accounts suppliedAccounts: [AccountRecord]? = nil) async -> AIQuotaEntry {
    let accounts = suppliedAccounts ?? []
    let resolved = suppliedAccounts != nil ? accounts : await configuredAccounts(configuration, family: family)
    var items:[WidgetDisplayItem]=[];var cooldowns:[UUID:Date]=[:]
    for account in resolved { items.append(WidgetDisplayItem(account:account,snapshot:await SharedStore.shared.snapshot(for:account.id)));if let until=await SharedStore.shared.cooldownUntil(accountID:account.id){cooldowns[account.id]=until} }
    let issue:String?;switch KeychainStore.shared.sharedAccessStatus(){case .available:issue=nil;case .unavailable(let reason):issue=reason}
    return AIQuotaEntry(date:.now,items:items,selectedAccountIDs:resolved.map(\.id),cooldowns:cooldowns,lastAttemptAt:.now,credentialAccessIssue:issue)
  }

  private func configuredAccounts(_ configuration: AIQuotaWidgetConfigurationIntent, family: WidgetFamily) async -> [AccountRecord] { let enabled=await SharedStore.shared.accounts().filter(\.isEnabled);let filtered:[AccountRecord];switch configuration.mode{case .all:filtered=enabled;case .provider:filtered=enabled.filter{$0.provider==configuration.provider.providerID};case .account:guard let rawID=configuration.account?.id,let id=UUID(uuidString:rawID),let account=enabled.first(where:{$0.id==id})else{return []};filtered=[account]};return Array(filtered.prefix(itemLimit(for:family))) }
  private func itemLimit(for family:WidgetFamily)->Int{switch family{case .systemSmall:1;case .systemMedium:3;case .systemLarge:7;default:3}}
}

struct AIQuotaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: AIQuotaEntry
  var body: some View { VStack(spacing:family == .systemSmall ? 7:8){header;if let issue=entry.credentialAccessIssue{signingState(issue)}else if entry.items.isEmpty{emptyState}else{ForEach(entry.items){accountRow($0)}}}.padding(family == .systemSmall ? 12:14).containerBackground(for:.widget){LinearGradient(colors:[Color.black.opacity(0.94),Color.black.opacity(0.82)],startPoint:.topLeading,endPoint:.bottomTrailing)}.widgetURL(URL(string:"aiquota://accounts")) }
  private var header:some View{HStack(spacing:8){VStack(alignment:.leading,spacing:1){Text("AI 额度").font(.system(size:family == .systemSmall ? 14:15,weight:.bold));if family != .systemSmall{Text("点 ↻ 原地刷新，不打开 App").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)}};Spacer(minLength:4);if entry.credentialAccessIssue == nil{Button(intent:RefreshWidgetSelectionIntent(accountIDs:entry.selectedAccountIDs)){Image(systemName:"arrow.clockwise").font(.system(size:13,weight:.bold)).frame(width:28,height:28).background(.thinMaterial,in:Circle())}.buttonStyle(.plain).accessibilityLabel("刷新当前小组件")}}}
  private func signingState(_ reason:String)->some View{VStack(spacing:6){Image(systemName:"signature").font(.title3).foregroundStyle(.red);Text("签名权限异常").font(.caption).fontWeight(.bold).foregroundStyle(.red);Text(family == .systemSmall ? "App 与小组件无法共享登录凭据" : reason).font(.system(size:family == .systemSmall ? 8:9)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3);if family != .systemSmall{Text("请重新签名并保留 App Group / Keychain").font(.system(size:8,weight:.medium)).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,maxHeight:.infinity)}
  private var emptyState:some View{VStack(spacing:6){Image(systemName:"person.crop.circle.badge.plus").font(.title3);Text("还没有账号").font(.caption).fontWeight(.semibold);Text("点小组件进入设置").font(.caption2).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)}
  @ViewBuilder private func accountRow(_ item:WidgetDisplayItem)->some View{HStack(spacing:8){VStack(alignment:.leading,spacing:4){HStack(spacing:5){Text(item.account.label).font(.system(size:11,weight:.semibold)).lineLimit(1);if let snapshot=item.snapshot,let kind=snapshot.effectiveErrorKind{Text(statusText(snapshot:snapshot,kind:kind,accountID:item.account.id)).font(.system(size:8,weight:.bold)).foregroundStyle(statusColor(kind)).lineLimit(1)}};if let snapshot=item.snapshot{snapshotBody(snapshot).invalidatableContent(true)}else{Text("等待首次刷新").font(.system(size:9)).foregroundStyle(.secondary)}};Spacer(minLength:2);if family != .systemSmall{Button(intent:RefreshAccountIntent(accountID:item.account.id.uuidString)){Image(systemName:"arrow.clockwise").font(.system(size:10,weight:.semibold)).frame(width:24,height:24).background(Color.secondary.opacity(0.14),in:Circle())}.buttonStyle(.plain).accessibilityLabel("刷新 \(item.account.label)")}}}
  private func statusText(snapshot:UsageSnapshot,kind:ProviderErrorKind,accountID:UUID)->String{let base=snapshot.stale&&hasCachedData(snapshot) ? "缓存 · \(kind.shortLabel)":kind.shortLabel;guard let until=entry.cooldowns[accountID],until>entry.date else{return base};return "\(base) · \(resetCountdown(until,from:entry.date)) 后重试"}
  @ViewBuilder private func snapshotBody(_ snapshot:UsageSnapshot)->some View{if let balance=snapshot.balance{HStack(spacing:6){Text("余额").foregroundStyle(.secondary);Text("\(balance.symbol)\(balance.total, specifier: "%.2f")").fontWeight(.bold);if !balance.available{Text("不可用").foregroundStyle(.red)}}.font(.system(size:10))}else if !snapshot.windows.isEmpty{HStack(spacing:family == .systemSmall ? 5:8){ForEach(Array(snapshot.windows.prefix(family == .systemSmall ? 2:3))){quotaPill($0)}}}else if !snapshot.metrics.isEmpty{HStack(spacing:8){ForEach(Array(snapshot.metrics.prefix(2))){Text("\($0.label) \($0.value)").font(.system(size:9,weight:.medium))}}}else if let kind=snapshot.effectiveErrorKind{HStack(spacing:4){Image(systemName:statusIcon(kind));Text(kind.shortLabel)}.font(.system(size:9,weight:.semibold)).foregroundStyle(statusColor(kind))}else if let error=snapshot.errorMessage{Text(error).font(.system(size:8)).foregroundStyle(.red).lineLimit(1)}}
  private func hasCachedData(_ s:UsageSnapshot)->Bool{!s.windows.isEmpty||!s.metrics.isEmpty||s.balance != nil}
  private func statusColor(_ k:ProviderErrorKind)->Color{switch k{case .authentication,.configuration:.red;case .rateLimited,.providerUnavailable,.network:.orange;case .invalidResponse,.unknown:.yellow}}
  private func statusIcon(_ k:ProviderErrorKind)->String{switch k{case .authentication:"person.crop.circle.badge.exclamationmark";case .rateLimited:"hourglass";case .providerUnavailable:"exclamationmark.icloud";case .network:"wifi.exclamationmark";case .invalidResponse:"exclamationmark.triangle";case .configuration:"gear.badge.xmark";case .unknown:"exclamationmark.circle"}}
  private func quotaPill(_ w:UsageWindow)->some View{VStack(alignment:.leading,spacing:2){HStack(spacing:2){Text(w.label).foregroundStyle(.secondary);Text("\(Int(w.remainingPercent.rounded()))%").fontWeight(.bold)}.font(.system(size:9));GeometryReader{p in ZStack(alignment:.leading){Capsule().fill(Color.secondary.opacity(0.18));Capsule().fill(progressColor(w.remainingPercent)).frame(width:max(2,p.size.width*w.remainingPercent/100))}}.frame(height:3);if family != .systemSmall,let reset=w.resetAt,reset>entry.date{Text("↻ \(resetCountdown(reset,from:entry.date))").font(.system(size:7,weight:.medium)).foregroundStyle(.secondary).lineLimit(1)}}.frame(maxWidth:78)}
  private func resetCountdown(_ d:Date,from n:Date)->String{let s=max(0,Int(d.timeIntervalSince(n)));let days=s/86400,h=(s%86400)/3600,m=(s%3600)/60;if days>0{return "\(days)d \(h)h"};if h>0{return "\(h)h \(m)m"};return "\(max(1,m))m"}
  private func progressColor(_ r:Double)->Color{if r<=15{return .red};if r<=35{return .orange};return .green}
}

struct AIQuotaWidget:Widget{let kind=AppConfig.widgetKind;var body:some WidgetConfiguration{AppIntentConfiguration(kind:kind,intent:AIQuotaWidgetConfigurationIntent.self,provider:AIQuotaProvider()){entry in AIQuotaWidgetView(entry:entry)}.configurationDisplayName("AI 额度").description("Codex、Claude、Kimi 等 AI 额度。支持单 Provider、单账号和小组件内刷新。").supportedFamilies([.systemSmall,.systemMedium,.systemLarge]).contentMarginsDisabled()}}
