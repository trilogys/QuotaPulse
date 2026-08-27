import SwiftUI

struct APIKeyEntryView: View {
  let provider: ProviderID
  let onSave: (String, String?) async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var key = ""
  @State private var baseURL = ""
  @State private var saving = false

  var body: some View {
    NavigationStack {
      Form {
        Section("\(provider.title) 凭据") {
          SecureField(keyPlaceholder, text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if provider == .minimax || provider == .glm {
            TextField("Base URL（可选）", text: $baseURL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }
        Section {
          Text(helpText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("添加 \(provider.title)")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            saving = true
            Task {
              await onSave(
                key.trimmingCharacters(in: .whitespacesAndNewlines), baseURL.isEmpty ? nil : baseURL
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

  private var helpText: String {
    switch provider {
    case .deepseek: "DeepSeek 显示官方 API 余额，不伪装成 5h/周额度。"
    case .minimax: "用于查询 MiniMax Coding Plan 剩余额度。"
    case .glm: "用于查询 Z.ai / 智谱 Coding Plan 额度。"
    case .copilot: "Copilot 当前适配内部 quota 快照接口，建议使用最小权限 Token。"
    default: "凭据只写入共享 Keychain，Widget Extension 可读取，但不会写入普通文件。"
    }
  }
}
