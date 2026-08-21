import SwiftUI

/// The single informational notice card: explanation first, optional icon,
/// tone-driven semantics. Replaces the per-feature notice-card copies.
struct NoticeCard: View {
    @Environment(\.appTheme) private var appTheme

    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case danger

        var systemImage: String {
            switch self {
            case .neutral: return "info.circle"
            case .accent: return "sparkles"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .danger: return "xmark.octagon"
            }
        }

        var textColor: (AppThemeColors) -> Color {
            switch self {
            case .neutral: return { $0.textSecondary }
            case .accent: return { $0.textAccent }
            case .success: return { $0.textSuccess }
            case .warning: return { $0.textWarning }
            case .danger: return { $0.textDanger }
            }
        }
    }

    let message: String
    let tone: Tone
    var systemImage: String?

    init(_ message: String, tone: Tone = .neutral, systemImage: String? = nil) {
        self.message = message
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        FitnessCard(style: .compact, padding: appTheme.metrics.spacing16) {
            Label {
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
            } icon: {
                Image(systemName: systemImage ?? tone.systemImage)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(tone.textColor(appTheme.colors))
            }
        }
    }
}
