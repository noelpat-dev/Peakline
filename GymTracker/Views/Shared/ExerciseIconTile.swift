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
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous)
                .stroke(appTheme.colors.cardBorder.opacity(0.68), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        ExerciseIconView(
            iconKey: iconKey,
            size: size * 0.54,
            tint: tintColor,
            showBackground: false
        )
        .frame(width: size, height: size)
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
}
