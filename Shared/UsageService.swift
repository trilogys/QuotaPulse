import Foundation

public enum UsageError: LocalizedError {
  case missingAccount, missingCredential, unauthorized
  case http(Int, String), invalidResponse(String), refreshFailed(String)
  public var errorDescription:String?{switch self{case .missingAccount:"Account not found";case .missingCredential:"Credential not found";case .unauthorized:"Login expired";case .http(let c,let m):"HTTP \(c): \(m)";case .invalidResponse(let m):"Invalid response: \(m)";case .refreshFailed(let m):"Token refresh failed: \(m)"}}
}

actor UsageService {
  static let shared=UsageService();private let http=HTTPClient.shared;private let keychain=KeychainStore.shared
  @discardableResult func refresh(accountID:UUID,manual:Bool=false) async throws->UsageSnapshot{
    guard let account=await SharedStore.shared.account(id:accountID) else{throw UsageError.missingAccount}
    if !manual,await SharedStore.shared.cooldownUntil(accountID:accountID) != nil{if let cached=await SharedStore.shared.snapshot(for:accountID){return cached};throw UsageError.refreshFailed("Account refresh is cooling down")}
    if manual{await SharedStore.shared.clearCooldown(accountID:accountID)}
    do{let snapshot=try await fetch(account:account);await SharedStore.shared.clearCooldown(accountID:accountID);await SharedStore.shared.saveSnapshot(snapshot);await QuotaNotifier.shared.evaluate(account:account,snapshot:snapshot);return snapshot}
    catch{let failure=classifyFailure(error);if let seconds=failure.cooldown{await SharedStore.shared.setCooldown(accountID:accountID,until:Date().addingTimeInterval(seconds))};if await SharedStore.shared.snapshot(for:accountID)==nil{await SharedStore.shared.saveSnapshot(UsageSnapshot(accountID:account.id,provider:account.provider,errorMessage:failure.message,stale:true,errorKind:failure.kind))}else{await SharedStore.shared.markSnapshotStale(accountID:accountID,message:failure.message,kind:failure.kind)};throw error}
  }
  func refresh(accountIDs:[UUID],manual:Bool=false) async->[UsageSnapshot]{await withTaskGroup(of:UsageSnapshot?.self){group in for id in accountIDs{group.addTask{try? await UsageService.shared.refresh(accountID:id,manual:manual)}};var values:[UsageSnapshot]=[];for await value in group{if let value{values.append(value)}};return values}}
  func refreshVisible(limit:Int?=nil,manual:Bool=false) async->[UsageSnapshot]{let accounts=await SharedStore.shared.displayAccounts(limit:limit);return await refresh(accountIDs:accounts.map(\.id),manual:manual)}
  private struct Failure{let kind:ProviderErrorKind;let message:String;let cooldown:TimeInterval?}
  private func classifyFailure(_ error:Error)->Failure{let message=error.localizedDescription;switch error{case UsageError.missingCredential,UsageError.unauthorized:return Failure(kind:.authentication,message:message,cooldown:6*3600);case UsageError.http(let code,_):if code==401||code==403{return Failure(kind:.authentication,message:message,cooldown:6*3600)};if code==429{return Failure(kind:.rateLimited,message:message,cooldown:15*60)};if code>=500{return Failure(kind:.providerUnavailable,message:message,cooldown:5*60)};return Failure(kind:ProviderErrorClassifier.classify(message:message),message:message,cooldown:5*60);case UsageError.invalidResponse:return Failure(kind:.invalidResponse,message:message,cooldown:3600);case UsageError.refreshFailed:return Failure(kind:ProviderErrorClassifier.classify(message:message),message:message,cooldown:3600);default:let kind=ProviderErrorClassifier.classify(message:message);return Failure(kind:kind,message:message,cooldown:kind == .network ? 60 : 5*60)}}

  private func fetch(account: AccountRecord) async throws -> UsageSnapshot {
    guard var credential = try keychain.credential(accountID: account.id) else { throw UsageError.missingCredential }
    switch account.provider {
    case .codex: return try await fetchCodex(account: account, credential: &credential)
    case .claude: return try await fetchClaude(account: account, credential: &credential)
    case .kimi: return try await fetchKimi(account: account, credential: &credential)
    case .deepseek: return try await fetchDeepSeek(account: account, credential: credential)
    case .minimax: return try await fetchMiniMax(account: account, credential: credential)
    case .glm: return try await fetchGLM(account: account, credential: credential)
    case .copilot: return try await fetchCopilot(account: account, credential: credential)
    }
  }

  private func fetchCodex(account: AccountRecord, credential: inout Credential) async throws -> UsageSnapshot {
    func call(_ credential: Credential) async throws -> HTTPResult { var headers=["Authorization":"Bearer \(credential.accessToken)","User-Agent":"codex-cli","Accept":"application/json"];if let accountID=credential.accountID,!accountID.isEmpty{headers["chatgpt-account-id"]=accountID};return try await http.send(URL(string:"https://chatgpt.com/backend-api/wham/usage")!,headers:headers) }
    var result=try await call(credential);if result.statusCode==401,credential.refreshToken != nil{credential=try await refreshCodexCredential(credential,accountID:account.id);result=try await call(credential)};guard (200..<300).contains(result.statusCode)else{throw UsageError.http(result.statusCode,String(data:result.data,encoding:.utf8) ?? "")};let root=try result.jsonDictionary();guard let rateLimit=dictionary(root["rate_limit"])else{throw UsageError.invalidResponse("Missing rate_limit")};var windows:[UsageWindow]=[];for(key,rawAny)in rateLimit{guard key.hasSuffix("_window"),let raw=dictionary(rawAny),number(raw["used_percent"]) != nil else{continue};let duration=int64(raw["limit_window_seconds"]) ?? 0;let used=number(raw["used_percent"]) ?? 0;let resetAt:Date?;if let epoch=int64(raw["reset_at"]),epoch>0{resetAt=Date(timeIntervalSince1970:TimeInterval(epoch))}else if let seconds=int64(raw["reset_after_seconds"]),seconds>=0{resetAt=Date().addingTimeInterval(TimeInterval(seconds))}else{resetAt=nil};windows.append(UsageWindow(id:"codex-\(key)",label:durationLabel(seconds:duration),remainingPercent:100-used,resetAt:resetAt))};windows=uniqueWindows(windows);guard !windows.isEmpty else{throw UsageError.invalidResponse("No Codex quota windows")};return UsageSnapshot(accountID:account.id,provider:.codex,windows:windows)
  }

  private func refreshCodexCredential(_ credential: Credential, accountID: UUID) async throws -> Credential {
    guard let refreshToken=credential.refreshToken else{throw UsageError.unauthorized};let body="grant_type=refresh_token&refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? refreshToken)&client_id=app_EMoamEEZ73f0CkXaXp7hrann".data(using:.utf8)!;let result=try await http.send(URL(string:"https://auth.openai.com/oauth/token")!,method:"POST",headers:["Content-Type":"application/x-www-form-urlencoded"],body:body);guard (200..<300).contains(result.statusCode)else{throw UsageError.refreshFailed("Codex HTTP \(result.statusCode)")};let root=try result.jsonDictionary();guard let access=root["access_token"] as? String else{throw UsageError.refreshFailed("Codex access_token missing")};let updated=Credential(accessToken:access,refreshToken:root["refresh_token"] as? String ?? refreshToken,expiresAt:(root["expires_in"] as? NSNumber).map{Date().addingTimeInterval($0.doubleValue)},accountID:credential.accountID);try keychain.saveCredential(updated,accountID:accountID);return updated
  }

  private func fetchClaude(account:AccountRecord,credential:inout Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("Claude implementation retained in repository history")}
  private func fetchKimi(account:AccountRecord,credential:inout Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("Kimi implementation retained in repository history")}
  private func fetchDeepSeek(account:AccountRecord,credential:Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("DeepSeek implementation retained in repository history")}
  private func fetchMiniMax(account:AccountRecord,credential:Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("MiniMax implementation retained in repository history")}
  private func fetchGLM(account:AccountRecord,credential:Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("GLM implementation retained in repository history")}
  private func fetchCopilot(account:AccountRecord,credential:Credential)async throws->UsageSnapshot{throw UsageError.invalidResponse("Copilot implementation retained in repository history")}
  private func dictionary(_ value:Any?)->[String:Any]?{value as? [String:Any]};private func number(_ value:Any?)->Double?{(value as? NSNumber)?.doubleValue};private func int64(_ value:Any?)->Int64?{(value as? NSNumber)?.int64Value};private func uniqueWindows(_ windows:[UsageWindow])->[UsageWindow]{windows};private func durationLabel(seconds:Int64)->String{"\(seconds/3600)H"}
}
