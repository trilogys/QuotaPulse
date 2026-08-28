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

s=Path('Shared/AppConfig.swift').read_text(encoding='utf-8')
assert '0.11.0' in s
assert 'AIQuotaKeychainSuffix' in s
assert 'AIQuotaSingleProfile' in s
ks=Path('Shared/KeychainStore.swift').read_text(encoding='utf-8')
assert 'discoverDefaultAccessGroup' in ks
assert 'kSecAttrAccessGroup' in ks
assert 'credentialQuery' in ks and 'AppConfig.isAppOnlyBuild' in ks
assert 'AppConfig.isWidgetExtension' in ks
print('runtime keychain resolution: ok')

theme=Path('Shared/DashboardTheme.swift').read_text(encoding='utf-8')
store=Path('Shared/SharedStore.swift').read_text(encoding='utf-8')
assert 'enum DashboardTheme' in theme
assert all(case in theme for case in ['case neon', 'case graphite', 'case aurora', 'case daylight'])
assert 'defaultValue: DashboardTheme = .daylight' in theme
assert 'dashboardTheme' in store
print('dashboard themes: ok')

proxy=Path('Shared/ProxyConfiguration.swift').read_text(encoding='utf-8')
http=Path('Shared/HTTPClient.swift').read_text(encoding='utf-8')
loopback=Path('AIQuotaApp/LoopbackOAuthServer.swift').read_text(encoding='utf-8')
assert 'case http' in proxy and 'case socks5' in proxy
assert 'connectionProxyDictionary' in http and 'ProxyAuthenticationDelegate' in http
assert 'requiredLocalEndpoint' not in loopback and 'allowLocalEndpointReuse' in loopback
print('proxy / OAuth networking: ok')

history=Path('Shared/UsageHistory.swift').read_text(encoding='utf-8')
history_view=Path('AIQuotaApp/UsageHistoryView.swift').read_text(encoding='utf-8')
usage=Path('Shared/UsageService.swift').read_text(encoding='utf-8')
assert 'UsageHistorySample' in history and 'UsageHistoryMetricKind' in history
assert 'import Charts' in history_view
assert all(value in history_view for value in ['case ring', 'case bar', 'case line', 'case heatmap'])
assert 'aggregateHistory' in store and 'clearHistory' in store
assert 'rate-limit-reset-credits/consume' in usage
assert all(value in usage for value in ['credit_id', 'redeem_request_id', 'queryCodexResetCredits', 'consumeCodexResetCredit'])
print('local usage history / charts: ok')

icons=list(Path('AIQuotaApp/Assets.xcassets/AppIcon.appiconset').glob('AppIcon-*.png'))
assert len(icons)==15
print('AppIcon catalog: ok')

models=Path('Shared/Models.swift').read_text(encoding='utf-8')
health=Path('Shared/ProviderHealth.swift').read_text(encoding='utf-8')
for case in ['authentication', 'rateLimited', 'providerUnavailable', 'network', 'invalidResponse', 'configuration', 'unknown']:
    assert f'case {case}' in models, case
assert 'effectiveErrorKind' in health
assert 'healthState' in health
assert 'HTTP 401' not in health  # classifier matches status fragments, not provider-specific hardcoding
assert 'kind:ProviderErrorKind?' in store or 'kind: ProviderErrorKind?' in store
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
grep -q 'build_app_only_ipa.sh' .github/workflows/ipa.yml
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.xcconfig
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.single-profile.xcconfig
grep -q 'AIQUOTA_RELEASE_STORE_FILE: ../release.keystore' .github/workflows/android.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.single-profile.yml
echo "signing / IPA configuration: ok"

python3 - <<'PY'
from pathlib import Path
widget=Path('AIQuotaWidget/AIQuotaWidget.swift').read_text(encoding='utf-8')
content=Path('AIQuotaApp/ContentView.swift').read_text(encoding='utf-8')
single=Path('project.single-profile.yml').read_text(encoding='utf-8')
assert 'StaticConfiguration' in widget
assert 'AppIntentConfiguration' in widget
assert '#available(iOS 17.0, *)' in widget
assert 'ContentUnavailableView' not in content
assert 'RefreshIntents.swift' in single and 'WidgetConfigurationIntent.swift' in single
assert Path('Scripts/build_app_only_ipa.sh').exists()
print('iOS 16 / app-only compatibility contracts: ok')
PY

python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    print('yaml parse: skipped (PyYAML unavailable)')
else:
    for p in Path('.github/workflows').glob('*.yml'):
        yaml.safe_load(p.read_text(encoding='utf-8'))
    yaml.safe_load(Path('project.yml').read_text(encoding='utf-8'))
    yaml.safe_load(Path('project.single-profile.yml').read_text(encoding='utf-8'))
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
