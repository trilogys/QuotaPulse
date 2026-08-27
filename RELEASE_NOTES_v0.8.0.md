# AI Quota Native v0.8.0

## IPA-first release

- Added `Actions → ipa` workflow with `unsigned` and `signed` modes.
- Added real unsigned iphoneos IPA packaging for third-party re-signing.
- Added one-command local `.p12 + two profiles → signed IPA` build.
- Signed builds derive Team ID, app/widget Bundle IDs, App Group, Keychain group and profile names directly from provisioning profiles.
- Removed the need for a separate Team ID GitHub secret in the signed workflow.
- Added signed/unsigned IPA structure verification and SHA-256 output.

## Re-sign-safe Keychain architecture

- Replaced build-time full Keychain access-group injection with a suffix-only runtime configuration.
- The app/widget discover the access-group prefix from the installed code signature through public Keychain APIs at runtime.
- This prevents a prebuilt unsigned IPA from being tied to the Team/AppIdentifierPrefix used at compile time.

## Existing functionality retained

- Interactive Widget refresh without opening the app.
- Per-account and refresh-all App Intents.
- Automatic WidgetKit timeline refresh.
- Multi-account credential/cache isolation.
- Codex / Claude / Kimi OAuth plus API-key providers.
