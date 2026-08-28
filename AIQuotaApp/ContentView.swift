import Foundation
import SwiftUI
import UIKit
import WidgetKit

private enum DashboardPalette {
  static let background = Color(red: 0.035, green: 0.04, blue: 0.055)
  static let surface = Color(red: 0.085, green: 0.09, blue: 0.115)
  static let surfaceRaised = Color(red: 0.115, green: 0.12, blue: 0.15)
  static let border = Color.white.opacity(0.12)
  static let secondaryText = Color(red: 0.62, green: 0.64, blue: 0.72)
  static let purple = Color(red: 0.49, green: 0.20, blue: 0.96)
  static let cyan = Color(red: 0.25, green: 0.82, blue: 0.80)
  static let orange = Color(red: 0.94, green: 0.39, blue: 0.18)
  static let green = Color(red: 0.20, green: 0.78, blue: 0.45)

  static func accent(for provider: ProviderID) -> Color {
    switch provider {
    case .codex: purple
    case .claude: orange
    case .kimi: green
    case .deepseek: cyan
    case .minimax: Color(red: 0.95, green: 0.65, blue: 0.18)
    case .glm: Color(red: 0.30, green: 0.53, blue: 0.98)
    case .copilot: Color(red: 0.78, green: 0.45, blue: 0.92)
    }
  }
}

struct ContentView: View {
  @StateObject private var model = AppModel()
  @State private var selectedProvider: ProviderID?
  @State private var apiProvider: ProviderID?
  @State private var renameTarget: AccountRecord?
  @State private var renameText = ""
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      ZStack {
        DashboardPalette.background.ignoresSafeArea()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            header
            providerFilter
            DashboardSummary(
              account: featuredAccount,
              snapshot: featuredAccount.flatMap { model.snapshots[$0.id] },
              activeAccountCount: model.accounts.filter(\.isEnabled).count,
              providerCount: Set(model.accounts.filter(\.isEnabled).map(\.provider)).count,
              lastUpdatedAt: model.snapshots.values.map(\.fetchedAt).max()
            )
            accountSection
            buildModeNote
          }
          .padding(.horizontal, 18)
          .padding(.top, 10)
          .padding(.bottom, 32)
        }
        .refreshable { await model.refreshAll() }

        if model.isBusy {
          ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            ProgressView("正在同步额度")
              .tint(.white)
              .padding(.horizontal, 22)
              .padding(.vertical, 16)
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .task { await model.load() }
      .alert(
        "错误",
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button("好", role: .cancel) { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "")
      }
      .alert(
        "重命名账号",
        isPresented: Binding(
          get: { renameTarget != nil },
          set: { if !$0 { renameTarget = nil } }
        )
      ) {
        TextField("账号名称", text: $renameText)
        Button("取消", role: .cancel) { renameTarget = nil }
        Button("保存") {
          if let target = renameTarget {
            Task { await model.rename(target, label: renameText) }
          }
          renameTarget = nil
        }
      }
      .sheet(item: $apiProvider) { provider in
        APIKeyEntryView(provider: provider) { key, baseURL in
          await model.addAPIKey(provider: provider, key: key, baseURL: baseURL)
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView(model: model)
          .preferredColorScheme(.dark)
      }
    }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("AI QUOTA")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(DashboardPalette.cyan)
        Text("额度总览")
          .font(.system(size: 30, weight: .bold))
      }
      Spacer()
      livePill
      iconButton(systemName: "gearshape") { showingSettings = true }
      addMenu
    }
  }

  private var livePill: some View {
    HStack(spacing: 6) {
      Circle().fill(DashboardPalette.green).frame(width: 6, height: 6)
      Text("LIVE")
        .font(.system(size: 10, weight: .bold))
    }
    .foregroundStyle(DashboardPalette.green)
    .padding(.horizontal, 10)
    .frame(height: 34)
    .background(DashboardPalette.green.opacity(0.12), in: Capsule())
  }

  private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 36, height: 36)
        .background(DashboardPalette.surfaceRaised, in: Circle())
        .overlay(Circle().stroke(DashboardPalette.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private var addMenu: some View {
    Menu {
      Button("Codex · ChatGPT 登录") { loginOAuth(.codex) }
      Button("Claude · OAuth 登录") { loginOAuth(.claude) }
      Button("Kimi · OAuth 登录") { loginOAuth(.kimi) }
      Divider()
      Button("DeepSeek · API Key") { apiProvider = .deepseek }
      Button("MiniMax · Coding Key") { apiProvider = .minimax }
      Button("GLM · Coding Key") { apiProvider = .glm }
      Button("GitHub Copilot · Token") { apiProvider = .copilot }
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 36, height: 36)
        .foregroundStyle(.white)
        .background(DashboardPalette.purple, in: Circle())
    }
    .buttonStyle(.plain)
  }

  private var providerFilter: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ProviderFilterButton(title: "全部", color: DashboardPalette.purple, isSelected: selectedProvider == nil) {
          selectedProvider = nil
        }
        ForEach(ProviderID.allCases) { provider in
          ProviderFilterButton(
            title: provider.title,
            color: DashboardPalette.accent(for: provider),
            isSelected: selectedProvider == provider
          ) {
            selectedProvider = provider
          }
        }
      }
    }
  }

  private var accountSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("账户额度")
          .font(.system(size: 16, weight: .bold))
        Text("\(filteredAccounts.count)")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(DashboardPalette.secondaryText)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(DashboardPalette.surfaceRaised, in: Capsule())
        Spacer()
        Button {
          Task { await model.refreshAll() }
        } label: {
          Label("全部刷新", systemImage: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DashboardPalette.cyan)
        .disabled(model.isBusy || model.accounts.isEmpty)
      }

      if filteredAccounts.isEmpty {
        EmptyAccountsView(hasAccounts: !model.accounts.isEmpty)
      } else {
        ForEach(filteredAccounts) { account in
          AccountDashboardCard(
            account: account,
            snapshot: model.snapshots[account.id],
            cooldownUntil: model.cooldownUntil(account),
            recommended: recommendedAccountIDs.contains(account.id),
            health: model.credentialHealth(account),
            onRefresh: { await model.refresh(account) },
            onReauthenticate: { await reauthenticate(account) },
            onRename: {
              renameTarget = account
              renameText = account.label
            },
            onToggle: { Task { await model.setEnabled(account, enabled: !account.isEnabled) } },
            onMoveUp: { Task { await model.move(account, offset: -1) } },
            onMoveDown: { Task { await model.move(account, offset: 1) } },
            onDelete: { Task { await model.delete(account) } }
          )
        }
      }
    }
  }

  private var buildModeNote: some View {
    HStack(spacing: 9) {
      Image(systemName: AppConfig.isAppOnlyBuild ? "iphone" : "rectangle.stack.badge.person.crop")
      Text(AppConfig.isAppOnlyBuild ? "单 App 兼容版" : "App + Widget 完整版")
      Spacer()
      Text("iOS 16+")
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(DashboardPalette.secondaryText)
    .padding(.top, 2)
  }

  private var filteredAccounts: [AccountRecord] {
    guard let selectedProvider else { return model.accounts }
    return model.accounts.filter { $0.provider == selectedProvider }
  }

  private var featuredAccount: AccountRecord? {
    filteredAccounts
      .filter(\.isEnabled)
      .max { score(for: $0) < score(for: $1) }
      ?? filteredAccounts.first
  }

  private func score(for account: AccountRecord) -> Double {
    guard let snapshot = model.snapshots[account.id], !snapshot.stale else { return -1 }
    if let balance = snapshot.balance { return balance.total }
    return snapshot.windows.map(\.remainingPercent).min() ?? -1
  }

  private var recommendedAccountIDs: Set<UUID> {
    Set(ProviderID.allCases.compactMap { provider in
      model.accounts
        .filter { $0.isEnabled && $0.provider == provider }
        .max { score(for: $0) < score(for: $1) }?
        .id
    })
  }

  private func loginOAuth(_ provider: ProviderID) {
    Task { @MainActor in
      guard let presenter = UIApplication.shared.activeTopViewController() else {
        model.errorMessage = "无法打开登录页面"
        return
      }
      switch provider {
      case .codex: await model.addCodex(presenter: presenter)
      case .claude: await model.addClaude(presenter: presenter)
      case .kimi: await model.addKimi(presenter: presenter)
      default: break
      }
    }
  }

  private func reauthenticate(_ account: AccountRecord) async {
    guard [.codex, .claude, .kimi].contains(account.provider) else {
      await MainActor.run { apiProvider = account.provider }
      return
    }
    guard let presenter = await MainActor.run(body: { UIApplication.shared.activeTopViewController() }) else {
      await MainActor.run { model.errorMessage = "无法打开重新认证页面" }
      return
    }
    await model.reauthenticate(account, presenter: presenter)
  }
}

private struct ProviderFilterButton: View {
  let title: String
  let color: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isSelected ? .white : DashboardPalette.secondaryText)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(isSelected ? color.opacity(0.72) : DashboardPalette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? color : DashboardPalette.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

private struct DashboardSummary: View {
  let account: AccountRecord?
  let snapshot: UsageSnapshot?
  let activeAccountCount: Int
  let providerCount: Int
  let lastUpdatedAt: Date?

  private var accent: Color {
    account.map { DashboardPalette.accent(for: $0.provider) } ?? DashboardPalette.purple
  }

  private var progress: Double? {
    snapshot?.windows.map(\.remainingPercent).min().map { min(1, max(0, $0 / 100)) }
  }

  private var primaryValue: String {
    if let balance = snapshot?.balance { return "\(balance.symbol)\(String(format: "%.2f", balance.total))" }
    if let progress { return "\(Int((progress * 100).rounded()))%" }
    return "--"
  }

  private var primaryLabel: String {
    snapshot?.balance == nil ? "最低剩余额度" : "可用余额"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text(account?.label ?? "等待添加账号")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DashboardPalette.secondaryText)
          Text(primaryValue)
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text(primaryLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent)
        }
        Spacer()
        ZStack {
          Circle().stroke(DashboardPalette.surfaceRaised, lineWidth: 9)
          Circle()
            .trim(from: 0, to: progress ?? 0)
            .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Image(systemName: account == nil ? "chart.donut" : "bolt.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(accent)
        }
        .frame(width: 82, height: 82)
      }

      Divider().overlay(DashboardPalette.border)

      HStack(spacing: 0) {
        SummaryMetric(value: "\(activeAccountCount)", label: "启用账号")
        Divider().frame(height: 34).overlay(DashboardPalette.border)
        SummaryMetric(value: "\(providerCount)", label: "平台")
        Divider().frame(height: 34).overlay(DashboardPalette.border)
        SummaryMetric(
          value: lastUpdatedAt?.formatted(date: .omitted, time: .shortened) ?? "--",
          label: "最近更新"
        )
      }
    }
    .padding(20)
    .background(DashboardPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardPalette.border, lineWidth: 1))
  }
}

private struct SummaryMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(DashboardPalette.secondaryText)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct EmptyAccountsView: View {
  let hasAccounts: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: hasAccounts ? "line.3.horizontal.decrease.circle" : "person.crop.circle.badge.plus")
        .font(.system(size: 28))
        .foregroundStyle(DashboardPalette.cyan)
      Text(hasAccounts ? "这个平台还没有账号" : "还没有账号")
        .font(.system(size: 16, weight: .bold))
      Text(hasAccounts ? "切换到其他平台查看" : "点右上角 + 添加账号")
        .font(.system(size: 12))
        .foregroundStyle(DashboardPalette.secondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 150)
    .background(DashboardPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardPalette.border, lineWidth: 1))
  }
}

private struct AccountDashboardCard: View {
  let account: AccountRecord
  let snapshot: UsageSnapshot?
  let cooldownUntil: Date?
  let recommended: Bool
  let health: CredentialHealth
  let onRefresh: () async -> Void
  let onReauthenticate: () async -> Void
  let onRename: () -> Void
  let onToggle: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onDelete: () -> Void

  @State private var refreshing = false
  @State private var reauthenticating = false

  private var accent: Color { DashboardPalette.accent(for: account.provider) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 10) {
        Circle().fill(accent).frame(width: 9, height: 9).padding(.top, 6)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text(account.label)
              .font(.system(size: 17, weight: .bold))
              .lineLimit(1)
            if recommended {
              Text("推荐")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(DashboardPalette.green, in: Capsule())
            }
          }
          Text(account.provider.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DashboardPalette.secondaryText)
        }
        Spacer()
        CredentialStatusPill(health: health)
        accountMenu
      }

      if let snapshot {
        SnapshotDashboardBody(snapshot: snapshot, accent: accent, cooldownUntil: cooldownUntil)
      } else {
        HStack(spacing: 8) {
          Image(systemName: "clock")
          Text("等待首次刷新")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(DashboardPalette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
      }

      Divider().overlay(DashboardPalette.border)

      HStack(spacing: 14) {
        Button {
          refreshing = true
          Task {
            await onRefresh()
            refreshing = false
          }
        } label: {
          Label(refreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
        }
        .disabled(refreshing)

        Button {
          reauthenticating = true
          Task {
            await onReauthenticate()
            reauthenticating = false
          }
        } label: {
          Label(reauthenticating ? "认证中" : "重新认证", systemImage: "key")
        }
        .disabled(reauthenticating)

        Spacer()
        if !account.isEnabled {
          Text("已隐藏")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DashboardPalette.orange)
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(accent)
      .buttonStyle(.plain)
    }
    .padding(16)
    .background(DashboardPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardPalette.border, lineWidth: 1))
    .opacity(account.isEnabled ? 1 : 0.62)
  }

  private var accountMenu: some View {
    Menu {
      Button(action: onRename) { Label("重命名", systemImage: "pencil") }
      Button(action: onToggle) {
        Label(account.isEnabled ? "隐藏" : "显示", systemImage: account.isEnabled ? "eye.slash" : "eye")
      }
      Button(action: onMoveUp) { Label("上移", systemImage: "arrow.up") }
      Button(action: onMoveDown) { Label("下移", systemImage: "arrow.down") }
      Divider()
      Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(DashboardPalette.surfaceRaised, in: Circle())
    }
    .buttonStyle(.plain)
  }
}

private struct CredentialStatusPill: View {
  let health: CredentialHealth

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: health.icon)
      Text(health.title)
    }
    .font(.system(size: 9, weight: .bold))
    .foregroundStyle(health.color)
    .padding(.horizontal, 8)
    .frame(height: 27)
    .background(health.color.opacity(0.12), in: Capsule())
  }
}

private struct SnapshotDashboardBody: View {
  let snapshot: UsageSnapshot
  let accent: Color
  let cooldownUntil: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let kind = snapshot.effectiveErrorKind {
        HStack(spacing: 6) {
          Image(systemName: statusIcon(kind))
          Text(healthText(kind))
          if let cooldownUntil, cooldownUntil > .now {
            Text("· \(resetCountdown(cooldownUntil)) 后重试")
          }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(statusColor(kind))
      }

      if let balance = snapshot.balance {
        HStack(alignment: .firstTextBaseline) {
          Text("可用余额")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DashboardPalette.secondaryText)
          Spacer()
          Text("\(balance.symbol)\(balance.total, specifier: "%.2f")")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(balance.available ? accent : .red)
        }
      } else if !snapshot.windows.isEmpty {
        ForEach(snapshot.windows.prefix(3)) { window in
          QuotaWindowRow(window: window, accent: accent)
        }
      } else if !snapshot.metrics.isEmpty {
        HStack(spacing: 18) {
          ForEach(snapshot.metrics.prefix(3)) { metric in
            VStack(alignment: .leading, spacing: 3) {
              Text(metric.label)
                .font(.system(size: 10))
                .foregroundStyle(DashboardPalette.secondaryText)
              Text(metric.value)
                .font(.system(size: 15, weight: .bold))
            }
          }
        }
      } else {
        Text("暂无可显示额度")
          .font(.system(size: 12))
          .foregroundStyle(DashboardPalette.secondaryText)
      }

      HStack(spacing: 7) {
        Text("更新 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
        if snapshot.stale {
          Text("缓存")
            .foregroundStyle(DashboardPalette.orange)
        }
        if let plan = snapshot.plan, !plan.isEmpty {
          Text(plan)
            .lineLimit(1)
        }
      }
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(DashboardPalette.secondaryText)
    }
  }

  private func healthText(_ kind: ProviderErrorKind) -> String {
    snapshot.stale && hasCachedData ? "缓存 · \(kind.shortLabel)" : kind.shortLabel
  }

  private var hasCachedData: Bool {
    !snapshot.windows.isEmpty || !snapshot.metrics.isEmpty || snapshot.balance != nil
  }
}

private struct QuotaWindowRow: View {
  let window: UsageWindow
  let accent: Color

  var body: some View {
    VStack(spacing: 7) {
      HStack {
        Text(window.label)
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Text("\(Int(window.remainingPercent.rounded()))%")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(progressColor)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(DashboardPalette.surfaceRaised)
          Capsule()
            .fill(progressColor)
            .frame(width: max(5, proxy.size.width * window.remainingPercent / 100))
        }
      }
      .frame(height: 7)
      if let reset = window.resetAt, reset > .now {
        HStack {
          Text("重置")
          Spacer()
          Text(resetCountdown(reset))
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(DashboardPalette.secondaryText)
      }
    }
  }

  private var progressColor: Color {
    if window.remainingPercent <= 15 { return .red }
    if window.remainingPercent <= 35 { return DashboardPalette.orange }
    return accent
  }
}

private func statusColor(_ kind: ProviderErrorKind) -> Color {
  switch kind {
  case .authentication, .configuration: .red
  case .rateLimited, .providerUnavailable, .network: DashboardPalette.orange
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

private func resetCountdown(_ date: Date) -> String {
  let seconds = max(0, Int(date.timeIntervalSinceNow))
  let days = seconds / 86_400
  let hours = (seconds % 86_400) / 3_600
  let minutes = (seconds % 3_600) / 60
  if days > 0 { return "\(days)天 \(hours)小时" }
  if hours > 0 { return "\(hours)小时 \(minutes)分" }
  return "\(max(1, minutes))分"
}

struct CredentialHealth {
  let title: String
  let icon: String
  let color: Color
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var autoMinutes = 15

  var body: some View {
    NavigationStack {
      Form {
        if AppConfig.isAppOnlyBuild {
          Section("刷新") {
            Label("支持单账号刷新、全部刷新和下拉刷新", systemImage: "arrow.clockwise")
            Text("当前安装的是单 App 兼容版，不包含桌面小组件。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else {
          Section("自动刷新") {
            Picker("最早刷新间隔", selection: $autoMinutes) {
              Text("10 分钟").tag(10)
              Text("15 分钟").tag(15)
              Text("30 分钟").tag(30)
              Text("1 小时").tag(60)
              Text("2 小时").tag(120)
            }
            Text("实际后台刷新由 iOS 调度；iOS 17 以上可直接使用小组件刷新按钮。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        Section("数据") {
          NavigationLink {
            BackupSettingsView(model: model)
          } label: {
            Label("导入与导出", systemImage: "arrow.up.arrow.down.square")
          }
          Text("配置文件可在 iOS 与 Android 之间共用。完整备份可包含登录凭据。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Section("凭据状态") {
          ForEach(model.accounts) { account in
            let health = model.credentialHealth(account)
            HStack {
              VStack(alignment: .leading) {
                Text(account.label)
                Text(account.provider.title).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Label(health.title, systemImage: health.icon)
                .foregroundStyle(health.color)
                .font(.caption)
            }
          }
        }
        Section("显示账号") {
          ForEach(model.accounts) { account in
            Toggle(
              account.label,
              isOn: Binding(
                get: { account.isEnabled },
                set: { value in Task { await model.setEnabled(account, enabled: value) } }
              )
            )
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(DashboardPalette.background)
      .navigationTitle("设置")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") { dismiss() }
        }
      }
      .task { autoMinutes = await SharedStore.shared.autoRefreshMinutes() }
      .onChange(of: autoMinutes) { newValue in
        guard !AppConfig.isAppOnlyBuild else { return }
        Task {
          await SharedStore.shared.setAutoRefreshMinutes(newValue)
          WidgetCenter.shared.reloadAllTimelines()
        }
      }
    }
  }
}
