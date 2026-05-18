import SwiftUI
import UIKit

struct AppThemeColors {
    let accent: Color
    let accentHighlight: Color
    let accentSurface: Color
    let accentSurfaceStrong: Color
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let cardBackground: Color
    let cardBackgroundElevated: Color
    let cardBorder: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let success: Color
    let warning: Color
    let danger: Color
}

enum AppTheme: String, CaseIterable, Identifiable {
    case appleGreen
    case purple
    case orange
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleGreen:
            return "Fitness Green"
        case .purple:
            return "Purple"
        case .orange:
            return "Orange"
        case .blue:
            return "Blue"
        }
    }

    var primaryColor: Color {
        colors.accent
    }

    var secondaryColor: Color {
        colors.accentSurfaceStrong
    }

    var colors: AppThemeColors {
        let accent: Color
        switch self {
        case .appleGreen:
            accent = Color(hex: 0x30D158)
        case .purple:
            accent = Color(hex: 0xBF5AF2)
        case .orange:
            accent = Color(hex: 0xFF9F0A)
        case .blue:
            accent = Color(hex: 0x0A84FF)
        }

        return AppThemeColors(
            accent: accent,
            accentHighlight: self == .appleGreen ? Color(hex: 0x64D80A) : accent.opacity(0.86),
            accentSurface: accent.opacity(0.16),
            accentSurfaceStrong: accent.opacity(0.26),
            backgroundPrimary: Color(light: 0xF7F7F9, dark: 0x000000),
            backgroundSecondary: Color(light: 0xFFFFFF, dark: 0x0B0B0D),
            cardBackground: Color(light: 0xFFFFFF, dark: 0x1C1C1E),
            cardBackgroundElevated: Color(light: 0xF0F0F5, dark: 0x242426),
            cardBorder: Color(light: 0xDEDEE6, dark: 0x2F2F33),
            textPrimary: Color(light: 0x111114, dark: 0xFFFFFF),
            textSecondary: Color(light: 0x66666D, dark: 0xA1A1A6),
            textTertiary: Color(light: 0x8B8B92, dark: 0x6E6E73),
            success: Color(hex: 0x30D158),
            warning: Color(hex: 0xFF9F0A),
            danger: Color(hex: 0xFF453A)
        )
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

extension AppTheme {
    var cardBackground: Color {
        colors.cardBackground
    }

    var elevatedCardBackground: Color {
        colors.cardBackgroundElevated
    }

    var cardBorder: Color {
        colors.cardBorder
    }

    var mutedText: Color {
        colors.textSecondary
    }

    var successColor: Color {
        colors.success
    }

    var actionColor: Color {
        colors.accent
    }

    var warningColor: Color {
        colors.warning
    }

    var dangerColor: Color {
        colors.danger
    }
}

private extension Color {
    init(light: UInt, dark: UInt) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            }
        )
    }

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt, opacity: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
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
            .tint(theme.actionColor)
            .preferredColorScheme(appearance.colorScheme)
    }
}
