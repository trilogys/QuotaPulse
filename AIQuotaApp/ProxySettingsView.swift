import SwiftUI

private struct ProxyProbeResult: Identifiable, Sendable {
  let id: String
  let name: String
  let latencyMilliseconds: Int?
  let errorMessage: String?
}

private enum ProxySpeedTester {
  static func run(
    configuration: AppProxyConfiguration,
    password: String,
    targets: Set<AppProxyTarget>
  ) async -> [ProxyProbeResult] {
    await withTaskGroup(of: ProxyProbeResult.self) { group in
      for target in AppProxyTarget.allCases where targets.contains(target) {
        group.addTask {
          let url: URL
          switch target {
          case .codex: url = URL(string: "https://auth.openai.com/")!
          case .claude: url = URL(string: "https://api.anthropic.com/")!
          }
          return await probe(
            target: target,
            url: url,
            configuration: configuration,
            password: password
          )
        }
      }
      var values: [ProxyProbeResult] = []
      for await value in group { values.append(value) }
      return values.sorted { lhs, rhs in
        let order = Dictionary(uniqueKeysWithValues: AppProxyTarget.allCases.enumerated().map { ($0.element.title, $0.offset) })
        return (order[lhs.name] ?? 0) < (order[rhs.name] ?? 0)
      }
    }
  }

  private static func probe(
    target: AppProxyTarget,
    url: URL,
    configuration: AppProxyConfiguration,
    password: String
  ) async -> ProxyProbeResult {
    let start = Date()
    do {
      _ = try await HTTPClient.shared.send(
        url,
        method: "GET",
        timeout: 12,
        proxyOverride: configuration,
        proxyPasswordOverride: password
      )
      return ProxyProbeResult(
        id: target.rawValue,
        name: target.title,
        latencyMilliseconds: max(1, Int(Date().timeIntervalSince(start) * 1000)),
        errorMessage: nil
      )
    } catch {
      return ProxyProbeResult(
        id: target.rawValue,
        name: target.title,
        latencyMilliseconds: nil,
        errorMessage: error.localizedDescription
      )
    }
  }
}

struct ProxySettingsView: View {
  @Environment(\.dashboardTheme) private var theme
  @State private var profiles: [AppProxyProfile] = []
  @State private var editingID: UUID?
  @State private var profileName = ""
  @State private var configuration = AppProxyConfiguration(kind: .socks5)
  @State private var targets = Set(AppProxyTarget.allCases)
  @State private var activateAfterSave = true
  @State private var proxyLink = ""
  @State private var password = ""
  @State private var results: [ProxyProbeResult] = []
  @State private var isTesting = false
  @State private var statusMessage: String?
  @State private var pendingDelete: AppProxyProfile?

  var body: some View {
    Form {
      Section(editingID == nil ? "创建代理" : "编辑代理") {
        TextField("代理名称", text: $profileName)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Toggle("保存后激活", isOn: $activateAfterSave)
      }

      Section("适用服务") {
        ForEach(AppProxyTarget.allCases) { target in
          Toggle(target.title, isOn: targetBinding(target))
        }
        Text("同一时间最多激活一个代理；未勾选的服务保持直连。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("代理链接") {
        TextField("socks5://user:pass@host:port", text: $proxyLink)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        Button {
          parseProxyLink()
        } label: {
          Label("解析代理链接", systemImage: "link")
        }
        .disabled(proxyLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Text("兼容 socks5://、socks://、socket://、http:// 和 https://；特殊字符建议使用 URL 编码。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("代理类型") {
        Picker("代理类型", selection: $configuration.kind) {
          Text(AppProxyKind.http.title).tag(AppProxyKind.http)
          Text(AppProxyKind.socks5.title).tag(AppProxyKind.socks5)
        }
        .pickerStyle(.segmented)
      }

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

      if let validationMessage = draftValidationMessage {
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
            Label(isTesting ? "正在测试" : "测试所选服务", systemImage: "speedometer")
            Spacer()
            if isTesting { ProgressView() }
          }
        }
        .disabled(isTesting || draftValidationMessage != nil)

        ForEach(results) { result in
          HStack {
            Text(result.name)
            Spacer()
            if let latency = result.latencyMilliseconds {
              Text("\(latency) ms")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(latencyColor(latency))
            } else {
              Text("失败").foregroundStyle(.red)
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

      Section {
        Button {
          saveProfile()
        } label: {
          Label(editingID == nil ? "创建代理" : "保存修改", systemImage: "checkmark.circle")
            .frame(maxWidth: .infinity)
        }
        .disabled(draftValidationMessage != nil)

        if editingID != nil {
          Button("取消编辑", role: .cancel) { resetEditor() }
            .frame(maxWidth: .infinity)
        }

        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("已创建代理") {
        if profiles.isEmpty {
          Text("尚未创建代理")
            .foregroundStyle(.secondary)
        } else {
          ForEach(profiles) { profile in
            proxyRow(profile)
          }
        }
      } footer: {
        Text("代理用于所选服务的额度查询、Token 刷新和测速。iOS 16 的系统 OAuth 登录页仍遵循系统网络。")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.background)
    .navigationTitle("网络代理")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadProfiles() }
    .confirmationDialog(
      "删除代理？",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("删除", role: .destructive) {
        if let profile = pendingDelete { deleteProfile(profile) }
      }
      Button("取消", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("代理配置和对应密码将从本机删除。")
    }
  }

  @ViewBuilder private func proxyRow(_ profile: AppProxyProfile) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(profile.name)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
        Spacer()
        if profile.isActive {
          Label("已激活", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }
      Text("\(profile.configuration.kind.title) · \(profile.configuration.normalizedHost):\(profile.configuration.port)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(profile.targets.map(\.title).sorted().joined(separator: " · "))
        .font(.caption)
        .foregroundStyle(theme.secondary)

      HStack(spacing: 14) {
        Button {
          setActive(profile, active: !profile.isActive)
        } label: {
          Label(profile.isActive ? "停用" : "激活", systemImage: profile.isActive ? "pause.circle" : "play.circle")
        }
        Button {
          editProfile(profile)
        } label: {
          Label("编辑", systemImage: "pencil")
        }
        Spacer()
        Button(role: .destructive) {
          pendingDelete = profile
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityLabel("删除 \(profile.name)")
      }
      .font(.system(size: 12, weight: .semibold))
      .buttonStyle(.plain)
    }
    .padding(.vertical, 4)
  }

  private var draftValidationMessage: String? {
    AppProxyProfile(
      id: editingID ?? UUID(),
      name: profileName,
      configuration: configuration,
      targets: targets,
      isActive: activateAfterSave
    ).validationMessage
  }

  private var portBinding: Binding<String> {
    Binding(
      get: { configuration.port == 0 ? "" : String(configuration.port) },
      set: { configuration.port = Int($0.filter(\.isNumber)) ?? 0 }
    )
  }

  private func targetBinding(_ target: AppProxyTarget) -> Binding<Bool> {
    Binding(
      get: { targets.contains(target) },
      set: { selected in
        if selected { targets.insert(target) } else { targets.remove(target) }
      }
    )
  }

  private func loadProfiles() async {
    profiles = await SharedStore.shared.proxyProfiles()
  }

  private func parseProxyLink() {
    do {
      let parsed = try AppProxyConfiguration.parse(link: proxyLink)
      configuration = parsed.configuration
      password = parsed.password
      results = []
      statusMessage = "代理链接已解析，请测试后创建"
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func saveProfile() {
    let existing = editingID.flatMap { id in profiles.first { $0.id == id } }
    let profile = AppProxyProfile(
      id: editingID ?? UUID(),
      name: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
      configuration: configuration,
      targets: targets,
      isActive: activateAfterSave,
      createdAt: existing?.createdAt ?? .now
    )
    Task {
      do {
        try KeychainStore.shared.saveProxyPassword(password, profileID: profile.id)
        await SharedStore.shared.upsertProxyProfile(profile)
        await loadProfiles()
        await MainActor.run {
          statusMessage = editingID == nil ? "代理已创建" : "代理已更新"
          resetEditor(keepStatus: true)
        }
      } catch {
        await MainActor.run { statusMessage = error.localizedDescription }
      }
    }
  }

  private func editProfile(_ profile: AppProxyProfile) {
    editingID = profile.id
    profileName = profile.name
    configuration = profile.configuration
    targets = profile.targets
    activateAfterSave = profile.isActive
    proxyLink = ""
    password = (try? KeychainStore.shared.proxyPassword(profileID: profile.id)) ?? ""
    results = []
    statusMessage = "正在编辑 \(profile.name)"
  }

  private func setActive(_ profile: AppProxyProfile, active: Bool) {
    Task {
      await SharedStore.shared.setProxyProfileActive(id: profile.id, active: active)
      await loadProfiles()
      await MainActor.run { statusMessage = active ? "已激活 \(profile.name)" : "已停用 \(profile.name)" }
    }
  }

  private func deleteProfile(_ profile: AppProxyProfile) {
    pendingDelete = nil
    Task {
      await SharedStore.shared.removeProxyProfile(id: profile.id)
      try? KeychainStore.shared.deleteProxyPassword(profileID: profile.id)
      await loadProfiles()
      await MainActor.run {
        if editingID == profile.id { resetEditor() }
        statusMessage = "代理已删除"
      }
    }
  }

  private func resetEditor(keepStatus: Bool = false) {
    editingID = nil
    profileName = ""
    configuration = AppProxyConfiguration(kind: .socks5)
    targets = Set(AppProxyTarget.allCases)
    activateAfterSave = profiles.first(where: \.isActive) == nil
    proxyLink = ""
    password = ""
    results = []
    if !keepStatus { statusMessage = nil }
  }

  private func testProxy() {
    isTesting = true
    results = []
    Task {
      let values = await ProxySpeedTester.run(
        configuration: configuration,
        password: password,
        targets: targets
      )
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
