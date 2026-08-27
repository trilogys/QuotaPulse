import AppIntents
import Foundation
import WidgetKit

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
    do { _ = try await CooldownAwareRefresh.shared.refresh(accountID: id, manual: true) } catch { }
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
    _ = await CooldownAwareRefresh.shared.refresh(accountIDs: ids, manual: true)
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
    _ = await CooldownAwareRefresh.shared.refresh(accountIDs: accounts.map(\.id), manual: true)
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}
