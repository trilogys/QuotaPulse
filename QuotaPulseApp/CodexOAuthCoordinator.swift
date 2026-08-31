import Foundation
import SafariServices
import UIKit

@MainActor
final class CodexOAuthCoordinator: NSObject, SFSafariViewControllerDelegate {
  private var server: LoopbackOAuthServer?
  private weak var safari: SFSafariViewController?

  func login(presenting presenter: UIViewController) async throws -> Credential {
    let pkce = PKCEPair.generate()
    let state = randomBase64URL(byteCount: 32)

    let server: LoopbackOAuthServer
    do {
      let primary = LoopbackOAuthServer(port: 1455)
      try await primary.start()
      server = primary
    } catch {
      let fallback = LoopbackOAuthServer(port: 1457)
      try await fallback.start()
      server = fallback
    }
    self.server = server
    let redirectURI = "http://localhost:\(server.rawPort)/auth/callback"

    let authURL = queryEncodedURL(
      base: "\(AppConfig.codexIssuer)/oauth/authorize",
      parameters: [
        ("response_type", "code"),
        ("client_id", AppConfig.codexClientID),
        ("redirect_uri", redirectURI),
        ("scope", "openid profile email offline_access api.connectors.read api.connectors.invoke"),
        ("code_challenge", pkce.challenge),
        ("code_challenge_method", "S256"),
        ("id_token_add_organizations", "true"),
        ("codex_cli_simplified_flow", "true"),
        ("state", state),
        ("originator", "codex_cli_rs"),
      ]
    )

    let mode: OAuthAuthorizationMode
    do {
      mode = try await chooseOAuthAuthorizationMode(
        providerName: "GPT / Codex",
        authorizationURL: authURL,
        presenting: presenter
      )
      try? await Task.sleep(nanoseconds: 250_000_000)
    } catch {
      server.cancel()
      self.server = nil
      throw error
    }

    if mode == .copiedLink {
      server.cancel()
      self.server = nil
      let callback = try await promptForCallback(presenting: presenter)
      return try await exchange(
        callback: callback,
        expectedState: state,
        pkce: pkce,
        redirectURI: redirectURI
      )
    }

    let browser = SFSafariViewController(url: authURL)
    browser.delegate = self
    safari = browser
    presenter.present(browser, animated: true)

    do {
      let callback = try await server.waitForCallback(timeout: 300)
      browser.dismiss(animated: true)
      self.server = nil
      self.safari = nil
      return try await exchange(
        callback: callback, expectedState: state, pkce: pkce, redirectURI: redirectURI)
    } catch {
      browser.dismiss(animated: true)
      self.server = nil
      self.safari = nil
      throw error
    }
  }

  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    server?.cancel()
  }

  private func promptForCallback(presenting presenter: UIViewController) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let alert = UIAlertController(
        title: NSLocalizedString("粘贴 GPT 回调地址", comment: ""),
        message: NSLocalizedString(
          "已复制授权链接。请在其它浏览器完成授权，复制最终的 localhost 完整地址，再返回此处粘贴。",
          comment: ""
        ),
        preferredStyle: .alert
      )
      alert.addTextField { field in
        field.placeholder = NSLocalizedString("完整 localhost 回调地址", comment: "")
        if let value = UIPasteboard.general.string,
          value.hasPrefix("http://localhost"),
          value.contains("/auth/callback")
        {
          field.text = value
        }
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
      }
      alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: ""), style: .cancel) { _ in
        continuation.resume(throwing: UsageError.refreshFailed("Login cancelled"))
      })
      alert.addAction(UIAlertAction(title: NSLocalizedString("完成", comment: ""), style: .default) { _ in
        let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw),
          url.scheme == "http",
          url.host == "localhost",
          url.path == "/auth/callback"
        else {
          continuation.resume(throwing: UsageError.refreshFailed("Invalid localhost callback URL"))
          return
        }
        continuation.resume(returning: url)
      })
      presenter.present(alert, animated: true)
    }
  }

  private func exchange(callback: URL, expectedState: String, pkce: PKCEPair, redirectURI: String) async throws
    -> Credential
  {
    let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
    let values = Dictionary(
      uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item -> (String, String)? in
        guard let value = item.value else { return nil }
        return (item.name, value)
      })
    if let error = values["error"] {
      throw UsageError.refreshFailed(values["error_description"] ?? error)
    }
    guard values["state"] == expectedState else {
      throw UsageError.refreshFailed("OAuth state mismatch")
    }
    guard let code = values["code"], !code.isEmpty else {
      throw UsageError.refreshFailed("Missing authorization code")
    }

    let result = try await HTTPClient.shared.send(
      URL(string: "\(AppConfig.codexIssuer)/oauth/token")!,
      method: "POST",
      headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
      body: formURLEncoded([
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirectURI,
        "client_id": AppConfig.codexClientID,
        "code_verifier": pkce.verifier,
      ]),
      timeout: 15
    )
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let json = try result.jsonDictionary()
    guard let access = json["access_token"] as? String,
      let refresh = json["refresh_token"] as? String
    else { throw UsageError.invalidResponse("Codex token response missing tokens") }
    let idToken = json["id_token"] as? String
    let claims = decodeJWTPayload(idToken) ?? [:]
    let accountID = findNestedString(claims, key: "chatgpt_account_id")
    return Credential(
      accessToken: access,
      refreshToken: refresh,
      idToken: idToken,
      accountID: accountID,
      clientID: AppConfig.codexClientID,
      authenticationMode: .oauth
    )
  }
}
