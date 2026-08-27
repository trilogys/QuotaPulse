import AppIntents
import Foundation
import WidgetKit

struct RefreshAccountIntent: AppIntent {
  static var title: LocalizedStringResource = "刷新 AI 额度"
  static var description = IntentDescription("刷新指定账号的额度，不打开主 App。")
  static var openAppWhenRun: Bool { false }

  @Parameter(title: "Account ID")
  var accountID: String

  init() {
    accountID = ""
  }

  init(accountID: String) {
    self.accountID = accountID
  }

  func perform() async throws -> some IntentResult {
    guard let id = UUID(uuidString: accountID) else { return .result() }
    do {
      _ = try await UsageService.shared.refresh(accountID: id)
    } catch {
      // The service marks the cached snapshot stale with the error.
      // Returning normally keeps the interaction inside the widget.
    }
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}

struct RefreshAllVisibleIntent: AppIntent {
  static var title: LocalizedStringResource = "刷新全部 AI 额度"
  static var description = IntentDescription("刷新小组件当前选择的账号，不打开主 App。")
  static var openAppWhenRun: Bool { false }

  func perform() async throws -> some IntentResult {
    let accounts = await SharedStore.shared.displayAccounts()
    _ = await UsageService.shared.refresh(accountIDs: accounts.map(\.id))
    WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    return .result()
  }
}
