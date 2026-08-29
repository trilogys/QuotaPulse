import SwiftUI

@main
struct AIQuotaApp: App {
  @UIApplicationDelegateAdaptor(QuotaPulseAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          await QuotaNotifier.shared.requestAuthorization()
        }
    }
  }
}
