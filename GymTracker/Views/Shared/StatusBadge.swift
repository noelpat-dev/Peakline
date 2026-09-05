import SwiftUI

/// The single capsule badge for statuses, sources, and verification states.
/// Text uses the text-safe semantic role so labels meet contrast targets in
/// Light and Dark Mode; the fill stays a low-opacity tint of the same role.
struct StatusBadge: View {
    @Environment(\.appTheme) private var appTheme

    enum Role {
        case neutral
        case accent
        case success
        case warning
        case danger
        case hydration

        var textColor: (AppThemeColors) -> Color {
            switch self {
            case .neutral: return { $0.textSecondary }
            case .accent: return { $0.textAccent }
            case .success: return { $0.textSuccess }
            case .warning: return { $0.textWarning }
            case .danger: return { $0.textDanger }
            case .hydration: return { $0.textHydration }
            }
        }

        var fillColor: (AppThemeColors) -> Color {
            switch self {
            case .neutral: return { $0.cardBackgroundElevated }
            case .accent: return { $0.accentSurface }
            case .success: return { $0.success.opacity(0.14) }
            case .warning: return { $0.warning.opacity(0.14) }
            case .danger: return { $0.danger.opacity(0.14) }
            case .hydration: return { $0.hydration.opacity(0.14) }
            }
        }
    }

    let title: String
    let systemImage: String?
    let role: Role

    init(_ title: String, systemImage: String? = nil, role: Role = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppTypography.badge)
            }
            Text(title)
                .font(AppTypography.badge)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(role.textColor(appTheme.colors))
        .padding(.horizontal, appTheme.metrics.spacing8)
        .padding(.vertical, 5)
        .background(role.fillColor(appTheme.colors), in: Capsule())
    }
}
