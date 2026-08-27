# AIQuota Native v0.10.0

AI 服务额度监控：**原生 iOS + 原生 Android + 桌面小组件 + 多账号 + 本机凭据保存 + 后台刷新**。

目标是让手机自己完成日常额度查询与 Widget 更新；电脑最多只作为首次 credentials 导入的可选方式，不作为持续运行的中转设备。

## Provider

- Codex：ChatGPT OAuth / credentials 导入，多账号，动态额度窗口
- Claude：OAuth / credentials 导入，多账号，5h / 周
- Kimi：Device OAuth / credentials 导入，多账号，动态额度窗口
- DeepSeek：API Key，多账号，余额

iOS 端还保留 MiniMax、GLM / Z.ai、GitHub Copilot 等适配，后续逐步同步 Android。

## iOS

技术栈：SwiftUI + WidgetKit + App Intents + App Group + Keychain。

当前支持：

- Codex / Claude / Kimi OAuth
- DeepSeek API Key
- OAuth token 自动 refresh
- 多账号 UUID 隔离
- 账号重命名、启用/隐藏、排序
- 每个 Provider 自动标记推荐账号：额度型 Provider 按“最紧张窗口剩余最多”选择；余额型 Provider 按余额选择
- WidgetKit 桌面 Widget
- Widget 内 `↻` 原地刷新，不打开主 App
- Widget timeline 自动刷新
- stale cache：网络失败保留上次成功数据
- GitHub Actions 构建 unsigned / signed IPA

Codex 使用 browser OAuth + PKCE + iPhone 本机 localhost callback；日常刷新不依赖电脑或中转服务器。

## Android

技术栈：Kotlin + Jetpack Compose + Jetpack Glance + WorkManager + Android Keystore/EncryptedSharedPreferences。

v0.10.0 已形成可安装闭环：

- Codex browser OAuth + PKCE
- localhost callback；1455 不可用时尝试备用端口
- Codex 自动回调失败时支持粘贴完整 localhost callback URL
- Claude OAuth，授权后粘贴 `CODE#STATE`
- Kimi Device OAuth，浏览器确认 + App 自动轮询 token
- Codex / Claude / Kimi refresh token 自动续期
- Kimi device headers 持久化并用于 refresh / usage
- DeepSeek API Key 查询余额
- 多账号 Account UUID 隔离
- EncryptedSharedPreferences + Android Keystore 保存敏感凭据
- 本地 usage snapshot cache；失败时保留旧数据并标记 stale
- WorkManager 每 15 分钟后台刷新
- Jetpack Glance 桌面 Widget
- Widget 独立配置：全部账号 / 单 Provider / 单账号
- 每个 Widget 配置按 `appWidgetId` 独立保存
- Widget `↻` 不打开 App；总览刷新全部、Provider Widget 只刷新该 Provider、单账号 Widget 只刷新该账号
- 账号显示/隐藏、上下排序
- 每个 Provider 推荐账号
- 80% / 90% / 约 100% 已用额度分级通知，并按账号/窗口去重
- Android 13+ 请求通知权限
- GitHub Actions 自动构建 debug APK

### 已验证 Android 构建

GitHub Actions Android run `33064011400` 已完整通过：`assembleDebug` 成功，APK artifact 上传成功。

Artifact：`AIQuota-Android-debug`，其中包含 `app-debug.apk`。

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

所有账号的 access token / refresh token / API Key 独立保存；刷新一个账号不会覆盖同 Provider 的其它账号。

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

## 推荐账号规则

对于 Codex / Claude / Kimi，一个账号可能同时有 5h、周等多个窗口。AIQuota 使用：

```text
账号评分 = min(该账号所有额度窗口剩余百分比)
推荐账号 = 同 Provider 中评分最高的账号
```

因此不会出现“5h 剩很多，但周额度已经快用完却仍然推荐”的情况。

DeepSeek 等余额型 Provider 则按可用余额比较。

## 额度提醒

Android 当前默认分三级：

- 已用约 80%：剩余 ≤ 20%
- 已用约 90%：剩余 ≤ 10%
- 已用约 100%：剩余 ≤ 0.5%

同一账号、同一额度窗口、同一级别不会被 15 分钟后台任务反复通知；额度恢复到安全区后会重置提醒状态。

iOS 的同规则系统通知仍在后续同步计划中。

## 安全

- iOS：OAuth token / API Key 存共享 Keychain，按 Account UUID 隔离
- Android：OAuth token / API Key 存 EncryptedSharedPreferences，主密钥由 Android Keystore 管理
- 普通账号配置和 Widget snapshot 不保存 token
- 日志、Widget、错误提示不应输出完整 token、refresh token、Cookie 或 API Key

## 项目结构

```text
AIQuotaApp/                       iOS 主 App / OAuth / 多账号
AIQuotaWidget/                    iOS WidgetKit Interactive Widget
Shared/                           iOS Provider / Keychain / App Intents
android/
  app/src/main/java/.../auth/     Android OAuth / PKCE / Device Flow
  app/src/main/java/.../core/     Account / Credential / Provider / Usage / Alerts
  app/src/main/java/.../widget/   Glance Widget / config / refresh action
  app/src/main/java/.../work/     WorkManager 后台刷新
.github/workflows/ipa.yml         iOS IPA
.github/workflows/android.yml     Android APK
Scripts/                          iOS 构建/签名脚本
```

## 构建

iOS：`Actions → ipa → Run workflow`，支持 unsigned IPA 和 p12 + mobileprovision signed IPA，详见 `IPA.md` / `SIGNING.md`。

Android：`Actions → Android → Run workflow`，成功后下载 `AIQuota-Android-debug`，解压得到 `app-debug.apk`。

Android 当前工具链：API 37 / AGP 9.3 / Gradle 9.5 / Compose 2026.08 / Glance 1.2。

## 下一阶段

1. iOS 同步 80% / 90% / 100% 系统额度提醒
2. Android Widget 显示条数、紧凑/详细布局配置
3. 两端完整中英文本地化
4. Provider fixture / contract tests，降低上游 API 格式变化风险
5. Gemini / OpenRouter / Cursor / Copilot 等 Provider 扩展
6. Release APK / AAB 签名和版本发布流程
7. OAuth 登录状态诊断、凭据健康检查与一键重新认证

项目原则：**手机自己查询额度；电脑最多只作为首次 credentials 导入的可选方式，日常刷新不依赖 Mac、Windows、Linux 或中转服务器。**
