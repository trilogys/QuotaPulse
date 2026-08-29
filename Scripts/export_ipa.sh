#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-debugging}"
case "$MODE" in
  debugging|release-testing) ;;
  development) MODE="debugging" ;;
  ad-hoc) MODE="release-testing" ;;
  *) echo "Usage: $0 [debugging|release-testing]" >&2; exit 2 ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Run this on macOS with Xcode installed." >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
[[ -f SigningConfig.xcconfig ]] || {
  echo "Missing SigningConfig.xcconfig. Run Scripts/configure_signing.sh first." >&2
  exit 1
}

get_cfg() {
  local key="$1"
  grep -E "^${key} *=" SigningConfig.xcconfig | tail -1 | cut -d= -f2- | xargs
}

STYLE="$(get_cfg QUOTAPULSE_CODE_SIGN_STYLE)"
APP_BUNDLE="$(get_cfg QUOTAPULSE_APP_BUNDLE_ID)"
WIDGET_BUNDLE="$(get_cfg QUOTAPULSE_WIDGET_BUNDLE_ID)"
APP_PROFILE="$(get_cfg QUOTAPULSE_APP_PROFILE_SPECIFIER)"
WIDGET_PROFILE="$(get_cfg QUOTAPULSE_WIDGET_PROFILE_SPECIFIER)"

xcodegen generate
rm -rf build/QuotaPulse.xcarchive build/export
mkdir -p build/export

ARCHIVE_ARGS=(
  -project QuotaPulse.xcodeproj
  -scheme QuotaPulseApp
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath build/QuotaPulse.xcarchive
)
if [[ "$STYLE" == "Automatic" ]]; then
  ARCHIVE_ARGS+=(-allowProvisioningUpdates)
fi
xcodebuild "${ARCHIVE_ARGS[@]}" archive

SIGNING_STYLE="automatic"
[[ "$STYLE" == "Manual" ]] && SIGNING_STYLE="manual"

{
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$MODE</string>
  <key>signingStyle</key><string>$SIGNING_STYLE</string>
  <key>stripSwiftSymbols</key><true/>
PLIST
if [[ "$STYLE" == "Manual" ]]; then
cat <<PLIST
  <key>provisioningProfiles</key>
  <dict>
    <key>$APP_BUNDLE</key><string>$APP_PROFILE</string>
    <key>$WIDGET_BUNDLE</key><string>$WIDGET_PROFILE</string>
  </dict>
PLIST
fi
cat <<'PLIST'
</dict>
</plist>
PLIST
} > build/ExportOptions.plist

EXPORT_ARGS=(
  -exportArchive
  -archivePath build/QuotaPulse.xcarchive
  -exportPath build/export
  -exportOptionsPlist build/ExportOptions.plist
)
if [[ "$STYLE" == "Automatic" ]]; then
  EXPORT_ARGS+=(-allowProvisioningUpdates)
fi
xcodebuild "${EXPORT_ARGS[@]}"

IPA="$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)"
[[ -n "$IPA" ]] || { echo "No IPA produced." >&2; exit 1; }
printf '\nIPA: %s\n' "$IPA"
printf 'Distribution method: %s\n' "$MODE"
