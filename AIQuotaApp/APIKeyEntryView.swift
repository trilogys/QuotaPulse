import SwiftUI

struct APIKeyEntryView: View {
  let provider: ProviderID
  let isEditing: Bool
  let onSave: (String?, String, String?) async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var key = ""
  @State private var baseURL = ""
  @State private var saving = false

  init(
    provider: ProviderID,
    initialName: String = "",
    initialBaseURL: String = "",
    isEditing: Bool = false,
    onSave: @escaping (String?, String, String?) async -> Void
  ) {
    self.provider = provider
    self.isEditing = isEditing
    self.onSave = onSave
    _name = State(initialValue: initialName)
    _baseURL = State(initialValue: initialBaseURL)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("显示名称") {
          TextField("账号名称（可选）", text: $name)
        }
        Section("\(credentialTitle) 凭据") {
          SecureField(keyPlaceholder, text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if supportsBaseURL {
            TextField("Base URL（可选）", text: $baseURL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }
        Section {
          Text(LocalizedStringKey(helpText))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("\(isEditing ? "更新" : "添加") \(credentialTitle)")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            saving = true
            Task {
              await onSave(
                name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
                key.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL.isEmpty ? nil : baseURL
              )
              saving = false
              dismiss()
            }
          }
          .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
        }
      }
    }
  }

  private var keyPlaceholder: String {
    switch provider {
    case .copilot: "GitHub Token"
    case .glm: "GLM / Z.ai Coding Key"
    default: "API Key"
    }
  }

  private var credentialTitle: String {
    provider == .codex ? "OpenAI / GPT" : provider.title
  }

  private var supportsBaseURL: Bool {
    [.codex, .claude, .kimi, .minimax, .glm].contains(provider)
  }

  private var helpText: String {
    switch provider {
    case .codex: "OpenAI API Key 使用 Platform API；具备组织 Usage 权限时可显示每日 Token 与模型汇总。"
    case .claude: "Claude API Key 用于验证 Anthropic API 连接；官方普通 Key 不返回订阅额度。"
    case .kimi: "Kimi API Key 使用兼容 API 验证模型访问；Coding Plan OAuth 额度仍需 OAuth 登录。"
    case .deepseek: "DeepSeek 显示官方 API 余额，不伪装成 5h/周额度。"
    case .minimax: "用于查询 MiniMax Coding Plan 剩余额度。"
    case .glm: "用于查询 Z.ai / 智谱 Coding Plan 额度。"
    case .copilot: "Copilot 当前适配内部 quota 快照接口，建议使用最小权限 Token。"
    default: "凭据只写入共享 Keychain，Widget Extension 可读取，但不会写入普通文件。"
    }
  }
}
