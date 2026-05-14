import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case appleGreen
    case purple
    case orange
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleGreen:
            return "Workout Green"
        case .purple:
            return "Purple"
        case .orange:
            return "Orange"
        case .blue:
            return "Blue"
        }
    }

    var primaryColor: Color {
        switch self {
        case .appleGreen:
            return Color(red: 124.0 / 255.0, green: 252.0 / 255.0, blue: 0.0)
        case .purple:
            return Color(red: 0.54, green: 0.32, blue: 0.92)
        case .orange:
            return Color(red: 0.95, green: 0.45, blue: 0.16)
        case .blue:
            return .blue
        }
    }

    var secondaryColor: Color {
        switch self {
        case .appleGreen:
            return Color(red: 0.24, green: 0.52, blue: 0.0)
        case .purple:
            return Color(red: 0.30, green: 0.18, blue: 0.60)
        case .orange:
            return Color(red: 0.62, green: 0.25, blue: 0.06)
        case .blue:
            return .indigo
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.appleGreen
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct AppThemeProvider<Content: View>: View {
    @AppStorage("appTheme") private var storedTheme = AppTheme.appleGreen.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var theme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .appleGreen
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: storedAppearance) ?? .system
    }

    var body: some View {
        content
            .environment(\.appTheme, theme)
            .tint(theme.primaryColor)
            .preferredColorScheme(appearance.colorScheme)
    }
}
