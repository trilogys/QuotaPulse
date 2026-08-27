#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 certificate.p12" >&2
  echo "Imports a .p12 into the macOS login keychain interactively." >&2
  exit 2
fi
P12="$1"
[[ -f "$P12" ]] || { echo "Not found: $P12" >&2; exit 2; }
command -v security >/dev/null || { echo "macOS security tool required." >&2; exit 1; }

read -r -s -p "P12 password: " P12_PASSWORD
echo
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
unset P12_PASSWORD
security find-identity -v -p codesigning
