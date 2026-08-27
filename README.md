# AIQuota Native v0.9.1

AI 服务额度监控：**原生 iOS + 原生 Android + 桌面小组件 + 多账号 + 本机凭据保存 + 后台刷新**。

## Provider

- Codex：ChatGPT OAuth / credentials 导入，多账号，动态额度窗口
- Claude：OAuth / credentials 导入，多账号，5h / 周
- Kimi：Device OAuth / credentials 导入，多账号，动态额度窗口
- DeepSeek：API Key，多账号，余额

iOS 端还保留 MiniMax、GLM / Z.ai、GitHub Copilot 等适配，后续逐步同步 Android。

## iOS

SwiftUI + WidgetKit + App Intents + App Group + Keychain。

已支持多账号、Codex/Claude/Kimi OAuth、DeepSeek API Key、Token refresh、桌面 Widget、Widget 内 `↻` 原地刷新、timeline 自动刷新、stale cache，以及 GitHub Actions 构建 unsigned/signed IPA。

Codex 使用 browser OAuth + PKCE + iPhone 本机 localhost callback；日常刷新不依赖电脑或中转服务器。

## Android

Kotlin + Jetpack Compose + Jetpack Glance + WorkManager + Android Keystore/EncryptedSharedPreferences。

v0.9.1 已加入：

- Codex browser OAuth + PKCE
- iPhone 同逻辑的 `localhost:1455` callback；1455 占用时自动尝试备用端口
- Codex localhost 自动回调失败时，可粘贴完整 callback URL 手动完成
- Claude OAuth，授权后粘贴 `CODE#STATE`
- Kimi Device OAuth，浏览器授权 + App 轮询 token
- Codex / Claude / Kimi refresh token 自动续期
- Kimi device headers 持久化，refresh 与 usage 请求继续复用
- DeepSeek API Key 余额查询
- 多账号 Account UUID 隔离
- EncryptedSharedPreferences + Android Keystore 保存敏感凭据
- 本地 usage snapshot cache；失败时保留旧值并标记 stale
- WorkManager 每 15 分钟后台刷新
- Jetpack Glance 桌面 Widget
- Widget 顶部 `↻` 直接触发后台刷新，不打开主 App
- 主 App 单账号/全部刷新、删除、OAuth 登录、凭据导入
- GitHub Actions 自动构建 debug APK

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

所有账号的 access token / refresh token / API Key 独立保存，刷新某个账号不会覆盖同 Provider 的其它账号。

## 后台刷新

### iOS

WidgetKit timeline 请求自动刷新；设置可选 10 / 15 / 30 / 60 / 120 分钟的最早请求时间。实际调度由 iOS 决定。Interactive Widget `↻` 可以立即执行刷新且不打开 App。

### Android

WorkManager 以 15 分钟周期安排网络刷新；Widget `↻` 会提交一次 OneTimeWorkRequest，完成后调用 Glance `updateAll()` 更新桌面小组件。

## 安全

- iOS：OAuth token / API Key 存共享 Keychain，按 Account UUID 隔离。
- Android：OAuth token / API Key 存 EncryptedSharedPreferences，主密钥由 Android Keystore 管理。
- 普通账号配置和 Widget snapshot 不保存 token。
- 日志、Widget、错误提示不得输出完整 token、refresh token、Cookie 或 API Key。

## 项目结构

```text
AIQuotaApp/                       iOS 主 App / OAuth / 多账号
AIQuotaWidget/                    iOS WidgetKit Interactive Widget
Shared/                           iOS Provider / Keychain / App Intents
android/
  app/src/main/java/.../auth/     Android OAuth / PKCE / Device Flow
  app/src/main/java/.../core/     Account / Credential / Provider / Usage
  app/src/main/java/.../widget/   Jetpack Glance Widget / refresh action
  app/src/main/java/.../work/     WorkManager 后台刷新
.github/workflows/ipa.yml         iOS IPA
.github/workflows/android.yml     Android APK
Scripts/                          iOS 构建/签名脚本
```

## 构建

iOS：`Actions → ipa → Run workflow`，支持 unsigned IPA 和 p12 + mobileprovision signed IPA，详见 `IPA.md` / `SIGNING.md`。

Android：`Actions → Android → Run workflow`，成功后下载 `AIQuota-Android-debug/app-debug.apk`。

Android 当前工具链：API 37 / AGP 9.3 / Gradle 9.5 / Compose 2026.08 / Glance 1.2。

## 下一阶段

1. Android Widget 配置：选择 Provider / 账号 / 显示条数
2. Android 单账号 Widget 刷新按钮
3. 两端统一账号排序、启用/隐藏与推荐账号
4. 80% / 90% / 100% 阈值提醒
5. Gemini / OpenRouter / Cursor / Copilot 等 Provider 扩展
6. 中英文完整本地化
7. OAuth 与 Provider fixture/contract tests

项目原则：**手机自己查询额度；电脑最多只作为首次 credentials 导入的可选方式，日常刷新不依赖 Mac、Windows、Linux 或中转服务器。**
