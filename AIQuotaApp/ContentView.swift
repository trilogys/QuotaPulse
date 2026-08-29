import Foundation
import SwiftUI
import UIKit
import WidgetKit

private enum AccountSortMode: String, CaseIterable, Identifiable {
  case manual
  case available
  case risk

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual: "自定义"
    case .available: "额度优先"
    case .risk: "风险优先"
    }
  }
}

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = AppModel()
  @State private var selectedTheme: DashboardTheme = .daylight
  @State private var selectedProvider: ProviderID?
  @State private var sortMode: AccountSortMode = .manual
  @State private var aggregateHistory = false
  @State private var overviewAutoRefreshSeconds = 0
  @State private var lastSuccessfulRefreshAt: Date?
  @State private var apiProvider: ProviderID?
  @State private var apiCredentialTarget: AccountRecord?
  @State private var namingOAuthProvider: ProviderID?
  @State private var newOAuthAccountName = ""
  @State private var renameTarget: AccountRecord?
  @State private var renameText = ""
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      ZStack {
        selectedTheme.background.ignoresSafeArea()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            header
            providerFilter
            DashboardSummary(
              account: featuredAccount,
              snapshot: featuredAccount.flatMap { model.snapshots[$0.id] },
              allAccounts: selectedProvider == nil ? enabledAccounts : [],
              snapshots: model.snapshots,
              activeAccountCount: model.accounts.filter(\.isEnabled).count,
              providerCount: Set(model.accounts.filter(\.isEnabled).map(\.provider)).count,
              lastUpdatedAt: model.snapshots.values.map(\.fetchedAt).max()
            )
            UsageHistoryDashboard(
              history: enabledUsageHistory,
              accounts: enabledAccounts,
              snapshots: model.snapshots,
              selectedProvider: selectedProvider,
              aggregateProviders: aggregateHistory
            )
            accountSection
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
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: selectedTheme.compactCardCornerRadius))
          }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .task {
        selectedTheme = await SharedStore.shared.dashboardTheme()
        aggregateHistory = await SharedStore.shared.aggregateHistory()
        overviewAutoRefreshSeconds = await SharedStore.shared.overviewAutoRefreshSeconds()
        lastSuccessfulRefreshAt = await SharedStore.shared.lastSuccessfulRefreshAt()
        await model.load()
      }
      .task(id: overviewRefreshTaskID) {
        await runOverviewAutoRefresh()
      }
      .onChange(of: scenePhase) { phase in
        guard phase == .active else { return }
        Task {
          await model.load()
          lastSuccessfulRefreshAt = await SharedStore.shared.lastSuccessfulRefreshAt()
        }
      }
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
        "提示",
        isPresented: Binding(
          get: { model.statusMessage != nil },
          set: { if !$0 { model.statusMessage = nil } }
        )
      ) {
        Button("好", role: .cancel) { model.statusMessage = nil }
      } message: {
        Text(model.statusMessage ?? "")
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
      .alert(
        "添加 OAuth 账号",
        isPresented: Binding(
          get: { namingOAuthProvider != nil },
          set: { if !$0 { namingOAuthProvider = nil } }
        )
      ) {
        TextField("账号名称（可选）", text: $newOAuthAccountName)
        Button("取消", role: .cancel) {
          namingOAuthProvider = nil
          newOAuthAccountName = ""
        }
        Button("继续登录") {
          if let provider = namingOAuthProvider {
            let name = newOAuthAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
            namingOAuthProvider = nil
            newOAuthAccountName = ""
            loginOAuth(provider, customName: name.isEmpty ? nil : name)
          }
        }
      } message: {
        Text("名称只用于本机显示；留空时自动使用邮箱或账号标识。")
      }
      .sheet(item: $apiProvider) { provider in
        APIKeyEntryView(provider: provider) { name, key, baseURL in
          await model.addAPIKey(provider: provider, name: name, key: key, baseURL: baseURL)
        }
      }
      .sheet(item: $apiCredentialTarget) { account in
        APIKeyEntryView(
          provider: account.provider,
          initialName: account.label,
          initialBaseURL: model.apiBaseURL(account),
          isEditing: true
        ) { name, key, baseURL in
          await model.updateAPIKey(account, name: name, key: key, baseURL: baseURL)
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView(
          model: model,
          selectedTheme: $selectedTheme,
          aggregateHistory: $aggregateHistory,
          overviewAutoRefreshSeconds: $overviewAutoRefreshSeconds
        )
      }
    }
    .environment(\.dashboardTheme, selectedTheme)
    .preferredColorScheme(selectedTheme.preferredColorScheme)
    .onOpenURL { url in
      importSharedJSON(url)
    }
  }

  private func importSharedJSON(_ url: URL) {
    guard url.isFileURL else { return }
    Task { @MainActor in
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        await model.importConfig(data, replace: false)
      } catch {
        model.errorMessage = "无法读取共享的 JSON：\(error.localizedDescription)"
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("QuotaPulse")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(selectedTheme.secondary)
          .lineLimit(1)
        Text("额度总览")
          .font(.system(size: 30, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Group {
          if let refreshAt = homepageLastRefreshAt {
            Text("上次刷新 \(refreshAt.formatted(date: .omitted, time: .shortened))")
          } else {
            Text("尚未成功刷新")
          }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(selectedTheme.secondaryText)
        .lineLimit(1)
      }
      .layoutPriority(1)
      Spacer()
      livePill
      iconButton(systemName: "gearshape") { showingSettings = true }
      addMenu
    }
  }

  private var livePill: some View {
    HStack(spacing: 6) {
      Circle().fill(selectedTheme.success).frame(width: 6, height: 6)
      Text("LIVE")
        .font(.system(size: 10, weight: .bold))
    }
    .foregroundStyle(selectedTheme.success)
    .padding(.horizontal, 10)
    .frame(height: 34)
    .background(selectedTheme.success.opacity(0.12), in: Capsule())
  }

  private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 36, height: 36)
        .background(selectedTheme.surfaceRaised, in: Circle())
        .overlay(Circle().stroke(selectedTheme.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private var addMenu: some View {
    Menu {
      Button("Codex · ChatGPT 登录") { beginOAuth(.codex) }
      Button("Claude · OAuth 登录") { beginOAuth(.claude) }
      Button("Kimi · OAuth 登录") { beginOAuth(.kimi) }
      Divider()
      Button("OpenAI / GPT · API Key") { apiProvider = .codex }
      Button("Claude · API Key") { apiProvider = .claude }
      Button("Kimi · API Key") { apiProvider = .kimi }
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
        .background(selectedTheme.primary, in: Circle())
    }
    .buttonStyle(.plain)
  }

  private var providerFilter: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ProviderFilterButton(title: "全部", color: selectedTheme.primary, isSelected: selectedProvider == nil) {
          selectedProvider = nil
        }
        ForEach(ProviderID.allCases) { provider in
          ProviderFilterButton(
            title: provider.title,
            color: selectedTheme.accent(for: provider),
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
          .foregroundStyle(selectedTheme.secondaryText)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(selectedTheme.surfaceRaised, in: Capsule())
        Spacer()
        Menu {
          ForEach(AccountSortMode.allCases) { mode in
            Button {
              sortMode = mode
            } label: {
              HStack {
                Text(mode.title)
                if sortMode == mode { Image(systemName: "checkmark") }
              }
            }
          }
        } label: {
          Label(sortMode.title, systemImage: "arrow.up.arrow.down")
            .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTheme.secondaryText)
        Button {
          Task { await model.refreshAll() }
        } label: {
          Label("全部刷新", systemImage: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTheme.secondary)
        .disabled(model.isBusy || model.accounts.isEmpty)
      }

      if filteredAccounts.isEmpty {
        EmptyAccountsView(hasAccounts: !model.accounts.isEmpty)
      } else {
        ForEach(filteredAccounts) { account in
          let usesAPIKey = model.usesAPIKey(account)
          AccountDashboardCard(
            account: account,
            snapshot: model.snapshots[account.id],
            cooldownUntil: model.cooldownUntil(account),
            recommended: recommendedAccountIDs.contains(account.id),
            health: model.credentialHealth(account),
            usesAPIKey: usesAPIKey,
            onRefresh: { await model.refresh(account) },
            onReauthenticate: {
              if usesAPIKey {
                apiCredentialTarget = account
              } else {
                await reauthenticate(account)
              }
            },
            onQueryResetCredits: { await model.queryCodexResetCredits(account) },
            onQueryCodexModels: { await model.queryCodexModelUsage(account) },
            onResetCodexQuota: { await model.resetCodexQuota(account) },
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

  private var filteredAccounts: [AccountRecord] {
    let values = selectedProvider.map { provider in
      model.accounts.filter { $0.provider == provider }
    } ?? model.accounts
    switch sortMode {
    case .manual:
      return values
    case .available:
      return values.sorted { score(for: $0) > score(for: $1) }
    case .risk:
      return values.sorted {
        let lhs = score(for: $0)
        let rhs = score(for: $1)
        return (lhs < 0 ? 101 : lhs) < (rhs < 0 ? 101 : rhs)
      }
    }
  }

  private var enabledAccounts: [AccountRecord] {
    model.accounts.filter(\.isEnabled)
  }

  private var enabledUsageHistory: [UsageHistorySample] {
    let ids = Set(enabledAccounts.map(\.id))
    return model.usageHistory.filter { ids.contains($0.accountID) }
  }

  private var featuredAccount: AccountRecord? {
    filteredAccounts
      .filter(\.isEnabled)
      .max { score(for: $0) < score(for: $1) }
  }

  private func score(for account: AccountRecord) -> Double {
    guard let snapshot = model.snapshots[account.id], !snapshot.stale else { return -1 }
    if let balance = snapshot.balance { return balance.available && balance.total > 0 ? 100 : 0 }
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

  private func beginOAuth(_ provider: ProviderID) {
    newOAuthAccountName = ""
    namingOAuthProvider = provider
  }

  private var homepageLastRefreshAt: Date? {
    ([lastSuccessfulRefreshAt] + model.snapshots.values.map(\.fetchedAt))
      .compactMap { $0 }
      .max()
  }

  private var overviewRefreshTaskID: String {
    "\(overviewAutoRefreshSeconds)-\(scenePhase == .active)"
  }

  private func runOverviewAutoRefresh() async {
    guard scenePhase == .active, overviewAutoRefreshSeconds > 0 else { return }
    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: UInt64(overviewAutoRefreshSeconds) * 1_000_000_000)
      } catch {
        return
      }
      guard scenePhase == .active else { return }
      if !model.isBusy { await model.refreshAll(manual: false) }
    }
  }

  private func loginOAuth(_ provider: ProviderID, customName: String?) {
    Task { @MainActor in
      guard let presenter = UIApplication.shared.activeTopViewController() else {
        model.errorMessage = "无法打开登录页面"
        return
      }
      switch provider {
      case .codex: await model.addCodex(name: customName, presenter: presenter)
      case .claude: await model.addClaude(name: customName, presenter: presenter)
      case .kimi: await model.addKimi(name: customName, presenter: presenter)
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
  @Environment(\.dashboardTheme) private var theme
  let title: String
  let color: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isSelected ? .white : theme.secondaryText)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(isSelected ? color.opacity(0.72) : theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? color : theme.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

private struct DashboardSummary: View {
  @Environment(\.dashboardTheme) private var theme
  let account: AccountRecord?
  let snapshot: UsageSnapshot?
  let allAccounts: [AccountRecord]
  let snapshots: [UUID: UsageSnapshot]
  let activeAccountCount: Int
  let providerCount: Int
  let lastUpdatedAt: Date?

  private var accent: Color {
    account.map { theme.accent(for: $0.provider) } ?? theme.primary
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
      if allAccounts.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 18) {
            ForEach(allAccounts) { item in
              AccountOverviewRing(account: item, snapshot: snapshots[item.id])
            }
          }
          .padding(.horizontal, 1)
        }
      } else {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Text(account?.label ?? "等待添加账号")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
            Text(primaryValue)
              .font(.system(size: 38, weight: .bold, design: .rounded))
              .foregroundStyle(theme.primaryText)
            Text(primaryLabel)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(accent)
          }
          Spacer()
          ZStack {
            Circle().stroke(theme.surfaceRaised, lineWidth: 9)
            Circle()
              .trim(from: 0, to: progress ?? 0)
              .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: account == nil ? "chart.pie.fill" : "bolt.fill")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(accent)
          }
          .frame(width: 82, height: 82)
        }
      }

      Divider().overlay(theme.border)

      HStack(spacing: 0) {
        SummaryMetric(value: "\(activeAccountCount)", label: "启用账号")
        Divider().frame(height: 34).overlay(theme.border)
        SummaryMetric(value: "\(providerCount)", label: "平台")
        Divider().frame(height: 34).overlay(theme.border)
        SummaryMetric(
          value: lastUpdatedAt?.formatted(date: .omitted, time: .shortened) ?? "--",
          label: "最近更新"
        )
      }
    }
    .padding(20)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
  }
}

private struct SummaryMetric: View {
  @Environment(\.dashboardTheme) private var theme
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
        .foregroundStyle(theme.secondaryText)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct EmptyAccountsView: View {
  @Environment(\.dashboardTheme) private var theme
  let hasAccounts: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: hasAccounts ? "line.3.horizontal.decrease.circle" : "person.crop.circle.badge.plus")
        .font(.system(size: 28))
        .foregroundStyle(theme.secondary)
      Text(hasAccounts ? "这个平台还没有账号" : "还没有账号")
        .font(.system(size: 16, weight: .bold))
      Text(hasAccounts ? "切换到其他平台查看" : "点右上角 + 添加账号")
        .font(.system(size: 12))
        .foregroundStyle(theme.secondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 150)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
  }
}

private struct AccountDashboardCard: View {
  @Environment(\.dashboardTheme) private var theme
  let account: AccountRecord
  let snapshot: UsageSnapshot?
  let cooldownUntil: Date?
  let recommended: Bool
  let health: CredentialHealth
  let usesAPIKey: Bool
  let onRefresh: () async -> Void
  let onReauthenticate: () async -> Void
  let onQueryResetCredits: () async -> Void
  let onQueryCodexModels: () async -> Void
  let onResetCodexQuota: () async -> Void
  let onRename: () -> Void
  let onToggle: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onDelete: () -> Void

  @State private var refreshing = false
  @State private var reauthenticating = false

  private var accent: Color { theme.accent(for: account.provider) }

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
                .background(theme.success, in: Capsule())
            }
          }
          HStack(spacing: 4) {
            Text(account.provider.title)
            Text(usesAPIKey ? "· API Key" : "· OAuth")
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.secondaryText)
        }
        Spacer()
        CredentialStatusPill(health: health)
        accountMenu
      }

      if let snapshot {
        SnapshotDashboardBody(
          snapshot: snapshot,
          accent: accent,
          cooldownUntil: cooldownUntil,
          onQueryResetCredits: onQueryResetCredits,
          onQueryCodexModels: onQueryCodexModels,
          onResetCodexQuota: onResetCodexQuota
        )
      } else {
        HStack(spacing: 8) {
          Image(systemName: "clock")
          Text("等待首次刷新")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
      }

      Divider().overlay(theme.border)

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
          Label(
            reauthenticating ? "认证中" : (usesAPIKey ? "更新 Key" : "重新认证"),
            systemImage: "key"
          )
        }
        .disabled(reauthenticating)

        Spacer()
        if !account.isEnabled {
          Text("已停用")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.warning)
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(accent)
      .buttonStyle(.plain)
    }
    .padding(16)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.border, lineWidth: 1))
    .opacity(account.isEnabled ? 1 : 0.62)
  }

  private var accountMenu: some View {
    Menu {
      Button(action: onRename) { Label("重命名", systemImage: "pencil") }
      Button(action: onToggle) {
        Label(account.isEnabled ? "停用" : "启用", systemImage: account.isEnabled ? "pause.circle" : "play.circle")
      }
      Button(action: onMoveUp) { Label("上移", systemImage: "arrow.up") }
      Button(action: onMoveDown) { Label("下移", systemImage: "arrow.down") }
      Divider()
      Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(theme.surfaceRaised, in: Circle())
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
  @Environment(\.dashboardTheme) private var theme
  let snapshot: UsageSnapshot
  let accent: Color
  let cooldownUntil: Date?
  let onQueryResetCredits: () async -> Void
  let onQueryCodexModels: () async -> Void
  let onResetCodexQuota: () async -> Void

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
        .foregroundStyle(statusColor(kind, theme: theme))
      }

      if let balance = snapshot.balance {
        HStack(alignment: .firstTextBaseline) {
          Text("可用余额")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondaryText)
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
                .foregroundStyle(theme.secondaryText)
              Text(metric.value)
                .font(.system(size: 15, weight: .bold))
            }
          }
        }
      } else {
        Text("暂无可显示额度")
          .font(.system(size: 12))
          .foregroundStyle(theme.secondaryText)
      }

      if !snapshot.availableModels.isEmpty {
        AvailableModelsRow(models: snapshot.availableModels, accent: accent)
      }

      if let tokenUsage = snapshot.codexTokenUsage, tokenUsage.hasData {
        CodexTokenUsageSummaryView(
          usage: tokenUsage,
          modelUsage: snapshot.codexModelUsage,
          accent: accent,
          allowsModelQuery: snapshot.authenticationMode != .apiKey,
          onQueryModels: onQueryCodexModels
        )
      }

      if snapshot.provider == .codex, !snapshot.windows.isEmpty {
        CodexResetSchedule(
          windows: snapshot.windows,
          resetCredits: snapshot.codexResetCredits,
          accent: accent,
          onQuery: onQueryResetCredits,
          onReset: onResetCodexQuota
        )
      }

      HStack(spacing: 7) {
        Text("更新 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
        if snapshot.stale {
          Text("缓存")
            .foregroundStyle(theme.warning)
        }
        if let plan = snapshot.plan, !plan.isEmpty {
          Text(plan)
            .lineLimit(1)
        }
      }
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(theme.secondaryText)
    }
  }

  private func healthText(_ kind: ProviderErrorKind) -> String {
    snapshot.stale && hasCachedData ? "缓存 · \(kind.shortLabel)" : kind.shortLabel
  }

  private var hasCachedData: Bool {
    !snapshot.windows.isEmpty
      || !snapshot.metrics.isEmpty
      || !snapshot.availableModels.isEmpty
      || snapshot.balance != nil
      || snapshot.codexTokenUsage?.hasData == true
  }
}

private struct AvailableModelsRow: View {
  @Environment(\.dashboardTheme) private var theme
  let models: [String]
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Label("可用模型", systemImage: "cpu")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(accent)
        Spacer()
        Text("\(models.count)")
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundStyle(theme.secondaryText)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(models, id: \.self) { model in
            Text(model)
              .font(.system(size: 9, weight: .medium))
              .lineLimit(1)
              .padding(.horizontal, 7)
              .frame(height: 24)
              .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 4))
          }
        }
      }
    }
  }
}

private struct AccountOverviewRing: View {
  @Environment(\.dashboardTheme) private var theme
  let account: AccountRecord
  let snapshot: UsageSnapshot?

  private var accent: Color { theme.accent(for: account.provider) }
  private var progress: Double? {
    snapshot?.windows.map(\.remainingPercent).min().map { min(1, max(0, $0 / 100)) }
  }
  private var value: String {
    if let balance = snapshot?.balance { return "\(balance.symbol)\(String(format: "%.2f", balance.total))" }
    if let progress { return "\(Int((progress * 100).rounded()))%" }
    return "--"
  }

  var body: some View {
    VStack(spacing: 7) {
      ZStack {
        Circle().stroke(theme.surfaceRaised, lineWidth: 7)
        Circle()
          .trim(from: 0, to: progress ?? (snapshot?.balance == nil ? 0 : 1))
          .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(value)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .minimumScaleFactor(0.58)
          .lineLimit(1)
          .padding(6)
      }
      .frame(width: 72, height: 72)
      Text(account.label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(theme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(width: 84)
    }
  }
}

private struct CodexTokenUsageSummaryView: View {
  @Environment(\.dashboardTheme) private var theme
  let usage: CodexTokenUsageSummary
  let modelUsage: CodexModelUsageSummary?
  let accent: Color
  let allowsModelQuery: Bool
  let onQueryModels: () async -> Void
  @State private var queryingModels = false

  private var latestBucket: CodexDailyTokenUsage? {
    usage.dailyUsageBuckets.max { $0.startDate < $1.startDate }
  }

  private var items: [(label: String, value: String)] {
    var values: [(String, String)] = []
    if let lifetime = usage.lifetimeTokens {
      values.append(("累计 Token", compactTokens(lifetime)))
    }
    if let peak = usage.peakDailyTokens {
      values.append(("单日峰值", compactTokens(peak)))
    }
    if let streak = usage.currentStreakDays {
      values.append(("当前连续天数", dayCount(streak)))
    }
    if let streak = usage.longestStreakDays {
      values.append(("最长连续天数", dayCount(streak)))
    }
    if values.count < 4, let latestBucket {
      let label = Calendar.current.isDateInToday(latestBucket.startDate)
        ? "今日 Token"
        : latestBucket.startDate.formatted(.dateTime.month().day())
      values.append((label, compactTokens(latestBucket.tokens)))
    }
    return Array(values.prefix(4))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label {
        Text(allowsModelQuery
          ? LocalizedStringKey("Codex Token 用量")
          : LocalizedStringKey("OpenAI Token 用量"))
      } icon: {
        Image(systemName: "number")
      }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(accent)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
        alignment: .leading,
        spacing: 10
      ) {
        ForEach(Array(items.enumerated()), id: \.offset) { item in
          VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(item.element.label))
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
            Text(item.element.value)
              .font(.system(size: 15, weight: .bold, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
        }
      }

      if let modelUsage, !modelUsage.groups.isEmpty {
        Divider().overlay(theme.border)
        HStack(spacing: 8) {
          Text("模型明细")
            .font(.system(size: 10, weight: .semibold))
          Group {
            if allowsModelQuery {
              Text("\(modelUsage.returnedThreadCount) 个线程")
            } else {
              Text("\(modelUsage.returnedThreadCount) 次请求")
            }
          }
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(theme.secondaryText)
          Spacer()
          if let micros = modelUsage.estimatedUsageUSDMicros {
            Text("约 $\(Double(micros) / 1_000_000, specifier: "%.4f")")
              .font(.system(size: 10, weight: .bold, design: .rounded))
              .foregroundStyle(accent)
          }
        }
        ForEach(modelUsage.groups.prefix(6)) { group in
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(group.model)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
              Spacer()
              Text(compactTokens(group.totalTokens))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            }
            Text(modelDetail(group))
              .font(.system(size: 8, weight: .medium))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.65)
          }
        }
        if modelUsage.isPartial {
          Text(allowsModelQuery
            ? LocalizedStringKey("模型汇总来自最近一页云端任务")
            : LocalizedStringKey("模型汇总仅包含本次返回的用量页"))
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(theme.secondaryText)
        }
      }

      if allowsModelQuery {
        Button {
          queryingModels = true
          Task {
            await onQueryModels()
            queryingModels = false
          }
        } label: {
          Label(queryingModels ? "查询中" : "更新模型明细", systemImage: "arrow.clockwise")
            .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .disabled(queryingModels)
      }
    }
    .padding(.top, 2)
  }

  private func compactTokens(_ value: Int64) -> String {
    let number = Double(value)
    if abs(number) >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
    if abs(number) >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
    if abs(number) >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
  }

  private func dayCount(_ value: Int64) -> String {
    String.localizedStringWithFormat(NSLocalizedString("%lld 天", comment: ""), value)
  }

  private func modelDetail(_ usage: CodexModelTokenUsage) -> String {
    var parts = [
      "\(NSLocalizedString("输入", comment: "")) \(compactTokens(usage.inputTokens))",
      "\(NSLocalizedString("缓存", comment: "")) \(compactTokens(usage.cachedInputTokens))",
      "\(NSLocalizedString("输出", comment: "")) \(compactTokens(usage.outputTokens))",
    ]
    if let effort = usage.reasoningEffort, !effort.isEmpty { parts.append(effort) }
    if let speed = usage.speed, !speed.isEmpty { parts.append(speed) }
    return parts.joined(separator: " · ")
  }
}

private struct CodexResetSchedule: View {
  @Environment(\.dashboardTheme) private var theme
  let windows: [UsageWindow]
  let resetCredits: CodexResetCreditSummary?
  let accent: Color
  let onQuery: () async -> Void
  let onReset: () async -> Void

  @State private var querying = false
  @State private var resetting = false
  @State private var confirmingReset = false

  private var shortWindow: UsageWindow? {
    windows.first { $0.label.lowercased().contains("h") }
  }

  private var weeklyWindow: UsageWindow? {
    windows.first { $0.label == "周" || $0.label.lowercased().contains("week") }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Label("Codex 额度与重置", systemImage: "clock.arrow.2.circlepath")
          .foregroundStyle(accent)
          .lineLimit(1)
        Spacer()
        Text(resetCredits.map { "可用 \($0.availableCount) 次" } ?? "次数未查询")
          .foregroundStyle(theme.secondaryText)
          .lineLimit(1)
      }
      .font(.system(size: 9, weight: .semibold))

      HStack(spacing: 12) {
        if let reset = shortWindow?.resetAt, reset > .now {
          Label("5h · \(resetCountdown(reset))", systemImage: "timer")
        }
        if let reset = weeklyWindow?.resetAt, reset > .now {
          Label("周 · \(resetCountdown(reset))", systemImage: "calendar")
        }
      }
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(theme.secondaryText)
      .lineLimit(1)
      .minimumScaleFactor(0.75)

      if let expiry = resetCredits?.expiresAt.first {
        Text("最早一张重置卡到期：\(expiry.formatted(date: .abbreviated, time: .shortened))")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(theme.secondaryText)
      }

      HStack(spacing: 10) {
        Button {
          querying = true
          Task {
            await onQuery()
            querying = false
          }
        } label: {
          Label(querying ? "查询中" : "查询重置", systemImage: "magnifyingglass")
        }
        .disabled(querying || resetting)

        Button(role: .destructive) {
          confirmingReset = true
        } label: {
          Label(resetting ? "重置中" : "重置额度", systemImage: "arrow.counterclockwise.circle")
        }
        .disabled((resetCredits?.availableCount ?? 0) <= 0 || querying || resetting)
      }
      .font(.system(size: 10, weight: .semibold))
      .buttonStyle(.plain)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
    }
    .padding(10)
    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: theme.compactCardCornerRadius))
    .alert("消耗一次重置机会？", isPresented: $confirmingReset) {
      Button("取消", role: .cancel) {}
      Button("确认重置", role: .destructive) {
        resetting = true
        Task {
          await onReset()
          resetting = false
        }
      }
    } message: {
      Text("当前可用 \(resetCredits?.availableCount ?? 0) 次。确认后会消耗一张 OpenAI 重置卡，并重置适用的额度窗口。")
    }
  }
}

private struct QuotaWindowRow: View {
  @Environment(\.dashboardTheme) private var theme
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
          Capsule().fill(theme.surfaceRaised)
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
        .foregroundStyle(theme.secondaryText)
      }
    }
  }

  private var progressColor: Color {
    if window.remainingPercent <= 15 { return .red }
    if window.remainingPercent <= 35 { return theme.warning }
    return accent
  }
}

private func statusColor(_ kind: ProviderErrorKind, theme: DashboardTheme) -> Color {
  switch kind {
  case .authentication, .configuration: .red
  case .rateLimited, .providerUnavailable, .network: theme.warning
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

private enum AppIconChoice: String, CaseIterable, Identifiable {
  case current
  case classic
  case night

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .current: "翠绿脉冲"
    case .classic: "经典绿环"
    case .night: "深色霓虹"
    }
  }

  var previewAsset: String {
    switch self {
    case .current: "AppIconCurrentPreview"
    case .classic: "AppIconClassicPreview"
    case .night: "AppIconNightPreview"
    }
  }

  var alternateIconName: String? {
    switch self {
    case .current: "AppIconClassic"
    case .classic: nil
    case .night: "AppIconNight"
    }
  }

  static func resolve(alternateIconName: String?) -> AppIconChoice {
    allCases.first { $0.alternateIconName == alternateIconName } ?? .classic
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Binding var selectedTheme: DashboardTheme
  @Binding var aggregateHistory: Bool
  @Binding var overviewAutoRefreshSeconds: Int
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var autoMinutes = 15
  @State private var refreshIntervalPreset = 15
  @State private var customRefreshMinutes = 45
  @State private var backgroundRefreshEnabled = true
  @State private var confirmingHistoryClear = false
  @State private var selectedAppIcon: AppIconChoice = .classic
  @State private var isChangingAppIcon = false
  @State private var appIconError: String?
  @State private var checkingForUpdate = false
  @State private var availableUpdate: AvailableAppUpdate?
  @State private var updateMessage: String?

  var body: some View {
    NavigationStack {
      settingsForm
    }
    .environment(\.dashboardTheme, selectedTheme)
    .preferredColorScheme(selectedTheme.preferredColorScheme)
  }

  private var settingsForm: some View {
    Form {
      appearanceSection
      appIconSection
      networkSection
      chartSection
      overviewRefreshSection
      backgroundRefreshSection
      dataSection
      updateSection
      privacySection
      compatibilitySection
      credentialSection
      accountScopeSection
    }
    .scrollContentBackground(.hidden)
    .background(selectedTheme.background)
    .navigationTitle("设置")
    .alert("清除走势历史？", isPresented: $confirmingHistoryClear) {
      Button("取消", role: .cancel) {}
      Button("清除", role: .destructive) {
        Task { await model.clearUsageHistory() }
      }
    } message: {
      Text("只会删除本机统计记录，不会删除账号或登录凭据。")
    }
    .alert(
      "在线更新",
      isPresented: Binding(
        get: { updateMessage != nil },
        set: { if !$0 { updateMessage = nil } }
      )
    ) {
      if let update = availableUpdate {
        Button("打开发布页") { openURL(update.releaseURL) }
      }
      Button("好", role: .cancel) {
        updateMessage = nil
        availableUpdate = nil
      }
    } message: {
      Text(updateMessage ?? "")
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("完成") { dismiss() }
      }
    }
    .task { await loadSettings() }
    .onChange(of: autoMinutes, perform: saveAutoRefreshMinutes)
    .onChange(of: refreshIntervalPreset) { preset in
      autoMinutes = preset > 0 ? preset : customRefreshMinutes
    }
    .onChange(of: customRefreshMinutes) { minutes in
      if refreshIntervalPreset == -1 { autoMinutes = minutes }
    }
    .onChange(of: backgroundRefreshEnabled, perform: saveBackgroundRefresh)
    .onChange(of: selectedTheme, perform: saveTheme)
    .onChange(of: aggregateHistory) { enabled in
      Task { await SharedStore.shared.setAggregateHistory(enabled) }
    }
    .onChange(of: overviewAutoRefreshSeconds) { seconds in
      Task { await SharedStore.shared.setOverviewAutoRefreshSeconds(seconds) }
    }
  }

  private var appearanceSection: some View {
    Section("外观") {
      Picker("界面主题", selection: $selectedTheme) {
        ForEach(DashboardTheme.allCases) { theme in
          Text(theme.title).tag(theme)
        }
      }
      .pickerStyle(.menu)
      ThemePreviewRow(theme: selectedTheme)
    }
  }

  private var appIconSection: some View {
    Section("App 图标") {
      AppIconPicker(
        selection: selectedAppIcon,
        isChanging: isChangingAppIcon,
        onSelect: selectAppIcon
      )
      if !UIApplication.shared.supportsAlternateIcons {
        Text("当前设备或安装方式不支持切换 App 图标。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if let appIconError {
        Text("切换失败：\(appIconError)")
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var networkSection: some View {
    Section("网络") {
      NavigationLink {
        ProxySettingsView()
      } label: {
        Label("HTTP / SOCKS5 代理", systemImage: "network")
      }
    }
  }

  private var chartSection: some View {
    Section("走势图") {
      Toggle("全部页合并走势图", isOn: $aggregateHistory)
      Text(
        aggregateHistory
          ? "“全部”页会在一张图中叠加各平台曲线；余额类数据仍单独展示。"
          : "“全部”页按平台分别展示走势图。"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }

  private var overviewRefreshSection: some View {
    Section("总览自动刷新") {
      Picker("前台刷新间隔", selection: $overviewAutoRefreshSeconds) {
        Text("关闭").tag(0)
        Text("30 秒").tag(30)
        Text("1 分钟").tag(60)
        Text("5 分钟").tag(300)
        Text("10 分钟").tag(600)
      }
      .pickerStyle(.menu)
      Text("仅在 QuotaPulse 位于前台时定时刷新；进入后台后停止，并遵守账号冷却时间。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var backgroundRefreshSection: some View {
    Section("后台刷新") {
      Toggle("允许后台刷新", isOn: $backgroundRefreshEnabled)
      if backgroundRefreshEnabled {
        Picker("最早刷新间隔", selection: $refreshIntervalPreset) {
          Text("10 分钟").tag(10)
          Text("15 分钟").tag(15)
          Text("30 分钟").tag(30)
          Text("1 小时").tag(60)
          Text("2 小时").tag(120)
          Text("自定义").tag(-1)
        }
        if refreshIntervalPreset == -1 {
          Stepper(
            "自定义：\(customRefreshMinutes) 分钟",
            value: $customRefreshMinutes,
            in: 10...1_440,
            step: 5
          )
        }
      }
      Text("App 未被划掉时会向 iOS 申请后台刷新；具体执行时刻由系统根据电量、网络和使用习惯调度。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var dataSection: some View {
    Section("数据") {
      NavigationLink {
        BackupSettingsView(model: model)
      } label: {
        Label("导入与导出", systemImage: "arrow.up.arrow.down.square")
      }
      Text("配置文件可在 iOS 与 Android 之间共用。完整备份可包含登录凭据。")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button(role: .destructive) {
        confirmingHistoryClear = true
      } label: {
        Label("清除本机走势历史", systemImage: "trash")
      }
      .disabled(model.usageHistory.isEmpty)
    }
  }

  private var updateSection: some View {
    Section("在线更新") {
      Button(action: checkForUpdate) {
        HStack {
          Label(checkingForUpdate ? "正在检查" : "检查更新", systemImage: "arrow.down.app")
          Spacer()
          if checkingForUpdate { ProgressView() }
        }
      }
      .disabled(checkingForUpdate)
      Text("可检查 GitHub Release；第三方签名安装仍需下载 IPA 后重新签名。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var privacySection: some View {
    Section("隐私与本机存储") {
      Label("配置仅保存在本机", systemImage: "lock.shield")
      Text("账号配置和走势图保存在本机；Token 与 API Key 由系统 Keychain 保护。QuotaPulse 未在程序中使用自建服务器。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var compatibilitySection: some View {
    Section("版本与兼容性") {
      Label(
        AppConfig.isAppOnlyBuild ? "单 App 兼容版" : "App + Widget 完整版",
        systemImage: AppConfig.isAppOnlyBuild ? "iphone" : "rectangle.stack.badge.person.crop"
      )
      LabeledContent("系统要求", value: "iOS 16+")
      if AppConfig.isAppOnlyBuild {
        Text("当前安装包不包含桌面小组件，适合只有一套 P12 / 描述文件或使用第三方重签工具的场景。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var credentialSection: some View {
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
  }

  private var accountScopeSection: some View {
    Section("账号参与范围") {
      ForEach(model.accounts) { account in
        Toggle(
          account.label,
          isOn: Binding(
            get: { account.isEnabled },
            set: { value in Task { await model.setEnabled(account, enabled: value) } }
          )
        )
      }
      Text("停用后不参与全部刷新、推荐账号和桌面小组件，但仍保留在账号列表，可单独刷新或重新启用。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func loadSettings() async {
    let savedMinutes = await SharedStore.shared.autoRefreshMinutes()
    autoMinutes = savedMinutes
    if [10, 15, 30, 60, 120].contains(savedMinutes) {
      refreshIntervalPreset = savedMinutes
    } else {
      refreshIntervalPreset = -1
      customRefreshMinutes = savedMinutes
    }
    backgroundRefreshEnabled = await SharedStore.shared.backgroundRefreshEnabled()
    selectedAppIcon = AppIconChoice.resolve(
      alternateIconName: UIApplication.shared.alternateIconName
    )
  }

  private func saveAutoRefreshMinutes(_ newValue: Int) {
    Task {
      await SharedStore.shared.setAutoRefreshMinutes(newValue)
      WidgetCenter.shared.reloadAllTimelines()
      if backgroundRefreshEnabled { BackgroundRefreshManager.scheduleIfEnabled() }
    }
  }

  private func saveBackgroundRefresh(_ enabled: Bool) {
    Task {
      await SharedStore.shared.setBackgroundRefreshEnabled(enabled)
      BackgroundRefreshManager.setEnabled(enabled)
    }
  }

  private func saveTheme(_ newTheme: DashboardTheme) {
    Task {
      await SharedStore.shared.setDashboardTheme(newTheme)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  private func selectAppIcon(_ choice: AppIconChoice) {
    guard UIApplication.shared.supportsAlternateIcons,
          !isChangingAppIcon,
          choice != selectedAppIcon else { return }
    isChangingAppIcon = true
    appIconError = nil
    UIApplication.shared.setAlternateIconName(choice.alternateIconName) { error in
      DispatchQueue.main.async {
        isChangingAppIcon = false
        if let error {
          appIconError = error.localizedDescription
          selectedAppIcon = AppIconChoice.resolve(
            alternateIconName: UIApplication.shared.alternateIconName
          )
        } else {
          selectedAppIcon = choice
        }
      }
    }
  }

  private func checkForUpdate() {
    checkingForUpdate = true
    availableUpdate = nil
    Task {
      do {
        let update = try await UpdateChecker.check()
        await MainActor.run {
          availableUpdate = update
          updateMessage = update.map { "发现新版本 \($0.version)" } ?? "当前已是最新版本"
          checkingForUpdate = false
        }
      } catch {
        await MainActor.run {
          updateMessage = error.localizedDescription
          checkingForUpdate = false
        }
      }
    }
  }
}

private struct AppIconPicker: View {
  let selection: AppIconChoice
  let isChanging: Bool
  let onSelect: (AppIconChoice) -> Void

  private let columns = Array(
    repeating: GridItem(.flexible(minimum: 72), spacing: 12),
    count: 3
  )

  var body: some View {
    LazyVGrid(columns: columns, spacing: 12) {
      ForEach(AppIconChoice.allCases) { choice in
        Button {
          onSelect(choice)
        } label: {
          VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
              Image(choice.previewAsset)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
              if selection == choice {
                Image(systemName: "checkmark.circle.fill")
                  .symbolRenderingMode(.palette)
                  .foregroundStyle(.white, Color.accentColor)
                  .font(.system(size: 20, weight: .semibold))
                  .offset(x: 5, y: -5)
              }
            }
            Text(choice.title)
              .font(.system(size: 12, weight: selection == choice ? .semibold : .regular))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChanging || selection == choice)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selection == choice ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }
}

private struct ThemePreviewRow: View {
  let theme: DashboardTheme

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 5) {
        ForEach(Array(theme.previewColors.enumerated()), id: \.offset) { item in
          Circle().fill(item.element).frame(width: 16, height: 16)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(theme.title).font(.system(size: 13, weight: .semibold))
        Text(theme.subtitle).font(.system(size: 10)).foregroundStyle(theme.secondaryText)
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }
}
