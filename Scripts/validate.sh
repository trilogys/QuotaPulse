#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import plistlib
for p in [Path('AIQuotaApp/AIQuotaApp.entitlements'), Path('AIQuotaWidget/AIQuotaWidget.entitlements')]:
    with p.open('rb') as f: d=plistlib.load(f)
    assert 'com.apple.security.application-groups' in d, p
    assert 'keychain-access-groups' in d, p
print('entitlements: ok')

s=Path('Shared/AppConfig.swift').read_text()
assert '0.8.0' in s
assert 'AIQuotaKeychainSuffix' in s
ks=Path('Shared/KeychainStore.swift').read_text()
assert 'discoverDefaultAccessGroup' in ks
assert 'kSecAttrAccessGroup' in ks
print('v0.8 runtime keychain resolution: ok')

models=Path('Shared/Models.swift').read_text()
health=Path('Shared/ProviderHealth.swift').read_text()
store=Path('Shared/SharedStore.swift').read_text()
for case in ['authentication', 'rateLimited', 'providerUnavailable', 'network', 'invalidResponse', 'configuration', 'unknown']:
    assert f'case {case}' in models, case
assert 'effectiveErrorKind' in health
assert 'healthState' in health
assert 'HTTP 401' not in health  # classifier matches status fragments, not provider-specific hardcoding
assert 'kind: ProviderErrorKind?' in store
print('provider health contracts: ok')
PY

for s in Scripts/*.sh; do bash -n "$s"; done
echo "shell syntax: ok"

grep -q 'AIQUOTA_APP_PROFILE_SPECIFIER' project.yml
grep -q 'AIQUOTA_WIDGET_PROFILE_SPECIFIER' project.yml
grep -q 'INFOPLIST_KEY_AIQuotaKeychainSuffix' project.yml
grep -q '#include? "SigningConfig.xcconfig"' Config.xcconfig
grep -q 'build_type:' .github/workflows/ipa.yml
grep -q 'AIQuota-unsigned.ipa' .github/workflows/ipa.yml
grep -q 'AIQuota-signed.ipa' .github/workflows/ipa.yml
echo "signing / IPA configuration: ok"

python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    print('yaml parse: skipped (PyYAML unavailable)')
else:
    for p in Path('.github/workflows').glob('*.yml'):
        yaml.safe_load(p.read_text())
    yaml.safe_load(Path('project.yml').read_text())
    print('yaml parse: ok')
PY

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
  echo "xcodegen: ok"
else
  echo "xcodegen: skipped (not installed)"
fi

if command -v swiftc >/dev/null 2>&1; then
  swiftc -parse Shared/*.swift AIQuotaApp/*.swift AIQuotaWidget/*.swift >/dev/null
  echo "swift parse: ok"
else
  echo "swift parse: skipped (swiftc unavailable)"
fi
