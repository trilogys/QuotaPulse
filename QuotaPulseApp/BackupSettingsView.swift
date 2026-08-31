import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
  @State private var exporting = false
  @State private var pendingCredentialExport = false

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
        Button(role: .destructive) { pendingCredentialExport = true } label: { Label("完整备份（含 Token / API Key）", systemImage: "key.horizontal") }
        Text("不含凭据的配置适合普通备份和分享。完整备份可以在 iOS 与 Android 间迁移登录状态，但文件包含敏感 Token/API Key，请只保存到可信位置。")
          .font(.footnote).foregroundStyle(.secondary)
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
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: exportFilename) { result in
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
      exportDocument = nil
    }
    .confirmationDialog("完整备份包含敏感凭据", isPresented: $pendingCredentialExport, titleVisibility: .visible) {
      Button("继续导出完整备份", role: .destructive) { prepareExport(includeCredentials: true) }
      Button("取消", role: .cancel) {}
    } message: {
      Text("任何拿到此文件的人都可能获得其中账号的 API Key、Access Token 或 Refresh Token。请勿发送到群聊、公开网盘或 GitHub。")
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
      exportDocument = try model.exportConfig(includeCredentials: includeCredentials)
      exporting = true
    }
    catch { model.errorMessage = error.localizedDescription }
  }

  private func exportTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }

  @MainActor private func importFile(_ result: Result<URL, Error>) async {
    importInProgress = true
    defer { importInProgress = false }
    do {
      let url = try result.get()
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
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
  let onResult: (Result<URL, Error>) -> Void
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
      parent.onResult(.success(url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      parent.onCancel()
    }
  }
}
