import Charts
import Foundation
import SwiftUI

private enum HistoryRange: String, CaseIterable, Identifiable {
  case today
  case week
  case month

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today: "今天"
    case .week: "近 7 天"
    case .month: "近 30 天"
    }
  }

  func startDate(now: Date = .now, calendar: Calendar = .current) -> Date {
    switch self {
    case .today:
      return calendar.startOfDay(for: now)
    case .week:
      return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
    case .month:
      return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
    }
  }

  func bucket(_ date: Date, calendar: Calendar = .current) -> Date {
    switch self {
    case .today:
      return calendar.dateInterval(of: .hour, for: date)?.start ?? date
    case .week, .month:
      return calendar.startOfDay(for: date)
    }
  }
}

private enum HistoryChartMode: String, CaseIterable, Identifiable {
  case ring
  case bar
  case line
  case heatmap

  var id: String { rawValue }

  var title: String {
    switch self {
    case .ring: "圆环"
    case .bar: "柱状"
    case .line: "折线"
    case .heatmap: "热力图"
    }
  }

  var systemImage: String {
    switch self {
    case .ring: "chart.donut"
    case .bar: "chart.bar.fill"
    case .line: "chart.xyaxis.line"
    case .heatmap: "square.grid.3x3.fill"
    }
  }
}

private struct HistoryPoint: Identifiable {
  var id: Date { date }
  let date: Date
  let value: Double
}

private struct HistorySeries: Identifiable {
  let id: String
  let name: String
  let provider: ProviderID
  let kind: UsageHistoryMetricKind
  let unit: String
  let points: [HistoryPoint]
}

private struct HistoryHeatmapPoint: Identifiable {
  var id: Date { date }
  let date: Date
  let value: Double
  let provider: ProviderID
  let unit: String
}

private enum CodexTokenAggregationMode: String, CaseIterable, Identifiable {
  case daily
  case weekly
  case cumulative

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .daily: "每日"
    case .weekly: "每周"
    case .cumulative: "累计"
    }
  }
}

private struct CodexTokenHeatmapDay: Identifiable {
  var id: Date { date }
  let date: Date
  let value: Int64
  let dailyTokens: Int64
  let isFuture: Bool
}

private struct CodexTokenHeatmapWeek: Identifiable {
  var id: Date { startDate }
  let startDate: Date
  let days: [CodexTokenHeatmapDay]
}

private struct CodexOfficialTokenActivityCard: View {
  @Environment(\.dashboardTheme) private var theme
  let usage: CodexTokenUsageSummary

  @State private var aggregation: CodexTokenAggregationMode = .daily
  @State private var selectedDate: Date?

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = .current
    value.timeZone = .current
    value.firstWeekday = 2
    return value
  }

  private var today: Date { calendar.startOfDay(for: .now) }

  private var rawDailyValues: [Date: Int64] {
    usage.dailyUsageBuckets.reduce(into: [:]) { values, bucket in
      let date = calendar.startOfDay(for: bucket.startDate)
      values[date, default: 0] += max(0, bucket.tokens)
    }
  }

  private var gridDates: [Date] {
    let endWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
    let start = calendar.date(byAdding: .weekOfYear, value: -52, to: endWeek) ?? endWeek
    return (0..<(53 * 7)).compactMap {
      calendar.date(byAdding: .day, value: $0, to: start)
    }
  }

  private var displayValues: [Date: Int64] {
    switch aggregation {
    case .daily:
      return rawDailyValues
    case .weekly:
      var totals: [Date: Int64] = [:]
      for (date, tokens) in rawDailyValues {
        let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        totals[week, default: 0] += tokens
      }
      return Dictionary(uniqueKeysWithValues: gridDates.filter { $0 <= today }.map { date in
        let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (date, totals[week] ?? 0)
      })
    case .cumulative:
      let visibleTotal = gridDates.reduce(Int64(0)) { $0 + (rawDailyValues[$1] ?? 0) }
      var running = max(0, (usage.lifetimeTokens ?? visibleTotal) - visibleTotal)
      var values: [Date: Int64] = [:]
      for date in gridDates where date <= today {
        running += rawDailyValues[date] ?? 0
        values[date] = running
      }
      return values
    }
  }

  private var cells: [CodexTokenHeatmapDay] {
    gridDates.map { date in
      CodexTokenHeatmapDay(
        date: date,
        value: displayValues[date] ?? 0,
        dailyTokens: rawDailyValues[date] ?? 0,
        isFuture: date > today
      )
    }
  }

  private var weeks: [CodexTokenHeatmapWeek] {
    stride(from: 0, to: cells.count, by: 7).map { index in
      let values = Array(cells[index..<min(index + 7, cells.count)])
      return CodexTokenHeatmapWeek(startDate: values[0].date, days: values)
    }
  }

  private var activeValues: [Int64] {
    cells.filter { !$0.isFuture && $0.value > 0 }.map(\.value)
  }

  private var selectedCell: CodexTokenHeatmapDay? {
    guard let selectedDate else { return nil }
    return cells.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
  }

  private var stats: [(label: LocalizedStringKey, value: String)] {
    [
      ("总计 Token", compactTokens(usage.lifetimeTokens)),
      ("峰值 Token", compactTokens(usage.peakDailyTokens)),
      ("当前连续天数", dayCount(usage.currentStreakDays)),
      ("最长连续天数", dayCount(usage.longestStreakDays)),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Codex 官方 Token 活动")
        .font(.system(size: 16, weight: .bold))
        .lineLimit(1)

      HStack(spacing: 0) {
        ForEach(Array(stats.enumerated()), id: \.offset) { item in
          if item.offset > 0 {
            Divider().frame(height: 34)
          }
          VStack(spacing: 3) {
            Text(item.element.value)
              .font(.system(size: 15, weight: .bold, design: .rounded))
              .foregroundStyle(theme.primaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.62)
            Text(item.element.label)
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.65)
          }
          .frame(maxWidth: .infinity, minHeight: 46)
        }
      }

      Divider().overlay(theme.border)

      HStack(spacing: 10) {
        Text("Token 活动")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        Picker("Token 聚合方式", selection: $aggregation) {
          ForEach(CodexTokenAggregationMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 164)
      }

      ScrollViewReader { reader in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { item in
              VStack(alignment: .leading, spacing: 4) {
                Text(monthLabel(for: item.element, isFirst: item.offset == 0))
                  .font(.system(size: 8, weight: .medium))
                  .foregroundStyle(theme.secondaryText)
                  .fixedSize()
                  .frame(width: 10, height: 12, alignment: .leading)
                VStack(spacing: 3) {
                  ForEach(item.element.days) { day in
                    heatmapCell(day)
                  }
                }
              }
              .id(item.element.id)
            }
          }
          .padding(.horizontal, 1)
        }
        .task(id: weeks.last?.id) {
          guard let last = weeks.last else { return }
          reader.scrollTo(last.id, anchor: .trailing)
        }
      }
      .frame(height: 111)

      HStack(spacing: 5) {
        Text("低")
        ForEach(1...5, id: \.self) { level in
          RoundedRectangle(cornerRadius: 2)
            .fill(color(level: level))
            .frame(width: 11, height: 11)
        }
        Text("高")
        Spacer()
        if let selectedCell {
          Text(selectedCell.date.formatted(date: .abbreviated, time: .omitted))
          Text("\(selectedLabel)：\(exactTokens(selectedCell.value))")
            .fontWeight(.semibold)
            .foregroundStyle(theme.accent(for: .codex))
        }
      }
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(theme.secondaryText)
      .lineLimit(1)
      .minimumScaleFactor(0.68)
    }
    .padding(16)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
  }

  private func heatmapCell(_ day: CodexTokenHeatmapDay) -> some View {
    Button {
      selectedDate = day.date
    } label: {
      RoundedRectangle(cornerRadius: 2.5)
        .fill(day.isFuture ? theme.surfaceRaised.opacity(0.45) : color(level: intensityLevel(day.value)))
        .frame(width: 10, height: 10)
        .overlay {
          RoundedRectangle(cornerRadius: 2.5)
            .stroke(
              selectedCell?.id == day.id ? theme.primary : Color.clear,
              lineWidth: 1.5
            )
        }
    }
    .buttonStyle(.plain)
    .disabled(day.isFuture)
    .accessibilityLabel(
      "\(day.date.formatted(date: .complete, time: .omitted))，\(selectedLabel) \(exactTokens(day.value))"
    )
  }

  private func intensityLevel(_ value: Int64) -> Int {
    guard value > 0, let maximum = activeValues.max() else { return 0 }
    let minimum = aggregation == .cumulative ? (activeValues.min() ?? 0) : 0
    guard maximum > minimum else { return 3 }
    let ratio = Double(value - minimum) / Double(maximum - minimum)
    switch ratio {
    case ..<0.12: return 1
    case ..<0.32: return 2
    case ..<0.56: return 3
    case ..<0.80: return 4
    default: return 5
    }
  }

  private func color(level: Int) -> Color {
    guard level > 0 else { return theme.surfaceRaised }
    return theme.accent(for: .codex).opacity(0.18 + Double(level) * 0.15)
  }

  private func monthLabel(for week: CodexTokenHeatmapWeek, isFirst: Bool) -> String {
    let date = isFirst
      ? week.days.first?.date
      : week.days.first(where: { calendar.component(.day, from: $0.date) == 1 })?.date
    return date?.formatted(.dateTime.month(.abbreviated)) ?? ""
  }

  private var selectedLabel: String {
    switch aggregation {
    case .daily: NSLocalizedString("当日", comment: "")
    case .weekly: NSLocalizedString("当周", comment: "")
    case .cumulative: NSLocalizedString("累计", comment: "")
    }
  }

  private func compactTokens(_ value: Int64?) -> String {
    guard let value else { return "--" }
    let number = Double(value)
    if Locale.current.identifier.lowercased().hasPrefix("zh") {
      if abs(number) >= 100_000_000 { return "\(shortDecimal(number / 100_000_000))亿" }
      if abs(number) >= 10_000 { return "\(shortDecimal(number / 10_000))万" }
    }
    if abs(number) >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
    if abs(number) >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
    if abs(number) >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
  }

  private func shortDecimal(_ value: Double) -> String {
    String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
  }

  private func exactTokens(_ value: Int64) -> String {
    "\(value.formatted(.number.grouping(.automatic))) Token"
  }

  private func dayCount(_ value: Int64?) -> String {
    guard let value else { return "--" }
    return String.localizedStringWithFormat(NSLocalizedString("%lld 天", comment: ""), value)
  }
}

struct UsageHistoryDashboard: View {
  @Environment(\.dashboardTheme) private var theme
  let history: [UsageHistorySample]
  let accounts: [AccountRecord]
  let snapshots: [UUID: UsageSnapshot]
  let selectedProvider: ProviderID?
  let aggregateProviders: Bool

  @State private var range: HistoryRange = .week
  @State private var mode: HistoryChartMode = .line

  private var rangedSamples: [UsageHistorySample] {
    let start = range.startDate()
    return history.filter { sample in
      sample.recordedAt >= start && (selectedProvider == nil || sample.provider == selectedProvider)
    }
  }

  private var providers: [ProviderID] {
    ProviderID.allCases.filter { provider in
      rangedSamples.contains { $0.provider == provider }
    }
  }

  private var combinedCodexTokenUsage: CodexTokenUsageSummary? {
    guard selectedProvider == nil || selectedProvider == .codex else { return nil }
    let codexAccountIDs = Set(accounts.filter { $0.provider == .codex }.map(\.id))
    let values = snapshots.values.compactMap { snapshot -> CodexTokenUsageSummary? in
      guard codexAccountIDs.contains(snapshot.accountID),
            snapshot.authenticationMode != .apiKey else { return nil }
      return snapshot.codexTokenUsage
    }
    guard !values.isEmpty else { return nil }
    let daily = Dictionary(grouping: values.flatMap(\.dailyUsageBuckets)) {
      Calendar.current.startOfDay(for: $0.startDate)
    }.map { date, buckets in
      CodexDailyTokenUsage(startDate: date, tokens: buckets.reduce(0) { $0 + $1.tokens })
    }.sorted { $0.startDate < $1.startDate }
    func sum(_ values: [Int64?]) -> Int64? {
      let present = values.compactMap { $0 }
      return present.isEmpty ? nil : present.reduce(0, +)
    }
    func maximum(_ values: [Int64?]) -> Int64? { values.compactMap { $0 }.max() }
    let peak = [maximum(values.map(\.peakDailyTokens)), daily.map(\.tokens).max()]
      .compactMap { $0 }
      .max()
    return CodexTokenUsageSummary(
      lifetimeTokens: sum(values.map(\.lifetimeTokens)),
      peakDailyTokens: peak,
      longestRunningTurnSeconds: maximum(values.map(\.longestRunningTurnSeconds)),
      currentStreakDays: maximum(values.map(\.currentStreakDays)),
      longestStreakDays: maximum(values.map(\.longestStreakDays)),
      dailyUsageBuckets: daily
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let tokenUsage = combinedCodexTokenUsage, tokenUsage.hasData {
        CodexOfficialTokenActivityCard(usage: tokenUsage)
      }

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("使用走势")
            .font(.system(size: 17, weight: .bold))
            .lineLimit(1)
          Text("本机刷新记录")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.secondaryText)
        }
        Spacer()
        chartModeControl
      }

      Picker("时间范围", selection: $range) {
        ForEach(HistoryRange.allCases) { item in
          Text(item.title).tag(item)
        }
      }
      .pickerStyle(.segmented)

      if rangedSamples.isEmpty {
        historyEmptyState
      } else if let selectedProvider {
        ForEach(metricKinds(for: selectedProvider), id: \.self) { kind in
          HistoryChartCard(
            title: chartTitle(provider: selectedProvider, kind: kind),
            range: range,
            mode: mode,
            series: accountSeries(provider: selectedProvider, kind: kind)
          )
        }
      } else if aggregateProviders {
        aggregateContent
      } else {
        ForEach(providers) { provider in
          ForEach(metricKinds(for: provider), id: \.self) { kind in
            HistoryChartCard(
              title: chartTitle(provider: provider, kind: kind),
              range: range,
              mode: mode,
              series: accountSeries(provider: provider, kind: kind)
            )
          }
        }
      }

      if selectedProvider == .deepseek {
        dataSourceNote("DeepSeek 官方余额接口只返回账户余额，不返回逐请求模型、Token 数或 Cost；因此这里只显示余额趋势。")
      } else {
        if selectedProvider == .codex || (selectedProvider == nil && providers.contains(.codex)) {
          dataSourceNote("Codex OAuth 提供累计与每日 Token；按模型明细仅在线程计费数据可用时提供。数据只保存在本机。")
        }
        if selectedProvider == nil, providers.contains(.deepseek) {
          dataSourceNote("DeepSeek 官方余额接口不提供逐请求模型、Token 数或 Cost，余额数据不会与额度百分比相加。")
        }
      }
    }
  }

  private var chartModeControl: some View {
    HStack(spacing: 3) {
      ForEach(HistoryChartMode.allCases) { item in
        Button {
          mode = item
        } label: {
          Image(systemName: item.systemImage)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 32, height: 30)
            .foregroundStyle(mode == item ? .white : theme.secondaryText)
            .background(mode == item ? theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
      }
    }
    .padding(3)
    .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
  }

  private func dataSourceNote(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.system(size: 9))
      .foregroundStyle(theme.secondaryText)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var aggregateContent: some View {
    let tokens = providerSeries(kind: .tokens)
    if !tokens.isEmpty {
      HistoryChartCard(
        title: "全部平台 Token",
        range: range,
        mode: mode,
        series: tokens
      )
    }
    let utilization = providerSeries(kind: .utilization)
    if !utilization.isEmpty {
      HistoryChartCard(
        title: "全部平台汇总",
        range: range,
        mode: mode,
        series: utilization
      )
    }
    ForEach(providersWithBalance) { provider in
      HistoryChartCard(
        title: "\(provider.title) 余额",
        range: range,
        mode: mode,
        series: accountSeries(provider: provider, kind: .balance)
      )
    }
  }

  private var providersWithBalance: [ProviderID] {
    providers.filter { provider in
      rangedSamples.contains { $0.provider == provider && $0.kind == .balance }
    }
  }

  private func metricKinds(for provider: ProviderID) -> [UsageHistoryMetricKind] {
    [.tokens, .utilization, .balance].filter { kind in
      rangedSamples.contains { $0.provider == provider && $0.kind == kind }
    }
  }

  private func chartTitle(provider: ProviderID, kind: UsageHistoryMetricKind) -> String {
    switch kind {
    case .tokens: "\(provider.title) Token"
    case .utilization: provider.title
    case .balance: "\(provider.title) 余额"
    }
  }

  private var historyEmptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.xyaxis.line")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(theme.secondaryText)
      Text("暂无历史走势")
        .font(.system(size: 13, weight: .semibold))
      Text("下一次成功刷新后开始记录；至少两次记录后可看到变化。")
        .font(.system(size: 10))
        .foregroundStyle(theme.secondaryText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
  }

  private func accountSeries(provider: ProviderID, kind: UsageHistoryMetricKind? = nil) -> [HistorySeries] {
    let matchingAccounts = accounts.filter { $0.provider == provider }
    return matchingAccounts.compactMap { account in
      let samples = rangedSamples.filter {
        $0.accountID == account.id && (kind == nil || $0.kind == kind)
      }
      return makeSeries(id: account.id.uuidString, name: account.label, provider: provider, samples: samples)
    }
  }

  private func providerSeries(kind: UsageHistoryMetricKind) -> [HistorySeries] {
    providers.compactMap { provider in
      let samples = rangedSamples.filter { $0.provider == provider && $0.kind == kind }
      return makeSeries(id: provider.rawValue, name: provider.title, provider: provider, samples: samples)
    }
  }

  private func makeSeries(
    id: String,
    name: String,
    provider: ProviderID,
    samples: [UsageHistorySample]
  ) -> HistorySeries? {
    guard let first = samples.first else { return nil }
    let matching = samples.filter { $0.kind == first.kind }
    let buckets = Dictionary(grouping: matching) { sample in
      sample.kind == .tokens ? Calendar.current.startOfDay(for: sample.recordedAt) : range.bucket(sample.recordedAt)
    }
    let points = buckets.map { date, values in
      let value: Double
      if first.kind == .utilization || first.kind == .tokens {
        value = values.map(\.value).max() ?? 0
      } else {
        value = values.max(by: { $0.recordedAt < $1.recordedAt })?.value ?? 0
      }
      return HistoryPoint(date: date, value: value)
    }.sorted { $0.date < $1.date }
    return HistorySeries(
      id: id,
      name: name,
      provider: provider,
      kind: first.kind,
      unit: first.unit,
      points: points
    )
  }
}

private struct HistoryChartCard: View {
  @Environment(\.dashboardTheme) private var theme
  let title: String
  let range: HistoryRange
  let mode: HistoryChartMode
  let series: [HistorySeries]
  @State private var selectedHeatmapPoint: HistoryHeatmapPoint?

  private var allPoints: [(series: HistorySeries, point: HistoryPoint)] {
    series.flatMap { item in item.points.map { (item, $0) } }
  }

  private var peak: (series: HistorySeries, point: HistoryPoint)? {
    allPoints.max { $0.point.value < $1.point.value }
  }

  private var heatmapPoints: [HistoryHeatmapPoint] {
    let grouped = Dictionary(grouping: allPoints) { $0.point.date }
    return grouped.compactMap { date, values in
      guard let peak = values.max(by: { $0.point.value < $1.point.value }) else { return nil }
      return HistoryHeatmapPoint(
        date: date,
        value: peak.point.value,
        provider: peak.series.provider,
        unit: peak.series.unit
      )
    }.sorted { $0.date < $1.date }
  }

  private var chartDomain: ClosedRange<Double> {
    if series.first?.kind == .utilization { return 0...100 }
    let maximum = allPoints.map { $0.point.value }.max() ?? 1
    return 0...max(1, maximum * 1.15)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(metricSubtitle)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.secondaryText)
        }
        Spacer()
        if let peak {
          VStack(alignment: .trailing, spacing: 2) {
            Text(peakLabel)
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(theme.secondaryText)
            Text(formatted(peak.point.value, unit: peak.series.unit))
              .font(.system(size: 18, weight: .bold, design: .rounded))
              .foregroundStyle(theme.accent(for: peak.series.provider))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
            Text(peak.point.date.formatted(
              date: .abbreviated,
              time: peak.series.kind == .tokens ? .omitted : .shortened
            ))
              .font(.system(size: 8))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
          }
        }
      }

      if series.isEmpty {
        Text("当前范围没有可绘制的数据")
          .font(.system(size: 11))
          .foregroundStyle(theme.secondaryText)
          .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        legend
        switch mode {
        case .ring:
          ringChart
        case .bar:
          barChart
        case .line:
          lineChart
        case .heatmap:
          heatmapChart
        }
      }
    }
    .padding(16)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
  }

  private var metricSubtitle: LocalizedStringKey {
    switch series.first?.kind ?? .utilization {
    case .tokens: "每日 Token 用量"
    case .balance: "余额趋势"
    case .utilization: "额度使用率"
    }
  }

  private var peakLabel: LocalizedStringKey {
    switch series.first?.kind ?? .utilization {
    case .tokens: "单日峰值"
    case .balance: "最高余额"
    case .utilization: "峰值"
    }
  }

  private var legend: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(series) { item in
          HStack(spacing: 5) {
            Circle().fill(theme.accent(for: item.provider)).frame(width: 7, height: 7)
            Text(item.name)
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(theme.secondaryText)
          }
        }
      }
    }
  }

  private var lineChart: some View {
    Chart {
      ForEach(series) { item in
        ForEach(item.points) { point in
          LineMark(
            x: .value("时间", point.date),
            y: .value("数值", point.value)
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(theme.accent(for: item.provider))
          .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
          PointMark(
            x: .value("时间", point.date),
            y: .value("数值", point.value)
          )
          .foregroundStyle(theme.accent(for: item.provider))
          .symbolSize(22)
        }
      }
    }
    .chartYScale(domain: chartDomain)
    .chartXAxis { AxisMarks(values: .automatic(desiredCount: range == .today ? 4 : 5)) }
    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
    .frame(height: 190)
  }

  private var barChart: some View {
    Chart {
      ForEach(series) { item in
        ForEach(item.points) { point in
          BarMark(
            x: .value("时间", point.date),
            y: .value("数值", point.value)
          )
          .position(by: .value("系列", item.name))
          .foregroundStyle(theme.accent(for: item.provider).opacity(0.82))
          .cornerRadius(4)
        }
      }
    }
    .chartYScale(domain: chartDomain)
    .chartXAxis { AxisMarks(values: .automatic(desiredCount: range == .today ? 4 : 5)) }
    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
    .frame(height: 190)
  }

  private var ringChart: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 20) {
        ForEach(series) { item in
          let latest = item.points.last?.value ?? 0
          VStack(spacing: 8) {
            ZStack {
              Circle().stroke(theme.surfaceRaised, lineWidth: 11)
              Circle()
                .trim(from: 0, to: item.kind == .utilization ? min(1, max(0, latest / 100)) : 1)
                .stroke(theme.accent(for: item.provider), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
              VStack(spacing: 1) {
                Text(formatted(latest, unit: item.unit))
                  .font(.system(size: 17, weight: .bold, design: .rounded))
                  .minimumScaleFactor(0.65)
                Text(ringValueLabel(item.kind))
                  .font(.system(size: 8))
                  .foregroundStyle(theme.secondaryText)
              }
              .padding(8)
            }
            .frame(width: 104, height: 104)
            Text(item.name)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
              .frame(width: 112)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
    }
    .frame(minHeight: 140)
  }

  private var heatmapChart: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
        spacing: 5
      ) {
        ForEach(heatmapPoints) { point in
          Button {
            selectedHeatmapPoint = point
          } label: {
            Text(heatmapLabel(point))
              .font(.system(size: 9, weight: .semibold, design: .rounded))
              .foregroundStyle(heatmapRatio(point) > 0.55 ? Color.white : theme.primaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .frame(maxWidth: .infinity)
              .aspectRatio(1, contentMode: .fit)
              .background(
                theme.success.opacity(0.12 + 0.78 * heatmapRatio(point)),
                in: RoundedRectangle(cornerRadius: 6)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 6)
                  .stroke(
                    selectedHeatmapPoint?.id == point.id ? theme.primary : Color.clear,
                    lineWidth: 2
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(point.date.formatted(date: .abbreviated, time: range == .today && point.unit != "Token" ? .shortened : .omitted))，\(formatted(point.value, unit: point.unit))"
          )
        }
      }

      HStack(spacing: 5) {
        Text("低")
        ForEach(1...4, id: \.self) { level in
          RoundedRectangle(cornerRadius: 3)
            .fill(theme.success.opacity(0.12 + Double(level) * 0.19))
            .frame(width: 15, height: 15)
        }
        Text("高")
        Spacer()
      }
      .font(.system(size: 8, weight: .medium))
      .foregroundStyle(theme.secondaryText)

      if let selected = selectedHeatmapPoint {
        HStack {
          Text(selected.date.formatted(date: .abbreviated, time: range == .today && selected.unit != "Token" ? .shortened : .omitted))
          Spacer()
          Text(selected.provider.title)
          Text(formatted(selected.value, unit: selected.unit))
            .fontWeight(.bold)
            .foregroundStyle(theme.accent(for: selected.provider))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      }
    }
    .frame(minHeight: 176, alignment: .top)
  }

  private func heatmapRatio(_ point: HistoryHeatmapPoint) -> Double {
    let ceiling = max(1, chartDomain.upperBound)
    return min(1, max(0, point.value / ceiling))
  }

  private func ringValueLabel(_ kind: UsageHistoryMetricKind) -> LocalizedStringKey {
    switch kind {
    case .tokens: "当前 Token"
    case .balance: "当前余额"
    case .utilization: "当前使用"
    }
  }

  private func heatmapLabel(_ point: HistoryHeatmapPoint) -> String {
    if range == .today && point.unit != "Token" {
      return "\(Calendar.current.component(.hour, from: point.date))时"
    }
    return "\(Calendar.current.component(.day, from: point.date))"
  }

  private func formatted(_ value: Double, unit: String) -> String {
    if unit == "%" { return "\(Int(value.rounded()))%" }
    let prefix = unit == "Token" ? "" : unit
    if abs(value) >= 1_000_000_000 { return "\(prefix)\(String(format: "%.1f", value / 1_000_000_000))B" }
    if abs(value) >= 1_000_000 { return "\(prefix)\(String(format: "%.1f", value / 1_000_000))M" }
    if abs(value) >= 1_000 { return "\(prefix)\(String(format: "%.1f", value / 1_000))K" }
    return "\(prefix)\(String(format: value.rounded() == value ? "%.0f" : "%.2f", value))"
  }
}
