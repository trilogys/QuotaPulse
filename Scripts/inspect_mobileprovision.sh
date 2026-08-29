#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 path/to/profile.mobileprovision" >&2
  exit 2
fi
PROFILE="$1"
[[ -f "$PROFILE" ]] || { echo "Not found: $PROFILE" >&2; exit 2; }

if ! command -v security >/dev/null 2>&1; then
  echo "This inspector requires macOS 'security'." >&2
  exit 1
fi
TMP="$(mktemp -t quotapulse-profile).plist"
trap 'rm -f "$TMP"' EXIT
security cms -D -i "$PROFILE" > "$TMP"

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$TMP" 2>/dev/null || true
}

NAME="$(read_plist Name)"
UUID="$(read_plist UUID)"
TEAM="$(read_plist 'TeamIdentifier:0')"
APPID="$(read_plist 'Entitlements:application-identifier')"
GROUPS="$(read_plist 'Entitlements:com.apple.security.application-groups')"
KEYCHAINS="$(read_plist 'Entitlements:keychain-access-groups')"
GETTASK="$(read_plist 'Entitlements:get-task-allow')"
EXP="$(read_plist ExpirationDate)"

cat <<OUT
Profile Name: $NAME
UUID:         $UUID
Team ID:      $TEAM
App ID:       $APPID
Expires:      $EXP
get-task-allow: $GETTASK

App Groups:
${GROUPS:-  (none)}

Keychain Access Groups:
${KEYCHAINS:-  (none)}
OUT

if [[ -z "$GROUPS" ]]; then
  echo "WARNING: no App Groups entitlement. The Widget cannot share quota cache with the app." >&2
fi
if [[ -z "$KEYCHAINS" ]]; then
  echo "WARNING: no Keychain Sharing entitlement. The Widget cannot read OAuth/API credentials." >&2
fi
