#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="${AIQUOTA_APP_BUNDLE_ID:-com.example.aiquota}"
WIDGET_BUNDLE="${AIQUOTA_WIDGET_BUNDLE_ID:-${APP_BUNDLE}.widget}"
APP_GROUP="${AIQUOTA_APP_GROUP:-group.${APP_BUNDLE}.shared}"
KEYCHAIN_SUFFIX="${AIQUOTA_KEYCHAIN_SUFFIX:-${APP_BUNDLE}.shared}"
OUT_DIR="${AIQUOTA_UNSIGNED_OUTPUT_DIR:-build/unsigned-export}"
DERIVED="${AIQUOTA_UNSIGNED_DERIVED_DIR:-build/unsigned-derived}"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/build_unsigned_ipa.sh [options]

Options:
  --bundle ID              Main app bundle ID
  --widget-bundle ID       Widget bundle ID (default <bundle>.widget)
  --app-group ID           App Group stored in app/widget Info.plist
  --keychain-suffix VALUE  Shared Keychain group suffix (without Apple prefix)
  --output DIR             Output directory (default build/unsigned-export)

This builds a real iphoneos .app + Widget .appex without a code signature and
packages them into Payload/AIQuota.app. It produces two identical IPA files:

  AIQuota-unsigned.ipa  generic unsigned artifact
  AIQuota-resign.ipa    clearly named for third-party re-signing tools

The resulting IPA is intended for tools such as ESign/全能签 and desktop
re-signing utilities. A compatible signer must sign BOTH the main .app and the
embedded Widget .appex with provisioning profiles that authorize matching App
Group and shared Keychain entitlements.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) APP_BUNDLE="${2:-}"; shift 2 ;;
    --widget-bundle) WIDGET_BUNDLE="${2:-}"; shift 2 ;;
    --app-group) APP_GROUP="${2:-}"; shift 2 ;;
    --keychain-suffix) KEYCHAIN_SUFFIX="${2:-}"; shift 2 ;;
    --output) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$APP_BUNDLE" && -n "$WIDGET_BUNDLE" && -n "$APP_GROUP" && -n "$KEYCHAIN_SUFFIX" ]] || {
  echo "Bundle/App Group/Keychain values must not be empty." >&2; exit 2;
}
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found; run on macOS with Xcode." >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found; install with: brew install xcodegen" >&2; exit 1; }

xcodegen generate
rm -rf "$DERIVED" "$OUT_DIR"
mkdir -p "$DERIVED" "$OUT_DIR"

xcodebuild \
  -project AIQuota.xcodeproj \
  -scheme AIQuotaNativeWidget \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  AIQUOTA_APP_BUNDLE_ID="$APP_BUNDLE" \
  AIQUOTA_WIDGET_BUNDLE_ID="$WIDGET_BUNDLE" \
  AIQUOTA_APP_GROUP="$APP_GROUP" \
  AIQUOTA_KEYCHAIN_SUFFIX="$KEYCHAIN_SUFFIX" \
  build

APP="$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name 'AIQuotaApp.app' -print -quit)"
[[ -d "$APP" ]] || { echo "Built AIQuotaApp.app not found." >&2; exit 1; }
WIDGET="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -print -quit 2>/dev/null || true)"
[[ -d "$WIDGET" ]] || { echo "Widget extension was not embedded in the app." >&2; exit 1; }

find "$APP" -name _CodeSignature -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP" -name embedded.mobileprovision -type f -delete 2>/dev/null || true

STAGE="$(mktemp -d -t aiquota-unsigned)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/AIQuota.app"

IPA="$ROOT/$OUT_DIR/AIQuota-unsigned.ipa"
RESIGN_IPA="$ROOT/$OUT_DIR/AIQuota-resign.ipa"
(
  cd "$STAGE"
  /usr/bin/zip -qry "$IPA" Payload
)
cp "$IPA" "$RESIGN_IPA"

cat > "$ROOT/$OUT_DIR/AIQuota-unsigned-signing-info.txt" <<INFO
AIQuota Native unsigned / re-sign IPA
Minimum iOS: 16.0
Main bundle ID: $APP_BUNDLE
Widget bundle ID: $WIDGET_BUNDLE
App Group expected at runtime: $APP_GROUP
Keychain suffix expected at runtime: $KEYCHAIN_SUFFIX

Artifacts:
- AIQuota-unsigned.ipa : generic unsigned IPA
- AIQuota-resign.ipa   : identical copy named for third-party re-signing

IMPORTANT FOR 全能签 / ESign / 爱思助手 / OTHER RE-SIGN TOOLS:
- The IPA uses standard Payload/AIQuota.app packaging.
- The Widget is embedded at Payload/AIQuota.app/PlugIns/AIQuotaWidget.appex.
- The signer must sign BOTH the main app and the embedded Widget extension.
- The main app and Widget may require separate provisioning profiles.
- Both profiles must authorize the SAME App Group used by this build.
- Both profiles must authorize compatible shared Keychain access groups.
- If a re-sign tool only replaces the main-app profile/signature, the app may
  install while the Widget fails to appear or fails to share credentials.
- Re-signing cannot add an App Group that your Apple provisioning profile does
  not authorize. Use bundle IDs/App Group matching the profiles when possible.
INFO

"$ROOT/Scripts/verify_ipa_structure.sh" "$IPA" unsigned
"$ROOT/Scripts/verify_ipa_structure.sh" "$RESIGN_IPA" unsigned
(
  cd "$ROOT/$OUT_DIR"
  shasum -a 256 AIQuota-unsigned.ipa > AIQuota-unsigned.ipa.sha256
  shasum -a 256 AIQuota-resign.ipa > AIQuota-resign.ipa.sha256
)
printf '\nUnsigned IPA: %s\nRe-sign IPA: %s\n' "$IPA" "$RESIGN_IPA"
