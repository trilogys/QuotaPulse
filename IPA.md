# IPA quick start

QuotaPulse 支持 iOS 16.0 以上，并提供三种发行方式：

1. **App-only unsigned / re-sign IPA**：只有一套签名材料或使用全能签、爱思助手时的首选，不含 Widget。
2. **Full unsigned / re-sign IPA**：包含 Widget，重签工具必须能处理 App Extension 和两份 profile。
3. **P12 + mobileprovision signed IPA**：GitHub Actions 或 macOS 直接签名完整 Widget 版。

> P12 只是证书与私钥。任何 iOS 安装方式还需要与 Bundle ID、设备/分发方式匹配的 provisioning profile；P12 不能代替 profile。

## 1. 全能签 / 爱思助手推荐路径

1. 打开 **Actions → ipa → Run workflow**。
2. 选择 `build_type = unsigned`。
3. 如果你已经知道自己描述文件中的 Bundle ID / Widget Bundle ID / App Group，建议在 workflow 中填成对应值。
4. 下载 artifact：`AIQuota-iOS-resign`。

Artifact 包含：

- `AIQuota-resign.ipa` — 包含 Widget，仅用于支持 Extension 的重签工具
- `AIQuota-resign.ipa.sha256`
- `AIQuota-unsigned.ipa` — 与 resign 版内容相同的通用命名
- `AIQuota-unsigned.ipa.sha256`
- `AIQuota-unsigned-signing-info.txt`
- `QuotaPulse.ipa` — **单 App 兼容版，优先用于全能签/爱思助手**
- `AIQuota-app-only-unsigned.ipa`
- `AIQuota-app-only-signing-info.txt`

选择规则：

```text
只有 P12 + 一份主 App profile
  → QuotaPulse.ipa
  → 在签名工具中导入 P12、密码和 profile
  → 签名后安装

有主 App + Widget 两份 profile，且工具支持 Extension
  → AIQuota-resign.ipa
  → 同时签名 AIQuota.app 与 AIQuotaWidget.appex
  → 安装后检查小组件列表
```

App-only 包保留账号、OAuth、额度查询、通知、导入导出和 App 内刷新，只移除桌面 Widget。它不需要 App Group 或共享 Keychain entitlement，因此对单 profile 签名最稳妥。

## 2. Full unsigned / re-sign IPA

IPA 是真实 iphoneos 构建，标准结构：

```text
Payload/
└─ AIQuota.app
   └─ PlugIns/
      └─ AIQuotaWidget.appex
```

### 全能签 / ESign

原则上可用于 QuotaPulse，只要当前版本的签名工具能够：

- 重签 `AIQuota.app`
- 同时重签 `PlugIns/AIQuotaWidget.appex`
- 为主 App 和 Widget 使用匹配的 provisioning profile
- 保留/重建正确的 App Group entitlement
- 保留/重建兼容的 Keychain access group

如果只签主 App，App 本身可能可以安装，但 Widget 可能不显示、无法刷新，或无法读取主 App 保存的 OAuth/API Key。

### 爱思助手

QuotaPulse 使用标准 IPA 结构，因此可以作为爱思助手等桌面签名/安装工具的输入包。实际是否能保留 Widget，取决于所用签名方式是否会同时正确重签嵌入的 `.appex` 以及对应 entitlements。

如果签完后出现“App 能打开但没有小组件”，优先检查：

1. Widget `.appex` 是否被重新签名；
2. Widget provisioning profile 是否存在；
3. App 与 Widget 的 App Group 是否完全一致；
4. 两个 profile 是否允许对应 App Group；
5. 主 App / Widget bundle ID 是否与 profile 匹配。

> QuotaPulse 不依赖某个私有签名工具的特殊格式；它输出的是标准 IPA。若工具不能处理 Extension，请改用 `QuotaPulse.ipa`。

## 3. P12 + mobileprovision signed IPA

这是保留 Widget 功能最稳妥的方式。

需要两份描述文件：

- 主 App profile
- Widget Extension profile

并且两份 profile 必须属于同一个 Team，允许同一个 App Group，并与各自 Bundle ID 匹配。

GitHub Actions Secrets：

- `AIQUOTA_P12_BASE64`
- `AIQUOTA_P12_PASSWORD`
- `AIQUOTA_APP_PROFILE_BASE64`
- `AIQUOTA_WIDGET_PROFILE_BASE64`

不需要手工填写 Team ID / Bundle ID / App Group；workflow 会从 provisioning profiles 中推导并验证。

然后：

1. **Actions → ipa → Run workflow**
2. `build_type = signed`
3. `release-testing`：适合 Ad Hoc / 注册设备分发
4. `debugging`：适合 Development profile
5. 下载 `AIQuota-signed-...`

签名 workflow 会：

```text
P12
 + App.mobileprovision
 + Widget.mobileprovision
        ↓
临时 CI Keychain
        ↓
自动解析 Team / Bundle ID / App Group
        ↓
验证两个 profiles
        ↓
构建主 App + Widget
        ↓
分别签名
        ↓
验证 entitlements
        ↓
AIQuota-signed.ipa
```

## 4. One-command local signed IPA on macOS

```bash
brew install xcodegen
export P12_PASSWORD='your-p12-password'

./Scripts/build_signed_ipa.sh \
  certificate.p12 \
  App.mobileprovision \
  Widget.mobileprovision \
  release-testing
```

输出：

```text
build/export/AIQuota-signed.ipa
build/export/AIQuota-signed.ipa.sha256
```

## 5. Why two provisioning profiles?

QuotaPulse 不是只有一个 App：

```text
AIQuota.app
└─ PlugIns/
   └─ AIQuotaWidget.appex
```

Apple 把 Widget Extension 当成独立签名 bundle，因此 Widget 一般需要自己的 Bundle ID 和 provisioning profile。

这也是为什么某些“一键签名”工具看起来签名成功、App 也能打开，但桌面小组件没有出现。

## 6. Runtime credential sharing

QuotaPulse 的 OAuth token / API Key 存在共享 Keychain 中；App 和 Widget 通过 App Group / Keychain entitlement 协作。

unsigned IPA 无法预先知道最终 Apple application-identifier prefix，所以 QuotaPulse 只把 Keychain suffix 放进构建配置，最终前缀由实际签名环境决定。这样更适合后续使用自己的证书重签。

## Recommended path

如果主要是自己手机使用：

```text
只有一份主 App profile / 不需要小组件
        → QuotaPulse.ipa
        → 全能签或爱思助手导入 P12 + profile 后签名安装

已有 P12 + 主 App profile + Widget profile
        → GitHub Actions signed IPA
        → 直接安装
```

如果只有 P12 + 一份主 App profile，并习惯使用手机签名工具：

```text
Actions 下载 QuotaPulse.ipa
        → 全能签 / ESign
        → 签名主 App
        → 安装
```

如果使用爱思助手：

```text
Actions 下载 QuotaPulse.ipa
        → 爱思助手签名/安装
        → 安装并在 App 内刷新
```

若 App 能安装但 Widget 不存在，应先判断为 **Extension 签名/entitlement 问题**，而不是额度 Provider 或 OAuth 代码问题。
