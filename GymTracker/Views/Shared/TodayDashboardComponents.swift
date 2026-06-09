import SwiftUI

struct DashboardHeaderView: View {
    @Environment(\.appTheme) private var appTheme

    let dateText: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dateText)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)

                Text(title)
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(AppTypography.screenSubtitle)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "person.crop.circle.fill")
                .font(AppTypography.rounded(size: 25, weight: .semibold))
                .foregroundStyle(appTheme.colors.accent)
                .frame(width: 48, height: 48)
                .background(appTheme.colors.cardBackgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

struct DashboardChip: Identifiable, Hashable {
    let title: String
    let systemImage: String?

    var id: String {
        [title, systemImage ?? ""].joined(separator: "|")
    }

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }
}

struct HeroRecommendationCard: View {
    @Environment(\.appTheme) private var appTheme

    let eyebrow: String
    let splitName: String
    let reason: String
    let context: String?
    let iconKey: ExerciseIconKey
    let chips: [DashboardChip]
    let nextActionTitle: String
    let nextActionDetail: String
    let primaryTitle: String
    let secondaryTitle: String
    let primarySystemImage: String
    let secondarySystemImage: String
    let isPrimaryEnabled: Bool
    let isSecondaryEnabled: Bool
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(eyebrow)
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(splitName)
                            .font(AppTypography.heroTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .accessibilityIdentifier("today-suggested-split")
                    }

                    Spacer(minLength: 12)

                    ExerciseIconView(
                        iconKey: iconKey,
                        size: 62,
                        showBackground: true,
                        isDecorative: true
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(reason)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let context, !context.isEmpty {
                        Text(context)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: primarySystemImage)
                        .font(AppTypography.metadataEmphasis)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(appTheme.colors.accent)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Now")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(nextActionTitle)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(nextActionDetail)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, appTheme.metrics.spacing12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(appTheme.colors.accent)
                        .frame(width: 3)
                }

                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips) { chip in
                                DashboardMetadataChip(chip: chip)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .mask(Rectangle())
                    .accessibilityIdentifier("today-suggested-chips")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        heroPrimaryButton
                        heroSecondaryButton
                    }

                    VStack(spacing: 10) {
                        heroPrimaryButton
                        heroSecondaryButton
                    }
                }
            }
        }
    }

    private var heroPrimaryButton: some View {
        Button {
            AppHaptics.mediumImpact()
            primaryAction()
        } label: {
            Label(primaryTitle, systemImage: primarySystemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
        .disabled(!isPrimaryEnabled)
    }

    private var heroSecondaryButton: some View {
        Button {
            AppHaptics.selection()
            secondaryAction()
        } label: {
            Label(secondaryTitle, systemImage: secondarySystemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
        .disabled(!isSecondaryEnabled)
    }
}

struct QuickAction: Identifiable {
    let identifier: String?
    let title: String
    let subtitle: String
    let systemImage: String
    let style: QuickActionStyle
    let action: () -> Void

    var id: String {
        identifier ?? title
    }

    init(
        identifier: String? = nil,
        title: String,
        subtitle: String,
        systemImage: String,
        style: QuickActionStyle,
        action: @escaping () -> Void
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }
}

enum QuickActionStyle {
    case primary
    case neutral
    case calm
    case progress
    case hydration
}

struct QuickActionsGrid: View {
    let actions: [QuickAction]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(actions) { action in
                QuickActionTile(action: action)
            }
        }
    }
}

struct QuickActionTile: View {
    @Environment(\.appTheme) private var appTheme

    let action: QuickAction

    var body: some View {
        let identifier = action.identifier ?? "quick-action-\(action.title.lowercased().replacingOccurrences(of: " ", with: "-"))"

        Button {
            action.action()
        } label: {
            FitnessCard(style: .compact) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Image(systemName: action.systemImage)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(iconColor)
                            .frame(width: appTheme.metrics.rowIconSize, height: appTheme.metrics.rowIconSize)
                            .background(iconBackground, in: Circle())

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(AppTypography.compactCardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text(action.subtitle)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    private var iconColor: Color {
        switch action.style {
        case .hydration:
            return appTheme.colors.hydration
        case .primary, .progress:
            return appTheme.colors.accent
        case .neutral:
            return appTheme.colors.textPrimary
        case .calm:
            return appTheme.colors.textSecondary
        }
    }

    private var iconBackground: Color {
        switch action.style {
        case .hydration:
            return appTheme.colors.hydration.opacity(0.14)
        case .primary, .progress:
            return appTheme.colors.accentSurface
        case .neutral:
            return appTheme.colors.cardBackgroundElevated
        case .calm:
            return appTheme.colors.textSecondary.opacity(0.13)
        }
    }

    private var tileBorder: Color {
        switch action.style {
        case .hydration:
            return appTheme.colors.hydration.opacity(0.24)
        case .primary, .progress:
            return appTheme.colors.accent.opacity(0.22)
        case .neutral, .calm:
            return appTheme.colors.cardBorder
        }
    }
}

struct CoachInsightCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let recommendation: String
    let reason: String
    let badge: String
    let buttonTitle: String
    let isButtonEnabled: Bool
    let action: () -> Void

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "sparkles", size: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(recommendation)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(badge)
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(appTheme.colors.accentSurface, in: Capsule())
                        .lineLimit(1)
                }

                Text(reason)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    AppHaptics.selection()
                    action()
                } label: {
                    Label(buttonTitle, systemImage: "target")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .disabled(!isButtonEnabled)
            }
        }
    }
}

struct WeekMetricTile: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.accent)

                Text(value)
                    .font(AppTypography.largeMetric)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)

                    Text(caption)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        }
    }
}

struct SplitCoverageItem: Identifiable, Hashable {
    let name: String
    let isComplete: Bool

    var id: String {
        name
    }
}

struct SplitCoverageBarView: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let items: [SplitCoverageItem]

    var body: some View {
        FitnessCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(subtitle)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()

                    Text("\(completedCount)/\(items.count)")
                        .font(AppTypography.workoutNumber)
                        .foregroundStyle(appTheme.colors.accent)
                }

                HStack(spacing: 7) {
                    ForEach(items) { item in
                        Capsule()
                            .fill(item.isComplete ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated)
                            .frame(height: 10)
                            .overlay {
                                Capsule()
                                    .stroke(item.isComplete ? appTheme.colors.accent.opacity(0.15) : appTheme.colors.cardBorder, lineWidth: 1)
                            }
                    }
                }
                .accessibilityHidden(true)

                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Text(item.name)
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(item.isComplete ? appTheme.colors.textPrimary : appTheme.colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(completedCount) of \(items.count) splits completed")
    }

    private var completedCount: Int {
        items.filter(\.isComplete).count
    }
}

struct DashboardSection<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appTheme.metrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                Spacer()

                if let actionTitle, let action {
                    Button {
                        AppHaptics.selection()
                        action()
                    } label: {
                        Text(actionTitle)
                    }
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.accent)
                }
            }

            content
        }
    }
}

struct DashboardEmptyStateCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(systemImage: systemImage, size: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct DashboardMetadataChip: View {
    @Environment(\.appTheme) private var appTheme

    let chip: DashboardChip

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage = chip.systemImage {
                Image(systemName: systemImage)
                    .font(AppTypography.badge)
            }

            Text(chip.title)
                .font(AppTypography.chip)
                .lineLimit(1)
        }
        .foregroundStyle(appTheme.colors.textPrimary)
        .padding(.horizontal, appTheme.metrics.chipHorizontalPadding)
        .padding(.vertical, appTheme.metrics.chipVerticalPadding)
        .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
        .overlay {
            Capsule()
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }
}
