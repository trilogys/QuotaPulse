import SwiftUI

enum DashboardTheme: String, CaseIterable, Codable, Identifiable, Sendable {
  case neon
  case graphite
  case aurora
  case daylight

  var id: String { rawValue }

  var title: String {
    switch self {
    case .neon: "霓虹夜"
    case .graphite: "石墨"
    case .aurora: "极光"
    case .daylight: "明亮"
    }
  }

  var subtitle: String {
    switch self {
    case .neon: "紫色与青色，高对比暗色"
    case .graphite: "中性黑灰，安静克制"
    case .aurora: "墨绿底色，多彩强调"
    case .daylight: "浅色背景，日间清晰"
    }
  }

  var preferredColorScheme: ColorScheme {
    self == .daylight ? .light : .dark
  }

  var background: Color {
    switch self {
    case .neon: Color(red: 0.035, green: 0.04, blue: 0.055)
    case .graphite: Color(red: 0.045, green: 0.05, blue: 0.055)
    case .aurora: Color(red: 0.025, green: 0.07, blue: 0.06)
    case .daylight: Color(red: 0.94, green: 0.945, blue: 0.95)
    }
  }

  var backgroundAccent: Color {
    switch self {
    case .neon: Color(red: 0.075, green: 0.055, blue: 0.13)
    case .graphite: Color(red: 0.075, green: 0.08, blue: 0.085)
    case .aurora: Color(red: 0.04, green: 0.12, blue: 0.10)
    case .daylight: Color(red: 0.87, green: 0.88, blue: 0.89)
    }
  }

  var surface: Color {
    switch self {
    case .neon: Color(red: 0.085, green: 0.09, blue: 0.115)
    case .graphite: Color(red: 0.09, green: 0.095, blue: 0.10)
    case .aurora: Color(red: 0.065, green: 0.105, blue: 0.095)
    case .daylight: .white
    }
  }

  var surfaceRaised: Color {
    switch self {
    case .neon: Color(red: 0.115, green: 0.12, blue: 0.15)
    case .graphite: Color(red: 0.13, green: 0.135, blue: 0.14)
    case .aurora: Color(red: 0.09, green: 0.145, blue: 0.13)
    case .daylight: Color(red: 0.925, green: 0.93, blue: 0.935)
    }
  }

  var border: Color {
    self == .daylight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
  }

  var secondaryText: Color {
    switch self {
    case .daylight: Color(red: 0.36, green: 0.39, blue: 0.45)
    default: Color(red: 0.62, green: 0.64, blue: 0.72)
    }
  }

  var primaryText: Color {
    self == .daylight ? Color(red: 0.08, green: 0.09, blue: 0.12) : .white
  }

  var cardCornerRadius: CGFloat { self == .daylight ? 24 : 22 }
  var compactCardCornerRadius: CGFloat { self == .daylight ? 18 : 16 }

  var primary: Color {
    switch self {
    case .neon: Color(red: 0.49, green: 0.20, blue: 0.96)
    case .graphite: Color(red: 0.20, green: 0.76, blue: 0.60)
    case .aurora: Color(red: 0.22, green: 0.82, blue: 0.80)
    case .daylight: Color(red: 0.93, green: 0.34, blue: 0.10)
    }
  }

  var secondary: Color {
    switch self {
    case .neon: Color(red: 0.25, green: 0.82, blue: 0.80)
    case .graphite: Color(red: 0.95, green: 0.53, blue: 0.19)
    case .aurora: Color(red: 0.62, green: 0.34, blue: 0.94)
    case .daylight: Color(red: 0.96, green: 0.10, blue: 0.28)
    }
  }

  var success: Color {
    switch self {
    case .graphite: Color(red: 0.33, green: 0.74, blue: 0.44)
    case .daylight: Color(red: 0.16, green: 0.65, blue: 0.34)
    default: Color(red: 0.20, green: 0.78, blue: 0.45)
    }
  }

  var warning: Color { Color(red: 0.94, green: 0.39, blue: 0.18) }

  func accent(for provider: ProviderID) -> Color {
    switch (self, provider) {
    case (.daylight, .codex): Color(red: 0.93, green: 0.34, blue: 0.10)
    case (.daylight, .claude): Color(red: 0.96, green: 0.10, blue: 0.28)
    case (.daylight, .kimi): Color(red: 0.16, green: 0.65, blue: 0.34)
    case (.daylight, .deepseek): Color(red: 0.08, green: 0.58, blue: 0.55)
    case (.daylight, .minimax): Color(red: 0.96, green: 0.60, blue: 0.10)
    case (.daylight, .glm): Color(red: 0.24, green: 0.49, blue: 0.88)
    case (.daylight, .copilot): Color(red: 0.54, green: 0.35, blue: 0.78)
    case (_, .codex): primary
    case (_, .claude): warning
    case (_, .kimi): success
    case (_, .deepseek): secondary
    case (.graphite, .minimax): Color(red: 0.88, green: 0.72, blue: 0.28)
    case (_, .minimax): Color(red: 0.95, green: 0.65, blue: 0.18)
    case (.aurora, .glm): Color(red: 0.42, green: 0.58, blue: 0.98)
    case (_, .glm): Color(red: 0.30, green: 0.53, blue: 0.98)
    case (_, .copilot): Color(red: 0.78, green: 0.45, blue: 0.92)
    }
  }

  var previewColors: [Color] { [primary, secondary, success, warning] }
}

private struct DashboardThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue: DashboardTheme = .daylight
}

extension EnvironmentValues {
  var dashboardTheme: DashboardTheme {
    get { self[DashboardThemeEnvironmentKey.self] }
    set { self[DashboardThemeEnvironmentKey.self] = newValue }
  }
}
