import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeSession: WorkoutSession?
    @State private var selectedExerciseIds: [UUID] = []
    @State private var selectedMode: WorkoutMode = .full
    @State private var optionalExerciseId: UUID?
    @State private var draggingExerciseId: UUID?
    @State private var pendingSubstitutionExercise: PlannedWorkoutExercise?
    @State private var activeCoachSheet: CoachWorkoutSheet?
    @State private var appliedWorkoutAdjustment: AppliedCoachWorkoutAdjustment?
    @State private var substitutionNotesByExerciseId: [UUID: String] = [:]
    @State private var renderSnapshot: WorkoutPreviewRenderSnapshot?
    @State private var lastRenderSignature: String?
    @State private var lastRenderSignatureParts: [String: String] = [:]
    @State private var queuedRenderRequestID: UUID?
    @State private var renderRefreshTask: Task<Void, Never>?
    @State private var renderLoadingIndicatorTask: Task<Void, Never>?
    @State private var showRenderLoadingIndicator = false
    @State private var didRequestInitialRenderSnapshot = false
    @State private var didMarkInitialPreviewContent = false
    @State private var didMarkRouteShellVisible = false
    @State private var didMarkStartButtonVisible = false
    @State private var didMarkExerciseRowsVisible = false
    @State private var didMarkCoachGuidanceVisible = false
    @State private var didMarkFullContentVisible = false
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()

    @Query
    private var exercises: [Exercise]

    @Query
    private var completedSessions: [WorkoutSession]

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
    private var activeSplits: [TrainingSplit]

    @Query
    private var coachActionHistory: [CoachActionHistoryEntry]

    @Query
    private var recommendationFeedback: [CoachRecommendationFeedback]

    @Query
    private var savedDeloadBlocks: [SavedCoachDeloadBlock]

    @Query
    private var exerciseMetadata: [CoachExerciseMetadata]

    @Query
    private var coachPreferences: [CoachPreferences]

    @Query
    private var splitMetadataRecords: [CoachSplitMetadata]

    @State private var sleepSettings = SleepSettingsStore().load()

    let split: WorkoutPreviewSplit

    private let coachIntelligence = CoachIntelligenceService()
    private let workoutAdjustmentService = CoachWorkoutAdjustmentService()
    private let coachHistoryService = CoachActionHistoryService()
    private let deloadBlockService = SavedCoachDeloadBlockService()
    private let deloadReviewService = CoachDeloadCalendarReviewService()
    private let coachPreferencesService = CoachPreferencesService()
    private let targetService = TargetSuggestionService()
    private let modePlanner = WorkoutModePlanner()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let trainingDecisionService = TrainingDecisionService()
    private let substitutionService = ExerciseSubstitutionService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()

    init(split: TrainingSplit, initialMode: WorkoutMode = .full) {
        self.split = WorkoutPreviewSplit(split)
        _selectedMode = State(initialValue: initialMode)
        Self.configureQueries(
            exercises: &_exercises,
            completedSessions: &_completedSessions,
            sleepSessions: &_sleepSessions,
            napSessions: &_napSessions,
            hydrationEntries: &_hydrationEntries,
            foodLogEntries: &_foodLogEntries,
            coachCheckIns: &_coachCheckIns,
            activeSplits: &_activeSplits,
            coachActionHistory: &_coachActionHistory,
            recommendationFeedback: &_recommendationFeedback,
            savedDeloadBlocks: &_savedDeloadBlocks,
            exerciseMetadata: &_exerciseMetadata,
            coachPreferences: &_coachPreferences,
            splitMetadataRecords: &_splitMetadataRecords
        )
    }

    init(split: WorkoutPreviewSplit, initialMode: WorkoutMode = .full) {
        self.split = split
        _selectedMode = State(initialValue: initialMode)
        Self.configureQueries(
            exercises: &_exercises,
            completedSessions: &_completedSessions,
            sleepSessions: &_sleepSessions,
            napSessions: &_napSessions,
            hydrationEntries: &_hydrationEntries,
            foodLogEntries: &_foodLogEntries,
            coachCheckIns: &_coachCheckIns,
            activeSplits: &_activeSplits,
            coachActionHistory: &_coachActionHistory,
            recommendationFeedback: &_recommendationFeedback,
            savedDeloadBlocks: &_savedDeloadBlocks,
            exerciseMetadata: &_exerciseMetadata,
            coachPreferences: &_coachPreferences,
            splitMetadataRecords: &_splitMetadataRecords
        )
    }

    private static func configureQueries(
        exercises: inout Query<Exercise, [Exercise]>,
        completedSessions: inout Query<WorkoutSession, [WorkoutSession]>,
        sleepSessions: inout Query<SleepSession, [SleepSession]>,
        napSessions: inout Query<NapSession, [NapSession]>,
        hydrationEntries: inout Query<HydrationEntry, [HydrationEntry]>,
        foodLogEntries: inout Query<FoodLogEntry, [FoodLogEntry]>,
        coachCheckIns: inout Query<DailyCoachCheckIn, [DailyCoachCheckIn]>,
        activeSplits: inout Query<TrainingSplit, [TrainingSplit]>,
        coachActionHistory: inout Query<CoachActionHistoryEntry, [CoachActionHistoryEntry]>,
        recommendationFeedback: inout Query<CoachRecommendationFeedback, [CoachRecommendationFeedback]>,
        savedDeloadBlocks: inout Query<SavedCoachDeloadBlock, [SavedCoachDeloadBlock]>,
        exerciseMetadata: inout Query<CoachExerciseMetadata, [CoachExerciseMetadata]>,
        coachPreferences: inout Query<CoachPreferences, [CoachPreferences]>,
        splitMetadataRecords: inout Query<CoachSplitMetadata, [CoachSplitMetadata]>
    ) {
        exercises = Query(exercisesDescriptor)
        completedSessions = Query(completedSessionsDescriptor)
        sleepSessions = Query(sleepSessionsDescriptor)
        napSessions = Query(napSessionsDescriptor)
        hydrationEntries = Query(hydrationEntriesDescriptor)
        foodLogEntries = Query(foodLogEntriesDescriptor)
        coachCheckIns = Query(coachCheckInsDescriptor)
        activeSplits = Query(activeSplitsDescriptor)
        coachActionHistory = Query(coachActionHistoryDescriptor)
        recommendationFeedback = Query(recommendationFeedbackDescriptor)
        savedDeloadBlocks = Query(savedDeloadBlocksDescriptor)
        exerciseMetadata = Query(exerciseMetadataDescriptor)
        coachPreferences = Query(coachPreferencesDescriptor)
        splitMetadataRecords = Query(splitMetadataRecordsDescriptor)
    }

    private static var exercisesDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 180
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

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var hydrationEntriesDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var foodLogEntriesDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        descriptor.fetchLimit = 160
        return descriptor
    }

    private static var coachCheckInsDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var coachActionHistoryDescriptor: FetchDescriptor<CoachActionHistoryEntry> {
        var descriptor = FetchDescriptor<CoachActionHistoryEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var recommendationFeedbackDescriptor: FetchDescriptor<CoachRecommendationFeedback> {
        var descriptor = FetchDescriptor<CoachRecommendationFeedback>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var savedDeloadBlocksDescriptor: FetchDescriptor<SavedCoachDeloadBlock> {
        var descriptor = FetchDescriptor<SavedCoachDeloadBlock>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var exerciseMetadataDescriptor: FetchDescriptor<CoachExerciseMetadata> {
        var descriptor = FetchDescriptor<CoachExerciseMetadata>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 180
        return descriptor
    }

    private static var coachPreferencesDescriptor: FetchDescriptor<CoachPreferences> {
        var descriptor = FetchDescriptor<CoachPreferences>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    private static var splitMetadataRecordsDescriptor: FetchDescriptor<CoachSplitMetadata> {
        var descriptor = FetchDescriptor<CoachSplitMetadata>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var currentRenderSnapshot: WorkoutPreviewRenderSnapshot {
        if let renderSnapshot {
            return renderSnapshot
        }

        return PerformanceTracer.trace(.workoutPreviewRenderSnapshot) {
            makeRenderSnapshot()
        }
    }

    private var renderSignatureParts: [String: String] {
        [
            "split": "\(split.id.uuidString):\(signature(split.exercises, limit: split.exercises.count, sortedBy: { $0.id.uuidString < $1.id.uuidString }) { "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.name):\($0.targetSets):\($0.minReps):\($0.maxReps):\($0.notes ?? "")" })",
            "mode": selectedMode.rawValue,
            "selected_exercises": selectedExerciseIds.map(\.uuidString).joined(separator: ","),
            "substitutions": substitutionNotesByExerciseId
                .map { "\($0.key.uuidString):\($0.value)" }
                .sorted()
                .joined(separator: ","),
            "applied_adjustment": appliedWorkoutAdjustment?.id.uuidString ?? "none",
            "exercises": signature(exercises, limit: 180, sortedBy: { $0.id.uuidString < $1.id.uuidString }) { exercise in
                [
                    exercise.id.uuidString,
                    exercise.name,
                    exercise.primaryMuscleGroup.rawValue,
                    exercise.secondaryMuscleGroups.map(\.rawValue).sorted().joined(separator: "+"),
                    exercise.movementPattern.rawValue,
                    exercise.equipment.rawValue,
                    "\(exercise.isCompound)",
                    "\(exercise.updatedAt.timeIntervalSince1970)"
                ].joined(separator: ":")
            },
            "completed_sessions": signature(recentCompletedSessions, limit: 20, sortedBy: workoutSessionSort) { workoutSessionRouteSignature($0) },
            "sleep_sessions": signature(sleepSessions, limit: 60, sortedBy: { stableDateIDSort($0.updatedAt, $0.id, $1.updatedAt, $1.id) }) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "nap_sessions": signature(napSessions, limit: 30, sortedBy: { stableDateIDSort($0.updatedAt, $0.id, $1.updatedAt, $1.id) }) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "hydration": signature(hydrationEntries, limit: 120, sortedBy: { stableDateIDSort($0.loggedAt, $0.id, $1.loggedAt, $1.id) }) { "\($0.id.uuidString):\($0.loggedAt.timeIntervalSince1970):\($0.amountML):\($0.source.rawValue):\($0.context.rawValue):\($0.updatedAt.timeIntervalSince1970)" },
            "food_logs": signature(foodLogEntries, limit: 160, sortedBy: { stableDateIDSort($0.loggedAt, $0.id, $1.loggedAt, $1.id) }) { "\($0.id.uuidString):\($0.loggedAt.timeIntervalSince1970):\($0.foodItemId.uuidString):\($0.consumedAmount):\($0.amountUnit.rawValue):\($0.mealType.rawValue):\($0.caloriesSnapshot):\($0.proteinSnapshot):\($0.carbsSnapshot):\($0.fatSnapshot):\($0.updatedAt.timeIntervalSince1970)" },
            "coach_checkins": signature(coachCheckIns, limit: 30, sortedBy: { stableDateIDSort($0.date, $0.id, $1.date, $1.id) }) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.energy):\($0.soreness):\($0.stress):\($0.motivation):\($0.updatedAt.timeIntervalSince1970)" },
            "recommendation_feedback": signature(recommendationFeedback, limit: 120, sortedBy: { stableDateIDSort($0.createdAt, $0.id, $1.createdAt, $1.id) }) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            "saved_deload_blocks": signature(savedDeloadBlocks, limit: 40, sortedBy: { stableDateIDSort($0.updatedAt, $0.id, $1.updatedAt, $1.id) }) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "exercise_metadata": signature(exerciseMetadata, limit: 180, sortedBy: { $0.exerciseId.uuidString < $1.exerciseId.uuidString }) { "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "coach_preferences": signature(coachPreferences, limit: 5, sortedBy: { stableDateIDSort($0.updatedAt, $0.id, $1.updatedAt, $1.id) }) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "split_metadata": signature(splitMetadataRecords, limit: 40, sortedBy: { $0.splitId.uuidString < $1.splitId.uuidString }) { "\($0.id.uuidString):\($0.splitId.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "sleep_settings": sleepSettingsRenderSignature,
            "hydration_target": "\(hydrationTargetML)",
            "nutrition_goal": nutritionGoalSignature
        ]
    }

    private var nutritionGoalSignature: String {
        guard nutritionGoal.hasTargets else { return "nutrition-goal-empty" }
        return [
            "\(nutritionGoal.isEnabled)",
            "\(nutritionGoal.dailyCaloriesTarget ?? 0)",
            "\(nutritionGoal.dailyProteinTarget ?? 0)",
            "\(nutritionGoal.dailyCarbsTarget ?? 0)",
            "\(nutritionGoal.dailyFatTarget ?? 0)",
            "\(nutritionGoal.trainingDayCaloriesTarget ?? 0)",
            "\(nutritionGoal.restDayCaloriesTarget ?? 0)"
        ].joined(separator: ":")
    }

    private func scheduleRenderSnapshotRefresh(reason: String, force: Bool = false) {
        renderRefreshTask?.cancel()
        let requestID = UUID()
        queuedRenderRequestID = requestID
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "queue \(reason)")
        PerformanceTracer.mark(.previewHydrationBegin, "queued reason=\(reason) hydrated=\(renderSnapshot?.isHydrated == true)")

        if renderSnapshot == nil {
            scheduleRenderLoadingIndicator()
        }

        let delay: TimeInterval
        if renderSnapshot == nil {
            delay = 0.02
        } else if renderSnapshot?.isHydrated == false {
            delay = fullHydrationDelaySeconds
        } else {
            delay = 0.04
        }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard queuedRenderRequestID == requestID else { return }
            let signatureParts = renderSignatureParts
            let signature = renderSignature(from: signatureParts)

            if !force, renderSnapshot != nil, signature == lastRenderSignature {
                PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "skip \(reason) same_signature")
                queuedRenderRequestID = nil
                return
            }

            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "refresh \(reason) changes=\(renderSignatureChangeDescription(from: lastRenderSignatureParts, to: signatureParts))")
            refreshRenderSnapshot(signature: signature, signatureParts: signatureParts)
            queuedRenderRequestID = nil
        }

        renderRefreshTask = task
    }

    private var fullHydrationDelaySeconds: TimeInterval {
        #if DEBUG
        if PerformanceAcceptanceState.isEnabled {
            return 0.6
        }
        #endif

        return 0.35
    }

    private func refreshRenderSnapshot(signature: String, signatureParts: [String: String]) {
        guard renderSnapshot == nil || signature != lastRenderSignature else {
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "skip refresh same_signature")
            return
        }

        let nextSnapshot = PerformanceTracer.trace(.workoutPreviewRenderSnapshot) {
            makeRenderSnapshot()
        }
        PerformanceTracer.mark(.previewHydrationTargetSuggestionsReady, "count=\(nextSnapshot.suggestions.count)")
        PerformanceTracer.mark(.previewHydrationCoachGuidanceReady, "actions=\(nextSnapshot.actionRecommendations.count)")
        PerformanceTracer.mark(.previewHydrationFullContentReady, "exercises=\(nextSnapshot.plannedExercises.count)")
        AppMotion.withoutAnimation {
            renderSnapshot = nextSnapshot
            cancelRenderLoadingIndicator()
            lastRenderSignature = signature
            lastRenderSignatureParts = signatureParts
        }
    }

    private func scheduleRenderLoadingIndicator() {
        guard renderLoadingIndicatorTask == nil else { return }

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            guard renderSnapshot == nil else { return }
            showRenderLoadingIndicator = true
            PerformanceTracer.mark(.motionLoadingReveal, "workout_preview_loading_shell")
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "loading_indicator show delayed")
        }

        renderLoadingIndicatorTask = task
    }

    private func cancelRenderLoadingIndicator() {
        renderLoadingIndicatorTask?.cancel()
        renderLoadingIndicatorTask = nil
        showRenderLoadingIndicator = false
    }

    private func installRouteShellSnapshotIfNeeded() {
        guard renderSnapshot == nil else { return }

        let snapshot = makeRouteShellSnapshot()
        AppMotion.withoutAnimation {
            renderSnapshot = snapshot
            cancelRenderLoadingIndicator()
        }
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "route_shell installed exercises=\(snapshot.plannedExercises.count)")
        PerformanceTracer.mark(.previewHydrationBasicPlanReady, "route_shell exercises=\(snapshot.plannedExercises.count)")
        markInitialPreviewContentIfNeeded()
    }

    private func markInitialPreviewContentIfNeeded() {
        guard !didMarkInitialPreviewContent else { return }
        didMarkInitialPreviewContent = true
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "first_content visible")
    }

    private func markRouteShellVisibleIfNeeded(_ source: String) {
        guard !didMarkRouteShellVisible else { return }
        didMarkRouteShellVisible = true
        PerformanceTracer.mark(.previewRouteShellVisible, "\(source) split=\(split.name)")
    }

    private func markStartButtonVisibleIfNeeded(_ source: String) {
        guard !didMarkStartButtonVisible else { return }
        didMarkStartButtonVisible = true
        PerformanceTracer.mark(.previewRouteStartButtonVisible, "\(source) split=\(split.name)")
    }

    private func markExerciseRowsVisibleIfNeeded(count: Int, source: String) {
        guard !didMarkExerciseRowsVisible else { return }
        didMarkExerciseRowsVisible = true
        PerformanceTracer.mark(.previewHydrationExerciseRowsReady, "\(source) count=\(count)")
    }

    private func markCoachGuidanceVisibleIfNeeded(_ source: String) {
        guard !didMarkCoachGuidanceVisible else { return }
        didMarkCoachGuidanceVisible = true
        PerformanceTracer.mark(.previewHydrationCoachGuidanceReady, "visible \(source)")
    }

    private func markFullContentVisibleIfNeeded(snapshot: WorkoutPreviewRenderSnapshot) {
        guard !didMarkFullContentVisible else { return }
        didMarkFullContentVisible = true
        PerformanceTracer.mark(.previewHydrationFullContentReady, "visible exercises=\(snapshot.plannedExercises.count)")
    }

    private func renderSignature(from parts: [String: String]) -> String {
        parts.keys.sorted().map { "\($0)=\(parts[$0] ?? "")" }.joined(separator: "|")
    }

    private func renderSignatureChangeDescription(from oldParts: [String: String], to newParts: [String: String]) -> String {
        let keys = Set(oldParts.keys).union(newParts.keys).sorted()
        let changedKeys = keys.filter { oldParts[$0] != newParts[$0] }
        guard !changedKeys.isEmpty else { return "none" }

        return changedKeys.prefix(6).map { key in
            "\(key):\(shortSignatureValue(oldParts[key]))->\(shortSignatureValue(newParts[key]))"
        }.joined(separator: ",")
    }

    private func shortSignatureValue(_ value: String?) -> String {
        guard let value else { return "nil" }
        guard value.count > 28 else { return value }
        return "\(value.prefix(12))...\(value.suffix(12))"
    }

    private func signature<Value>(
        _ values: [Value],
        limit: Int,
        sortedBy areInIncreasingOrder: (Value, Value) -> Bool,
        transform: (Value) -> String
    ) -> String {
        values.sorted(by: areInIncreasingOrder).prefix(limit).map(transform).joined(separator: ",")
    }

    private func stableDateIDSort(_ lhsDate: Date, _ lhsID: UUID, _ rhsDate: Date, _ rhsID: UUID) -> Bool {
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhsID.uuidString < rhsID.uuidString
    }

    private func workoutSessionSort(_ lhs: WorkoutSession, _ rhs: WorkoutSession) -> Bool {
        stableDateIDSort(lhs.date, lhs.id, rhs.date, rhs.id)
    }

    private func workoutSessionRouteSignature(_ session: WorkoutSession) -> String {
        return [
            session.id.uuidString,
            "\(session.date.timeIntervalSince1970)",
            "\(session.endedAt?.timeIntervalSince1970 ?? 0)",
            "\(session.durationSeconds ?? 0)",
            "\(session.perceivedDifficulty ?? 0)",
            "\(session.energyLevel ?? 0)",
            "\(session.sorenessLevel ?? 0)"
        ].joined(separator: ":")
    }

    private var sleepSettingsRenderSignature: String {
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

    private func makeRenderSnapshot() -> WorkoutPreviewRenderSnapshot {
        let exerciseLookup = WorkoutPreviewExerciseLookup(exercises: exercises)
        let orderedExercises = makeOrderedExercises(exerciseLookup: exerciseLookup)
        let orderedExercisesByID = Dictionary(orderedExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedExerciseIDSet = Set(selectedExerciseIds)
        let selectedBaseExercises = makeSelectedBaseExercises(
            orderedExercisesByID: orderedExercisesByID,
            exerciseLookup: exerciseLookup
        )
        let basePlannedExercises = modePlanner.plannedExercises(from: selectedBaseExercises, mode: selectedMode)
        let plannedExercises = appliedWorkoutAdjustment?.adjustedExercises ?? basePlannedExercises
        let estimatedDuration = modePlanner.estimatedDurationMinutes(for: plannedExercises, mode: selectedMode)
        let suggestions = suggestionsByExerciseId(for: plannedExercises)
        let alternatives = alternativesByExerciseId(for: plannedExercises)
        let addableExercises = exercises.filter { !selectedExerciseIDSet.contains($0.id) }
        let plannedMuscleGroups = Set(plannedExercises.flatMap { planned in
            exerciseLookup.byID[planned.exerciseId].map { exercise in
                [exercise.primaryMuscleGroup] + exercise.secondaryMuscleGroups
            } ?? []
        })
        let intelligence = makeCoachSnapshot(plannedExercises: plannedExercises)
        let plannedFatigueItems = intelligence.muscleFatigue.filter { plannedMuscleGroups.contains($0.muscleGroup) }
        let actionRecommendations = coachActionRecommendations(
            snapshot: intelligence,
            plannedExercises: plannedExercises,
            plannedFatigueItems: plannedFatigueItems
        )
        let trainingCall = makeTrainingCallSnapshot(
            suggestions: suggestions,
            intelligence: intelligence
        )

        return WorkoutPreviewRenderSnapshot(
            exerciseLookup: exerciseLookup,
            orderedExercises: orderedExercises,
            selectedExerciseIDSet: selectedExerciseIDSet,
            addableExercises: addableExercises,
            coreExercise: exerciseLookup.byName["Abdominal Crunch"],
            basePlannedExercises: basePlannedExercises,
            plannedExercises: plannedExercises,
            estimatedDuration: estimatedDuration,
            suggestions: suggestions,
            alternatives: alternatives,
            intelligence: intelligence,
            plannedFatigueItems: plannedFatigueItems,
            actionRecommendations: actionRecommendations,
            trainingCall: trainingCall,
            coachSummaryText: coachSummaryText(suggestions: suggestions, mode: selectedMode, trainingCall: trainingCall),
            coachSummaryBadge: coachSummaryBadge(suggestions: suggestions, mode: selectedMode),
            isHydrated: true
        )
    }

    private func makeRouteShellSnapshot() -> WorkoutPreviewRenderSnapshot {
        let selectedIDs = selectedExerciseIds.isEmpty
            ? defaultSelectedExerciseIdsFromSplit(for: selectedMode)
            : selectedExerciseIds
        let selectableByID = Dictionary(split.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedExercises = selectedIDs.compactMap { selectableByID[$0] }
        let basePlannedExercises = modePlanner.plannedExercises(from: selectedExercises, mode: selectedMode)
        let estimatedDuration = modePlanner.estimatedDurationMinutes(for: basePlannedExercises, mode: selectedMode)
        let suggestions = baselineSuggestionsByExerciseId(for: basePlannedExercises)
        let trainingCall = TrainingCallSnapshot(
            recommendedSplitName: split.name,
            recommendedMode: selectedMode,
            action: .buildBaseline,
            title: "\(split.name) preview ready",
            reason: "Preview is ready. Coach details are loading in the background.",
            confidence: .low,
            targetSummary: nil,
            sourceSignals: ["Route shell loaded before history and readiness details."],
            missingOrStaleInputs: ["Coach details are still preparing."],
            guardrailNotes: ["Start controls stay available while richer guidance loads."],
            isConservative: true
        )

        return WorkoutPreviewRenderSnapshot(
            exerciseLookup: WorkoutPreviewExerciseLookup(exercises: []),
            orderedExercises: split.exercises,
            selectedExerciseIDSet: Set(selectedIDs),
            addableExercises: [],
            coreExercise: nil,
            basePlannedExercises: basePlannedExercises,
            plannedExercises: basePlannedExercises,
            estimatedDuration: estimatedDuration,
            suggestions: suggestions,
            alternatives: [:],
            intelligence: CoachIntelligenceService.emptySnapshot(),
            plannedFatigueItems: [],
            actionRecommendations: [],
            trainingCall: trainingCall,
            coachSummaryText: "Coach details are loading. The workout plan is ready to review now.",
            coachSummaryBadge: .baseline,
            isHydrated: false
        )
    }

    private func makeTrainingCallSnapshot(
        suggestions: [UUID: TargetSuggestion],
        intelligence: CoachIntelligenceSnapshot
    ) -> TrainingCallSnapshot {
        let completedSnapshots = recentCompletedSessions.map(WorkoutAnalyticsSession.init)
        let activeSnapshots = activeSplits.map(TrainingSplitSnapshot.init)
        let previewSnapshot = trainingSplitSnapshot(from: split)
        let snapshots = activeSnapshots.contains { $0.id == previewSnapshot.id }
            ? activeSnapshots
            : activeSnapshots + [previewSnapshot]
        let decision = trainingDecisionService.decision(
            activeSplits: snapshots,
            completedSessions: completedSnapshots
        )

        return trainingCallBuilder.make(
            decision: decision,
            activeSplits: snapshots,
            completedSessions: completedSnapshots,
            readiness: intelligence.readiness,
            fatigueRisk: intelligence.fatigueRisk,
            targetSuggestions: Array(suggestions.values),
            selectedPreviewMode: selectedMode
        )
    }

    private func trainingSplitSnapshot(from split: WorkoutPreviewSplit) -> TrainingSplitSnapshot {
        TrainingSplitSnapshot(
            id: split.id,
            name: split.name,
            updatedAt: .distantPast,
            exercises: split.exercises.enumerated().map { index, exercise in
                SplitExerciseSnapshot(
                    id: exercise.id,
                    exerciseId: exercise.exerciseId,
                    exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                    orderIndex: index,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps
                )
            }
        )
    }

    private func makeOrderedExercises(exerciseLookup: WorkoutPreviewExerciseLookup) -> [WorkoutSelectableExercise] {
        var items = split.exercises
        let existingNames = Set(items.map(\.name))

        if
            !existingNames.contains("Abdominal Crunch"),
            let abdominalCrunch = exerciseLookup.byName["Abdominal Crunch"]
        {
            items.append(
                WorkoutSelectableExercise(
                    id: abdominalCrunch.id,
                    exerciseId: abdominalCrunch.id,
                    name: abdominalCrunch.name,
                    targetSets: 2,
                    minReps: 8,
                    maxReps: 15,
                    notes: "Optional core work."
                )
            )
        }

        return items
    }

    private func makeDefaultSelectedExerciseIds(for mode: WorkoutMode) -> [UUID] {
        let exerciseLookup = WorkoutPreviewExerciseLookup(exercises: exercises)
        return modePlanner
            .plannedExercises(from: makeOrderedExercises(exerciseLookup: exerciseLookup), mode: mode)
            .map(\.id)
    }

    private func defaultSelectedExerciseIdsFromSplit(for mode: WorkoutMode) -> [UUID] {
        modePlanner
            .plannedExercises(from: split.exercises, mode: mode)
            .map(\.id)
    }

    private func makeSelectedBaseExercises(
        orderedExercisesByID: [UUID: WorkoutSelectableExercise],
        exerciseLookup: WorkoutPreviewExerciseLookup
    ) -> [WorkoutSelectableExercise] {
        selectedExerciseIds.compactMap { selectedId in
            if let planned = orderedExercisesByID[selectedId] {
                return WorkoutSelectableExercise(
                    id: planned.id,
                    exerciseId: planned.exerciseId,
                    name: planned.name,
                    targetSets: planned.targetSets,
                    minReps: planned.minReps,
                    maxReps: planned.maxReps,
                    notes: substitutionNotesByExerciseId[planned.exerciseId] ?? planned.notes
                )
            }

            guard let exercise = exerciseLookup.byID[selectedId] else { return nil }

            return WorkoutSelectableExercise(
                id: exercise.id,
                exerciseId: exercise.id,
                name: exercise.name,
                targetSets: exercise.primaryMuscleGroup == .core ? 2 : 2,
                minReps: exercise.primaryMuscleGroup == .core ? 8 : 8,
                maxReps: exercise.primaryMuscleGroup == .core ? 15 : 12,
                notes: substitutionNotesByExerciseId[exercise.id]
            )
        }
    }

    private var recentCompletedSessions: [WorkoutSession] {
        Array(completedSessions.prefix(20))
    }

    private var readinessScore: ReadinessScore {
        currentRenderSnapshot.intelligence.readiness
    }

    private func makeCoachSnapshot(plannedExercises: [PlannedWorkoutExercise]) -> CoachIntelligenceSnapshot {
        coachIntelligence.snapshot(
            exercises: exercises,
            plannedExerciseIDs: plannedExercises.map(\.exerciseId),
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: recentCompletedSessions,
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

    private var coachPreferencesSnapshot: CoachPreferencesSnapshot {
        coachPreferencesService.snapshot(from: coachPreferences)
    }

    private var currentSplitMetadataSnapshot: CoachSplitMetadataSnapshot? {
        splitMetadataRecords.first { $0.splitId == split.id }?.snapshot
    }

    private var calibrationContext: CoachCalibrationContext {
        CoachCalibrationContext(
            actionHistory: coachActionHistory,
            feedback: recommendationFeedback,
            deloadBlocks: savedDeloadBlocks,
            exerciseMetadata: exerciseMetadata,
            preferences: coachPreferencesSnapshot,
            splitMetadata: currentSplitMetadataSnapshot
        )
    }

    private func coachActionRecommendations(
        snapshot: CoachIntelligenceSnapshot,
        plannedExercises: [PlannedWorkoutExercise],
        plannedFatigueItems: [MuscleGroupFatigue]
    ) -> [CoachWorkoutActionRecommendation] {
        workoutAdjustmentService.recommendations(
            for: snapshot,
            plannedExercises: plannedExercises,
            plannedMuscleFatigue: plannedFatigueItems,
            calibration: calibrationContext
        )
    }

    private func previewExerciseCard(
        exercise: PlannedWorkoutExercise,
        index: Int,
        plannedCount: Int,
        suggestions: [UUID: TargetSuggestion],
        alternatives: [UUID: [Exercise]]
    ) -> some View {
        WorkoutPreviewExerciseCard(
            exercise: exercise,
            suggestion: suggestions[exercise.id] ?? baselineSuggestion(for: exercise),
            alternatives: alternatives[exercise.id] ?? [],
            isFirst: index == 0,
            isLast: index == plannedCount - 1,
            substitute: { alternative in
                substitute(exercise, with: alternative)
            },
            requestSubstitute: {
                pendingSubstitutionExercise = exercise
            },
            moveToTop: {
                moveToTop(exercise)
            },
            moveToBottom: {
                moveToBottom(exercise)
            },
            remove: {
                remove(exercise)
            }
        )
        .rowInsertRemoveMotion(reduceMotion: reduceMotion)
        .onDrag {
            draggingExerciseId = exercise.id
            return NSItemProvider(object: exercise.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: WorkoutPreviewExerciseDropDelegate(
                destinationExerciseId: exercise.id,
                selectedExerciseIds: $selectedExerciseIds,
                draggingExerciseId: $draggingExerciseId,
                reduceMotion: reduceMotion
            )
        )
    }

    var body: some View {
        ZStack {
            if let renderSnapshot {
                previewContent(snapshot: renderSnapshot)
            } else {
                loadingPreviewContent
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
        .sheet(item: $pendingSubstitutionExercise) { exercise in
            SubstitutionPickerSheet(
                title: "Substitute \(exercise.exerciseNameSnapshot)",
                candidatesProvider: { reason in
                    substitutionService.candidates(
                        for: exercise.exerciseId,
                        in: exercises,
                        completedSessions: recentCompletedSessions,
                        reason: reason
                    )
                },
                select: { candidate, reason in
                    if let replacement = currentRenderSnapshot.exerciseLookup.byID[candidate.exerciseId] {
                        substitute(exercise, with: replacement, reason: reason)
                    }
                }
            )
        }
        .sheet(item: $activeCoachSheet) { sheet in
            switch sheet {
            case let .actionPreview(preview):
                WorkoutAdjustmentPreviewSheet(
                    preview: preview,
                    preferences: coachPreferencesSnapshot,
                    splitMetadata: currentSplitMetadataSnapshot
                ) { editedPreview in
                    applyCoachAdjustment(editedPreview, snapshot: currentRenderSnapshot.intelligence)
                } cancel: {
                    recordCoachAction(preview: preview, outcome: .cancelled, snapshot: currentRenderSnapshot.intelligence)
                }
            case .deloadPlanner:
                ManualDeloadPlannerSheet(
                    defaultPlan: workoutAdjustmentService.defaultDeloadPlan(for: currentRenderSnapshot.intelligence.fatigueRisk),
                    fatigueRisk: currentRenderSnapshot.intelligence.fatigueRisk,
                    calendarPreview: { plan in
                        deloadReviewService.preview(plan: plan, activeSplits: activeSplits)
                    }
                ) { plan in
                    activeCoachSheet = .actionPreview(
                        workoutAdjustmentPreview(
                            action: .deloadStyleSession,
                            snapshot: currentRenderSnapshot.intelligence,
                            plannedFatigueItems: currentRenderSnapshot.plannedFatigueItems,
                            deloadPlan: plan
                        )
                    )
                } savePlan: { plan in
                    saveDeloadBlock(plan, snapshot: currentRenderSnapshot.intelligence)
                }
            }
        }
        .onAppear {
            sleepSettings = sleepSettingsStore.load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            if selectedExerciseIds.isEmpty {
                selectedExerciseIds = defaultSelectedExerciseIdsFromSplit(for: selectedMode)
            }
            installRouteShellSnapshotIfNeeded()
            guard !didRequestInitialRenderSnapshot else {
                PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "skip onAppear already_requested")
                return
            }
            didRequestInitialRenderSnapshot = true
            PerformanceTracer.mark(.previewOnAppearRefresh, "requested")
            scheduleRenderSnapshotRefresh(reason: "onAppear", force: true)
        }
        .onChange(of: selectedMode) { _, newMode in
            PerformanceTracer.trace(.motionPreviewModeChange) {
                PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "mode_change begin mode=\(newMode.rawValue)")
                resetCoachAdjustment()
                AppMotion.withoutAnimation {
                    selectedExerciseIds = makeDefaultSelectedExerciseIds(for: newMode)
                }
            }
            guard renderSnapshot != nil else { return }
            scheduleRenderSnapshotRefresh(reason: "mode_changed")
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "mode_change end mode=\(newMode.rawValue)")
        }
        .onChange(of: selectedExerciseIds) { _, _ in
            guard renderSnapshot != nil else { return }
            scheduleRenderSnapshotRefresh(reason: "selected_exercises_changed")
        }
        .onChange(of: substitutionNotesByExerciseId) { _, _ in
            guard renderSnapshot != nil else { return }
            scheduleRenderSnapshotRefresh(reason: "substitution_changed")
        }
        .onChange(of: appliedWorkoutAdjustment?.id) { _, _ in
            guard renderSnapshot != nil else { return }
            scheduleRenderSnapshotRefresh(reason: "coach_adjustment_changed")
        }
        .onDisappear {
            renderRefreshTask?.cancel()
            queuedRenderRequestID = nil
            cancelRenderLoadingIndicator()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            renderRefreshTask?.cancel()
            queuedRenderRequestID = nil
            cancelRenderLoadingIndicator()
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "cancel scenePhase=\(String(describing: newPhase))")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            renderRefreshTask?.cancel()
            queuedRenderRequestID = nil
            cancelRenderLoadingIndicator()
            PerformanceTracer.mark(.unsafeBreadcrumb, "workout_preview.willResignActive no_async_task")
        }
    }

    @ViewBuilder
    private func previewContent(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        if snapshot.isHydrated {
            hydratedPreviewContent(snapshot: snapshot)
        } else {
            previewRouteShellContent(snapshot: snapshot)
        }
    }

    private func previewRouteShellContent(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(split.name) Preview")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(selectedMode.displayName) mode - \(snapshot.plannedExercises.count) exercises - ~\(snapshot.estimatedDuration.lowerBound)-\(snapshot.estimatedDuration.upperBound)m")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WorkoutModePicker(selection: $selectedMode)
                    .accessibilityIdentifier("workout-preview-mode-controls")

                startWorkoutButton(snapshot: snapshot, identifier: "workout-preview-start")

                FitnessCard(style: .compact) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Exercise Order", systemImage: "list.bullet")
                                .font(AppTypography.compactCardTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .accessibilityIdentifier("workout-preview-basic-exercise-rows")

                            Spacer()

                            Text("Targets loading")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.mutedText)
                        }

                        basicExerciseRows(snapshot: snapshot, source: "route_shell")
                    }
                }

                coachDetailsLoadingCard(snapshot: snapshot)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .accessibilityIdentifier("workout-preview-route-shell")
        .onAppear {
            markRouteShellVisibleIfNeeded("route_shell")
            markInitialPreviewContentIfNeeded()
        }
    }

    private func basicExerciseRows(snapshot: WorkoutPreviewRenderSnapshot, source: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(snapshot.plannedExercises.enumerated()), id: \.element.id) { index, exercise in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(width: 24, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.exerciseNameSnapshot)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(exercise.targetSets) sets - \(exercise.minReps)-\(exercise.maxReps) reps")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.mutedText)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 3)
                .accessibilityIdentifier("workout-preview-basic-exercise-row")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-preview-basic-exercise-rows")
        .onAppear {
            markExerciseRowsVisibleIfNeeded(count: snapshot.plannedExercises.count, source: source)
        }
    }

    private func hydratedPreviewContent(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        FitnessScreen(
            title: "\(split.name) Preview",
            subtitle: "\(selectedMode.displayName) mode - ~\(snapshot.estimatedDuration.lowerBound)-\(snapshot.estimatedDuration.upperBound)m",
            systemImage: "figure.strengthtraining.traditional"
        ) {
            DashboardSection(title: "Mode") {
                FitnessCard {
                    WorkoutModePicker(selection: $selectedMode)
                }
            }

            DashboardSection(title: "Session Snapshot") {
                planReadinessCard(snapshot: snapshot)
                startWorkoutShortcut(snapshot: snapshot)
            }

            DashboardSection(title: "Coach Brief") {
                if snapshot.isHydrated {
                    TrainingCallAuditCard(snapshot: snapshot.trainingCall)
                        .accessibilityIdentifier("workout-preview-training-call-audit")

                    AdaptiveWorkoutGuidanceCard(guidance: snapshot.intelligence.adaptiveGuidance)

                    AdaptiveWorkoutActionsCard(
                        guidance: snapshot.intelligence.adaptiveGuidance,
                        recommendations: snapshot.actionRecommendations,
                        appliedAdjustment: appliedWorkoutAdjustment,
                        selectAction: { action in
                            requestCoachAction(action, snapshot: snapshot.intelligence, plannedFatigueItems: snapshot.plannedFatigueItems)
                        },
                        reset: resetCoachAdjustment
                    )

                    if appliedWorkoutAdjustment != nil {
                        originalPlanShortcut(snapshot: snapshot)
                    }

                    WorkoutReadinessBriefCard(readiness: snapshot.intelligence.readiness)

                    if snapshot.plannedFatigueItems.contains(where: { $0.state == .loaded || $0.state == .fatigued }) {
                        MuscleFatigueMapCard(items: snapshot.plannedFatigueItems)
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Text(snapshot.coachSummaryText)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer()

                                CoachBadgeView(state: snapshot.coachSummaryBadge)
                            }
                        }
                    }
                } else {
                    coachDetailsLoadingCard(snapshot: snapshot)
                }
            }

            DashboardSection(title: "Exercise Order") {
                HStack {
                    Spacer()
                    Button("Select All") {
                        AppMotion.withoutAnimation {
                            selectedExerciseIds = snapshot.orderedExercises.map(\.id)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(appTheme.actionColor)
                }

                if snapshot.plannedExercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises selected",
                        message: "Choose at least one exercise before starting.",
                        systemImage: "list.bullet"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(snapshot.plannedExercises.enumerated()), id: \.element.id) { index, exercise in
                            previewExerciseCard(
                                exercise: exercise,
                                index: index,
                                plannedCount: snapshot.plannedExercises.count,
                                suggestions: snapshot.suggestions,
                                alternatives: snapshot.isHydrated ? snapshot.alternatives : [:]
                            )
                        }
                    }
                    .accessibilityIdentifier("workout-preview-basic-exercise-rows")
                    .onAppear {
                        markExerciseRowsVisibleIfNeeded(count: snapshot.plannedExercises.count, source: "hydrated")
                    }
                }
            }

            if snapshot.isHydrated {
                DashboardSection(title: "Add Exercise") {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Optional exercise", selection: $optionalExerciseId) {
                                Text("Choose").tag(Optional<UUID>.none)
                                ForEach(snapshot.addableExercises) { exercise in
                                    Text(exercise.name).tag(Optional(exercise.id))
                                }
                            }

                            HStack {
                                Button {
                                    addOptionalExercise()
                                } label: {
                                    Label("Add Selected", systemImage: "plus.circle")
                                }
                                .disabled(optionalExerciseId == nil)

                                Spacer()

                                if let coreExercise = snapshot.coreExercise {
                                    Button {
                                        addExercise(coreExercise, targetSets: 2, minReps: 8, maxReps: 15, notes: "Optional core work.")
                                    } label: {
                                        Label("Add Core", systemImage: "figure.core.training")
                                    }
                                    .disabled(snapshot.selectedExerciseIDSet.contains(coreExercise.id))
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            DashboardSection(title: "Start") {
                FitnessCard(style: .hero) {
                    VStack(alignment: .leading, spacing: 12) {
                        startWorkoutButton(snapshot: snapshot, identifier: "workout-preview-start-footer")

                        if appliedWorkoutAdjustment != nil {
                            startOriginalPlanButton(snapshot: snapshot, identifier: "workout-preview-start-original-footer")
                        }

                        Text(startHint)
                            .font(.footnote)
                            .foregroundStyle(appTheme.mutedText)
                    }
                }
            }
        }
        .onAppear {
            markInitialPreviewContentIfNeeded()
            markFullContentVisibleIfNeeded(snapshot: snapshot)
        }
    }

    private var loadingPreviewContent: some View {
        ZStack {
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()

            if showRenderLoadingIndicator {
                SwiftUI.ProgressView()
                    .tint(appTheme.colors.accent)
                    .accessibilityLabel("Preparing preview")
                    .transition(.opacity)
            }
        }
        .animation(AppMotion.gentleFade(reduceMotion: reduceMotion), value: showRenderLoadingIndicator)
    }

    private func coachDetailsLoadingCard(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 36, height: 36)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Preview ready")
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(snapshot.coachSummaryText)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                CoachBadgeView(state: snapshot.coachSummaryBadge)
            }
        }
        .accessibilityIdentifier("workout-preview-guidance-chips")
        .onAppear {
            markCoachGuidanceVisibleIfNeeded(snapshot.isHydrated ? "hydrated" : "fallback")
        }
    }

    private func planReadinessCard(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: planReadinessIcon(snapshot: snapshot))
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(planReadinessAccent(snapshot: snapshot))
                        .background(planReadinessAccent(snapshot: snapshot).opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(planReadinessTitle(snapshot: snapshot))
                            .font(AppTypography.compactCardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(planReadinessMessage(snapshot: snapshot))
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    CoachBadgeView(state: planReadinessBadge(snapshot: snapshot))
                }

                HStack(alignment: .top, spacing: 12) {
                    planReadinessStat(label: "Mode", value: selectedMode.displayName, systemImage: selectedMode.systemImage)
                    Divider().frame(height: 44)
                    planReadinessStat(label: "Exercises", value: "\(snapshot.plannedExercises.count)", systemImage: "list.bullet")
                    Divider().frame(height: 44)
                    planReadinessStat(label: "Time", value: "\(snapshot.estimatedDuration.lowerBound)-\(snapshot.estimatedDuration.upperBound)m", systemImage: "clock")
                }
                .accessibilityElement(children: .combine)

                if let appliedWorkoutAdjustment {
                    Label(
                        "\(appliedWorkoutAdjustment.title) is active for this workout only. The split template stays unchanged.",
                        systemImage: "wand.and.stars"
                    )
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func planReadinessStat(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(AppTypography.badge)
                Text(label)
                    .font(AppTypography.metadataEmphasis)
                    .textCase(.uppercase)
            }
            .foregroundStyle(appTheme.mutedText)

            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planReadinessTitle(snapshot: WorkoutPreviewRenderSnapshot) -> String {
        if appliedWorkoutAdjustment != nil {
            return "Coach-adjusted plan"
        }

        if snapshot.plannedExercises.isEmpty {
            return "Plan needs exercises"
        }

        return "\(selectedMode.displayName) plan ready"
    }

    private func planReadinessMessage(snapshot: WorkoutPreviewRenderSnapshot) -> String {
        if snapshot.plannedExercises.isEmpty {
            return "Select at least one exercise before starting."
        }

        if let appliedWorkoutAdjustment {
            return "\(appliedWorkoutAdjustment.title) is the plan that will start when you press play."
        }

        switch selectedMode {
        case .full:
            return "The planned session is intact, with every selected exercise kept in order."
        case .quick:
            return "Main lifts stay first so the session can move quickly without losing focus."
        case .recovery:
            return "Volume is lower and targets stay controlled for a lighter training day."
        case .heavy:
            return "The session keeps the load progression work prominent."
        }
    }

    private func planReadinessBadge(snapshot: WorkoutPreviewRenderSnapshot) -> CoachBadgeState {
        if snapshot.plannedExercises.isEmpty {
            return .missedSplit
        }

        return snapshot.coachSummaryBadge
    }

    private func planReadinessIcon(snapshot: WorkoutPreviewRenderSnapshot) -> String {
        snapshot.plannedExercises.isEmpty ? "exclamationmark.triangle" : selectedMode.systemImage
    }

    private func planReadinessAccent(snapshot: WorkoutPreviewRenderSnapshot) -> Color {
        snapshot.plannedExercises.isEmpty ? appTheme.warningColor : appTheme.colors.accent
    }

    private func originalPlanShortcut(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Original plan")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(selectedMode.displayName) mode without the coach adjustment.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                startOriginalPlanButton(snapshot: snapshot, identifier: "workout-preview-start-original")
            }
        }
    }

    private func startWorkoutShortcut(snapshot: WorkoutPreviewRenderSnapshot) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                startWorkoutButton(snapshot: snapshot, identifier: "workout-preview-start")

                Text(startHint)
                    .font(.footnote)
                    .foregroundStyle(appTheme.mutedText)

                Divider()

                HStack {
                    Label("Exercise Order", systemImage: "list.bullet")
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("workout-preview-basic-exercise-rows")

                    Spacer()

                    Text("\(snapshot.plannedExercises.count) moves")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.mutedText)
                }

                basicExerciseRows(snapshot: snapshot, source: "hydrated_priority")
            }
        }
    }

    private func startWorkoutButton(
        snapshot: WorkoutPreviewRenderSnapshot,
        identifier: String
    ) -> some View {
        Button {
            activeSession = createWorkout(from: split)
        } label: {
            Label(startButtonTitle, systemImage: "play.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
        .accessibilityIdentifier(identifier)
        .disabled(snapshot.plannedExercises.isEmpty)
        .onAppear {
            markStartButtonVisibleIfNeeded(identifier)
        }
    }

    private func startOriginalPlanButton(
        snapshot: WorkoutPreviewRenderSnapshot,
        identifier: String
    ) -> some View {
        Button {
            startOriginalPlan(snapshot: snapshot)
        } label: {
            Label("Start Original Plan", systemImage: "arrow.uturn.backward.circle")
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
        .accessibilityIdentifier(identifier)
        .disabled(snapshot.basePlannedExercises.isEmpty)
    }

    private func startOriginalPlan(snapshot: WorkoutPreviewRenderSnapshot) {
        if let appliedWorkoutAdjustment {
            recordCoachAction(
                preview: appliedWorkoutAdjustment.preview,
                outcome: .bypassed,
                snapshot: snapshot.intelligence
            )
        }

        activeSession = createWorkout(
            from: split,
            plannedExercises: snapshot.basePlannedExercises,
            modeLabel: "\(selectedMode.displayName) Original"
        )
    }

    private var startButtonTitle: String {
        if let appliedWorkoutAdjustment {
            return "Start \(appliedWorkoutAdjustment.title)"
        }

        return "Start \(split.name)"
    }

    private var startHint: String {
        if let appliedWorkoutAdjustment {
            return "\(appliedWorkoutAdjustment.title) changes only this workout preview. The original split stays unchanged."
        }

        switch selectedMode {
        case .full:
            return "Full mode keeps the planned session intact."
        case .quick:
            return "Quick mode prioritises the main lifts and keeps the session tight."
        case .recovery:
            return "Recovery mode lowers volume and softens target pressure."
        case .heavy:
            return "Heavy mode keeps the focus on load progression."
        }
    }

    private func coachSummaryText(
        suggestions: [UUID: TargetSuggestion],
        mode: WorkoutMode,
        trainingCall: TrainingCallSnapshot
    ) -> String {
        if trainingCall.recommendedMode != mode || trainingCall.isConservative {
            return trainingCall.reason
        }

        let suggestions = suggestions.values
        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) {
            return "Performance has dipped on at least one lift. Keep the session controlled and rest properly."
        }

        if let increase = suggestions.first(where: { $0.recommendationType == .increaseLoad }) {
            return "Progress opportunity: push \(increase.exerciseName), then keep the rest efficient."
        }

        if mode == .recovery {
            return "Lower stress session. Repeat targets, keep form clean, and avoid forcing PRs."
        }

        if mode == .quick {
            return "Short session. Hit the important lifts first and leave accessories optional."
        }

        return "Targets are ready. Repeat or add reps where the range allows."
    }

    private func coachSummaryBadge(suggestions: [UUID: TargetSuggestion], mode: WorkoutMode) -> CoachBadgeState {
        let suggestions = suggestions.values
        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) {
            return .fatigueRisk
        }
        if suggestions.contains(where: { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }) {
            return .ready
        }
        if mode == .recovery {
            return .recovery
        }
        return .repeatTarget
    }

    private func remove(_ exercise: PlannedWorkoutExercise) {
        resetCoachAdjustment()
        withAnimation(AppMotion.animation(for: .rowRemove, reduceMotion: reduceMotion)) {
            selectedExerciseIds.removeAll { $0 == exercise.id }
        }
    }

    private func moveToTop(_ exercise: PlannedWorkoutExercise) {
        moveExercise(exercise.id, to: 0)
    }

    private func moveToBottom(_ exercise: PlannedWorkoutExercise) {
        moveExercise(exercise.id, to: selectedExerciseIds.count - 1)
    }

    private func moveExercise(_ exerciseId: UUID, to destination: Int) {
        guard let index = selectedExerciseIds.firstIndex(of: exerciseId) else { return }
        var ids = selectedExerciseIds
        let movedId = ids.remove(at: index)
        ids.insert(movedId, at: max(0, min(destination, ids.count)))
        withAnimation(AppMotion.animation(for: .rowReorder, reduceMotion: reduceMotion)) {
            selectedExerciseIds = ids
        }
    }

    private func addOptionalExercise() {
        guard
            let optionalExerciseId,
            let exercise = currentRenderSnapshot.exerciseLookup.byID[optionalExerciseId]
        else { return }

        addExercise(exercise, targetSets: 2, minReps: 8, maxReps: 12, notes: "Added for today's workout.")
        self.optionalExerciseId = nil
    }

    private func addExercise(_ exercise: Exercise, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        guard !selectedExerciseIds.contains(exercise.id) else { return }
        resetCoachAdjustment()
        withAnimation(AppMotion.animation(for: .rowInsert, reduceMotion: reduceMotion)) {
            selectedExerciseIds.append(exercise.id)
        }
    }

    private func alternatives(for exercise: PlannedWorkoutExercise) -> [Exercise] {
        substitutionService.alternatives(for: exercise.exerciseId, in: exercises)
    }

    private func suggestionsByExerciseId(for plannedExercises: [PlannedWorkoutExercise]) -> [UUID: TargetSuggestion] {
        plannedExercises.reduce(into: [:]) { result, exercise in
            result[exercise.id] = targetSuggestion(for: exercise)
        }
    }

    private func alternativesByExerciseId(for plannedExercises: [PlannedWorkoutExercise]) -> [UUID: [Exercise]] {
        plannedExercises.reduce(into: [:]) { result, exercise in
            result[exercise.id] = alternatives(for: exercise)
        }
    }

    private func baselineSuggestionsByExerciseId(for plannedExercises: [PlannedWorkoutExercise]) -> [UUID: TargetSuggestion] {
        plannedExercises.reduce(into: [:]) { result, exercise in
            result[exercise.id] = baselineSuggestion(for: exercise)
        }
    }

    private func baselineSuggestion(for exercise: PlannedWorkoutExercise) -> TargetSuggestion {
        TargetSuggestion(
            exerciseName: exercise.exerciseNameSnapshot,
            lastBestSetDescription: nil,
            lastBestWeight: nil,
            lastBestReps: nil,
            suggestedWeight: nil,
            suggestedReps: exercise.minReps,
            recommendationType: .baseline,
            reason: "Review the plan now. Recent target history is still loading.",
            confidence: 0.45
        )
    }

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: Exercise) {
        substitute(exercise, with: alternative, reason: .preferAlternative)
    }

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: Exercise, reason: ExerciseSubstitutionReason) {
        guard let index = selectedExerciseIds.firstIndex(of: exercise.id) else { return }
        resetCoachAdjustment()
        withAnimation(AppMotion.modeChange(reduceMotion: reduceMotion)) {
            selectedExerciseIds[index] = alternative.id
            substitutionNotesByExerciseId[alternative.id] = substitutionService.substitutionNote(
                originalName: exercise.exerciseNameSnapshot,
                replacementName: alternative.name,
                reason: reason
            )
        }
    }

    private func createWorkout(
        from split: WorkoutPreviewSplit,
        plannedExercises sessionExercises: [PlannedWorkoutExercise]? = nil,
        modeLabel: String? = nil
    ) -> WorkoutSession {
        let startDate = Date()
        let sessionExercises = sessionExercises ?? currentRenderSnapshot.plannedExercises
        let label = modeLabel ?? appliedWorkoutAdjustment.map { "\(selectedMode.displayName) - \($0.title)" } ?? selectedMode.displayName
        let session = WorkoutSession(
            date: startDate,
            splitId: split.id,
            splitNameSnapshot: "\(split.name) - \(label)",
            startedAt: startDate
        )

        session.exerciseLogs = sessionExercises.enumerated().map { index, splitExercise in
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: splitExercise.exerciseId,
                exerciseNameSnapshot: splitExercise.exerciseNameSnapshot,
                orderIndex: index,
                targetSets: splitExercise.targetSets,
                minReps: splitExercise.minReps,
                maxReps: splitExercise.maxReps,
                notes: splitExercise.notes
            )
            log.workoutSession = session
            return log
        }

        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    private func targetSuggestion(for exercise: PlannedWorkoutExercise) -> TargetSuggestion {
        let suggestion = targetService.suggestion(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.exerciseNameSnapshot,
            minReps: exercise.minReps,
            maxReps: exercise.maxReps,
            completedSessions: recentCompletedSessions
        )

        return modePlanner.modeAdjustedSuggestion(suggestion, mode: selectedMode)
    }

    private func requestCoachAction(
        _ action: CoachWorkoutAdjustmentAction,
        snapshot: CoachIntelligenceSnapshot,
        plannedFatigueItems: [MuscleGroupFatigue]
    ) {
        if action == .deloadStyleSession {
            PerformanceTracer.mark(.motionTapFeedback, "preview coach deload sheet requested")
            activeCoachSheet = .deloadPlanner
            return
        }

        PerformanceTracer.mark(.motionTapFeedback, "preview coach action sheet requested")
        activeCoachSheet = .actionPreview(
            workoutAdjustmentPreview(
                action: action,
                snapshot: snapshot,
                plannedFatigueItems: plannedFatigueItems
            )
        )
    }

    private func workoutAdjustmentPreview(
        action: CoachWorkoutAdjustmentAction,
        snapshot: CoachIntelligenceSnapshot,
        plannedFatigueItems: [MuscleGroupFatigue],
        deloadPlan: ManualDeloadPlan? = nil
    ) -> CoachWorkoutAdjustmentPreview {
        workoutAdjustmentService.makePreview(
            action: action,
            plannedExercises: currentRenderSnapshot.basePlannedExercises,
            snapshot: snapshot,
            exercises: exercises,
            plannedMuscleFatigue: plannedFatigueItems,
            deloadPlan: deloadPlan,
            splitName: split.name,
            exerciseMetadata: exerciseMetadata,
            preferences: coachPreferencesSnapshot,
            splitMetadata: currentSplitMetadataSnapshot
        )
    }

    private func applyCoachAdjustment(_ preview: CoachWorkoutAdjustmentPreview, snapshot: CoachIntelligenceSnapshot) {
        if preview.action == .keepPlan || !preview.hasWorkoutChanges {
            recordCoachAction(preview: preview, outcome: .bypassed, snapshot: snapshot)
            resetCoachAdjustment()
            return
        }

        appliedWorkoutAdjustment = AppliedCoachWorkoutAdjustment(preview: preview)
        recordCoachAction(preview: preview, outcome: .applied, snapshot: snapshot)
    }

    private func resetCoachAdjustment() {
        if let appliedWorkoutAdjustment {
            recordCoachAction(preview: appliedWorkoutAdjustment.preview, outcome: .reset, snapshot: currentRenderSnapshot.intelligence)
        }
        appliedWorkoutAdjustment = nil
    }

    private func recordCoachAction(
        preview: CoachWorkoutAdjustmentPreview,
        outcome: CoachActionHistoryOutcome,
        snapshot: CoachIntelligenceSnapshot
    ) {
        let entry = coachHistoryService.makeEntry(
            preview: preview,
            outcome: outcome,
            snapshot: snapshot,
            splitName: split.name
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    private func saveDeloadBlock(_ plan: ManualDeloadPlan, snapshot: CoachIntelligenceSnapshot) {
        let block = deloadBlockService.makeBlock(
            plan: plan,
            reason: snapshot.fatigueRisk.recommendedAction,
            splitName: split.name
        )
        modelContext.insert(block)
        try? modelContext.save()
    }
}

private struct WorkoutPreviewRenderSnapshot {
    let exerciseLookup: WorkoutPreviewExerciseLookup
    let orderedExercises: [WorkoutSelectableExercise]
    let selectedExerciseIDSet: Set<UUID>
    let addableExercises: [Exercise]
    let coreExercise: Exercise?
    let basePlannedExercises: [PlannedWorkoutExercise]
    let plannedExercises: [PlannedWorkoutExercise]
    let estimatedDuration: ClosedRange<Int>
    let suggestions: [UUID: TargetSuggestion]
    let alternatives: [UUID: [Exercise]]
    let intelligence: CoachIntelligenceSnapshot
    let plannedFatigueItems: [MuscleGroupFatigue]
    let actionRecommendations: [CoachWorkoutActionRecommendation]
    let trainingCall: TrainingCallSnapshot
    let coachSummaryText: String
    let coachSummaryBadge: CoachBadgeState
    let isHydrated: Bool
}

struct WorkoutPreviewRouteView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showFullPreview = false
    @State private var showFullPreviewTask: Task<Void, Never>?
    @State private var activeSession: WorkoutSession?
    @State private var selectedMode: WorkoutMode

    let split: WorkoutPreviewSplit
    let initialMode: WorkoutMode

    private let modePlanner = WorkoutModePlanner()

    init(split: WorkoutPreviewSplit, initialMode: WorkoutMode) {
        self.split = split
        self.initialMode = initialMode
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            if showFullPreview {
                WorkoutPreviewView(split: split, initialMode: selectedMode)
            } else {
                bootstrapShell
                    .navigationDestination(item: $activeSession) { session in
                        WorkoutLoggerView(session: session)
                    }
            }
        }
        .onAppear {
            PerformanceTracer.mark(.previewRouteShellVisible, "route_host split=\(split.name)")
            scheduleFullPreview()
        }
        .onDisappear {
            showFullPreviewTask?.cancel()
            showFullPreviewTask = nil
        }
    }

    private var bootstrapShell: some View {
        let plannedExercises = modePlanner.plannedExercises(from: split.exercises, mode: selectedMode)
        let estimatedDuration = modePlanner.estimatedDurationMinutes(for: plannedExercises, mode: selectedMode)

        return WorkoutPreviewBootstrapShellView(
            splitName: split.name,
            mode: selectedMode,
            plannedExercises: plannedExercises,
            estimatedDuration: estimatedDuration,
            selectMode: { mode in
                selectedMode = mode
            },
            start: startWorkout
        )
    }

    private func scheduleFullPreview() {
        guard !showFullPreview else { return }
        guard showFullPreviewTask == nil else { return }

        showFullPreviewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: fullPreviewDelayNanoseconds)
            guard !Task.isCancelled else { return }
            showFullPreview = true
            showFullPreviewTask = nil
        }
    }

    private var fullPreviewDelayNanoseconds: UInt64 {
        #if DEBUG
        if PerformanceAcceptanceState.isEnabled {
            return 120_000_000
        }
        #endif

        return 120_000_000
    }

    private func startWorkout() {
        let plannedExercises = modePlanner.plannedExercises(from: split.exercises, mode: selectedMode)
        guard !plannedExercises.isEmpty else { return }

        showFullPreviewTask?.cancel()
        showFullPreviewTask = nil

        let startDate = Date()
        let session = WorkoutSession(
            date: startDate,
            splitId: split.id,
            splitNameSnapshot: "\(split.name) - \(selectedMode.displayName)",
            startedAt: startDate
        )

        session.exerciseLogs = plannedExercises.enumerated().map { index, exercise in
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: exercise.exerciseId,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                orderIndex: index,
                targetSets: exercise.targetSets,
                minReps: exercise.minReps,
                maxReps: exercise.maxReps,
                notes: exercise.notes
            )
            log.workoutSession = session
            return log
        }

        modelContext.insert(session)
        try? modelContext.save()
        activeSession = session
    }
}

private struct WorkoutPreviewBootstrapShellView: View {
    let splitName: String
    let mode: WorkoutMode
    let plannedExercises: [PlannedWorkoutExercise]
    let estimatedDuration: ClosedRange<Int>
    let selectMode: (WorkoutMode) -> Void
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(splitName) Preview")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: "\(mode.displayName) mode - \(plannedExercises.count) exercises - ~\(estimatedDuration.lowerBound)-\(estimatedDuration.upperBound)m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(WorkoutMode.allCases) { modeOption in
                    Button {
                        selectMode(modeOption)
                    } label: {
                        Label(modeOption.displayName, systemImage: modeOption.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(mode == modeOption ? .accentColor : .gray)
                }
            }

            Button(action: start) {
                Label("Start \(splitName)", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("workout-preview-start")
            .onAppear {
                PerformanceTracer.mark(.previewRouteStartButtonVisible, "bootstrap split=\(splitName)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise Order")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("workout-preview-basic-exercise-rows")

                ForEach(Array(plannedExercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.exerciseNameSnapshot)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(exercise.targetSets) sets - \(exercise.minReps)-\(exercise.maxReps) reps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("workout-preview-basic-exercise-row")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout-preview-basic-exercise-rows")
            .onAppear {
                PerformanceTracer.mark(.previewHydrationBasicPlanReady, "bootstrap exercises=\(plannedExercises.count)")
                PerformanceTracer.mark(.previewHydrationExerciseRowsReady, "bootstrap count=\(plannedExercises.count)")
            }

            Text(verbatim: "Coach details are preparing. You can start now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("workout-preview-guidance-chips")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutPreviewExerciseLookup {
    let byID: [UUID: Exercise]
    let byName: [String: Exercise]

    init(exercises: [Exercise]) {
        byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byName = Dictionary(exercises.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

private enum CoachWorkoutSheet: Identifiable {
    case actionPreview(CoachWorkoutAdjustmentPreview)
    case deloadPlanner

    var id: String {
        switch self {
        case let .actionPreview(preview):
            return "action-\(preview.id)"
        case .deloadPlanner:
            return "deload-planner"
        }
    }
}

private struct WorkoutPreviewExerciseDropDelegate: DropDelegate {
    let destinationExerciseId: UUID
    @Binding var selectedExerciseIds: [UUID]
    @Binding var draggingExerciseId: UUID?
    let reduceMotion: Bool

    func dropEntered(info: DropInfo) {
        guard
            let draggingExerciseId,
            draggingExerciseId != destinationExerciseId,
            let sourceIndex = selectedExerciseIds.firstIndex(of: draggingExerciseId),
            let destinationIndex = selectedExerciseIds.firstIndex(of: destinationExerciseId)
        else { return }

        withAnimation(AppMotion.animation(for: .rowReorder, reduceMotion: reduceMotion)) {
            selectedExerciseIds.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingExerciseId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct WorkoutPreviewSplit: Identifiable, Hashable {
    let id: UUID
    let name: String
    let exercises: [WorkoutSelectableExercise]

    init(id: UUID, name: String, exercises: [WorkoutSelectableExercise]) {
        self.id = id
        self.name = name
        self.exercises = exercises
    }

    init(_ split: TrainingSplit) {
        id = split.id
        name = split.name
        exercises = split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(WorkoutSelectableExercise.init)
    }
}

struct WorkoutSelectableExercise: Identifiable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?

    var exerciseNameSnapshot: String {
        name
    }

    init(_ splitExercise: SplitExercise) {
        id = splitExercise.id
        exerciseId = splitExercise.exerciseId
        name = splitExercise.exerciseNameSnapshot
        targetSets = splitExercise.targetSets
        minReps = splitExercise.minReps
        maxReps = splitExercise.maxReps
        notes = splitExercise.notes
    }

    init(id: UUID, exerciseId: UUID, name: String, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.notes = notes
    }
}
