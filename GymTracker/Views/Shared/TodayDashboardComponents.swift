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
        appTheme.colors.accent
    }

    private var iconBackground: Color {
        appTheme.colors.accentSurface
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

// MARK: - Today redesign components

/// The primary Today decision card. Inputs are prepared values so the card can
/// render without reaching through to SwiftData or rebuilding a live snapshot.
struct TodayReadinessHero: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 48

    let scoreText: String
    let status: String
    let summary: String
    let coverage: String
    let isProvisional: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            FitnessCard(style: .hero, padding: appTheme.metrics.spacing16) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing8) {
                    HStack(alignment: .firstTextBaseline, spacing: appTheme.metrics.spacing8) {
                        Text("Readiness")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Spacer(minLength: appTheme.metrics.spacing8)

                        if isProvisional {
                            Text("Provisional")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .padding(.horizontal, appTheme.metrics.spacing10)
                                .padding(.vertical, appTheme.metrics.spacing6)
                                .background(
                                    appTheme.colors.cardBackgroundElevated,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(appTheme.colors.cardBorder.opacity(0.72), lineWidth: 0.75)
                                }
                                .accessibilityIdentifier("readiness-provisional-status")
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: appTheme.metrics.spacing6) {
                        Text(scoreText)
                            .font(AppTypography.rounded(size: scoreSize, weight: .heavy).monospacedDigit())
                            .foregroundStyle(scoreColor)
                            .lineLimit(1)
                            .accessibilityIdentifier("today-readiness-score-value")

                        Text("/100")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }

                    Text(status)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !summary.isEmpty {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .overlay(appTheme.colors.cardBorder.opacity(0.62))

                    HStack(alignment: .center, spacing: appTheme.metrics.spacing10) {
                        Image(systemName: "chart.bar.fill")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .accessibilityHidden(true)

                        Text(coverage)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("readiness-signal-coverage")

                        Spacer(minLength: appTheme.metrics.spacing8)

                        Image(systemName: "chevron.right")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityHint("Opens your readiness details")
        .accessibilityIdentifier("today-readiness-hero")
    }

    private var scoreColor: Color {
        scoreText == "—" ? appTheme.colors.textSecondary : appTheme.colors.textSuccess
    }
}

/// A compact, tappable Today tile for a prepared metric or next action.
struct TodayMetricCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    let value: String
    let detail: String
    let footer: String?
    let isMetric: Bool
    let highlightValue: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        value: String,
        detail: String,
        footer: String? = nil,
        isMetric: Bool = false,
        highlightValue: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.detail = detail
        self.footer = footer
        self.isMetric = isMetric
        self.highlightValue = highlightValue
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            FitnessCard(style: .compact, padding: appTheme.metrics.spacing14) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing6) {
                    HStack(alignment: .center, spacing: appTheme.metrics.spacing8) {
                        Image(systemName: systemImage)
                            .font(AppTypography.rounded(size: appTheme.metrics.spacing20, weight: .semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .frame(width: appTheme.metrics.spacing22, height: appTheme.metrics.spacing22, alignment: .leading)
                            .accessibilityHidden(true)

                        Spacer(minLength: appTheme.metrics.spacing8)

                        Text(title)
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }

                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        HStack(spacing: appTheme.metrics.spacing8) {
                            Text(detail)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if footer == nil {
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.metadataEmphasis)
                                    .foregroundStyle(appTheme.colors.textTertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }

                    if let footer, !footer.isEmpty {
                        Divider()
                            .overlay(appTheme.colors.cardBorder.opacity(0.58))

                        HStack(alignment: .center, spacing: appTheme.metrics.spacing8) {
                            Text(footer)
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: appTheme.metrics.spacing4)

                            Image(systemName: "chevron.right")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: dynamicTypeSize.isAccessibilitySize
                        ? appTheme.metrics.metricTileMinHeight + appTheme.metrics.spacing16
                        : appTheme.metrics.metricTileMinHeight,
                    alignment: .topLeading
                )
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }

    private var valueFont: Font {
        isMetric
            ? AppTypography.largeMetric
            : AppTypography.compactCardTitle
    }

    private var valueColor: Color {
        highlightValue ? appTheme.colors.textSuccess : appTheme.colors.textPrimary
    }
}

/// A compact seven day activity summary. The label intentionally describes
/// completed days rather than implying a streak or another derived measure.
struct TodayWeeklyActivityCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let completedDays: [Bool]
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            FitnessCard(style: .compact) {
                ViewThatFits(in: .horizontal) {
                    horizontalContent
                    verticalContent
                }
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly activity")
        .accessibilityValue("\(completedCount) of \(dayCount) days completed")
        .accessibilityHint("Opens your activity history")
        .accessibilityIdentifier("today-weekly-activity")
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: appTheme.metrics.spacing12) {
            Image(systemName: "calendar")
                .font(AppTypography.rounded(size: appTheme.metrics.spacing22, weight: .semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(width: appTheme.metrics.spacing28, height: appTheme.metrics.spacing28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                Text("Weekly activity")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: appTheme.metrics.spacing6) {
                    Text("\(completedCount)/\(dayCount)")
                        .font(AppTypography.workoutLargeNumber)
                        .foregroundStyle(appTheme.colors.textSuccess)

                    Text("days")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }

            Spacer(minLength: appTheme.metrics.spacing8)

            dayDots

            Image(systemName: "chevron.right")
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: appTheme.metrics.compactRowMinHeight, alignment: .leading)
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
            HStack(alignment: .center, spacing: appTheme.metrics.spacing12) {
                Image(systemName: "calendar")
                    .font(AppTypography.rounded(size: appTheme.metrics.spacing22, weight: .semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .frame(width: appTheme.metrics.spacing28, height: appTheme.metrics.spacing28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                    Text("Weekly activity")
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .textCase(.uppercase)

                    Text("\(completedCount) of \(dayCount) days completed")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                }

                Spacer(minLength: appTheme.metrics.spacing8)

                Image(systemName: "chevron.right")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .accessibilityHidden(true)
            }

            dayDots
        }
    }

    private var dayDots: some View {
        HStack(spacing: appTheme.metrics.spacing6) {
            ForEach(Array(completedDays.enumerated()), id: \.offset) { _, isComplete in
                Circle()
                    .fill(isComplete ? appTheme.colors.textSuccess : appTheme.colors.cardBackgroundElevated)
                    .frame(
                        width: dynamicTypeSize.isAccessibilitySize
                            ? appTheme.metrics.spacing14
                            : appTheme.metrics.spacing12,
                        height: dynamicTypeSize.isAccessibilitySize
                            ? appTheme.metrics.spacing14
                            : appTheme.metrics.spacing12
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                isComplete
                                    ? appTheme.colors.textSuccess.opacity(0.16)
                                    : appTheme.colors.cardBorder,
                                lineWidth: 0.75
                            )
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var completedCount: Int {
        completedDays.filter { $0 }.count
    }

    private var dayCount: Int {
        completedDays.count
    }
}

/// The monochrome entry point for the existing suggested session preview.
struct TodayPlanButton: View {
    @Environment(\.appTheme) private var appTheme

    var title: String = "Review Today’s Plan"
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: appTheme.metrics.spacing8) {
                Spacer(minLength: appTheme.metrics.spacing8)

                Label(title, systemImage: "list.bullet")

                Spacer(minLength: appTheme.metrics.spacing8)

                Image(systemName: "chevron.right")
                    .font(AppTypography.metadataEmphasis)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(NeutralFitnessButtonStyle())
        .disabled(!isEnabled)
        .accessibilityIdentifier("today-review-plan")
    }
}
