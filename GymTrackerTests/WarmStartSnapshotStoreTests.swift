import XCTest
@testable import GymTracker

@MainActor
final class WarmStartSnapshotStoreTests: XCTestCase {
    func testWorkoutWarmStartSourceSignatureCanonicalizesCollectionOrder() {
        let first = WorkoutWarmStartSourceSignature.make(
            revision: 4,
            splitSignatures: ["split-b", "split-a"],
            workoutSignatures: ["workout-b", "workout-a"],
            exerciseSignatures: ["exercise-b", "exercise-a"]
        )
        let second = WorkoutWarmStartSourceSignature.make(
            revision: 4,
            splitSignatures: ["split-a", "split-b"],
            workoutSignatures: ["workout-a", "workout-b"],
            exerciseSignatures: ["exercise-a", "exercise-b"]
        )

        XCTAssertEqual(first, second)
    }

    func testCoachWarmRefreshSignaturesSurvivePublicationButInvalidateChangedIntelligence() {
        let prepared = CoachRouteRenderSnapshot(
            intelligence: CoachIntelligenceService.emptySnapshot(),
            weeklyReview: nil,
            derivedMetrics: .placeholder,
            sleepAnalytics: SleepAnalyticsService.emptySnapshot(),
            trainingCall: .placeholder,
            intelligenceInputSignature: "prepared-recovery",
            trainingInputSignature: "prepared-training"
        )
        let published = prepared.withSourceGeneration(12)
        XCTAssertEqual(published.intelligenceInputSignature, "prepared-recovery")
        XCTAssertEqual(published.trainingInputSignature, "prepared-training")
        let changed = published.replacing(
            intelligence: CoachIntelligenceService.emptySnapshot(),
            trainingCall: .placeholder,
            recommendedSplit: nil,
            sourceGeneration: 13
        )
        XCTAssertNil(changed.intelligenceInputSignature)
        XCTAssertEqual(changed.trainingInputSignature, "prepared-training")
    }

    func testPreparedRecoveryCoachTargetUsesLastBestRepeatTarget() throws {
        let rawTarget = TargetSuggestion(
            exerciseName: "Bench Press",
            lastBestSetDescription: "100kg x 10",
            lastBestWeight: 100,
            lastBestReps: 10,
            suggestedWeight: 102.5,
            suggestedReps: 6,
            recommendationType: .increaseLoad,
            reason: "You reached the top of the rep range. Add a small load jump.",
            confidence: 0.78
        )
        let baselineTarget = TargetSuggestion(
            exerciseName: "Chest Fly",
            lastBestSetDescription: nil,
            lastBestWeight: nil,
            lastBestReps: nil,
            suggestedWeight: nil,
            suggestedReps: 10,
            recommendationType: .baseline,
            reason: "Build a baseline.",
            confidence: 0.45
        )
        let derivedMetrics = CoachDerivedMetrics(
            summary: CoachDerivedMetrics.placeholder.summary,
            recentPRs: [],
            targetSuggestions: [baselineTarget, rawTarget],
            weeklyWorkoutCount: 0,
            weeklyWorkingSetCount: 0,
            progressOpportunityInsights: []
        )
        let recoveryCall = TrainingCallSnapshot(
            recommendedSplitName: "Push",
            recommendedMode: .recovery,
            action: .recover,
            title: "Recovery mode makes sense",
            reason: "Recovery signals keep today's plan lighter.",
            confidence: .high,
            targetSummary: "Bench Press: keep this controlled rather than chasing progression.",
            sourceSignals: [],
            missingOrStaleInputs: [],
            guardrailNotes: [],
            isConservative: true
        )

        let prepared = CoachRouteRenderSnapshot(
            intelligence: CoachIntelligenceService.emptySnapshot(),
            weeklyReview: nil,
            derivedMetrics: derivedMetrics,
            sleepAnalytics: SleepAnalyticsService.emptySnapshot(),
            trainingCall: recoveryCall
        )

        let target = try XCTUnwrap(prepared.dailyDecision.primaryTarget)
        XCTAssertEqual(target.exerciseName, "Bench Press")
        XCTAssertEqual(target.suggestedWeight, 100)
        XCTAssertEqual(target.suggestedReps, 10)
        XCTAssertEqual(target.recommendationType, .repeatTarget)
        XCTAssertEqual(prepared.derivedMetrics.targetSuggestions.last?.suggestedWeight, 102.5)
        XCTAssertEqual(prepared.derivedMetrics.targetSuggestions.last?.recommendationType, .increaseLoad)
    }

    func testCoachRoutePublicationKeepsFreshReadinessCallAndSplitInOneGeneration() {
        let store = CoachRouteSnapshotStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let base = CoachRouteRenderSnapshot(
            intelligence: CoachIntelligenceService.emptySnapshot(),
            weeklyReview: nil,
            derivedMetrics: .placeholder,
            sleepAnalytics: SleepAnalyticsService.emptySnapshot(),
            trainingCall: .placeholder,
            sourceGeneration: 1
        )
        store.update(snapshot: base, signature: "old", source: "test", sourceGeneration: 1)

        let freshCheckIn = DailyCoachCheckIn(
            date: .now,
            energy: 5,
            soreness: 1,
            stress: 1,
            motivation: 5,
            calendar: .current
        )
        let freshIntelligence = CoachIntelligenceService().snapshot(
            sleepSessions: [],
            napSessions: [],
            hydrationEntries: [],
            completedWorkouts: [],
            foodLogs: [],
            checkIns: [freshCheckIn],
            sleepSettings: .default,
            hydrationTargetML: 2_500,
            nutritionGoal: .empty
        )
        let freshCall = TrainingCallSnapshot(
            recommendedSplitName: "Pull",
            recommendedMode: .quick,
            action: .repeatTarget,
            title: "Pull ready",
            reason: "Fresh local evidence supports the next Pull session.",
            confidence: .medium,
            targetSummary: "Keep the main lifts crisp.",
            sourceSignals: ["Fresh workout history"],
            missingOrStaleInputs: [],
            guardrailNotes: ["Use warm-ups to confirm the load."],
            isConservative: false
        )
        let freshSplit = WorkoutPreviewSplit(id: UUID(), name: "Pull", exercises: [])
        let generation = store.nextSourceGeneration()

        store.update(
            intelligence: freshIntelligence,
            trainingCall: freshCall,
            recommendedSplit: freshSplit,
            fallback: base,
            signature: "fresh",
            sourceGeneration: generation,
            source: "test"
        )

        XCTAssertEqual(store.snapshot?.sourceGeneration, generation)
        XCTAssertEqual(store.snapshot?.intelligence.readiness.value, freshIntelligence.readiness.value)
        XCTAssertEqual(store.snapshot?.dailyDecision.trainingCall, freshCall)
        XCTAssertEqual(store.snapshot?.dailyDecision.recommendedSplitName, freshCall.recommendedSplitName)
        XCTAssertEqual(store.snapshot?.recommendedSplit?.name, freshSplit.name)

        store.update(snapshot: base, signature: "stale", source: "test", sourceGeneration: generation - 1)
        XCTAssertEqual(store.signature, "fresh")
        XCTAssertEqual(store.snapshot?.sourceGeneration, generation)
    }

    func testProgressWarmStartPayloadBoundsRowsAndRejectsOldGenerations() {
        let store = ProgressWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let revision = WorkoutWarmStartInvalidation.shared.revision
        let exercises = (0..<(ProgressWarmStartLimits.exerciseRowLimit + 4)).map { index in
            Exercise(
                name: String(format: "Exercise %03d", index),
                primaryMuscleGroup: .chest,
                movementPattern: .push,
                equipment: .barbell,
                isCompound: true
            )
        }
        let weekly = WeeklyTrainingSummary(
            weekStart: Date(timeIntervalSince1970: 1),
            weekEnd: Date(timeIntervalSince1970: 2),
            completedWorkouts: 1,
            workingSets: 2,
            splitCounts: ["Push": 1],
            totalTonnage: 100,
            bestSetVolumeTotal: 100,
            prCount: 0,
            consistencyMessage: "Keep going"
        )
        let consistency = SplitConsistencySummary(
            orderedCounts: [.init(name: "Push", count: 1)],
            missedSplitName: nil,
            balanceDescription: "Balanced"
        )
        let payload = ProgressWarmStartPayload(
            sourceSignature: "progress-source",
            workoutRevision: revision,
            weeklySummary: weekly,
            splitConsistency: consistency,
            exerciseRows: exercises.map(ProgressExerciseRowSnapshot.init)
        )

        store.update(payload)

        XCTAssertEqual(store.payload?.sourceSignature, "progress-source")
        XCTAssertEqual(store.payload?.workoutRevision, revision)
        XCTAssertEqual(store.exerciseRows.count, ProgressWarmStartLimits.exerciseRowLimit)
        XCTAssertNotNil(store.payload(matching: "progress-source", workoutRevision: revision))
        XCTAssertNil(store.payload(matching: "other-source", workoutRevision: revision))

        WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutSetEdited)
        XCTAssertNil(store.payload)
        XCTAssertNil(store.weeklySummary)
    }

    func testWorkoutWarmStartInvalidationPersistsAcrossStoreRecreation() throws {
        let suiteName = "WorkoutWarmStartInvalidationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = WorkoutWarmStartInvalidation(defaults: defaults)

        first.invalidate(reason: .completedWorkoutSetEdited)
        let recreated = WorkoutWarmStartInvalidation(defaults: defaults)

        XCTAssertEqual(recreated.revision, first.revision)
    }

    func testSaveAndLoadMatchingSnapshot() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        let payload = TestWarmStartPayload(title: "History", count: 3)

        await store.save(payload, screenKey: "history", sourceSignature: "source-a")

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "history", matching: "source-a")
        XCTAssertEqual(envelope?.payload, payload)
        XCTAssertEqual(envelope?.sourceSignature, "source-a")
        XCTAssertEqual(envelope?.screenKey, "history")
    }

    func testLoadRejectsMismatchedSourceSignature() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        await store.save(TestWarmStartPayload(title: "Workout", count: 2), screenKey: "workout_start", sourceSignature: "old-source")

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "workout_start", matching: "new-source")
        XCTAssertNil(envelope)
    }

    func testCorruptSnapshotReturnsNilAndClearsFile() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        let fileURL = await store.snapshotFileURL(forTesting: "history")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "history")
        XCTAssertNil(envelope)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSavedFoodCatalogSortsFiltersAndKeepsStableValues() {
        let banana = FoodItem(
            name: "Banana",
            brand: "Local",
            caloriesPer100g: 89,
            proteinPer100g: 1.1,
            carbsPer100g: 23,
            fatPer100g: 0.3
        )
        let apple = FoodItem(
            name: "Apple",
            brand: "Orchard",
            caloriesPer100g: 52,
            proteinPer100g: 0.3,
            carbsPer100g: 14,
            fatPer100g: 0.2
        )

        let catalog = SavedFoodCatalogSnapshot(
            foods: [SavedFoodSnapshot(banana), SavedFoodSnapshot(apple)]
        )

        XCTAssertEqual(catalog.foods.map(\.name), ["Apple", "Banana"])
        XCTAssertEqual(catalog.filtered(by: "orch").map(\.name), ["Apple"])
        XCTAssertEqual(catalog.filtered(by: "banana").first?.caloriesPer100g, 89)
    }

    func testSavedFoodCatalogUpsertAndRemovalCreateNewGenerations() {
        let food = FoodItem(name: "Apple", caloriesPer100g: 52)
        let initial = SavedFoodCatalogSnapshot(foods: [SavedFoodSnapshot(food)])

        food.name = "Green Apple"
        food.updatedAt = food.updatedAt.addingTimeInterval(1)
        let updated = initial.upserting(SavedFoodSnapshot(food))
        let removed = updated.removing(id: food.id)

        XCTAssertEqual(updated.foods.map(\.name), ["Green Apple"])
        XCTAssertNotEqual(updated.sourceSignature, initial.sourceSignature)
        XCTAssertTrue(removed.foods.isEmpty)
    }

    func testWorkoutWarmStartSignatureUsesScalarInputsAndRevision() {
        let session = WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            splitId: UUID(uuidString: "10000000-0000-0000-0000-000000000001"),
            endedAt: Date(timeIntervalSince1970: 1_700_002_700),
            durationMinutes: 45,
            durationSeconds: 2_700,
            completed: true
        )
        let splitSignatures = ["split-1"]
        let workoutSignatures = [WorkoutWarmStartSourceSignature.workout(session)]

        let initial = WorkoutWarmStartSourceSignature.make(
            revision: 7,
            splitSignatures: splitSignatures,
            workoutSignatures: workoutSignatures
        )
        session.exerciseLogs = [
            ExerciseLog(
                exerciseId: UUID(),
                exerciseNameSnapshot: "Bench Press",
                orderIndex: 0,
                setLogs: [SetLog(setNumber: 1, weight: 80, reps: 8, completed: true)]
            )
        ]

        XCTAssertEqual(
            initial,
            WorkoutWarmStartSourceSignature.make(
                revision: 7,
                splitSignatures: splitSignatures,
                workoutSignatures: [WorkoutWarmStartSourceSignature.workout(session)]
            )
        )
        XCTAssertNotEqual(
            initial,
            WorkoutWarmStartSourceSignature.make(
                revision: 8,
                splitSignatures: splitSignatures,
                workoutSignatures: workoutSignatures
            )
        )

        session.exerciseLogs[0].setLogs[0].completed = false
        XCTAssertEqual(initial, WorkoutWarmStartSourceSignature.make(
            revision: 7,
            splitSignatures: splitSignatures,
            workoutSignatures: [WorkoutWarmStartSourceSignature.workout(session)]
        ))

        session.durationSeconds = 2_760
        XCTAssertNotEqual(
            initial,
            WorkoutWarmStartSourceSignature.make(
                revision: 7,
                splitSignatures: splitSignatures,
                workoutSignatures: [WorkoutWarmStartSourceSignature.workout(session)]
            )
        )
    }

    func testWorkoutWarmStartInvalidationAdvancesForCompletionAndEdits() {
        let invalidation = WorkoutWarmStartInvalidation.shared
        let initialRevision = invalidation.revision

        invalidation.invalidate(reason: .workoutCompleted)
        XCTAssertEqual(invalidation.revision, initialRevision + 1)

        invalidation.invalidate(reason: .completedWorkoutSetEdited)
        XCTAssertEqual(invalidation.revision, initialRevision + 2)

        invalidation.invalidate(reason: .completedWorkoutEdited)
        XCTAssertEqual(invalidation.revision, initialRevision + 3)
    }

    func testSavedFoodPreparedRouteRetainsItsExactCatalogGeneration() throws {
        let store = SavedFoodWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let apple = FoodItem(name: "Apple", caloriesPer100g: 52)
        let firstCatalog = SavedFoodCatalogSnapshot(foods: [SavedFoodSnapshot(apple)])
        store.update(firstCatalog)
        let firstRoute = try XCTUnwrap(store.preparedRoute())

        apple.name = "Green Apple"
        apple.updatedAt = apple.updatedAt.addingTimeInterval(1)
        store.update(SavedFoodCatalogSnapshot(foods: [SavedFoodSnapshot(apple)]))

        XCTAssertEqual(store.snapshot(for: firstRoute)?.foods.map(\.name), ["Apple"])
        XCTAssertEqual(store.catalog?.foods.map(\.name), ["Green Apple"])
    }

    func testPreviewWarmCacheMatchesSplitContentAndMode() {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let split = previewSplit(name: "Upper", exerciseName: "Incline Chest Press")
        let snapshots = WorkoutMode.allCases.map {
            WorkoutPreviewWarmSnapshot.fallback(split: split, mode: $0)
        }
        store.replaceActiveSnapshots(snapshots)

        for mode in WorkoutMode.allCases {
            XCTAssertEqual(store.snapshot(for: split, mode: mode)?.mode, mode)
        }

        let renamed = WorkoutPreviewSplit(id: split.id, name: "Upper A", exercises: split.exercises)
        XCTAssertNotNil(store.snapshot(for: renamed, mode: .full))

        let changed = previewSplit(id: split.id, name: split.name, exerciseName: "Shoulder Press")
        XCTAssertNil(store.snapshot(for: changed, mode: .full))
    }

    func testPreviewFallbackCacheEvictsLeastRecentEntry() {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let first = previewSplit(name: "Custom 0", exerciseName: "Exercise 0")
        store.insertFallback(.fallback(split: first, mode: .full))

        for index in 1...8 {
            let split = previewSplit(name: "Custom \(index)", exerciseName: "Exercise \(index)")
            store.insertFallback(.fallback(split: split, mode: .full))
        }

        XCTAssertEqual(store.cachedSnapshotCountForTesting, 8)
        XCTAssertNil(store.snapshot(for: first, mode: .full))
    }

    func testPreparedPreviewRouteContainsEveryModeAndKeepsItsGenerationStable() {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let split = previewSplit(name: "Upper", exerciseName: "Incline Chest Press")
        store.replaceActiveSnapshots(
            WorkoutMode.allCases.map { .fallback(split: split, mode: $0) }
        )

        let route = store.prepareRoute(for: split, initialMode: .recovery)
        let original = store.snapshot(for: route, mode: .full)

        for mode in WorkoutMode.allCases {
            XCTAssertEqual(store.snapshot(for: route, mode: mode)?.mode, mode)
        }

        let replacement = snapshot(
            replacingSourceSignatureOf: .fallback(split: split, mode: .full),
            with: "new-generation"
        )
        store.upsert(replacement)

        XCTAssertEqual(store.snapshot(for: route, mode: .full)?.sourceSignature, original?.sourceSignature)
        XCTAssertNotEqual(store.snapshot(for: split, mode: .full)?.sourceSignature, original?.sourceSignature)
    }

    func testPreviewCachePublicationWaitsUntilMountedRouteDismisses() {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let split = previewSplit(name: "Upper", exerciseName: "Incline Chest Press")
        store.replaceActiveSnapshots(
            WorkoutMode.allCases.map { .fallback(split: split, mode: $0) }
        )
        let route = store.prepareRoute(for: split, initialMode: .full)
        let originalSignature = store.snapshot(for: split, mode: .full)?.sourceSignature
        let replacement = snapshot(
            replacingSourceSignatureOf: .fallback(split: split, mode: .full),
            with: "deferred-generation"
        )

        store.routeDidMount(route)
        store.upsert(replacement)

        XCTAssertEqual(store.snapshot(for: split, mode: .full)?.sourceSignature, originalSignature)
        XCTAssertEqual(store.snapshot(for: route, mode: .full)?.sourceSignature, originalSignature)

        store.routeDidDismiss(route)

        XCTAssertEqual(store.snapshot(for: split, mode: .full)?.sourceSignature, "deferred-generation")
        XCTAssertEqual(store.snapshot(for: route, mode: .full)?.sourceSignature, originalSignature)
    }

    func testPreviewSnapshotBuilderPreservesEveryModeOrderTargetsAndCandidateOrdering() throws {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let inclinePress = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Incline Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            movementPattern: .push,
            equipment: .machine,
            isCompound: true
        )
        let chestPress = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            equipment: .machine,
            isCompound: true
        )
        let benchPress = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            equipment: .barbell,
            isCompound: true
        )
        let chestFly = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            name: "Chest Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            movementPattern: .isolation,
            equipment: .machine,
            isCompound: false
        )
        let shoulderPress = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            name: "Dumbbell Shoulder Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            equipment: .dumbbell,
            isCompound: true
        )
        let lateralRaise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
            name: "Cable Lateral Raise",
            primaryMuscleGroup: .shoulders,
            movementPattern: .isolation,
            equipment: .cable,
            isCompound: false
        )
        let tricepsPushdown = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
            name: "Triceps Pushdown",
            primaryMuscleGroup: .triceps,
            movementPattern: .isolation,
            equipment: .cable,
            isCompound: false
        )
        let core = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!,
            name: "Abdominal Crunch",
            primaryMuscleGroup: .core,
            movementPattern: .core,
            equipment: .machine,
            isCompound: false
        )
        let exercises = [
            inclinePress,
            chestPress,
            benchPress,
            chestFly,
            shoulderPress,
            lateralRaise,
            tricepsPushdown,
            core
        ]

        let splitID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let splitExerciseInputs: [(Exercise, Int, Int)] = [
            (inclinePress, 6, 10),
            (shoulderPress, 8, 12),
            (lateralRaise, 10, 15),
            (tricepsPushdown, 8, 12),
            (benchPress, 5, 8),
            (chestFly, 10, 15)
        ]
        let splitExercises = splitExerciseInputs.enumerated().map { index, input in
            SplitExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 301 + index))!,
                splitId: splitID,
                exerciseId: input.0.id,
                exerciseNameSnapshot: input.0.name,
                orderIndex: index,
                targetSets: 3,
                minReps: input.1,
                maxReps: input.2
            )
        }
        let split = TrainingSplit(
            id: splitID,
            name: "Push",
            splitType: .custom,
            isActive: true,
            activeRotationIndex: 0,
            daysPerWeek: 1,
            exercises: splitExercises
        )
        splitExercises.forEach { $0.split = split }

        let completedWorkout = workoutSession(
            splitID: splitID,
            exerciseSets: [
                (inclinePress, [(60, 10), (60, 10), (60, 10)]),
                (shoulderPress, [(20, 10), (20, 9), (20, 8)]),
                (chestPress, [(50, 8)])
            ]
        )
        let completedModels = [completedWorkout]
        let completedSnapshots = completedModels.map(WorkoutAnalyticsSession.init)
        let splitSnapshots = [TrainingSplitSnapshot(split: split)]
        let coachSnapshot = CoachIntelligenceService.emptySnapshot()

        let snapshots = WorkoutPreviewSnapshotBuilder.build(
            activeSplits: [split],
            splitSnapshots: splitSnapshots,
            completedSessions: completedSnapshots,
            completedWorkoutModels: completedModels,
            exercises: exercises,
            sourceSignature: "preview-builder-parity",
            coachSnapshot: coachSnapshot
        )
        let snapshotsByMode = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.mode, $0) }
        )

        XCTAssertEqual(snapshots.count, WorkoutMode.allCases.count)
        XCTAssertEqual(Set(snapshots.map(\.mode)), Set(WorkoutMode.allCases))

        var legacyOrderedExercises = WorkoutPreviewSplit(split).exercises
        legacyOrderedExercises.append(
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
        let planner = WorkoutModePlanner()
        let targetService = TargetSuggestionService()
        let substitutionService = ExerciseSubstitutionService()

        for mode in WorkoutMode.allCases {
            let snapshot = try XCTUnwrap(snapshotsByMode[mode])
            let expectedPlan = planner.plannedExercises(from: legacyOrderedExercises, mode: mode)

            XCTAssertEqual(snapshot.orderedExercises, legacyOrderedExercises, "Ordered split input changed for \(mode)")
            XCTAssertEqual(snapshot.selectedExerciseIDs, expectedPlan.map(\.id), "Selected order changed for \(mode)")
            XCTAssertEqual(snapshot.plannedExercises, expectedPlan, "Planned order changed for \(mode)")

            for planned in expectedPlan {
                let baseTarget = targetService.suggestion(
                    exerciseId: planned.exerciseId,
                    exerciseName: planned.exerciseNameSnapshot,
                    minReps: planned.minReps,
                    maxReps: planned.maxReps,
                    completedSessions: completedSnapshots
                )
                let expectedTarget = planner.modeAdjustedSuggestion(baseTarget, mode: mode, trainingCall: snapshot.trainingCall)
                XCTAssertEqual(snapshot.suggestions[planned.id], expectedTarget, "Target changed for \(planned.name) in \(mode)")

                let expectedCandidates = substitutionService.candidates(
                    for: planned.exerciseId,
                    in: exercises,
                    completedSessions: completedModels,
                    reason: nil
                )
                XCTAssertEqual(
                    snapshot.substitutionCandidates[planned.id] ?? [],
                    expectedCandidates,
                    "Candidate ranking changed for \(planned.name) in \(mode)"
                )
                XCTAssertEqual(
                    snapshot.alternatives[planned.id]?.map(\.id) ?? [],
                    expectedCandidates.map(\.exerciseId),
                    "Alternative order changed for \(planned.name) in \(mode)"
                )
            }
        }

        let fullSnapshot = try XCTUnwrap(snapshotsByMode[.full])
        let inclinePlan = try XCTUnwrap(fullSnapshot.plannedExercises.first { $0.exerciseId == inclinePress.id })
        XCTAssertTrue(fullSnapshot.trainingCall.isConservative)
        XCTAssertEqual(fullSnapshot.suggestions[inclinePlan.id]?.recommendationType, .repeatTarget)
        XCTAssertEqual(fullSnapshot.suggestions[inclinePlan.id]?.suggestedWeight, 60)
        XCTAssertEqual(
            fullSnapshot.substitutionCandidates[inclinePlan.id]?.map(\.exerciseId),
            [chestPress.id, benchPress.id, chestFly.id, shoulderPress.id, core.id]
        )

        let recoverySnapshot = try XCTUnwrap(snapshotsByMode[.recovery])
        XCTAssertEqual(recoverySnapshot.suggestions[inclinePlan.id]?.recommendationType, .repeatTarget)
        XCTAssertEqual(recoverySnapshot.suggestions[inclinePlan.id]?.suggestedWeight, 60)
    }

    private func snapshot(
        replacingSourceSignatureOf base: WorkoutPreviewPreparedSnapshot,
        with sourceSignature: String
    ) -> WorkoutPreviewPreparedSnapshot {
        WorkoutPreviewPreparedSnapshot(
            splitID: base.splitID,
            splitSignature: base.splitSignature,
            sourceSignature: sourceSignature,
            mode: base.mode,
            selectedExerciseIDs: base.selectedExerciseIDs,
            orderedExercises: base.orderedExercises,
            exerciseOptions: base.exerciseOptions,
            addableExercises: base.addableExercises,
            coreExercise: base.coreExercise,
            basePlannedExercises: base.basePlannedExercises,
            plannedExercises: base.plannedExercises,
            estimatedDuration: base.estimatedDuration,
            durationCalibration: base.durationCalibration,
            suggestions: base.suggestions,
            alternatives: base.alternatives,
            substitutionCandidates: base.substitutionCandidates,
            intelligence: base.intelligence,
            plannedFatigueItems: base.plannedFatigueItems,
            actionRecommendations: base.actionRecommendations,
            actionPreviews: base.actionPreviews,
            trainingCall: base.trainingCall,
            coachSummaryText: base.coachSummaryText,
            coachSummaryBadge: base.coachSummaryBadge,
            preparedAt: base.preparedAt
        )
    }

    func testDailyCheckInDraftCopiesOnlyImmutableValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_721_411_200)
        let model = DailyCoachCheckIn(
            id: id,
            date: date,
            energy: 5,
            soreness: 2,
            stress: 1,
            motivation: 4,
            note: "Ready",
            createdAt: date,
            updatedAt: date
        )
        let snapshot = DailyCoachCheckInSnapshot(model)

        let draft = DailyCheckInDraft(existingCheckIn: snapshot)

        XCTAssertEqual(draft.existingCheckInID, id)
        XCTAssertEqual(draft.energy, 5)
        XCTAssertEqual(draft.soreness, 2)
        XCTAssertEqual(draft.stress, 1)
        XCTAssertEqual(draft.motivation, 4)
        XCTAssertEqual(draft.note, "Ready")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarmStartSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func previewSplit(
        id: UUID = UUID(),
        name: String,
        exerciseName: String
    ) -> WorkoutPreviewSplit {
        WorkoutPreviewSplit(
            id: id,
            name: name,
            exercises: [
                WorkoutSelectableExercise(
                    id: UUID(),
                    exerciseId: UUID(),
                    name: exerciseName,
                    targetSets: 3,
                    minReps: 6,
                    maxReps: 10,
                    notes: nil
                )
            ]
        )
    }

    private func workoutSession(
        splitID: UUID,
        exerciseSets: [(Exercise, [(Double, Int)])]
    ) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: 1_786_000_000)
        let session = WorkoutSession(
            date: date,
            splitId: splitID,
            splitNameSnapshot: "Push",
            endedAt: date.addingTimeInterval(3_600),
            completed: true
        )
        session.exerciseLogs = exerciseSets.enumerated().map { exerciseIndex, input in
            let exercise = input.0
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: exerciseIndex,
                targetSets: input.1.count,
                minReps: 1,
                maxReps: 20
            )
            log.workoutSession = session
            log.setLogs = input.1.enumerated().map { setIndex, values in
                let set = SetLog(
                    exerciseLogId: log.id,
                    setNumber: setIndex + 1,
                    weight: values.0,
                    reps: values.1,
                    completed: true
                )
                set.exerciseLog = log
                return set
            }
            return log
        }
        return session
    }
}

private struct TestWarmStartPayload: Codable, Equatable {
    let title: String
    let count: Int
}
