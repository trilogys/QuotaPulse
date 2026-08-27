import SwiftUI

@main
struct AIQuotaApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .onOpenURL { url in
          // Reserved for future deep links such as adquota://account/<uuid>.
          _ = url
        }
    }
  }
}
