import Foundation

@MainActor
final class WorkoutDashboardWarmStartStore {
    static let shared = WorkoutDashboardWarmStartStore()

    private(set) var trainingCall: TrainingCallSnapshot?
    private(set) var sourceSignature: String?

    private init() {}

    func update(trainingCall: TrainingCallSnapshot, sourceSignature: String) {
        self.trainingCall = trainingCall
        self.sourceSignature = sourceSignature
    }
}

struct SavedFoodSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let barcode: String?
    let name: String
    let brand: String?
    let servingSize: Double?
    let baseUnit: FoodAmountUnit
    let caloriesPer100g: Double?
    let proteinPer100g: Double?
    let carbsPer100g: Double?
    let fatPer100g: Double?
    let sugarPer100g: Double?
    let fibrePer100g: Double?
    let saltPer100g: Double?
    let source: FoodDataSource
    let verificationStatus: FoodVerificationStatus
    let createdAt: Date
    let updatedAt: Date

    init(_ food: FoodItem) {
        id = food.id
        barcode = food.barcode
        name = food.name
        brand = food.brand
        servingSize = food.servingSize
        baseUnit = food.baseUnit
        caloriesPer100g = food.caloriesPer100g
        proteinPer100g = food.proteinPer100g
        carbsPer100g = food.carbsPer100g
        fatPer100g = food.fatPer100g
        sugarPer100g = food.sugarPer100g
        fibrePer100g = food.fibrePer100g
        saltPer100g = food.saltPer100g
        source = food.source
        verificationStatus = food.verificationStatus
        createdAt = food.createdAt
        updatedAt = food.updatedAt
    }
}

struct SavedFoodCatalogSnapshot: Hashable, Sendable {
    let sourceSignature: String
    let foods: [SavedFoodSnapshot]

    static let empty = SavedFoodCatalogSnapshot(sourceSignature: "empty", foods: [])

    init(sourceSignature: String? = nil, foods: [SavedFoodSnapshot]) {
        let orderedFoods = foods.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return comparison == .orderedAscending
        }
        self.foods = orderedFoods
        self.sourceSignature = sourceSignature ?? Self.signature(for: orderedFoods)
    }

    func filtered(by query: String) -> [SavedFoodSnapshot] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedCaseInsensitiveContains(term)
                || ($0.brand?.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    func upserting(_ food: SavedFoodSnapshot) -> SavedFoodCatalogSnapshot {
        SavedFoodCatalogSnapshot(foods: foods.filter { $0.id != food.id } + [food])
    }

    func removing(id: UUID) -> SavedFoodCatalogSnapshot {
        SavedFoodCatalogSnapshot(foods: foods.filter { $0.id != id })
    }

    private static func signature(for foods: [SavedFoodSnapshot]) -> String {
        foods.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
        }.joined(separator: ",")
    }
}

struct SavedFoodPreparedRoute: Identifiable, Hashable, Sendable {
    let sourceSignature: String
    var id: String { sourceSignature }
}

@MainActor
final class SavedFoodWarmStartStore {
    static let shared = SavedFoodWarmStartStore()

    private(set) var catalog: SavedFoodCatalogSnapshot?
    private var catalogsBySignature: [String: SavedFoodCatalogSnapshot] = [:]
    private var signatureOrder: [String] = []
    private let retainedGenerationLimit = 3

    private init() {}

    func update(_ catalog: SavedFoodCatalogSnapshot) {
        self.catalog = catalog
        catalogsBySignature[catalog.sourceSignature] = catalog
        signatureOrder.removeAll { $0 == catalog.sourceSignature }
        signatureOrder.append(catalog.sourceSignature)

        while signatureOrder.count > retainedGenerationLimit {
            let evictedSignature = signatureOrder.removeFirst()
            catalogsBySignature.removeValue(forKey: evictedSignature)
        }
    }

    func preparedRoute() -> SavedFoodPreparedRoute? {
        guard let catalog else { return nil }
        return SavedFoodPreparedRoute(sourceSignature: catalog.sourceSignature)
    }

    func snapshot(for route: SavedFoodPreparedRoute) -> SavedFoodCatalogSnapshot? {
        catalogsBySignature[route.sourceSignature]
    }

    func upsert(_ food: SavedFoodSnapshot) {
        update((catalog ?? .empty).upserting(food))
    }

    func remove(id: UUID) {
        update((catalog ?? .empty).removing(id: id))
    }

    func resetForTesting() {
        catalog = nil
        catalogsBySignature.removeAll()
        signatureOrder.removeAll()
    }
}

struct WorkoutPreviewExerciseOption: Identifiable, Hashable, @unchecked Sendable {
    let id: UUID
    let name: String
    let primaryMuscleGroup: MuscleGroup?
    let secondaryMuscleGroups: [MuscleGroup]
    let movementPattern: MovementPattern?
    let equipment: EquipmentType?
    let isCompound: Bool
    let iconKey: ExerciseIconKey

    init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        primaryMuscleGroup = exercise.primaryMuscleGroup
        secondaryMuscleGroups = exercise.secondaryMuscleGroups
        movementPattern = exercise.movementPattern
        equipment = exercise.equipment
        isCompound = exercise.isCompound
        iconKey = ExerciseIconMapper.iconKey(forName: exercise.name)
    }

    init(planned exercise: WorkoutSelectableExercise) {
        id = exercise.exerciseId
        name = exercise.name
        primaryMuscleGroup = nil
        secondaryMuscleGroups = []
        movementPattern = nil
        equipment = nil
        isCompound = false
        iconKey = ExerciseIconMapper.iconKey(forName: exercise.name)
    }
}

struct WorkoutPreviewExerciseLookup: @unchecked Sendable {
    let byID: [UUID: WorkoutPreviewExerciseOption]
    let byName: [String: WorkoutPreviewExerciseOption]

    init(options: [WorkoutPreviewExerciseOption]) {
        byID = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byName = Dictionary(options.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(exercises: [Exercise]) {
        self.init(options: exercises.map(WorkoutPreviewExerciseOption.init))
    }
}

struct WorkoutPreviewPreparedSnapshot: @unchecked Sendable {
    let splitID: UUID
    let splitSignature: String
    let sourceSignature: String
    let mode: WorkoutMode
    let selectedExerciseIDs: [UUID]
    let orderedExercises: [WorkoutSelectableExercise]
    let exerciseOptions: [WorkoutPreviewExerciseOption]
    let addableExercises: [WorkoutPreviewExerciseOption]
    let coreExercise: WorkoutPreviewExerciseOption?
    let basePlannedExercises: [PlannedWorkoutExercise]
    let plannedExercises: [PlannedWorkoutExercise]
    let estimatedDuration: ClosedRange<Int>
    let suggestions: [UUID: TargetSuggestion]
    let alternatives: [UUID: [WorkoutPreviewExerciseOption]]
    let substitutionCandidates: [UUID: [ExerciseSubstitutionCandidate]]
    let intelligence: CoachIntelligenceSnapshot
    let plannedFatigueItems: [MuscleGroupFatigue]
    let actionRecommendations: [CoachWorkoutActionRecommendation]
    let actionPreviews: [CoachWorkoutAdjustmentAction: CoachWorkoutAdjustmentPreview]
    let trainingCall: TrainingCallSnapshot
    let coachSummaryText: String
    let coachSummaryBadge: CoachBadgeState
    let preparedAt: Date

    var selectedExerciseIDSet: Set<UUID> { Set(selectedExerciseIDs) }
    var exerciseLookup: WorkoutPreviewExerciseLookup {
        WorkoutPreviewExerciseLookup(options: exerciseOptions)
    }

    static func fallback(split: WorkoutPreviewSplit, mode: WorkoutMode) -> WorkoutPreviewPreparedSnapshot {
        let planner = WorkoutModePlanner()
        let plannedExercises = planner.plannedExercises(from: split.exercises, mode: mode)
        let suggestions = plannedExercises.reduce(into: [UUID: TargetSuggestion]()) { result, exercise in
            result[exercise.id] = TargetSuggestion(
                exerciseName: exercise.exerciseNameSnapshot,
                lastBestSetDescription: nil,
                lastBestWeight: nil,
                lastBestReps: nil,
                suggestedWeight: nil,
                suggestedReps: exercise.minReps,
                recommendationType: .baseline,
                reason: "Use the planned rep range and log clean working sets.",
                confidence: 0.45
            )
        }
        let intelligence = CoachIntelligenceService.emptySnapshot()
        let trainingCall = TrainingCallSnapshot(
            recommendedSplitName: split.name,
            recommendedMode: mode,
            action: .buildBaseline,
            title: "\(split.name) plan ready",
            reason: "Review the planned session and adjust the mode if needed.",
            confidence: .low,
            targetSummary: nil,
            sourceSignals: ["The workout template is available locally."],
            missingOrStaleInputs: [],
            guardrailNotes: ["Keep the first working sets controlled."],
            isConservative: true
        )

        let options = split.exercises.map { WorkoutPreviewExerciseOption(planned: $0) }
        return WorkoutPreviewPreparedSnapshot(
            splitID: split.id,
            splitSignature: WorkoutPreviewWarmStartStore.splitSignature(split),
            sourceSignature: "fallback",
            mode: mode,
            selectedExerciseIDs: plannedExercises.map(\.id),
            orderedExercises: split.exercises,
            exerciseOptions: options,
            addableExercises: [],
            coreExercise: options.first { $0.name == "Abdominal Crunch" },
            basePlannedExercises: plannedExercises,
            plannedExercises: plannedExercises,
            estimatedDuration: planner.estimatedDurationMinutes(for: plannedExercises, mode: mode),
            suggestions: suggestions,
            alternatives: [:],
            substitutionCandidates: [:],
            intelligence: intelligence,
            plannedFatigueItems: [],
            actionRecommendations: [],
            actionPreviews: [:],
            trainingCall: trainingCall,
            coachSummaryText: trainingCall.reason,
            coachSummaryBadge: mode == .recovery ? .recovery : .repeatTarget,
            preparedAt: .now
        )
    }
}

typealias WorkoutPreviewWarmSnapshot = WorkoutPreviewPreparedSnapshot

struct WorkoutPreviewPreparedRoute: Identifiable, Hashable {
    let split: WorkoutPreviewSplit
    let initialMode: WorkoutMode
    let cacheToken: String

    var id: String { "\(cacheToken)|\(initialMode.rawValue)" }

    static func == (lhs: WorkoutPreviewPreparedRoute, rhs: WorkoutPreviewPreparedRoute) -> Bool {
        lhs.cacheToken == rhs.cacheToken && lhs.initialMode == rhs.initialMode
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cacheToken)
        hasher.combine(initialMode)
    }
}

@MainActor
enum WorkoutPreviewSnapshotBuilder {
    static func build(
        activeSplits: [TrainingSplit],
        splitSnapshots: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession],
        completedWorkoutModels: [WorkoutSession],
        exercises: [Exercise],
        sourceSignature: String,
        coachSnapshot: CoachIntelligenceSnapshot
    ) -> [WorkoutPreviewWarmSnapshot] {
        let decision = TrainingDecisionService().decision(
            activeSplits: splitSnapshots,
            completedSessions: completedSessions
        )
        let modePlanner = WorkoutModePlanner()
        let targetService = TargetSuggestionService()
        let trainingCallBuilder = TrainingCallSnapshotBuilder()
        let substitutionService = ExerciseSubstitutionService()
        let adjustmentService = CoachWorkoutAdjustmentService()
        let exerciseOptions = exercises.map(WorkoutPreviewExerciseOption.init)
        ExerciseIconView.prewarm(exerciseOptions.map(\.iconKey))
        let optionsByID = Dictionary(exerciseOptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workoutUsedExerciseIDs = Set(
            completedWorkoutModels.flatMap { session in
                session.exerciseLogs.map(\.exerciseId)
            }
        )
        let candidatesByExerciseID = Dictionary(
            uniqueKeysWithValues: exercises.map { exercise in
                (
                    exercise.id,
                    substitutionService.candidates(
                        for: exercise.id,
                        in: exercises,
                        usedExerciseIDs: workoutUsedExerciseIDs,
                        reason: nil
                    )
                )
            }
        )
        WorkoutPreviewWarmStartStore.shared.registerPreparationCatalog(
            options: exerciseOptions,
            candidatesByExerciseID: candidatesByExerciseID
        )

        return activeSplits.flatMap { activeSplit in
            let previewSplit = WorkoutPreviewSplit(activeSplit)
            let splitSignature = WorkoutPreviewWarmStartStore.splitSignature(previewSplit)
            var orderedExercises = previewSplit.exercises
            if
                !orderedExercises.contains(where: { $0.name == "Abdominal Crunch" }),
                let core = exercises.first(where: { $0.name == "Abdominal Crunch" })
            {
                orderedExercises.append(
                    WorkoutSelectableExercise(
                        id: core.id,
                        exerciseId: core.id,
                        name: core.name,
                        targetSets: 2,
                        minReps: 8,
                        maxReps: 15,
                        notes: "Optional core work."
                    )
                )
            }
            let plannedExercisesByMode = Dictionary(
                uniqueKeysWithValues: WorkoutMode.allCases.map { mode in
                    (
                        mode,
                        modePlanner.plannedExercises(
                            from: orderedExercises,
                            mode: mode
                        )
                    )
                }
            )
            var baseSuggestionsByInput: [TargetSuggestionInput: TargetSuggestion] = [:]
            for exercise in orderedExercises {
                let input = TargetSuggestionInput(exercise)
                guard baseSuggestionsByInput[input] == nil else { continue }
                baseSuggestionsByInput[input] = targetService.suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
            }

            return WorkoutMode.allCases.map { mode in
                let plannedExercises = plannedExercisesByMode[mode] ?? []
                let suggestions = plannedExercises.reduce(into: [UUID: TargetSuggestion]()) { result, exercise in
                    let input = TargetSuggestionInput(exercise)
                    guard let suggestion = baseSuggestionsByInput[input] else { return }
                    result[exercise.id] = modePlanner.modeAdjustedSuggestion(
                        suggestion,
                        mode: mode
                    )
                }
                let trainingCall = trainingCallBuilder.make(
                    decision: decision,
                    activeSplits: splitSnapshots,
                    completedSessions: completedSessions,
                    readiness: coachSnapshot.readiness,
                    fatigueRisk: coachSnapshot.fatigueRisk,
                    targetSuggestions: Array(suggestions.values),
                    selectedPreviewMode: mode
                )
                let selectedExerciseIDs = Set(plannedExercises.map(\.exerciseId))
                let candidates = plannedExercises.reduce(into: [UUID: [ExerciseSubstitutionCandidate]]()) { result, planned in
                    result[planned.id] = candidatesByExerciseID[planned.exerciseId] ?? []
                }
                let alternatives = candidates.mapValues { values in
                    values.compactMap { optionsByID[$0.exerciseId] }
                }
                let plannedGroups = Set(plannedExercises.flatMap { planned -> [MuscleGroup] in
                    guard let option = optionsByID[planned.exerciseId], let primary = option.primaryMuscleGroup else { return [] }
                    return [primary] + option.secondaryMuscleGroups
                })
                let plannedFatigue = coachSnapshot.muscleFatigue.filter { plannedGroups.contains($0.muscleGroup) }
                let actionRecommendations = adjustmentService.recommendations(
                    for: coachSnapshot,
                    plannedExercises: plannedExercises,
                    plannedMuscleFatigue: plannedFatigue
                )
                let actionPreviews = Dictionary(
                    uniqueKeysWithValues: actionRecommendations.map { recommendation in
                        (
                            recommendation.action,
                            adjustmentService.makePreview(
                                action: recommendation.action,
                                plannedExercises: plannedExercises,
                                snapshot: coachSnapshot,
                                exercises: exercises,
                                plannedMuscleFatigue: plannedFatigue,
                                splitName: previewSplit.name
                            )
                        )
                    }
                )
                let summaryBadge = summaryBadge(
                    suggestions: suggestions,
                    mode: mode
                )

                return WorkoutPreviewWarmSnapshot(
                    splitID: previewSplit.id,
                    splitSignature: splitSignature,
                    sourceSignature: sourceSignature,
                    mode: mode,
                    selectedExerciseIDs: plannedExercises.map(\.id),
                    orderedExercises: orderedExercises,
                    exerciseOptions: exerciseOptions,
                    addableExercises: exerciseOptions.filter { !selectedExerciseIDs.contains($0.id) },
                    coreExercise: exerciseOptions.first { $0.name == "Abdominal Crunch" },
                    basePlannedExercises: plannedExercises,
                    plannedExercises: plannedExercises,
                    estimatedDuration: modePlanner.estimatedDurationMinutes(
                        for: plannedExercises,
                        mode: mode
                    ),
                    suggestions: suggestions,
                    alternatives: alternatives,
                    substitutionCandidates: candidates,
                    intelligence: coachSnapshot,
                    plannedFatigueItems: plannedFatigue,
                    actionRecommendations: actionRecommendations,
                    actionPreviews: actionPreviews,
                    trainingCall: trainingCall,
                    coachSummaryText: summaryText(suggestions: suggestions, mode: mode, trainingCall: trainingCall),
                    coachSummaryBadge: summaryBadge,
                    preparedAt: .now
                )
            }
        }
    }

    private struct TargetSuggestionInput: Hashable {
        let exerciseID: UUID
        let exerciseName: String
        let minimumReps: Int
        let maximumReps: Int

        init(_ exercise: WorkoutSelectableExercise) {
            exerciseID = exercise.exerciseId
            exerciseName = exercise.exerciseNameSnapshot
            minimumReps = exercise.minReps
            maximumReps = exercise.maxReps
        }

        init(_ exercise: PlannedWorkoutExercise) {
            exerciseID = exercise.exerciseId
            exerciseName = exercise.exerciseNameSnapshot
            minimumReps = exercise.minReps
            maximumReps = exercise.maxReps
        }
    }

    private static func summaryBadge(
        suggestions: [UUID: TargetSuggestion],
        mode: WorkoutMode
    ) -> CoachBadgeState {
        if suggestions.values.contains(where: { $0.recommendationType == .fatigueRisk }) { return .fatigueRisk }
        if suggestions.values.contains(where: { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }) { return .ready }
        return mode == .recovery ? .recovery : .repeatTarget
    }

    private static func summaryText(
        suggestions: [UUID: TargetSuggestion],
        mode: WorkoutMode,
        trainingCall: TrainingCallSnapshot
    ) -> String {
        if trainingCall.recommendedMode != mode || trainingCall.isConservative { return trainingCall.reason }
        if suggestions.values.contains(where: { $0.recommendationType == .fatigueRisk }) {
            return "Performance has dipped on at least one lift. Keep the session controlled and rest properly."
        }
        if let increase = suggestions.values.first(where: { $0.recommendationType == .increaseLoad }) {
            return "Progress opportunity: push \(increase.exerciseName), then keep the rest efficient."
        }
        if mode == .recovery { return "Lower stress session. Repeat targets, keep form clean, and avoid forcing PRs." }
        if mode == .quick { return "Short session. Hit the important lifts first and leave accessories optional." }
        return "Targets are ready. Repeat or add reps where the range allows."
    }
}

@MainActor
final class WorkoutPreviewWarmStartStore {
    static let shared = WorkoutPreviewWarmStartStore()

    private var snapshotsByKey: [String: WorkoutPreviewWarmSnapshot] = [:]
    private var fallbackKeys: [String] = []
    private var routeSnapshotsByToken: [String: [WorkoutMode: WorkoutPreviewPreparedSnapshot]] = [:]
    private var routeTokens: [String] = []
    private var mountedRouteTokens: Set<String> = []
    private var pendingActiveSnapshots: [WorkoutPreviewWarmSnapshot]?
    private var pendingCatalog: ([WorkoutPreviewExerciseOption], [UUID: [ExerciseSubstitutionCandidate]])?
    private var pendingUpserts: [String: WorkoutPreviewWarmSnapshot] = [:]
    private var preparationOptions: [WorkoutPreviewExerciseOption] = []
    private var preparationCandidatesByExerciseID: [UUID: [ExerciseSubstitutionCandidate]] = [:]
    private let fallbackLimit = 8
    private let routeLimit = 16

    private init() {}

    var cachedSnapshotCountForTesting: Int {
        snapshotsByKey.count
    }

    func resetForTesting() {
        snapshotsByKey.removeAll()
        fallbackKeys.removeAll()
        routeSnapshotsByToken.removeAll()
        routeTokens.removeAll()
        mountedRouteTokens.removeAll()
        pendingActiveSnapshots = nil
        pendingCatalog = nil
        pendingUpserts.removeAll()
        preparationOptions.removeAll()
        preparationCandidatesByExerciseID.removeAll()
    }

    func replaceActiveSnapshots(_ snapshots: [WorkoutPreviewWarmSnapshot]) {
        guard mountedRouteTokens.isEmpty else {
            pendingActiveSnapshots = snapshots
            return
        }
        publishActiveSnapshots(snapshots)
    }

    private func publishActiveSnapshots(_ snapshots: [WorkoutPreviewWarmSnapshot]) {
        let fallbackSnapshots = snapshotsByKey.filter { fallbackKeys.contains($0.key) }
        snapshotsByKey = Dictionary(
            snapshots.map { (Self.key(splitID: $0.splitID, splitSignature: $0.splitSignature, mode: $0.mode), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for (key, snapshot) in fallbackSnapshots {
            if snapshotsByKey[key] == nil {
                snapshotsByKey[key] = snapshot
            }
        }
        fallbackKeys = fallbackKeys.filter { snapshotsByKey[$0]?.sourceSignature.hasPrefix("fallback") == true }
        PerformanceTracer.mark(.workoutPreviewWarmCache, "published active=\(snapshots.count)")
    }

    func registerPreparationCatalog(
        options: [WorkoutPreviewExerciseOption],
        candidatesByExerciseID: [UUID: [ExerciseSubstitutionCandidate]]
    ) {
        guard mountedRouteTokens.isEmpty else {
            pendingCatalog = (options, candidatesByExerciseID)
            return
        }
        publishPreparationCatalog(options: options, candidatesByExerciseID: candidatesByExerciseID)
    }

    private func publishPreparationCatalog(
        options: [WorkoutPreviewExerciseOption],
        candidatesByExerciseID: [UUID: [ExerciseSubstitutionCandidate]]
    ) {
        preparationOptions = options
        preparationCandidatesByExerciseID = candidatesByExerciseID
        PerformanceTracer.mark(.workoutPreviewWarmCache, "catalog prepared exercises=\(options.count)")
    }

    func snapshot(for split: WorkoutPreviewSplit, mode: WorkoutMode) -> WorkoutPreviewWarmSnapshot? {
        let key = Self.key(
            splitID: split.id,
            splitSignature: Self.splitSignature(split),
            mode: mode
        )
        guard let snapshot = snapshotsByKey[key] else {
            PerformanceTracer.mark(.workoutPreviewWarmCache, "miss split=\(split.name) mode=\(mode.rawValue)")
            return nil
        }
        PerformanceTracer.mark(.workoutPreviewWarmCache, "hit split=\(split.name) mode=\(mode.rawValue)")
        return snapshot
    }

    func prepareRoute(
        for split: WorkoutPreviewSplit,
        initialMode: WorkoutMode
    ) -> WorkoutPreviewPreparedRoute {
        for mode in WorkoutMode.allCases where snapshotWithoutTracing(for: split, mode: mode) == nil {
            insertFallback(makePreparedFallback(split: split, mode: mode))
        }

        let snapshots = Dictionary(
            uniqueKeysWithValues: WorkoutMode.allCases.compactMap { mode in
                snapshotWithoutTracing(for: split, mode: mode).map { (mode, $0) }
            }
        )
        precondition(snapshots.count == WorkoutMode.allCases.count, "A Preview route requires every mode to be prepared")

        let generation = snapshots[initialMode]?.sourceSignature ?? "fallback"
        let token = "\(Self.routeToken(split))|\(Self.stableDigest(generation))"
        routeSnapshotsByToken[token] = snapshots
        routeTokens.removeAll { $0 == token }
        routeTokens.append(token)
        while routeTokens.count > routeLimit {
            routeSnapshotsByToken.removeValue(forKey: routeTokens.removeFirst())
        }

        return WorkoutPreviewPreparedRoute(
            split: split,
            initialMode: initialMode,
            cacheToken: token
        )
    }

    func snapshot(
        for route: WorkoutPreviewPreparedRoute,
        mode: WorkoutMode
    ) -> WorkoutPreviewPreparedSnapshot? {
        guard let snapshot = routeSnapshotsByToken[route.cacheToken]?[mode] else {
            PerformanceTracer.mark(.workoutPreviewWarmCache, "reject unresolved route split=\(route.split.name) mode=\(mode.rawValue)")
            return nil
        }
        PerformanceTracer.mark(.workoutPreviewWarmCache, "hit route split=\(route.split.name) mode=\(mode.rawValue)")
        return snapshot
    }

    func routeDidMount(_ route: WorkoutPreviewPreparedRoute) {
        mountedRouteTokens.insert(route.cacheToken)
    }

    func routeDidDismiss(_ route: WorkoutPreviewPreparedRoute) {
        mountedRouteTokens.remove(route.cacheToken)
        guard mountedRouteTokens.isEmpty else { return }

        if let pendingActiveSnapshots {
            self.pendingActiveSnapshots = nil
            publishActiveSnapshots(pendingActiveSnapshots)
        }
        if let pendingCatalog {
            self.pendingCatalog = nil
            publishPreparationCatalog(
                options: pendingCatalog.0,
                candidatesByExerciseID: pendingCatalog.1
            )
        }
        if !pendingUpserts.isEmpty {
            let upserts = pendingUpserts.values
            pendingUpserts.removeAll()
            for snapshot in upserts {
                publishUpsert(snapshot)
            }
        }
    }

    func insertFallback(_ snapshot: WorkoutPreviewWarmSnapshot) {
        let key = Self.key(
            splitID: snapshot.splitID,
            splitSignature: snapshot.splitSignature,
            mode: snapshot.mode
        )
        snapshotsByKey[key] = snapshot
        fallbackKeys.removeAll { $0 == key }
        fallbackKeys.append(key)

        while fallbackKeys.count > fallbackLimit {
            let removedKey = fallbackKeys.removeFirst()
            snapshotsByKey.removeValue(forKey: removedKey)
        }
    }

    func upsert(_ snapshot: WorkoutPreviewWarmSnapshot) {
        let key = Self.key(
            splitID: snapshot.splitID,
            splitSignature: snapshot.splitSignature,
            mode: snapshot.mode
        )
        guard mountedRouteTokens.isEmpty else {
            pendingUpserts[key] = snapshot
            return
        }
        publishUpsert(snapshot, key: key)
    }

    private func publishUpsert(
        _ snapshot: WorkoutPreviewWarmSnapshot,
        key: String? = nil
    ) {
        let key = key ?? Self.key(
            splitID: snapshot.splitID,
            splitSignature: snapshot.splitSignature,
            mode: snapshot.mode
        )
        snapshotsByKey[key] = snapshot
        fallbackKeys.removeAll { $0 == key }
        PerformanceTracer.mark(
            .workoutPreviewWarmCache,
            "updated split=\(snapshot.splitID.uuidString) mode=\(snapshot.mode.rawValue)"
        )
    }

    nonisolated static func splitSignature(_ split: WorkoutPreviewSplit) -> String {
        split.exercises.map {
            [
                $0.id.uuidString,
                $0.exerciseId.uuidString,
                $0.name,
                "\($0.targetSets)",
                "\($0.minReps)",
                "\($0.maxReps)",
                $0.notes ?? ""
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    nonisolated static func routeToken(_ split: WorkoutPreviewSplit) -> String {
        "\(split.id.uuidString)|\(stableDigest(splitSignature(split)))"
    }

    nonisolated static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func snapshotWithoutTracing(
        for split: WorkoutPreviewSplit,
        mode: WorkoutMode
    ) -> WorkoutPreviewPreparedSnapshot? {
        snapshotsByKey[
            Self.key(
                splitID: split.id,
                splitSignature: Self.splitSignature(split),
                mode: mode
            )
        ]
    }

    private func makePreparedFallback(
        split: WorkoutPreviewSplit,
        mode: WorkoutMode
    ) -> WorkoutPreviewPreparedSnapshot {
        var orderedExercises = split.exercises
        if
            !orderedExercises.contains(where: { $0.name == "Abdominal Crunch" }),
            let core = preparationOptions.first(where: { $0.name == "Abdominal Crunch" })
        {
            orderedExercises.append(
                WorkoutSelectableExercise(
                    id: core.id,
                    exerciseId: core.id,
                    name: core.name,
                    targetSets: 2,
                    minReps: 8,
                    maxReps: 15,
                    notes: "Optional core work."
                )
            )
        }

        let preparedSplit = WorkoutPreviewSplit(
            id: split.id,
            name: split.name,
            exercises: orderedExercises
        )
        let base = WorkoutPreviewPreparedSnapshot.fallback(split: preparedSplit, mode: mode)
        let context = snapshotsByKey.values.first {
            $0.mode == mode && !$0.sourceSignature.hasPrefix("fallback")
        }
        let options = preparationOptions.isEmpty ? base.exerciseOptions : preparationOptions
        let optionsByID = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedExerciseIDs = Set(base.plannedExercises.map(\.exerciseId))
        let candidates = base.plannedExercises.reduce(into: [UUID: [ExerciseSubstitutionCandidate]]()) { result, planned in
            result[planned.id] = preparationCandidatesByExerciseID[planned.exerciseId] ?? []
        }
        let alternatives = candidates.mapValues { values in
            values.compactMap { optionsByID[$0.exerciseId] }
        }
        let intelligence = context?.intelligence ?? base.intelligence
        let plannedGroups = Set(base.plannedExercises.flatMap { planned -> [MuscleGroup] in
            guard let option = optionsByID[planned.exerciseId], let primary = option.primaryMuscleGroup else { return [] }
            return [primary] + option.secondaryMuscleGroups
        })
        let fatigue = intelligence.muscleFatigue.filter { plannedGroups.contains($0.muscleGroup) }
        let adjustmentService = CoachWorkoutAdjustmentService()
        let recommendations = adjustmentService.recommendations(
            for: intelligence,
            plannedExercises: base.plannedExercises,
            plannedMuscleFatigue: fatigue
        )
        let transientExercises = options.compactMap { option -> Exercise? in
            guard
                let primary = option.primaryMuscleGroup,
                let movement = option.movementPattern,
                let equipment = option.equipment
            else { return nil }
            return Exercise(
                id: option.id,
                name: option.name,
                primaryMuscleGroup: primary,
                secondaryMuscleGroups: option.secondaryMuscleGroups,
                movementPattern: movement,
                equipment: equipment,
                isCompound: option.isCompound
            )
        }
        let actionPreviews = Dictionary(
            uniqueKeysWithValues: recommendations.map { recommendation in
                (
                    recommendation.action,
                    adjustmentService.makePreview(
                        action: recommendation.action,
                        plannedExercises: base.plannedExercises,
                        snapshot: intelligence,
                        exercises: transientExercises,
                        plannedMuscleFatigue: fatigue,
                        splitName: split.name
                    )
                )
            }
        )

        return WorkoutPreviewPreparedSnapshot(
            splitID: base.splitID,
            splitSignature: Self.splitSignature(split),
            sourceSignature: "fallback-prepared|\(context?.sourceSignature ?? "offline")",
            mode: base.mode,
            selectedExerciseIDs: base.selectedExerciseIDs,
            orderedExercises: base.orderedExercises,
            exerciseOptions: options,
            addableExercises: options.filter { !selectedExerciseIDs.contains($0.id) },
            coreExercise: options.first { $0.name == "Abdominal Crunch" },
            basePlannedExercises: base.basePlannedExercises,
            plannedExercises: base.plannedExercises,
            estimatedDuration: base.estimatedDuration,
            suggestions: base.suggestions,
            alternatives: alternatives,
            substitutionCandidates: candidates,
            intelligence: intelligence,
            plannedFatigueItems: fatigue,
            actionRecommendations: recommendations,
            actionPreviews: actionPreviews,
            trainingCall: base.trainingCall,
            coachSummaryText: base.coachSummaryText,
            coachSummaryBadge: base.coachSummaryBadge,
            preparedAt: .now
        )
    }

    private static func key(splitID: UUID, splitSignature: String, mode: WorkoutMode) -> String {
        "\(splitID.uuidString)|\(mode.rawValue)|\(stableDigest(splitSignature))"
    }
}

struct WarmStartSnapshotEnvelope<Payload: Codable>: Codable {
    let schemaVersion: Int
    let screenKey: String
    let sourceSignature: String
    let createdAt: Date
    let payload: Payload
}

actor WarmStartSnapshotStore {
    static let shared = WarmStartSnapshotStore()

    private let directoryURL: URL
    private let schemaVersion = 1

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = baseURL
                .appendingPathComponent("Peakline", isDirectory: true)
                .appendingPathComponent("WarmStartSnapshots", isDirectory: true)
        }
    }

    func load<Payload: Codable>(
        _ payloadType: Payload.Type,
        screenKey: String,
        matching sourceSignature: String? = nil,
        maxAge: TimeInterval? = nil
    ) async -> WarmStartSnapshotEnvelope<Payload>? {
        let fileURL = fileURL(for: screenKey)

        return PerformanceTracer.trace(.warmStartLoad) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=missing")
                return nil
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let envelope = try decoder.decode(WarmStartSnapshotEnvelope<Payload>.self, from: data)

                guard envelope.schemaVersion == schemaVersion else {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=schema")
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }

                guard envelope.screenKey == screenKey else {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=screen_key")
                    return nil
                }

                if let sourceSignature, envelope.sourceSignature != sourceSignature {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=signature")
                    return nil
                }

                if let maxAge, Date().timeIntervalSince(envelope.createdAt) > maxAge {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=expired")
                    return nil
                }

                PerformanceTracer.mark(.warmStartCacheHit, "screen=\(screenKey) bytes=\(data.count)")
                return envelope
            } catch {
                PerformanceTracer.mark(.warmStartDecodeFailed, "screen=\(screenKey) error=\(String(describing: error))")
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
        }
    }

    func save<Payload: Codable>(
        _ payload: Payload,
        screenKey: String,
        sourceSignature: String
    ) async {
        PerformanceTracer.trace(.warmStartPersist) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let envelope = WarmStartSnapshotEnvelope(
                    schemaVersion: schemaVersion,
                    screenKey: screenKey,
                    sourceSignature: sourceSignature,
                    createdAt: Date(),
                    payload: payload
                )
                let data = try encoder.encode(envelope)
                try data.write(to: fileURL(for: screenKey), options: [.atomic])
                PerformanceTracer.mark(.warmStartPersist, "screen=\(screenKey) bytes=\(data.count)")
            } catch {
                PerformanceTracer.mark(.warmStartPersist, "screen=\(screenKey) error=\(String(describing: error))")
            }
        }
    }

    func clear(screenKey: String) async {
        try? FileManager.default.removeItem(at: fileURL(for: screenKey))
    }

    func snapshotFileURL(forTesting screenKey: String) -> URL {
        fileURL(for: screenKey)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fileURL(for screenKey: String) -> URL {
        let safeName = screenKey.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        return directoryURL.appendingPathComponent(String(safeName)).appendingPathExtension("json")
    }
}
