# IPA quick start — v0.8.0

## 1. Unsigned IPA for ESign / re-sign tools

1. Open **Actions → ipa → Run workflow**.
2. Choose `build_type = unsigned`.
3. Keep the default identifiers for a generic build, or enter the identifiers expected by your signing profiles.
4. Download the `AIQuota-unsigned` artifact.

Artifact contents:

- `AIQuota-unsigned.ipa`
- `AIQuota-unsigned.ipa.sha256`
- `AIQuota-unsigned-signing-info.txt`

The IPA contains a real iphoneos build:

```text
Payload/
└─ AIQuota.app
   └─ PlugIns/
      └─ AIQuotaWidget.appex
```

A re-signing tool must sign both `.app` and `.appex`. The final profiles must authorize the same App Group and a compatible shared Keychain group.

### Important for unsigned IPA

The Apple application-identifier prefix does **not** exist until signing. v0.8.0 therefore stores only the Keychain group suffix in Info.plist and resolves the signed prefix at runtime through public Keychain APIs. This avoids baking a wrong Team/AppIdentifierPrefix into a prebuilt unsigned IPA.

## 2. Signed IPA from your own certificate

Required GitHub Actions secrets:

- `AIQUOTA_P12_BASE64`
- `AIQUOTA_P12_PASSWORD`
- `AIQUOTA_APP_PROFILE_BASE64`
- `AIQUOTA_WIDGET_PROFILE_BASE64`

No Bundle ID / Team ID / App Group input is required. The workflow derives them from the two provisioning profiles.

Then:

1. **Actions → ipa → Run workflow**
2. `build_type = signed`
3. Select `release-testing` for Ad Hoc / registered-device distribution or `debugging` for Development profiles.
4. Download `AIQuota-signed-...`.

The workflow validates the two profiles, imports the `.p12` into a temporary CI keychain, exports the IPA, then verifies the main app and Widget signatures and entitlements.

## 3. One-command local signed IPA on a Mac

```bash
brew install xcodegen
export P12_PASSWORD='your-p12-password'

./Scripts/build_signed_ipa.sh \
  certificate.p12 \
  App.mobileprovision \
  Widget.mobileprovision \
  release-testing
```

Output:

```text
build/export/AIQuota-signed.ipa
build/export/AIQuota-signed.ipa.sha256
```

AI Quota contains two independently signed bundles (main app + Widget Extension), so both need compatible provisioning profiles.
