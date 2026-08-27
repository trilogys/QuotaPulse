import Foundation

enum AppConfig {
  static let version = "0.11.0"
  static var appGroup: String? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: "AIQuotaAppGroup") as? String,
      !value.isEmpty
    else { return nil }
    return value
  }
  static var isAppOnlyBuild: Bool {
    Bundle.main.object(forInfoDictionaryKey: "AIQuotaSingleProfile") as? Bool ?? false
  }
  static let widgetKind = "AIQuotaWidget"
  static let keychainService = "AIQuota.Credentials"
  static let keychainSuffixInfoKey = "AIQuotaKeychainSuffix"
  static let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  static let codexIssuer = "https://auth.openai.com"
  static let codexRedirectURI = "http://localhost:1455/auth/callback"
  static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  static let kimiClientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
}
