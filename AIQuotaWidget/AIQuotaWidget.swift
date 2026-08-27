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

private enum WidgetEntryLoader {
  static func placeholder() -> AIQuotaEntry {
    let account = AccountRecord(provider: .codex, label: "Codex · Work")
    let snapshot = UsageSnapshot(
      accountID: account.id,
      provider: .codex,
      windows: [
        UsageWindow(id: "5h", label: "5h", remainingPercent: 72, resetAt: .now.addingTimeInterval(7_200)),
        UsageWindow(id: "week", label: "周", remainingPercent: 48, resetAt: .now.addingTimeInterval(172_800)),
      ]
    )
    return AIQuotaEntry(
      date: .now,
      items: [WidgetDisplayItem(account: account, snapshot: snapshot)],
      selectedAccountIDs: [account.id],
      cooldowns: [:],
      lastAttemptAt: .now,
      credentialAccessIssue: nil
    )
  }

  static func enabledAccounts(family: WidgetFamily) async -> [AccountRecord] {
    let accounts = await SharedStore.shared.accounts().filter(\.isEnabled)
    return Array(accounts.prefix(itemLimit(for: family)))
  }

  static func entry(accounts: [AccountRecord]) async -> AIQuotaEntry {
    var items: [WidgetDisplayItem] = []
    var cooldowns: [UUID: Date] = [:]
    for account in accounts {
      items.append(WidgetDisplayItem(account: account, snapshot: await SharedStore.shared.snapshot(for: account.id)))
      if let until = await SharedStore.shared.cooldownUntil(accountID: account.id) {
        cooldowns[account.id] = until
      }
    }
    let issue: String?
    switch KeychainStore.shared.sharedAccessStatus() {
    case .available:
      issue = nil
    case .unavailable(let reason):
      issue = reason
    }
    return AIQuotaEntry(
      date: .now,
      items: items,
      selectedAccountIDs: accounts.map(\.id),
      cooldowns: cooldowns,
      lastAttemptAt: .now,
      credentialAccessIssue: issue
    )
  }

  static func canRefreshCredentials() -> Bool {
    if case .available = KeychainStore.shared.sharedAccessStatus() { return true }
    return false
  }

  static func itemLimit(for family: WidgetFamily) -> Int {
    switch family {
    case .systemSmall: 1
    case .systemMedium: 3
    case .systemLarge: 7
    default: 3
    }
  }
}

struct AIQuotaLegacyProvider: TimelineProvider {
  func placeholder(in context: Context) -> AIQuotaEntry {
    WidgetEntryLoader.placeholder()
  }

  func getSnapshot(in context: Context, completion: @escaping (AIQuotaEntry) -> Void) {
    Task {
      let accounts = await WidgetEntryLoader.enabledAccounts(family: context.family)
      completion(await WidgetEntryLoader.entry(accounts: accounts))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AIQuotaEntry>) -> Void) {
    Task {
      let accounts = await WidgetEntryLoader.enabledAccounts(family: context.family)
      if WidgetEntryLoader.canRefreshCredentials() {
        _ = await CooldownAwareRefresh.shared.refresh(accountIDs: accounts.map(\.id), manual: false)
      }
      let entry = await WidgetEntryLoader.entry(accounts: accounts)
      let minutes = await SharedStore.shared.autoRefreshMinutes()
      completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(minutes * 60)))))
    }
  }
}

@available(iOS 17.0, *)
struct AIQuotaProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> AIQuotaEntry {
    WidgetEntryLoader.placeholder()
  }

  func snapshot(for configuration: AIQuotaWidgetConfigurationIntent, in context: Context) async -> AIQuotaEntry {
    await WidgetEntryLoader.entry(accounts: configuredAccounts(configuration, family: context.family))
  }

  func timeline(for configuration: AIQuotaWidgetConfigurationIntent, in context: Context) async -> Timeline<AIQuotaEntry> {
    let accounts = await configuredAccounts(configuration, family: context.family)
    if WidgetEntryLoader.canRefreshCredentials() {
      _ = await CooldownAwareRefresh.shared.refresh(accountIDs: accounts.map(\.id), manual: false)
    }
    let entry = await WidgetEntryLoader.entry(accounts: accounts)
    let minutes = await SharedStore.shared.autoRefreshMinutes()
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(minutes * 60))))
  }

  private func configuredAccounts(
    _ configuration: AIQuotaWidgetConfigurationIntent,
    family: WidgetFamily
  ) async -> [AccountRecord] {
    let enabled = await SharedStore.shared.accounts().filter(\.isEnabled)
    let filtered: [AccountRecord]
    switch configuration.mode {
    case .all:
      filtered = enabled
    case .provider:
      filtered = enabled.filter { $0.provider == configuration.provider.providerID }
    case .account:
      guard
        let rawID = configuration.account?.id,
        let id = UUID(uuidString: rawID),
        let account = enabled.first(where: { $0.id == id })
      else { return [] }
      filtered = [account]
    }
    return Array(filtered.prefix(WidgetEntryLoader.itemLimit(for: family)))
  }
}

struct AIQuotaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: AIQuotaEntry

  var body: some View {
    if #available(iOS 17.0, *) {
      content
        .containerBackground(for: .widget) { background }
        .widgetURL(URL(string: "aiquota://accounts"))
    } else {
      content
        .background(background)
        .widgetURL(URL(string: "aiquota://accounts"))
    }
  }

  private var content: some View {
    VStack(spacing: family == .systemSmall ? 7 : 8) {
      header
      if let issue = entry.credentialAccessIssue {
        signingState(issue)
      } else if entry.items.isEmpty {
        emptyState
      } else {
        ForEach(entry.items) { accountRow($0) }
      }
    }
    .padding(family == .systemSmall ? 12 : 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var background: some View {
    LinearGradient(
      colors: [Color.black.opacity(0.94), Color.black.opacity(0.82)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  @ViewBuilder private var header: some View {
    if #available(iOS 17.0, *) {
      interactiveHeader
    } else {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text("AI 额度").font(.system(size: family == .systemSmall ? 14 : 15, weight: .bold))
          if family != .systemSmall {
            Text("点小组件打开 App 刷新").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 4)
        Image(systemName: "arrow.up.forward.app")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
  }

  @available(iOS 17.0, *)
  private var interactiveHeader: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("AI 额度").font(.system(size: family == .systemSmall ? 14 : 15, weight: .bold))
        if family != .systemSmall {
          Text("点刷新按钮原地刷新").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if entry.credentialAccessIssue == nil {
        Button(intent: RefreshWidgetSelectionIntent(accountIDs: entry.selectedAccountIDs)) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 28, height: 28)
            .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("刷新当前小组件")
      }
    }
  }

  private func signingState(_ reason: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: "signature").font(.title3).foregroundStyle(.red)
      Text("签名权限异常").font(.caption).fontWeight(.bold).foregroundStyle(.red)
      Text(family == .systemSmall ? "App 与小组件无法共享登录凭据" : reason)
        .font(.system(size: family == .systemSmall ? 8 : 9))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
      if family != .systemSmall {
        Text("请重新签名并保留 App Group / Keychain")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Image(systemName: "person.crop.circle.badge.plus").font(.title3)
      Text("还没有账号").font(.caption).fontWeight(.semibold)
      Text("点小组件进入设置").font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private func accountRow(_ item: WidgetDisplayItem) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(item.account.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
          if let snapshot = item.snapshot, let kind = snapshot.effectiveErrorKind {
            Text(statusText(snapshot: snapshot, kind: kind, accountID: item.account.id))
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(statusColor(kind))
              .lineLimit(1)
          }
        }
        if let snapshot = item.snapshot {
          snapshotBody(snapshot)
        } else {
          Text("等待首次刷新").font(.system(size: 9)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 2)
      if family != .systemSmall, entry.credentialAccessIssue == nil {
        if #available(iOS 17.0, *) {
          accountRefreshButton(item)
        }
      }
    }
  }

  @available(iOS 17.0, *)
  private func accountRefreshButton(_ item: WidgetDisplayItem) -> some View {
    Button(intent: RefreshAccountIntent(accountID: item.account.id.uuidString)) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 24, height: 24)
        .background(Color.secondary.opacity(0.14), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("刷新 \(item.account.label)")
  }

  private func statusText(snapshot: UsageSnapshot, kind: ProviderErrorKind, accountID: UUID) -> String {
    let base = snapshot.stale && hasCachedData(snapshot) ? "缓存 · \(kind.shortLabel)" : kind.shortLabel
    guard let until = entry.cooldowns[accountID], until > entry.date else { return base }
    return "\(base) · \(resetCountdown(until, from: entry.date)) 后重试"
  }

  @ViewBuilder private func snapshotBody(_ snapshot: UsageSnapshot) -> some View {
    if let balance = snapshot.balance {
      HStack(spacing: 6) {
        Text("余额").foregroundStyle(.secondary)
        Text("\(balance.symbol)\(balance.total, specifier: "%.2f")").fontWeight(.bold)
        if !balance.available { Text("不可用").foregroundStyle(.red) }
      }
      .font(.system(size: 10))
    } else if !snapshot.windows.isEmpty {
      HStack(spacing: family == .systemSmall ? 5 : 8) {
        ForEach(Array(snapshot.windows.prefix(family == .systemSmall ? 2 : 3))) { quotaPill($0) }
      }
    } else if !snapshot.metrics.isEmpty {
      HStack(spacing: 8) {
        ForEach(Array(snapshot.metrics.prefix(2))) {
          Text("\($0.label) \($0.value)").font(.system(size: 9, weight: .medium))
        }
      }
    } else if let kind = snapshot.effectiveErrorKind {
      HStack(spacing: 4) {
        Image(systemName: statusIcon(kind))
        Text(kind.shortLabel)
      }
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(statusColor(kind))
    } else if let error = snapshot.errorMessage {
      Text(error).font(.system(size: 8)).foregroundStyle(.red).lineLimit(1)
    }
  }

  private func quotaPill(_ window: UsageWindow) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 2) {
        Text(window.label).foregroundStyle(.secondary)
        Text("\(Int(window.remainingPercent.rounded()))%").fontWeight(.bold)
      }
      .font(.system(size: 9))
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.18))
          Capsule()
            .fill(progressColor(window.remainingPercent))
            .frame(width: max(2, proxy.size.width * window.remainingPercent / 100))
        }
      }
      .frame(height: 3)
      if family != .systemSmall, let reset = window.resetAt, reset > entry.date {
        Text("↻ \(resetCountdown(reset, from: entry.date))")
          .font(.system(size: 7, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: 78)
  }

  private func hasCachedData(_ snapshot: UsageSnapshot) -> Bool {
    !snapshot.windows.isEmpty || !snapshot.metrics.isEmpty || snapshot.balance != nil
  }

  private func statusColor(_ kind: ProviderErrorKind) -> Color {
    switch kind {
    case .authentication, .configuration: .red
    case .rateLimited, .providerUnavailable, .network: .orange
    case .invalidResponse, .unknown: .yellow
    }
  }

  private func statusIcon(_ kind: ProviderErrorKind) -> String {
    switch kind {
    case .authentication: "person.crop.circle.badge.exclamationmark"
    case .rateLimited: "hourglass"
    case .providerUnavailable: "exclamationmark.icloud"
    case .network: "wifi.exclamationmark"
    case .invalidResponse: "exclamationmark.triangle"
    case .configuration: "gear.badge.xmark"
    case .unknown: "exclamationmark.circle"
    }
  }

  private func resetCountdown(_ date: Date, from now: Date) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(max(1, minutes))m"
  }

  private func progressColor(_ remaining: Double) -> Color {
    if remaining <= 15 { return .red }
    if remaining <= 35 { return .orange }
    return .green
  }
}

struct AIQuotaWidget: Widget {
  let kind = AppConfig.widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AIQuotaLegacyProvider()) { entry in
      AIQuotaWidgetView(entry: entry)
    }
    .configurationDisplayName("AI 额度")
    .description("Codex、Claude、Kimi 等 AI 额度。点小组件可打开 App 刷新。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@available(iOS 17.0, *)
struct AIQuotaInteractiveWidget: Widget {
  let kind = AppConfig.widgetKind

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: AIQuotaWidgetConfigurationIntent.self,
      provider: AIQuotaProvider()
    ) { entry in
      AIQuotaWidgetView(entry: entry)
    }
    .configurationDisplayName("AI 额度")
    .description("Codex、Claude、Kimi 等 AI 额度，支持选择 Provider 或账号并原地刷新。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}
