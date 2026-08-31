import Foundation

enum AppConfig {
  static let version = "1.0.6"
  static var appGroup: String? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: "QuotaPulseAppGroup") as? String,
      !value.isEmpty
    else { return nil }
    return value
  }
  static var isAppOnlyBuild: Bool {
    Bundle.main.object(forInfoDictionaryKey: "QuotaPulseSingleProfile") as? Bool ?? false
  }
  static var isWidgetExtension: Bool {
    Bundle.main.bundleURL.pathExtension == "appex"
  }
  static let widgetKind = "QuotaPulseWidget"
  static let keychainService = "QuotaPulse.Credentials"
  static let keychainSuffixInfoKey = "QuotaPulseKeychainSuffix"
  static let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  static let codexIssuer = "https://auth.openai.com"
  static let codexRedirectURI = "http://localhost:1455/auth/callback"
  static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  static let kimiClientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
}
