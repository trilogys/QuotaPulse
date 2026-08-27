import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
  @Published var accounts: [AccountRecord] = []
  @Published var snapshots: [UUID: UsageSnapshot] = [:]
  @Published var cooldowns: [UUID: Date] = [:]
  @Published var isBusy = false
  @Published var errorMessage: String?

  private let keychain = KeychainStore.shared

  func load() async {
    accounts = await SharedStore.shared.accounts()
    var map: [UUID: UsageSnapshot] = [:]
    var cooldownMap: [UUID: Date] = [:]
    for account in accounts {
      if let snapshot = await SharedStore.shared.snapshot(for: account.id) { map[account.id] = snapshot }
      if let cooldown = await SharedStore.shared.cooldownUntil(accountID: account.id) { cooldownMap[account.id] = cooldown }
    }
    snapshots = map; cooldowns = cooldownMap
  }

  func cooldownUntil(_ account: AccountRecord) -> Date? { cooldowns[account.id] }

  func credentialHealth(_ account: AccountRecord) -> CredentialHealth {
    guard let credential = try? keychain.credential(accountID: account.id) else { return CredentialHealth(title: "需重登", icon: "exclamationmark.triangle.fill", color: .red) }
    if account.provider == .deepseek || account.provider == .minimax || account.provider == .glm || account.provider == .copilot { return CredentialHealth(title: "已保存", icon: "checkmark.shield.fill", color: .green) }
    if let expires = credential.expiresAt {
      if expires <= .now { if credential.refreshToken?.isEmpty == false { return CredentialHealth(title: "可续期", icon: "arrow.triangle.2.circlepath", color: .orange) }; return CredentialHealth(title: "需重登", icon: "exclamationmark.triangle.fill", color: .red) }
      if expires.timeIntervalSinceNow < 3600 { return CredentialHealth(title: "即将续期", icon: "clock.arrow.circlepath", color: .orange) }
    }
    if snapshots[account.id]?.stale == true { return CredentialHealth(title: "缓存中", icon: "icloud.slash", color: .orange) }
    return CredentialHealth(title: "正常", icon: "checkmark.circle.fill", color: .green)
  }

  func addCodex(presenter:UIViewController) async { await performBusy { let c=try await CodexOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.codex) } }
  func addClaude(presenter:UIViewController) async { await performBusy { let c=try await ClaudeOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.claude) } }
  func addKimi(presenter:UIViewController) async { await performBusy { let c=try await KimiOAuthCoordinator().login(presenting:presenter);try await saveCredential(c,provider:.kimi) } }

  func reauthenticate(_ account:AccountRecord,presenter:UIViewController) async { await performBusy { let credential:Credential;switch account.provider{case .codex:credential=try await CodexOAuthCoordinator().login(presenting:presenter);case .claude:credential=try await ClaudeOAuthCoordinator().login(presenting:presenter);case .kimi:credential=try await KimiOAuthCoordinator().login(presenting:presenter);default:throw NSError(domain:"AIQuota",code:1,userInfo:[NSLocalizedDescriptionKey:"该平台请重新输入 API Key/Token"])};try keychain.saveCredential(credential,accountID:account.id);await SharedStore.shared.clearCooldown(accountID:account.id);if let snapshot=try? await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true){snapshots[account.id]=snapshot};WidgetCenter.shared.reloadAllTimelines() } }

  func addAPIKey(provider:ProviderID,key:String,baseURL:String?=nil) async { await performBusy { let credential=Credential(accessToken:key,baseURL:baseURL?.trimmingCharacters(in:.whitespacesAndNewlines));try await saveCredential(credential,provider:provider) } }

  func refresh(_ account:AccountRecord) async { do { let snapshot=try await CooldownAwareRefresh.shared.refresh(accountID:account.id,manual:true);snapshots[account.id]=snapshot;cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id);WidgetCenter.shared.reloadTimelines(ofKind:AppConfig.widgetKind) } catch { errorMessage=error.localizedDescription;if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot};cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id) } }

  func refreshAll() async { isBusy=true;let enabled=accounts.filter(\.isEnabled);let refreshed=await CooldownAwareRefresh.shared.refresh(accountIDs:enabled.map(\.id),manual:true);for snapshot in refreshed{snapshots[snapshot.accountID]=snapshot};for account in enabled{cooldowns[account.id]=await SharedStore.shared.cooldownUntil(accountID:account.id);if let snapshot=await SharedStore.shared.snapshot(for:account.id){snapshots[account.id]=snapshot}};isBusy=false;WidgetCenter.shared.reloadTimelines(ofKind:AppConfig.widgetKind) }

  func delete(_ account:AccountRecord) async { do{try keychain.deleteCredential(accountID:account.id)}catch{errorMessage=error.localizedDescription};await SharedStore.shared.removeAccount(account.id);accounts.removeAll{$0.id==account.id};snapshots[account.id]=nil;cooldowns[account.id]=nil;await normalizeAndSaveOrder();WidgetCenter.shared.reloadAllTimelines() }
  func setEnabled(_ account:AccountRecord,enabled:Bool) async { var updated=account;updated.isEnabled=enabled;await SharedStore.shared.upsertAccount(updated);if let index=accounts.firstIndex(where:{$0.id==account.id}){accounts[index]=updated};WidgetCenter.shared.reloadAllTimelines() }
  func rename(_ account:AccountRecord,label:String) async { var updated=account;updated.label=label.trimmingCharacters(in:.whitespacesAndNewlines);guard !updated.label.isEmpty else{return};await SharedStore.shared.upsertAccount(updated);if let index=accounts.firstIndex(where:{$0.id==account.id}){accounts[index]=updated};WidgetCenter.shared.reloadAllTimelines() }
  func move(_ account:AccountRecord,offset:Int) async { guard offset != 0,let from=accounts.firstIndex(where:{$0.id==account.id})else{return};let to=min(max(0,from+offset),accounts.count-1);guard to != from else{return};var reordered=accounts;let item=reordered.remove(at:from);reordered.insert(item,at:to);accounts=reordered.enumerated().map{index,record in var updated=record;updated.sortOrder=index;return updated};await SharedStore.shared.saveAccounts(accounts);WidgetCenter.shared.reloadAllTimelines() }
  private func normalizeAndSaveOrder() async { accounts=accounts.enumerated().map{index,record in var updated=record;updated.sortOrder=index;return updated};await SharedStore.shared.saveAccounts(accounts) }

  private func saveCredential(_ credential:Credential,provider:ProviderID) async throws { let identity=identityForCredential(provider:provider,credential:credential);if let providerID=identity.providerAccountID,let existing=accounts.first(where:{$0.provider==provider&&$0.providerAccountID==providerID}){try keychain.saveCredential(credential,accountID:existing.id);await SharedStore.shared.clearCooldown(accountID:existing.id);_=try? await CooldownAwareRefresh.shared.refresh(accountID:existing.id,manual:true);await load();WidgetCenter.shared.reloadAllTimelines();return};if !provider.supportsMultipleAccounts,let existing=accounts.first(where:{$0.provider==provider}){try keychain.saveCredential(credential,accountID:existing.id);await SharedStore.shared.clearCooldown(accountID:existing.id);_=try? await CooldownAwareRefresh.shared.refresh(accountID:existing.id,manual:true);await load();WidgetCenter.shared.reloadAllTimelines();return};let count=accounts.filter{$0.provider==provider}.count+1;let label=identity.email ?? identity.shortAccountLabel ?? "\(provider.title) \(count)";let record=AccountRecord(provider:provider,label:label,providerAccountID:identity.providerAccountID,sortOrder:accounts.count);try keychain.saveCredential(credential,accountID:record.id);await SharedStore.shared.upsertAccount(record);accounts.append(record);if let snapshot=try? await CooldownAwareRefresh.shared.refresh(accountID:record.id,manual:true){snapshots[record.id]=snapshot};WidgetCenter.shared.reloadAllTimelines() }
  private func identityForCredential(provider:ProviderID,credential:Credential)->(email:String?,providerAccountID:String?,shortAccountLabel:String?){let claims=decodeJWTPayload(credential.idToken ?? credential.accessToken) ?? [:];let email=findNestedString(claims,key:"email");let accountID=credential.accountID ?? findNestedString(claims,key:"chatgpt_account_id") ?? findNestedString(claims,key:"sub");let short=accountID.map{"\(provider.title) · \(String($0.prefix(8)))"};return(email,accountID,short)}
  private func performBusy(_ operation:() async throws->Void) async { isBusy=true;defer{isBusy=false};do{try await operation();await load()}catch{errorMessage=error.localizedDescription} }
}
