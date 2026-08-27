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
          if model.accounts.isEmpty { EmptyAccountsView() }
          else { ForEach(model.accounts) { account in
            AccountRow(account:account,snapshot:model.snapshots[account.id],cooldownUntil:model.cooldownUntil(account),recommended:recommendedAccountIDs.contains(account.id),health:model.credentialHealth(account),onRefresh:{await model.refresh(account)},onReauth:{await reauthenticate(account)},onToggle:{enabled in await model.setEnabled(account,enabled:enabled)})
              .swipeActions(edge:.trailing,allowsFullSwipe:false){Button(role:.destructive){Task{await model.delete(account)}}label:{Label("删除",systemImage:"trash")};Button{renameTarget=account;renameText=account.label}label:{Label("重命名",systemImage:"pencil")}.tint(.blue)}
              .swipeActions(edge:.leading,allowsFullSwipe:false){Button{Task{await model.move(account,offset:-1)}}label:{Label("上移",systemImage:"arrow.up")}.tint(.indigo);Button{Task{await model.move(account,offset:1)}}label:{Label("下移",systemImage:"arrow.down")}.tint(.teal)}
          }}
        } header:{HStack{Text("账号");Spacer();if !model.accounts.isEmpty{Button{Task{await model.refreshAll()}}label:{Label("全部刷新",systemImage:"arrow.clockwise").labelStyle(.iconOnly)}.disabled(model.isBusy)}}}
        if AppConfig.isAppOnlyBuild {
          Section("当前版本") {
            Label("单 App 兼容版，不包含桌面小组件", systemImage: "iphone")
            Label("支持 App 内按钮和下拉刷新", systemImage: "arrow.clockwise.circle")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        } else {
          Section("小组件") {
            if #available(iOS 17.0, *) {
              Label("小组件中的刷新按钮会原地刷新", systemImage: "arrow.clockwise.circle")
            } else {
              Label("iOS 16 点小组件后在 App 内刷新", systemImage: "hand.tap")
            }
            Label("完整小组件版需要独立的 Widget 描述文件", systemImage: "checkmark.shield")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("AI Quota")
      .toolbar{ToolbarItem(placement:.navigationBarLeading){Button{showingSettings=true}label:{Image(systemName:"gearshape")}};ToolbarItem(placement:.navigationBarTrailing){Menu{Button("Codex · ChatGPT 登录"){loginOAuth(.codex)};Button("Claude · OAuth 登录"){loginOAuth(.claude)};Button("Kimi · OAuth 登录"){loginOAuth(.kimi)};Divider();Button("DeepSeek · API Key"){apiProvider=.deepseek};Button("MiniMax · Coding Key"){apiProvider=.minimax};Button("GLM · Coding Key"){apiProvider=.glm};Button("GitHub Copilot · Token"){apiProvider=.copilot}}label:{Image(systemName:"plus")}}}
      .overlay{if model.isBusy{ZStack{Color.black.opacity(0.08).ignoresSafeArea();ProgressView("处理中…").padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))}}}
      .task{await model.load()}.refreshable{await model.refreshAll()}
      .alert("错误",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0{model.errorMessage=nil}})){Button("好",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
      .alert("重命名账号",isPresented:Binding(get:{renameTarget != nil},set:{if !$0{renameTarget=nil}})){TextField("账号名称",text:$renameText);Button("取消",role:.cancel){renameTarget=nil};Button("保存"){if let target=renameTarget{Task{await model.rename(target,label:renameText)}};renameTarget=nil}}
      .sheet(item:$apiProvider){provider in APIKeyEntryView(provider:provider){key,baseURL in await model.addAPIKey(provider:provider,key:key,baseURL:baseURL)}}
      .sheet(isPresented:$showingSettings){SettingsView(model:model)}
    }
  }
  private var recommendedAccountIDs:Set<UUID>{Set(ProviderID.allCases.compactMap{provider in model.accounts.filter{$0.isEnabled&&$0.provider==provider}.compactMap{account->(UUID,Double)? in guard let snapshot=model.snapshots[account.id],!snapshot.stale else{return nil};let score:Double;if let balance=snapshot.balance{score=balance.total}else if let minimum=snapshot.windows.map(\.remainingPercent).min(){score=minimum}else{return nil};return(account.id,score)}.max(by:{$0.1<$1.1})?.0})}
  private func loginOAuth(_ provider:ProviderID){Task{@MainActor in guard let presenter=UIApplication.shared.activeTopViewController() else{model.errorMessage="无法打开登录页面";return};switch provider{case .codex:await model.addCodex(presenter:presenter);case .claude:await model.addClaude(presenter:presenter);case .kimi:await model.addKimi(presenter:presenter);default:break}}}
  private func reauthenticate(_ account:AccountRecord) async{guard [.codex,.claude,.kimi].contains(account.provider) else{await MainActor.run{apiProvider=account.provider};return};guard let presenter=await MainActor.run(body:{UIApplication.shared.activeTopViewController()}) else{await MainActor.run{model.errorMessage="无法打开重新认证页面"};return};await model.reauthenticate(account,presenter:presenter)}
}

private struct EmptyAccountsView: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.crop.circle.badge.plus")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("还没有账号").font(.headline)
      Text("右上角 + 添加 Codex、Claude、Kimi 或 API 平台。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }
}

private struct AccountRow:View{
  let account:AccountRecord;let snapshot:UsageSnapshot?;let cooldownUntil:Date?;let recommended:Bool;let health:CredentialHealth;let onRefresh:() async->Void;let onReauth:() async->Void;let onToggle:(Bool) async->Void
  @State private var refreshing=false;@State private var reauthing=false
  var body:some View{VStack(alignment:.leading,spacing:8){HStack{VStack(alignment:.leading,spacing:2){HStack(spacing:5){Text(account.label).font(.headline);if recommended{Label("推荐",systemImage:"star.fill").labelStyle(.iconOnly).foregroundStyle(.yellow).accessibilityLabel("推荐账号")}};HStack(spacing:6){Text(account.provider.title);Label(health.title,systemImage:health.icon).foregroundStyle(health.color)}.font(.caption)};Spacer();Toggle("显示",isOn:Binding(get:{account.isEnabled},set:{value in Task{await onToggle(value)}})).labelsHidden();Button{refreshing=true;Task{await onRefresh();refreshing=false}}label:{refreshing ? AnyView(ProgressView().controlSize(.small)):AnyView(Image(systemName:"arrow.clockwise"))}.buttonStyle(.borderless)}
    if let snapshot{SnapshotSummary(snapshot:snapshot,cooldownUntil:cooldownUntil)}else{Text("尚未获取额度").font(.caption).foregroundStyle(.secondary)}
    HStack{Button{reauthing=true;Task{await onReauth();reauthing=false}}label:{Label(reauthing ? "认证中…":"重新认证",systemImage:"person.badge.key")}.buttonStyle(.borderless).font(.caption);Spacer()}
  }.padding(.vertical,3)}
}

private struct SnapshotSummary:View{
  let snapshot:UsageSnapshot;let cooldownUntil:Date?
  var body:some View{VStack(alignment:.leading,spacing:5){if let kind=snapshot.effectiveErrorKind{HStack(spacing:4){Image(systemName:statusIcon(kind));Text(healthText(kind));if let cooldownUntil,cooldownUntil > .now{Text("· \(resetCountdown(cooldownUntil)) 后重试")}}.font(.caption).foregroundStyle(statusColor(kind))}
    if let balance=snapshot.balance{HStack{Text("余额");Spacer();Text("\(balance.symbol)\(balance.total,specifier:"%.2f")").fontWeight(.semibold)}.font(.subheadline)}else if !snapshot.windows.isEmpty{VStack(spacing:5){ForEach(snapshot.windows.prefix(3)){window in VStack(spacing:2){HStack{Text(window.label).frame(width:48,alignment:.leading);ProgressView(value:window.remainingPercent,total:100);Text("\(Int(window.remainingPercent.rounded()))%").monospacedDigit().frame(width:44,alignment:.trailing)}.font(.caption);if let reset=window.resetAt,reset > .now{HStack{Spacer();Text("重置 \(resetCountdown(reset))").font(.caption2).foregroundStyle(.secondary)}}}}}else{HStack{ForEach(snapshot.metrics.prefix(2)){metric in Text("\(metric.label)：\(metric.value)")}}.font(.caption)}
    HStack(spacing:6){Text("更新 \(snapshot.fetchedAt.formatted(date:.omitted,time:.shortened))");if snapshot.stale{Text("缓存").foregroundStyle(.orange)}}.font(.caption2).foregroundStyle(.secondary)
  }}
  private func healthText(_ kind:ProviderErrorKind)->String{let base=snapshot.stale&&hasCachedData ? "缓存 · \(kind.shortLabel)":kind.shortLabel;return base}
  private var hasCachedData:Bool{!snapshot.windows.isEmpty||!snapshot.metrics.isEmpty||snapshot.balance != nil}
  private func statusColor(_ kind:ProviderErrorKind)->Color{switch kind{case .authentication,.configuration:.red;case .rateLimited,.providerUnavailable,.network:.orange;case .invalidResponse,.unknown:.yellow}}
  private func statusIcon(_ kind:ProviderErrorKind)->String{switch kind{case .authentication:"person.crop.circle.badge.exclamationmark";case .rateLimited:"hourglass";case .providerUnavailable:"exclamationmark.icloud";case .network:"wifi.exclamationmark";case .invalidResponse:"exclamationmark.triangle";case .configuration:"gear.badge.xmark";case .unknown:"exclamationmark.circle"}}
}

private func resetCountdown(_ date:Date)->String{let seconds=max(0,Int(date.timeIntervalSinceNow));let days=seconds/86400;let hours=(seconds%86400)/3600;let minutes=(seconds%3600)/60;if days>0{return "\(days)天 \(hours)小时"};if hours>0{return "\(hours)小时 \(minutes)分"};return "\(max(1,minutes))分"}
struct CredentialHealth{let title:String;let icon:String;let color:Color}

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
            Text("这是 WidgetKit 的最早刷新时间，实际自动刷新由 iOS 调度；iOS 17 以上可直接使用小组件刷新按钮。")
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
              Label(health.title, systemImage: health.icon).foregroundStyle(health.color).font(.caption)
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
      .navigationTitle("设置")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
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
