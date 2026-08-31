import Foundation
import SafariServices
import UIKit

@MainActor
final class ClaudeOAuthCoordinator: NSObject, SFSafariViewControllerDelegate {
  private var closeContinuation: CheckedContinuation<Void, Never>?

  func login(presenting presenter: UIViewController) async throws -> Credential {
    let pkce = PKCEPair.generate()
    let authURL = queryEncodedURL(
      base: "https://claude.ai/oauth/authorize",
      parameters: [
        ("code", "true"),
        ("client_id", AppConfig.claudeClientID),
        ("response_type", "code"),
        ("redirect_uri", "https://console.anthropic.com/oauth/code/callback"),
        ("scope", "user:profile user:inference"),
        ("code_challenge", pkce.challenge),
        ("code_challenge_method", "S256"),
        ("state", pkce.verifier),
      ]
    )

    let mode = try await chooseOAuthAuthorizationMode(
      providerName: "Claude",
      authorizationURL: authURL,
      presenting: presenter
    )
    try? await Task.sleep(nanoseconds: 250_000_000)
    if mode == .inAppBrowser {
      let safari = SFSafariViewController(url: authURL)
      safari.delegate = self
      presenter.present(safari, animated: true)
      await withCheckedContinuation { continuation in
        closeContinuation = continuation
      }
    }

    let raw = try await promptForCode(presenting: presenter, linkWasCopied: mode == .copiedLink)
    let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first, !first.isEmpty else {
      throw UsageError.refreshFailed("Missing Claude authorization code")
    }
    let code = String(first)
    let state = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : pkce.verifier

    let body = try JSONSerialization.data(withJSONObject: [
      "grant_type": "authorization_code",
      "code": code,
      "state": state,
      "client_id": AppConfig.claudeClientID,
      "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
      "code_verifier": pkce.verifier,
    ])
    let result = try await HTTPClient.shared.send(
      URL(string: "https://platform.claude.com/v1/oauth/token")!,
      method: "POST",
      headers: ["Content-Type": "application/json", "Accept": "application/json"],
      body: body,
      timeout: 15
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let json = try result.jsonDictionary()
    guard let access = json["access_token"] as? String else {
      throw UsageError.invalidResponse("Claude token response missing access_token")
    }
    let expires = number(json["expires_in"]).map { Date().addingTimeInterval($0) }
    return Credential(
      accessToken: access,
      refreshToken: json["refresh_token"] as? String,
      expiresAt: expires,
      clientID: AppConfig.claudeClientID,
      authenticationMode: .oauth
    )
  }

  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    closeContinuation?.resume()
    closeContinuation = nil
  }

  private func promptForCode(presenting presenter: UIViewController, linkWasCopied: Bool) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let alert = UIAlertController(
        title: "粘贴 Claude 授权码",
        message: linkWasCopied
          ? NSLocalizedString("已复制授权链接。请在其它浏览器完成授权，再把页面显示的完整 CODE#STATE 粘贴到这里。", comment: "")
          : NSLocalizedString("把授权页面显示的完整 CODE#STATE 粘贴到这里。", comment: ""),
        preferredStyle: .alert
      )
      alert.addTextField { field in
        field.placeholder = "CODE#STATE"
        if !linkWasCopied, let text = UIPasteboard.general.string, text.count < 1000 { field.text = text }
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
      }
      alert.addAction(
        UIAlertAction(title: "取消", style: .cancel) { _ in
          continuation.resume(throwing: UsageError.refreshFailed("Login cancelled"))
        })
      alert.addAction(
        UIAlertAction(title: "完成", style: .default) { _ in
          let value =
            alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          if value.isEmpty {
            continuation.resume(throwing: UsageError.refreshFailed("Authorization code is empty"))
          } else {
            continuation.resume(returning: value)
          }
        })
      presenter.present(alert, animated: true)
    }
  }
}
