#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import plistlib
legacy_values=['AI'+'Quota','AI'+'QUOTA','ai'+'quota','ai-quota'+'-native','AI Quota'+' Native']
text_suffixes={'.swift','.kt','.kts','.yml','.yaml','.md','.sh','.xcconfig','.plist','.xml','.json','.strings','.py','.entitlements'}
for path in Path('.').rglob('*'):
    if not path.is_file() or '.git' in path.parts or 'build' in path.parts or 'dist' in path.parts or path.name == 'provider_research_fetch.md':
        continue
    assert not any(value in path.as_posix() for value in legacy_values), path
    if path.suffix.lower() in text_suffixes:
        text=path.read_text(encoding='utf-8')
        assert not any(value in text for value in legacy_values), path
print('legacy naming: none')

for p in [Path('QuotaPulseApp/QuotaPulseApp.entitlements'), Path('QuotaPulseWidget/QuotaPulseWidget.entitlements')]:
    with p.open('rb') as f: d=plistlib.load(f)
    assert 'com.apple.security.application-groups' in d, p
    assert 'keychain-access-groups' in d, p
print('entitlements: ok')

s=Path('Shared/AppConfig.swift').read_text(encoding='utf-8')
assert '1.0.0' in s
assert 'QuotaPulseKeychainSuffix' in s
assert 'QuotaPulseSingleProfile' in s
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
loopback=Path('QuotaPulseApp/LoopbackOAuthServer.swift').read_text(encoding='utf-8')
sub2api=Path('Shared/Sub2APIConfigImport.swift').read_text(encoding='utf-8')
assert 'case http' in proxy and 'case socks5' in proxy
assert 'connectionProxyDictionary' in http and 'ProxyAuthenticationDelegate' in http
assert all(value in http for value in ['SystemVPNDetector', 'getifaddrs', 'SystemVPNDetector.isActive()', 'finishTasksAndInvalidate'])
assert all(value in proxy for value in ['socket', 'socks5://', 'SOCKSEnable', 'SOCKSProxy', 'SOCKSUser'])
assert 'kCFProxyUsernameKey' in proxy and 'case 306, 310' in http
assert all(value in proxy for value in ['AppProxyProfile', 'AppProxyTarget', 'legacyID'])
proxy_view=Path('QuotaPulseApp/ProxySettingsView.swift').read_text(encoding='utf-8')
assert all(value in proxy_view for value in ['测试服务', 'testSavedProfile', 'savedResults', 'latencyMilliseconds'])
assert all(value in proxy_view for value in ['systemVPNActive', '系统 VPN 已连接', '优先使用系统 VPN'])
assert all(value not in proxy_view for value in ['Section("代理类型")', 'Section("服务器")', '解析代理链接'])
assert all(value in store for value in ['proxyProfiles', 'activeProxyProfile', 'setProxyProfileActive'])
assert 'profileID' in ks
assert all(value in sub2api for value in ['sub2api-data', 'openai', 'anthropic', 'proxy_key', 'access_token'])
assert 'decodeForImport' in Path('Shared/PortableConfig.swift').read_text(encoding='utf-8')
assert 'requiredLocalEndpoint' not in loopback and 'allowLocalEndpointReuse' in loopback
print('proxy / Sub2API import / OAuth networking: ok')

history=Path('Shared/UsageHistory.swift').read_text(encoding='utf-8')
history_view=Path('QuotaPulseApp/UsageHistoryView.swift').read_text(encoding='utf-8')
usage=Path('Shared/UsageService.swift').read_text(encoding='utf-8')
assert 'UsageHistorySample' in history and 'UsageHistoryMetricKind' in history
assert 'import Charts' in history_view
assert all(value in history_view for value in ['case ring', 'case bar', 'case line', 'case heatmap'])
assert 'chart.pie.fill' in history_view and 'chart.donut' not in history_view
assert 'case tokens' in history and 'Codex OAuth 提供累计与每日 Token' in history_view
assert all(value in history_view for value in ['CodexOfficialTokenActivityCard', '53 * 7', 'case daily', 'case weekly', 'case cumulative'])
assert all(value in history_view for value in ['点按日期查看用量', 'selectedCell.dailyTokens', 'selectedHeatmapPoint = point', 'selectedHeatmapValues'])
assert '.frame(width: 13, height: 13)' in history_view and '.font(.system(size: 10, weight: .semibold))' in history_view
assert all(value in history_view for value in ['总计 Token', '峰值 Token', '当前连续天数', '最长连续天数'])
assert 'aggregateHistory' in store and 'clearHistory' in store
assert 'DeepSeek 官方余额接口只返回账户余额' in history_view
assert 'rate-limit-reset-credits/consume' in usage
assert all(value in usage for value in ['credit_id', 'redeem_request_id', 'queryCodexResetCredits', 'consumeCodexResetCredit'])
assert '/wham/profiles/me' in usage and 'daily_usage_buckets' in usage
assert all(value in usage for value in ['/wham/tasks?limit=50', '/wham/usage/thread_usage/query', 'queryCodexModelUsage'])
assert all(value in usage for value in ['fetchOpenAIAPIKey', 'fetchClaudeAPIKey', 'fetchKimiAPIKey', 'organization/usage/completions'])
assert 'users/me/balance' in usage
assert 'fetchDeepSeek' in usage and r'\(base)/models' in usage
models_text=Path('Shared/Models.swift').read_text(encoding='utf-8')
assert 'codexTokenUsage' in models_text and 'CodexModelTokenUsage' in models_text
assert 'CredentialAuthenticationMode' in models_text and 'case apiKey' in models_text
print('OAuth token usage / local history / charts: ok')

android_models=Path('android/app/src/main/java/com/trilogys/quotapulse/core/Models.kt').read_text(encoding='utf-8')
android_usage=Path('android/app/src/main/java/com/trilogys/quotapulse/core/UsageService.kt').read_text(encoding='utf-8')
android_ui=Path('android/app/src/main/java/com/trilogys/quotapulse/MainActivity.kt').read_text(encoding='utf-8')
android_portable_ui=Path('android/app/src/main/java/com/trilogys/quotapulse/PortableConfigUi.kt').read_text(encoding='utf-8')
android_theme=Path('android/app/src/main/java/com/trilogys/quotapulse/ui/QuotaPulseTheme.kt').read_text(encoding='utf-8')
android_gradle=Path('android/app/build.gradle.kts').read_text(encoding='utf-8')
import xml.etree.ElementTree as ET
assert 'CredentialAuthenticationMode' in android_models and 'connectionLabel' in android_models
assert all(value in android_usage for value in ['fetchOpenAIKey', 'fetchClaudeKey', 'fetchKimiKey'])
assert 'availableModels=models' in android_usage and 'availableModels' in android_models
assert 'modelIds(body)' in android_usage and 'request("models")' in android_usage
assert 'CredentialAuthenticationMode.API_KEY' in android_ui and 'snapshot.connectionLabel' in android_ui
assert 'R.string.available_models' in android_ui
assert all(value in android_ui for value in ['DashboardOverviewCard', 'AccountDashboardCard', 'ProviderFilterBar', 'AccountEditorSheet', 'SettingsSheet'])
assert 'val quotaColor = palette.success' in android_ui
assert 'import androidx.compose.foundation.layout.weight' not in android_ui
assert all(value in android_theme for value in ['DAYLIGHT', 'NEON', 'GRAPHITE', 'AURORA', 'DashboardThemePreferences', 'LocalDashboardPalette'])
assert 'DashboardThemeOption.DAYLIGHT.name' in android_theme
assert 'material-icons-extended' in android_gradle
assert 'versionCode = 10000' in android_gradle and 'versionName = "1.0.0"' in android_gradle
assert max(map(len, android_ui.splitlines())) < 180
assert 'QuotaPulse-backup-' in android_portable_ui and 'yyyyMMdd-HHmmss' in android_portable_ui
android_string_files=[Path('android/app/src/main/res/values/strings.xml'), Path('android/app/src/main/res/values-zh-rCN/strings.xml')]
android_string_sets=[]
for strings in android_string_files:
    root=ET.parse(strings).getroot()
    values={item.attrib.get('name'): item.text for item in root.findall('string')}
    android_string_sets.append(set(values))
    assert values.get('access_token') == 'Access Token / API Key', strings
assert android_string_sets[0] == android_string_sets[1]
print('Android OAuth / API key modes: ok')

assets=Path('QuotaPulseApp/Assets.xcassets')
for name in ['AppIcon', 'AppIconClassic', 'AppIconNight']:
    icons=list((assets / f'{name}.appiconset').glob('AppIcon-*.png'))
    assert len(icons)==15, (name, len(icons))
for name in ['AppIconCurrentPreview', 'AppIconClassicPreview', 'AppIconNightPreview']:
    assert (assets / f'{name}.imageset' / 'preview.png').exists(), name
print('AppIcon catalogs and Settings previews: ok')

content=Path('QuotaPulseApp/ContentView.swift').read_text(encoding='utf-8')
icon_script=Path('Scripts/generate_app_icon.py').read_text(encoding='utf-8')
assert 'case .classic: nil' in content and 'selectedAppIcon: AppIconChoice = .classic' in content
assert '("AppIcon", "AppIconClassicPreview", draw_classic())' in icon_script
background=Path('QuotaPulseApp/BackgroundRefreshManager.swift').read_text(encoding='utf-8')
backup=Path('QuotaPulseApp/BackupSettingsView.swift').read_text(encoding='utf-8')
assert all(value in background for value in ['BGAppRefreshTaskRequest', 'com.trilogys.quotapulse.refresh', 'scheduleIfEnabled'])
assert all(value in store for value in ['backgroundRefreshEnabled', 'lastSuccessfulRefreshAt'])
assert all(value in backup for value in ['.plainText', 'importInProgress', 'importFeedback', 'importStatusText', 'JSONDocumentPicker', 'onResult:', 'onCancel:', '导入失败', '导入与导出格式', 'QuotaPulse-backup-', 'yyyyMMdd-HHmmss'])
assert all(value in content for value in ['homepageLastRefreshAt', 'refreshIntervalPreset', 'customRefreshMinutes', 'importSharedJSON'])
assert all(value in content for value in ['AccountOverviewRing', 'allAccounts.count > 1', 'checkForUpdate'])
assert all(value in content for value in ['padding(.vertical, 5)', 'padding(.top, 4)', 'private var ringColor', 'theme.success'])
assert all(value in content for value in ['didLoadInitialState', 'refreshOnActivationIfNeeded', 'force: true', 'refreshTimeText'])
update=Path('QuotaPulseApp/UpdateChecker.swift').read_text(encoding='utf-8')
assert all(value in update for value in ['trilogys/QuotaPulse/releases/latest', 'AvailableAppUpdate', 'AppConfig.version'])
assert 'availableModels' in models_text and 'AvailableModelsRow' in content
assert 'users/me/balance' in usage and 'availableModelIDs' in usage
readme=Path('README.md').read_text(encoding='utf-8')
readme_zh=Path('README.zh-CN.md').read_text(encoding='utf-8')
assert '[简体中文](README.zh-CN.md)' in readme and '[English](README.md)' in readme_zh
assert readme.startswith('# QuotaPulse') and 'QuotaPulse is a native iOS and Android' in readme
print('default icon / background refresh / JSON import: ok')

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

grep -q 'QUOTAPULSE_APP_PROFILE_SPECIFIER' project.yml
grep -q 'QUOTAPULSE_WIDGET_PROFILE_SPECIFIER' project.yml
grep -q 'INFOPLIST_KEY_QuotaPulseKeychainSuffix' project.yml
grep -q 'com.trilogys.quotapulse.refresh' project.yml
grep -q 'com.trilogys.quotapulse.refresh' project.single-profile.yml
grep -q 'CFBundleDocumentTypes' project.yml
grep -q 'CFBundleDocumentTypes' project.single-profile.yml
grep -q 'public.json' project.yml
grep -q '#include? "SigningConfig.xcconfig"' Config.xcconfig
grep -q 'build_type:' .github/workflows/ipa.yml
grep -q 'QuotaPulse-unsigned.ipa' .github/workflows/ipa.yml
grep -q 'QuotaPulse-signed.ipa' .github/workflows/ipa.yml
grep -q 'build/app-only-export/QuotaPulse.ipa' .github/workflows/ipa.yml
grep -q 'RESIGN_IPA="$ROOT/$OUT_DIR/QuotaPulse.ipa"' Scripts/build_app_only_ipa.sh
grep -q 'build_app_only_ipa.sh' .github/workflows/ipa.yml
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.xcconfig
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0' Config.single-profile.xcconfig
grep -q 'MARKETING_VERSION: 1.0.0' project.yml
grep -q 'CURRENT_PROJECT_VERSION: 10000' project.yml
grep -q 'MARKETING_VERSION: 1.0.0' project.single-profile.yml
grep -q 'CURRENT_PROJECT_VERSION: 10000' project.single-profile.yml
grep -q 'QUOTAPULSE_RELEASE_STORE_FILE: ../release.keystore' .github/workflows/android.yml
grep -q 'QuotaPulse-Android-debug' .github/workflows/android.yml
grep -q 'QuotaPulse.apk' .github/workflows/android.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.yml
grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.single-profile.yml
grep -q 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIconClassic AppIconNight"' project.yml
grep -q 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIconClassic AppIconNight"' project.single-profile.yml
grep -q 'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: true' project.yml
grep -q 'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: true' project.single-profile.yml
echo "signing / IPA configuration: ok"

python3 - <<'PY'
from pathlib import Path
widget=Path('QuotaPulseWidget/QuotaPulseWidget.swift').read_text(encoding='utf-8')
content=Path('QuotaPulseApp/ContentView.swift').read_text(encoding='utf-8')
api_key=Path('QuotaPulseApp/APIKeyEntryView.swift').read_text(encoding='utf-8')
single=Path('project.single-profile.yml').read_text(encoding='utf-8')
assert 'StaticConfiguration' in widget
assert 'AppIntentConfiguration' in widget
assert '#available(iOS 17.0, *)' in widget
assert '.foregroundStyle(entry.theme.success)' in widget and '.fill(entry.theme.success)' in widget
assert 'ContentUnavailableView' not in content
assert 'newOAuthAccountName' in content and '账号名称（可选）' in api_key
assert 'runOverviewAutoRefresh' in content and 'refreshAll(manual: false)' in content
assert 'snapshots: model.snapshots' in content
assert all(value in content for value in ['OpenAI / GPT · API Key', 'Claude · API Key', 'Kimi · API Key', '更新 Key'])
assert 'authenticationMode:.apiKey' in Path('QuotaPulseApp/AppModel.swift').read_text(encoding='utf-8')
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
  swiftc -parse Shared/*.swift QuotaPulseApp/*.swift QuotaPulseWidget/*.swift >/dev/null
  echo "swift parse: ok"
else
  echo "swift parse: skipped (swiftc unavailable)"
fi
