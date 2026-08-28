import SwiftUI

private struct ProxyProbeResult: Identifiable, Sendable {
  let id: String
  let name: String
  let latencyMilliseconds: Int?
  let errorMessage: String?
}

private enum ProxySpeedTester {
  static func run(configuration: AppProxyConfiguration, password: String) async -> [ProxyProbeResult] {
    async let openAI = probe(
      name: "OpenAI",
      url: URL(string: "https://auth.openai.com/")!,
      configuration: configuration,
      password: password
    )
    async let claude = probe(
      name: "Claude",
      url: URL(string: "https://api.anthropic.com/")!,
      configuration: configuration,
      password: password
    )
    let values = await (openAI, claude)
    return [values.0, values.1]
  }

  private static func probe(
    name: String,
    url: URL,
    configuration: AppProxyConfiguration,
    password: String
  ) async -> ProxyProbeResult {
    let start = Date()
    do {
      _ = try await HTTPClient.shared.send(
        url,
        method: "HEAD",
        timeout: 12,
        proxyOverride: configuration,
        proxyPasswordOverride: password
      )
      let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
      return ProxyProbeResult(id: name, name: name, latencyMilliseconds: latency, errorMessage: nil)
    } catch {
      return ProxyProbeResult(
        id: name,
        name: name,
        latencyMilliseconds: nil,
        errorMessage: error.localizedDescription
      )
    }
  }
}

struct ProxySettingsView: View {
  @Environment(\.dashboardTheme) private var theme
  @State private var configuration = AppProxyConfiguration.disabled
  @State private var password = ""
  @State private var results: [ProxyProbeResult] = []
  @State private var isTesting = false
  @State private var statusMessage: String?

  var body: some View {
    Form {
      Section("代理类型") {
        Picker("代理类型", selection: $configuration.kind) {
          ForEach(AppProxyKind.allCases) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .pickerStyle(.segmented)
      }

      if configuration.kind != .disabled {
        Section("服务器") {
          TextField("主机，例如 192.168.1.2", text: $configuration.host)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          TextField("端口", text: portBinding)
            .keyboardType(.numberPad)
          TextField("用户名（可选）", text: $configuration.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("密码（可选）", text: $password)
        }

        if let validationMessage = configuration.validationMessage {
          Section {
            Label(validationMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }

        Section("连接测试") {
          Button {
            testProxy()
          } label: {
            HStack {
              Label(isTesting ? "正在测试" : "测试 OpenAI 与 Claude", systemImage: "speedometer")
              Spacer()
              if isTesting { ProgressView() }
            }
          }
          .disabled(isTesting || configuration.validationMessage != nil)

          ForEach(results) { result in
            HStack {
              Text(result.name)
              Spacer()
              if let latency = result.latencyMilliseconds {
                Text("\(latency) ms")
                  .font(.system(.body, design: .monospaced).weight(.semibold))
                  .foregroundStyle(latencyColor(latency))
              } else {
                Text("失败")
                  .foregroundStyle(.red)
              }
            }
            if let error = result.errorMessage {
              Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
          }
        }
      }

      Section {
        Button {
          saveProxy()
        } label: {
          Label(configuration.kind == .disabled ? "关闭并保存" : "保存代理配置", systemImage: "checkmark.circle")
            .frame(maxWidth: .infinity)
        }
        .disabled(configuration.validationMessage != nil)

        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text("代理用于额度查询、Token 刷新和测速。iOS 16 的系统 OAuth 登录页仍遵循系统网络；无法登录时可先导入已有凭据。")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.background)
    .navigationTitle("网络代理")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadProxy() }
  }

  private var portBinding: Binding<String> {
    Binding(
      get: { configuration.port == 0 ? "" : String(configuration.port) },
      set: { configuration.port = Int($0.filter(\.isNumber)) ?? 0 }
    )
  }

  private func loadProxy() async {
    configuration = await SharedStore.shared.proxyConfiguration()
    password = (try? KeychainStore.shared.proxyPassword()) ?? ""
  }

  private func saveProxy() {
    Task {
      await SharedStore.shared.setProxyConfiguration(configuration)
      do {
        try KeychainStore.shared.saveProxyPassword(password)
        await MainActor.run { statusMessage = "代理配置已保存" }
      } catch {
        await MainActor.run { statusMessage = error.localizedDescription }
      }
    }
  }

  private func testProxy() {
    isTesting = true
    results = []
    Task {
      let values = await ProxySpeedTester.run(configuration: configuration, password: password)
      await MainActor.run {
        results = values
        isTesting = false
      }
    }
  }

  private func latencyColor(_ milliseconds: Int) -> Color {
    if milliseconds <= 300 { return .green }
    if milliseconds <= 1_000 { return .orange }
    return .red
  }
}
