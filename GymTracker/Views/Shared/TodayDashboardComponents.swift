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

struct DashboardSection<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let usesSummitWaypointTitle: Bool
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        usesSummitWaypointTitle: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.usesSummitWaypointTitle = usesSummitWaypointTitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appTheme.metrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if usesSummitWaypointTitle {
                        Text(title)
                            .modifier(AppTypography.waypointLabel)
                            .accessibilityLabel(title)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        Text(title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                    }

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

    let scoreText: String
    let scoreValue: Int?
    let status: String
    let summary: String
    let coverage: String
    let isProvisional: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: appTheme.metrics.spacing8) {
                HStack(alignment: .top, spacing: appTheme.metrics.spacing8) {
                    Text(status)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(2)
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let scoreValue {
                    HStack(alignment: .center, spacing: appTheme.metrics.spacing6) {
                        Text("READINESS")
                            .modifier(AppTypography.waypointLabel)
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Text(scoreText)
                            .modifier(AppTypography.instrumentLarge)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityIdentifier("today-readiness-score-value")

                        Text("/100")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textTertiary)

                        Spacer(minLength: appTheme.metrics.spacing4)

                        TodayReadinessGauge(value: scoreValue)
                    }
                } else {
                    Text(scoreText)
                        .font(.system(size: 1))
                        .foregroundStyle(Color.clear)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(scoreText)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

private struct TodayReadinessGauge: View {
    @Environment(\.appTheme) private var appTheme
    let value: Int

    private var clampedValue: Int { min(max(value, 0), 100) }

    var body: some View {
        Canvas { context, size in
            let tickCount = 14
            let spacing: CGFloat = 2
            let tickWidth = (size.width - spacing * CGFloat(tickCount - 1)) / CGFloat(tickCount)

            for index in 0..<tickCount {
                let tallTick = index.isMultiple(of: 3)
                let tickHeight = tallTick ? size.height : size.height * 0.65
                let x = CGFloat(index) * (tickWidth + spacing)
                var tick = Path()
                tick.move(to: CGPoint(x: x + tickWidth / 2, y: size.height - tickHeight))
                tick.addLine(to: CGPoint(x: x + tickWidth / 2, y: size.height))
                context.stroke(
                    tick,
                    with: .color(appTheme.colors.textPrimary.opacity(
                        Double(index) * 100 / Double(tickCount) < Double(clampedValue) ? 0.95 : 0.18
                    )),
                    style: StrokeStyle(lineWidth: max(1, tickWidth), lineCap: .round)
                )
            }
        }
        .frame(width: 76, height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instrument gauge")
        .accessibilityValue("\(clampedValue) of 100")
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
                            TrailStop(title: "Choose a training split", detail: "Choose a training split")
                            TrailStop(title: "Log your first glass", detail: "Log your first glass")
                            TrailStop(title: "Start your first workout", detail: "Start your first workout")
                            TrailStop(title: "Choose a nightly target", detail: "Choose a nightly target")
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
