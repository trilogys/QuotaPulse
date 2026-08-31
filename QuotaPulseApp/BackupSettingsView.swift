import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum SensitiveExportKind: String, Identifiable, Equatable {
  case fullBackup
  case scriptable

  var id: String { rawValue }
  var title: String {
    switch self {
    case .fullBackup: "完整备份包含敏感凭据"
    case .scriptable: "导出高风险 Scriptable 配置"
    }
  }
  var message: String {
    switch self {
    case .fullBackup:
      "任何拿到此文件的人都可能获得其中账号的 API Key、Access Token 或 Refresh Token。请勿发送到群聊、公开网盘或 GitHub。"
    case .scriptable:
      "这是第三方兼容方案。导出的明文 JSON 会将 API Key、Access Token 和 Refresh Token 交给 Scriptable，凭据将离开 QuotaPulse Keychain。QuotaPulse 无法控制 Scriptable 的存储、同步、脚本修改或联网行为。继续导出表示你已理解并自行承担凭据泄露、账号异常及相关损失风险。导入后请立即删除 JSON 和“最近删除”中的副本。"
    }
  }
}

struct BackupSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var importing = false
  @State private var importInProgress = false
  @State private var importFeedback: ImportFeedback?
  @State private var importStatusText: String?
  @State private var importStatusIsError = false
  @State private var replaceOnImport = false
  @State private var exportDocument: PortableConfigDocument?
  @State private var exportFilename = "QuotaPulse-backup"
  @State private var exportContentType: UTType = .json
  @State private var exporting = false
  @State private var pendingSensitiveExport: SensitiveExportKind?

  var body: some View {
    Form {
      Section {
        LabeledContent("导入与导出格式", value: "JSON")
      }
      Section("导入") {
        Toggle("导入时替换现有账号", isOn: $replaceOnImport)
        Button {
          importStatusText = nil
          importing = true
        } label: {
          HStack {
            Label(
              importInProgress ? "正在导入" : "导入 QuotaPulse / Sub2API JSON",
              systemImage: "square.and.arrow.down"
            )
            Spacer()
            if importInProgress { ProgressView() }
          }
        }
        .disabled(importInProgress)
        Text(replaceOnImport ? "会先移除现有账号和对应凭据，再导入文件。" : "默认合并导入；相同账号会更新，不会重复创建。")
          .font(.footnote).foregroundStyle(.secondary)
        Text("Sub2API 支持 OpenAI OAuth、Anthropic OAuth / Setup Token；单一账号代理会新增为命名代理并激活。")
          .font(.footnote).foregroundStyle(.secondary)
        if let importStatusText {
          Label(
            importStatusText,
            systemImage: importStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
          )
          .font(.footnote)
          .foregroundStyle(importStatusIsError ? Color.red : Color.green)
        }
      }
      Section("导出") {
        Button { prepareExport(includeCredentials: false) } label: { Label("导出配置（不含凭据）", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { pendingSensitiveExport = .fullBackup } label: { Label("完整备份（含 Token / API Key）", systemImage: "key.horizontal") }
        Text("不含凭据的配置适合普通备份和分享。完整备份可以在 iOS 与 Android 间迁移登录状态，但文件包含敏感 Token/API Key，请只保存到可信位置。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section("Scriptable 小组件") {
        Button { prepareScriptExport() } label: {
          Label("导出 QuotaPulseWidget.js", systemImage: "doc.badge.gearshape")
        }
        Button(role: .destructive) { pendingSensitiveExport = .scriptable } label: {
          Label("导出 Scriptable 配置（含凭据）", systemImage: "key.viewfinder")
        }
        Text("先把 JS 文件加入 Scriptable，再在 Scriptable App 中运行脚本并选择配置 JSON。凭据会保存到 Scriptable 自己的 Keychain，随后小组件可独立刷新。")
          .font(.footnote).foregroundStyle(.secondary)
        Text("第三方兼容方案，风险由用户自行承担。Scriptable 只能使用系统网络或系统 VPN，不能读取 QuotaPulse 的 App 内代理。")
          .font(.footnote).foregroundStyle(.orange)
      }
    }
    .navigationTitle("导入与导出")
    .sheet(isPresented: $importing) {
      JSONDocumentPicker(
        onResult: { result in
          importing = false
          Task { await importFile(result) }
        },
        onCancel: {
          importing = false
        }
      )
    }
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportContentType, defaultFilename: exportFilename) { result in
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
      exportDocument = nil
    }
    .confirmationDialog(
      pendingSensitiveExport?.title ?? "敏感凭据导出",
      isPresented: Binding(
        get: { pendingSensitiveExport != nil },
        set: { if !$0 { pendingSensitiveExport = nil } }
      ),
      titleVisibility: .visible
    ) {
      if pendingSensitiveExport == .fullBackup {
        Button("继续导出完整备份", role: .destructive) {
          pendingSensitiveExport = nil
          prepareExport(includeCredentials: true)
        }
      }
      if pendingSensitiveExport == .scriptable {
        Button("我已了解风险，继续导出", role: .destructive) {
          pendingSensitiveExport = nil
          Task { await prepareScriptableConfigExport() }
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text(pendingSensitiveExport?.message ?? "")
    }
    .alert(item: $importFeedback) { feedback in
      Alert(
        title: Text(feedback.title),
        message: Text(feedback.message),
        dismissButton: .default(Text("好"))
      )
    }
  }

  private func prepareExport(includeCredentials: Bool) {
    do {
      exportFilename = "QuotaPulse-backup-\(exportTimestamp())"
      exportContentType = .json
      exportDocument = try model.exportConfig(includeCredentials: includeCredentials)
      exporting = true
    }
    catch { model.errorMessage = error.localizedDescription }
  }

  private func prepareScriptExport() {
    do {
      exportFilename = "QuotaPulseWidget.js"
      exportContentType = .javaScript
      exportDocument = PortableConfigDocument(data: try ScriptableConfigExporter.scriptData())
      exporting = true
    } catch {
      showImportFeedback(title: "导出失败", message: error.localizedDescription, isError: true)
    }
  }

  @MainActor private func prepareScriptableConfigExport() async {
    do {
      exportFilename = "QuotaPulse-Scriptable-\(exportTimestamp())"
      exportContentType = .json
      let minutes = await SharedStore.shared.autoRefreshMinutes()
      let data = try ScriptableConfigExporter.configData(
        accounts: model.accounts,
        refreshMinutes: minutes
      )
      exportDocument = PortableConfigDocument(data: data)
      exporting = true
    } catch {
      showImportFeedback(title: "导出失败", message: error.localizedDescription, isError: true)
    }
  }

  private func exportTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }

  @MainActor private func importFile(_ result: Result<Data, Error>) async {
    importInProgress = true
    defer { importInProgress = false }
    do {
      let data = try result.get()
      await model.importConfig(data, replace: replaceOnImport)
      if let error = model.errorMessage {
        model.errorMessage = nil
        showImportFeedback(title: "导入失败", message: error, isError: true)
      } else {
        let message = model.statusMessage ?? "JSON 导入完成"
        model.statusMessage = nil
        showImportFeedback(title: "导入完成", message: message, isError: false)
      }
    } catch {
      showImportFeedback(title: "导入失败", message: error.localizedDescription, isError: true)
    }
  }

  private func showImportFeedback(title: String, message: String, isError: Bool) {
    importStatusText = message
    importStatusIsError = isError
    importFeedback = ImportFeedback(title: title, message: message)
  }
}

private struct ImportFeedback: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

private struct JSONDocumentPicker: UIViewControllerRepresentable {
  let onResult: (Result<Data, Error>) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.json, .plainText, .data],
      asCopy: true
    )
    picker.allowsMultipleSelection = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let parent: JSONDocumentPicker

    init(parent: JSONDocumentPicker) { self.parent = parent }

    func documentPicker(
      _ controller: UIDocumentPickerViewController,
      didPickDocumentsAt urls: [URL]
    ) {
      guard let url = urls.first else {
        parent.onResult(.failure(PortableConfigError.invalidFormat))
        return
      }
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        parent.onResult(.success(try Data(contentsOf: url, options: .mappedIfSafe)))
      } catch {
        parent.onResult(.failure(error))
      }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      parent.onCancel()
    }
  }
}
