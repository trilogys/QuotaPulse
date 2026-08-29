import BackgroundTasks
import Foundation
import UIKit

enum BackgroundRefreshManager {
  static let taskIdentifier = "com.trilogys.quotapulse.refresh"

  static func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: taskIdentifier,
      using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      handle(refreshTask)
    }
  }

  static func scheduleIfEnabled() {
    Task {
      let enabled = await SharedStore.shared.backgroundRefreshEnabled()
      guard enabled else {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        return
      }
      let minutes = await SharedStore.shared.autoRefreshMinutes()
      let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
      request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
      try? BGTaskScheduler.shared.submit(request)
    }
  }

  static func setEnabled(_ enabled: Bool) {
    if enabled {
      scheduleIfEnabled()
    } else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
  }

  private static func handle(_ task: BGAppRefreshTask) {
    scheduleIfEnabled()
    let operation = Task {
      let accounts = await SharedStore.shared.accounts().filter(\.isEnabled)
      _ = await CooldownAwareRefresh.shared.refresh(
        accountIDs: accounts.map(\.id),
        manual: false
      )
      task.setTaskCompleted(success: !Task.isCancelled)
    }
    task.expirationHandler = {
      operation.cancel()
    }
  }
}

final class QuotaPulseAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    BackgroundRefreshManager.register()
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    BackgroundRefreshManager.scheduleIfEnabled()
  }
}
