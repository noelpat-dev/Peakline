import SwiftData
import SwiftUI

struct CoachRouteDestinationView: View {
    let initialSnapshot: CoachRouteRenderSnapshot?
    let backButtonTitle: String?
    let onBack: (() -> Void)?

    @State private var liveQueriesEnabled = false

    init(
        initialSnapshot: CoachRouteRenderSnapshot? = nil,
        backButtonTitle: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.initialSnapshot = initialSnapshot
        self.backButtonTitle = backButtonTitle
        self.onBack = onBack
    }

    var body: some View {
        let routeSnapshot = CoachRouteSnapshotStore.shared.snapshot ?? initialSnapshot

        CoachContentView(
            initialSnapshot: routeSnapshot,
            liveQueriesEnabled: routeSnapshot == nil || liveQueriesEnabled
        )
            .background {
                CoachRouteFrameProbe(label: "coach.route.stable")
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("coach-route-screen")
            .onAppear {
                guard routeSnapshot != nil, !liveQueriesEnabled else { return }
                DispatchQueue.main.async {
                    liveQueriesEnabled = true
                }
            }
    }
}

private struct CoachSupportingDashboard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
            content()
        }
    }
}

struct CoachRouteFrameProbe: View {
    let label: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear {
                PerformanceTracer.mark(.todayCoachFirstFrame, "\(label) onAppear")
                DispatchQueue.main.async {
                    PerformanceTracer.mark(.todayCoachFirstFrame, "\(label) after_main_async")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    PerformanceTracer.mark(.todayCoachFirstFrame, "\(label) after_50ms")
                }
            }
    }
}

struct CoachContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @State private var liveInputs: CoachRouteInputs?
    private var activeSplits: [TrainingSplit] { liveInputs?.activeSplits ?? [] }
    private var completedSessions: [WorkoutSession] { liveInputs?.completedSessions ?? [] }
    private var exercises: [Exercise] { liveInputs?.exercises ?? [] }
    private var sleepSessions: [SleepSession] { liveInputs?.sleepSessions ?? [] }
    private var napSessions: [NapSession] { liveInputs?.napSessions ?? [] }
    private var hydrationEntries: [HydrationEntry] { liveInputs?.hydrationEntries ?? [] }
    private var foodLogEntries: [FoodLogEntry] { liveInputs?.foodLogEntries ?? [] }
    private var coachCheckIns: [DailyCoachCheckIn] { liveInputs?.coachCheckIns ?? [] }
    private var coachActionHistory: [CoachActionHistoryEntry] { liveInputs?.coachActionHistory ?? [] }
    private var savedDeloadBlocks: [SavedCoachDeloadBlock] { liveInputs?.savedDeloadBlocks ?? [] }
    private var recommendationFeedback: [CoachRecommendationFeedback] { liveInputs?.recommendationFeedback ?? [] }
    private var exerciseMetadata: [CoachExerciseMetadata] { liveInputs?.exerciseMetadata ?? [] }
    private var coachPreferences: [CoachPreferences] { liveInputs?.coachPreferences ?? [] }
    private var splitMetadataRecords: [CoachSplitMetadata] { liveInputs?.splitMetadataRecords ?? [] }

    @State private var sleepSettings = SleepSettings.default
    @State private var sleepSnapshot = SleepAnalyticsService.emptySnapshot()
    @State private var lastSleepAnalyticsSignature: SleepAnalyticsInputSignature?
    @State private var coachSnapshot = CoachIntelligenceService.emptySnapshot()
    @State private var lastCoachSnapshotSignature: String?
    @State private var hasLoadedCoachSnapshot = false
    @State private var route: CoachRoute?
    @State private var previewRoute: CoachWorkoutPreviewRoute?
    @State private var weeklyReview: WeeklyReview?
    @State private var lastWeeklyReviewSignature: String?
    @State private var weeklyReviewTask: Task<Void, Never>?
    @State private var summary = CoachDerivedMetrics.placeholder.summary
    @State private var recentPRs: [PRRecord] = []
    @State private var targetSuggestions: [TargetSuggestion] = []
    @State private var weeklyWorkoutCount = 0
    @State private var weeklyWorkingSetCount = 0
    @State private var progressOpportunityInsights: [CoachInsight] = []
    @State private var dailyDecision = CoachDailyDecision.placeholder
    @State private var practicalWeeklyReview = CoachWeeklyReviewSnapshot.placeholder
    @State private var lastCoachDerivedSignature: String?
    @State private var coachDerivedTask: Task<Void, Never>?
    @State private var isTrainingCallEvidenceExpanded = false
    @State private var liveObservationEnabled: Bool
    @State private var isLiveObservationSuspendedForPreview = false
    @State private var liveObservationActivationTask: Task<Void, Never>?
    @State private var previewResumeTask: Task<Void, Never>?
    @State private var isCoachVisible = false
    @State private var hydrationTargetML = 2_500
    @State private var nutritionGoal = NutritionGoal.empty

    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepAnalyticsStore = SleepAnalyticsSnapshotStore.shared
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let deloadBlockService = SavedCoachDeloadBlockService()
    private let coachPreferencesService = CoachPreferencesService()
    private let modePlanner = WorkoutModePlanner()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let initialSnapshot: CoachRouteRenderSnapshot?
    private let liveQueriesEnabled: Bool

    init(
        initialSnapshot: CoachRouteRenderSnapshot? = nil,
        liveQueriesEnabled: Bool = true
    ) {
        self.initialSnapshot = initialSnapshot
        self.liveQueriesEnabled = initialSnapshot == nil || liveQueriesEnabled
        _liveObservationEnabled = State(initialValue: false)
        if let initialSnapshot {
            _coachSnapshot = State(initialValue: initialSnapshot.intelligence)
            _weeklyReview = State(initialValue: initialSnapshot.weeklyReview)
            _summary = State(initialValue: initialSnapshot.derivedMetrics.summary)
            _recentPRs = State(initialValue: initialSnapshot.derivedMetrics.recentPRs)
            _targetSuggestions = State(initialValue: initialSnapshot.derivedMetrics.targetSuggestions)
            _weeklyWorkoutCount = State(initialValue: initialSnapshot.derivedMetrics.weeklyWorkoutCount)
            _weeklyWorkingSetCount = State(initialValue: initialSnapshot.derivedMetrics.weeklyWorkingSetCount)
            _progressOpportunityInsights = State(initialValue: initialSnapshot.derivedMetrics.progressOpportunityInsights)
            _dailyDecision = State(initialValue: initialSnapshot.dailyDecision)
            _practicalWeeklyReview = State(initialValue: initialSnapshot.practicalWeeklyReview)
            _sleepSnapshot = State(initialValue: initialSnapshot.sleepAnalytics)
            _hasLoadedCoachSnapshot = State(initialValue: true)
            _lastCoachSnapshotSignature = State(initialValue: initialSnapshot.intelligenceInputSignature)
            _lastWeeklyReviewSignature = State(initialValue: initialSnapshot.trainingInputSignature)
            _lastCoachDerivedSignature = State(initialValue: initialSnapshot.trainingInputSignature)
            _lastSleepAnalyticsSignature = State(initialValue: initialSnapshot.sleepAnalytics.inputSignature)
        }
    }

    fileprivate static func activeSplitsDescriptor() -> FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    fileprivate static func completedSessionsDescriptor() -> FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    fileprivate static func exercisesDescriptor() -> FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 180
        return descriptor
    }

    fileprivate static func sleepSessionsDescriptor() -> FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    fileprivate static func napSessionsDescriptor() -> FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    fileprivate static func hydrationEntriesDescriptor() -> FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    fileprivate static func foodLogEntriesDescriptor() -> FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 160
        return descriptor
    }

    fileprivate static func coachCheckInsDescriptor() -> FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    fileprivate static func coachActionHistoryDescriptor() -> FetchDescriptor<CoachActionHistoryEntry> {
        var descriptor = FetchDescriptor<CoachActionHistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    fileprivate static func savedDeloadBlocksDescriptor() -> FetchDescriptor<SavedCoachDeloadBlock> {
        var descriptor = FetchDescriptor<SavedCoachDeloadBlock>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    fileprivate static func recommendationFeedbackDescriptor() -> FetchDescriptor<CoachRecommendationFeedback> {
        var descriptor = FetchDescriptor<CoachRecommendationFeedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    fileprivate static func exerciseMetadataDescriptor() -> FetchDescriptor<CoachExerciseMetadata> {
        var descriptor = FetchDescriptor<CoachExerciseMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    fileprivate static func coachPreferencesDescriptor() -> FetchDescriptor<CoachPreferences> {
        var descriptor = FetchDescriptor<CoachPreferences>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    fileprivate static func splitMetadataDescriptor() -> FetchDescriptor<CoachSplitMetadata> {
        var descriptor = FetchDescriptor<CoachSplitMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var recentCompletedSessions: [WorkoutSession] {
        Array(completedSessions.prefix(40))
    }

    private var coachHistorySessions: [WorkoutSession] {
        Array(completedSessions.prefix(40))
    }

    private var sleepDashboardSummary: SleepDashboardSummary {
        currentSleepSnapshot.dashboardSummary
    }

    private var displayedSleepCoachingInsights: [SleepCoachingInsight] {
        guard !readinessScore.isProvisional else { return [] }
        return sleepDashboardSummary.coachingInsights
    }

    private var readinessScore: ReadinessScore {
        currentCoachSnapshot.readiness
    }

    private var currentSleepSnapshot: SleepAnalyticsSnapshot {
        sleepSnapshot
    }

    private var currentCoachSnapshot: CoachIntelligenceSnapshot {
        coachSnapshot
    }

    private var displayedNextStep: String {
        let rawText = dailyDecision.nextStep
        let prefix = "Next: "
        let instruction = rawText.hasPrefix(prefix) ? String(rawText.dropFirst(prefix.count)) : rawText
        guard let first = instruction.first else { return instruction }
        return first.uppercased() + instruction.dropFirst()
    }

    private var presentationDailyDecision: CoachDailyDecision {
        guard currentCoachSnapshot.readiness.isProvisional else { return dailyDecision }
        return dailyDecision.neutralizedForProvisionalReadiness()
    }

    private var refreshInputs: CoachRouteInputs {
        CoachRouteInputs(
            activeSplits: activeSplits,
            completedSessions: completedSessions,
            exercises: exercises,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            foodLogEntries: foodLogEntries,
            coachCheckIns: coachCheckIns,
            coachActionHistory: coachActionHistory,
            savedDeloadBlocks: savedDeloadBlocks,
            recommendationFeedback: recommendationFeedback,
            exerciseMetadata: exerciseMetadata,
            coachPreferences: coachPreferences,
            splitMetadataRecords: splitMetadataRecords,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            workoutRevision: workoutWarmStartInvalidation.revision,
            readinessSignature: readinessRefreshClock.token.signature
        )
    }

    private var currentCoachSnapshotSignature: String { refreshInputs.currentCoachSnapshotSignature }
    private var currentWeeklyReviewSignature: String { refreshInputs.currentWeeklyReviewSignature }
    private var currentCoachDerivedSignature: String { currentWeeklyReviewSignature }
    private var currentSleepAnalyticsSignature: SleepAnalyticsInputSignature { refreshInputs.currentSleepAnalyticsSignature }
    private var coachPreferencesSnapshot: CoachPreferencesSnapshot { coachPreferencesService.snapshot(from: coachPreferences) }
    private func makeCoachSnapshot() -> CoachIntelligenceSnapshot { refreshInputs.makeCoachSnapshot() }

    private var observedSleepAnalyticsSignature: SleepAnalyticsInputSignature? {
        guard liveObservationEnabled, !isLiveObservationSuspendedForPreview else { return nil }
        return currentSleepAnalyticsSignature
    }

    private var observedCoachSnapshotSignature: String? {
        guard liveObservationEnabled, !isLiveObservationSuspendedForPreview else { return nil }
        return currentCoachSnapshotSignature
    }

    private var observedCoachDerivedSignature: String? {
        guard liveObservationEnabled, !isLiveObservationSuspendedForPreview else { return nil }
        return currentCoachDerivedSignature
    }

    private var observedWeeklyReviewSignature: String? {
        guard liveObservationEnabled, !isLiveObservationSuspendedForPreview else { return nil }
        return currentWeeklyReviewSignature
    }

    var body: some View {
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "CoachContentView body hasLoaded=\(hasLoadedCoachSnapshot) initialSnapshot=\(initialSnapshot != nil)")
        let intelligence = currentCoachSnapshot
        let dailyDecision = presentationDailyDecision

        FitnessScreen(
            title: "Coach",
            subtitle: "Readiness, targets, and recovery.",
            systemImage: "sparkles"
        ) {
            FitnessInformationalActionCard(style: .hero) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            ExerciseIconTile(
                                iconKey: ExerciseIconMapper.splitIconKey(for: dailyDecision.recommendedSplitName ?? ""),
                                title: nil,
                                size: 60,
                                style: .compact
                            )

                            Text("Today's Call")
                                .font(AppTypography.eyebrow)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 5) {
                                CoachBadgeView(state: dailyDecision.badgeState)
                                if dailyDecision.confidenceLabel.caseInsensitiveCompare(
                                    dailyDecision.badgeState.label
                                ) != .orderedSame {
                                    Text(dailyDecision.confidenceLabel)
                                        .font(AppTypography.metadataEmphasis)
                                        .foregroundStyle(appTheme.colors.textTertiary)
                                }
                            }
                        }

                        Text(dailyDecision.headline)
                            .font(AppTypography.heroTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coach-todays-call")
                    }

                    Text(dailyDecision.shortReason)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start here")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(displayedNextStep)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } action: {
                if dailyDecision.canOpenPreview {
                    Button {
                        openRecommendedPreview()
                    } label: {
                        Label(dailyDecision.primaryActionTitle, systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .accessibilityIdentifier("coach-primary-action")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach-hero-card")

            if previewRoute == nil {
                DashboardSection(title: "Why this plan") {
                    TrainingCallAuditCard(
                        snapshot: dailyDecision.trainingCall,
                        title: "Evidence",
                        isExpandable: true,
                        showsReason: false,
                        expanded: $isTrainingCallEvidenceExpanded
                    )
                }
                .accessibilityIdentifier("coach-why-this-section")
            }

            if previewRoute == nil {
                CoachSupportingDashboard {
                    DashboardSection(title: "Main Target") {
                        if let primaryTarget = dailyDecision.primaryTarget {
                            FitnessCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    ExerciseTargetRow(suggestion: primaryTarget)

                                    if dailyDecision.additionalTargetCount > 0 {
                                        Text("\(dailyDecision.additionalTargetCount) more targets are ready in Workout Preview.")
                                            .font(.footnote)
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("coach-main-target-section")
                        } else {
                            FitnessCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No clear load target yet")
                                        .font(AppTypography.sectionTitle)
                                        .foregroundStyle(appTheme.colors.textPrimary)

                                    Text(dailyDecision.targetFallback)
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityIdentifier("coach-main-target-section")
                        }
                    }

                    DashboardSection(title: "Workout Mode") {
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Recommended")
                                            .font(AppTypography.chip)
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                            .textCase(.uppercase)

                                        Text("\(dailyDecision.recommendedMode.displayName) Mode")
                                            .font(AppTypography.cardTitle)
                                            .foregroundStyle(appTheme.colors.textPrimary)

                                        Text(dailyDecision.modeReason)
                                            .font(AppTypography.body)
                                            .foregroundStyle(appTheme.colors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 8)
                                    CoachBadgeView(state: badgeState(for: dailyDecision.recommendedMode))
                                }

                                WorkoutModePicker(selection: .constant(dailyDecision.recommendedMode))
                                    .allowsHitTesting(false)

                                Text("You can still switch modes in Workout Preview.")
                                    .font(.footnote)
                                    .foregroundStyle(appTheme.colors.textTertiary)
                            }
                        }
                    }

                    DashboardSection(title: "Coach Controls") {
                        VStack(spacing: 12) {
                            Button {
                                openCoachRoute(.preferences)
                            } label: {
                                DashboardActionTile(
                                    title: "Coach Preferences",
                                    subtitle:
                                        "\(coachPreferencesSnapshot.aggressiveness.displayName), \(coachPreferencesSnapshot.trainingPriority.displayName.lowercased()) priority",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityIdentifier("coach-preferences-open")

                            Button {
                                openCoachRoute(.weeklyReview)
                            } label: {
                                DashboardActionTile(
                                    title: "Weekly Review",
                                    subtitle: PeaklineText.joinedMetadata([
                                        PeaklineText.count(weeklyWorkoutCount, singular: "workout"),
                                        PeaklineText.count(weeklyWorkingSetCount, singular: "working set"),
                                    ]),
                                    systemImage: "chart.bar.doc.horizontal"
                                )
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityIdentifier("coach-weekly-review-open")
                        }
                    }

                    DashboardSection(title: "Weekly Review") {
                        FitnessInformationalActionCard {
                            HStack(spacing: 10) {
                                MetricTile(
                                    label: "Workouts",
                                    value: "\(weeklyWorkoutCount)",
                                    caption: "This week",
                                    systemImage: "figure.strengthtraining.traditional"
                                )

                                MetricTile(
                                    label: "Sets",
                                    value: "\(weeklyWorkingSetCount)",
                                    caption: "Working sets",
                                    systemImage: "checkmark.circle"
                                )
                            }

                            CoachWeeklyReviewRow(title: "Best win", message: practicalWeeklyReview.bestWin)
                            CoachWeeklyReviewRow(title: "Main risk", message: practicalWeeklyReview.mainRisk)
                            CoachWeeklyReviewRow(title: "Next adjustment", message: practicalWeeklyReview.nextAdjustment)
                            CoachWeeklyReviewRow(title: "Split balance", message: practicalWeeklyReview.splitBalance)
                            CoachWeeklyReviewRow(title: "Recovery note", message: practicalWeeklyReview.recoveryNote)
                        } action: {
                            Button {
                                openCoachRoute(.weeklyReview)
                            } label: {
                                Label("Open weekly review", systemImage: "chart.bar.doc.horizontal")
                                    .font(AppTypography.bodyEmphasis)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .accessibilityIdentifier("coach-weekly-review-open-detail")
                        }
                        .accessibilityIdentifier("coach-weekly-review-section")
                    }

                    ReadinessDetailHeaderCard(readiness: intelligence.readiness)

                    DashboardSection(title: "Readiness Summary") {
                        ReadinessRecommendationCard(readiness: intelligence.readiness)
                    }

                    DashboardSection(title: "Weekly Summary") {
                        WeeklyCoachSummaryCard(summary: intelligence.weeklySummary)
                    }

                    DashboardSection(title: "Recent Coach Actions") {
                        CoachActionHistoryTimeline(entries: Array(coachActionHistory.prefix(5)))

                        Button {
                            openCoachRoute(.actionHistory)
                        } label: {
                            Label("Review action history", systemImage: "clock.arrow.circlepath")
                                .font(AppTypography.bodyEmphasis)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .accessibilityIdentifier("coach-history-detail-open")
                    }

                    DashboardSection(title: "Sleep Coaching") {
                        if intelligence.readiness.isProvisional {
                            FitnessCard {
                                Text("Sleep is one supportive signal. Training guidance waits until daily readiness has enough evidence.")
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        } else if let recommendation = sleepDashboardSummary.adaptiveRecommendation {
                            FitnessCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(recommendation.title)
                                            .font(AppTypography.sectionTitle)
                                        Spacer()
                                        CoachBadgeView(state: badgeState(for: recommendation.level))
                                    }

                                    Text(recommendation.message)
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.mutedText)

                                    if !recommendation.basedOn.isEmpty {
                                        Text("Based on: \(recommendation.basedOn.map(\.displayName).joined(separator: ", ")).")
                                            .font(AppTypography.metadata)
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                        }

                        if displayedSleepCoachingInsights.isEmpty {
                            FitnessCard {
                                Text("Keep tracking sleep and workouts to unlock personalised sleep-performance coaching.")
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        } else {
                            ForEach(displayedSleepCoachingInsights.prefix(3)) { insight in
                                FitnessCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(insight.title)
                                                .font(AppTypography.sectionTitle)
                                            Spacer()
                                            CoachBadgeView(state: badgeState(for: insight.severity))
                                        }

                                        Text(insight.message)
                                            .font(AppTypography.body)
                                            .foregroundStyle(appTheme.mutedText)
                                    }
                                }
                            }
                        }
                    }

                    DashboardSection(title: "Recovery Warnings") {
                        if summary.recoveryWarnings.isEmpty {
                            FitnessCard {
                                HStack(spacing: 10) {
                                    CoachBadgeView(state: .ready)
                                    Text("No major recovery warnings right now.")
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.mutedText)
                                }
                            }
                        } else {
                            ForEach(summary.recoveryWarnings) { warning in
                                FitnessCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(warning.title)
                                                .font(AppTypography.sectionTitle)
                                            Spacer()
                                            CoachBadgeView(state: warningBadgeState(for: warning.severity))
                                        }

                                        Text(warning.message)
                                            .font(AppTypography.body)
                                            .foregroundStyle(appTheme.mutedText)
                                    }
                                }
                            }
                        }
                    }

                    DashboardSection(title: "Fatigue / Deload Risk") {
                        FatigueRiskCard(risk: intelligence.fatigueRisk)
                    }

                    if !intelligence.liftInsights.isEmpty {
                        DashboardSection(title: "Lift-Specific Insights") {
                            LiftProgressInsightsCard(insights: intelligence.liftInsights)
                        }
                    }

                    DashboardSection(title: "Muscle Fatigue Map") {
                        MuscleFatigueMapCard(items: intelligence.muscleFatigue)
                    }

                    DashboardSection(title: "Weekly Insights") {
                        CoachInsightsFeedView(insights: intelligence.insights)
                    }

                    insightList(
                        title: "Progress Opportunities", insights: progressOpportunityInsights,
                        empty: "No obvious load jumps yet. Repeat targets and build clean reps.")
                    insightList(
                        title: "Watchlist", insights: weeklyReview?.watchlist ?? [],
                        empty: "No major fatigue or plateau warnings right now.")

                    DashboardSection(title: "Key Habit Contributors") {
                        CoachHabitContributorsCard(trends: intelligence.trends)
                    }

                    DashboardSection(title: "Signal Breakdown") {
                        LazyVStack(spacing: 12) {
                            ForEach(intelligence.readiness.factors) { factor in
                                ReadinessFactorCard(factor: factor)
                            }
                        }
                    }

                    DashboardSection(title: "Saved Deload Blocks") {
                        SavedDeloadBlocksList(
                            blocks: sortedDeloadBlocks,
                            complete: completeDeloadBlock,
                            cancel: cancelDeloadBlock
                        )
                    }

                    DashboardSection(title: "Recent PRs") {
                        if recentPRs.isEmpty {
                            FitnessCard {
                                Text("PRs will appear here when a completed working set beats prior history.")
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        } else {
                            ForEach(recentPRs) { pr in
                                FitnessCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(pr.exerciseName)
                                                .font(AppTypography.sectionTitle)
                                            Text(pr.improvementDescription)
                                                .font(AppTypography.body)
                                                .foregroundStyle(appTheme.mutedText)
                                        }
                                        Spacer()
                                        CoachBadgeView(state: .pr)
                                    }
                                }
                            }
                        }
                    }

                    #if DEBUG
                        if coachPreferencesSnapshot.showDiagnostics {
                            DashboardSection(title: "Diagnostics") {
                                CoachDiagnosticsCard(diagnostics: intelligence.diagnostics)
                            }
                        }
                    #endif
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("coach-screen")
        }
        .background {
            if liveQueriesEnabled {
                CoachLiveQueryObserver(
                    inputs: $liveInputs,
                    sleepSettings: sleepSettings,
                    hydrationTargetML: hydrationTargetML,
                    nutritionGoal: nutritionGoal,
                    workoutRevision: workoutWarmStartInvalidation.revision,
                    readinessSignature: readinessRefreshClock.token.signature
                )
            }
        }
        .onChange(of: liveInputs != nil) { _, isReady in
            if isReady { scheduleLiveObservationActivationIfNeeded() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach-screen")
        .navigationDestination(item: $route) { route in
            Group {
                switch route {
                case .actionHistory:
                    CoachActionHistoryDetailView(
                        entries: coachActionHistory,
                        feedback: recommendationFeedback
                    )
                case .preferences:
                    CoachPreferencesView()
                case .weeklyReview:
                    WeeklyReviewView(initialReview: weeklyReview ?? initialSnapshot?.weeklyReview)
                }
            }
            .onAppear {
                NavigationInteraction.destinationDidAppear(
                    key: "coach.\(route.analyticsName)"
                )
            }
        }
        .navigationDestination(item: $previewRoute) { route in
            WorkoutPreviewRouteView(preparedRoute: route.preparedRoute)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(
                        key: "coach.preview.\(route.id)"
                    )
                }
        }
        .onAppear {
            isCoachVisible = true
            readinessRefreshClock.start()
            PerformanceTracer.mark(.todayCoachDestinationAppear, "CoachContentView onAppear begin hasLoaded=\(hasLoadedCoachSnapshot) initialSnapshot=\(initialSnapshot != nil)")
            if isLiveObservationSuspendedForPreview {
                resumeLiveObservationAfterPreviewIfNeeded()
            } else if initialSnapshot != nil {
                // The startup payload already represents one coherent source generation.
                // Do not traverse every live query while the native push is mounting;
                // enable query-driven invalidation after the prepared frame can present.
                PerformanceTracer.mark(.coachSnapshot, "warm_route_payload_reused_without_mount_traversal")
                scheduleLiveObservationActivationIfNeeded()
            } else {
                loadLiveObservationSettings()
                scheduleLiveObservationActivationIfNeeded()
            }
            PerformanceTracer.mark(.todayCoachDestinationAppear, "CoachContentView onAppear end")
        }
        .onChange(of: liveQueriesEnabled) { queriesWereEnabled, queriesAreEnabled in
            guard !queriesWereEnabled, queriesAreEnabled else { return }
            scheduleLiveObservationActivationIfNeeded()
        }
        .onChange(of: previewRoute) { previousRoute, nextRoute in
            guard previousRoute != nil, nextRoute == nil else { return }
            resumeLiveObservationAfterPreviewIfNeeded()
        }
        .onChange(of: observedSleepAnalyticsSignature) { previousSignature, signature in
            guard previousSignature != nil, let signature else { return }
            guard signature != lastSleepAnalyticsSignature else { return }
            refreshSleepAnalytics()
        }
        .onChange(of: observedCoachSnapshotSignature) { previousSignature, signature in
            guard previousSignature != nil, let signature else { return }
            guard signature != lastCoachSnapshotSignature else { return }
            refreshCoachSnapshot()
        }
        .onChange(of: observedCoachDerivedSignature) { previousSignature, signature in
            guard previousSignature != nil, let signature else { return }
            guard signature != lastCoachDerivedSignature else { return }
            refreshCoachDerivedMetrics()
        }
        .onChange(of: observedWeeklyReviewSignature) { previousSignature, signature in
            guard previousSignature != nil, let signature else { return }
            guard signature != lastWeeklyReviewSignature else { return }
            refreshWeeklyReview()
        }
        .onDisappear {
            isCoachVisible = false
            previewResumeTask?.cancel()
            previewResumeTask = nil
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.onDisappear cancel_tasks begin")
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
            liveObservationActivationTask?.cancel()
            liveObservationActivationTask = nil
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.onDisappear cancel_tasks end")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.willResignActive cancel_tasks begin")
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.willResignActive cancel_tasks end")
        }
    }

    private func refreshLiveObservationInputs() {
        refreshSleepAnalytics()
        refreshCoachSnapshot()
        refreshCoachDerivedMetrics()
        refreshWeeklyReview()
    }

    private func loadLiveObservationSettings() {
        sleepSettings = sleepSettingsStore.load()
        hydrationTargetML = hydrationSettingsStore.dailyTargetML()
        nutritionGoal = nutritionGoalStore.loadGoal()
    }

    private func scheduleLiveObservationActivationIfNeeded() {
        guard liveQueriesEnabled, liveInputs != nil, !liveObservationEnabled else { return }
        liveObservationActivationTask?.cancel()
        liveObservationActivationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, liveQueriesEnabled, liveInputs != nil, !liveObservationEnabled else { return }
            loadLiveObservationSettings()
            liveObservationEnabled = true
            refreshLiveObservationInputs()
            liveObservationActivationTask = nil
        }
    }

    private func resumeLiveObservationAfterPreviewIfNeeded() {
        guard isCoachVisible, isLiveObservationSuspendedForPreview else { return }
        previewResumeTask?.cancel()
        previewResumeTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isCoachVisible,
                  isLiveObservationSuspendedForPreview, previewRoute == nil else { return }
            defer { previewResumeTask = nil }

            // Catch up once while observation is still gated, then reattach the
            // onChange inputs without starting duplicate refresh work.
            loadLiveObservationSettings()
            refreshLiveObservationInputs()
            isLiveObservationSuspendedForPreview = false
        }
    }

    private func refreshSleepAnalytics(force: Bool = false) {
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.sleep_analytics before_signature force=\(force)")
        let signature = currentSleepAnalyticsSignature
        guard force || signature != lastSleepAnalyticsSignature else {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.sleep_analytics skip same_signature")
            return
        }

        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.sleep_analytics before_snapshot")
        sleepSnapshot = PerformanceTracer.trace(.coachSleepAnalytics) {
            sleepAnalyticsStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedSessions.prefix(28)),
                settings: sleepSettings,
                workoutLimit: 28,
                workoutRevision: workoutWarmStartInvalidation.revision,
                force: force
            )
        }
        lastSleepAnalyticsSignature = signature
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.sleep_analytics after_snapshot")
    }

    private func refreshCoachSnapshot(force: Bool = false) {
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.snapshot before_signature force=\(force)")
        let signature = currentCoachSnapshotSignature
        guard force || signature != lastCoachSnapshotSignature else {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.snapshot skip same_signature")
            return
        }

        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.snapshot before_make")
        let nextSnapshot = makeCoachSnapshot()
        AppMotion.withoutAnimation {
            coachSnapshot = nextSnapshot
            lastCoachSnapshotSignature = signature
            hasLoadedCoachSnapshot = true
        }
        let canonicalDecision = TrainingDecisionService().decision(
            activeSplits: activeSplits,
            completedSessions: coachHistorySessions
        )
        let nextTrainingCall = trainingCallBuilder.make(
            decision: canonicalDecision,
            activeSplits: activeSplits,
            completedSessions: coachHistorySessions,
            readiness: nextSnapshot.readiness,
            fatigueRisk: nextSnapshot.fatigueRisk
        ).neutralizedForProvisionalReadiness(
            if: nextSnapshot.readiness.isProvisional
        )
        let nextRecommendedSplit = recommendedSplit(named: nextTrainingCall.recommendedSplitName)
            .map(WorkoutPreviewSplit.init)
        OverallReadinessSnapshotStore.shared.update(
            readiness: nextSnapshot.readiness,
            sourceSignature: signature
        )
        CoachRouteSnapshotStore.shared.update(
            intelligence: nextSnapshot,
            trainingCall: nextTrainingCall,
            recommendedSplit: nextRecommendedSplit,
            fallback: initialSnapshot,
            signature: signature,
            sourceGeneration: CoachRouteSnapshotStore.shared.nextSourceGeneration(),
            source: "coach"
        )
        refreshPresentationState()
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.snapshot after_make")
    }

    private func refreshWeeklyReview(force: Bool = false) {
        weeklyReviewTask?.cancel()
        let signature = currentWeeklyReviewSignature
        guard force || signature != lastWeeklyReviewSignature else {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review skip same_signature")
            return
        }

        let splitSnapshots: [TrainingSplitSnapshot]
        let sessionSnapshots: [WorkoutAnalyticsSession]
        do {
            splitSnapshots = try TrainingSplitSnapshotBuilder.snapshots(from: activeSplits, in: modelContext)
            sessionSnapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: recentCompletedSessions, in: modelContext)
        } catch {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review snapshot_error")
            return
        }
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review snapshots_ready splits=\(splitSnapshots.count) sessions=\(sessionSnapshots.count)")
        weeklyReviewTask = Task { @MainActor in
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review task_begin")
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review detached_begin")
                return PerformanceTracer.trace(.coachWeeklyReview) {
                    WeeklyReviewBuilder().build(activeSplits: splitSnapshots, completedSessions: sessionSnapshots)
                }
            }.value

            guard !Task.isCancelled, !isLiveObservationSuspendedForPreview else { return }
            AppMotion.withoutAnimation {
                weeklyReview = result
                lastWeeklyReviewSignature = signature
            }
            refreshPresentationState()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.weekly_review task_end")
        }
    }

    private func refreshCoachDerivedMetrics(force: Bool = false) {
        coachDerivedTask?.cancel()
        let signature = currentCoachDerivedSignature
        guard force || signature != lastCoachDerivedSignature else {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics skip same_signature")
            return
        }

        let splitSnapshots: [TrainingSplitSnapshot]
        let sessionSnapshots: [WorkoutAnalyticsSession]
        do {
            splitSnapshots = try TrainingSplitSnapshotBuilder.snapshots(from: activeSplits, in: modelContext)
            sessionSnapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: recentCompletedSessions, in: modelContext)
        } catch {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics snapshot_error")
            return
        }
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics snapshots_ready splits=\(splitSnapshots.count) sessions=\(sessionSnapshots.count)")
        coachDerivedTask = Task { @MainActor in
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics task_begin")
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics detached_begin")
                return PerformanceTracer.trace(.coachDerivedMetrics) {
                    CoachDerivedMetrics.make(
                        activeSplits: splitSnapshots,
                        completedSessions: sessionSnapshots
                    )
                }
            }.value

            guard !Task.isCancelled, !isLiveObservationSuspendedForPreview else { return }
            AppMotion.withoutAnimation {
                summary = result.summary
                recentPRs = result.recentPRs
                targetSuggestions = result.targetSuggestions
                weeklyWorkoutCount = result.weeklyWorkoutCount
                weeklyWorkingSetCount = result.weeklyWorkingSetCount
                progressOpportunityInsights = result.progressOpportunityInsights
                lastCoachDerivedSignature = signature
            }
            refreshPresentationState()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.derived_metrics task_end")
        }
    }

    private func refreshPresentationState() {
        let intelligence = currentCoachSnapshot
        let nextDailyDecision = makeDailyDecision(
            intelligence: intelligence,
            summary: summary,
            weeklyReview: weeklyReview,
            targetSuggestions: targetSuggestions
        )
        let nextPracticalWeeklyReview = makeWeeklyReviewSnapshot(
            intelligence: intelligence,
            weeklyReview: weeklyReview
        )

        AppMotion.withoutAnimation {
            dailyDecision = nextDailyDecision
            practicalWeeklyReview = nextPracticalWeeklyReview
        }

        // Cache a complete refreshed generation only after every input family
        // has caught up. Reopening Coach can then reuse it just like startup.
        let inputs = refreshInputs
        guard lastCoachSnapshotSignature == inputs.currentCoachSnapshotSignature,
              lastCoachDerivedSignature == inputs.currentWeeklyReviewSignature,
              lastWeeklyReviewSignature == inputs.currentWeeklyReviewSignature,
              lastSleepAnalyticsSignature == inputs.currentSleepAnalyticsSignature else { return }
        let store = CoachRouteSnapshotStore.shared
        store.update(
            snapshot: CoachRouteRenderSnapshot(
                intelligence: intelligence,
                weeklyReview: weeklyReview,
                derivedMetrics: CoachDerivedMetrics(
                    summary: summary,
                    recentPRs: recentPRs,
                    targetSuggestions: targetSuggestions,
                    weeklyWorkoutCount: weeklyWorkoutCount,
                    weeklyWorkingSetCount: weeklyWorkingSetCount,
                    progressOpportunityInsights: progressOpportunityInsights
                ),
                sleepAnalytics: sleepSnapshot,
                trainingCall: nextDailyDecision.trainingCall,
                recommendedSplit: recommendedSplit(named: nextDailyDecision.recommendedSplitName).map(WorkoutPreviewSplit.init),
                sourceGeneration: store.nextSourceGeneration(),
                intelligenceInputSignature: lastCoachSnapshotSignature,
                trainingInputSignature: lastWeeklyReviewSignature
            ),
            signature: inputs.currentCoachSnapshotSignature,
            source: "coach.complete"
        )
    }

    private func makeDailyDecision(
        intelligence: CoachIntelligenceSnapshot,
        summary: CoachRecommendationSummary,
        weeklyReview: WeeklyReview?,
        targetSuggestions: [TargetSuggestion]
    ) -> CoachDailyDecision {
        let canonicalDecision = summary.trainingDecision
        let splitName = canonicalDecision.recommendedSplitName
        let trainingCall = trainingCallBuilder.make(
            decision: canonicalDecision,
            activeSplits: activeSplits,
            completedSessions: coachHistorySessions,
            readiness: intelligence.readiness,
            fatigueRisk: intelligence.fatigueRisk,
            targetSuggestions: targetSuggestions
        )
        let recommendedMode = trainingCall.recommendedMode
        let displayedTargets = displayedTargetSuggestions(targetSuggestions, trainingCall: trainingCall)
        let primaryTarget = CoachDerivedMetrics.primaryTarget(from: displayedTargets, mode: recommendedMode)
        let whySignals = makeWhySignals(
            splitName: splitName,
            intelligence: intelligence,
            summary: summary,
            weeklyReview: weeklyReview,
            primaryTarget: primaryTarget
        )
        let canOpenPreview = recommendedPreviewSplit(named: splitName) != nil

        return CoachDailyDecision(
            recommendedSplitName: splitName,
            recommendedMode: recommendedMode,
            headline: decisionHeadline(splitName: splitName, mode: recommendedMode),
            targetLine: trainingCall.targetSummary ?? primaryTarget.map(targetLine(for:)),
            shortReason: trainingCall.reason,
            confidenceLabel: trainingCall.confidence.displayName,
            badgeState: decisionBadgeState(trainingCall: trainingCall, primaryTarget: primaryTarget),
            canOpenPreview: canOpenPreview,
            primaryActionTitle: "Open \(recommendedMode.displayName) Preview",
            nextStep: nextStepText(splitName: splitName, mode: recommendedMode, canOpenPreview: canOpenPreview),
            whySignals: whySignals,
            primaryTarget: primaryTarget,
            additionalTargetCount: max(0, displayedTargets.count - (primaryTarget == nil ? 0 : 1)),
            targetFallback: targetFallbackText(splitName: splitName),
            modeReason: modeReason(for: recommendedMode, intelligence: intelligence, trainingCall: trainingCall),
            trainingCall: trainingCall
        )
    }

    private func makeWeeklyReviewSnapshot(
        intelligence: CoachIntelligenceSnapshot,
        weeklyReview: WeeklyReview?
    ) -> CoachWeeklyReviewSnapshot {
        guard let weeklyReview else {
            return CoachWeeklyReviewSnapshot(
                bestWin: "Finish a few sessions to build a weekly win.",
                mainRisk: "The watchlist is still building from recent training.",
                nextAdjustment: "Keep logging workouts so Peakline can sharpen the next call.",
                splitBalance: "Active programme coverage will appear once the week has completed sessions.",
                recoveryNote: intelligence.weeklySummary.recommendedFocus
            )
        }

        return CoachWeeklyReviewSnapshot(
            bestWin: weeklyReview.highlights.first?.message ?? "No clear PR win yet this week.",
            mainRisk: weeklyReview.watchlist.first?.message ?? "No major risk is standing out right now.",
            nextAdjustment: weeklyReview.nextDecision.reason,
            splitBalance: "\(weeklyReview.splitConsistency.countDescription(separator: " / ")). \(weeklyReview.splitConsistency.balanceDescription)",
            recoveryNote: intelligence.weeklySummary.recommendedFocus
        )
    }

    private func displayedTargetSuggestions(_ suggestions: [TargetSuggestion], trainingCall: TrainingCallSnapshot) -> [TargetSuggestion] {
        suggestions.map { suggestion in
            modePlanner.modeAdjustedSuggestion(suggestion, mode: trainingCall.recommendedMode, trainingCall: trainingCall)
        }
    }

    private func makeWhySignals(
        splitName: String?,
        intelligence: CoachIntelligenceSnapshot,
        summary: CoachRecommendationSummary,
        weeklyReview: WeeklyReview?,
        primaryTarget: TargetSuggestion?
    ) -> [CoachDecisionSignal] {
        var signals: [CoachDecisionSignal] = []

        if let splitName {
            signals.append(rotationSignal(for: splitName, weeklyReview: weeklyReview, fallback: summary.reason))
        }

        signals.append(
            CoachDecisionSignal(
                title: "Recovery",
                message: intelligence.adaptiveGuidance.summary,
                systemImage: "gauge.with.dots.needle.bottom.50percent"
            )
        )

        if let primaryTarget {
            signals.append(
                CoachDecisionSignal(
                    title: "Performance",
                    message: primaryTarget.reason,
                    systemImage: "target"
                )
            )
        } else if let firstRecommendation = summary.exerciseRecommendations.first {
            signals.append(
                CoachDecisionSignal(
                    title: "Performance",
                    message: firstRecommendation.message,
                    systemImage: "target"
                )
            )
        } else if let weeklyReason = weeklyReview?.nextDecision.reason {
            signals.append(
                CoachDecisionSignal(
                    title: "Performance",
                    message: weeklyReason,
                    systemImage: "target"
                )
            )
        }

        return Array(signals.prefix(3))
    }

    private func rotationSignal(
        for splitName: String,
        weeklyReview: WeeklyReview?,
        fallback: String
    ) -> CoachDecisionSignal {
        if weeklyReview?.splitConsistency.missedSplitName == splitName {
            return CoachDecisionSignal(
                title: "Rotation",
                message: "\(splitName) is the missed split in this week's balance.",
                systemImage: "calendar.badge.exclamationmark"
            )
        }

        guard let days = daysSinceLastCompletedSplit(named: splitName) else {
            return CoachDecisionSignal(
                title: "Rotation",
                message: "No completed \(splitName) session is logged yet, so this is your clean baseline.",
                systemImage: "calendar.badge.clock"
            )
        }

        let message: String
        switch days {
        case 0:
            message = "\(splitName) was already logged today. Repeat only if that is intentional."
        case 1:
            message = "\(splitName) was last trained yesterday."
        default:
            message = "\(splitName) was last trained \(days) days ago."
        }

        return CoachDecisionSignal(
            title: "Rotation",
            message: fallback.contains(splitName) ? "\(message) \(fallback)" : message,
            systemImage: "calendar.badge.clock"
        )
    }

    private func decisionHeadline(splitName: String?, mode _: WorkoutMode) -> String {
        guard let splitName else {
            return "Build Today's Baseline"
        }

        return splitName
    }

    private func targetLine(for suggestion: TargetSuggestion) -> String {
        "\(suggestion.exerciseName) \(targetDescription(for: suggestion))"
    }

    private func targetDescription(for suggestion: TargetSuggestion) -> String {
        switch (suggestion.suggestedWeight, suggestion.suggestedReps) {
        case let (.some(weight), .some(reps)):
            return PeaklineText.loadReps(weight: format(weight), reps: reps)
        case let (.some(weight), .none):
            return "\(format(weight)) kg"
        case let (.none, .some(reps)):
            return "\(reps)+ reps"
        case (.none, .none):
            return "Log clean sets"
        }
    }

    private func targetFallbackText(splitName: String?) -> String {
        guard let splitName else {
            return "Activate Push, Pull, and Legs, then log a session so Peakline can build a next target."
        }

        return "Open \(splitName) and finish a clean session to build the next load target."
    }

    private func modeReason(
        for mode: WorkoutMode,
        intelligence: CoachIntelligenceSnapshot,
        trainingCall: TrainingCallSnapshot
    ) -> String {
        if let guardrail = trainingCall.guardrailNotes.first {
            return guardrail
        }

        switch mode {
        case .full:
            return "Normal training day. Keep the full split and chase one clear target."
        case .quick:
            return "Keep the main work, trim accessories, and keep the session moving."
        case .recovery:
            return "Lower-fatigue call. Repeat clean work and keep the session controlled."
        case .heavy:
            return intelligence.adaptiveGuidance.primarySuggestion == "Progress one primary lift"
                ? "Push one main lift if warm-ups feel normal, then keep the rest steady."
                : "Use the extra readiness to bias the session toward heavier top work."
        }
    }

    private func nextStepText(splitName: String?, mode: WorkoutMode, canOpenPreview: Bool) -> String {
        guard let splitName else {
            return "Next: keep logging workouts so Peakline can sharpen today's call."
        }

        guard canOpenPreview else {
            return "Next: open the \(splitName) split once it is available again."
        }

        return "Next: open \(splitName) in \(mode.displayName.lowercased()) mode and start if warm-ups feel normal."
    }

    private func decisionBadgeState(
        weeklyReview: WeeklyReview?,
        mode: WorkoutMode,
        primaryTarget: TargetSuggestion?
    ) -> CoachBadgeState {
        if let action = weeklyReview?.nextDecision.action {
            switch action {
            case .rebalance:
                return .missedSplit
            case .recover:
                return .recovery
            case .repeatTarget:
                return primaryTarget.map { CoachBadgeState(recommendationType: $0.recommendationType) } ?? .repeatTarget
            case .buildBaseline:
                return .baseline
            case .push:
                if primaryTarget?.recommendationType == .increaseLoad {
                    return .increaseLoad
                }
                if primaryTarget?.recommendationType == .addReps {
                    return .addReps
                }
                return badgeState(for: mode)
            }
        }

        return badgeState(for: mode)
    }

    private func decisionBadgeState(
        trainingCall: TrainingCallSnapshot,
        primaryTarget: TargetSuggestion?
    ) -> CoachBadgeState {
        switch trainingCall.action {
        case .rebalance:
            return .missedSplit
        case .recover:
            return .recovery
        case .repeatTarget:
            return primaryTarget.map { CoachBadgeState(recommendationType: $0.recommendationType) } ?? .repeatTarget
        case .buildBaseline:
            return .baseline
        case .push:
            if primaryTarget?.recommendationType == .increaseLoad {
                return .increaseLoad
            }
            if primaryTarget?.recommendationType == .addReps {
                return .addReps
            }
            return badgeState(for: trainingCall.recommendedMode)
        }
    }

    private func recommendedSplit(named name: String?) -> TrainingSplit? {
        guard let name else { return nil }
        let requestedBaseName = baseSplitName(name)
        return activeSplits.first { split in
            split.name == name || baseSplitName(split.name) == requestedBaseName
        }
    }

    private func recommendedPreviewSplit(named name: String?) -> WorkoutPreviewSplit? {
        guard let name else { return nil }

        if let liveSplit = recommendedSplit(named: name) {
            return WorkoutPreviewSplit(liveSplit)
        }

        guard let preparedSplit = initialSnapshot?.recommendedSplit,
              preparedSplit.name == name || baseSplitName(preparedSplit.name) == baseSplitName(name) else {
            return nil
        }
        return preparedSplit
    }

    private func daysSinceLastCompletedSplit(named splitName: String) -> Int? {
        guard let lastSession = coachHistorySessions.first(where: { baseSplitName($0.splitNameSnapshot) == splitName }) else {
            return nil
        }

        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastSession.date),
            to: Calendar.current.startOfDay(for: .now)
        ).day
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }

    private func openRecommendedPreview() {
        let decision = presentationDailyDecision
        guard let preparedSplit = recommendedPreviewSplit(named: decision.recommendedSplitName) else { return }

        let route = CoachWorkoutPreviewRoute(
            split: preparedSplit,
            mode: decision.recommendedMode
        )

        PerformanceTracer.mark(.previewRouteTap, "source=coach split=\(route.split.name) mode=\(route.mode.rawValue)")
        PerformanceTracer.mark(
            .workoutPreviewRenderSnapshot,
            "navigation request source=coach split=\(route.split.id.uuidString) mode=\(route.mode.rawValue) active=\(previewRoute?.split.id.uuidString ?? "none")"
        )

        guard previewRoute != route else {
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation skip source=coach already_active split=\(route.split.id.uuidString)")
            return
        }

        // A preview push should not compete with detached dashboard work that
        // was started by the just-mounted Coach route. Cancellation is cheap and
        // prevents late completions from invalidating the transition's parent.
        weeklyReviewTask?.cancel()
        weeklyReviewTask = nil
        coachDerivedTask?.cancel()
        coachDerivedTask = nil

        NavigationInteraction.perform(
            key: "coach.preview.\(route.id)",
            destinationClass: .deep,
            haptic: .selection
        ) {
            isLiveObservationSuspendedForPreview = true
            previewRoute = route
        }
    }

    private func openCoachRoute(_ nextRoute: CoachRoute) {
        guard route == nil else {
            PerformanceTracer.mark(
                .navigationInteraction,
                "coach route ignored active=\(route?.analyticsName ?? "none") requested=\(nextRoute.analyticsName)"
            )
            return
        }
        NavigationInteraction.perform(
            key: "coach.\(nextRoute.analyticsName)",
            destinationClass: .deep,
            haptic: .selection
        ) {
            route = nextRoute
        }
    }


    private var sortedDeloadBlocks: [SavedCoachDeloadBlock] {
        savedDeloadBlocks.sorted { lhs, rhs in
            if lhs.state == .active, rhs.state != .active { return true }
            if lhs.state != .active, rhs.state == .active { return false }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func completeDeloadBlock(_ block: SavedCoachDeloadBlock) {
        deloadBlockService.complete(block)
        try? modelContext.save()
    }

    private func cancelDeloadBlock(_ block: SavedCoachDeloadBlock) {
        deloadBlockService.cancel(block)
        try? modelContext.save()
    }

    private func warningBadgeState(for priority: CoachPriority) -> CoachBadgeState {
        switch priority {
        case .low:
            return .repeatTarget
        case .medium:
            return .fatigueRisk
        case .high:
            return .possiblePlateau
        }
    }

    private func badgeState(for action: TrainingDecisionAction) -> CoachBadgeState {
        switch action {
        case .push:
            return .ready
        case .repeatTarget:
            return .repeatTarget
        case .recover:
            return .recovery
        case .rebalance:
            return .missedSplit
        case .buildBaseline:
            return .baseline
        }
    }

    private func badgeState(for mode: WorkoutMode) -> CoachBadgeState {
        switch mode {
        case .full:
            return .ready
        case .quick:
            return .repeatTarget
        case .recovery:
            return .recovery
        case .heavy:
            return .increaseLoad
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }

    private func badgeState(for level: TrainingReadinessRecommendation) -> CoachBadgeState {
        switch level {
        case .push, .normal:
            return .ready
        case .moderate:
            return .repeatTarget
        case .light, .recovery:
            return .fatigueRisk
        case .rest:
            return .recovery
        }
    }

    private func badgeState(for severity: InsightSeverity) -> CoachBadgeState {
        switch severity {
        case .positive:
            return .ready
        case .neutral:
            return .repeatTarget
        case .caution:
            return .fatigueRisk
        case .important:
            return .possiblePlateau
        }
    }

    private func insightList(title: String, insights: [CoachInsight], empty: String) -> some View {
        DashboardSection(title: title) {
            if insights.isEmpty {
                FitnessCard {
                    Text(empty)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.mutedText)
                }
            } else {
                ForEach(insights) { insight in
                    FitnessCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(AppTypography.sectionTitle)
                                Text(insight.message)
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                            Spacer()
                            CoachBadgeView(state: badgeState(for: insight.severity))
                        }
                    }
                }
            }
        }
    }

    private func badgeState(for severity: CoachInsightSeverity) -> CoachBadgeState {
        switch severity {
        case .info:
            return .repeatTarget
        case .positive:
            return .ready
        case .warning:
            return .possiblePlateau
        case .recovery:
            return .fatigueRisk
        }
    }
}

private extension CoachDailyDecision {
    func neutralizedForProvisionalReadiness() -> CoachDailyDecision {
        let safeTrainingCall = trainingCall.neutralizedForProvisionalReadiness(if: true)
        return CoachDailyDecision(
            recommendedSplitName: recommendedSplitName,
            recommendedMode: .full,
            headline: recommendedSplitName ?? "Readiness pending",
            targetLine: nil,
            shortReason: safeTrainingCall.reason,
            confidenceLabel: "Provisional",
            badgeState: .provisional,
            canOpenPreview: recommendedSplitName != nil,
            primaryActionTitle: "Open Full Preview",
            nextStep: recommendedSplitName.map {
                "Next: preview \($0), adjust if needed, then start when ready."
            } ?? "Keep tracking today’s signals while readiness builds.",
            whySignals: [
                CoachDecisionSignal(
                    title: "Readiness",
                    message: "Daily readiness is provisional; missing signals do not lower the score.",
                    systemImage: "hourglass"
                )
            ],
            primaryTarget: nil,
            additionalTargetCount: 0,
            targetFallback: "Readiness evidence is still building; no load or recovery prescription is available yet.",
            modeReason: safeTrainingCall.reason,
            trainingCall: safeTrainingCall
        )
    }
}

private struct CoachWeeklyReviewRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)
                .textCase(.uppercase)

            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CoachActionHistoryTimeline: View {
    @Environment(\.appTheme) private var appTheme

    let entries: [CoachActionHistoryEntry]

    var body: some View {
        if entries.isEmpty {
            FitnessCard {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "clock.arrow.circlepath", size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No coach actions yet")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("Applied or bypassed workout adjustments will appear here.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(tint(for: entry))
                                    .frame(width: 10, height: 10)

                                if index < entries.prefix(5).count - 1 {
                                    Rectangle()
                                        .fill(appTheme.colors.cardBorder)
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(historyTitle(for: entry))
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(entry.shortReason)
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(appTheme.colors.textTertiary)
                            }

                            Spacer(minLength: 8)
                        }
                    }
                }
            }
        }
    }

    private func historyTitle(for entry: CoachActionHistoryEntry) -> String {
        let splitName = entry.splitName ?? entry.workoutName
        if let splitName, !splitName.isEmpty {
            return "\(entry.action.displayName) - \(splitName)"
        }

        return "\(entry.action.displayName) \(entry.outcome.displayName.lowercased())"
    }

    private func tint(for entry: CoachActionHistoryEntry) -> Color {
        switch entry.outcome {
        case .applied:
            return appTheme.colors.success
        case .cancelled:
            return appTheme.colors.textTertiary
        case .reset:
            return appTheme.colors.warning
        case .bypassed:
            return appTheme.colors.accent
        }
    }
}

private enum CoachRoute: Hashable, Identifiable {
    case actionHistory
    case preferences
    case weeklyReview

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .actionHistory: "action-history"
        case .preferences: "preferences"
        case .weeklyReview: "weekly-review"
        }
    }
}

private struct CoachWorkoutPreviewRoute: Hashable, Identifiable {
    let preparedRoute: WorkoutPreviewPreparedRoute

    var split: WorkoutPreviewSplit { preparedRoute.split }
    var mode: WorkoutMode { preparedRoute.initialMode }

    @MainActor
    init(split: WorkoutPreviewSplit, mode: WorkoutMode) {
        preparedRoute = WorkoutPreviewWarmStartStore.shared.prepareRoute(
            for: split,
            initialMode: mode
        )
    }

    var id: String {
        "\(split.id.uuidString)-\(mode.rawValue)"
    }
}

/// One bounded input contract for startup preparation and mounted Coach refreshes.
/// Live SwiftData values stay on their owning actor; only signatures enter the route payload.
@MainActor
struct CoachRouteInputs {
    let activeSplits: [TrainingSplit]
    let completedSessions: [WorkoutSession]
    let exercises: [Exercise]
    let sleepSessions: [SleepSession]
    let napSessions: [NapSession]
    let hydrationEntries: [HydrationEntry]
    let foodLogEntries: [FoodLogEntry]
    let coachCheckIns: [DailyCoachCheckIn]
    let coachActionHistory: [CoachActionHistoryEntry]
    let savedDeloadBlocks: [SavedCoachDeloadBlock]
    let recommendationFeedback: [CoachRecommendationFeedback]
    let exerciseMetadata: [CoachExerciseMetadata]
    let coachPreferences: [CoachPreferences]
    let splitMetadataRecords: [CoachSplitMetadata]
    let sleepSettings: SleepSettings
    let hydrationTargetML: Int
    let nutritionGoal: NutritionGoal
    let workoutRevision: Int
    let readinessSignature: String
    var recentCompletedSessions: [WorkoutSession] { completedSessions }
    var coachHistorySessions: [WorkoutSession] { completedSessions }

    static func load(in context: ModelContext) throws -> CoachRouteInputs {
        CoachRouteInputs(
            activeSplits: try context.fetch(CoachContentView.activeSplitsDescriptor()),
            completedSessions: try context.fetch(CoachContentView.completedSessionsDescriptor()),
            exercises: try context.fetch(CoachContentView.exercisesDescriptor()),
            sleepSessions: try context.fetch(CoachContentView.sleepSessionsDescriptor()),
            napSessions: try context.fetch(CoachContentView.napSessionsDescriptor()),
            hydrationEntries: try context.fetch(CoachContentView.hydrationEntriesDescriptor()),
            foodLogEntries: try context.fetch(CoachContentView.foodLogEntriesDescriptor()),
            coachCheckIns: try context.fetch(CoachContentView.coachCheckInsDescriptor()),
            coachActionHistory: try context.fetch(CoachContentView.coachActionHistoryDescriptor()),
            savedDeloadBlocks: try context.fetch(CoachContentView.savedDeloadBlocksDescriptor()),
            recommendationFeedback: try context.fetch(CoachContentView.recommendationFeedbackDescriptor()),
            exerciseMetadata: try context.fetch(CoachContentView.exerciseMetadataDescriptor()),
            coachPreferences: try context.fetch(CoachContentView.coachPreferencesDescriptor()),
            splitMetadataRecords: try context.fetch(CoachContentView.splitMetadataDescriptor()),
            sleepSettings: SleepSettingsStore().load(),
            hydrationTargetML: HydrationSettingsStore().dailyTargetML(),
            nutritionGoal: NutritionGoalService().loadGoal(),
            workoutRevision: WorkoutWarmStartInvalidation.shared.revision,
            readinessSignature: ReadinessRefreshClock.shared.token.signature
        )
    }

    var currentCoachSnapshotSignature: String {
        [
            signature(activeSplits, limit: 12) {
                "\($0.id.uuidString):\($0.activeRotationIndex ?? -1):\($0.updatedAt.timeIntervalSince1970)"
            },
            signature(exercises, limit: 180) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachHistorySessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(sleepSessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachActionHistory, limit: 80) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(savedDeloadBlocks, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(recommendationFeedback, limit: 80) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(exerciseMetadata, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachPreferences, limit: 5) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(splitMetadataRecords, limit: 40) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "workoutRevision:\(workoutRevision)",
            sleepSettingsSignature,
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            readinessSignature
        ].joined(separator: "|")
    }

    var currentWeeklyReviewSignature: String {
        [
            signature(activeSplits, limit: 12) { split in
                "\(split.id.uuidString):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
            },
            signature(recentCompletedSessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            "revision:\(workoutRevision)",
            "day:\(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)"
        ].joined(separator: "|")
    }

    var sleepSettingsSignature: String {
        [
            "\(sleepSettings.targetSleepMinutes)",
            "\(sleepSettings.recoveryCoachingEnabled)",
            sleepSettings.preferredSource.rawValue,
            "\(sleepSettings.coachingPreferences.sleepCoachingInsightsEnabled)",
            "\(sleepSettings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled)",
            "\(sleepSettings.coachingPreferences.deloadSuggestionsEnabled)",
            "\(sleepSettings.coachingPreferences.sleepPerformanceInsightsEnabled)"
        ].joined(separator: ":")
    }

    func makeCoachSnapshot() -> CoachIntelligenceSnapshot {
        PerformanceTracer.trace(.coachSnapshot) {
            CoachIntelligenceService().snapshot(
                activeSplits: activeSplits,
                exercises: exercises,
                sleepSessions: sleepSessions,
                napSessions: napSessions,
                hydrationEntries: hydrationEntries,
                completedWorkouts: coachHistorySessions,
                foodLogs: foodLogEntries,
                checkIns: coachCheckIns,
                sleepSettings: sleepSettings,
                hydrationTargetML: hydrationTargetML,
                nutritionGoal: nutritionGoal,
                exerciseMetadata: exerciseMetadata,
                coachActionHistory: coachActionHistory,
                recommendationFeedback: recommendationFeedback,
                savedDeloadBlocks: savedDeloadBlocks,
                coachPreferences: coachPreferencesSnapshot,
                splitMetadata: splitMetadataRecords
            )
        }
    }

    var coachPreferencesSnapshot: CoachPreferencesSnapshot {
        CoachPreferencesService().snapshot(from: coachPreferences)
    }

    var currentSleepAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: Array(completedSessions.prefix(28)),
            settings: sleepSettings,
            sessionLimit: 90,
            workoutLimit: 28,
            workoutRevision: workoutRevision
        )
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }
}

/// Query observation mounts after the prepared route has appeared. It updates
/// the existing screen's inputs without replacing its content or navigation state.
private struct CoachLiveQueryObserver: View {
    @Binding var inputs: CoachRouteInputs?
    @Query
    private var activeSplits: [TrainingSplit]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var exercises: [Exercise]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @Query
    private var hydrationEntries: [HydrationEntry]

    @Query
    private var foodLogEntries: [FoodLogEntry]

    @Query
    private var coachCheckIns: [DailyCoachCheckIn]

    @Query
    private var coachActionHistory: [CoachActionHistoryEntry]

    @Query
    private var savedDeloadBlocks: [SavedCoachDeloadBlock]

    @Query
    private var recommendationFeedback: [CoachRecommendationFeedback]

    @Query
    private var exerciseMetadata: [CoachExerciseMetadata]

    @Query
    private var coachPreferences: [CoachPreferences]

    @Query
    private var splitMetadataRecords: [CoachSplitMetadata]

    let sleepSettings: SleepSettings
    let hydrationTargetML: Int
    let nutritionGoal: NutritionGoal
    let workoutRevision: Int
    let readinessSignature: String

    init(
        inputs: Binding<CoachRouteInputs?>,
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        workoutRevision: Int,
        readinessSignature: String
    ) {
        _inputs = inputs
        self.sleepSettings = sleepSettings
        self.hydrationTargetML = hydrationTargetML
        self.nutritionGoal = nutritionGoal
        self.workoutRevision = workoutRevision
        self.readinessSignature = readinessSignature
        _activeSplits = Query(CoachContentView.activeSplitsDescriptor())
        _completedSessions = Query(CoachContentView.completedSessionsDescriptor())
        _exercises = Query(CoachContentView.exercisesDescriptor())
        _sleepSessions = Query(CoachContentView.sleepSessionsDescriptor())
        _napSessions = Query(CoachContentView.napSessionsDescriptor())
        _hydrationEntries = Query(CoachContentView.hydrationEntriesDescriptor())
        _foodLogEntries = Query(CoachContentView.foodLogEntriesDescriptor())
        _coachCheckIns = Query(CoachContentView.coachCheckInsDescriptor())
        _coachActionHistory = Query(CoachContentView.coachActionHistoryDescriptor())
        _savedDeloadBlocks = Query(CoachContentView.savedDeloadBlocksDescriptor())
        _recommendationFeedback = Query(CoachContentView.recommendationFeedbackDescriptor())
        _exerciseMetadata = Query(CoachContentView.exerciseMetadataDescriptor())
        _coachPreferences = Query(CoachContentView.coachPreferencesDescriptor())
        _splitMetadataRecords = Query(CoachContentView.splitMetadataDescriptor())
    }

    var body: some View {
        let snapshot = CoachRouteInputs(
            activeSplits: activeSplits,
            completedSessions: completedSessions,
            exercises: exercises,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            foodLogEntries: foodLogEntries,
            coachCheckIns: coachCheckIns,
            coachActionHistory: coachActionHistory,
            savedDeloadBlocks: savedDeloadBlocks,
            recommendationFeedback: recommendationFeedback,
            exerciseMetadata: exerciseMetadata,
            coachPreferences: coachPreferences,
            splitMetadataRecords: splitMetadataRecords,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            workoutRevision: workoutRevision,
            readinessSignature: readinessSignature
        )
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { inputs = snapshot }
            .onChange(of: snapshot.currentCoachSnapshotSignature) { _, _ in inputs = snapshot }
            .onChange(of: snapshot.currentWeeklyReviewSignature) { _, _ in inputs = snapshot }
            .onChange(of: snapshot.currentSleepAnalyticsSignature) { _, _ in inputs = snapshot }
    }
}
