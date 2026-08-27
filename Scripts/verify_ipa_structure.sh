#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 file.ipa [unsigned|signed]" >&2; exit 2; }
IPA="$1"
MODE="${2:-unsigned}"
[[ -f "$IPA" ]] || { echo "IPA not found: $IPA" >&2; exit 1; }
[[ "$MODE" == "unsigned" || "$MODE" == "signed" ]] || { echo "Mode must be unsigned or signed" >&2; exit 2; }

TMP="$(mktemp -d -t aiquota-ipa-check)"
trap 'rm -rf "$TMP"' EXIT
if command -v ditto >/dev/null 2>&1; then ditto -x -k "$IPA" "$TMP"; else unzip -q "$IPA" -d "$TMP"; fi
APP="$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
[[ -d "$APP" ]] || { echo "FAIL: Payload/*.app missing" >&2; exit 1; }
WIDGET="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -print -quit 2>/dev/null || true)"
[[ -d "$WIDGET" ]] || { echo "FAIL: Widget .appex missing" >&2; exit 1; }

plist_value() { local plist="$1" key="$2"; if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true; else python3 - "$plist" "$key" <<'PY'
import plistlib,sys
p,k=sys.argv[1:]
with open(p,'rb') as f:d=plistlib.load(f)
print(d.get(k,''))
PY
fi; }
APP_ID="$(plist_value "$APP/Info.plist" CFBundleIdentifier)"
WIDGET_ID="$(plist_value "$WIDGET/Info.plist" CFBundleIdentifier)"
GROUP="$(plist_value "$APP/Info.plist" AIQuotaAppGroup)"
KEYCHAIN="$(plist_value "$APP/Info.plist" AIQuotaKeychainSuffix)"
[[ -n "$APP_ID" && -n "$WIDGET_ID" ]] || { echo "FAIL: bundle identifiers missing" >&2; exit 1; }
printf 'App:     %s\nWidget:  %s\nGroup:   %s\nKeychain suffix:%s\n' "$APP_ID" "$WIDGET_ID" "$GROUP" "$KEYCHAIN"

if [[ "$MODE" == "signed" ]]; then
  command -v codesign >/dev/null 2>&1 || { echo "codesign required for signed verification" >&2; exit 1; }
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign --verify --strict --verbose=2 "$WIDGET"
  codesign -d --entitlements - "$APP" 2> "$TMP/app-entitlements.plist"
  codesign -d --entitlements - "$WIDGET" 2> "$TMP/widget-entitlements.plist"
  python3 - "$TMP/app-entitlements.plist" "$TMP/widget-entitlements.plist" "$GROUP" "$KEYCHAIN" <<'PY'
import plistlib,sys
ap,wp,expected_group,key_suffix=sys.argv[1:]
def load(p):
    with open(p,'rb') as f:return plistlib.load(f)
def one(label,e):
    groups=e.get('com.apple.security.application-groups') or []
    keys=e.get('keychain-access-groups') or []
    if not groups: raise SystemExit(f'FAIL: {label} has no application-groups entitlement')
    if not keys: raise SystemExit(f'FAIL: {label} has no keychain-access-groups entitlement')
    return set(map(str,groups)),set(map(str,keys))
aG,aK=one('main app',load(ap)); wG,wK=one('Widget',load(wp))
sharedG=aG&wG
if expected_group and expected_group not in sharedG:
    raise SystemExit(f'FAIL: app/widget do not share expected App Group {expected_group!r}; shared={sorted(sharedG)}')
if not sharedG: raise SystemExit('FAIL: app/widget have no shared App Group')
sharedK=aK&wK
if key_suffix:
    matches=[g for g in sharedK if g==key_suffix or g.endswith('.'+key_suffix)]
    if not matches: raise SystemExit(f'FAIL: app/widget do not share Keychain suffix {key_suffix!r}; shared={sorted(sharedK)}')
elif not sharedK: raise SystemExit('FAIL: app/widget have no shared Keychain access group')
print('Shared App Group:', ', '.join(sorted(sharedG)))
print('Shared Keychain group:', ', '.join(sorted(sharedK)))
PY
  echo "Signed IPA structure/signatures/shared entitlements: OK"
else
  if [[ -d "$APP/_CodeSignature" || -d "$WIDGET/_CodeSignature" ]]; then echo "FAIL: unsigned IPA unexpectedly contains _CodeSignature" >&2; exit 1; fi
  echo "Unsigned IPA structure: OK"
fi
