import Foundation
import SafariServices
import UIKit

@MainActor
final class KimiOAuthCoordinator: NSObject, SFSafariViewControllerDelegate {
  private weak var safari: SFSafariViewController?
  private var cancelled = false

  func login(presenting presenter: UIViewController) async throws -> Credential {
    cancelled = false
    let headers = deviceHeaders()
    var requestHeaders = headers
    requestHeaders["Content-Type"] = "application/x-www-form-urlencoded"
    requestHeaders["Accept"] = "application/json"

    let first = try await HTTPClient.shared.send(
      URL(string: "https://auth.kimi.com/api/oauth/device_authorization")!,
      method: "POST",
      headers: requestHeaders,
      body: formURLEncoded(["client_id": AppConfig.kimiClientID]),
      timeout: 15
    )
    guard (200..<300).contains(first.statusCode) else {
      throw UsageError.http(first.statusCode, String(data: first.data, encoding: .utf8) ?? "")
    }
    let json = try first.jsonDictionary()
    guard let deviceCode = json["device_code"] as? String,
      let userCode = json["user_code"] as? String
    else { throw UsageError.invalidResponse("Kimi device authorization response is incomplete") }
    let verifyString =
      (json["verification_uri_complete"] as? String) ?? (json["verification_uri"] as? String)
    guard let verifyString, let verifyURL = URL(string: verifyString) else {
      throw UsageError.invalidResponse("Kimi verification URL missing")
    }

    if json["verification_uri_complete"] == nil {
      UIPasteboard.general.string = userCode
      let alert = UIAlertController(
        title: "Kimi 授权码已复制",
        message: "验证码 \(userCode) 已复制。打开页面后粘贴即可。",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "继续", style: .default))
      presenter.present(alert, animated: true)
      try? await Task.sleep(nanoseconds: 800_000_000)
      alert.dismiss(animated: true)
    }

    let browser = SFSafariViewController(url: verifyURL)
    browser.delegate = self
    safari = browser
    presenter.present(browser, animated: true)

    var interval = max(1.0, number(json["interval"]) ?? 5)
    let expires = max(60.0, number(json["expires_in"]) ?? 900)
    let deadline = Date().addingTimeInterval(expires)
    while Date() < deadline {
      if cancelled { throw UsageError.refreshFailed("Kimi login cancelled") }
      try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      let poll = try await HTTPClient.shared.send(
        URL(string: "https://auth.kimi.com/api/oauth/token")!,
        method: "POST",
        headers: requestHeaders,
        body: formURLEncoded([
          "client_id": AppConfig.kimiClientID,
          "device_code": deviceCode,
          "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]),
        timeout: 15
      )
      let body = (try? poll.jsonDictionary()) ?? [:]
      if (200..<300).contains(poll.statusCode), let access = body["access_token"] as? String {
        browser.dismiss(animated: true)
        safari = nil
        return Credential(
          accessToken: access,
          refreshToken: body["refresh_token"] as? String,
          expiresAt: number(body["expires_in"]).map { Date().addingTimeInterval($0) },
          clientID: AppConfig.kimiClientID,
          deviceHeaders: headers,
          authenticationMode: .oauth
        )
      }
      let error = body["error"] as? String
      if error == "slow_down" {
        interval += 5
      } else if ["expired_token", "access_denied"].contains(error ?? "") {
        throw UsageError.refreshFailed("Kimi login: \(error ?? "failed")")
      } else if let error, error != "authorization_pending", poll.statusCode < 500,
        poll.statusCode != 429
      {
        throw UsageError.refreshFailed("Kimi login: \(error)")
      }
    }
    browser.dismiss(animated: true)
    safari = nil
    throw UsageError.refreshFailed("Kimi authorization timed out")
  }

  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    cancelled = true
  }

  private func deviceHeaders() -> [String: String] {
    let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    return [
      "X-Msh-Platform": "kimi_cli",
      "X-Msh-Version": "ai-quota-native/\(AppConfig.version)",
      "X-Msh-Device-Name": UIDevice.current.name,
      "X-Msh-Device-Model": UIDevice.current.model,
      "X-Msh-Os-Version": UIDevice.current.systemVersion,
      "X-Msh-Device-Id": id,
    ]
  }
}
