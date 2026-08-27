import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var importing = false
  @State private var replaceOnImport = false
  @State private var exportDocument: PortableConfigDocument?
  @State private var exporting = false
  @State private var pendingCredentialExport = false

  var body: some View {
    Form {
      Section("导入") {
        Toggle("导入时替换现有账号", isOn: $replaceOnImport)
        Button { importing = true } label: { Label("导入 AI Quota 配置", systemImage: "square.and.arrow.down") }
        Text(replaceOnImport ? "会先移除现有账号和对应凭据，再导入文件。" : "默认合并导入；相同账号会更新，不会重复创建。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section("导出") {
        Button { prepareExport(includeCredentials: false) } label: { Label("导出配置（不含凭据）", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { pendingCredentialExport = true } label: { Label("完整备份（含 Token / API Key）", systemImage: "key.horizontal") }
        Text("不含凭据的配置适合普通备份和分享。完整备份可以在 iOS 与 Android 间迁移登录状态，但文件包含敏感 Token/API Key，请只保存到可信位置。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("导入与导出")
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
      do {
        guard let url = try result.get().first else { return }
        let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        Task { await model.importConfig(data, replace: replaceOnImport) }
      } catch { model.errorMessage = error.localizedDescription }
    }
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "ai-quota-native") { result in
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
      exportDocument = nil
    }
    .confirmationDialog("完整备份包含敏感凭据", isPresented: $pendingCredentialExport, titleVisibility: .visible) {
      Button("继续导出完整备份", role: .destructive) { prepareExport(includeCredentials: true) }
      Button("取消", role: .cancel) {}
    } message: {
      Text("任何拿到此文件的人都可能获得其中账号的 API Key、Access Token 或 Refresh Token。请勿发送到群聊、公开网盘或 GitHub。")
    }
    .alert("完成", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
      Button("好", role: .cancel) { model.statusMessage = nil }
    } message: { Text(model.statusMessage ?? "") }
  }

  private func prepareExport(includeCredentials: Bool) {
    do { exportDocument = try model.exportConfig(includeCredentials: includeCredentials); exporting = true }
    catch { model.errorMessage = error.localizedDescription }
  }
}
