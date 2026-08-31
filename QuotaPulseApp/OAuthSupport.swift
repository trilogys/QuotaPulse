import CryptoKit
import Foundation
import UIKit

enum OAuthAuthorizationMode {
  case inAppBrowser
  case copiedLink
}

@MainActor
func chooseOAuthAuthorizationMode(
  providerName: String,
  authorizationURL: URL,
  presenting presenter: UIViewController
) async throws -> OAuthAuthorizationMode {
  try await withCheckedThrowingContinuation { continuation in
    let alert = UIAlertController(
      title: String(format: NSLocalizedString("%@ 授权", comment: ""), providerName),
      message: NSLocalizedString("可以在应用内打开，或复制链接到同一台设备的其它浏览器完成授权。", comment: ""),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: NSLocalizedString("在应用内打开", comment: ""), style: .default) { _ in
      continuation.resume(returning: .inAppBrowser)
    })
    alert.addAction(UIAlertAction(title: NSLocalizedString("复制授权链接", comment: ""), style: .default) { _ in
      UIPasteboard.general.string = authorizationURL.absoluteString
      continuation.resume(returning: .copiedLink)
    })
    alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: ""), style: .cancel) { _ in
      continuation.resume(throwing: UsageError.refreshFailed("Login cancelled"))
    })
    presenter.present(alert, animated: true)
  }
}

struct PKCEPair: Sendable {
  let verifier: String
  let challenge: String

  static func generate() -> PKCEPair {
    let verifier = randomBase64URL(byteCount: 32)
    let digest = SHA256.hash(data: Data(verifier.utf8))
    let challenge = Data(digest).base64URLEncodedString()
    return PKCEPair(verifier: verifier, challenge: challenge)
  }
}

func randomBase64URL(byteCount: Int = 32) -> String {
  var bytes = [UInt8](repeating: 0, count: byteCount)
  _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
  return Data(bytes).base64URLEncodedString()
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

func queryEncodedURL(base: String, parameters: [(String, String)]) -> URL {
  var components = URLComponents(string: base)!
  components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
  return components.url!
}
