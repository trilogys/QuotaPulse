# AIQuota Native v0.9.0

AI 服务额度监控：**原生 iOS + 原生 Android + 桌面小组件 + 多账号 + 本机凭据保存 + 后台刷新**。

当前仓库由原 iOS-only 版本升级为双端工程。iOS 保留已经工作的 WidgetKit / App Intents / OAuth / Keychain 实现；Android 新增 Kotlin + Compose + Glance + WorkManager 实现。

## Provider

核心目标 Provider：

- Codex：ChatGPT OAuth / 导入已有 credentials，多账号；动态识别实际返回的额度窗口
- Claude：OAuth / 导入已有 credentials，多账号；5h / 周
- Kimi：OAuth / 导入已有 credentials，多账号；动态识别实际返回窗口
- DeepSeek：API Key，多账号；余额

现有 iOS 端还保留 MiniMax、GLM / Z.ai、GitHub Copilot 等适配，后续会逐步同步到 Android。

## iOS

技术栈：SwiftUI + WidgetKit + App Intents + App Group + Keychain。

已支持：

- 多账号独立 UUID
- Codex / Claude / Kimi OAuth
- DeepSeek API Key
- Token refresh
- 桌面 Widget
- Widget 内 `↻` 原地刷新，不打开主 App
- 自动 timeline 刷新
- stale cache：网络失败时保留上次成功额度
- GitHub Actions 构建 unsigned / signed IPA

Codex 使用 browser OAuth + PKCE + iPhone 本机 localhost callback，不需要后续依赖电脑或服务器中转。

## Android

技术栈：Kotlin + Jetpack Compose + Jetpack Glance + WorkManager + Android Keystore/EncryptedSharedPreferences。

v0.9.0 第一阶段已经加入：

- 原生 Android App 工程：`android/`
- Codex / Claude / Kimi / DeepSeek usage Provider
- Codex / Claude / Kimi refresh token 自动续期
- DeepSeek API Key 查询余额
- 多账号 Account UUID 隔离
- 加密凭据存储
- 本地额度 snapshot cache
- 网络失败保留旧 snapshot 并标记 stale
- 15 分钟 WorkManager 后台刷新
- Jetpack Glance 桌面 Widget
- 主 App 添加账号、删除账号、单账号/全部刷新
- GitHub Actions 自动构建 debug APK

当前 Android 的登录入口先支持 **导入已有 access/refresh token 或 API Key**。下一阶段会把 iOS 已有的 Codex/Claude/Kimi OAuth 登录流程移植为 Android 浏览器 OAuth / localhost callback / callback URL 粘贴 fallback。

## 多账号模型

每个账号都有独立 UUID：

```text
Provider
  ├─ Account A
  │    ├─ Credential
  │    └─ Usage Snapshot
  ├─ Account B
  │    ├─ Credential
  │    └─ Usage Snapshot
  └─ Account C
```

Token 刷新只更新当前 Account UUID，不会覆盖同 Provider 的其它账号。

## 后台刷新

### iOS

- WidgetKit timeline 请求后台刷新
- 用户可以设置 10 / 15 / 30 / 60 / 120 分钟的最早刷新请求
- 最终后台调度时间由 iOS 决定
- Interactive Widget `↻` 可以立即执行刷新且 `openAppWhenRun = false`

### Android

- WorkManager 每 15 分钟安排一次网络刷新
- 只在网络可用时执行
- 刷新完成调用 Glance `updateAll()` 更新桌面 Widget
- 打开 App 也可以手动刷新全部或单账号

## 安全

### iOS

OAuth token / API Key 存共享 Keychain，按 Account UUID 隔离。

### Android

OAuth token / API Key 存 EncryptedSharedPreferences，主密钥由 Android Keystore 管理。账号名称和使用量缓存不保存 token。

任何日志和 Widget 都不应该输出完整 token、refresh token、Cookie 或 API Key。

## 项目结构

```text
AIQuotaApp/                       iOS 主 App / OAuth / 多账号
AIQuotaWidget/                    iOS WidgetKit Interactive Widget
Shared/                           iOS Provider / Keychain / App Intents
android/                          Android 原生工程
  app/src/main/java/.../core/     Android Account / Credential / Usage
  app/src/main/java/.../widget/   Jetpack Glance Widget
  app/src/main/java/.../work/     WorkManager 后台刷新
.github/workflows/ipa.yml         iOS IPA
.github/workflows/android.yml     Android APK
Scripts/                          iOS 构建/签名脚本
Config.xcconfig
project.yml
IPA.md
SIGNING.md
```

## 构建 iOS IPA

GitHub Actions：

```text
Actions → ipa → Run workflow
```

支持 unsigned IPA 和使用自己的 p12 + mobileprovision 生成 signed IPA。详细见 [`IPA.md`](IPA.md) 与 [`SIGNING.md`](SIGNING.md)。

## 构建 Android APK

GitHub Actions：

```text
Actions → Android → Run workflow
```

成功后下载 artifact：

```text
AIQuota-Android-debug
└─ app-debug.apk
```

Android 当前使用 API 37 / AGP 9.1 / Gradle 9.3.1 / Compose 2026.08 / Glance 1.2。

## 下一阶段

优先顺序：

1. Android Codex OAuth + PKCE + localhost/manual callback fallback
2. Android Claude OAuth
3. Android Kimi Device/OAuth
4. Android Widget 手动刷新按钮与 Widget 配置
5. 两端统一账号排序、隐藏、推荐账号与额度阈值提醒
6. Gemini / OpenRouter / Cursor / Copilot 等 Provider 扩展
7. 中英文完整本地化

项目原则：**手机自己查询额度，电脑最多只作为首次导入凭据的可选方式；日常刷新不依赖 Mac、Windows、Linux 或中转服务器。**
