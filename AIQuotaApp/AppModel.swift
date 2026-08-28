import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
  @Published var accounts: [AccountRecord] = []
  @Published var snapshots: [UUID: UsageSnapshot] = [:]
  @Published var usageHistory: [UsageHistorySample] = []
  @Published var cooldowns: [UUID: Date] = [:]
  @Published var isBusy = false
  @Published var errorMessage: String?
  @Published var statusMessage: String?

  private let keychain = KeychainStore.shared

  func load() async {
    accounts = await SharedStore.shared.accounts()
    var map: [UUID: UsageSnapshot] = [:];var cooldownMap: [UUID: Date] = [:]
    for account in accounts { if let snapshot=await SharedStore.shared.snapshot(for:account.id){map[account.id]=snapshot};if let cooldown=await SharedStore.shared.cooldownUntil(accountID:account.id){cooldownMap[account.id]=cooldown} }
    snapshots=map;cooldowns=cooldownMap
    usageHistory = await SharedStore.shared.history(accountIDs: accounts.map(\.id))
  }

  func exportConfig(includeCredentials:Bool) throws -> PortableConfigDocument { PortableConfigDocument(data:try PortableConfigCodec.encode(accounts:accounts,keychain:keychain,includeCredentials:includeCredentials)) }
  func importConfig(_ data:Data,replace:Bool) async { isBusy=true;defer{isBusy=false};do{let result=try await PortableConfigImporter.shared.importData(data,mode:replace ? .replace:.merge);await load();let skipped=result.skippedAccounts>0 ? "，跳过 \(result.skippedAccounts)":"";let proxy=result.proxyImported ? "，代理已导入":"";statusMessage="\(result.source.title) 导入完成：新增 \(result.added)，更新 \(result.updated)，凭据 \(result.credentialsImported)\(skipped)\(proxy)";await refreshAll()}catch{errorMessage=error.localizedDescription} }

  func cooldownUntil(_ account:AccountRecord)->Date?{cooldowns[account.id]}
  func credentialHealth(_ account:AccountRecord)->CredentialHealth{guard let credential=try? keychain.credential(accountID:account.id)else{return CredentialHealth(title:"需重登",icon:"exclamationmark.triangle.fill",color:.red)};if [.deepseek,.minimax,.glm,.copilot].contains(account.provider){return CredentialHealth(title:"已保存",icon:"checkmark.shield.fill",color:.green)};if let expires=credential.expiresAt{if expires <= .now{return credential.refreshToken?.isEmpty == false ? CredentialHealth(title:"可续期",icon:"arrow.triangle.2.circlepath",color:.orange):CredentialHealth(title:"需重登",icon:"exclamationmark.triangle.fill",color:.red)};if expires.timeIntervalSinceNow < 3600{return CredentialHealth(title:"即将续期",icon:"clock.arrow.circlepath",color:.orange)}};if snapshots[account.id]?.stale == true{return CredentialHealth(title:"缓存中",icon:"icloud.slash",color:.orange)};return CredentialHealth(title:"正常",icon:"checkmark.circle.fill",color:.green)}

  func addCodex(name:String?=nil,presenter:UIViewController)async{await performBusy{let c=try await CodexOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.codex,customLabel:name)}}
  func addClaude(name:String?=nil,presenter:UIViewController)async{await performBusy{let c=try await ClaudeOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.claude,customLabel:name)}}
  func addKimi(name:String?=nil,presenter:UIViewController)async{await performBusy{let c=try await KimiOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.kimi,customLabel:name)}}
  func reauthenticate(_ account:AccountRecord,presenter:UIViewController)async{await performBusy{let credential:Credential;switch account.provider{case .codex:credential=try await CodexOAuthCoordinator().login(presenting:presenter);case .claude:credential=try await ClaudeOAuthCoordinator().login(presenting:presenter);case .kimi:credential=try await KimiOAuthCoordinator().login(presenting:presenter);default:throw NSError(domain:"AIQuota",code:1,userInfo:[NSLocalizedDescriptionKey:"该平台请重新输入 API Key/Token"])};try keychain.saveCredential(credential,accountID:account.id);await SharedStore.shared.clearCooldown(accountID:account.id);if let snapshot=try? await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true){snapshots[account.id]=snapshot};WidgetCenter.shared.reloadAllTimelines()}}
  func addAPIKey(provider:ProviderID,name:String?=nil,key:String,baseURL:String?=nil)async{await performBusy{try await saveCredential(Credential(accessToken:key,baseURL:baseURL?.trimmingCharacters(in:.whitespacesAndNewlines),authenticationMode:.apiKey),provider:provider,customLabel:name)}}
  func updateAPIKey(_ account:AccountRecord,name:String?=nil,key:String,baseURL:String?=nil)async{await performBusy{var updated=account;let trimmed=name?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "";if !trimmed.isEmpty{updated.label=trimmed;await SharedStore.shared.upsertAccount(updated)};let credential=Credential(accessToken:key,baseURL:baseURL?.trimmingCharacters(in:.whitespacesAndNewlines),authenticationMode:.apiKey);try keychain.saveCredential(credential,accountID:account.id);await SharedStore.shared.clearCooldown(accountID:account.id);_=try await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true)}}
  func usesAPIKey(_ account:AccountRecord)->Bool{if ![ProviderID.codex,.claude,.kimi].contains(account.provider){return true};guard let credential=try? keychain.credential(accountID:account.id)else{return false};return credential.authenticationMode == .apiKey}
  func apiBaseURL(_ account:AccountRecord)->String{guard let credential=try? keychain.credential(accountID:account.id)else{return ""};return credential.baseURL ?? ""}
  func refresh(_ account:AccountRecord)async{do{let snapshot=try await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true);snapshots[account.id]=snapshot;cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id);await reloadHistory();WidgetCenter.shared.reloadTimelines(ofKind:AppConfig.widgetKind)}catch{errorMessage=error.localizedDescription;if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot};cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id)}}
  func refreshAll(manual:Bool=true)async{isBusy=true;let enabled=accounts.filter(\.isEnabled);let refreshed=await CooldownAwareRefresh.shared.refresh(accountIDs:enabled.map(\.id),manual:manual);for snapshot in refreshed{snapshots[snapshot.accountID]=snapshot};for account in enabled{cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id);if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot}};await reloadHistory();isBusy=false;WidgetCenter.shared.reloadTimelines(ofKind:AppConfig.widgetKind)}
  func queryCodexResetCredits(_ account:AccountRecord)async{guard account.provider == .codex else{return};isBusy=true;defer{isBusy=false};do{let summary=try await UsageService.shared.queryCodexResetCredits(accountID:account.id);if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot};statusMessage="查询完成：当前可用 \(summary.availableCount) 次重置"}catch{errorMessage=error.localizedDescription}}
  func queryCodexModelUsage(_ account:AccountRecord)async{guard account.provider == .codex else{return};isBusy=true;defer{isBusy=false};do{let summary=try await UsageService.shared.queryCodexModelUsage(accountID:account.id);if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot};statusMessage="模型用量已更新：\(summary.returnedThreadCount) 个线程，\(summary.groups.count) 个模型分组"}catch{errorMessage=error.localizedDescription}}
  func resetCodexQuota(_ account:AccountRecord)async{guard account.provider == .codex else{return};isBusy=true;defer{isBusy=false};do{let result=try await UsageService.shared.consumeCodexResetCredit(accountID:account.id);_=try? await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true);_=try? await UsageService.shared.queryCodexResetCredits(accountID:account.id);await load();statusMessage="重置成功：已重置 \(result.windowsReset) 个额度窗口";WidgetCenter.shared.reloadAllTimelines()}catch{if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot};errorMessage=error.localizedDescription}}
  func delete(_ account:AccountRecord)async{try? keychain.deleteCredential(accountID:account.id);await SharedStore.shared.removeAccount(account.id);accounts.removeAll{$0.id==account.id};snapshots[account.id]=nil;cooldowns[account.id]=nil;await normalizeAndSaveOrder();await reloadHistory();WidgetCenter.shared.reloadAllTimelines()}
  func clearUsageHistory()async{await SharedStore.shared.clearHistory();usageHistory=[]}
  func setEnabled(_ account:AccountRecord,enabled:Bool)async{var updated=account;updated.isEnabled=enabled;await SharedStore.shared.upsertAccount(updated);if let i=accounts.firstIndex(where:{$0.id==account.id}){accounts[i]=updated};WidgetCenter.shared.reloadAllTimelines()}
  func rename(_ account:AccountRecord,label:String)async{var updated=account;updated.label=label.trimmingCharacters(in:.whitespacesAndNewlines);guard !updated.label.isEmpty else{return};await SharedStore.shared.upsertAccount(updated);if let i=accounts.firstIndex(where:{$0.id==account.id}){accounts[i]=updated};WidgetCenter.shared.reloadAllTimelines()}
  func move(_ account:AccountRecord,offset:Int)async{guard offset != 0,let from=accounts.firstIndex(where:{$0.id==account.id})else{return};let to=min(max(0,from+offset),accounts.count-1);guard to != from else{return};var reordered=accounts;let item=reordered.remove(at:from);reordered.insert(item,at:to);accounts=reordered.enumerated().map{index,record in var u=record;u.sortOrder=index;return u};await SharedStore.shared.saveAccounts(accounts);WidgetCenter.shared.reloadAllTimelines()}
  private func normalizeAndSaveOrder()async{accounts=accounts.enumerated().map{index,record in var u=record;u.sortOrder=index;return u};await SharedStore.shared.saveAccounts(accounts)}
  private func reloadHistory()async{usageHistory=await SharedStore.shared.history(accountIDs:accounts.map(\.id))}
  private func saveCredential(_ credential:Credential,provider:ProviderID,customLabel:String?=nil)async throws{
    let identity=identityForCredential(provider:provider,credential:credential)
    let trimmedLabel=customLabel?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
    let preferredLabel:String?=trimmedLabel.isEmpty ? nil:trimmedLabel
    if let providerID=identity.providerAccountID,
      var existing=accounts.first(where:{$0.provider==provider&&$0.providerAccountID==providerID}) {
      if let preferredLabel { existing.label=preferredLabel;await SharedStore.shared.upsertAccount(existing) }
      try keychain.saveCredential(credential,accountID:existing.id)
      await SharedStore.shared.clearCooldown(accountID:existing.id)
      _=try? await CooldownAwareRefresh.shared.refresh(accountID:existing.id,manual:true)
      await load();WidgetCenter.shared.reloadAllTimelines();return
    }
    if !provider.supportsMultipleAccounts,
      var existing=accounts.first(where:{$0.provider==provider}) {
      if let preferredLabel { existing.label=preferredLabel;await SharedStore.shared.upsertAccount(existing) }
      try keychain.saveCredential(credential,accountID:existing.id)
      await SharedStore.shared.clearCooldown(accountID:existing.id)
      _=try? await CooldownAwareRefresh.shared.refresh(accountID:existing.id,manual:true)
      await load();WidgetCenter.shared.reloadAllTimelines();return
    }
    let count=accounts.filter{$0.provider==provider}.count+1
    let defaultPrefix=credential.authenticationMode == .apiKey ? "\(provider.title) Key":"\(provider.title)"
    let label=preferredLabel ?? identity.email ?? identity.shortAccountLabel ?? "\(defaultPrefix) \(count)"
    let record=AccountRecord(provider:provider,label:label,providerAccountID:identity.providerAccountID,sortOrder:accounts.count)
    try keychain.saveCredential(credential,accountID:record.id)
    await SharedStore.shared.upsertAccount(record);accounts.append(record)
    if let snapshot=try? await CooldownAwareRefresh.shared.refresh(accountID:record.id,manual:true){snapshots[record.id]=snapshot}
    WidgetCenter.shared.reloadAllTimelines()
  }
  private func identityForCredential(provider:ProviderID,credential:Credential)->(email:String?,providerAccountID:String?,shortAccountLabel:String?){let claims=decodeJWTPayload(credential.idToken ?? credential.accessToken) ?? [:];let email=findNestedString(claims,key:"email");let accountID=credential.accountID ?? findNestedString(claims,key:"chatgpt_account_id") ?? findNestedString(claims,key:"sub");return(email,accountID,accountID.map{"\(provider.title) · \(String($0.prefix(8)))"})}
  private func performBusy(_ operation:()async throws->Void)async{isBusy=true;defer{isBusy=false};do{try await operation();await load()}catch{errorMessage=error.localizedDescription}}
}
