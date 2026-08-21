import SwiftData
import SwiftUI

struct CoachRouteRenderSnapshot: @unchecked Sendable {
    /// Monotonic source generation for the complete route payload. Readiness,
    /// the training call, and the recommended split must be published as one
    /// generation so a newer intelligence score cannot be paired with an
    /// older actionable decision.
    let sourceGeneration: Int
    let intelligence: CoachIntelligenceSnapshot
    let weeklyReview: WeeklyReview?
    let derivedMetrics: CoachDerivedMetrics
    let sleepAnalytics: SleepAnalyticsSnapshot
    let dailyDecision: CoachDailyDecision
    let practicalWeeklyReview: CoachWeeklyReviewSnapshot
    let recommendedSplit: WorkoutPreviewSplit?

    init(
        intelligence: CoachIntelligenceSnapshot,
        weeklyReview: WeeklyReview?,
        derivedMetrics: CoachDerivedMetrics,
        sleepAnalytics: SleepAnalyticsSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit? = nil,
        sourceGeneration: Int = 0
    ) {
        self.sourceGeneration = sourceGeneration
        self.intelligence = intelligence.routeCacheValueSnapshot
        self.weeklyReview = weeklyReview
        self.derivedMetrics = derivedMetrics
        self.sleepAnalytics = sleepAnalytics
        self.recommendedSplit = recommendedSplit

        let primaryTarget = derivedMetrics.targetSuggestions.first
        let badgeState: CoachBadgeState
        if trainingCall.recommendedMode == .recovery {
            badgeState = .recovery
        } else if let primaryTarget {
            badgeState = CoachBadgeState(recommendationType: primaryTarget.recommendationType)
        } else {
            badgeState = .baseline
        }

        let splitName = trainingCall.recommendedSplitName
        self.dailyDecision = CoachDailyDecision(
            recommendedSplitName: splitName,
            recommendedMode: trainingCall.recommendedMode,
            headline: splitName ?? trainingCall.title,
            targetLine: trainingCall.targetSummary,
            shortReason: trainingCall.reason,
            confidenceLabel: trainingCall.confidence.displayName,
            badgeState: badgeState,
            canOpenPreview: splitName != nil,
            primaryActionTitle: "Open \(trainingCall.recommendedMode.displayName) Preview",
            nextStep: splitName.map { "Next: preview \($0), adjust if needed, then start the session." }
                ?? "Create or activate a split to prepare a workout preview.",
            whySignals: Array(trainingCall.auditSignals.prefix(3)).enumerated().map { index, signal in
                CoachDecisionSignal(
                    title: index == 0 ? "Programme" : "Signal \(index + 1)",
                    message: signal,
                    systemImage: index == 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                )
            },
            primaryTarget: primaryTarget,
            additionalTargetCount: max(0, derivedMetrics.targetSuggestions.count - (primaryTarget == nil ? 0 : 1)),
            targetFallback: "Complete clean working sets to sharpen the next target.",
            modeReason: trainingCall.guardrailNotes.first ?? trainingCall.reason,
            trainingCall: trainingCall
        )

        self.practicalWeeklyReview = CoachWeeklyReviewSnapshot(
            bestWin: weeklyReview?.highlights.first?.message ?? "Finish a few sessions to build a weekly win.",
            mainRisk: weeklyReview?.watchlist.first?.message ?? "No major risk is standing out right now.",
            nextAdjustment: weeklyReview?.nextDecision.reason ?? trainingCall.reason,
            splitBalance: weeklyReview.map {
                "\($0.splitConsistency.countDescription(separator: " / ")). \($0.splitConsistency.balanceDescription)"
            } ?? "Active programme coverage will appear once this week has completed sessions.",
            recoveryNote: intelligence.weeklySummary.recommendedFocus
        )
    }

    func replacing(
        intelligence: CoachIntelligenceSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit?,
        sourceGeneration: Int
    ) -> CoachRouteRenderSnapshot {
        CoachRouteRenderSnapshot(
            intelligence: intelligence,
            weeklyReview: weeklyReview,
            derivedMetrics: derivedMetrics,
            sleepAnalytics: sleepAnalytics,
            trainingCall: trainingCall,
            recommendedSplit: recommendedSplit,
            sourceGeneration: sourceGeneration
        )
    }

    func withSourceGeneration(_ sourceGeneration: Int) -> CoachRouteRenderSnapshot {
        replacing(
            intelligence: intelligence,
            trainingCall: dailyDecision.trainingCall,
            recommendedSplit: recommendedSplit,
            sourceGeneration: sourceGeneration
        )
    }
}

@MainActor
final class CoachRouteSnapshotStore {
    static let shared = CoachRouteSnapshotStore()

    private(set) var snapshot: CoachRouteRenderSnapshot?
    private(set) var signature: String?
    private(set) var sourceGeneration = 0

    private init() {}

    func update(
        snapshot: CoachRouteRenderSnapshot,
        signature: String,
        source: String,
        sourceGeneration: Int? = nil
    ) {
        let generation = sourceGeneration ?? snapshot.sourceGeneration
        guard generation >= self.sourceGeneration else {
            PerformanceTracer.mark(
                .coachSnapshot,
                "route_snapshot_store reject_older source=\(source) generation=\(generation) current=\(self.sourceGeneration)"
            )
            return
        }
        let normalizedSnapshot = snapshot.sourceGeneration == generation
            ? snapshot
            : snapshot.withSourceGeneration(generation)
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_begin source=\(source) generation=\(generation) main=\(Thread.isMainThread) contains_model_checkIn=\(normalizedSnapshot.intelligence.readiness.checkIn != nil)"
        )
        self.snapshot = normalizedSnapshot
        self.signature = signature
        self.sourceGeneration = generation
        PerformanceTracer.mark(.coachSnapshot, "route_snapshot_store update source=\(source)")
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store update_end source=\(source) generation=\(generation) stored_model_checkIn=\(self.snapshot?.intelligence.readiness.checkIn != nil)"
        )
    }

    func update(
        intelligence: CoachIntelligenceSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit?,
        fallback: CoachRouteRenderSnapshot? = nil,
        signature: String,
        sourceGeneration: Int,
        source: String
    ) {
        guard let base = snapshot ?? fallback else {
            PerformanceTracer.mark(
                .coachSnapshot,
                "route_snapshot_store skip incomplete_update source=\(source) generation=\(sourceGeneration)"
            )
            return
        }
        update(
            snapshot: base.replacing(
                intelligence: intelligence,
                trainingCall: trainingCall,
                recommendedSplit: recommendedSplit,
                sourceGeneration: sourceGeneration
            ),
            signature: signature,
            source: source,
            sourceGeneration: sourceGeneration
        )
    }

    func invalidate(source: String) {
        snapshot = nil
        signature = nil
        PerformanceTracer.mark(.coachSnapshot, "route_snapshot_store invalidate source=\(source)")
    }

    /// Reserves a monotonic publication generation before any asynchronous
    /// preparation starts. A late completion carrying an older reservation is
    /// rejected by `update`, regardless of which input family changed.
    func nextSourceGeneration() -> Int {
        sourceGeneration &+= 1
        return sourceGeneration
    }

    func resetForTesting() {
        snapshot = nil
        signature = nil
        sourceGeneration = 0
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
    @State private var liveObservationEnabled: Bool
    @State private var isLiveObservationSuspendedForPreview = false
    @State private var supportingDashboardMounted: Bool
    @StateObject private var dashboardArrival = DashboardArrivalCoordinator()
    @State private var supportingDashboardMountTask: Task<Void, Never>?
    @State private var liveObservationActivationTask: Task<Void, Never>?
    @State private var hydrationTargetML = 2_500
    @State private var nutritionGoal = NutritionGoal.empty

    private let coachIntelligence = CoachIntelligenceService()
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
        let shouldFetchLiveData = initialSnapshot == nil || liveQueriesEnabled
        self.initialSnapshot = initialSnapshot
        self.liveQueriesEnabled = shouldFetchLiveData
        _activeSplits = Query(Self.activeSplitsDescriptor(live: shouldFetchLiveData))
        _completedSessions = Query(Self.completedSessionsDescriptor(live: shouldFetchLiveData))
        _exercises = Query(Self.exercisesDescriptor(live: shouldFetchLiveData))
        _sleepSessions = Query(Self.sleepSessionsDescriptor(live: shouldFetchLiveData))
        _napSessions = Query(Self.napSessionsDescriptor(live: shouldFetchLiveData))
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor(live: shouldFetchLiveData))
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor(live: shouldFetchLiveData))
        _coachCheckIns = Query(Self.coachCheckInsDescriptor(live: shouldFetchLiveData))
        _coachActionHistory = Query(Self.coachActionHistoryDescriptor(live: shouldFetchLiveData))
        _savedDeloadBlocks = Query(Self.savedDeloadBlocksDescriptor(live: shouldFetchLiveData))
        _recommendationFeedback = Query(Self.recommendationFeedbackDescriptor(live: shouldFetchLiveData))
        _exerciseMetadata = Query(Self.exerciseMetadataDescriptor(live: shouldFetchLiveData))
        _coachPreferences = Query(Self.coachPreferencesDescriptor(live: shouldFetchLiveData))
        _splitMetadataRecords = Query(Self.splitMetadataDescriptor(live: shouldFetchLiveData))
        _liveObservationEnabled = State(initialValue: initialSnapshot == nil)
        _supportingDashboardMounted = State(initialValue: initialSnapshot == nil)
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
        }
    }

    private static func activeSplitsDescriptor(live: Bool) -> FetchDescriptor<TrainingSplit> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<TrainingSplit> { _ in false })
        }
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static func completedSessionsDescriptor(live: Bool) -> FetchDescriptor<WorkoutSession> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<WorkoutSession> { _ in false })
        }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static func exercisesDescriptor(live: Bool) -> FetchDescriptor<Exercise> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<Exercise> { _ in false })
        }
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 140
        return descriptor
    }

    private static func sleepSessionsDescriptor(live: Bool) -> FetchDescriptor<SleepSession> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<SleepSession> { _ in false })
        }
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static func napSessionsDescriptor(live: Bool) -> FetchDescriptor<NapSession> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<NapSession> { _ in false })
        }
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static func hydrationEntriesDescriptor(live: Bool) -> FetchDescriptor<HydrationEntry> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<HydrationEntry> { _ in false })
        }
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        return descriptor
    }

    private static func foodLogEntriesDescriptor(live: Bool) -> FetchDescriptor<FoodLogEntry> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<FoodLogEntry> { _ in false })
        }
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return descriptor
    }

    private static func coachCheckInsDescriptor(live: Bool) -> FetchDescriptor<DailyCoachCheckIn> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<DailyCoachCheckIn> { _ in false })
        }
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static func coachActionHistoryDescriptor(live: Bool) -> FetchDescriptor<CoachActionHistoryEntry> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<CoachActionHistoryEntry> { _ in false })
        }
        var descriptor = FetchDescriptor<CoachActionHistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static func savedDeloadBlocksDescriptor(live: Bool) -> FetchDescriptor<SavedCoachDeloadBlock> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<SavedCoachDeloadBlock> { _ in false })
        }
        var descriptor = FetchDescriptor<SavedCoachDeloadBlock>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static func recommendationFeedbackDescriptor(live: Bool) -> FetchDescriptor<CoachRecommendationFeedback> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<CoachRecommendationFeedback> { _ in false })
        }
        var descriptor = FetchDescriptor<CoachRecommendationFeedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static func exerciseMetadataDescriptor(live: Bool) -> FetchDescriptor<CoachExerciseMetadata> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<CoachExerciseMetadata> { _ in false })
        }
        var descriptor = FetchDescriptor<CoachExerciseMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static func coachPreferencesDescriptor(live: Bool) -> FetchDescriptor<CoachPreferences> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<CoachPreferences> { _ in false })
        }
        var descriptor = FetchDescriptor<CoachPreferences>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private static func splitMetadataDescriptor(live: Bool) -> FetchDescriptor<CoachSplitMetadata> {
        guard live else {
            return FetchDescriptor(predicate: #Predicate<CoachSplitMetadata> { _ in false })
        }
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

    private var presentationDailyDecision: CoachDailyDecision {
        guard currentCoachSnapshot.readiness.isProvisional else { return dailyDecision }
        return dailyDecision.neutralizedForProvisionalReadiness()
    }

    private var currentCoachSnapshotSignature: String {
        [
            signature(activeSplits, limit: 12) {
                "\($0.id.uuidString):\($0.activeRotationIndex ?? -1):\($0.updatedAt.timeIntervalSince1970)"
            },
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
            "workoutRevision:\(workoutWarmStartInvalidation.revision)",
            sleepSettingsSignature,
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    private var currentWeeklyReviewSignature: String {
        [
            signature(activeSplits, limit: 12) { split in
                "\(split.id.uuidString):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
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
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: recentCompletedSessions,
            settings: sleepSettings,
            sessionLimit: 90,
            workoutLimit: 20,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

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
                    HStack(alignment: .top, spacing: 14) {
                        ExerciseIconTile(
                            iconKey: ExerciseIconMapper.splitIconKey(for: dailyDecision.recommendedSplitName ?? ""),
                            title: nil,
                            size: 50,
                            style: .compact
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Today's Call")
                                .font(AppTypography.eyebrow)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(dailyDecision.headline)
                                .font(AppTypography.heroTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("coach-todays-call")
                        }

                        Spacer(minLength: 10)

                        VStack(alignment: .trailing, spacing: 8) {
                            CoachBadgeView(state: dailyDecision.badgeState)
                            Text(dailyDecision.confidenceLabel)
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textTertiary)
                        }
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
                            Text("Next step")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textTertiary)
                                .textCase(.uppercase)

                            Text(dailyDecision.nextStep)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } action: {
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
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach-hero-card")

            if previewRoute == nil, supportingDashboardMounted {
                DashboardSection(title: "Why this?") {
                TrainingCallAuditCard(snapshot: dailyDecision.trainingCall)
                }
                .accessibilityIdentifier("coach-why-this-section")
                .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 0), index: 0)

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
                            subtitle: "\(coachPreferencesSnapshot.aggressiveness.displayName), \(coachPreferencesSnapshot.trainingPriority.displayName.lowercased()) priority",
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
                                PeaklineText.count(weeklyWorkingSetCount, singular: "working set")
                            ]),
                            systemImage: "chart.bar.doc.horizontal"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("coach-weekly-review-open")
                }
            }
            .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 1), index: 1)

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
            .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 2), index: 2)

            ReadinessDetailHeaderCard(readiness: intelligence.readiness)
                .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 3), index: 3)

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
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("coach-screen")
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
            readinessRefreshClock.start()
            PerformanceTracer.mark(.todayCoachDestinationAppear, "CoachContentView onAppear begin hasLoaded=\(hasLoadedCoachSnapshot) initialSnapshot=\(initialSnapshot != nil)")
            if isLiveObservationSuspendedForPreview {
                resumeLiveObservationAfterPreviewIfNeeded()
            } else if initialSnapshot != nil {
                // The startup payload already represents one coherent source generation.
                // Do not traverse every live query while the native push is mounting;
                // enable query-driven invalidation after the prepared frame can present.
                PerformanceTracer.mark(.coachSnapshot, "warm_route_payload_reused_without_mount_traversal")
                scheduleSupportingDashboardMountIfNeeded()
                scheduleLiveObservationActivationIfNeeded()
            } else {
                loadLiveObservationSettings()
                refreshLiveObservationInputs()
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
            PerformanceTracer.mark(.unsafeBreadcrumb, "coach.onDisappear cancel_tasks begin")
            coachDerivedTask?.cancel()
            weeklyReviewTask?.cancel()
            supportingDashboardMountTask?.cancel()
            supportingDashboardMountTask = nil
            liveObservationActivationTask?.cancel()
            liveObservationActivationTask = nil
            dashboardArrival.cancel()
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

    private func scheduleSupportingDashboardMountIfNeeded() {
        guard initialSnapshot != nil, !supportingDashboardMounted else { return }

        // The complete snapshot-backed decision remains visible and actionable
        // immediately. Sections below the initial viewport join after the first
        // rendered frame so their large view graph cannot delay the native push.
        supportingDashboardMountTask?.cancel()
        supportingDashboardMountTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            supportingDashboardMounted = true
            dashboardArrival.start(itemCount: 4, reduceMotion: reduceMotion)
            supportingDashboardMountTask = nil
        }
    }

    private func scheduleLiveObservationActivationIfNeeded() {
        guard liveQueriesEnabled, !liveObservationEnabled else { return }
        liveObservationActivationTask?.cancel()
        liveObservationActivationTask = Task { @MainActor in
            await Task.yield()
            guard liveQueriesEnabled, !liveObservationEnabled else { return }
            loadLiveObservationSettings()
            liveObservationEnabled = true
            refreshLiveObservationInputs()
            liveObservationActivationTask = nil
        }
    }

    private func resumeLiveObservationAfterPreviewIfNeeded() {
        guard isLiveObservationSuspendedForPreview else { return }
        Task { @MainActor in
            await Task.yield()
            guard isLiveObservationSuspendedForPreview, previewRoute == nil else { return }

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
                workouts: recentCompletedSessions,
                settings: sleepSettings,
                workoutLimit: 20,
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
        let liveSplit = recommendedSplit(named: decision.recommendedSplitName)
            ?? activeSplits.first(where: { $0.name == decision.recommendedSplitName })
        let preparedSplit = liveSplit.map(WorkoutPreviewSplit.init)
            ?? initialSnapshot?.recommendedSplit

        guard let preparedSplit else { return }

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
        guard route != nextRoute else { return }
        NavigationInteraction.perform(
            key: "coach.\(nextRoute.analyticsName)",
            destinationClass: .deep,
            haptic: .selection
        ) {
            route = nextRoute
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

struct CoachDerivedMetrics: Sendable {
    let summary: CoachRecommendationSummary
    let recentPRs: [PRRecord]
    let targetSuggestions: [TargetSuggestion]
    let weeklyWorkoutCount: Int
    let weeklyWorkingSetCount: Int
    let progressOpportunityInsights: [CoachInsight]

    static let placeholder = CoachDerivedMetrics(
        summary: .placeholder,
        recentPRs: [],
        targetSuggestions: [],
        weeklyWorkoutCount: 0,
        weeklyWorkingSetCount: 0,
        progressOpportunityInsights: []
    )

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

struct CoachDailyDecision: Equatable {
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

private extension CoachDailyDecision {
    func neutralizedForProvisionalReadiness() -> CoachDailyDecision {
        let safeTrainingCall = trainingCall.neutralizedForProvisionalReadiness(if: true)
        return CoachDailyDecision(
            recommendedSplitName: recommendedSplitName,
            recommendedMode: .full,
            headline: recommendedSplitName.map { "\($0) — Readiness pending" } ?? "Readiness is still settling",
            targetLine: nil,
            shortReason: safeTrainingCall.reason,
            confidenceLabel: "Provisional",
            badgeState: .baseline,
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

struct CoachWeeklyReviewSnapshot: Equatable {
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

struct CoachDecisionSignal: Identifiable, Equatable {
    let title: String
    let message: String
    let systemImage: String

    var id: String {
        "\(title)|\(message)|\(systemImage)"
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
