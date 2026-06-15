import SwiftData
import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            CoachContentView()
        }
    }
}

@MainActor
final class CoachRouteSnapshotStore {
    static let shared = CoachRouteSnapshotStore()

    private(set) var snapshot: CoachIntelligenceSnapshot?
    private(set) var signature: String?

    private init() {}

    func update(snapshot: CoachIntelligenceSnapshot, signature: String, source: String) {
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_begin source=\(source) main=\(Thread.isMainThread) contains_model_checkIn=\(snapshot.readiness.checkIn != nil)"
        )
        self.snapshot = snapshot.routeCacheValueSnapshot
        self.signature = signature
        PerformanceTracer.mark(.coachSnapshot, "route_snapshot_store update source=\(source)")
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_end source=\(source) stored_model_checkIn=\(self.snapshot?.readiness.checkIn != nil)"
        )
    }
}

private extension CoachIntelligenceSnapshot {
    var routeCacheValueSnapshot: CoachIntelligenceSnapshot {
        CoachIntelligenceSnapshot(
            readiness: readiness.routeCacheValueScore,
            weeklySummary: weeklySummary,
            trends: trends,
            insights: insights,
            fatigueRisk: fatigueRisk,
            muscleFatigue: muscleFatigue,
            liftInsights: liftInsights,
            adaptiveGuidance: adaptiveGuidance,
            diagnostics: diagnostics
        )
    }
}

private extension ReadinessScore {
    var routeCacheValueScore: ReadinessScore {
        ReadinessScore(
            value: value,
            category: category,
            confidence: confidence,
            recommendation: recommendation,
            factors: factors,
            generatedAt: generatedAt,
            checkIn: nil,
            workoutAdjustment: workoutAdjustment,
            recoveryNote: recoveryNote
        )
    }
}

struct CoachRouteDestinationView: View {
    @Environment(\.scenePhase) private var scenePhase

    let initialSnapshot: CoachIntelligenceSnapshot?
    let backButtonTitle: String?
    let onBack: (() -> Void)?

    init(
        initialSnapshot: CoachIntelligenceSnapshot? = nil,
        backButtonTitle: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.initialSnapshot = initialSnapshot?.routeCacheValueSnapshot
        self.backButtonTitle = backButtonTitle
        self.onBack = onBack
    }

    var body: some View {
        let routeSnapshot = initialSnapshot ?? CoachRouteSnapshotStore.shared.snapshot

        if scenePhase == .active {
            DeferredCoachDestinationView(
                initialSnapshot: routeSnapshot,
                backButtonTitle: backButtonTitle,
                onBack: onBack
            )
        } else {
            CoachInactiveDestinationPlaceholder(scenePhaseDescription: String(describing: scenePhase))
        }
    }
}

struct CoachInactiveDestinationPlaceholder: View {
    let scenePhaseDescription: String

    var body: some View {
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "inactive_placeholder scenePhase=\(scenePhaseDescription)")
        Color.clear
            .accessibilityHidden(true)
    }
}

struct DeferredCoachDestinationView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let initialSnapshot: CoachIntelligenceSnapshot?
    let backButtonTitle: String?
    let onBack: (() -> Void)?

    @State private var showFullContent = false
    @State private var showWarmStartContent = false

    var body: some View {
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "body showFullContent=\(showFullContent) showWarmStartContent=\(showWarmStartContent) initialSnapshot=\(initialSnapshot != nil)")
        ZStack {
            if scenePhase != .active {
                inactivePlaceholder
            } else if showFullContent {
                CoachContentView(initialSnapshot: initialSnapshot)
                    .transition(.opacity)
            } else if showWarmStartContent {
                coachWarmStartView
                    .transition(.opacity)
            } else {
                firstFrameShell
            }
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .background {
            if scenePhase == .active {
                CoachRouteFrameProbe(label: "deferredCoach.root")
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach-route-screen")
        .onAppear {
            PerformanceTracer.mark(.todayCoachDestinationAppear, "root_onAppear showFullContent=\(showFullContent) initialSnapshot=\(initialSnapshot != nil)")
            guard !showWarmStartContent && !showFullContent else { return }
            DispatchQueue.main.async {
                PerformanceTracer.mark(.todayCoachContentMount, "show_warm_start_content")
                withAnimation(AppMotion.gentleFade(reduceMotion: reduceMotion)) {
                    showWarmStartContent = true
                }
                PerformanceTracer.trace(.todayCoachContentMount) {
                    withAnimation(AppMotion.gentleFade(reduceMotion: reduceMotion)) {
                        showFullContent = true
                    }
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                PerformanceTracer.mark(.todayCoachContentMount, "task_skip scenePhase=\(String(describing: scenePhase))")
                return
            }
            guard !showFullContent else { return }
            PerformanceTracer.mark(.todayCoachContentMount, "task_start reduceMotion=\(reduceMotion)")
            await Task.yield()
            guard !Task.isCancelled, scenePhase == .active else {
                PerformanceTracer.mark(.todayCoachContentMount, "task_cancelled_or_inactive scenePhase=\(String(describing: scenePhase))")
                return
            }
            PerformanceTracer.mark(.todayCoachContentMount, "before_showFullContent")
            PerformanceTracer.trace(.todayCoachContentMount) {
                withAnimation(AppMotion.gentleFade(reduceMotion: reduceMotion)) {
                    showFullContent = true
                }
            }
            PerformanceTracer.mark(.todayCoachContentMount, "after_showFullContent")
        }
    }

    @ViewBuilder
    private var inactivePlaceholder: some View {
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "inactive_placeholder scenePhase=\(String(describing: scenePhase))")
        Color.clear
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .accessibilityHidden(true)
    }

    private var firstFrameShell: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var coachWarmStartView: some View {
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "warm_start_body initialSnapshot=\(initialSnapshot != nil)")
        if let initialSnapshot {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                    FitnessScreenHeader(
                        title: "Coach",
                        subtitle: "Readiness, targets, and recovery.",
                        systemImage: "sparkles"
                    )

                    ReadinessDetailHeaderCard(readiness: initialSnapshot.readiness)

                    DashboardSection(title: "Recommendation") {
                        ReadinessRecommendationCard(readiness: initialSnapshot.readiness)
                    }

                    DashboardSection(title: "Weekly Summary") {
                        WeeklyCoachSummaryCard(summary: initialSnapshot.weeklySummary)
                    }
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
            }
        } else {
            FitnessScreen(
                title: "Coach",
                subtitle: "Readiness, targets, and recovery.",
                systemImage: "sparkles"
            ) {
                ReadinessDetailHeaderCard(readiness: CoachIntelligenceService.emptySnapshot().readiness)

                DashboardSection(title: "Recommendation") {
                    ReadinessRecommendationCard(readiness: CoachIntelligenceService.emptySnapshot().readiness)
                }
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
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
    @State private var route: CoachRoute?
    @State private var previewRoute: CoachWorkoutPreviewRoute?
    @State private var weeklyReview: WeeklyReview?
    @State private var lastWeeklyReviewSignature: String?
    @State private var weeklyReviewTask: Task<Void, Never>?
    @State private var summary = CoachRecommendationSummary.placeholder
    @State private var recentPRs: [PRRecord] = []
    @State private var targetSuggestions: [TargetSuggestion] = []
    @State private var weeklyWorkoutCount = 0
    @State private var weeklyWorkingSetCount = 0
    @State private var progressOpportunityInsights: [CoachInsight] = []
    @State private var dailyDecision = CoachDailyDecision.placeholder
    @State private var practicalWeeklyReview = CoachWeeklyReviewSnapshot.placeholder
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
    private let modePlanner = WorkoutModePlanner()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let initialSnapshot: CoachIntelligenceSnapshot?

    init(initialSnapshot: CoachIntelligenceSnapshot? = nil) {
        self.initialSnapshot = initialSnapshot?.routeCacheValueSnapshot
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
            let routeSafeSnapshot = initialSnapshot.routeCacheValueSnapshot
            _coachSnapshot = State(initialValue: routeSafeSnapshot)
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
        let _ = PerformanceTracer.mark(.todayCoachDestinationBody, "CoachContentView body hasLoaded=\(hasLoadedCoachSnapshot) initialSnapshot=\(initialSnapshot != nil)")
        let intelligence = currentCoachSnapshot

        FitnessScreen(
            title: "Coach",
            subtitle: "Readiness, targets, and recovery.",
            systemImage: "sparkles"
        ) {
            FitnessCard(style: .hero) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ExerciseIconTile(
                            iconKey: ExerciseIconMapper.splitIconKey(for: dailyDecision.recommendedSplitName ?? ""),
                            title: nil,
                            size: 58,
                            style: .compact
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Today's Call")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(dailyDecision.headline)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("coach-todays-call")
                        }

                        Spacer(minLength: 10)

                        VStack(alignment: .trailing, spacing: 8) {
                            CoachBadgeView(state: dailyDecision.badgeState)
                            Text(dailyDecision.confidenceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textTertiary)
                        }
                    }

                    if dailyDecision.recommendedSplitName != nil {
                        Button {
                            openRecommendedPreview()
                        } label: {
                            Label(dailyDecision.primaryActionTitle, systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .accessibilityIdentifier("coach-primary-action")
                        .disabled(!dailyDecision.canOpenPreview)
                    }

                    if let targetLine = dailyDecision.targetLine {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Main Target")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(targetLine)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(dailyDecision.shortReason)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Next step")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(dailyDecision.nextStep)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach-hero-card")

            DashboardSection(title: "Why this?") {
                TrainingCallAuditCard(snapshot: dailyDecision.trainingCall)
                .accessibilityIdentifier("coach-why-this-section")
            }

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
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(dailyDecision.targetFallback)
                                .font(.subheadline)
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
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(appTheme.colors.textTertiary)
                                    .textCase(.uppercase)

                                Text("\(dailyDecision.recommendedMode.displayName) Mode")
                                    .font(.title3.bold())
                                    .foregroundStyle(appTheme.colors.textPrimary)

                                Text(dailyDecision.modeReason)
                                    .font(.subheadline)
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
                        route = .preferences
                    } label: {
                        DashboardActionTile(
                            title: "Coach Preferences",
                            subtitle: "\(coachPreferencesSnapshot.aggressiveness.displayName), \(coachPreferencesSnapshot.trainingPriority.displayName.lowercased()) priority",
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("coach-preferences-open")

                    Button {
                        route = .weeklyReview
                    } label: {
                        DashboardActionTile(
                            title: "Weekly Review",
                            subtitle: "\(weeklyWorkoutCount) workouts, \(weeklyWorkingSetCount) working sets",
                            systemImage: "chart.bar.doc.horizontal"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("coach-weekly-review-open")
                }
            }

            DashboardSection(title: "Weekly Review") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
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

                        Button {
                            route = .weeklyReview
                        } label: {
                            Label("Open weekly review", systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .accessibilityIdentifier("coach-weekly-review-open-detail")
                    }
                }
                .accessibilityIdentifier("coach-weekly-review-section")
            }

            DashboardSection(title: "Today's Check-In") {
                CheckInStatusCard(checkIn: intelligence.readiness.checkIn)
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
                    route = .actionHistory
                } label: {
                    Label("Review action history", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .accessibilityIdentifier("coach-history-detail-open")
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

            insightList(title: "Progress Opportunities", insights: progressOpportunityInsights, empty: "No obvious load jumps yet. Repeat targets and build clean reps.")
            insightList(title: "Watchlist", insights: weeklyReview?.watchlist ?? [], empty: "No major fatigue or plateau warnings right now.")

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
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("coach-screen")
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach-screen")
        .navigationDestination(item: $route) { route in
            switch route {
            case .actionHistory:
                CoachActionHistoryDetailView(
                    entries: coachActionHistory,
                    feedback: recommendationFeedback
                )
            case .preferences:
                CoachPreferencesView()
            case .weeklyReview:
                WeeklyReviewView()
            }
        }
        .navigationDestination(item: $previewRoute) { route in
            WorkoutPreviewRouteView(split: route.split, initialMode: route.mode)
        }
        .onAppear {
            PerformanceTracer.mark(.todayCoachDestinationAppear, "CoachContentView onAppear begin hasLoaded=\(hasLoadedCoachSnapshot) initialSnapshot=\(initialSnapshot != nil)")
            sleepSettings = sleepSettingsStore.load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            refreshCoachAfterFirstMount()
            PerformanceTracer.mark(.todayCoachDestinationAppear, "CoachContentView onAppear end")
        }
        .onDisappear {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.onDisappear cancel_tasks begin")
            deferredCoachRefreshWorkItem?.cancel()
            deferredFullCoachSnapshotWorkItem?.cancel()
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.onDisappear cancel_tasks end")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.willResignActive cancel_tasks begin")
            deferredCoachRefreshWorkItem?.cancel()
            deferredFullCoachSnapshotWorkItem?.cancel()
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.willResignActive cancel_tasks end")
        }
        .redacted(reason: hasLoadedCoachSnapshot ? [] : .placeholder)
    }

    private func refreshCoachAfterFirstMount() {
        deferredCoachRefreshWorkItem?.cancel()
        PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh schedule")
        let workItem = DispatchWorkItem {
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh begin")
            refreshSleepAnalytics()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh after_sleep_analytics")
            if initialSnapshot != nil, hasLoadedCoachSnapshot, lastCoachSnapshotSignature == nil {
                PerformanceTracer.mark(.coachSnapshot, "warm_start reused_today_snapshot")
                let signature = currentCoachSnapshotSignature
                lastCoachSnapshotSignature = signature
                CoachRouteSnapshotStore.shared.update(snapshot: coachSnapshot, signature: signature, source: "coach_warm_start")
                scheduleFullCoachSnapshotRefresh()
            } else {
                refreshCoachSnapshot()
            }
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh after_coach_snapshot")
            refreshCoachDerivedMetrics()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh after_derived_schedule")
            refreshWeeklyReview()
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_refresh end")
        }
        deferredCoachRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func scheduleFullCoachSnapshotRefresh() {
        deferredFullCoachSnapshotWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            PerformanceTracer.mark(.coachSnapshot, "deferred_full_refresh")
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_full_snapshot begin")
            refreshCoachSnapshot(force: true)
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.deferred_full_snapshot end")
        }
        deferredFullCoachSnapshotWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
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
                workouts: recentCompletedSessions,
                settings: sleepSettings,
                workoutLimit: 20,
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
        CoachRouteSnapshotStore.shared.update(snapshot: coachSnapshot, signature: signature, source: "coach")
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

            guard !Task.isCancelled else { return }
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

            guard !Task.isCancelled else { return }
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
        let displayedTargets = displayedTargetSuggestions(targetSuggestions, mode: recommendedMode)
        let primaryTarget = primaryTarget(from: displayedTargets, mode: recommendedMode)
        let whySignals = makeWhySignals(
            splitName: splitName,
            intelligence: intelligence,
            summary: summary,
            weeklyReview: weeklyReview,
            primaryTarget: primaryTarget
        )
        let canOpenPreview = recommendedSplit(named: splitName) != nil

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
                splitBalance: "Push/Pull/Legs balance will appear once the week has completed sessions.",
                recoveryNote: intelligence.weeklySummary.recommendedFocus
            )
        }

        return CoachWeeklyReviewSnapshot(
            bestWin: weeklyReview.highlights.first?.message ?? "No clear PR win yet this week.",
            mainRisk: weeklyReview.watchlist.first?.message ?? "No major risk is standing out right now.",
            nextAdjustment: weeklyReview.nextDecision.reason,
            splitBalance: "Push \(weeklyReview.splitConsistency.pushCount) / Pull \(weeklyReview.splitConsistency.pullCount) / Legs \(weeklyReview.splitConsistency.legsCount). \(weeklyReview.splitConsistency.balanceDescription)",
            recoveryNote: intelligence.weeklySummary.recommendedFocus
        )
    }

    private func recommendedPreviewMode(
        canonicalDecision: TrainingDecision,
        intelligence: CoachIntelligenceSnapshot,
        weeklyReview: WeeklyReview?,
        targetSuggestions: [TargetSuggestion]
    ) -> WorkoutMode {
        if canonicalDecision.recommendedMode == .recovery || weeklyReview?.nextDecision.recommendedMode == .recovery {
            return .recovery
        }

        switch intelligence.adaptiveGuidance.mode {
        case .recoveryFocus:
            return .recovery
        case .reduce:
            return .quick
        case .push:
            let hasLoadPush = targetSuggestions.contains { suggestion in
                suggestion.recommendationType == .increaseLoad || suggestion.recommendationType == .addReps
            }
            return hasLoadPush ? .heavy : .full
        case .maintain:
            return .full
        }
    }

    private func displayedTargetSuggestions(_ suggestions: [TargetSuggestion], mode: WorkoutMode) -> [TargetSuggestion] {
        suggestions.map { suggestion in
            modePlanner.modeAdjustedSuggestion(suggestion, mode: mode)
        }
    }

    private func primaryTarget(from suggestions: [TargetSuggestion], mode: WorkoutMode) -> TargetSuggestion? {
        suggestions.max { lhs, rhs in
            let leftScore = primaryTargetScore(for: lhs, mode: mode)
            let rightScore = primaryTargetScore(for: rhs, mode: mode)
            if leftScore == rightScore {
                return lhs.confidence < rhs.confidence
            }
            return leftScore < rightScore
        }
    }

    private func primaryTargetScore(for suggestion: TargetSuggestion, mode: WorkoutMode) -> Int {
        switch mode {
        case .recovery:
            switch suggestion.recommendationType {
            case .fatigueRisk:
                return 90
            case .repeatTarget:
                return 80
            case .reduceLoad:
                return 75
            case .possiblePlateau:
                return 70
            case .baseline:
                return 65
            case .addReps:
                return 55
            case .increaseLoad:
                return 50
            case .ready:
                return 60
            }
        case .heavy:
            switch suggestion.recommendationType {
            case .increaseLoad:
                return 90
            case .addReps:
                return 80
            case .possiblePlateau:
                return 72
            case .repeatTarget:
                return 66
            case .baseline:
                return 58
            case .reduceLoad:
                return 52
            case .fatigueRisk:
                return 45
            case .ready:
                return 70
            }
        case .full, .quick:
            switch suggestion.recommendationType {
            case .increaseLoad:
                return 90
            case .addReps:
                return 85
            case .repeatTarget:
                return 76
            case .possiblePlateau:
                return 72
            case .baseline:
                return 62
            case .reduceLoad:
                return 58
            case .fatigueRisk:
                return 54
            case .ready:
                return 70
            }
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
            return "\(format(weight))kg x \(reps)"
        case let (.some(weight), .none):
            return "\(format(weight))kg"
        case let (.none, .some(reps)):
            return "\(reps)+ reps"
        case (.none, .none):
            return "Log clean sets"
        }
    }

    private func summaryText(from signals: [CoachDecisionSignal], fallback: String) -> String {
        let message = signals.prefix(3).map(\.message).joined(separator: " ")
        return message.isEmpty ? fallback : message
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
        guard
            let split = recommendedSplit(named: dailyDecision.recommendedSplitName)
                ?? activeSplits.first(where: { $0.name == dailyDecision.recommendedSplitName })
        else { return }

        let route = CoachWorkoutPreviewRoute(
            split: WorkoutPreviewSplit(split),
            mode: dailyDecision.recommendedMode
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

        AppMotion.smoothNavigate(reduceMotion: reduceMotion) {
            previewRoute = route
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
        let canonicalDecision = TrainingDecisionService().decision(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let summary = CoachRecommendationEngine().makeSummary(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let prRecords = TrainingAnalyticsService().prTimeline(from: completedSessions)
        let targetSuggestions = makeTargetSuggestions(
            splitName: canonicalDecision.recommendedSplitName,
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
                    relatedSplitName: canonicalDecision.recommendedSplitName
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
        splitName: String?,
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> [TargetSuggestion] {
        guard let recommendedSplit = activeSplits.first(where: { $0.name == splitName }) else {
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
            weeklyInsights: [],
            trainingDecision: TrainingDecision(
                recommendedSplitName: nil,
                recommendedMode: .full,
                action: .buildBaseline,
                title: "Preparing recommendation",
                reason: "Preparing recommendation."
            )
        )
    }
}

private struct CoachDailyDecision: Equatable {
    let recommendedSplitName: String?
    let recommendedMode: WorkoutMode
    let headline: String
    let targetLine: String?
    let shortReason: String
    let confidenceLabel: String
    let badgeState: CoachBadgeState
    let canOpenPreview: Bool
    let primaryActionTitle: String
    let nextStep: String
    let whySignals: [CoachDecisionSignal]
    let primaryTarget: TargetSuggestion?
    let additionalTargetCount: Int
    let targetFallback: String
    let modeReason: String
    let trainingCall: TrainingCallSnapshot

    static let placeholder = CoachDailyDecision(
        recommendedSplitName: nil,
        recommendedMode: .full,
        headline: "Preparing Today's Call",
        targetLine: nil,
        shortReason: "Peakline is preparing your next training decision.",
        confidenceLabel: "Building confidence",
        badgeState: .baseline,
        canOpenPreview: false,
        primaryActionTitle: "Open Preview",
        nextStep: "Next: wait a moment while Peakline refreshes your current coaching snapshot.",
        whySignals: [
            CoachDecisionSignal(
                title: "Rotation",
                message: "Coach is checking your recent split rotation.",
                systemImage: "calendar.badge.clock"
            ),
            CoachDecisionSignal(
                title: "Recovery",
                message: "Coach is refreshing readiness and recovery signals.",
                systemImage: "gauge.with.dots.needle.bottom.50percent"
            )
        ],
        primaryTarget: nil,
        additionalTargetCount: 0,
        targetFallback: "Complete a workout to unlock a clearer next target.",
        modeReason: "Peakline is confirming which mode fits today best.",
        trainingCall: .placeholder
    )
}

private struct CoachWeeklyReviewSnapshot: Equatable {
    let bestWin: String
    let mainRisk: String
    let nextAdjustment: String
    let splitBalance: String
    let recoveryNote: String

    static let placeholder = CoachWeeklyReviewSnapshot(
        bestWin: "Finish workouts to build a weekly win.",
        mainRisk: "The weekly watchlist is still building.",
        nextAdjustment: "Keep logging sessions so the next adjustment gets sharper.",
        splitBalance: "Weekly split balance is still building.",
        recoveryNote: "Recovery guidance will appear once enough recent signals are available."
    )
}

private struct CoachDecisionSignal: Identifiable, Equatable {
    let title: String
    let message: String
    let systemImage: String

    var id: String {
        "\(title)|\(message)|\(systemImage)"
    }
}

private struct CoachDecisionSignalRow: View {
    @Environment(\.appTheme) private var appTheme

    let signal: CoachDecisionSignal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FitnessIconBadge(systemImage: signal.systemImage, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(signal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .textCase(.uppercase)

                Text(signal.message)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }
}

private struct CoachWeeklyReviewRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textTertiary)
                .textCase(.uppercase)

            Text(message)
                .font(.subheadline)
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
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("Applied or bypassed workout adjustments will appear here.")
                            .font(.subheadline)
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
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(entry.shortReason)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
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
}

private struct CoachWorkoutPreviewRoute: Hashable, Identifiable {
    let split: WorkoutPreviewSplit
    let mode: WorkoutMode

    var id: String {
        "\(split.id.uuidString)-\(mode.rawValue)"
    }
}
