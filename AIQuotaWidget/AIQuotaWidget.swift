import SwiftUI
import WidgetKit

struct AIQuotaEntry: TimelineEntry {
  let date: Date
  let items: [WidgetDisplayItem]
  let lastAttemptAt: Date
}

struct AIQuotaProvider: TimelineProvider {
  func placeholder(in context: Context) -> AIQuotaEntry {
    AIQuotaEntry(date: .now, items: [WidgetDisplayItem(account: AccountRecord(provider: .codex, label: "Codex · Work"), snapshot: UsageSnapshot(accountID: UUID(), provider: .codex, windows: [UsageWindow(id: "5h", label: "5h", remainingPercent: 72, resetAt: .now.addingTimeInterval(7200)), UsageWindow(id: "week", label: "周", remainingPercent: 48, resetAt: .now.addingTimeInterval(172800))]))], lastAttemptAt: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (AIQuotaEntry) -> Void) {
    Task { completion(await makeEntry(family: context.family)) }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AIQuotaEntry>) -> Void) {
    Task {
      let limit = itemLimit(for: context.family)
      _ = await UsageService.shared.refreshVisible(limit: limit)
      let entry = await makeEntry(family: context.family)
      let minutes = await SharedStore.shared.autoRefreshMinutes()
      completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(minutes * 60)))))
    }
  }

  private func makeEntry(family: WidgetFamily) async -> AIQuotaEntry {
    let accounts = await SharedStore.shared.displayAccounts(limit: itemLimit(for: family))
    var items: [WidgetDisplayItem] = []
    for account in accounts { items.append(WidgetDisplayItem(account: account, snapshot: await SharedStore.shared.snapshot(for: account.id))) }
    return AIQuotaEntry(date: .now, items: items, lastAttemptAt: .now)
  }

  private func itemLimit(for family: WidgetFamily) -> Int {
    switch family { case .systemSmall: 1; case .systemMedium: 3; case .systemLarge: 7; default: 3 }
  }
}

struct AIQuotaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: AIQuotaEntry

  var body: some View {
    VStack(spacing: family == .systemSmall ? 7 : 8) {
      header
      if entry.items.isEmpty { emptyState } else { ForEach(entry.items) { accountRow($0) } }
    }
    .padding(family == .systemSmall ? 12 : 14)
    .containerBackground(for: .widget) {
      LinearGradient(colors: [Color.black.opacity(0.94), Color.black.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .widgetURL(URL(string: "aiquota://accounts"))
  }

  private var header: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("AI 额度").font(.system(size: family == .systemSmall ? 14 : 15, weight: .bold))
        if family != .systemSmall { Text("点 ↻ 原地刷新，不打开 App").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 4)
      Button(intent: RefreshAllVisibleIntent()) {
        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold)).frame(width: 28, height: 28).background(.thinMaterial, in: Circle())
      }.buttonStyle(.plain).accessibilityLabel("刷新全部额度")
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Image(systemName: "person.crop.circle.badge.plus").font(.title3)
      Text("还没有账号").font(.caption).fontWeight(.semibold)
      Text("点小组件进入设置").font(.caption2).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func accountRow(_ item: WidgetDisplayItem) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(item.account.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
          if item.snapshot?.stale == true { Text("缓存").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
        }
        if let snapshot = item.snapshot { snapshotBody(snapshot).invalidatableContent(true) }
        else { Text("等待首次刷新").font(.system(size: 9)).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 2)
      if family != .systemSmall {
        Button(intent: RefreshAccountIntent(accountID: item.account.id.uuidString)) {
          Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24).background(Color.secondary.opacity(0.14), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("刷新 \(item.account.label)")
      }
    }
  }

  @ViewBuilder
  private func snapshotBody(_ snapshot: UsageSnapshot) -> some View {
    if let balance = snapshot.balance {
      HStack(spacing: 6) {
        Text("余额").foregroundStyle(.secondary)
        Text("\(balance.symbol)\(balance.total, specifier: "%.2f")").fontWeight(.bold)
        if !balance.available { Text("不可用").foregroundStyle(.red) }
      }.font(.system(size: 10))
    } else if !snapshot.windows.isEmpty {
      HStack(spacing: family == .systemSmall ? 5 : 8) {
        ForEach(Array(snapshot.windows.prefix(family == .systemSmall ? 2 : 3))) { quotaPill($0) }
      }
    } else if !snapshot.metrics.isEmpty {
      HStack(spacing: 8) { ForEach(Array(snapshot.metrics.prefix(2))) { Text("\($0.label) \($0.value)").font(.system(size: 9, weight: .medium)) } }
    } else if let error = snapshot.errorMessage {
      Text(error).font(.system(size: 8)).foregroundStyle(.red).lineLimit(1)
    }
  }

  private func quotaPill(_ window: UsageWindow) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 2) {
        Text(window.label).foregroundStyle(.secondary)
        Text("\(Int(window.remainingPercent.rounded()))%").fontWeight(.bold)
      }.font(.system(size: 9))
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.18))
          Capsule().fill(progressColor(window.remainingPercent)).frame(width: max(2, proxy.size.width * window.remainingPercent / 100))
        }
      }.frame(height: 3)
      if family != .systemSmall, let reset = window.resetAt, reset > entry.date {
        Text("↻ \(resetCountdown(reset, from: entry.date))").font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
      }
    }.frame(maxWidth: 78)
  }

  private func resetCountdown(_ date: Date, from now: Date) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86400, hours = (seconds % 86400) / 3600, minutes = (seconds % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(max(1, minutes))m"
  }

  private func progressColor(_ remaining: Double) -> Color {
    if remaining <= 15 { return .red }; if remaining <= 35 { return .orange }; return .green
  }
}

struct AIQuotaWidget: Widget {
  let kind = AppConfig.widgetKind
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AIQuotaProvider()) { AIQuotaWidgetView(entry: $0) }
      .configurationDisplayName("AI 额度")
      .description("Codex、Claude、Kimi 等 AI 额度。支持在小组件内直接刷新。")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
      .contentMarginsDisabled()
  }
}
