# AIQuota Native v0.11.0

AI 服务额度监控：**原生 iOS + 原生 Android + 桌面小组件 + 多账号 + 本机凭据保存 + 后台刷新**。

目标是让手机自己完成日常额度查询与 Widget 更新；电脑最多只作为首次 credentials 导入或签名材料准备的可选方式，不作为持续运行的中转设备。

## Provider

- Codex：ChatGPT OAuth / credentials 导入，多账号，动态额度窗口
- Claude：OAuth / credentials 导入，多账号，5h / 周
- Kimi：Device OAuth / credentials 导入，多账号，动态额度窗口
- DeepSeek：API Key，多账号，余额

iOS 端还保留 MiniMax、GLM / Z.ai、GitHub Copilot 等适配，后续逐步同步 Android。

## Visual direction

AIQuota 不直接复制某一个项目的 UI，而是组合三个方向：

- **claude-widget-ios**：iOS 原生 SwiftUI / WidgetKit 的简洁信息密度与系统风格
- **CodexBar**：额度窗口层级、session/weekly/reset 信息架构、stale/error 状态
- **AIQuota 自身**：多账号总览、推荐账号、单账号刷新、Provider/账号级 Widget 配置

最终风格原则：**原生、紧凑、额度优先、刷新状态清晰，不做重装饰 Dashboard。**

## iOS

技术栈：SwiftUI + WidgetKit + App Intents + App Group + Keychain。

当前支持：

- Codex / Claude / Kimi OAuth
- DeepSeek API Key
- OAuth token 自动 refresh
- 多账号 UUID 隔离
- 账号重命名、启用/隐藏、排序
- 每个 Provider 自动标记推荐账号
- 凭据健康状态：正常 / 即将续期 / 可续期 / 需重登 / 缓存
- Codex / Claude / Kimi 原账号一键重新认证，保持 UUID 与 Widget 绑定不变
- 额度 Reset 倒计时
- WidgetKit Small / Medium / Large 自适应信息密度
- Widget 内 `↻` 原地刷新，不打开主 App
- Widget timeline 自动刷新
- stale cache：网络失败保留上次成功数据
- 80% / 90% / 约 100% 已用额度分级通知，按账号/额度窗口去重
- 简体中文 / English 本地化；可使用 iOS 每 App 语言设置切换，Widget 同步语言
- GitHub Actions 构建 unsigned / re-sign / P12 signed IPA

Codex 使用 browser OAuth + PKCE + iPhone 本机 localhost callback；日常刷新不依赖电脑或中转服务器。

### iOS IPA / 重签

`Actions → ipa` 支持：

```text
AIQuota-iOS-resign
├─ AIQuota-resign.ipa
├─ AIQuota-unsigned.ipa
├─ SHA256
└─ signing-info

AIQuota-signed-release-testing / debugging
└─ AIQuota-signed.ipa
```

`AIQuota-resign.ipa` 是标准 IPA，可作为全能签、ESign、爱思助手等第三方签名/安装工具的输入。包内真实包含：

```text
Payload/AIQuota.app/PlugIns/AIQuotaWidget.appex
```

因此重签工具需要同时正确签名主 App 与 Widget Extension，并处理匹配的 App Group / Keychain entitlements。当前 GitHub Actions 已真实验证 unsigned/re-sign IPA 构建、Widget 嵌入和 artifact 上传成功。

P12 模式需要：`.p12` + 密码、主 App `.mobileprovision`、Widget `.mobileprovision`。GitHub Actions 会解析 Team / Bundle ID / App Group、验证 profile 兼容性并生成签名 IPA。详见 `IPA.md` / `SIGNING.md`。

## Android

技术栈：Kotlin + Jetpack Compose + Jetpack Glance + WorkManager + Android Keystore/EncryptedSharedPreferences。

当前支持：

- Codex browser OAuth + PKCE
- localhost callback；自动回调失败时可粘贴完整 callback URL
- Claude OAuth，授权后粘贴 `CODE#STATE`
- Kimi Device OAuth，浏览器确认 + App 自动轮询 token
- Codex / Claude / Kimi refresh token 自动续期
- Kimi device headers 持久化
- DeepSeek API Key 查询余额
- 多账号 UUID 隔离
- 凭据健康状态与原账号重新认证覆盖模式
- Reset 倒计时
- EncryptedSharedPreferences + Android Keystore 保存敏感凭据
- 本地 usage snapshot cache；失败时保留旧数据并标记 stale
- WorkManager 每 15 分钟后台刷新
- Jetpack Glance 桌面 Widget
- Widget 独立配置：全部账号 / 单 Provider / 单账号
- Widget 独立布局：紧凑 / 详细
- Widget 独立显示条数：1 / 2 / 4 / 6 / 8
- Widget 根据实际宽高自动减少行数；空间不足时自动降级为紧凑模式
- Widget `↻` 定向刷新：总览 / Provider / 单账号按配置缩小请求范围
- 账号显示/隐藏、上下排序、推荐账号
- 80% / 90% / 约 100% 已用额度分级通知
- 简体中文 / English 资源化；Android 13+ 支持系统“应用语言”单独切换
- GitHub Actions 自动构建 debug APK；配置 Secrets 后额外生成签名 release APK

## 认证策略

```text
Codex
  OAuth + PKCE
    → localhost 自动 callback
    → callback URL 手动粘贴 fallback
    → 已有 credentials 导入 fallback

Claude
  OAuth 授权页
    → CODE#STATE 粘贴
    → credentials 导入 fallback

Kimi
  Device OAuth
    → 浏览器确认
    → App 自动轮询 token
    → credentials 导入 fallback

DeepSeek
  API Key
```

所有账号的 access token / refresh token / API Key 独立保存；重新认证会覆盖原账号凭据而保留 Account UUID，因此已配置 Widget 不会失去绑定。

## Widget 刷新

### iOS

- WidgetKit timeline 请求自动刷新
- 设置可选 10 / 15 / 30 / 60 / 120 分钟的最早请求时间
- 实际后台调度时间由 iOS 决定
- Interactive Widget `↻` 立即执行刷新，`openAppWhenRun = false`

### Android

- WorkManager 15 分钟周期刷新，只在网络可用时执行
- Widget `↻` 使用 OneTimeWorkRequest
- Worker 根据当前 Widget 配置缩小请求范围
- 完成后调用 Glance `updateAll()` 更新桌面 Widget
- Widget 使用 `LocalSize` 根据实际尺寸调整行数/信息密度

## 推荐账号规则

对于 Codex / Claude / Kimi：

```text
账号评分 = min(该账号所有额度窗口剩余百分比)
推荐账号 = 同 Provider 中评分最高的账号
```

DeepSeek 等余额型 Provider 按可用余额比较。

## 额度提醒

双端统一三级：

- 已用约 80%：剩余 ≤ 20%
- 已用约 90%：剩余 ≤ 10%
- 已用约 100%：剩余 ≤ 0.5%

同一账号、同一额度窗口、同一级别不会被后台刷新反复通知；额度恢复到安全区后重置提醒状态。

## Android Release APK

默认 workflow 生成 debug APK。若希望 GitHub Actions 同时生成正式签名 APK，在 `Settings → Secrets and variables → Actions` 配置：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

然后运行 `Actions → Android`，额外生成 `AIQuota-Android-release/app-release.apk`。

## 安全

- iOS：OAuth token / API Key 存共享 Keychain，按 Account UUID 隔离
- Android：OAuth token / API Key 存 EncryptedSharedPreferences，主密钥由 Android Keystore 管理
- 普通账号配置和 Widget snapshot 不保存 token
- Android release keystore/password 不进入 Git 仓库
- iOS P12/profile/password 只通过 GitHub Actions Secrets 注入
- 日志、Widget、错误提示不应输出完整 token、refresh token、Cookie 或 API Key

## 项目结构

```text
AIQuotaApp/                       iOS 主 App / OAuth / 多账号
AIQuotaWidget/                    iOS WidgetKit Interactive Widget
Shared/                           iOS Provider / Keychain / App Intents / Alerts / Localizations
android/
  app/src/main/java/.../auth/     Android OAuth / PKCE / Device Flow
  app/src/main/java/.../core/     Account / Credential / Provider / Usage
  app/src/main/java/.../widget/   Glance Widget / config / refresh action
  app/src/main/java/.../work/     WorkManager / quota alerts
  app/src/main/res/values*        Android English / Simplified Chinese resources
.github/workflows/ipa.yml         iOS unsigned/re-sign/P12 signed IPA
.github/workflows/android.yml     Android debug/release APK
Scripts/                          iOS 构建/签名/结构验证脚本
```

## Next

- Provider fixture / contract tests
- Gemini / OpenRouter / Cursor 等 Provider
- iOS Widget 进一步支持单 Provider / 单账号配置
- Provider/API 健康诊断与错误分类
- Release automation / changelog
