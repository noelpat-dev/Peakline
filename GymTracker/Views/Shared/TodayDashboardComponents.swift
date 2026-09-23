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

    let scoreText: String
    let scoreValue: Int?
    let status: String
    let summary: String
    let coverage: String
    let isProvisional: Bool
    let signals: [(label: String, value: String?)]
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
                HStack(alignment: .firstTextBaseline, spacing: appTheme.metrics.spacing8) {
                    Text(status)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: appTheme.metrics.spacing8)

                    if isProvisional {
                        Text("Provisional")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .accessibilityIdentifier("readiness-provisional-status")
                    }
                }

                if !summary.isEmpty {
                    Text(summary)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let scoreValue {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("READINESS")
                            .modifier(AppTypography.waypointLabel)
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Spacer(minLength: appTheme.metrics.spacing8)

                        Text(scoreText)
                            .modifier(AppTypography.instrumentLarge)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .accessibilityIdentifier("today-readiness-score-value")

                        Text("/100")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }

                    InstrumentGauge(value: scoreValue)

                    if !signals.isEmpty {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(signals.prefix(3).enumerated()), id: \.offset) { index, signal in
                                if index > 0 {
                                    Rectangle()
                                        .fill(appTheme.colors.textTertiary.opacity(0.72))
                                        .frame(width: 0.5, height: 36)
                                        .padding(.horizontal, appTheme.metrics.spacing10)
                                        .accessibilityHidden(true)
                                }

                                VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                                    Text(signal.value ?? "+ LOG")
                                        .modifier(AppTypography.instrumentValue)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)

                                    Text(signal.label.uppercased())
                                        .modifier(AppTypography.waypointLabelSmall)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    Text(scoreText)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .accessibilityIdentifier("today-readiness-score-value")
                }

                HStack(alignment: .center, spacing: appTheme.metrics.spacing10) {
                    Image(systemName: "chart.bar.fill")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .accessibilityHidden(true)

                    Text(coverage)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("readiness-signal-coverage")

                    Spacer(minLength: appTheme.metrics.spacing8)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Coach")
        .accessibilityIdentifier("today-readiness-hero")
    }
}

/// Keeps the shared CampSuppliesRow appearance while assigning each existing
/// Today quick-action identifier to an individually tappable accessibility button.
struct TodayCampSuppliesRow: View {
    @Environment(\.appTheme) private var appTheme

    let items: [(symbol: String, caption: String, value: String?, identifier: String)]
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { element in
                let index = element.offset
                let item = element.element

                if index > 0 {
                    Rectangle()
                        .fill(appTheme.colors.textTertiary.opacity(0.72))
                        .frame(width: 0.5, height: 44)
                        .accessibilityHidden(true)
                }

                CampSuppliesRow(
                    items: [(symbol: item.symbol, caption: item.caption, value: item.value)],
                    onTap: { _ in onTap(index) }
                )
                .frame(maxWidth: .infinity)
                .accessibilityRepresentation {
                    Button {
                        onTap(index)
                    } label: {
                        Text(item.caption)
                    }
                    .accessibilityLabel(
                        item.value.map { "\(item.caption), \($0)" } ?? "\(item.caption), no log"
                    )
                    .accessibilityHint(item.value == nil ? "Add a log" : "Opens \(item.caption)")
                    .accessibilityIdentifier(item.identifier)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        value: String,
        detail: String,
        footer: String? = nil,
        isMetric: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.detail = detail
        self.footer = footer
        self.isMetric = isMetric
        self.isEnabled = isEnabled
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
                        .foregroundStyle(appTheme.colors.textPrimary)
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            isEnabled
                ? "Opens \(title)"
                : "Unavailable until a workout plan is available"
        )
    }

    private var valueFont: Font {
        isMetric
            ? AppTypography.largeMetric
            : AppTypography.compactCardTitle
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
                        .foregroundStyle(appTheme.colors.textPrimary)

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
                    .fill(isComplete ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated)
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
                                    ? appTheme.colors.accent.opacity(0.16)
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
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityHint(
            isEnabled
                ? "Opens your prepared workout preview"
                : "Unavailable until an active split is available"
        )
        .accessibilityIdentifier("today-review-plan")
    }
}

private struct TodaySummitPreviewGallery: View {
    private enum Scene: String, CaseIterable {
        case baseCamp
        case clear
        case changeable
        case storm
        case afterTraining
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                ForEach(Scene.allCases, id: \.self) { scene in
                    previewScene(scene)
                }
            }
            .padding(20)
        }
        .background(Color.clear)
    }

    private func previewScene(_ scene: Scene) -> some View {
        let isBaseCamp = scene == .baseCamp
        let isAfterTraining = scene == .afterTraining
        let condition: SummitCondition = switch scene {
        case .storm: .storm
        case .changeable: .changeable
        default: .clear
        }
        let score: Int? = switch scene {
        case .baseCamp: nil
        case .clear: 88
        case .changeable: 63
        case .storm: 38
        case .afterTraining: 82
        }
        let headline = switch scene {
        case .baseCamp: "Pack for the climb"
        case .clear: "Clear skies"
        case .changeable: "Changeable"
        case .storm: "Storm warning"
        case .afterTraining: "Clear skies"
        }
        let advice = switch scene {
        case .baseCamp: "3 of 5 supplies packed."
        case .clear: "Good climbing weather. Train as planned."
        case .changeable: "Steady climb. Train as planned, skip the max attempts."
        case .storm: "Stay at base camp. Mobility or an easy walk today."
        case .afterTraining: "Good climbing weather. Train as planned."
        }
        let load: [Double] = isBaseCamp ? Array(repeating: 0, count: 7) : [0.25, 0, 0.5, 0, 0, 1, 0.35]

        return TrailPage {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    SummitHorizonView(
                        week: load,
                        todayIndex: 2,
                        prDayIndex: isAfterTraining ? 5 : nil,
                        condition: condition,
                        timeOfDay: .day,
                        isEmpty: isBaseCamp,
                        animatesIntro: false
                    )
                    SummitHeaderOverlay(
                        title: "Peakline",
                        subtitle: "WED 23 SEP",
                        profileButton: Button(action: {}) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 28, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                    )
                }

                if isBaseCamp {
                    TrailSection(index: 1, label: "BASE CAMP") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pack for the climb")
                                .font(AppTypography.sectionTitle)
                            Text(advice)
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(.primary.opacity(0.55))
                                .frame(height: 2)
                            TrailStop(title: "Health connected", detail: "Sleep signal available", done: true)
                            TrailStop(title: "Split chosen", detail: "Choose a training split")
                            TrailStop(title: "First water logged", detail: "Log your first glass")
                            TrailStop(title: "First workout", detail: "Start your first workout")
                            TrailStop(title: "Sleep goal set", detail: "Choose a nightly target")
                        }
                    }
                    TrailSection(index: 2, label: "YOUR FIRST CLIMB") {
                        TrailStop(title: "Choose your first split", detail: "Set up a training split to prepare your first climb.")
                        SummitPrimaryButton(title: "Start your first climb", action: {})
                    }
                } else {
                    TrailSection(index: 1, label: "SUMMIT CONDITIONS") {
                        TodayReadinessHero(
                            scoreText: score.map(String.init) ?? "Not available",
                            scoreValue: score,
                            status: headline,
                            summary: advice,
                            coverage: "4 of 5 signals included",
                            isProvisional: scene == .changeable,
                            signals: [("Sleep", "7h 42m"), ("Training", "76/100"), ("Water", "1.8 L")],
                            action: {}
                        )
                    }

                    TrailSection(index: 2, label: "TODAY'S ROUTE") {
                        if isAfterTraining {
                            HStack(spacing: 8) {
                                Image(systemName: "flag.fill").foregroundStyle(.orange)
                                Text("Summit reached").font(AppTypography.sectionTitle)
                                Spacer()
                                Text("Finished 17:42").font(AppTypography.metadata)
                            }
                            TrailStop(title: "Time", detail: "54 min")
                            TrailStop(title: "Volume", detail: "8,240 kg")
                            TrailStop(title: "Top PR", detail: "No PR logged")
                            Text("Hydration goal met. Aim for 8h of sleep tonight.")
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Text("Push A").font(AppTypography.sectionTitle)
                                Spacer()
                                Text("6 LIFTS · ~55 MIN").modifier(AppTypography.instrumentValue)
                            }
                            TrailStop(title: "Bench Press", detail: "60 kg × 8 reps")
                            TrailStop(title: "Incline Dumbbell Press", detail: "22 kg × 10 reps")
                            TrailStop(title: "+ 4 more", detail: "Lateral Raise · Triceps Pushdown · Pec Deck · Plank")
                            if scene == .clear {
                                TrailSignTag(text: "PR ATTEMPT")
                            }
                            SummitPrimaryButton(title: "Start Push A", action: {})
                                .accessibilityIdentifier("today-review-plan")
                        }
                    }

                    TrailSection(index: 3, label: "CAMP SUPPLIES") {
                        CampSuppliesRow(items: [
                            (symbol: "tent", caption: "Sleep", value: "7h 42m"),
                            (symbol: "waterbottle", caption: "Water", value: "1.8 L"),
                            (symbol: "flame", caption: "Fuel", value: nil)
                        ])
                    }
                }

                TrailSection(index: 4, label: "THIS WEEK") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(isBaseCamp ? "0/7" : "3/7").modifier(AppTypography.instrumentLarge)
                        Text("days").font(AppTypography.body).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview("Today Summit · All states · Light") {
    TodaySummitPreviewGallery()
        .preferredColorScheme(.light)
}

#Preview("Today Summit · All states · Dark") {
    TodaySummitPreviewGallery()
        .preferredColorScheme(.dark)
}
