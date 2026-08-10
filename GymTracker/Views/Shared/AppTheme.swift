import SwiftUI
import UIKit

struct AppThemeColors {
    let accent: Color
    let accentForeground: Color
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
    let hydration: Color
    let danger: Color
}

struct AppThemeMetrics {
    let spacing2: CGFloat = 2
    let spacing4: CGFloat = 4
    let spacing6: CGFloat = 6
    let spacing8: CGFloat = 8
    let spacing10: CGFloat = 10
    let spacing12: CGFloat = 12
    let spacing14: CGFloat = 14
    let spacing16: CGFloat = 16
    let spacing18: CGFloat = 18
    let spacing20: CGFloat = 20
    let spacing22: CGFloat = 22
    let spacing24: CGFloat = 24
    let spacing28: CGFloat = 28
    let spacing32: CGFloat = 32
    let radius8: CGFloat = 8
    let radius10: CGFloat = 10
    let radius12: CGFloat = 12
    let radius14: CGFloat = 14
    let radius16: CGFloat = 16
    let radius18: CGFloat = 18
    let radius20: CGFloat = 20
    let radius24: CGFloat = 24
    let radius28: CGFloat = 28
    let radius32: CGFloat = 32
    let screenPadding: CGFloat = 16
    let screenBottomPadding: CGFloat = 28
    let screenContentSpacing: CGFloat = 18
    let sectionSpacing: CGFloat = 10
    let cardSpacing: CGFloat = 12
    let standardCardPadding: CGFloat = 20
    let compactCardPadding: CGFloat = 16
    let heroCardPadding: CGFloat = 22
    let standardCardRadius: CGFloat = 24
    let compactCardRadius: CGFloat = 20
    let heroCardRadius: CGFloat = 30
    let iconButtonSize: CGFloat = 44
    let rowIconSize: CGFloat = 38
    let buttonHeight: CGFloat = 50
    let chipVerticalPadding: CGFloat = 8
    let chipHorizontalPadding: CGFloat = 13
    let minimumHitTarget: CGFloat = 44
    let compactRowMinHeight: CGFloat = 48
    let standardRowMinHeight: CGFloat = 56
    let largeRowMinHeight: CGFloat = 64
    let metricTileMinHeight: CGFloat = 104
    let chartCompactHeight: CGFloat = 180
    let chartStandardHeight: CGFloat = 240
    let swipeRevealWidth: CGFloat = 96
    let swipeRevealActionSize: CGFloat = 56
    let swipeRevealActionTrailingPadding: CGFloat = 14
}

enum AppTypography {
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let screenSubtitle = Font.subheadline
    static let heroTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let heroMetric = Font.system(.largeTitle, design: .rounded).monospacedDigit().weight(.heavy)
    static let largeMetric = Font.system(.title2, design: .rounded).monospacedDigit().weight(.bold)
    static let sectionTitle = Font.headline
    static let sectionSubtitle = Font.subheadline
    static let cardTitle = Font.title3.bold()
    static let compactCardTitle = Font.headline.weight(.semibold)
    static let body = Font.subheadline
    static let bodyEmphasis = Font.subheadline.weight(.semibold)
    static let metadata = Font.caption
    static let metadataEmphasis = Font.caption.weight(.semibold)
    static let eyebrow = Font.caption.weight(.bold)
    static let badge = Font.caption2.weight(.bold)
    static let chip = Font.caption.weight(.semibold)
    static let button = Font.headline.weight(.semibold)
    static let workoutNumber = Font.system(.headline, design: .rounded).monospacedDigit().weight(.bold)
    static let workoutLargeNumber = Font.system(.title2, design: .rounded).monospacedDigit().weight(.bold)

    static func rounded(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum PeaklineText {
    static let metadataSeparator = " · "

    static func count(_ value: Int, singular: String, plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    static func joinedMetadata(_ values: [String]) -> String {
        values.filter { !$0.isEmpty }.joined(separator: metadataSeparator)
    }

    static func setRepSummary(sets: Int, minimumReps: Int, maximumReps: Int) -> String {
        joinedMetadata([
            count(sets, singular: "set"),
            repRange(minimum: minimumReps, maximum: maximumReps)
        ])
    }

    static func repRange(minimum: Int, maximum: Int) -> String {
        if minimum == maximum {
            return count(minimum, singular: "rep")
        }
        return "\(minimum)–\(maximum) reps"
    }

    static func loadReps(weight: String, reps: Int, unit: String = "kg") -> String {
        "\(weight) \(unit) × \(reps)"
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case appleGreen
    case red
    case purple
    case orange
    case blue
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleGreen:
            return "Fitness Green"
        case .red:
            return "Pulse Red"
        case .purple:
            return "Purple"
        case .orange:
            return "Orange"
        case .blue:
            return "Blue"
        case .black:
            return "Black"
        }
    }

    var primaryColor: Color {
        colors.accent
    }

    var secondaryColor: Color {
        colors.accentSurfaceStrong
    }

    var metrics: AppThemeMetrics {
        AppThemeMetrics()
    }

    var colors: AppThemeColors {
        let accent: Color
        switch self {
        case .appleGreen:
            accent = Color(hex: 0x30D158)
        case .red:
            accent = Color(hex: 0xFF2C2C)
        case .purple:
            accent = Color(hex: 0xBF5AF2)
        case .orange:
            accent = Color(hex: 0xFF9F0A)
        case .blue:
            accent = Color(hex: 0x0A84FF)
        case .black:
            accent = Color(light: 0x111114, dark: 0xF5F5F7)
        }

        return AppThemeColors(
            accent: accent,
            accentForeground: accentForeground,
            accentHighlight: accentHighlight(for: accent),
            accentSurface: accent.opacity(0.12),
            accentSurfaceStrong: accent.opacity(0.20),
            backgroundPrimary: Color(light: 0xF4F4F7, dark: 0x08080A),
            backgroundSecondary: Color(light: 0xECECF1, dark: 0x101013),
            cardBackground: Color(light: 0xFFFFFF, dark: 0x18181B),
            cardBackgroundElevated: Color(light: 0xF1F1F5, dark: 0x222226),
            cardBorder: Color(light: 0xDEDEE6, dark: 0x303036),
            textPrimary: Color(light: 0x111114, dark: 0xFFFFFF),
            textSecondary: Color(light: 0x606067, dark: 0xB0B0B7),
            textTertiary: Color(light: 0x85858D, dark: 0x7D7D86),
            success: Color(hex: 0x30D158),
            warning: Color(hex: 0xFF9F0A),
            hydration: self == .black ? accent : Color(hex: 0x0A84FF),
            danger: Color(hex: 0xFF453A)
        )
    }

    private var accentForeground: Color {
        switch self {
        case .appleGreen, .orange, .blue:
            return .black
        case .red, .purple:
            return .white
        case .black:
            return Color(light: 0xFFFFFF, dark: 0x000000)
        }
    }

    private func accentHighlight(for accent: Color) -> Color {
        switch self {
        case .appleGreen:
            return Color(hex: 0x64D80A)
        case .red:
            return Color(hex: 0xFF5A5A)
        case .black:
            return Color(light: 0x3A3A3C, dark: 0xFFFFFF)
        case .purple, .orange, .blue:
            return accent.opacity(0.86)
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

extension AppAppearance {
    static var launchArgumentOverride: AppAppearance? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestInMemoryStore"),
              let argumentIndex = arguments.firstIndex(of: "-UITestAppearance"),
              arguments.indices.contains(argumentIndex + 1)
        else {
            return nil
        }

        return AppAppearance(rawValue: arguments[argumentIndex + 1].lowercased())
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
    static let defaultValue = AppTheme.black
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct AppThemeProvider<Content: View>: View {
    @AppStorage("appTheme") private var storedTheme = AppTheme.black.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var theme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .black
    }

    private var appearance: AppAppearance {
        AppAppearance.launchArgumentOverride
            ?? AppAppearance(rawValue: storedAppearance)
            ?? .system
    }

    var body: some View {
        content
            .environment(\.appTheme, theme)
            .tint(theme.actionColor)
            .toggleStyle(AppSwitchToggleStyle(theme: theme))
            .preferredColorScheme(appearance.colorScheme)
            .onAppear {
                if AppTheme(rawValue: storedTheme) == nil {
                    storedTheme = AppTheme.black.rawValue
                }
            }
    }
}

private struct AppSwitchToggleStyle: ToggleStyle {
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeTrack: Color {
        if theme == .black && colorScheme == .dark {
            return Color(hex: 0xF5F5F7)
        }
        return theme.colors.accent
    }

    private var activeThumb: Color {
        if theme == .black && colorScheme == .dark {
            return Color(hex: 0x111114)
        }
        return theme.colors.accentForeground
    }

    private var inactiveTrack: Color {
        colorScheme == .dark
            ? Color(hex: 0x3A3A3C)
            : Color(hex: 0xD7D7DD)
    }

    private var inactiveThumb: Color {
        colorScheme == .dark
            ? Color(hex: 0xF5F5F7)
            : Color(hex: 0xFFFFFF)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            AppHaptics.selection()
            withAnimation(AppMotion.toggle(reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label

                Spacer(minLength: 12)

                switchBody(isOn: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        .opacity(isEnabled ? 1 : 0.52)
    }

    private func switchBody(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: theme.metrics.radius18, style: .continuous)
                .fill(isOn ? activeTrack : inactiveTrack)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.metrics.radius18, style: .continuous)
                        .stroke(
                            isOn ? activeTrack.opacity(0.28) : Color.black.opacity(colorScheme == .dark ? 0 : 0.08),
                            lineWidth: 1
                        )
                }

            Circle()
                .fill(isOn ? activeThumb : inactiveThumb)
                .frame(width: 28, height: 28)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(activeTrack)
                    }
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.16), radius: 3, x: 0, y: 1)
                .padding(3)
        }
        .frame(width: 58, height: 34)
        .animation(AppMotion.toggle(reduceMotion: reduceMotion), value: isOn)
    }
}
