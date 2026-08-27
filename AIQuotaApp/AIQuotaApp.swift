import SwiftUI

@main
struct AIQuotaApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          await QuotaNotifier.shared.requestAuthorization()
        }
        .onOpenURL { url in
          // Reserved for future deep links such as aiquota://account/<uuid>.
          _ = url
        }
    }
  }
}
