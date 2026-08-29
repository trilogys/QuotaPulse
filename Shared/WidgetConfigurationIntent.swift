import AppIntents
import Foundation

@available(iOS 17.0, *)
enum WidgetScopeMode: String, AppEnum {
  case all
  case provider
  case account

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "显示范围")
  static let caseDisplayRepresentations: [WidgetScopeMode: DisplayRepresentation] = [
    .all: "全部账号",
    .provider: "单 Provider",
    .account: "单账号",
  ]
}

@available(iOS 17.0, *)
enum WidgetProviderChoice: String, AppEnum, CaseIterable {
  case codex
  case claude
  case kimi
  case deepseek
  case minimax
  case glm
  case copilot

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
  static let caseDisplayRepresentations: [WidgetProviderChoice: DisplayRepresentation] = [
    .codex: "Codex",
    .claude: "Claude",
    .kimi: "Kimi",
    .deepseek: "DeepSeek",
    .minimax: "MiniMax",
    .glm: "GLM",
    .copilot: "GitHub Copilot",
  ]

  var providerID: ProviderID {
    ProviderID(rawValue: rawValue) ?? .codex
  }
}

@available(iOS 17.0, *)
struct WidgetAccountEntity: AppEntity, Identifiable, Hashable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "账号")
  static let defaultQuery = WidgetAccountQuery()

  let id: String
  let label: String
  let provider: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(label)", subtitle: "\(provider)")
  }
}

@available(iOS 17.0, *)
struct WidgetAccountQuery: EntityQuery {
  func entities(for identifiers: [WidgetAccountEntity.ID]) async throws -> [WidgetAccountEntity] {
    let wanted = Set(identifiers)
    return await SharedStore.shared.accounts()
      .filter { wanted.contains($0.id.uuidString) }
      .map(WidgetAccountEntity.init)
  }

  func suggestedEntities() async throws -> [WidgetAccountEntity] {
    await SharedStore.shared.accounts()
      .filter(\.isEnabled)
      .map(WidgetAccountEntity.init)
  }
}

@available(iOS 17.0, *)
private extension WidgetAccountEntity {
  init(_ account: AccountRecord) {
    self.init(id: account.id.uuidString, label: account.label, provider: account.provider.title)
  }
}

@available(iOS 17.0, *)
struct QuotaPulseWidgetConfigurationIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "配置 QuotaPulse 小组件"
  static let description = IntentDescription("选择显示全部账号、单个 Provider 或单个账号。")

  @Parameter(title: "显示范围", default: .all)
  var mode: WidgetScopeMode

  @Parameter(title: "Provider", default: .codex)
  var provider: WidgetProviderChoice

  @Parameter(title: "账号")
  var account: WidgetAccountEntity?
}
