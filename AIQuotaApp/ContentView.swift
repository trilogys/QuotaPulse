import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
  @StateObject private var model = AppModel()
  @State private var apiProvider: ProviderID?
  @State private var renameTarget: AccountRecord?
  @State private var renameText = ""
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          if model.accounts.isEmpty {
            ContentUnavailableView(
              "还没有账号",
              systemImage: "person.crop.circle.badge.plus",
              description: Text("右上角 + 添加 Codex、Claude、Kimi 或 API 平台。")
            )
          } else {
            ForEach(model.accounts) { account in
              AccountRow(
                account: account,
                snapshot: model.snapshots[account.id],
                recommended: recommendedAccountIDs.contains(account.id),
                onRefresh: { await model.refresh(account) },
                onToggle: { enabled in await model.setEnabled(account, enabled: enabled) }
              )
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  Task { await model.delete(account) }
                } label: {
                  Label("删除", systemImage: "trash")
                }
                Button {
                  renameTarget = account
                  renameText = account.label
                } label: {
                  Label("重命名", systemImage: "pencil")
                }
                .tint(.blue)
              }
              .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                  Task { await model.move(account, offset: -1) }
                } label: {
                  Label("上移", systemImage: "arrow.up")
                }
                .tint(.indigo)
                Button {
                  Task { await model.move(account, offset: 1) }
                } label: {
                  Label("下移", systemImage: "arrow.down")
                }
                .tint(.teal)
              }
            }
          }
        } header: {
          HStack {
            Text("账号")
            Spacer()
            if !model.accounts.isEmpty {
              Button {
                Task { await model.refreshAll() }
              } label: {
                Label("全部刷新", systemImage: "arrow.clockwise")
                  .labelStyle(.iconOnly)
              }
              .disabled(model.isBusy)
            }
          }
        }

        Section("小组件") {
          Label("小组件中的 ↻ 会原地刷新，不打开 App", systemImage: "arrow.clockwise.circle")
          Label("普通点小组件区域才会进入这里", systemImage: "hand.tap")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .navigationTitle("AI Quota")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
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
          }
        }
      }
      .overlay {
        if model.isBusy {
          ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            ProgressView("处理中…")
              .padding(18)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
          }
        }
      }
      .task { await model.load() }
      .refreshable { await model.refreshAll() }
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
      }
    }
  }

  private var recommendedAccountIDs: Set<UUID> {
    Set(ProviderID.allCases.compactMap { provider in
      model.accounts
        .filter { $0.isEnabled && $0.provider == provider }
        .compactMap { account -> (UUID, Double)? in
          guard let snapshot = model.snapshots[account.id], !snapshot.stale else { return nil }
          let score: Double
          if let balance = snapshot.balance {
            score = balance.total
          } else if let minimum = snapshot.windows.map(\.remainingPercent).min() {
            score = minimum
          } else {
            return nil
          }
          return (account.id, score)
        }
        .max(by: { $0.1 < $1.1 })?.0
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
}

private struct AccountRow: View {
  let account: AccountRecord
  let snapshot: UsageSnapshot?
  let recommended: Bool
  let onRefresh: () async -> Void
  let onToggle: (Bool) async -> Void

  @State private var refreshing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 5) {
            Text(account.label)
              .font(.headline)
            if recommended {
              Label("推荐", systemImage: "star.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.yellow)
                .accessibilityLabel("推荐账号")
            }
          }
          Text(account.provider.title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Toggle(
          "显示",
          isOn: Binding(
            get: { account.isEnabled },
            set: { value in Task { await onToggle(value) } }
          )
        )
        .labelsHidden()
        Button {
          refreshing = true
          Task {
            await onRefresh()
            refreshing = false
          }
        } label: {
          if refreshing {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .buttonStyle(.borderless)
      }

      if let snapshot {
        SnapshotSummary(snapshot: snapshot)
      } else {
        Text("尚未获取额度")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct SnapshotSummary: View {
  let snapshot: UsageSnapshot

  var body: some View {
    if let balance = snapshot.balance {
      HStack {
        Text("余额")
        Spacer()
        Text("\(balance.symbol)\(balance.total, specifier: "%.2f")")
          .fontWeight(.semibold)
      }
      .font(.subheadline)
    } else if !snapshot.windows.isEmpty {
      VStack(spacing: 5) {
        ForEach(snapshot.windows.prefix(3)) { window in
          HStack {
            Text(window.label)
              .frame(width: 48, alignment: .leading)
            ProgressView(value: window.remainingPercent, total: 100)
            Text("\(Int(window.remainingPercent.rounded()))%")
              .monospacedDigit()
              .frame(width: 44, alignment: .trailing)
          }
          .font(.caption)
        }
      }
    } else {
      HStack {
        ForEach(snapshot.metrics.prefix(2)) { metric in
          Text("\(metric.label)：\(metric.value)")
        }
      }
      .font(.caption)
    }

    HStack(spacing: 6) {
      Text("更新 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
      if snapshot.stale { Text("缓存").foregroundStyle(.orange) }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var autoMinutes = 15

  var body: some View {
    NavigationStack {
      Form {
        Section("自动刷新") {
          Picker("最早刷新间隔", selection: $autoMinutes) {
            Text("10 分钟").tag(10)
            Text("15 分钟").tag(15)
            Text("30 分钟").tag(30)
            Text("1 小时").tag(60)
            Text("2 小时").tag(120)
          }
          Text("这是 WidgetKit 的最早刷新时间，实际自动刷新由 iOS 调度；小组件里的 ↻ 属于用户主动刷新，会立即执行 App Intent。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section("显示账号") {
          ForEach(model.accounts) { account in
            Toggle(
              account.label,
              isOn: Binding(
                get: { account.isEnabled },
                set: { value in Task { await model.setEnabled(account, enabled: value) } }
              ))
          }
        }
      }
      .navigationTitle("设置")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") { dismiss() }
        }
      }
      .task {
        autoMinutes = await SharedStore.shared.autoRefreshMinutes()
      }
      .onChange(of: autoMinutes) { _, newValue in
        Task {
          await SharedStore.shared.setAutoRefreshMinutes(newValue)
          WidgetCenter.shared.reloadAllTimelines()
        }
      }
    }
  }
}
