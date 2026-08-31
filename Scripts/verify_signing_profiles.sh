#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 App.mobileprovision Widget.mobileprovision" >&2
  echo "Requires SigningConfig.xcconfig to already exist." >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/SigningConfig.xcconfig"
[[ -f "$CFG" ]] || { echo "Missing $CFG" >&2; exit 2; }
command -v security >/dev/null || { echo "macOS security tool required." >&2; exit 1; }

get_cfg() {
  local key="$1"
  grep -E "^${key} *=" "$CFG" | tail -1 | cut -d= -f2- | xargs
}
TEAM="$(get_cfg QUOTAPULSE_TEAM_ID)"
APP_BUNDLE="$(get_cfg QUOTAPULSE_APP_BUNDLE_ID)"
WIDGET_BUNDLE="$(get_cfg QUOTAPULSE_WIDGET_BUNDLE_ID)"
APP_GROUP="$(get_cfg QUOTAPULSE_APP_GROUP)"
KEYCHAIN_SUFFIX="$(get_cfg QUOTAPULSE_KEYCHAIN_SUFFIX)"

TMP="$(mktemp -d -t quotapulse-profiles)"
trap 'rm -rf "$TMP"' EXIT
security cms -D -i "$1" > "$TMP/app.plist"
security cms -D -i "$2" > "$TMP/widget.plist"

python3 - "$TMP/app.plist" "$TMP/widget.plist" "$TEAM" "$APP_BUNDLE" "$WIDGET_BUNDLE" "$APP_GROUP" "$KEYCHAIN_SUFFIX" <<'PY'
import plistlib, sys, datetime
app_path, widget_path, team, app_bundle, widget_bundle, app_group, key_suffix = sys.argv[1:]

def load(path):
    with open(path, 'rb') as f: return plistlib.load(f)

def allowed_app_id(profile_id, bundle):
    if not profile_id: return False
    suffix = profile_id.split('.', 1)[1] if '.' in profile_id else profile_id
    if suffix == '*': return True
    if suffix.endswith('*'): return bundle.startswith(suffix[:-1])
    return suffix == bundle

def profile_prefix(p):
    vals=p.get('ApplicationIdentifierPrefix') or []
    if vals: return str(vals[0]).rstrip('.')
    ent=p.get('Entitlements') or {}
    aid=ent.get('application-identifier') or ent.get('com.apple.application-identifier')
    return aid.split('.',1)[0] if aid and '.' in aid else None

def keychain_allowed(groups, prefix, suffix):
    desired = f"{prefix}.{suffix}"
    for g in groups or []:
        if g == desired: return True
        if g == f"{prefix}.*": return True
        if g.endswith('*') and desired.startswith(g[:-1]): return True
    return False

def verify(label, p, bundle):
    errors=[]
    prefix=profile_prefix(p)
    if not prefix:
        errors.append('could not determine ApplicationIdentifierPrefix')
    teams=p.get('TeamIdentifier') or []
    if team not in teams:
        errors.append(f"Team ID {team} not authorized (profile teams={teams})")
    ent=p.get('Entitlements') or {}
    appid=ent.get('application-identifier') or ent.get('com.apple.application-identifier')
    if not allowed_app_id(appid, bundle):
        errors.append(f"application-identifier {appid!r} does not authorize {bundle}")
    groups=ent.get('com.apple.security.application-groups') or []
    if app_group not in groups:
        errors.append(f"App Group {app_group!r} missing (profile groups={groups})")
    kgs=ent.get('keychain-access-groups') or []
    if prefix and not keychain_allowed(kgs, prefix, key_suffix):
        errors.append(f"Keychain group {prefix}.{key_suffix} not authorized (profile groups={kgs})")
    exp=p.get('ExpirationDate')
    if exp and exp.replace(tzinfo=None) <= datetime.datetime.utcnow():
        errors.append(f"profile expired at {exp}")
    if errors:
        print(f"{label}: FAIL")
        for e in errors: print(f"  - {e}")
        return False
    print(f"{label}: OK — {p.get('Name','(unnamed)')}")
    return True

ok1=verify('Main app profile', load(app_path), app_bundle)
ok2=verify('Widget profile', load(widget_path), widget_bundle)
if not (ok1 and ok2): raise SystemExit(1)
print('Signing profiles are mutually compatible with SigningConfig.xcconfig.')
PY
