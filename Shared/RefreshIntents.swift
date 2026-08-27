import AppIntents
import Foundation
import WidgetKit

/// User-initiated refreshes intentionally bypass an active account cooldown once.
/// Automatic WidgetKit timeline refreshes continue to respect cooldowns.
struct RefreshAccountIntent: AppIntent {
  static var title: LocalizedStringResource = "刷新 AI 额度"
  static var description = IntentDescription("刷新指定账号的额度，不打开主 App。")
  static var openAppWhenRun: Bool { false }

  @Parameter(title: "Account ID")
  var accountID: String

  init() { accountID = "" }
  init(accountID: String) { self.accountID = accountID }

  func perform() async throws -> some IntentResult {
    guard let id = UUID(uuidString: accountID) else { return .result() }
    await SharedStore.shared.clearCooldown(accountID: id)
    do { _ = try await UsageService.shared.refresh(accountID: id) } catch { }
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}

struct RefreshWidgetSelectionIntent: AppIntent {
  static var title: LocalizedStringResource = "刷新当前小组件"
  static var description = IntentDescription("只刷新当前小组件正在显示的账号，不打开主 App。")
  static var openAppWhenRun: Bool { false }

  @Parameter(title: "Account IDs")
  var accountIDs: String

  init() { accountIDs = "" }
  init(accountIDs: [UUID]) { self.accountIDs = accountIDs.map(\.uuidString).joined(separator: ",") }

  func perform() async throws -> some IntentResult {
    let ids = accountIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    guard !ids.isEmpty else { return .result() }
    for id in ids { await SharedStore.shared.clearCooldown(accountID: id) }
    _ = await UsageService.shared.refresh(accountIDs: ids)
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}

struct RefreshAllVisibleIntent: AppIntent {
  static var title: LocalizedStringResource = "刷新全部 AI 额度"
  static var description = IntentDescription("刷新全局可见账号，不打开主 App。")
  static var openAppWhenRun: Bool { false }

  func perform() async throws -> some IntentResult {
    let accounts = await SharedStore.shared.displayAccounts()
    for account in accounts { await SharedStore.shared.clearCooldown(accountID: account.id) }
    _ = await UsageService.shared.refresh(accountIDs: accounts.map(\.id))
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}
