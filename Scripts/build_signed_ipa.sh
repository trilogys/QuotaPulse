#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'USAGE'
Usage:
  P12_PASSWORD='your-password' ./Scripts/build_signed_ipa.sh \
    certificate.p12 App.mobileprovision Widget.mobileprovision [debugging|release-testing]

The script:
  1. Creates a temporary macOS keychain and imports the .p12.
  2. Installs the two provisioning profiles temporarily.
  3. Derives Team/Bundle IDs/App Group/Keychain group from the profiles.
  4. Verifies profile compatibility.
  5. Builds and exports the signed IPA.
  6. Verifies both the app and Widget signatures/entitlements.

P12_PASSWORD is read from the environment so the password does not need to be
placed in the command line/history.
USAGE
}

[[ $# -ge 3 && $# -le 4 ]] || { usage; exit 2; }
P12="$1"; APP_PROFILE_SRC="$2"; WIDGET_PROFILE_SRC="$3"; METHOD="${4:-release-testing}"
[[ "$METHOD" == "debugging" || "$METHOD" == "release-testing" ]] || { echo "Method must be debugging or release-testing" >&2; exit 2; }
[[ -f "$P12" && -f "$APP_PROFILE_SRC" && -f "$WIDGET_PROFILE_SRC" ]] || { echo "Certificate/profile file missing." >&2; exit 1; }
[[ -n "${P12_PASSWORD:-}" ]] || { echo "Set P12_PASSWORD in the environment." >&2; exit 2; }
command -v security >/dev/null 2>&1 || { echo "macOS security tool required." >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Xcode is required." >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found; install with: brew install xcodegen" >&2; exit 1; }

TMP="$(mktemp -d -t aiquota-sign)"
KEYCHAIN="$TMP/aiquota.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"

OLD_KEYCHAINS="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ' | xargs || true)"
CFG_BACKUP=""
if [[ -f SigningConfig.xcconfig ]]; then
  CFG_BACKUP="$TMP/SigningConfig.xcconfig.backup"
  cp SigningConfig.xcconfig "$CFG_BACKUP"
fi
APP_INSTALLED=""; WIDGET_INSTALLED=""

cleanup() {
  set +e
  if [[ -n "$APP_INSTALLED" && "${APP_EXISTED:-0}" == "0" ]]; then rm -f "$APP_INSTALLED"; fi
  if [[ -n "$WIDGET_INSTALLED" && "${WIDGET_EXISTED:-0}" == "0" ]]; then rm -f "$WIDGET_INSTALLED"; fi
  if [[ -n "$OLD_KEYCHAINS" ]]; then security list-keychains -d user -s $OLD_KEYCHAINS >/dev/null 2>&1; fi
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  if [[ -n "$CFG_BACKUP" ]]; then cp "$CFG_BACKUP" SigningConfig.xcconfig; else rm -f SigningConfig.xcconfig; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
if [[ -n "$OLD_KEYCHAINS" ]]; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $OLD_KEYCHAINS
else
  security list-keychains -d user -s "$KEYCHAIN"
fi
security find-identity -v -p codesigning "$KEYCHAIN"

profile_uuid() {
  local profile="$1" plist="$2"
  security cms -D -i "$profile" > "$plist"
  /usr/libexec/PlistBuddy -c 'Print :UUID' "$plist"
}
APP_UUID="$(profile_uuid "$APP_PROFILE_SRC" "$TMP/app.plist")"
WIDGET_UUID="$(profile_uuid "$WIDGET_PROFILE_SRC" "$TMP/widget.plist")"
APP_INSTALLED="$PROFILE_DIR/$APP_UUID.mobileprovision"
WIDGET_INSTALLED="$PROFILE_DIR/$WIDGET_UUID.mobileprovision"
[[ -e "$APP_INSTALLED" ]] && APP_EXISTED=1 || APP_EXISTED=0
[[ -e "$WIDGET_INSTALLED" ]] && WIDGET_EXISTED=1 || WIDGET_EXISTED=0
cp "$APP_PROFILE_SRC" "$APP_INSTALLED"
cp "$WIDGET_PROFILE_SRC" "$WIDGET_INSTALLED"

./Scripts/derive_signing_config.sh "$APP_PROFILE_SRC" "$WIDGET_PROFILE_SRC"
./Scripts/verify_signing_profiles.sh "$APP_PROFILE_SRC" "$WIDGET_PROFILE_SRC"
./Scripts/export_ipa.sh "$METHOD"

IPA="$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)"
[[ -f "$IPA" ]] || { echo "Signed IPA not produced." >&2; exit 1; }
./Scripts/verify_ipa_structure.sh "$IPA" signed
cp "$IPA" build/export/AIQuota-signed.ipa
(
  cd build/export
  shasum -a 256 AIQuota-signed.ipa > AIQuota-signed.ipa.sha256
)
printf '\nReady: %s\n' "$ROOT/build/export/AIQuota-signed.ipa"
