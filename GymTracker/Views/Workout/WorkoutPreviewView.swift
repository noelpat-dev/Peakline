import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    private let substitutionService = ExerciseSubstitutionService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()

    init(split: TrainingSplit) {
        self.split = WorkoutPreviewSplit(split)
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

    init(split: WorkoutPreviewSplit) {
        self.split = split
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

    private var renderSignature: String {
        [
            split.id.uuidString,
            selectedMode.rawValue,
            selectedExerciseIds.map(\.uuidString).joined(separator: ","),
            substitutionNotesByExerciseId
                .map { "\($0.key.uuidString):\($0.value)" }
                .sorted()
                .joined(separator: ","),
            appliedWorkoutAdjustment?.id.uuidString ?? "none",
            signature(exercises, limit: 180) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(completedSessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(sleepSessions, limit: 60) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachActionHistory, limit: 120) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(recommendationFeedback, limit: 120) { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" },
            signature(savedDeloadBlocks, limit: 40) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(exerciseMetadata, limit: 180) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachPreferences, limit: 5) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(splitMetadataRecords, limit: 40) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "\(sleepSettings.lastHealthKitSleepSyncAt?.timeIntervalSince1970 ?? 0)",
            "\(hydrationTargetML)",
            nutritionGoalSignature
        ].joined(separator: "|")
    }

    private var nutritionGoalSignature: String {
        guard nutritionGoal.hasTargets else { return "nutrition-goal-empty" }
        return "\(nutritionGoal.updatedAt.timeIntervalSince1970)"
    }

    private func refreshRenderSnapshot(force: Bool = false) {
        let signature = renderSignature
        guard force || signature != lastRenderSignature else { return }
        renderSnapshot = PerformanceTracer.trace(.workoutPreviewRenderSnapshot) {
            makeRenderSnapshot()
        }
        lastRenderSignature = signature
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }

    private func makeRenderSnapshot() -> WorkoutPreviewRenderSnapshot {
        let orderedExercises = makeOrderedExercises()
        let selectedBaseExercises = makeSelectedBaseExercises(orderedExercises: orderedExercises)
        let basePlannedExercises = modePlanner.plannedExercises(from: selectedBaseExercises, mode: selectedMode)
        let plannedExercises = appliedWorkoutAdjustment?.adjustedExercises ?? basePlannedExercises
        let estimatedDuration = modePlanner.estimatedDurationMinutes(for: plannedExercises, mode: selectedMode)
        let suggestions = suggestionsByExerciseId(for: plannedExercises)
        let alternatives = alternativesByExerciseId(for: plannedExercises)
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let plannedMuscleGroups = Set(plannedExercises.flatMap { planned in
            exerciseByID[planned.exerciseId].map { exercise in
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

        return WorkoutPreviewRenderSnapshot(
            orderedExercises: orderedExercises,
            basePlannedExercises: basePlannedExercises,
            plannedExercises: plannedExercises,
            estimatedDuration: estimatedDuration,
            suggestions: suggestions,
            alternatives: alternatives,
            intelligence: intelligence,
            plannedFatigueItems: plannedFatigueItems,
            actionRecommendations: actionRecommendations,
            coachSummaryText: coachSummaryText(suggestions: suggestions, mode: selectedMode),
            coachSummaryBadge: coachSummaryBadge(suggestions: suggestions, mode: selectedMode)
        )
    }

    private func makeOrderedExercises() -> [WorkoutSelectableExercise] {
        var items = split.exercises

        if
            !items.contains(where: { $0.name == "Abdominal Crunch" }),
            let abdominalCrunch = exercises.first(where: { $0.name == "Abdominal Crunch" })
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

    private func makeSelectedBaseExercises(orderedExercises: [WorkoutSelectableExercise]) -> [WorkoutSelectableExercise] {
        selectedExerciseIds.compactMap { selectedId in
            if let planned = orderedExercises.first(where: { $0.id == selectedId }) {
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

            guard let exercise = exercises.first(where: { $0.id == selectedId }) else { return nil }

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
            suggestion: suggestions[exercise.id] ?? targetSuggestion(for: exercise),
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
        .destructiveSwipeAction("Remove") {
            remove(exercise)
        }
    }

    var body: some View {
        let snapshot = currentRenderSnapshot

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

            DashboardSection(title: "Coach Brief") {
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
            }

            DashboardSection(title: "Session Snapshot") {
                HStack(spacing: 10) {
                    MetricTile(label: "Exercises", value: "\(snapshot.plannedExercises.count)", caption: "\(selectedMode.displayName) mode", systemImage: "list.bullet")
                    MetricTile(label: "Estimate", value: "\(snapshot.estimatedDuration.lowerBound)-\(snapshot.estimatedDuration.upperBound)m", caption: "Session time", systemImage: "clock")
                }
            }

            DashboardSection(title: "Exercise Order") {
                HStack {
                    Spacer()
                    Button("Select All") {
                        selectedExerciseIds = snapshot.orderedExercises.map(\.id)
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
                                alternatives: snapshot.alternatives
                            )
                        }
                    }
                }
            }

            DashboardSection(title: "Add Exercise") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Optional exercise", selection: $optionalExerciseId) {
                            Text("Choose").tag(Optional<UUID>.none)
                            ForEach(addableExercises) { exercise in
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

                            if let coreExercise = exercises.first(where: { $0.name == "Abdominal Crunch" }) {
                                Button {
                                    addExercise(coreExercise, targetSets: 2, minReps: 8, maxReps: 15, notes: "Optional core work.")
                                } label: {
                                    Label("Add Core", systemImage: "figure.core.training")
                                }
                                .disabled(selectedExerciseIds.contains(coreExercise.id))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            DashboardSection(title: "Start") {
                FitnessCard(style: .hero) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            activeSession = createWorkout(from: split)
                        } label: {
                            Label(startButtonTitle, systemImage: "play.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .accessibilityIdentifier("workout-preview-start")
                        .disabled(snapshot.plannedExercises.isEmpty)

                        if appliedWorkoutAdjustment != nil {
                        Button {
                            if let appliedWorkoutAdjustment {
                                recordCoachAction(
                                    preview: appliedWorkoutAdjustment.preview,
                                    outcome: .bypassed,
                                    snapshot: snapshot.intelligence
                                )
                            }
                            activeSession = createWorkout(from: split, plannedExercises: snapshot.basePlannedExercises, modeLabel: "\(selectedMode.displayName) Original")
                        } label: {
                            Label("Start Original Plan", systemImage: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .accessibilityIdentifier("workout-preview-start-original")
                        .disabled(snapshot.basePlannedExercises.isEmpty)
                        }

                        Text(startHint)
                            .font(.footnote)
                            .foregroundStyle(appTheme.mutedText)
                    }
                }
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
                    if let replacement = exercises.first(where: { $0.id == candidate.exerciseId }) {
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
                selectedExerciseIds = modePlanner.plannedExercises(from: makeOrderedExercises(), mode: selectedMode).map(\.id)
            }
            refreshRenderSnapshot(force: true)
        }
        .onChange(of: renderSignature) { _, _ in
            refreshRenderSnapshot()
        }
        .onChange(of: selectedMode) { _, newMode in
            resetCoachAdjustment()
            selectedExerciseIds = modePlanner.plannedExercises(from: makeOrderedExercises(), mode: newMode).map(\.id)
        }
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

    private func coachSummaryText(suggestions: [UUID: TargetSuggestion], mode: WorkoutMode) -> String {
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

    private var addableExercises: [Exercise] {
        exercises.filter { exercise in
            !selectedExerciseIds.contains(exercise.id)
        }
    }

    private func remove(_ exercise: PlannedWorkoutExercise) {
        resetCoachAdjustment()
        selectedExerciseIds.removeAll { $0 == exercise.id }
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
        selectedExerciseIds = ids
    }

    private func addOptionalExercise() {
        guard
            let optionalExerciseId,
            let exercise = exercises.first(where: { $0.id == optionalExerciseId })
        else { return }

        addExercise(exercise, targetSets: 2, minReps: 8, maxReps: 12, notes: "Added for today's workout.")
        self.optionalExerciseId = nil
    }

    private func addExercise(_ exercise: Exercise, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        guard !selectedExerciseIds.contains(exercise.id) else { return }
        resetCoachAdjustment()
        selectedExerciseIds.append(exercise.id)
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

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: Exercise) {
        substitute(exercise, with: alternative, reason: .preferAlternative)
    }

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: Exercise, reason: ExerciseSubstitutionReason) {
        guard let index = selectedExerciseIds.firstIndex(of: exercise.id) else { return }
        resetCoachAdjustment()
        selectedExerciseIds[index] = alternative.id
        substitutionNotesByExerciseId[alternative.id] = substitutionService.substitutionNote(
            originalName: exercise.exerciseNameSnapshot,
            replacementName: alternative.name,
            reason: reason
        )
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
            activeCoachSheet = .deloadPlanner
            return
        }

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
    let orderedExercises: [WorkoutSelectableExercise]
    let basePlannedExercises: [PlannedWorkoutExercise]
    let plannedExercises: [PlannedWorkoutExercise]
    let estimatedDuration: ClosedRange<Int>
    let suggestions: [UUID: TargetSuggestion]
    let alternatives: [UUID: [Exercise]]
    let intelligence: CoachIntelligenceSnapshot
    let plannedFatigueItems: [MuscleGroupFatigue]
    let actionRecommendations: [CoachWorkoutActionRecommendation]
    let coachSummaryText: String
    let coachSummaryBadge: CoachBadgeState
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

        withAnimation(AppMotion.reorderSpring(reduceMotion: reduceMotion)) {
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
