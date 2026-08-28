#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="${AIQUOTA_APP_BUNDLE_ID:-com.example.aiquota}"
OUT_DIR="${AIQUOTA_APP_ONLY_OUTPUT_DIR:-build/app-only-export}"
DERIVED="${AIQUOTA_APP_ONLY_DERIVED_DIR:-build/app-only-derived}"

usage() {
  cat <<'USAGE'
Usage: bash Scripts/build_app_only_ipa.sh [options]

Options:
  --bundle ID   Main app bundle ID (default com.example.aiquota)
  --output DIR  Output directory (default build/app-only-export)

Builds an unsigned iPhone device IPA without the Widget extension, App Group,
or shared Keychain entitlement. Use this variant with ESign, all-purpose iOS
signers, Aisi Assistant, or another tool that only supports one app profile.

The signing tool still needs a usable certificate and provisioning profile.
A .p12 file alone is not enough to create a valid iOS code signature.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) APP_BUNDLE="${2:-}"; shift 2 ;;
    --output) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$APP_BUNDLE" ]] || { echo "Bundle ID must not be empty." >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found; run on macOS with Xcode." >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found; install with: brew install xcodegen" >&2; exit 1; }

xcodegen generate --spec project.single-profile.yml
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
  build

APP="$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name 'AIQuotaApp.app' -print -quit)"
[[ -d "$APP" ]] || { echo "Built AIQuotaApp.app not found." >&2; exit 1; }
EMBEDDED_EXTENSION="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -print -quit 2>/dev/null || true)"
[[ -z "$EMBEDDED_EXTENSION" ]] || { echo "App-only build unexpectedly contains an extension." >&2; exit 1; }

find "$APP" -name _CodeSignature -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP" -name embedded.mobileprovision -type f -delete 2>/dev/null || true

STAGE="$(mktemp -d -t aiquota-app-only)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/AIQuota.app"

IPA="$ROOT/$OUT_DIR/AIQuota-app-only-unsigned.ipa"
RESIGN_IPA="$ROOT/$OUT_DIR/AIQuota-app-only-resign.ipa"
(
  cd "$STAGE"
  /usr/bin/zip -qry "$IPA" Payload
)
cp "$IPA" "$RESIGN_IPA"

cat > "$ROOT/$OUT_DIR/AIQuota-app-only-signing-info.txt" <<INFO
QuotaPulse app-only unsigned / re-sign IPA
Minimum iOS: 16.0
Main bundle ID before re-signing: $APP_BUNDLE
Widget extension: not included
App Group entitlement: not required
Shared Keychain entitlement: not required

Recommended for:
- A single provisioning profile
- ESign / all-purpose iOS signing tools
- Aisi Assistant and similar desktop installation tools

The signer may replace the bundle ID. It must sign Payload/AIQuota.app with a
matching provisioning profile. A P12 certificate without a provisioning profile
cannot produce an installable IPA.
INFO

"$ROOT/Scripts/verify_ipa_structure.sh" "$IPA" unsigned-app-only
"$ROOT/Scripts/verify_ipa_structure.sh" "$RESIGN_IPA" unsigned-app-only
(
  cd "$ROOT/$OUT_DIR"
  shasum -a 256 AIQuota-app-only-unsigned.ipa > AIQuota-app-only-unsigned.ipa.sha256
  shasum -a 256 AIQuota-app-only-resign.ipa > AIQuota-app-only-resign.ipa.sha256
)
printf '\nApp-only unsigned IPA: %s\nApp-only re-sign IPA: %s\n' "$IPA" "$RESIGN_IPA"
