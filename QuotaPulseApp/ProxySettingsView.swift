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
  @Environment(\.scenePhase) private var scenePhase
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
  @State private var testingSavedProfileID: UUID?
  @State private var savedResults: [UUID: [ProxyProbeResult]] = [:]
  @State private var statusMessage: String?
  @State private var pendingDelete: AppProxyProfile?
  @State private var systemVPNActive = false

  var body: some View {
    Form {
      if systemVPNActive {
        Section {
          Label("系统 VPN 已连接", systemImage: "shield.lefthalf.filled")
            .foregroundStyle(.green)
          Text("QuotaPulse 当前优先使用系统 VPN；已激活的内部代理会暂时待命，断开 VPN 后自动恢复使用。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      Section(editingID == nil ? "创建代理" : "编辑代理") {
        TextField("代理名称（可选）", text: $profileName)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Toggle("保存后激活", isOn: $activateAfterSave)
        TextField("socks5://user:pass@host:port", text: $proxyLink)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        Text("兼容 socks5://、socks://、socket://、http:// 和 https://；特殊字符建议使用 URL 编码。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("适用服务") {
        ForEach(AppProxyTarget.allCases) { target in
          Toggle(target.title, isOn: targetBinding(target))
        }
        Text("同一时间最多激活一个代理；未勾选的服务保持直连。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let validationMessage = draftValidationMessage {
        Section {
          Label(validationMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }

      Section {
        HStack(spacing: 10) {
          Button {
            testProxy()
          } label: {
            Label(isTesting ? "测试中" : "测试服务", systemImage: "speedometer")
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(isTesting || draftValidationMessage != nil)

          Button {
            saveProfile()
          } label: {
            Label(editingID == nil ? "创建代理" : "保存修改", systemImage: "checkmark.circle")
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(draftValidationMessage != nil)
        }

        probeRows(results)

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

      Section {
        if profiles.isEmpty {
          Text("尚未创建代理")
            .foregroundStyle(.secondary)
        } else {
          ForEach(profiles) { profile in
            proxyRow(profile)
          }
        }
      } header: {
        Text("已创建代理")
      } footer: {
        Text("代理用于所选服务的额度查询、Token 刷新和测速。iOS 16 的系统 OAuth 登录页仍遵循系统网络。")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.background)
    .navigationTitle("网络代理")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      systemVPNActive = await SystemVPNDetector.isActive()
      await loadProfiles()
    }
    .onChange(of: scenePhase) { phase in
      guard phase == .active else { return }
      Task { systemVPNActive = await SystemVPNDetector.isActive() }
    }
    .onChange(of: proxyLink) { _ in results = [] }
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
        Button {
          testSavedProfile(profile)
        } label: {
          Label(
            testingSavedProfileID == profile.id ? "测试中" : "测试",
            systemImage: "speedometer"
          )
        }
        .disabled(testingSavedProfileID != nil)
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

      probeRows(savedResults[profile.id] ?? [])
    }
    .padding(.vertical, 4)
  }

  private var draftValidationMessage: String? {
    if targets.isEmpty { return "请至少选择 Codex 或 Claude" }
    if proxyLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入代理链接" }
    do {
      _ = try AppProxyConfiguration.parse(link: proxyLink)
      return nil
    } catch {
      return error.localizedDescription
    }
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

  private func saveProfile() {
    let parsed: ParsedAppProxyLink
    do {
      parsed = try AppProxyConfiguration.parse(link: proxyLink)
    } catch {
      statusMessage = error.localizedDescription
      return
    }
    configuration = parsed.configuration
    password = parsed.password
    let existing = editingID.flatMap { id in profiles.first { $0.id == id } }
    let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = trimmedName.isEmpty
      ? (existing?.name ?? "代理 \(profiles.count + 1)")
      : trimmedName
    let profile = AppProxyProfile(
      id: editingID ?? UUID(),
      name: resolvedName,
      configuration: parsed.configuration,
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
    password = (try? KeychainStore.shared.proxyPassword(profileID: profile.id)) ?? ""
    proxyLink = linkString(configuration: profile.configuration, password: password)
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
        savedResults[profile.id] = nil
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
    let parsed: ParsedAppProxyLink
    do {
      parsed = try AppProxyConfiguration.parse(link: proxyLink)
    } catch {
      statusMessage = error.localizedDescription
      return
    }
    configuration = parsed.configuration
    password = parsed.password
    isTesting = true
    results = []
    Task {
      let values = await ProxySpeedTester.run(
        configuration: parsed.configuration,
        password: parsed.password,
        targets: targets
      )
      await MainActor.run {
        results = values
        isTesting = false
      }
    }
  }

  private func linkString(configuration: AppProxyConfiguration, password: String) -> String {
    var components = URLComponents()
    components.scheme = configuration.kind == .socks5 ? "socks5" : "http"
    components.host = configuration.normalizedHost
    components.port = configuration.port
    if !configuration.username.isEmpty {
      components.user = configuration.username
      if !password.isEmpty { components.password = password }
    }
    return components.string ?? ""
  }

  private func testSavedProfile(_ profile: AppProxyProfile) {
    testingSavedProfileID = profile.id
    savedResults[profile.id] = []
    let password = (try? KeychainStore.shared.proxyPassword(profileID: profile.id)) ?? ""
    Task {
      let values = await ProxySpeedTester.run(
        configuration: profile.configuration,
        password: password,
        targets: profile.targets
      )
      await MainActor.run {
        savedResults[profile.id] = values
        testingSavedProfileID = nil
      }
    }
  }

  @ViewBuilder private func probeRows(_ values: [ProxyProbeResult]) -> some View {
    ForEach(values) { result in
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

  private func latencyColor(_ milliseconds: Int) -> Color {
    if milliseconds <= 300 { return .green }
    if milliseconds <= 1_000 { return .orange }
    return .red
  }
}
