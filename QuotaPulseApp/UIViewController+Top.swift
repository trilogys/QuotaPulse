import UIKit

extension UIApplication {
  @MainActor
  func activeTopViewController() -> UIViewController? {
    let scene =
      connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    return root?.topMostViewController()
  }
}

extension UIViewController {
  fileprivate func topMostViewController() -> UIViewController {
    if let presented = presentedViewController { return presented.topMostViewController() }
    if let nav = self as? UINavigationController {
      return nav.visibleViewController?.topMostViewController() ?? nav
    }
    if let tab = self as? UITabBarController {
      return tab.selectedViewController?.topMostViewController() ?? tab
    }
    return self
  }
}
