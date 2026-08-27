import Foundation
import UserNotifications

actor QuotaNotifier {
  static let shared = QuotaNotifier()

  private let defaults: UserDefaults
  private let center = UNUserNotificationCenter.current()

  init() {
    if let appGroup = AppConfig.appGroup {
      defaults = UserDefaults(suiteName: appGroup) ?? .standard
    } else {
      defaults = .standard
    }
  }

  func requestAuthorization() async {
    _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
  }

  func evaluate(account: AccountRecord, snapshot: UsageSnapshot) async {
    guard !snapshot.stale, !snapshot.windows.isEmpty else { return }

    for window in snapshot.windows {
      let remaining = min(100, max(0, window.remainingPercent))
      let level: Int
      if remaining <= 0.5 {
        level = 3
      } else if remaining <= 10 {
        level = 2
      } else if remaining <= 20 {
        level = 1
      } else {
        level = 0
      }

      let key = "quotaAlert.\(account.id.uuidString).\(window.id)"
      let previous = defaults.integer(forKey: key)

      if level == 0 {
        if previous != 0 { defaults.set(0, forKey: key) }
        continue
      }
      guard level > previous else { continue }
      defaults.set(level, forKey: key)

      let content = UNMutableNotificationContent()
      switch level {
      case 3:
        content.title = "\(account.provider.title) 额度已耗尽"
      case 2:
        content.title = "\(account.provider.title) 额度仅剩 10%"
      default:
        content.title = "\(account.provider.title) 额度仅剩 20%"
      }
      content.body = "\(account.label) · \(window.label) · 剩余 \(Int(remaining.rounded()))%"
      content.sound = .default

      let request = UNNotificationRequest(
        identifier: "aiquota.\(account.id.uuidString).\(window.id).\(level)",
        content: content,
        trigger: nil
      )
      try? await center.add(request)
    }
  }
}
