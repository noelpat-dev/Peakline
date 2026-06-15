import SwiftUI

enum FitnessCardStyle {
    case standard
    case compact
    case hero

    func padding(using metrics: AppThemeMetrics) -> CGFloat {
        switch self {
        case .standard:
            return metrics.standardCardPadding
        case .compact:
            return metrics.compactCardPadding
        case .hero:
            return metrics.heroCardPadding
        }
    }

    func cornerRadius(using metrics: AppThemeMetrics) -> CGFloat {
        switch self {
        case .standard:
            return metrics.standardCardRadius
        case .compact:
            return metrics.compactCardRadius
        case .hero:
            return metrics.heroCardRadius
        }
    }
}

struct FitnessCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme

    private let style: FitnessCardStyle
    private let customPadding: CGFloat?
    private let content: Content

    init(
        style: FitnessCardStyle = .standard,
        padding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.customPadding = padding
        self.content = content()
    }

    var body: some View {
        let metrics = appTheme.metrics
        let radius = style.cornerRadius(using: metrics)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(customPadding ?? style.padding(using: metrics))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.cardBackground, in: shape)
            .overlay {
                shape
                    .stroke(appTheme.cardBorder.opacity(borderOpacity), lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
            .contentShape(shape)
    }

    private var borderOpacity: Double {
        switch style {
        case .hero:
            return 0.72
        case .standard:
            return 0.62
        case .compact:
            return 0.54
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.055)
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .hero:
            return 18
        case .standard:
            return 10
        case .compact:
            return 6
        }
    }

    private var shadowYOffset: CGFloat {
        switch style {
        case .hero:
            return 10
        case .standard:
            return 5
        case .compact:
            return 3
        }
    }
}

struct FitnessScreen<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String?
    let subtitle: String?
    let systemImage: String?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                if let title {
                    FitnessScreenHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                }

                content
            }
            .padding(appTheme.metrics.screenPadding)
            .padding(.bottom, appTheme.metrics.screenBottomPadding)
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
    }
}

struct PrimaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.accentForeground)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? AppMotion.cardPressScale : 1))
            .animation(AppMotion.buttonPress(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct SecondaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accentSurface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? AppMotion.cardPressScale : 1))
            .animation(AppMotion.buttonPress(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct NeutralFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.elevatedCardBackground.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? AppMotion.cardPressScale : 1))
            .animation(AppMotion.buttonPress(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed && !reduceMotion ? -0.018 : 0)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? AppMotion.cardPressScale : 1))
            .animation(AppMotion.cardPress(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct FitnessIconBadge: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String
    var size: CGFloat = 42
    var tint: Color?
    var background: Color?

    var body: some View {
        let foreground = tint ?? appTheme.colors.accent

        Image(systemName: systemImage)
            .font(AppTypography.rounded(size: max(17, size * 0.42), weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background ?? badgeBackground(for: foreground), in: Circle())
            .accessibilityHidden(true)
    }

    private func badgeBackground(for foreground: Color) -> Color {
        tint == nil ? appTheme.colors.accentSurface : foreground.opacity(0.14)
    }
}

enum DashboardActionTileLayout: Equatable {
    case vertical
    case horizontal
}

struct DashboardActionTile: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    var status: String?
    var isEnabled = true
    var layout: DashboardActionTileLayout = .vertical
    var showsChevron = true
    var width: CGFloat?
    var minHeight: CGFloat = 142
    var iconSize: CGFloat?

    var body: some View {
        FitnessCard(style: .compact) {
            content
        }
        .frame(width: width)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .vertical:
            verticalContent
        case .horizontal:
            horizontalContent
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FitnessIconBadge(
                    systemImage: systemImage,
                    size: iconSize ?? appTheme.metrics.rowIconSize,
                    tint: iconTint,
                    background: iconBackground
                )

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
            }

            titleBlock(titleFont: AppTypography.compactCardTitle, subtitleFont: AppTypography.metadata)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: max(0, minHeight - appTheme.metrics.compactCardPadding * 2),
            alignment: .topLeading
        )
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 12) {
            FitnessIconBadge(
                systemImage: systemImage,
                size: iconSize ?? 44,
                tint: iconTint,
                background: iconBackground
            )

            titleBlock(titleFont: AppTypography.sectionTitle, subtitleFont: AppTypography.body)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: isEnabled ? "chevron.right" : "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleBlock(titleFont: Font, subtitleFont: Font) -> some View {
        VStack(alignment: .leading, spacing: layout == .vertical ? 4 : 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(isEnabled ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let status {
                    Text(status)
                        .font(AppTypography.badge)
                        .foregroundStyle(isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(statusBackground, in: Capsule())
                        .lineLimit(1)
                }
            }

            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconTint: Color {
        isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary
    }

    private var iconBackground: Color {
        isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated
    }

    private var statusBackground: Color {
        isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated
    }

    private var accessibilityLabel: String {
        if let status, !status.isEmpty {
            return "\(title), \(status)"
        }

        return title
    }
}

extension View {
    func destructiveSwipeAction(
        _ title: String = "Delete",
        allowsFullSwipe: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
            Button(role: .destructive) {
                AppHaptics.warning()
                action()
            } label: {
                Label(title, systemImage: "trash")
            }
        }
    }
}

struct FilterChip: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.metadataEmphasis)
                }
                Text(title)
                    .font(AppTypography.bodyEmphasis)
            }
            .padding(.horizontal, appTheme.metrics.chipHorizontalPadding)
            .padding(.vertical, appTheme.metrics.chipVerticalPadding)
            .foregroundStyle(isSelected ? appTheme.colors.accent : appTheme.colors.textSecondary)
            .background(isSelected ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? appTheme.colors.accent.opacity(0.32) : appTheme.cardBorder, lineWidth: 1)
            }
            .peaklineSelectionMotion(isSelected: isSelected, reduceMotion: reduceMotion, scale: 1.01)
        }
        .buttonStyle(.plain)
    }
}
