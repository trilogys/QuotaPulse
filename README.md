# QuotaPulse

[简体中文](README.zh-CN.md)

QuotaPulse is a native iOS and Android quota dashboard for AI services. It keeps account credentials on the device, supports multiple accounts, and presents quota windows, balances, token activity, trends, widgets, and refresh health in one place.

The app does not use a QuotaPulse-operated backend. Requests go directly to the selected provider or to a proxy configured by the user.

## Providers

| Provider | Authentication | Available data |
| --- | --- | --- |
| Codex / OpenAI | ChatGPT OAuth or API Key | Quota windows, resets, official token activity, model details when returned, Platform model access |
| Claude | OAuth or API Key | OAuth quota windows or API model access |
| Kimi | Device OAuth or API Key | Coding-plan quota windows, API balance, and available models |
| DeepSeek | API Key | Official account balance and available models |
| MiniMax | Key | Coding-plan quota |
| GLM / Z.ai | Key | Coding-plan quota |
| GitHub Copilot | Token | Quota snapshots |

Provider APIs expose different data. QuotaPulse labels balances, percentages, and tokens separately instead of combining incompatible values.

## iOS

Built with SwiftUI, WidgetKit, App Intents, App Group storage, and Keychain. The minimum supported system is iOS 16.

Highlights:

- Multiple OAuth and API Key accounts with custom local names
- ChatGPT OAuth with PKCE and an on-device localhost callback
- OAuth token refresh and account-scoped cooldown handling
- Codex quota windows, reset schedule, reset-credit lookup, and user-confirmed manual reset
- Official Codex lifetime tokens, daily peak, streaks, daily buckets, and a 12-month heatmap
- Ring, bar, line, and heatmap chart modes
- Daily, weekly, and cumulative token aggregation
- Manual Codex model-detail lookup for available cloud task usage
- Kimi API balance and available-model listing
- DeepSeek API balance and available-model listing
- Named HTTP(S) and SOCKS5 proxy links with per-service scope, activation, and latency tests
- Foreground refresh intervals and an optional iOS background refresh request
- Custom background interval from 10 to 1,440 minutes
- Last successful refresh shown on the home screen
- Three switchable app icons with the classic green ring as the default
- Simplified Chinese and English localizations

iOS schedules background execution according to power, network, and usage conditions. A background task is not guaranteed to run at an exact interval, and force-quitting the app prevents further background refreshes.

## Token and Model Data

Codex ChatGPT OAuth can return official lifetime totals, peak daily tokens, streak data, and daily token buckets. Where thread billing data is available, QuotaPulse can also display model, input, cached input, output, total tokens, and estimated cost.

Kimi API Keys can return the current balance and available model IDs. The public Kimi balance and models endpoints do not provide historical per-model token consumption. QuotaPulse therefore does not display invented Kimi model usage; that requires provider request logs or gateway logs.

## JSON Import and Export

QuotaPulse import and export files are standard JSON.

- Import from the in-app file picker
- Share or open a JSON file from the iOS Files app with QuotaPulse
- Merge accounts by default or replace existing accounts explicitly
- Import QuotaPulse and compatible Sub2API account data
- Export configuration without credentials
- Export a complete backup containing credentials for device migration
- Timestamped filenames such as `QuotaPulse-backup-20260829-103512.json`

Complete backups contain sensitive API keys and OAuth tokens. Store them only in a trusted location.

## iOS Packages

The `ipa` GitHub Actions workflow produces unsigned, re-signable, and certificate-signed outputs.

```text
AIQuota-iOS-resign
├─ AIQuota-resign.ipa
├─ AIQuota-unsigned.ipa
├─ QuotaPulse.ipa
├─ AIQuota-app-only-unsigned.ipa
├─ SHA256
└─ signing-info
```

`QuotaPulse.ipa` is the app-only compatibility package. It excludes the Widget extension and is intended for tools such as ESign or Aisi Assistant when only one provisioning profile is available.

`AIQuota-resign.ipa` includes the Widget extension. Re-signing it requires matching App, Widget, App Group, and Keychain entitlements.

A P12 file contains a certificate and private key but is not a provisioning profile. An installable signed IPA still requires a compatible provisioning profile.

## Android

Built with Kotlin, Jetpack Compose, WorkManager, Jetpack Glance, Android Keystore, and EncryptedSharedPreferences. The minimum supported system is Android 8.

Android currently includes:

- Codex, Claude, and Kimi OAuth flows
- API Key modes for Codex / OpenAI, Claude, Kimi, and other supported providers
- Multiple accounts and encrypted credential storage
- Four switchable dashboard themes matching iOS, with Daylight as the default
- Provider filters, overview rings, rounded quota cards, and per-provider accent colors
- Background WorkManager refresh
- Configurable home-screen widgets
- Account ordering, enable/disable state, recommendations, and stale-cache handling
- JSON configuration migration between Android and iOS
- English and Simplified Chinese resources

## Online Updates

The iOS app can check the latest GitHub Release and open its release page. iOS does not allow a third-party signed app to silently replace itself. Sideloaded builds must still be downloaded and re-signed with the user's certificate and provisioning profile.

## Security

- iOS secrets are stored in Keychain and isolated by account UUID.
- Android secrets are stored in EncryptedSharedPreferences with an Android Keystore master key.
- Normal account metadata, charts, and widget snapshots do not contain access tokens.
- Signing files and passwords are injected through GitHub Actions secrets and are not committed.
- Logs and UI messages must not expose complete access tokens, refresh tokens, cookies, or API keys.

## Repository Layout

```text
AIQuotaApp/        iOS app, settings, OAuth, and account UI
AIQuotaWidget/     iOS WidgetKit extension
Shared/            iOS provider, storage, charts, and networking code
android/           Android app, workers, widgets, and resources
.github/workflows/ build workflows
Scripts/           iOS build, signing, and package verification
```

Additional signing details are documented in [IPA.md](IPA.md) and [SIGNING.md](SIGNING.md).
