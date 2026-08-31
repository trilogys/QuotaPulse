#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: $0 resigned.ipa" >&2; exit 2; }
IPA="$1"
[[ -f "$IPA" ]] || { echo "IPA not found: $IPA" >&2; exit 1; }
command -v codesign >/dev/null 2>&1 || { echo "codesign required; run this diagnostic on macOS." >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t quotapulse-resign-check)"
trap 'rm -rf "$TMP"' EXIT
if command -v ditto >/dev/null 2>&1; then ditto -x -k "$IPA" "$TMP"; else unzip -q "$IPA" -d "$TMP"; fi
APP="$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
[[ -d "$APP" ]] || { echo "FAIL: Payload/*.app missing" >&2; exit 1; }
WIDGET="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -print -quit 2>/dev/null || true)"
[[ -d "$WIDGET" ]] || { echo "FAIL: embedded Widget .appex missing" >&2; exit 1; }

APP_PLIST="$APP/Info.plist"; WIDGET_PLIST="$WIDGET/Info.plist"
read_plist(){ /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
APP_ID="$(read_plist "$APP_PLIST" CFBundleIdentifier)"
WIDGET_ID="$(read_plist "$WIDGET_PLIST" CFBundleIdentifier)"
EXPECTED_GROUP="$(read_plist "$APP_PLIST" QuotaPulseAppGroup)"
KEY_SUFFIX="$(read_plist "$APP_PLIST" QuotaPulseKeychainSuffix)"

echo "QuotaPulse re-signed IPA diagnostic"
echo "Main bundle:   $APP_ID"
echo "Widget bundle: $WIDGET_ID"
echo "Built group:   $EXPECTED_GROUP"
echo "Key suffix:    $KEY_SUFFIX"

fail=0
if ! codesign --verify --strict --verbose=2 "$APP"; then echo "FAIL: main app signature invalid"; fail=1; else echo "OK: main app signature"; fi
if ! codesign --verify --strict --verbose=2 "$WIDGET"; then echo "FAIL: Widget signature invalid"; fail=1; else echo "OK: Widget signature"; fi
codesign -d --entitlements - "$APP" 2> "$TMP/app-ent.plist" || { echo "FAIL: cannot read main entitlements"; exit 1; }
codesign -d --entitlements - "$WIDGET" 2> "$TMP/widget-ent.plist" || { echo "FAIL: cannot read Widget entitlements"; exit 1; }

python3 - "$TMP/app-ent.plist" "$TMP/widget-ent.plist" "$EXPECTED_GROUP" "$KEY_SUFFIX" <<'PY' || fail=1
import plistlib,sys
ap,wp,expected,key_suffix=sys.argv[1:]
def load(p):
    with open(p,'rb') as f:return plistlib.load(f)
def values(e,k): return set(map(str,e.get(k) or []))
a=load(ap); w=load(wp)
aG=values(a,'com.apple.security.application-groups'); wG=values(w,'com.apple.security.application-groups')
aK=values(a,'keychain-access-groups'); wK=values(w,'keychain-access-groups')
sharedG=aG&wG; sharedK=aK&wK
print('Main App Groups:', sorted(aG))
print('Widget App Groups:', sorted(wG))
print('Shared App Groups:', sorted(sharedG))
print('Main Keychain Groups:', sorted(aK))
print('Widget Keychain Groups:', sorted(wK))
print('Shared Keychain Groups:', sorted(sharedK))
errors=[]
if not sharedG: errors.append('main app and Widget do not share an App Group')
if expected and expected not in sharedG: errors.append(f'built App Group {expected!r} was not preserved by the signer')
if not sharedK: errors.append('main app and Widget do not share a Keychain access group')
if key_suffix and not any(k==key_suffix or k.endswith('.'+key_suffix) for k in sharedK): errors.append(f'shared Keychain does not preserve suffix {key_suffix!r}')
if errors:
    for e in errors: print('FAIL:',e)
    raise SystemExit(1)
print('OK: App Group and Keychain sharing are compatible.')
PY

if [[ -f "$APP/embedded.mobileprovision" ]]; then echo "OK: main embedded.mobileprovision present"; else echo "WARN: main embedded.mobileprovision missing"; fi
if [[ -f "$WIDGET/embedded.mobileprovision" ]]; then echo "OK: Widget embedded.mobileprovision present"; else echo "WARN: Widget embedded.mobileprovision missing"; fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "RESULT: FAIL — the re-signed IPA may install but QuotaPulse Widget/account sharing is not reliable."
  exit 1
fi
echo
echo "RESULT: PASS — signatures and shared entitlements required by QuotaPulse are intact."
echo "Note: iOS can still delay WidgetKit background refresh; this check validates packaging/signing, not system scheduling frequency."
