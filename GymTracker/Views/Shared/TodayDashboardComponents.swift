import SwiftUI

@MainActor
final class DashboardArrivalCoordinator: ObservableObject {
    @Published private(set) var isPresented = false

    private(set) var hasPlayed = false
    private var task: Task<Void, Never>?

    func start(itemCount: Int, reduceMotion: Bool) {
        guard !hasPlayed else { return }

        hasPlayed = true
        task?.cancel()

        guard !reduceMotion, itemCount > 0 else {
            isPresented = true
            task = nil
            return
        }

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isPresented = true
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if !isPresented {
            isPresented = true
        }
    }

    func isVisible(index _: Int) -> Bool {
        isPresented
    }
}

private struct DashboardArrivalModifier: ViewModifier {
    let isVisible: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : AppMotion.cardAppearOffset)
            .animation(
                AppMotion.staggeredAnimation(
                    for: .cardAppear,
                    index: index,
                    reduceMotion: reduceMotion
                ),
                value: isVisible
            )
    }
}

private struct TodayReentryWashModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: appTheme.metrics.standardCardRadius, style: .continuous)
                    .fill(appTheme.colors.accentSurface)
                    .opacity(isActive ? 0.72 : 0)
                    .allowsHitTesting(false)
            }
            .animation(
                .easeInOut(duration: AppMotion.todayReentryWashDuration),
                value: isActive
            )
    }
}

extension View {
    func dashboardArrival(isVisible: Bool, index: Int) -> some View {
        modifier(DashboardArrivalModifier(isVisible: isVisible, index: index))
    }

    func todayReentryWash(isActive: Bool) -> some View {
        modifier(TodayReentryWashModifier(isActive: isActive))
    }
}

struct DashboardHeaderView: View {
    @Environment(\.appTheme) private var appTheme

    let dateText: String
    let title: String?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateText)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)

            if let title, !title.isEmpty {
                Text(title)
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(subtitle)
                .font(AppTypography.screenSubtitle)
                .foregroundStyle(appTheme.colors.textTertiary)
                .lineLimit(1)
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
    let chips: [DashboardChip]
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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow)
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .textCase(.uppercase)

                    Text(splitName)
                        .font(AppTypography.heroTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .accessibilityIdentifier("today-suggested-split")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(reason)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let context, !context.isEmpty {
                        Text(context)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !chips.isEmpty {
                    Text(chips.map(\.title).joined(separator: PeaklineText.metadataSeparator))
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let actions: [QuickAction]

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

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
                        FitnessIconBadge(
                            systemImage: action.systemImage,
                            size: appTheme.metrics.rowIconSize,
                            tint: iconColor,
                            background: iconBackground
                        )

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(AppTypography.eyebrow)
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
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
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
                        .foregroundStyle(appTheme.colors.textAccent)
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
    let label: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        MetricTile(
            label: label,
            value: value,
            caption: caption,
            systemImage: systemImage
        )
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
                        .foregroundStyle(appTheme.colors.textAccent)
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
                            .frame(minHeight: appTheme.metrics.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textAccent)
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
