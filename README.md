# AI Quota Native v0.8.0

原生 iOS + WidgetKit AI 额度小组件。核心目标是：**桌面直接点 ↻ 原地刷新，不打开 App；支持多个账号，互不覆盖。**

## 支持的平台

- Codex：ChatGPT OAuth，多账号；动态识别实际返回的时间窗口
- Claude：OAuth，多账号；5h / 周
- Kimi：Device OAuth，多账号；动态识别实际返回窗口
- DeepSeek：API 余额
- MiniMax：Coding Plan
- GLM / Z.ai：Coding Plan
- GitHub Copilot：月度 quota 快照（实验适配）

## 真正的桌面刷新

项目使用 iOS 17+ WidgetKit + App Intents：

- 顶部 `↻`：刷新当前 Widget 中的全部账号
- 中/大号每个账号右侧 `↻`：只刷新这个账号
- App Intent 设置 `openAppWhenRun = false`
- 刷新完成后 WidgetKit 重载 timeline
- 点普通区域才进入主 App

因此点击刷新按钮时会留在桌面。

## 多账号隔离

每个账号都有独立 UUID：

- 账号信息：App Group UserDefaults
- OAuth / API 凭据：共享 Keychain，按 Account UUID 保存
- 使用量缓存：App Group，按 Account UUID 保存
- Token 刷新只写回对应账号
- 删除 A 不影响 B
- Widget 可以只刷新某个账号

## v0.8.0：直接产出 IPA

### A. unsigned IPA

用于 ESign / 轻松签 / 其它支持 App Extension 的重签工具。

```text
Actions
→ ipa
→ Run workflow
→ build_type = unsigned
→ 下载 AIQuota-unsigned
```

得到真正的设备构建：

```text
AIQuota-unsigned.ipa
└─ Payload/AIQuota.app
   └─ PlugIns/AIQuotaWidget.appex
```

### B. 使用自己的 p12 + mobileprovision 直接生成 signed IPA

只需要四个 GitHub Secrets：

```text
AIQUOTA_P12_BASE64
AIQUOTA_P12_PASSWORD
AIQUOTA_APP_PROFILE_BASE64
AIQUOTA_WIDGET_PROFILE_BASE64
```

然后：

```text
Actions
→ ipa
→ Run workflow
→ build_type = signed
→ distribution = release-testing / debugging
→ 下载 AIQuota-signed
```

**不用手填 Team ID / Bundle ID / Widget ID / App Group / Keychain Group。** 工作流会从两个 provisioning profile 自动读取和校验。

详细步骤见 [`IPA.md`](IPA.md) 和 [`SIGNING.md`](SIGNING.md)。

## 本地 Mac 一条命令生成 signed IPA

```bash
brew install xcodegen
export P12_PASSWORD='你的p12密码'

./Scripts/build_signed_ipa.sh \
  certificate.p12 \
  App.mobileprovision \
  Widget.mobileprovision \
  release-testing
```

输出：

```text
build/export/AIQuota-signed.ipa
```

## unsigned IPA 重签兼容

v0.8.0 只在 Info.plist 保存共享 Keychain **suffix**。App / Widget 运行时使用公开 Keychain API 读取当前签名实际分配的 access group，并据此解析 Apple prefix，再组成共享 Keychain Group。这样预编译 unsigned IPA 不会绑定某个开发者 Team Prefix。

## 构建要求

- iOS 17+
- macOS + Xcode（本地构建时）
- XcodeGen
- 原地刷新需要真正的 Widget Extension，因此不能退回单 Scriptable JS

## 自动刷新

设置页可选择 10 / 15 / 30 / 60 / 120 分钟。这个值是 WidgetKit timeline 的最早刷新请求时间，实际后台执行仍由 iOS 调度。手动 `↻` 使用 Interactive Widget App Intent，不需要等待 timeline。

## 代理

App、OAuth 和 Widget 网络请求使用 iOS 当前系统网络。系统 VPN / TUN / 代理可直接接管，不需要在代码里单独填代理。

## Codex 登录

Codex 使用 browser OAuth + PKCE + 本机 localhost callback：

1. App 在 iPhone 本机启动短时 `127.0.0.1` callback listener
2. Safari 登录 ChatGPT
3. OAuth 回调到本机
4. App 校验 code/state
5. 本机交换 token
6. token 写入共享 Keychain

不使用 Cloudflare Worker，不把授权码/token发给第三方服务器。

## 项目结构

```text
AIQuotaApp/                 主 App / OAuth / 多账号
AIQuotaWidget/              WidgetKit Interactive Widget
Shared/                     Provider / Keychain / App Intents
Scripts/build_unsigned_ipa.sh
Scripts/build_signed_ipa.sh
Scripts/derive_signing_config.sh
Scripts/verify_ipa_structure.sh
.github/workflows/ipa.yml   unsigned/signed 一键产出
Config.xcconfig
project.yml
IPA.md
SIGNING.md
```
