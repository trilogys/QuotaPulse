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
assert 'overviewAutoRefreshSeconds' in store
print('dashboard themes: ok')

proxy=Path('Shared/ProxyConfiguration.swift').read_text(encoding='utf-8')
http=Path('Shared/HTTPClient.swift').read_text(encoding='utf-8')
loopback=Path('AIQuotaApp/LoopbackOAuthServer.swift').read_text(encoding='utf-8')
sub2api=Path('Shared/Sub2APIConfigImport.swift').read_text(encoding='utf-8')
assert 'case http' in proxy and 'case socks5' in proxy
assert 'connectionProxyDictionary' in http and 'ProxyAuthenticationDelegate' in http
assert all(value in proxy for value in ['socket', 'socks5://', 'SOCKSEnable', 'SOCKSProxy', 'SOCKSUser'])
assert all(value in proxy for value in ['AppProxyProfile', 'AppProxyTarget', 'legacyID'])
assert all(value in store for value in ['proxyProfiles', 'activeProxyProfile', 'setProxyProfileActive'])
assert 'profileID' in ks
assert all(value in sub2api for value in ['sub2api-data', 'openai', 'anthropic', 'proxy_key', 'access_token'])
assert 'decodeForImport' in Path('Shared/PortableConfig.swift').read_text(encoding='utf-8')
assert 'requiredLocalEndpoint' not in loopback and 'allowLocalEndpointReuse' in loopback
print('proxy / Sub2API import / OAuth networking: ok')

history=Path('Shared/UsageHistory.swift').read_text(encoding='utf-8')
history_view=Path('AIQuotaApp/UsageHistoryView.swift').read_text(encoding='utf-8')
usage=Path('Shared/UsageService.swift').read_text(encoding='utf-8')
assert 'UsageHistorySample' in history and 'UsageHistoryMetricKind' in history
assert 'import Charts' in history_view
assert all(value in history_view for value in ['case ring', 'case bar', 'case line', 'case heatmap'])
assert 'case tokens' in history and 'Codex OAuth 提供累计与每日 Token' in history_view
assert all(value in history_view for value in ['CodexOfficialTokenActivityCard', '53 * 7', 'case daily', 'case weekly', 'case cumulative'])
assert all(value in history_view for value in ['总计 Token', '峰值 Token', '当前连续天数', '最长连续天数'])
assert 'aggregateHistory' in store and 'clearHistory' in store
assert 'DeepSeek 官方余额接口只返回账户余额' in history_view
assert 'rate-limit-reset-credits/consume' in usage
assert all(value in usage for value in ['credit_id', 'redeem_request_id', 'queryCodexResetCredits', 'consumeCodexResetCredit'])
assert '/wham/profiles/me' in usage and 'daily_usage_buckets' in usage
assert all(value in usage for value in ['/wham/tasks?limit=50', '/wham/usage/thread_usage/query', 'queryCodexModelUsage'])
assert all(value in usage for value in ['fetchOpenAIAPIKey', 'fetchClaudeAPIKey', 'fetchKimiAPIKey', 'organization/usage/completions'])
models_text=Path('Shared/Models.swift').read_text(encoding='utf-8')
assert 'codexTokenUsage' in models_text and 'CodexModelTokenUsage' in models_text
assert 'CredentialAuthenticationMode' in models_text and 'case apiKey' in models_text
print('OAuth token usage / local history / charts: ok')

android_models=Path('android/app/src/main/java/com/trilogys/aiquota/core/Models.kt').read_text(encoding='utf-8')
android_usage=Path('android/app/src/main/java/com/trilogys/aiquota/core/UsageService.kt').read_text(encoding='utf-8')
android_ui=Path('android/app/src/main/java/com/trilogys/aiquota/MainActivity.kt').read_text(encoding='utf-8')
import xml.etree.ElementTree as ET
assert 'CredentialAuthenticationMode' in android_models and 'connectionLabel' in android_models
assert all(value in android_usage for value in ['fetchOpenAIKey', 'fetchClaudeKey', 'fetchKimiKey'])
assert 'CredentialAuthenticationMode.API_KEY' in android_ui and 'snapshot?.connectionLabel' in android_ui
for strings in [Path('android/app/src/main/res/values/strings.xml'), Path('android/app/src/main/res/values-zh-rCN/strings.xml')]:
    root=ET.parse(strings).getroot()
    values={item.attrib.get('name'): item.text for item in root.findall('string')}
    assert values.get('access_token') == 'Access Token / API Key', strings
print('Android OAuth / API key modes: ok')

assets=Path('AIQuotaApp/Assets.xcassets')
for name in ['AppIcon', 'AppIconClassic', 'AppIconNight']:
    icons=list((assets / f'{name}.appiconset').glob('AppIcon-*.png'))
    assert len(icons)==15, (name, len(icons))
for name in ['AppIconCurrentPreview', 'AppIconClassicPreview', 'AppIconNightPreview']:
    assert (assets / f'{name}.imageset' / 'preview.png').exists(), name
print('AppIcon catalogs and Settings previews: ok')

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
grep -q 'build/app-only-export/QuotaPulse.ipa' .github/workflows/ipa.yml
grep -q 'RESIGN_IPA="$ROOT/$OUT_DIR/QuotaPulse.ipa"' Scripts/build_app_only_ipa.sh
grep -q 'build_app_only_ipa.sh' .github/workflows/ipa.yml
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.xcconfig
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.single-profile.xcconfig
grep -q 'AIQUOTA_RELEASE_STORE_FILE: ../release.keystore' .github/workflows/android.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.single-profile.yml
grep -q 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIconClassic AppIconNight"' project.yml
grep -q 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIconClassic AppIconNight"' project.single-profile.yml
grep -q 'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: true' project.yml
grep -q 'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: true' project.single-profile.yml
echo "signing / IPA configuration: ok"

python3 - <<'PY'
from pathlib import Path
widget=Path('AIQuotaWidget/AIQuotaWidget.swift').read_text(encoding='utf-8')
content=Path('AIQuotaApp/ContentView.swift').read_text(encoding='utf-8')
api_key=Path('AIQuotaApp/APIKeyEntryView.swift').read_text(encoding='utf-8')
single=Path('project.single-profile.yml').read_text(encoding='utf-8')
assert 'StaticConfiguration' in widget
assert 'AppIntentConfiguration' in widget
assert '#available(iOS 17.0, *)' in widget
assert 'ContentUnavailableView' not in content
assert 'newOAuthAccountName' in content and '账号名称（可选）' in api_key
assert 'runOverviewAutoRefresh' in content and 'refreshAll(manual: false)' in content
assert 'snapshots: model.snapshots' in content
assert all(value in content for value in ['OpenAI / GPT · API Key', 'Claude · API Key', 'Kimi · API Key', '更新 Key'])
assert 'authenticationMode:.apiKey' in Path('AIQuotaApp/AppModel.swift').read_text(encoding='utf-8')
assert 'setAlternateIconName' in content and 'supportsAlternateIcons' in content
assert all(value in content for value in ['AppIconClassic', 'AppIconNight', 'AppIconCurrentPreview'])
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
