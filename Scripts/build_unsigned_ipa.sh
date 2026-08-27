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
packages them into Payload/AIQuota.app as AIQuota-unsigned.ipa. It must run on
macOS with Xcode. The resulting IPA is intended for a re-signing tool that can
sign BOTH the app and Widget extension with compatible entitlements/profiles.
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
  -scheme AIQuotaApp \
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
(
  cd "$STAGE"
  /usr/bin/zip -qry "$IPA" Payload
)

cat > "$ROOT/$OUT_DIR/AIQuota-unsigned-signing-info.txt" <<INFO
AI Quota Native unsigned IPA
Version: 0.8.0
Main bundle ID: $APP_BUNDLE
Widget bundle ID: $WIDGET_BUNDLE
App Group expected at runtime: $APP_GROUP
Keychain suffix expected at runtime: $KEYCHAIN_SUFFIX

IMPORTANT:
- Sign Payload/AIQuota.app AND Payload/AIQuota.app/PlugIns/*.appex.
- Main app and widget provisioning profiles must authorize the same App Group.
- Both profiles must authorize a compatible shared Keychain access group.
- A generic one-profile re-sign may install the app but break the widget.
INFO

"$ROOT/Scripts/verify_ipa_structure.sh" "$IPA" unsigned
printf '\nUnsigned IPA: %s\n' "$IPA"
