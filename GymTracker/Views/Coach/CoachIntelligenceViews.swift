import SwiftData
import SwiftUI

struct CoachBriefCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let readiness: ReadinessScore
    let viewBrief: () -> Void
    let editCheckIn: () -> Void

    var body: some View {
        FitnessInformationalActionCard {
            HStack(alignment: .center, spacing: 14) {
                readinessScoreBlock

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 5) {
                    readinessBadge
                    if readiness.isProvisional {
                        Text(readiness.coverageSummary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("readiness-signal-coverage")
                    } else {
                        Text(readiness.confidence.displayName)
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(readiness.recommendation.title)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(readiness.recommendation.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(readiness.topFactors) { factor in
                    ReadinessMiniFactorRow(factor: factor)
                }
            }
        } action: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    viewBriefButton
                    checkInButton
                }

                VStack(spacing: 10) {
                    viewBriefButton
                    checkInButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var readinessScoreBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            AnimatedMetricNumber(value: Double(readiness.value))
                .font(AppTypography.heroTitle)
                .foregroundStyle(scoreColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .animation(
                    AppMotion.animation(for: .metricChange, reduceMotion: reduceMotion),
                    value: readiness.value
                )
                .accessibilityIdentifier("today-readiness-score-value")

            Text("/100")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness score")
        .accessibilityValue("\(readiness.value) out of 100")
    }

    private var readinessBadge: some View {
        Label(readiness.isProvisional ? "Provisional" : readiness.category.displayName, systemImage: readinessCategoryImage)
            .font(AppTypography.chip)
            .foregroundStyle(scoreColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(scoreColor.opacity(0.14), in: Capsule())
            .accessibilityLabel(readiness.isProvisional ? "Provisional" : "Readiness category \(readiness.category.displayName)")
            .accessibilityIdentifier("readiness-provisional-status")
    }

    private var viewBriefButton: some View {
        Button {
            viewBrief()
        } label: {
            Label("View brief", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
        .accessibilityIdentifier("today-coach-brief-open")
    }

    @ViewBuilder
    private var checkInButton: some View {
        if readiness.hasCompletedTodayCheckIn {
            Button {
                presentCheckIn()
            } label: {
                Label("Edit check-in", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeutralFitnessButtonStyle())
            .accessibilityIdentifier("today-check-in-open")
        } else {
            Button {
                presentCheckIn()
            } label: {
                Label("Check in", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
            .accessibilityIdentifier("today-check-in-open")
        }
    }

    private func presentCheckIn() {
        AppHaptics.prepareSelection()
        AppHaptics.selection()
        PerformanceTracer.mark(.checkInSheetPresentation, "requested source=today")
        PerformanceTracer.trace(.motionTapFeedback) {
            editCheckIn()
        }
    }

    private var scoreColor: Color {
        readiness.isProvisional
            ? appTheme.colors.accent
            : readinessColor(for: readiness.category, theme: appTheme)
    }

    private var readinessCategoryImage: String {
        switch readiness.category {
        case .peak:
            return "arrow.up.circle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .cautious:
            return "exclamationmark.circle.fill"
        case .low:
            return "arrow.down.circle.fill"
        case .recovery:
            return "leaf.fill"
        }
    }
}

struct TrainingCallAuditCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: TrainingCallSnapshot
    var title: String = "Why this call?"
    var isExpandable = false
    var showsReason = true

    @Binding private var isExpanded: Bool

    init(
        snapshot: TrainingCallSnapshot,
        title: String = "Why this call?",
        isExpandable: Bool = false,
        showsReason: Bool = true,
        expanded: Binding<Bool>? = nil
    ) {
        self.snapshot = snapshot
        self.title = title
        self.isExpandable = isExpandable
        self.showsReason = showsReason
        _isExpanded = expanded ?? .constant(!isExpandable)
    }

    var body: some View {
        if isExpandable {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    AppHaptics.selection()
                    withAnimation(AppMotion.animation(for: .secondaryAction, reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    FitnessCard { headerContent }
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Double tap to hide coaching evidence." : "Double tap to show coaching evidence.")
                .accessibilityIdentifier("coach-why-this-toggle")

                if isExpanded {
                    FitnessCard { details }
                        .accessibilityElement(children: .contain)
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    headerContent
                    details
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(snapshot.headline). \(snapshot.reason)")
        }
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            FitnessIconBadge(
                systemImage: snapshot.recommendedMode.systemImage,
                size: 42,
                tint: accent,
                background: accent.opacity(0.14)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                if isExpandable {
                    Text(snapshot.confidence.displayName)
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(accent)
                } else {
                    Text("\(snapshot.headline) - \(snapshot.confidence.displayName)")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if isExpandable {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .frame(width: 44, height: 44)
            } else {
                CoachBadgeView(state: badgeState)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsReason {
                Text(snapshot.reason)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let targetSummary = snapshot.targetSummary {
                Label(targetSummary, systemImage: "target")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !snapshot.auditSignals.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Signals used")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .textCase(.uppercase)

                    ForEach(snapshot.auditSignals, id: \.self) { signal in
                        TrainingCallAuditLine(text: signal, systemImage: "checkmark.circle")
                    }
                }
            }

            if !snapshot.missingOrStaleInputs.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What would improve this call")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .textCase(.uppercase)

                    ForEach(snapshot.missingOrStaleInputs, id: \.self) { input in
                        TrainingCallAuditLine(text: input, systemImage: "exclamationmark.circle")
                    }
                }
            }
        }
    }

    private var accent: Color {
        if snapshot.isConservative {
            return appTheme.colors.warning
        }

        switch snapshot.action {
        case .push:
            return appTheme.colors.success
        case .recover:
            return appTheme.colors.warning
        case .repeatTarget, .rebalance, .buildBaseline:
            return appTheme.colors.accent
        }
    }

    private var badgeState: CoachBadgeState {
        switch snapshot.action {
        case .push:
            return snapshot.recommendedMode == .heavy ? .increaseLoad : .ready
        case .recover:
            return .recovery
        case .repeatTarget:
            return .repeatTarget
        case .rebalance:
            return .missedSplit
        case .buildBaseline:
            return .baseline
        }
    }
}

private struct TrainingCallAuditLine: View {
    @Environment(\.appTheme) private var appTheme

    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(AppTypography.metadata)
            .foregroundStyle(appTheme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ReadinessDetailHeaderCard: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: ReadinessScore

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        scoreArc
                        headerText
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        scoreArc
                        headerText
                    }
                }

                Text(readiness.confidenceNote)
                    .font(.footnote)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("readiness-provisional-status")
            }
        }
    }

    private var scoreArc: some View {
        ProgressArcView(
            value: Double(readiness.value) / 100.0,
            label: "Readiness",
            caption: readiness.category.displayName
        )
        .accessibilityLabel("Readiness score \(readiness.value) out of 100, \(readiness.category.displayName)")
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(readiness.recommendation.title)
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                readiness.isProvisional
                    ? "\(readiness.category.displayName) score range; training guidance waits for more evidence."
                    : readiness.category.meaning
            )
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(readinessColor(for: readiness.category, theme: appTheme))

            Text(readiness.recommendation.summary)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ReadinessRecommendationCard: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: ReadinessScore

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(readiness.recommendation.title, systemImage: "sparkles")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(readiness.recommendation.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !readiness.recommendation.reasonBullets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(readiness.recommendation.reasonBullets, id: \.self) { reason in
                            Label(reason, systemImage: "checkmark.circle")
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !readiness.recommendation.suggestedActions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Suggested actions")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        ForEach(readiness.recommendation.suggestedActions, id: \.self) { action in
                            Text(action)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(appTheme.colors.textPrimary)
                        }
                    }
                }
            }
        }
    }
}

struct ReadinessFactorCard: View {
    @Environment(\.appTheme) private var appTheme

    let factor: ReadinessFactor

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(
                    systemImage: factor.kind.systemImage,
                    size: 40,
                    tint: impactColor,
                    background: impactColor.opacity(0.14)
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(factor.kind.displayName)
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        if let score = factor.score {
                            Text("\(score)")
                                .font(AppTypography.eyebrow)
                                .foregroundStyle(impactColor)

                            Text(contributionText)
                                .font(AppTypography.chip)
                                .foregroundStyle(impactColor)
                                .accessibilityIdentifier("readiness-factor-\(factor.kind.rawValue)-contribution")
                        } else {
                            Text("Not included")
                                .font(AppTypography.chip)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .accessibilityIdentifier("readiness-factor-\(factor.kind.rawValue)-availability")
                        }
                    }

                    Text(factor.title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(factor.detail)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readiness-factor-\(factor.kind.rawValue)")
    }

    private var impactColor: Color {
        color(for: factor.impact, theme: appTheme)
    }

    private var contributionText: String {
        let value = factor.contribution.formatted(.number.precision(.fractionLength(1)))
        return "\(factor.contribution > 0 ? "+" : "")\(value) pts"
    }
}

struct ReadinessContextCard: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: ReadinessScore
    let focus: ReadinessFactorKind
    let title: String

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(
                    systemImage: focus.systemImage,
                    size: 40,
                    tint: focusFactor.map { color(for: $0.impact, theme: appTheme) } ?? appTheme.colors.accent
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(focusFactor?.detail ?? readiness.recoveryNote)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        readiness.isProvisional
                            ? "Daily readiness \(readiness.value) - Provisional"
                            : "Daily readiness \(readiness.value) - \(readiness.category.displayName)"
                    )
                        .font(AppTypography.chip)
                        .foregroundStyle(readinessColor(for: readiness.category, theme: appTheme))
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var focusFactor: ReadinessFactor? {
        readiness.factors.first { $0.kind == focus }
    }
}

struct WeeklyInsightPreviewCard: View {
    @Environment(\.appTheme) private var appTheme

    let snapshot: CoachIntelligenceSnapshot
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            FitnessCard(style: .compact) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "chart.line.uptrend.xyaxis", size: 40)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weekly insight")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        Text(primaryInsight.title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(primaryInsight.summary)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel("Weekly insight. \(primaryInsight.title). \(primaryInsight.summary)")
    }

    private var primaryInsight: CoachIntelligenceInsight {
        snapshot.insights.first ?? CoachIntelligenceInsight(
            id: "empty",
            title: "Coach baseline is building",
            summary: "Keep logging workouts and recovery basics to unlock weekly patterns.",
            category: .habit,
            severity: .neutral,
            confidence: .low,
            supportingFactors: [],
            recommendedAction: "Keep logging consistently.",
            relatedArea: nil
        )
    }
}

struct WeeklyCoachSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let summary: WeeklyCoachSummary

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Weekly Summary")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        Text(summary.recommendedFocus)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(summary.recoveryTrend.displayName)
                        .font(AppTypography.chip)
                        .foregroundStyle(trendColor(summary.recoveryTrend))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(trendColor(summary.recoveryTrend).opacity(0.14), in: Capsule())
                }

                HStack(spacing: 10) {
                    MetricTile(
                        label: "Avg Ready",
                        value: summary.averageReadiness.map { "\($0)" } ?? "--",
                        caption: "Last 7 days",
                        systemImage: "gauge.with.dots.needle.bottom.50percent"
                    )

                    MetricTile(
                        label: "Sessions",
                        value: "\(summary.trainingSessionsCompleted)",
                        caption: "Last 7 days",
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(summary.topPositiveFactor, systemImage: "plus.circle.fill")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSuccess)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(summary.topLimitingFactor, systemImage: "minus.circle.fill")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func trendColor(_ direction: CoachTrendDirection) -> Color {
        switch direction {
        case .improving:
            return appTheme.colors.success
        case .stable, .insufficientData:
            return appTheme.colors.textTertiary
        case .declining:
            return appTheme.colors.warning
        }
    }
}

struct CoachInsightsFeedView: View {
    let insights: [CoachIntelligenceInsight]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(insights) { insight in
                CoachInsightRow(insight: insight)
            }
        }
    }
}

struct CoachInsightRow: View {
    @Environment(\.appTheme) private var appTheme

    let insight: CoachIntelligenceInsight

    var body: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: insight.category.systemImage,
                        size: 40,
                        tint: severityColor,
                        background: severityColor.opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(insight.category.displayName)
                                .font(AppTypography.chip)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(insight.confidence.displayName)
                                .font(AppTypography.badge)
                                .foregroundStyle(appTheme.colors.textTertiary)
                        }

                        Text(insight.title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                Text(insight.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.supportingFactors.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(insight.supportingFactors.prefix(3), id: \.self) { factor in
                            Label(factor, systemImage: "smallcircle.filled.circle")
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(insight.recommendedAction)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.category.displayName) insight. \(insight.title). \(insight.summary). \(insight.recommendedAction)")
    }

    private var severityColor: Color {
        switch insight.severity {
        case .positive:
            return appTheme.colors.success
        case .neutral:
            return appTheme.colors.accent
        case .caution:
            return appTheme.colors.warning
        case .important:
            return appTheme.colors.danger
        }
    }
}

struct FatigueRiskCard: View {
    @Environment(\.appTheme) private var appTheme

    let risk: CoachFatigueRisk

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: "bolt.slash.fill",
                        size: 42,
                        tint: levelColor,
                        background: levelColor.opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(risk.title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(risk.level.displayName) fatigue signal - \(risk.confidence.displayName.lowercased())")
                            .font(AppTypography.chip)
                            .foregroundStyle(levelColor)
                    }

                    Spacer(minLength: 8)
                }

                Text(risk.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(risk.factors.prefix(3), id: \.self) { factor in
                        Label(factor, systemImage: "checkmark.circle")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(risk.recommendedAction)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        switch risk.level {
        case .low:
            return appTheme.colors.success
        case .moderate, .high:
            return appTheme.colors.warning
        case .deloadWatch:
            return appTheme.colors.danger
        }
    }
}

struct MuscleFatigueMapCard: View {
    @Environment(\.appTheme) private var appTheme

    let items: [MuscleGroupFatigue]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Coaching guidance only. Use this to plan warm-ups and volume, not as an injury signal.")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: item.state))
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.muscleGroup.displayName)
                                    .font(AppTypography.chip)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(item.state.displayName)
                                    .font(AppTypography.badge)
                                    .foregroundStyle(color(for: item.state))
                            }

                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous))
                        .accessibilityLabel("\(item.muscleGroup.displayName), \(item.state.displayName). \(item.detail)")
                    }
                }
            }
        }
    }

    private func color(for state: MuscleFatigueState) -> Color {
        switch state {
        case .fresh:
            return appTheme.colors.success
        case .normal:
            return appTheme.colors.accent
        case .loaded:
            return appTheme.colors.warning
        case .fatigued:
            return appTheme.colors.danger
        case .unknown:
            return appTheme.colors.textTertiary
        }
    }
}

struct LiftProgressInsightsCard: View {
    @Environment(\.appTheme) private var appTheme

    let insights: [LiftProgressInsight]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(insights) { insight in
                FitnessCard(style: .compact) {
                    HStack(alignment: .top, spacing: 12) {
                        FitnessIconBadge(
                            systemImage: icon(for: insight.state),
                            size: 40,
                            tint: color(for: insight.state),
                            background: color(for: insight.state).opacity(0.14)
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(insight.exerciseName)
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(insight.summary)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(insight.recommendation)
                                .font(AppTypography.chip)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)
                    }
                }
            }
        }
    }

    private func icon(for state: LiftProgressState) -> String {
        switch state {
        case .improving:
            return "arrow.up.right"
        case .steady:
            return "equal"
        case .declining:
            return "arrow.down.right"
        }
    }

    private func color(for state: LiftProgressState) -> Color {
        switch state {
        case .improving:
            return appTheme.colors.success
        case .steady:
            return appTheme.colors.warning
        case .declining:
            return appTheme.colors.danger
        }
    }
}

struct CoachHabitContributorsCard: View {
    @Environment(\.appTheme) private var appTheme

    let trends: CoachTrendSummary

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(habitTrends, id: \.title) { trend in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: trend.direction))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(color(for: trend.direction))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(trend.title)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(trend.summary)
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)
                    }
                }
            }
        }
    }

    private var habitTrends: [CoachTrend] {
        [
            trends.sleepDuration,
            trends.hydrationConsistency,
            trends.nutritionConsistency,
            trends.energy,
            trends.stress
        ]
    }

    private func icon(for direction: CoachTrendDirection) -> String {
        switch direction {
        case .improving:
            return "arrow.up.right"
        case .stable:
            return "equal"
        case .declining:
            return "arrow.down.right"
        case .insufficientData:
            return "ellipsis"
        }
    }

    private func color(for direction: CoachTrendDirection) -> Color {
        switch direction {
        case .improving:
            return appTheme.colors.success
        case .stable:
            return appTheme.colors.accent
        case .declining:
            return appTheme.colors.warning
        case .insufficientData:
            return appTheme.colors.textTertiary
        }
    }
}

struct DailyCheckInDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    let presentationRequestedAt: Date
    let existingCheckInID: UUID?
    let date: Date
    let energy: Int
    let soreness: Int
    let stress: Int
    let motivation: Int
    let note: String

    init(date: Date = .now, existingCheckIn: DailyCoachCheckInSnapshot?) {
        presentationRequestedAt = .now
        existingCheckInID = existingCheckIn?.id
        self.date = existingCheckIn?.date ?? Calendar.current.startOfDay(for: date)
        energy = existingCheckIn?.energy ?? 3
        soreness = existingCheckIn?.soreness ?? 3
        stress = existingCheckIn?.stress ?? 3
        motivation = existingCheckIn?.motivation ?? 3
        note = existingCheckIn?.note ?? ""
    }
}

struct DailyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let draft: DailyCheckInDraft

    @State private var energy: Int
    @State private var soreness: Int
    @State private var stress: Int
    @State private var motivation: Int
    @State private var note: String
    @State private var errorText: String?
    @State private var hasAppeared = false

    init(draft: DailyCheckInDraft) {
        self.draft = draft
        _energy = State(initialValue: draft.energy)
        _soreness = State(initialValue: draft.soreness)
        _stress = State(initialValue: draft.stress)
        _motivation = State(initialValue: draft.motivation)
        _note = State(initialValue: draft.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            fixedHeader
            checkInDivider

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    sheetHeader
                    ratingsCard
                    noteCard

                    if let errorText {
                        Text(errorText)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textDanger)
                    }

                    Button {
                        save()
                    } label: {
                        Label(draft.existingCheckInID == nil ? "Save check-in" : "Update check-in", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                }
                .padding(.horizontal, appTheme.metrics.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .peaklineKeyboardDismissal()
        .onAppear {
            hasAppeared = true
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let elapsedMilliseconds = max(
                0,
                Int(Date.now.timeIntervalSince(draft.presentationRequestedAt) * 1_000)
            )
            PerformanceTracer.mark(
                .checkInSheetPresentation,
                "stable_frame elapsed_ms=\(elapsedMilliseconds)"
            )
        }
        .accessibilityIdentifier("check-in-sheet")
    }

    private var fixedHeader: some View {
        ZStack {
            Text("Check-In")
                .font(AppTypography.cardTitle)
                .foregroundStyle(appTheme.colors.textPrimary)
                .accessibilityIdentifier("check-in-sheet-title")

            HStack {
                Spacer()

                Button("Done") {
                    PerformanceTracer.mark(.checkInSheetPresentation, "dismissed action=done")
                    dismiss()
                }
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textAccent)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("check-in-done")
            }
        }
        .padding(.horizontal, appTheme.metrics.screenPadding)
        .padding(.vertical, 8)
        .background(appTheme.colors.backgroundPrimary)
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            FitnessIconBadge(systemImage: "slider.horizontal.3", size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recovery Check-In")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Four quick inputs for today's coach brief.")
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ratingsCard: some View {
        CheckInFlatCard {
            VStack(alignment: .leading, spacing: 14) {
                CheckInRatingRow(title: "Energy", lowLabel: "Low", highLabel: "High", value: $energy, animationsEnabled: hasAppeared)
                checkInDivider
                CheckInRatingRow(title: "Soreness", lowLabel: "Low", highLabel: "High", value: $soreness, animationsEnabled: hasAppeared)
                checkInDivider
                CheckInRatingRow(title: "Stress", lowLabel: "Low", highLabel: "High", value: $stress, animationsEnabled: hasAppeared)
                checkInDivider
                CheckInRatingRow(title: "Motivation", lowLabel: "Low", highLabel: "High", value: $motivation, animationsEnabled: hasAppeared)
            }
        }
    }

    private var noteCard: some View {
        CheckInFlatCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional note")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                TextField("Anything affecting today?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .padding(12)
                    .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous))
            }
        }
    }

    private var checkInDivider: some View {
        Rectangle()
            .fill(appTheme.colors.cardBorder.opacity(0.7))
            .frame(height: 1)
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingCheckIn = existingCheckInModel() {
            existingCheckIn.update(
                energy: energy,
                soreness: soreness,
                stress: stress,
                motivation: motivation,
                note: trimmedNote
            )
        } else {
            modelContext.insert(
                DailyCoachCheckIn(
                    id: draft.existingCheckInID ?? UUID(),
                    date: draft.date,
                    energy: energy,
                    soreness: soreness,
                    stress: stress,
                    motivation: motivation,
                    note: trimmedNote
                )
            )
        }

        do {
            try modelContext.save()
            AppHaptics.success()
            PerformanceTracer.mark(.checkInSheetPresentation, "dismissed action=save")
            dismiss()
        } catch {
            errorText = "Could not save today's check-in."
        }
    }

    private func existingCheckInModel() -> DailyCoachCheckIn? {
        guard let existingCheckInID = draft.existingCheckInID else { return nil }
        let descriptor = FetchDescriptor<DailyCoachCheckIn>(
            predicate: #Predicate<DailyCoachCheckIn> { checkIn in
                checkIn.id == existingCheckInID
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }
}

private struct CheckInFlatCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: appTheme.metrics.compactCardRadius,
            style: .continuous
        )

        content
            .padding(appTheme.metrics.compactCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.cardBackground, in: shape)
            .overlay {
                shape
                    .stroke(appTheme.cardBorder.opacity(0.54), lineWidth: 1)
            }
            .contentShape(shape)
    }
}

private struct CheckInRatingRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int
    let animationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("check-in-title-\(identifierSuffix)")

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(AppTypography.metadata)
            .foregroundStyle(appTheme.colors.textTertiary)

            ratingButtons
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var ratingButtons: some View {
        HStack(spacing: 16) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    AppHaptics.selection()
                    let responseStartedAt = Date.now
                    PerformanceTracer.mark(
                        .motionCheckInSelect,
                        "requested row=\(identifierSuffix) value=\(rating)"
                    )
                    value = rating
                    DispatchQueue.main.async {
                        let elapsedMilliseconds = max(
                            0,
                            Int(Date.now.timeIntervalSince(responseStartedAt) * 1_000)
                        )
                        PerformanceTracer.mark(
                            .motionCheckInSelect,
                            "response_ms=\(elapsedMilliseconds) row=\(identifierSuffix) value=\(rating)"
                        )
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(rating <= value ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated)
                            .overlay {
                                Circle()
                                    .stroke(
                                        rating <= value
                                            ? appTheme.colors.accent.opacity(0.55)
                                            : appTheme.colors.cardBorder,
                                        lineWidth: 1
                                    )
                            }
                            .frame(width: 44, height: 44)

                        Text("\(rating)")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(rating <= value ? appTheme.colors.accentForeground : appTheme.colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("check-in-rating-\(identifierSuffix)-\(rating)")
                .accessibilityLabel("\(title) \(rating) of 5")
                .accessibilityValue(rating == value ? "Selected" : "Not selected")
                .accessibilityAddTraits(rating == value ? .isSelected : [])
            }
        }
        .animation(selectionAnimation, value: value)
    }

    private var selectionAnimation: Animation? {
        guard animationsEnabled, !reduceMotion else { return nil }
        return AppMotion.checkInSelect(reduceMotion: false)
    }

    private var identifierSuffix: String {
        title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

private struct ReadinessMiniFactorRow: View {
    @Environment(\.appTheme) private var appTheme

    let factor: ReadinessFactor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: factor.kind.systemImage)
                .font(AppTypography.chip)
                .foregroundStyle(color(for: factor.impact, theme: appTheme))
                .frame(width: 18)

            Text(factor.title)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func readinessColor(for category: ReadinessCategory, theme: AppTheme) -> Color {
    switch category {
    case .peak, .ready:
        return theme.colors.success
    case .cautious, .low:
        return theme.colors.warning
    case .recovery:
        return theme.colors.danger
    }
}

private func color(for impact: ReadinessImpact, theme: AppTheme) -> Color {
    switch impact {
    case .positive:
        return theme.colors.success
    case .neutral:
        return theme.colors.textTertiary
    case .negative:
        return theme.colors.warning
    }
}
