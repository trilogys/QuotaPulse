#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew/xcodegen not found. Install XcodeGen first: brew install xcodegen" >&2
    exit 1
  fi
  brew install xcodegen
fi
xcodegen generate
printf '\nGenerated AIQuota.xcodeproj. Open it in Xcode and select your Development Team.\n'
