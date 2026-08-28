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

  var id: String { rawValue }

  var title: String {
    switch self {
    case .ring: "圆环"
    case .bar: "柱状"
    case .line: "折线"
    }
  }

  var systemImage: String {
    switch self {
    case .ring: "chart.donut"
    case .bar: "chart.bar.fill"
    case .line: "chart.xyaxis.line"
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

struct UsageHistoryDashboard: View {
  @Environment(\.dashboardTheme) private var theme
  let history: [UsageHistorySample]
  let accounts: [AccountRecord]
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
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
        HistoryChartCard(
          title: selectedProvider.title,
          range: range,
          mode: mode,
          series: accountSeries(provider: selectedProvider)
        )
      } else if aggregateProviders {
        aggregateContent
      } else {
        ForEach(providers) { provider in
          HistoryChartCard(
            title: provider.title,
            range: range,
            mode: mode,
            series: accountSeries(provider: provider)
          )
        }
      }

      Text("Codex 官方额度接口仅提供使用比例和重置时间，不提供每日 Token 总数。历史数据不会上传。")
        .font(.system(size: 9))
        .foregroundStyle(theme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
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

  @ViewBuilder private var aggregateContent: some View {
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
    let buckets = Dictionary(grouping: matching) { range.bucket($0.recordedAt) }
    let points = buckets.map { date, values in
      let value: Double
      if first.kind == .utilization {
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

  private var allPoints: [(series: HistorySeries, point: HistoryPoint)] {
    series.flatMap { item in item.points.map { (item, $0) } }
  }

  private var peak: (series: HistorySeries, point: HistoryPoint)? {
    allPoints.max { $0.point.value < $1.point.value }
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
          Text(series.first?.kind == .balance ? "余额变化" : "额度使用率")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.secondaryText)
        }
        Spacer()
        if let peak {
          VStack(alignment: .trailing, spacing: 2) {
            Text(series.first?.kind == .balance ? "最高记录" : "峰值")
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(theme.secondaryText)
            Text(formatted(peak.point.value, unit: peak.series.unit))
              .font(.system(size: 18, weight: .bold, design: .rounded))
              .foregroundStyle(theme.accent(for: peak.series.provider))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
            Text(peak.point.date.formatted(date: .abbreviated, time: .shortened))
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
        }
      }
    }
    .padding(16)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
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
                Text(item.kind == .balance ? "当前余额" : "当前使用")
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

  private func formatted(_ value: Double, unit: String) -> String {
    if unit == "%" { return "\(Int(value.rounded()))%" }
    if abs(value) >= 1_000_000_000 { return "\(unit)\(String(format: "%.1f", value / 1_000_000_000))B" }
    if abs(value) >= 1_000_000 { return "\(unit)\(String(format: "%.1f", value / 1_000_000))M" }
    if abs(value) >= 1_000 { return "\(unit)\(String(format: "%.1f", value / 1_000))K" }
    return "\(unit)\(String(format: value.rounded() == value ? "%.0f" : "%.2f", value))"
  }
}
