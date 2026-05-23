import SwiftData
import SwiftUI

struct CoachBriefCard: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: ReadinessScore
    let viewBrief: () -> Void
    let checkIn: () -> Void

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    readinessScoreBlock

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 8) {
                        readinessBadge
                        Text(readiness.confidence.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(readiness.recommendation.title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(readiness.recommendation.summary)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(readiness.topFactors) { factor in
                        ReadinessMiniFactorRow(factor: factor)
                    }
                }

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
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily Coach Brief. Readiness \(readiness.value), \(readiness.category.displayName). \(readiness.recommendation.title).")
    }

    private var readinessScoreBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(readiness.value)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("/100")
                .font(.headline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textTertiary)
        }
    }

    private var readinessBadge: some View {
        Label(readiness.category.displayName, systemImage: readinessCategoryImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(scoreColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(scoreColor.opacity(0.14), in: Capsule())
            .accessibilityLabel("Readiness category \(readiness.category.displayName)")
    }

    private var viewBriefButton: some View {
        Button(action: viewBrief) {
            Label("View brief", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    @ViewBuilder
    private var checkInButton: some View {
        if readiness.hasCompletedTodayCheckIn {
            Button(action: checkIn) {
                Label("Edit check-in", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeutralFitnessButtonStyle())
        } else {
            Button(action: checkIn) {
                Label("Check in", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
        }
    }

    private var scoreColor: Color {
        readinessColor(for: readiness.category, theme: appTheme)
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

                Text(readiness.confidence.note)
                    .font(.footnote)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .font(.title2.bold())
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(readiness.category.meaning)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readinessColor(for: readiness.category, theme: appTheme))

            Text(readiness.recommendation.summary)
                .font(.subheadline)
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
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(readiness.recommendation.summary)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !readiness.recommendation.reasonBullets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(readiness.recommendation.reasonBullets, id: \.self) { reason in
                            Label(reason, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !readiness.recommendation.suggestedActions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Suggested actions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        ForEach(readiness.recommendation.suggestedActions, id: \.self) { action in
                            Text(action)
                                .font(.subheadline.weight(.semibold))
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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        if let score = factor.score {
                            Text("\(score)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(impactColor)
                        }
                    }

                    Text(factor.title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(factor.detail)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var impactColor: Color {
        color(for: factor.impact, theme: appTheme)
    }
}

struct CheckInStatusCard: View {
    @Environment(\.appTheme) private var appTheme

    let checkIn: DailyCoachCheckIn?
    let action: () -> Void

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: checkIn == nil ? "slider.horizontal.3" : "checkmark.circle.fill",
                        size: 42
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkIn == nil ? "No check-in yet" : "Today's check-in complete")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(checkIn == nil ? "Add energy, soreness, stress, and motivation to sharpen the coach brief." : checkInSummary)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let note = checkIn?.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if checkIn == nil {
                    Button(action: action) {
                        Label("Check in", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                } else {
                    Button(action: action) {
                        Label("Edit check-in", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
    }

    private var checkInSummary: String {
        guard let checkIn else { return "" }
        return "Energy \(checkIn.energy)/5, soreness \(checkIn.soreness)/5, stress \(checkIn.stress)/5, motivation \(checkIn.motivation)/5."
    }
}

struct WorkoutReadinessBriefCard: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: ReadinessScore

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Readiness: \(readiness.value)")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(readiness.category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readinessColor(for: readiness.category, theme: appTheme))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(readinessColor(for: readiness.category, theme: appTheme).opacity(0.14), in: Capsule())

                    Spacer(minLength: 8)
                }

                Text(readiness.workoutAdjustment)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let top = readiness.topFactors.first {
                    Label(top.title, systemImage: top.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(color(for: top.impact, theme: appTheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workout readiness \(readiness.value), \(readiness.category.displayName). \(readiness.workoutAdjustment)")
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
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(focusFactor?.detail ?? readiness.recoveryNote)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Daily readiness \(readiness.value) - \(readiness.category.displayName)")
                        .font(.caption.weight(.semibold))
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
        Button(action: action) {
            FitnessCard(style: .compact) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "chart.line.uptrend.xyaxis", size: 40)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weekly insight")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        Text(primaryInsight.title)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(primaryInsight.summary)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        Text(summary.recommendedFocus)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(summary.recoveryTrend.displayName)
                        .font(.caption.weight(.semibold))
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
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.success)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(summary.topLimitingFactor, systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.warning)
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
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(insight.confidence.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textTertiary)
                        }

                        Text(insight.title)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.supportingFactors.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(insight.supportingFactors.prefix(3), id: \.self) { factor in
                            Label(factor, systemImage: "smallcircle.filled.circle")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(insight.recommendedAction)
                    .font(.subheadline.weight(.semibold))
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
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(risk.level.displayName) fatigue signal - \(risk.confidence.displayName.lowercased())")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(levelColor)
                    }

                    Spacer(minLength: 8)
                }

                Text(risk.summary)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(risk.factors.prefix(3), id: \.self) { factor in
                        Label(factor, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(risk.recommendedAction)
                    .font(.subheadline.weight(.semibold))
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
                    .font(.caption)
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
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(item.state.displayName)
                                    .font(.caption2.weight(.semibold))
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
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(insight.summary)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(insight.recommendation)
                                .font(.caption.weight(.semibold))
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

struct AdaptiveWorkoutGuidanceCard: View {
    @Environment(\.appTheme) private var appTheme

    let guidance: AdaptiveWorkoutGuidance

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: icon,
                        size: 42,
                        tint: modeColor,
                        background: modeColor.opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(guidance.title)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(guidance.readinessCategory.displayName) readiness - \(guidance.mode.displayName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(modeColor)
                    }

                    Spacer(minLength: 8)
                }

                Text(guidance.summary)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(guidance.fatigueContext)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(guidance.adjustmentChips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()

                Label("Advisory only. Workout plan stays unchanged.", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch guidance.mode {
        case .push:
            return "arrow.up.circle.fill"
        case .maintain:
            return "checkmark.circle.fill"
        case .reduce:
            return "arrow.down.circle.fill"
        case .recoveryFocus:
            return "leaf.fill"
        }
    }

    private var modeColor: Color {
        switch guidance.mode {
        case .push:
            return appTheme.colors.success
        case .maintain:
            return appTheme.colors.accent
        case .reduce:
            return appTheme.colors.warning
        case .recoveryFocus:
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
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color(for: trend.direction))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(trend.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(trend.summary)
                                .font(.caption)
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

struct DailyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let date: Date
    let existingCheckIn: DailyCoachCheckIn?

    @State private var energy: Int
    @State private var soreness: Int
    @State private var stress: Int
    @State private var motivation: Int
    @State private var note: String
    @State private var errorText: String?

    init(date: Date = .now, existingCheckIn: DailyCoachCheckIn?) {
        self.date = date
        self.existingCheckIn = existingCheckIn
        _energy = State(initialValue: existingCheckIn?.energy ?? 3)
        _soreness = State(initialValue: existingCheckIn?.soreness ?? 3)
        _stress = State(initialValue: existingCheckIn?.stress ?? 3)
        _motivation = State(initialValue: existingCheckIn?.motivation ?? 3)
        _note = State(initialValue: existingCheckIn?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Recovery Check-In",
                subtitle: "Four quick inputs for today's coach brief.",
                systemImage: "slider.horizontal.3"
            ) {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 18) {
                        CheckInRatingRow(title: "Energy", lowLabel: "Low", highLabel: "High", value: $energy)
                        CheckInRatingRow(title: "Soreness", lowLabel: "Low", highLabel: "High", value: $soreness)
                        CheckInRatingRow(title: "Stress", lowLabel: "Low", highLabel: "High", value: $stress)
                        CheckInRatingRow(title: "Motivation", lowLabel: "Low", highLabel: "High", value: $motivation)
                    }
                }

                FitnessCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional note")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        TextField("Anything affecting today?", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.danger)
                }

                Button(action: save) {
                    Label(existingCheckIn == nil ? "Save check-in" : "Update check-in", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
            .navigationTitle("Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingCheckIn {
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
                    date: date,
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
            dismiss()
        } catch {
            errorText = "Could not save today's check-in."
        }
    }
}

private struct CheckInRatingRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Spacer()

                Text("\(value)/5")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.accent)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(lowLabel)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textTertiary)

                    ratingButtons

                    Text(highLabel)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lowLabel)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textTertiary)

                        Spacer()

                        Text(highLabel)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }

                    ratingButtons
                }
            }
        }
    }

    private var ratingButtons: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    value = rating
                } label: {
                    Text("\(rating)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(rating <= value ? appTheme.colors.accentForeground : appTheme.colors.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(rating <= value ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(rating) of 5")
                .accessibilityAddTraits(rating == value ? .isSelected : [])
            }
        }
    }
}

private struct ReadinessMiniFactorRow: View {
    @Environment(\.appTheme) private var appTheme

    let factor: ReadinessFactor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: factor.kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: factor.impact, theme: appTheme))
                .frame(width: 18)

            Text(factor.title)
                .font(.caption)
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
