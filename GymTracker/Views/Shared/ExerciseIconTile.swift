import SwiftUI

enum ExerciseIconTileStyle {
    case compact
    case horizontal
    case hero
}

struct ExerciseIconTile: View {
    @Environment(\.appTheme) private var appTheme

    let iconKey: ExerciseIconKey
    let title: String?
    var size: CGFloat = 72
    var style: ExerciseIconTileStyle = .compact
    var tint: Color?

    private var tintColor: Color {
        tint ?? appTheme.colors.accent
    }

    var body: some View {
        Group {
            switch style {
            case .compact:
                VStack(spacing: 8) {
                    icon
                    titleText
                }
                .frame(width: size)
                .frame(minHeight: title == nil ? size : size + 28)
            case .horizontal:
                HStack(spacing: 12) {
                    icon
                    titleText
                    Spacer(minLength: 0)
                }
                .frame(minHeight: size)
            case .hero:
                VStack(alignment: .leading, spacing: 12) {
                    icon
                    titleText
                }
                .frame(maxWidth: .infinity, minHeight: size + 36, alignment: .leading)
            }
        }
        .padding(style == .compact ? appTheme.metrics.spacing8 : appTheme.metrics.spacing12)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous)
                .stroke(tintColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        ExerciseIconView(iconKey: iconKey, size: size, tint: tintColor, showBackground: true)
            .shadow(color: tintColor.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private var titleText: some View {
        if let title {
            Text(title)
                .font(style == .hero ? AppTypography.sectionTitle : AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }

    private var tileBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                appTheme.colors.cardBackgroundElevated,
                tintColor.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
