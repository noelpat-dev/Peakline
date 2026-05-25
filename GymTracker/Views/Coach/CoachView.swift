import SwiftData
import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            CoachContentView()
        }
    }
}

struct CoachContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepSnapshot = SleepAnalyticsService.emptySnapshot()
    @State private var lastSleepAnalyticsSignature: SleepAnalyticsInputSignature?
    @State private var coachSnapshot = CoachIntelligenceService.emptySnapshot()
    @State private var lastCoachSnapshotSignature: String?
    @State private var hasLoadedCoachSnapshot = false
    @State private var showingCoachCheckIn = false
    @State private var route: CoachRoute?
    @State private var weeklyReview: WeeklyReview?
    @State private var lastWeeklyReviewSignature: String?
    @State private var weeklyReviewTask: Task<Void, Never>?
    @State private var summary = CoachRecommendationSummary.placeholder
    @State private var recentPRs: [PRRecord] = []
    @State private var targetSuggestions: [TargetSuggestion] = []
    @State private var weeklyWorkoutCount = 0
    @State private var weeklyWorkingSetCount = 0
    @State private var progressOpportunityInsights: [CoachInsight] = []
    @State private var lastCoachDerivedSignature: String?
    @State private var coachDerivedTask: Task<Void, Never>?
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var deferredCoachRefreshWorkItem: DispatchWorkItem?
    @State private var deferredFullCoachSnapshotWorkItem: DispatchWorkItem?

    private let coachIntelligence = CoachIntelligenceService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepAnalyticsStore = SleepAnalyticsSnapshotStore.shared
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let deloadBlockService = SavedCoachDeloadBlockService()
    private let coachPreferencesService = CoachPreferencesService()
    private let initialSnapshot: CoachIntelligenceSnapshot?

    init(initialSnapshot: CoachIntelligenceSnapshot? = nil) {
        self.initialSnapshot = initialSnapshot
        _activeSplits = Query(Self.activeSplitsDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _exercises = Query(Self.exercisesDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
        _coachActionHistory = Query(Self.coachActionHistoryDescriptor)
        _savedDeloadBlocks = Query(Self.savedDeloadBlocksDescriptor)
        _recommendationFeedback = Query(Self.recommendationFeedbackDescriptor)
        _exerciseMetadata = Query(Self.exerciseMetadataDescriptor)
        _coachPreferences = Query(Self.coachPreferencesDescriptor)
        _splitMetadataRecords = Query(Self.splitMetadataDescriptor)
        if let initialSnapshot {
            _coachSnapshot = State(initialValue: initialSnapshot)
            _hasLoadedCoachSnapshot = State(initialValue: true)
        }
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var exercisesDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 140
        return descriptor
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var hydrationEntriesDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        return descriptor
    }

    private static var foodLogEntriesDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return descriptor
    }

    private static var coachCheckInsDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var coachActionHistoryDescriptor: FetchDescriptor<CoachActionHistoryEntry> {
        var descriptor = FetchDescriptor<CoachActionHistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var savedDeloadBlocksDescriptor: FetchDescriptor<SavedCoachDeloadBlock> {
        var descriptor = FetchDescriptor<SavedCoachDeloadBlock>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var recommendationFeedbackDescriptor: FetchDescriptor<CoachRecommendationFeedback> {
        var descriptor = FetchDescriptor<CoachRecommendationFeedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var exerciseMetadataDescriptor: FetchDescriptor<CoachExerciseMetadata> {
        var descriptor = FetchDescriptor<CoachExerciseMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var coachPreferencesDescriptor: FetchDescriptor<CoachPreferences> {
        var descriptor = FetchDescriptor<CoachPreferences>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private static var splitMetadataDescriptor: FetchDescriptor<CoachSplitMetadata> {
        var descriptor = FetchDescriptor<CoachSplitMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var recentCompletedSessions: [WorkoutSession] {
        Array(completedSessions.prefix(20))
    }

    private var coachHistorySessions: [WorkoutSession] {
        Array(completedSessions.prefix(40))
    }

    private var sleepDashboardSummary: SleepDashboardSummary {
        currentSleepSnapshot.dashboardSummary
    }

    private var readinessScore: ReadinessScore {
        currentCoachSnapshot.readiness
    }

    private var currentSleepSnapshot: SleepAnalyticsSnapshot {
        guard lastSleepAnalyticsSignature != nil else {
            return sleepSnapshot
        }

        let signature = currentSleepAnalyticsSignature
        if signature == lastSleepAnalyticsSignature {
            return sleepSnapshot
        }

        return sleepSnapshot
    }

    private var currentCoachSnapshot: CoachIntelligenceSnapshot {
        guard lastCoachSnapshotSignature != nil else {
            return coachSnapshot
        }

        let signature = currentCoachSnapshotSignature
        if signature == lastCoachSnapshotSignature {
            return coachSnapshot
        }

        return coachSnapshot
    }

    private var currentCoachSnapshotSignature: String {
        [
            signature(activeSplits, limit: 12) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(exercises, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachHistorySessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(sleepSessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 45) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(hydrationEntries, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachActionHistory, limit: 80) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(savedDeloadBlocks, limit: 20) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(recommendationFeedback, limit: 80) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(exerciseMetadata, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachPreferences, limit: 3) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(splitMetadataRecords, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            sleepSettingsSignature,
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)"
        ].joined(separator: "|")
    }

    private var currentWeeklyReviewSignature: String {
        [
            signature(activeSplits, limit: 12) { split in
                "\((split.id.uuidString)):\(split.updatedAt.timeIntervalSince1970)"
            },
            signature(recentCompletedSessions, limit: 20) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" }
        ].joined(separator: "|")
    }

    private var currentCoachDerivedSignature: String {
        currentWeeklyReviewSignature
    }

    private var sleepSettingsSignature: String {
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

    private func makeCoachSnapshot() -> CoachIntelligenceSnapshot {
        PerformanceTracer.trace(.coachSnapshot) {
            coachIntelligence.snapshot(
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

    private var coachPreferencesSnapshot: CoachPreferencesSnapshot {
        coachPreferencesService.snapshot(from: coachPreferences)
    }

    private var currentSleepAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sleepSessions, naps: napSessions, workouts: recentCompletedSessions, settings: sleepSettings, sessionLimit: 90, workoutLimit: 20)
    }

    var body: some View {
        let intelligence = currentCoachSnapshot

        FitnessScreen(
            title: "Coach",
            subtitle: "Readiness, targets, and recovery.",
            systemImage: "sparkles"
        ) {
            ReadinessDetailHeaderCard(readiness: intelligence.readiness)

            DashboardSection(title: "Recommendation") {
                ReadinessRecommendationCard(readiness: intelligence.readiness)
            }

            DashboardSection(title: "Today's Check-In") {
                CheckInStatusCard(checkIn: intelligence.readiness.checkIn) {
                    showingCoachCheckIn = true
                }
            }

            DashboardSection(title: "Coach Controls") {
                NavigationLink {
                    CoachPreferencesView()
                } label: {
                    DashboardActionTile(
                        title: "Coach Preferences",
                        subtitle: "\(coachPreferencesSnapshot.aggressiveness.displayName), \(coachPreferencesSnapshot.trainingPriority.displayName.lowercased()) priority",
                        systemImage: "slider.horizontal.3"
                    )
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityIdentifier("coach-preferences-open")
            }

            DashboardSection(title: "Weekly Summary") {
                WeeklyCoachSummaryCard(summary: intelligence.weeklySummary)
            }

            DashboardSection(title: "Recent Coach Actions") {
                CoachActionHistoryList(entries: Array(coachActionHistory.prefix(5)))

                Button {
                    route = .actionHistory
                } label: {
                    Label("Review action history", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .accessibilityIdentifier("coach-history-detail-open")
            }

            DashboardSection(title: "Saved Deload Blocks") {
                SavedDeloadBlocksList(
                    blocks: sortedDeloadBlocks,
                    complete: completeDeloadBlock,
                    cancel: cancelDeloadBlock
                )
            }

            DashboardSection(title: "Weekly Insights") {
                CoachInsightsFeedView(insights: intelligence.insights)
            }

            DashboardSection(title: "Fatigue / Deload Risk") {
                FatigueRiskCard(risk: intelligence.fatigueRisk)
            }

            DashboardSection(title: "Muscle Fatigue Map") {
                MuscleFatigueMapCard(items: intelligence.muscleFatigue)
            }

            DashboardSection(title: "Key Habit Contributors") {
                CoachHabitContributorsCard(trends: intelligence.trends)
            }

            if !intelligence.liftInsights.isEmpty {
                DashboardSection(title: "Lift-Specific Insights") {
                    LiftProgressInsightsCard(insights: intelligence.liftInsights)
                }
            }

            DashboardSection(title: "Signal Breakdown") {
                LazyVStack(spacing: 12) {
                    ForEach(intelligence.readiness.factors) { factor in
                        ReadinessFactorCard(factor: factor)
                    }
                }
            }

            DashboardSection(title: "Suggested Workout Adjustment") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("User controlled", systemImage: "hand.raised.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .textCase(.uppercase)

                        Text(intelligence.readiness.workoutAdjustment)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(intelligence.readiness.recoveryNote)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            FitnessCard(style: .hero) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        ExerciseIconTile(
                            iconKey: ExerciseIconMapper.splitIconKey(for: summary.recommendedSplitName ?? ""),
                            title: nil,
                            size: 58,
                            style: .compact
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Next Workout")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.mutedText)
                                .textCase(.uppercase)

                            Text(summary.recommendedSplitName ?? "No recommendation yet")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        }

                        Spacer()
                        CoachBadgeView(state: summary.recommendedSplitName == nil ? .baseline : .ready)
                    }

                    Text(summary.reason)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            }

            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next Training Decision")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.mutedText)
                                .textCase(.uppercase)
                            Text(weeklyReview?.nextDecision.title ?? "Preparing recommendation")
                                .font(.title2.bold())
                        }
                        Spacer()
                        CoachBadgeView(state: badgeState(for: weeklyReview?.nextDecision.action ?? .buildBaseline))
                    }

                    Text("Next: \(weeklyReview?.nextDecision.recommendedSplitName ?? summary.recommendedSplitName ?? "Any split") - \((weeklyReview?.nextDecision.recommendedMode ?? .full).displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text(weeklyReview?.nextDecision.reason ?? "Peakline is preparing your current weekly training decision.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            }

            DashboardSection(title: "Today's Targets") {
                if targetSuggestions.isEmpty {
                    FitnessCard {
                        Text("Complete a workout from your split to get load and rep targets.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }
                } else {
                    ForEach(targetSuggestions, id: \.self) { suggestion in
                        FitnessCard {
                            ExerciseTargetRow(suggestion: suggestion)
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
                                .font(.subheadline)
                                .foregroundStyle(appTheme.mutedText)
                        }
                    }
                } else {
                    ForEach(summary.recoveryWarnings) { warning in
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(warning.title)
                                        .font(.headline)
                                    Spacer()
                                    CoachBadgeView(state: warningBadgeState(for: warning.severity))
                                }

                                Text(warning.message)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        }
                    }
                }
            }

            DashboardSection(title: "Sleep Coaching") {
                if let recommendation = sleepDashboardSummary.adaptiveRecommendation {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(recommendation.title)
                                    .font(.headline)
                                Spacer()
                                CoachBadgeView(state: badgeState(for: recommendation.level))
                            }

                            Text(recommendation.message)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.mutedText)

                            if !recommendation.basedOn.isEmpty {
                                Text("Based on: \(recommendation.basedOn.map(\.displayName).joined(separator: ", ")).")
                                    .font(.caption)
                                    .foregroundStyle(appTheme.colors.textTertiary)
                            }
                        }
                    }
                }

                if sleepDashboardSummary.coachingInsights.isEmpty {
                    FitnessCard {
                        Text("Keep tracking sleep and workouts to unlock personalised sleep-performance coaching.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }
                } else {
                    ForEach(sleepDashboardSummary.coachingInsights.prefix(3)) { insight in
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(insight.title)
                                        .font(.headline)
                                    Spacer()
                                    CoachBadgeView(state: badgeState(for: insight.severity))
                                }

                                Text(insight.message)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        }
                    }
                }
            }

            DashboardSection(title: "This Week Review") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink {
                            WeeklyReviewView()
                        } label: {
                            Label("Open weekly review", systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .accessibilityIdentifier("coach-weekly-review-open")

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

                        HStack(spacing: 10) {
                            MetricTile(label: "PRs", value: "\(weeklyReview?.prCount ?? 0)", caption: "This week", systemImage: "trophy")
                            MetricTile(label: "Balance", value: splitBalanceText, caption: nil, systemImage: "scale.3d")
                        }

                        if summary.weeklyInsights.isEmpty {
                            Text("Finish workouts to build a weekly summary.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.mutedText)
                        } else {
                            ForEach(summary.weeklyInsights, id: \.self) { insight in
                                Text(insight)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        }
                    }
                }
            }

            insightList(title: "Progress Opportunities", insights: progressOpportunityInsights, empty: "No obvious load jumps yet. Repeat targets and build clean reps.")
            insightList(title: "Watchlist", insights: weeklyReview?.watchlist ?? [], empty: "No major fatigue or plateau warnings right now.")

            DashboardSection(title: "Recent PRs") {
                if recentPRs.isEmpty {
                    FitnessCard {
                        Text("PRs will appear here when a completed working set beats prior history.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }
                } else {
                    ForEach(recentPRs) { pr in
                        FitnessCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pr.exerciseName)
                                        .font(.headline)
                                    Text(pr.improvementDescription)
                                        .font(.subheadline)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("coach-screen")
        .navigationDestination(item: $route) { route in
            switch route {
            case .actionHistory:
                CoachActionHistoryDetailView(
                    entries: coachActionHistory,
                    feedback: recommendationFeedback
                )
            }
        }
        .onAppear {
            sleepSettings = sleepSettingsStore.load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            refreshCoachAfterFirstMount()
        }
        .onDisappear {
            deferredCoachRefreshWorkItem?.cancel()
            deferredFullCoachSnapshotWorkItem?.cancel()
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
        }
        .redacted(reason: hasLoadedCoachSnapshot ? [] : .placeholder)
        .allowsHitTesting(hasLoadedCoachSnapshot)
        .animation(AppMotion.gentleFade(reduceMotion: reduceMotion), value: hasLoadedCoachSnapshot)
        .sheet(isPresented: $showingCoachCheckIn) {
            DailyCheckInSheet(existingCheckIn: coachSnapshot.readiness.checkIn)
        }
    }

    private func refreshCoachAfterFirstMount() {
        deferredCoachRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshSleepAnalytics()
            if initialSnapshot != nil, hasLoadedCoachSnapshot, lastCoachSnapshotSignature == nil {
                PerformanceTracer.mark(.coachSnapshot, "warm_start reused_today_snapshot")
                lastCoachSnapshotSignature = currentCoachSnapshotSignature
                scheduleFullCoachSnapshotRefresh()
            } else {
                refreshCoachSnapshot()
            }
            refreshCoachDerivedMetrics()
            refreshWeeklyReview()
        }
        deferredCoachRefreshWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleFullCoachSnapshotRefresh() {
        deferredFullCoachSnapshotWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            PerformanceTracer.mark(.coachSnapshot, "deferred_full_refresh")
            refreshCoachSnapshot(force: true)
        }
        deferredFullCoachSnapshotWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func refreshSleepAnalytics(force: Bool = false) {
        let signature = currentSleepAnalyticsSignature
        guard force || signature != lastSleepAnalyticsSignature else { return }

        sleepSnapshot = PerformanceTracer.trace(.coachSleepAnalytics) {
            sleepAnalyticsStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: recentCompletedSessions,
                settings: sleepSettings,
                workoutLimit: 20,
                force: force
            )
        }
        lastSleepAnalyticsSignature = signature
    }

    private func refreshCoachSnapshot(force: Bool = false) {
        let signature = currentCoachSnapshotSignature
        guard force || signature != lastCoachSnapshotSignature else { return }

        coachSnapshot = makeCoachSnapshot()
        lastCoachSnapshotSignature = signature
        hasLoadedCoachSnapshot = true
    }

    private func refreshWeeklyReview(force: Bool = false) {
        weeklyReviewTask?.cancel()
        let signature = currentWeeklyReviewSignature
        guard force || signature != lastWeeklyReviewSignature else { return }

        let splitSnapshots = activeSplits.map(TrainingSplitSnapshot.init)
        let sessionSnapshots = recentCompletedSessions.map(WorkoutAnalyticsSession.init)
        weeklyReviewTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                PerformanceTracer.trace(.coachWeeklyReview) {
                    WeeklyReviewBuilder().build(activeSplits: splitSnapshots, completedSessions: sessionSnapshots)
                }
            }.value

            guard !Task.isCancelled else { return }
            weeklyReview = result
            lastWeeklyReviewSignature = signature
        }
    }

    private func refreshCoachDerivedMetrics(force: Bool = false) {
        coachDerivedTask?.cancel()
        let signature = currentCoachDerivedSignature
        guard force || signature != lastCoachDerivedSignature else { return }

        let splitSnapshots = activeSplits.map(TrainingSplitSnapshot.init)
        let sessionSnapshots = recentCompletedSessions.map(WorkoutAnalyticsSession.init)
        coachDerivedTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                PerformanceTracer.trace(.coachDerivedMetrics) {
                    CoachDerivedMetrics.make(
                        activeSplits: splitSnapshots,
                        completedSessions: sessionSnapshots
                    )
                }
            }.value

            guard !Task.isCancelled else { return }
            summary = result.summary
            recentPRs = result.recentPRs
            targetSuggestions = result.targetSuggestions
            weeklyWorkoutCount = result.weeklyWorkoutCount
            weeklyWorkingSetCount = result.weeklyWorkingSetCount
            progressOpportunityInsights = result.progressOpportunityInsights
            lastCoachDerivedSignature = signature
        }
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
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

    private var splitBalanceText: String {
        guard let split = weeklyReview?.splitConsistency else {
            return "--"
        }
        return "\(split.pushCount)/\(split.pullCount)/\(split.legsCount)"
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
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            } else {
                ForEach(insights) { insight in
                    FitnessCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.headline)
                                Text(insight.message)
                                    .font(.subheadline)
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

private struct CoachDerivedMetrics: Sendable {
    let summary: CoachRecommendationSummary
    let recentPRs: [PRRecord]
    let targetSuggestions: [TargetSuggestion]
    let weeklyWorkoutCount: Int
    let weeklyWorkingSetCount: Int
    let progressOpportunityInsights: [CoachInsight]

    static func make(
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> CoachDerivedMetrics {
        let summary = CoachRecommendationEngine().makeSummary(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let prRecords = TrainingAnalyticsService().prTimeline(from: completedSessions)
        let targetSuggestions = makeTargetSuggestions(
            summary: summary,
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 7 * 24 * 60 * 60)
        let weekSessions = completedSessions.filter {
            $0.completed && $0.date >= week.start && $0.date < week.end
        }
        let workingSets = weekSessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap { log in
                log.setLogs.filter { $0.completed && !$0.isWarmup }
            }.count
        }
        let progressInsights = targetSuggestions
            .filter { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }
            .prefix(4)
            .map { suggestion in
                CoachInsight(
                    title: suggestion.exerciseName,
                    message: suggestion.reason,
                    severity: .positive,
                    relatedExerciseName: suggestion.exerciseName,
                    relatedSplitName: summary.recommendedSplitName
                )
            }

        return CoachDerivedMetrics(
            summary: summary,
            recentPRs: Array(prRecords.prefix(3)),
            targetSuggestions: targetSuggestions,
            weeklyWorkoutCount: weekSessions.count,
            weeklyWorkingSetCount: workingSets,
            progressOpportunityInsights: progressInsights
        )
    }

    private static func makeTargetSuggestions(
        summary: CoachRecommendationSummary,
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> [TargetSuggestion] {
        guard let recommendedSplit = activeSplits.first(where: { $0.name == summary.recommendedSplitName }) else {
            return []
        }

        return recommendedSplit.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(4)
            .map { exercise in
                TargetSuggestionService().suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
            }
    }
}

private extension CoachRecommendationSummary {
    static var placeholder: CoachRecommendationSummary {
        CoachRecommendationSummary(
            recommendedSplitName: nil,
            reason: "Preparing recommendation.",
            exerciseRecommendations: [],
            recoveryWarnings: [],
            weeklyInsights: []
        )
    }
}

private enum CoachRoute: Hashable, Identifiable {
    case actionHistory

    var id: Self { self }
}
