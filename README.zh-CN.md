# QuotaPulse

[English](README.md)

AI 服务额度监控：**原生 iOS + 原生 Android + 桌面小组件 + 多账号 + 本机凭据保存 + 后台刷新**。

目标是让手机自己完成日常额度查询与 Widget 更新；电脑最多只作为首次 credentials 导入或签名材料准备的可选方式，不作为持续运行的中转设备。

## Provider

- Codex / OpenAI：ChatGPT OAuth 或 API Key，多账号，动态额度窗口、累计与每日 Token
- Claude：OAuth 或 API Key，多账号，OAuth 账号显示 5h / 周额度
- Kimi：Device OAuth 或 API Key，多账号；Key 账号显示余额和可用模型，OAuth 账号显示动态额度窗口
- DeepSeek：API Key，多账号，官方余额和可用模型

iOS 端还保留 MiniMax、GLM / Z.ai、GitHub Copilot 等适配，后续逐步同步 Android。

## Visual direction

QuotaPulse 不直接复制某一个项目的 UI，而是组合三个方向：

- **claude-widget-ios**：iOS 原生 SwiftUI / WidgetKit 的简洁信息密度与系统风格
- **CodexBar**：额度窗口层级、session/weekly/reset 信息架构、stale/error 状态
- **ScriptableTokenWidgets**：明亮主题的白色圆角卡片、橙红趋势、圆环与紧凑统计层级
- **QuotaPulse 自身**：多账号总览、推荐账号、单账号刷新、Provider/账号级 Widget 配置

最终风格原则：**原生、紧凑、额度优先、刷新状态清晰，不做重装饰 Dashboard。**

## iOS

技术栈：SwiftUI + WidgetKit + App Intents + App Group + Keychain。

系统要求：**iOS 16.0 以上**。iOS 16 使用静态 Widget，点按后进入 App 刷新；iOS 17 以上自动启用可配置 Widget 和小组件内原地刷新。

当前支持：

- Codex / Claude / Kimi 支持 OAuth 与 API Key 两种账号模式
- DeepSeek API Key
- 导入 QuotaPulse 或 Sub2API 账号 JSON；兼容 OpenAI OAuth、Anthropic OAuth / Setup Token 和单一账号代理
- 可从 iOS“文件”共享 JSON 到 QuotaPulse，并自动合并导入
- JSON 导出文件名包含本地时间戳，例如 `QuotaPulse-backup-20260829-103512.json`
- 多个命名 HTTP(S) / SOCKS5 代理：链接导入、Codex / Claude 适用范围、单一激活项、账号密码与测速
- 已保存代理可独立测速并显示各服务延迟
- 代理只通过单条 HTTP(S) / SOCKS5 链接配置，不分散填写主机、端口和凭据
- OAuth 与 API Key 账号创建时均可自定义显示名称
- OAuth token 自动 refresh
- 多账号 UUID 隔离
- 账号重命名、启用/隐藏、排序
- 每个 Provider 自动标记推荐账号
- 凭据健康状态：正常 / 即将续期 / 可续期 / 需重登 / 缓存
- Codex / Claude / Kimi 原账号一键重新认证，保持 UUID 与 Widget 绑定不变
- 额度 Reset 倒计时
- Codex 5h / 周额度重置安排、可用重置次数查询和用户确认后手动重置
- Codex OAuth 累计 Token、单日峰值、连续使用天数、官方每日 Token 走势图与手动按模型明细查询
- Codex 官方 12 个月 Token 热力图，支持每日 / 每周 / 累计切换和日期点选
- 最近 31 天本机历史：今天 / 近 7 天 / 近 30 天
- 圆环 / 柱状 / 折线 / 热力图切换，显示真实峰值使用率和日期
- “全部”页可选择按 Provider 分开展示或叠加汇总
- 总览前台定时刷新：关闭 / 30 秒 / 1 分钟 / 5 分钟 / 10 分钟
- 可关闭的 iOS 后台刷新，显示上次成功刷新时间
- 后台刷新支持 10–1440 分钟自定义间隔，首页显示上次刷新时间
- 设置内支持检查 GitHub Release 更新并打开发布页
- 三套可切换 App 图标，默认使用经典绿环
- WidgetKit Small / Medium / Large 自适应信息密度
- Widget 内 `↻` 原地刷新，不打开主 App
- Widget timeline 自动刷新
- stale cache：网络失败保留上次成功数据
- 80% / 90% / 约 100% 已用额度分级通知，按账号/额度窗口去重
- 简体中文 / English 本地化；可使用 iOS 每 App 语言设置切换，Widget 同步语言
- GitHub Actions 构建 unsigned / re-sign / P12 signed IPA

Codex 使用 browser OAuth + PKCE + iPhone 本机 localhost callback；日常刷新不依赖电脑或中转服务器。

Kimi Key 的公开接口可返回余额和模型列表，但不提供历史请求的逐模型 Token 用量；逐模型历史需要调用日志或网关日志，QuotaPulse 不会伪造该数据。

### iOS IPA / 重签

`Actions → ipa` 支持：

```text
QuotaPulse-iOS-resign
├─ QuotaPulse-resign.ipa
├─ QuotaPulse-unsigned.ipa
├─ QuotaPulse.ipa
├─ QuotaPulse-app-only-unsigned.ipa
├─ SHA256
└─ signing-info

QuotaPulse-signed-release-testing / debugging
└─ QuotaPulse-signed.ipa
```

只有 P12/一套描述文件，或使用全能签、爱思助手等兼容性不明确的工具时，优先使用 `QuotaPulse.ipa`。它不包含 Widget Extension，不要求 App Group，只需正确签名主 App。

`QuotaPulse-resign.ipa` 是包含 Widget 的标准 IPA。包内真实包含：

```text
Payload/QuotaPulse.app/PlugIns/QuotaPulseWidget.appex
```

因此重签工具需要同时正确签名主 App 与 Widget Extension，并处理匹配的 App Group / Keychain entitlements。GitHub Actions 会验证 unsigned/re-sign IPA 的结构、Widget 嵌入和 artifact 输出。

> `.p12` 只包含签名证书和私钥，不能单独生成可安装 IPA；仍需与 Bundle ID 匹配的 provisioning profile。全能签等工具若能正常签名，通常是工具中还导入或生成了对应 profile。

P12 模式需要：`.p12` + 密码、主 App `.mobileprovision`、Widget `.mobileprovision`。GitHub Actions 会解析 Team / Bundle ID / App Group、验证 profile 兼容性并生成签名 IPA。详见 `IPA.md` / `SIGNING.md`。

## Android

技术栈：Kotlin + Jetpack Compose + Jetpack Glance + WorkManager + Android Keystore/EncryptedSharedPreferences。

系统要求：Android 8.0（API 26）以上。`Actions → Android` 的 `QuotaPulse-Android-debug/QuotaPulse.apk` 可直接侧载；配置固定 release keystore 后生成的 release APK 才能在后续版本中稳定覆盖安装。两个 artifact 都同时提供 `.sha256` 校验文件。

当前支持：

- Codex browser OAuth + PKCE
- localhost callback；自动回调失败时可粘贴完整 callback URL
- Claude OAuth，授权后粘贴 `CODE#STATE`
- Kimi Device OAuth，浏览器确认 + App 自动轮询 token
- Codex / Claude / Kimi refresh token 自动续期
- Kimi device headers 持久化
- DeepSeek API Key 查询余额
- 多账号 UUID 隔离
- 与 iOS 对齐的明亮、霓虹夜、石墨、极光四套主题，默认明亮
- Provider 筛选、总览圆环、圆角额度卡片与平台独立强调色
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

然后运行 `Actions → Android`，额外生成 `QuotaPulse-Android-release/QuotaPulse-release.apk`。

## 安全

- iOS：OAuth token / API Key 存共享 Keychain，按 Account UUID 隔离
- Android：OAuth token / API Key 存 EncryptedSharedPreferences，主密钥由 Android Keystore 管理
- 普通账号配置和 Widget snapshot 不保存 token
- Android release keystore/password 不进入 Git 仓库
- iOS P12/profile/password 只通过 GitHub Actions Secrets 注入
- 日志、Widget、错误提示不应输出完整 token、refresh token、Cookie 或 API Key

## 项目结构

```text
QuotaPulseApp/                       iOS 主 App / OAuth / 多账号
QuotaPulseWidget/                    iOS WidgetKit Interactive Widget
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
