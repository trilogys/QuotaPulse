# IPA quick start — v0.10.0

AIQuota iOS 包保持标准 IPA 结构，并同时提供两种发行方式：

1. **unsigned / re-sign IPA**：给全能签、ESign、爱思助手或其它第三方签名工具重新签名。
2. **P12 + mobileprovision signed IPA**：GitHub Actions 或 macOS 构建时直接使用自己的证书和描述文件签名。

AIQuota 包含主 App 和 Widget Extension，因此签名工具必须正确处理两个 bundle。

## 1. Unsigned / re-sign IPA

1. 打开 **Actions → ipa → Run workflow**。
2. 选择 `build_type = unsigned`。
3. 如果你已经知道自己描述文件中的 Bundle ID / Widget Bundle ID / App Group，建议在 workflow 中填成对应值。
4. 下载 artifact：`AIQuota-iOS-resign`。

Artifact 包含：

- `AIQuota-resign.ipa` — 推荐直接交给第三方重签工具
- `AIQuota-resign.ipa.sha256`
- `AIQuota-unsigned.ipa` — 与 resign 版内容相同的通用命名
- `AIQuota-unsigned.ipa.sha256`
- `AIQuota-unsigned-signing-info.txt`

IPA 是真实 iphoneos 构建，标准结构：

```text
Payload/
└─ AIQuota.app
   └─ PlugIns/
      └─ AIQuotaWidget.appex
```

### 全能签 / ESign

原则上可用于 AIQuota，只要当前版本的签名工具能够：

- 重签 `AIQuota.app`
- 同时重签 `PlugIns/AIQuotaWidget.appex`
- 为主 App 和 Widget 使用匹配的 provisioning profile
- 保留/重建正确的 App Group entitlement
- 保留/重建兼容的 Keychain access group

如果只签主 App，App 本身可能可以安装，但 Widget 可能不显示、无法刷新，或无法读取主 App 保存的 OAuth/API Key。

### 爱思助手

AIQuota 使用标准 IPA 结构，因此可以作为爱思助手等桌面签名/安装工具的输入包。实际是否能保留 Widget，取决于所用签名方式是否会同时正确重签嵌入的 `.appex` 以及对应 entitlements。

如果签完后出现“App 能打开但没有小组件”，优先检查：

1. Widget `.appex` 是否被重新签名；
2. Widget provisioning profile 是否存在；
3. App 与 Widget 的 App Group 是否完全一致；
4. 两个 profile 是否允许对应 App Group；
5. 主 App / Widget bundle ID 是否与 profile 匹配。

> AIQuota 不依赖某个私有签名工具的特殊格式；它输出的是标准 IPA。只要签名工具能正确处理 App Extension，就可以工作。

## 2. P12 + mobileprovision signed IPA

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

## 3. One-command local signed IPA on macOS

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

## 4. Why two provisioning profiles?

AIQuota 不是只有一个 App：

```text
AIQuota.app
└─ PlugIns/
   └─ AIQuotaWidget.appex
```

Apple 把 Widget Extension 当成独立签名 bundle，因此 Widget 一般需要自己的 Bundle ID 和 provisioning profile。

这也是为什么某些“一键签名”工具看起来签名成功、App 也能打开，但桌面小组件没有出现。

## 5. Runtime credential sharing

AIQuota 的 OAuth token / API Key 存在共享 Keychain 中；App 和 Widget 通过 App Group / Keychain entitlement 协作。

unsigned IPA 无法预先知道最终 Apple application-identifier prefix，所以 AIQuota 只把 Keychain suffix 放进构建配置，最终前缀由实际签名环境决定。这样更适合后续使用自己的证书重签。

## Recommended path

如果主要是自己手机使用：

```text
已有 P12 + 主 App profile + Widget profile
        → GitHub Actions signed IPA
        → 直接安装
```

如果只拿到 P12/描述文件后习惯使用手机签名工具：

```text
Actions 下载 AIQuota-resign.ipa
        → 全能签 / ESign / 其它支持 Extension 的工具
        → 同时签 App + Widget
        → 安装
```

如果使用爱思助手：

```text
Actions 下载 AIQuota-resign.ipa
        → 爱思助手签名/安装
        → 安装后确认“添加小组件”列表中存在 AIQuota
```

若 App 能安装但 Widget 不存在，应先判断为 **Extension 签名/entitlement 问题**，而不是额度 Provider 或 OAuth 代码问题。
