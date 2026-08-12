import XCTest
@testable import GymTracker

@MainActor
final class WorkoutReliabilityTests: XCTestCase {
    private let exerciseId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    override func tearDown() {
        NavigationInteraction.resetForTesting()
        super.tearDown()
    }

    func testPeaklineTextUsesConsistentPluralRangesAndLoadNotation() {
        XCTAssertEqual(PeaklineText.count(1, singular: "set"), "1 set")
        XCTAssertEqual(PeaklineText.count(2, singular: "set"), "2 sets")
        XCTAssertEqual(PeaklineText.count(1, singular: "working set"), "1 working set")
        XCTAssertEqual(PeaklineText.setRepSummary(sets: 1, minimumReps: 8, maximumReps: 12), "1 set · 8–12 reps")
        XCTAssertEqual(PeaklineText.setRepSummary(sets: 3, minimumReps: 8, maximumReps: 8), "3 sets · 8 reps")
        XCTAssertEqual(PeaklineText.loadReps(weight: "60", reps: 8), "60 kg × 8")
    }

    func testHydrationFormattingUsesReadableUnitSpacing() {
        XCTAssertEqual(HydrationService.formatAmount(350), "350 mL")
        XCTAssertEqual(HydrationService.formatAmount(1_000), "1 L")
        XCTAssertEqual(HydrationService.formatAmount(2_500), "2.5 L")
    }

    func testNavigationInteractionDeduplicatesUntilDestinationAppears() {
        var routeMutations = 0

        XCTAssertTrue(
            NavigationInteraction.perform(
                key: "test.preview",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )
        XCTAssertFalse(
            NavigationInteraction.perform(
                key: "test.preview",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )
        XCTAssertEqual(routeMutations, 1)

        NavigationInteraction.destinationDidAppear(key: "test.preview")

        XCTAssertTrue(
            NavigationInteraction.perform(
                key: "test.preview",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )
        XCTAssertEqual(routeMutations, 2)
    }

    func testNavigationInteractionRecoversWhenDestinationNeverAppears() async {
        var routeMutations = 0

        XCTAssertTrue(
            NavigationInteraction.perform(
                key: "test.timeout",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )
        XCTAssertFalse(
            NavigationInteraction.perform(
                key: "test.timeout",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )

        try? await Task.sleep(nanoseconds: 1_100_000_000)

        XCTAssertTrue(
            NavigationInteraction.perform(
                key: "test.timeout",
                destinationClass: .warm,
                haptic: .none
            ) {
                routeMutations += 1
            }
        )
        XCTAssertEqual(routeMutations, 2)
    }

    func testProgressAnalyticsInputSignatureTracksScalarChangesWithoutWalkingNestedSets() {
        let session = WorkoutSession(
            date: date(day: 8, hour: 12),
            splitNameSnapshot: "Push",
            durationSeconds: 3_600,
            perceivedDifficulty: 3,
            completed: true
        )
        let exerciseID = UUID()
        let base = ProgressAnalyticsInputSignature(
            sessions: [session],
            exerciseIDs: [exerciseID],
            activeSplitNames: ["Push"]
        )

        session.durationSeconds = 3_900
        XCTAssertNotEqual(base, ProgressAnalyticsInputSignature(
            sessions: [session],
            exerciseIDs: [exerciseID],
            activeSplitNames: ["Push"]
        ))

        session.durationSeconds = 3_600
        session.perceivedDifficulty = 5
        XCTAssertNotEqual(base, ProgressAnalyticsInputSignature(
            sessions: [session],
            exerciseIDs: [exerciseID],
            activeSplitNames: ["Push"]
        ))

        session.perceivedDifficulty = 3
        let log = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: exerciseID,
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0,
            setLogs: [SetLog(setNumber: 1, weight: 100, reps: 8, completed: true)]
        )
        session.exerciseLogs = [log]
        let nestedBase = ProgressAnalyticsInputSignature(
            sessions: [session],
            exerciseIDs: [exerciseID],
            activeSplitNames: ["Push"]
        )
        log.setLogs[0].weight = 105

        XCTAssertEqual(nestedBase, ProgressAnalyticsInputSignature(
            sessions: [session],
            exerciseIDs: [exerciseID],
            activeSplitNames: ["Push"]
        ))
    }

    func testWorkoutLaunchDraftCopiesValuesAndCreatesOrderedSession() {
        let splitID = UUID()
        let exercises = [
            PlannedWorkoutExercise(
                id: UUID(),
                exerciseId: UUID(),
                name: "Incline Chest Press",
                targetSets: 3,
                minReps: 6,
                maxReps: 10,
                notes: "Controlled"
            ),
            PlannedWorkoutExercise(
                id: UUID(),
                exerciseId: UUID(),
                name: "Chest Fly",
                targetSets: 2,
                minReps: 8,
                maxReps: 12,
                notes: nil
            )
        ]
        let draft = WorkoutLaunchDraft(
            splitId: splitID,
            splitName: "Upper",
            modeLabel: WorkoutMode.full.displayName,
            exercises: exercises
        )

        XCTAssertEqual(draft.splitId, splitID)
        XCTAssertEqual(draft.splitNameSnapshot, "Upper - Full")
        XCTAssertEqual(draft.exercises.map(\.orderIndex), [0, 1])

        let startedAt = Date(timeIntervalSince1970: 1_721_411_200)
        let session = draft.makeSession(startedAt: startedAt)

        XCTAssertEqual(session.splitId, splitID)
        XCTAssertEqual(session.startedAt, startedAt)
        XCTAssertEqual(session.exerciseLogs.map(\.exerciseNameSnapshot), ["Incline Chest Press", "Chest Fly"])
        XCTAssertEqual(session.exerciseLogs.map(\.orderIndex), [0, 1])
        XCTAssertTrue(session.exerciseLogs.allSatisfy { $0.workoutSession === session })
    }

    func testWorkoutPreviewOrderReducerMovesFirstDownAndLaterExerciseUp() {
        let first = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let third = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let fourth = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let original = [first, second, third, fourth]

        XCTAssertEqual(
            WorkoutPreviewOrderReducer.move(original, sourceID: first, destinationID: third),
            [second, third, first, fourth]
        )
        XCTAssertEqual(
            WorkoutPreviewOrderReducer.move(original, sourceID: fourth, destinationID: second),
            [first, fourth, second, third]
        )
    }

    func testWorkoutPreviewOrderReducerHandlesAdjacentMovesNoOpsAndInvariants() {
        let first = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let third = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let fourth = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        let missing = UUID(uuidString: "20000000-0000-0000-0000-000000000099")!
        let original = [first, second, third, fourth]

        let adjacentDown = WorkoutPreviewOrderReducer.move(original, sourceID: second, destinationID: third)
        let adjacentUp = WorkoutPreviewOrderReducer.move(original, sourceID: third, destinationID: second)

        XCTAssertEqual(adjacentDown, [first, third, second, fourth])
        XCTAssertEqual(adjacentUp, [first, third, second, fourth])
        XCTAssertEqual(WorkoutPreviewOrderReducer.move(original, sourceID: second, destinationID: second), original)
        XCTAssertEqual(WorkoutPreviewOrderReducer.move(original, sourceID: missing, destinationID: second), original)
        XCTAssertEqual(WorkoutPreviewOrderReducer.move(original, sourceID: second, destinationID: missing), original)
        XCTAssertEqual(adjacentDown.count, original.count)
        XCTAssertEqual(Set(adjacentDown), Set(original))
        XCTAssertEqual(
            adjacentDown.filter { $0 != second },
            original.filter { $0 != second },
            "Moving one ID must preserve every other ID's relative order"
        )
    }

    func testWorkoutLaunchDraftUsesReducerOrderForLoggerExerciseLogs() {
        let exercises = [
            PlannedWorkoutExercise(id: UUID(), exerciseId: UUID(), name: "First", targetSets: 2, minReps: 6, maxReps: 10, notes: nil),
            PlannedWorkoutExercise(id: UUID(), exerciseId: UUID(), name: "Second", targetSets: 2, minReps: 8, maxReps: 12, notes: nil),
            PlannedWorkoutExercise(id: UUID(), exerciseId: UUID(), name: "Third", targetSets: 2, minReps: 10, maxReps: 15, notes: nil)
        ]
        let originalIDs = exercises.map(\.id)
        let reorderedIDs = WorkoutPreviewOrderReducer.move(
            originalIDs,
            sourceID: originalIDs[2],
            destinationID: originalIDs[0]
        )
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let reorderedExercises = reorderedIDs.compactMap { exercisesByID[$0] }
        let draft = WorkoutLaunchDraft(
            splitId: UUID(),
            splitName: "Fixture",
            modeLabel: WorkoutMode.full.displayName,
            exercises: reorderedExercises
        )

        XCTAssertEqual(draft.exercises.map(\.name), ["Third", "First", "Second"])

        let session = draft.makeSession(startedAt: Date(timeIntervalSince1970: 1_722_000_000))
        XCTAssertEqual(session.exerciseLogs.map(\.exerciseNameSnapshot), ["Third", "First", "Second"])
        XCTAssertEqual(session.exerciseLogs.map(\.orderIndex), [0, 1, 2])
    }

    func testLocalWorkoutPreviewReorderLeavesPreparedRouteSnapshotUnchanged() throws {
        let store = WorkoutPreviewWarmStartStore.shared
        store.resetForTesting()
        defer { store.resetForTesting() }

        let exercises = [
            WorkoutSelectableExercise(id: UUID(), exerciseId: UUID(), name: "First", targetSets: 2, minReps: 6, maxReps: 10, notes: nil),
            WorkoutSelectableExercise(id: UUID(), exerciseId: UUID(), name: "Second", targetSets: 2, minReps: 8, maxReps: 12, notes: nil),
            WorkoutSelectableExercise(id: UUID(), exerciseId: UUID(), name: "Third", targetSets: 2, minReps: 10, maxReps: 15, notes: nil)
        ]
        let split = WorkoutPreviewSplit(id: UUID(), name: "Fixture", exercises: exercises)
        store.replaceActiveSnapshots(WorkoutMode.allCases.map { .fallback(split: split, mode: $0) })
        let route = store.prepareRoute(for: split, initialMode: .full)
        let before = try XCTUnwrap(store.snapshot(for: route, mode: .full))

        let localIDs = WorkoutPreviewOrderReducer.move(
            before.selectedExerciseIDs,
            sourceID: exercises[2].id,
            destinationID: exercises[0].id
        )
        let after = try XCTUnwrap(store.snapshot(for: route, mode: .full))

        XCTAssertNotEqual(localIDs, before.selectedExerciseIDs)
        XCTAssertEqual(after.selectedExerciseIDs, before.selectedExerciseIDs)
        XCTAssertEqual(after.plannedExercises.map(\.id), before.plannedExercises.map(\.id))
        XCTAssertEqual(after.sourceSignature, before.sourceSignature)
    }

    func testWorkoutMotivationCatalogIsLargeUniqueAndComplete() {
        let messages = WorkoutMotivationCatalog.messages

        XCTAssertGreaterThanOrEqual(messages.count, 24)
        XCTAssertEqual(Set(messages.map(\.id)).count, messages.count)
        XCTAssertEqual(Set(messages.map { "\($0.title)|\($0.detail)" }).count, messages.count)
        XCTAssertTrue(messages.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    func testWorkoutMotivationRotationIsDeterministicForSameSessionSeed() {
        let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        var firstRotation = WorkoutMotivationRotation(sessionID: sessionID)
        var secondRotation = WorkoutMotivationRotation(sessionID: sessionID)

        let firstSequence = (0..<56).map { _ in firstRotation.next().id }
        let secondSequence = (0..<56).map { _ in secondRotation.next().id }

        XCTAssertEqual(firstSequence, secondSequence)
    }

    func testWorkoutMotivationRotationUsesEveryMessageBeforeReuseAndAvoidsRolloverRepeat() {
        let messages = WorkoutMotivationCatalog.messages
        var rotation = WorkoutMotivationRotation(
            sessionID: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        )
        let sequence = (0..<(messages.count * 2)).map { _ in rotation.next().id }

        XCTAssertEqual(Set(sequence.prefix(messages.count)).count, messages.count)
        XCTAssertEqual(Set(sequence.suffix(messages.count)).count, messages.count)
        XCTAssertEqual(Set(sequence.prefix(messages.count)), Set(messages.map(\.id)))
        for (current, next) in zip(sequence, sequence.dropFirst()) {
            XCTAssertNotEqual(current, next)
        }
    }

    func testWorkoutCompletionCopyIsSeparateFromTransitionCatalog() {
        let transitionPairs = Set(
            WorkoutMotivationCatalog.messages.map { "\($0.title)|\($0.detail)" }
        )

        for rating in WorkoutRating.options {
            XCTAssertFalse(
                transitionPairs.contains("\(rating.completionTitle)|\(rating.completionMessage)")
            )
        }
    }

    func testStandardWorkoutCompletionPresentationPreservesRatingCopy() throws {
        let rating = try XCTUnwrap(WorkoutRating.options.first { $0.id == 3 })

        let presentation = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "42m",
            prs: []
        )

        XCTAssertEqual(presentation.style, .completedWorkout)
        XCTAssertEqual(presentation.title, rating.completionTitle)
        XCTAssertEqual(presentation.systemImage, rating.systemImage)
        XCTAssertEqual(presentation.primaryActionTitle, "Done")
        XCTAssertEqual(
            presentation.message,
            "\(rating.completionMessage) You spent 42m in the gym."
        )
    }

    func testSinglePRWorkoutCompletionPresentationUsesSingularCopy() throws {
        let rating = try XCTUnwrap(WorkoutRating.options.first { $0.id == 4 })
        let exerciseLogID = UUID()

        let presentation = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "58m",
            prs: [prRecord(index: 1, exerciseLogID: exerciseLogID, exerciseName: "Bench Press")]
        )

        XCTAssertEqual(presentation.style, .pr)
        XCTAssertEqual(presentation.title, "New best unlocked.")
        XCTAssertEqual(presentation.systemImage, "trophy.fill")
        XCTAssertTrue(presentation.message.hasPrefix("1 PR on Bench Press."))
        XCTAssertTrue(presentation.message.contains(rating.completionMessage))
        XCTAssertTrue(presentation.message.hasSuffix("You spent 58m in the gym."))
    }

    func testMultiplePRsOnOneExerciseUseExerciseName() throws {
        let rating = try XCTUnwrap(WorkoutRating.options.first { $0.id == 5 })
        let exerciseLogID = UUID()
        let prs = [
            prRecord(index: 1, exerciseLogID: exerciseLogID, exerciseName: "Bench Press"),
            prRecord(index: 2, exerciseLogID: exerciseLogID, exerciseName: "Bench Press")
        ]

        let presentation = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "1h 04m",
            prs: prs
        )

        XCTAssertEqual(presentation.style, .pr)
        XCTAssertEqual(presentation.title, "New bests unlocked.")
        XCTAssertTrue(presentation.message.hasPrefix("2 PRs on Bench Press."))
    }

    func testPRsAcrossExercisesUseDistinctExerciseCount() throws {
        let rating = try XCTUnwrap(WorkoutRating.options.first { $0.id == 5 })
        let benchLogID = UUID()
        let rowLogID = UUID()
        let prs = [
            prRecord(index: 1, exerciseLogID: benchLogID, exerciseName: "Bench Press"),
            prRecord(index: 2, exerciseLogID: benchLogID, exerciseName: "Bench Press"),
            prRecord(index: 3, exerciseLogID: rowLogID, exerciseName: "Seated Row")
        ]

        let presentation = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "1h 12m",
            prs: prs
        )

        XCTAssertEqual(presentation.style, .pr)
        XCTAssertTrue(presentation.message.hasPrefix("3 PRs across 2 exercises."))
    }

    func testTargetSuggestionCoversBaselineProgressionAndFatigueRisk() {
        let service = TargetSuggestionService()

        let baseline = service.suggestion(
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            minReps: 6,
            maxReps: 10,
            completedSessions: [WorkoutAnalyticsSession]()
        )
        XCTAssertEqual(baseline.recommendationType, .baseline)
        XCTAssertEqual(baseline.suggestedReps, 6)
        XCTAssertNil(baseline.suggestedWeight)

        let topRange = service.suggestion(
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            minReps: 6,
            maxReps: 10,
            completedSessions: [
                analyticsSession(day: 3, weight: 100, reps: 10, setCount: 2)
            ]
        )
        XCTAssertEqual(topRange.recommendationType, .increaseLoad)
        XCTAssertEqual(topRange.suggestedWeight, 102.5)
        XCTAssertEqual(topRange.suggestedReps, 6)

        let fatigueRisk = service.suggestion(
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            minReps: 6,
            maxReps: 10,
            completedSessions: [
                analyticsSession(day: 3, weight: 90, reps: 6),
                analyticsSession(day: 2, weight: 95, reps: 6),
                analyticsSession(day: 1, weight: 100, reps: 6)
            ]
        )
        XCTAssertEqual(fatigueRisk.recommendationType, .fatigueRisk)
        XCTAssertEqual(fatigueRisk.suggestedWeight, 90)
        XCTAssertEqual(fatigueRisk.suggestedReps, 6)
    }

    func testWorkoutModePlannerKeepsQuickAndRecoveryPlansPredictable() {
        let planner = WorkoutModePlanner()
        let exercises = (0..<6).map { index in
            WorkoutSelectableExercise(
                id: UUID(),
                exerciseId: UUID(),
                name: "Exercise \(index)",
                targetSets: index == 0 ? 1 : 4,
                minReps: 6,
                maxReps: 10,
                notes: nil
            )
        }

        let quick = planner.plannedExercises(from: exercises, mode: .quick)
        XCTAssertEqual(quick.count, 4)
        XCTAssertEqual(quick.map(\.targetSets), [2, 3, 3, 3])

        let recovery = planner.plannedExercises(from: exercises, mode: .recovery)
        XCTAssertEqual(recovery.count, exercises.count)
        XCTAssertEqual(recovery.map(\.targetSets), [1, 3, 3, 3, 3, 3])

        let adjusted = planner.modeAdjustedSuggestion(
            TargetSuggestion(
                exerciseName: "Bench Press",
                lastBestSetDescription: "100kg x 10",
                lastBestWeight: 100,
                lastBestReps: 10,
                suggestedWeight: 102.5,
                suggestedReps: 6,
                recommendationType: .increaseLoad,
                reason: "Ready to progress.",
                confidence: 0.9
            ),
            mode: .recovery
        )
        XCTAssertEqual(adjusted.recommendationType, TargetRecommendationType.repeatTarget)
        XCTAssertEqual(adjusted.suggestedWeight, 100)
        XCTAssertEqual(adjusted.suggestedReps, 10)
        XCTAssertLessThanOrEqual(adjusted.confidence, 0.7)
    }

    func testWorkoutDurationEstimateUsesPersonalSameModeMedianAndIgnoresOutliers() {
        let now = date(day: 20, hour: 12)
        let calibration = WorkoutDurationCalibration(samples: [
            WorkoutDurationSample(date: date(day: 19, hour: 12), splitName: "Lower", mode: .quick, durationSeconds: 3_600, completedWorkingSetCount: 12),
            WorkoutDurationSample(date: date(day: 18, hour: 12), splitName: "Lower", mode: .quick, durationSeconds: 3_300, completedWorkingSetCount: 11),
            WorkoutDurationSample(date: date(day: 17, hour: 12), splitName: "Lower", mode: .quick, durationSeconds: 3_900, completedWorkingSetCount: 13),
            WorkoutDurationSample(date: date(day: 16, hour: 12), splitName: "Lower", mode: .quick, durationSeconds: 9 * 3_600, completedWorkingSetCount: 12),
            WorkoutDurationSample(date: date(day: 15, hour: 12), splitName: "Push", mode: .full, durationSeconds: 7_200, completedWorkingSetCount: 12)
        ])
        let exercises = (0..<4).map { index in
            PlannedWorkoutExercise(
                id: UUID(),
                exerciseId: UUID(),
                name: "Exercise \(index)",
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                notes: nil
            )
        }

        let estimate = WorkoutModePlanner().estimatedDurationMinutes(
            for: exercises,
            mode: .quick,
            calibration: calibration,
            splitName: "Lower",
            now: now
        )

        XCTAssertEqual(estimate, 50...70)
    }

    func testWorkoutDurationEstimateUsesConservativeModeFallbacksWhenHistoryIsSparse() {
        let exercises = (0..<4).map { index in
            PlannedWorkoutExercise(
                id: UUID(),
                exerciseId: UUID(),
                name: "Exercise \(index)",
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                notes: nil
            )
        }

        XCTAssertEqual(
            WorkoutModePlanner().estimatedDurationMinutes(for: exercises, mode: .quick),
            50...70
        )
        XCTAssertEqual(
            WorkoutModePlanner().estimatedDurationMinutes(for: exercises, mode: .recovery),
            45...65
        )
    }

    func testCanonicalDailyRecommendationKeepsCoachAndTargetsOnSameSplit() throws {
        let pushExerciseId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let pullExerciseId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let legsExerciseId = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let splits = [
            splitSnapshot(name: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press"),
            splitSnapshot(name: "Pull", exerciseId: pullExerciseId, exerciseName: "Lat Pulldown"),
            splitSnapshot(name: "Legs", exerciseId: legsExerciseId, exerciseName: "Quad Extension")
        ]
        let sessions = [
            analyticsSession(day: 25, splitName: "Pull", exerciseId: pullExerciseId, exerciseName: "Lat Pulldown", weight: 95, reps: 9),
            analyticsSession(day: 24, splitName: "Legs", exerciseId: legsExerciseId, exerciseName: "Quad Extension", weight: 113, reps: 12),
            analyticsSession(day: 10, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 100, reps: 8)
        ]

        let decision = TrainingDecisionService().decision(activeSplits: splits, completedSessions: sessions)
        let summary = CoachRecommendationEngine().makeSummary(activeSplits: splits, completedSessions: sessions, now: date(day: 26, hour: 12))
        let targetSplit = try XCTUnwrap(splits.first { $0.name == decision.recommendedSplitName })
        let target = try XCTUnwrap(targetSplit.exercises.first)
        let suggestion = TargetSuggestionService().suggestion(
            exerciseId: target.exerciseId,
            exerciseName: target.exerciseNameSnapshot,
            minReps: target.minReps,
            maxReps: target.maxReps,
            completedSessions: sessions
        )

        XCTAssertEqual(decision.recommendedSplitName, "Legs")
        XCTAssertEqual(summary.recommendedSplitName, "Legs")
        XCTAssertEqual(summary.trainingDecision.recommendedSplitName, "Legs")
        XCTAssertEqual(suggestion.exerciseName, "Quad Extension")
        XCTAssertFalse(summary.exerciseRecommendations.contains { $0.exerciseName == "Bench Press" })

        let call = TrainingCallSnapshotBuilder().make(
            decision: decision,
            activeSplits: splits,
            completedSessions: sessions
        )

        XCTAssertEqual(call.recommendedSplitName, "Legs")
        XCTAssertTrue(call.sourceSignals.contains(decision.reason))
        XCTAssertEqual(call.confidence, .medium)
    }

    func testTrainingCallSnapshotDowngradesLowConfidenceProgression() {
        let pushExerciseId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let splits = [
            splitSnapshot(name: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press")
        ]
        let sessions = [
            analyticsSession(day: 25, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 100, reps: 10),
            analyticsSession(day: 20, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 97.5, reps: 10),
            analyticsSession(day: 15, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 95, reps: 10)
        ]
        let decision = TrainingDecision(
            recommendedSplitName: "Push",
            recommendedMode: .full,
            action: .push,
            title: "Push today",
            reason: "Progression target is available."
        )
        let call = TrainingCallSnapshotBuilder().make(
            decision: decision,
            activeSplits: splits,
            completedSessions: sessions,
            readiness: readiness(confidence: .low, category: .peak, value: 88),
            fatigueRisk: fatigue(level: .low, confidence: .low),
            targetSuggestions: [
                TargetSuggestion(
                    exerciseName: "Bench Press",
                    lastBestSetDescription: "100kg x 10",
                    lastBestWeight: 100,
                    lastBestReps: 10,
                    suggestedWeight: 102.5,
                    suggestedReps: 8,
                    recommendationType: .increaseLoad,
                    reason: "Top of the range is available.",
                    confidence: 0.85
                )
            ]
        )

        XCTAssertEqual(call.action, .repeatTarget)
        XCTAssertEqual(call.recommendedMode, .full)
        XCTAssertTrue(call.isConservative)
        XCTAssertTrue(call.guardrailNotes.contains { $0.localizedCaseInsensitiveContains("low confidence") })
        XCTAssertTrue(call.targetSummary?.localizedCaseInsensitiveContains("repeat") == true)
    }

    func testTrainingCallSnapshotLetsFatigueOverrideLoadPush() {
        let pushExerciseId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let splits = [
            splitSnapshot(name: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press")
        ]
        let sessions = [
            analyticsSession(day: 25, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 100, reps: 10),
            analyticsSession(day: 20, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 97.5, reps: 10),
            analyticsSession(day: 15, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 95, reps: 10)
        ]
        let decision = TrainingDecision(
            recommendedSplitName: "Push",
            recommendedMode: .full,
            action: .push,
            title: "Push today",
            reason: "Progression target is available."
        )
        let call = TrainingCallSnapshotBuilder().make(
            decision: decision,
            activeSplits: splits,
            completedSessions: sessions,
            readiness: readiness(confidence: .high, category: .peak, value: 91),
            fatigueRisk: fatigue(level: .high, confidence: .high),
            targetSuggestions: [
                TargetSuggestion(
                    exerciseName: "Bench Press",
                    lastBestSetDescription: "100kg x 10",
                    lastBestWeight: 100,
                    lastBestReps: 10,
                    suggestedWeight: 102.5,
                    suggestedReps: 8,
                    recommendationType: .increaseLoad,
                    reason: "Top of the range is available.",
                    confidence: 0.85
                )
            ]
        )

        XCTAssertEqual(call.action, .recover)
        XCTAssertEqual(call.recommendedMode, .recovery)
        XCTAssertTrue(call.isConservative)
        XCTAssertTrue(call.guardrailNotes.contains { $0.localizedCaseInsensitiveContains("fatigue") })
    }

    func testWeeklyBalanceDoesNotSilentlyOverridePPLRotation() {
        let pushExerciseId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let pullExerciseId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let legsExerciseId = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let splits = [
            splitSnapshot(name: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press"),
            splitSnapshot(name: "Pull", exerciseId: pullExerciseId, exerciseName: "Lat Pulldown"),
            splitSnapshot(name: "Legs", exerciseId: legsExerciseId, exerciseName: "Quad Extension")
        ]
        let sessions = [
            analyticsSession(day: 25, splitName: "Pull", exerciseId: pullExerciseId, exerciseName: "Lat Pulldown", weight: 95, reps: 9),
            analyticsSession(day: 24, splitName: "Legs", exerciseId: legsExerciseId, exerciseName: "Quad Extension", weight: 113, reps: 12),
            analyticsSession(day: 10, splitName: "Push", exerciseId: pushExerciseId, exerciseName: "Bench Press", weight: 100, reps: 8)
        ]

        let decision = TrainingDecisionService().decision(activeSplits: splits, completedSessions: sessions)
        let weeklyReview = WeeklyReviewBuilder().build(activeSplits: splits, completedSessions: sessions)

        XCTAssertEqual(decision.recommendedSplitName, "Legs")
        XCTAssertEqual(weeklyReview.splitConsistency.missedSplitName, "Push")
        XCTAssertEqual(weeklyReview.nextDecision.recommendedSplitName, "Legs")
    }

    func testSessionSummaryCapturesDurationImprovementsAndNextSplit() throws {
        let previous = workout(
            date: date(day: 1, hour: 12),
            splitName: "Push - Full",
            weight: 90,
            reps: 8,
            durationSeconds: 2_400,
            rating: 3
        )
        let current = workout(
            date: date(day: 8, hour: 12),
            splitName: "Push - Full",
            weight: 100,
            reps: 8,
            durationSeconds: 3_661,
            rating: 4
        )
        let summary = SessionSummaryBuilder().build(
            from: current,
            completedSessions: [current, previous],
            activeSplits: [
                TrainingSplit(name: "Pull", splitType: .pushPullLegs),
                TrainingSplit(name: "Legs", splitType: .pushPullLegs)
            ]
        )

        XCTAssertEqual(summary.durationText, "1h 1m 1s")
        XCTAssertEqual(summary.completedExerciseCount, 1)
        XCTAssertEqual(summary.workingSetCount, 1)
        XCTAssertEqual(summary.ratingText, "Great")
        XCTAssertEqual(summary.suggestedNextSplit, "Pull")
        XCTAssertTrue(try XCTUnwrap(summary.bestSetImprovements.first).contains("improved from 90kg x 8 to 100kg x 8"))
    }

    func testSkippedExerciseReasonIsIdempotentAndDetectsOnlyEmptyPlannedLogs() throws {
        let service = SkippedExerciseReasonService()
        let skipped = exerciseLog(name: "Cable Fly", setLogs: [
            SetLog(setNumber: 1, weight: 0, reps: 0, completed: false)
        ])
        let completed = exerciseLog(name: "Bench Press", setLogs: [
            SetLog(setNumber: 1, weight: 100, reps: 6, completed: true)
        ])
        let session = WorkoutSession(splitNameSnapshot: "Push", completed: false, exerciseLogs: [skipped, completed])

        XCTAssertEqual(service.skippedLogs(in: session).map(\.id), [skipped.id])

        service.append(reason: .equipmentBusy, to: skipped)
        service.append(reason: .equipmentBusy, to: skipped)

        XCTAssertEqual(skipped.notes, "[Skipped: Equipment busy]")
    }

    func testLateNightWorkoutDateUsesActualStartTime() {
        let startedAt = date(day: 8, hour: 23, minute: 45)
        let incorrectDate = date(day: 9, hour: 0, minute: 10)
        let session = WorkoutSession(date: incorrectDate, startedAt: startedAt, completed: true)

        XCTAssertEqual(WorkoutSessionDateService.loggedDate(for: session), startedAt)

        WorkoutSessionDateService.alignLoggedDateToStartDate(session)

        XCTAssertEqual(session.date, startedAt)
    }

    func testHistorySnapshotBuilderFiltersValueDataAndAggregatesCalendarDays() {
        let push = workout(
            date: date(day: 8, hour: 12),
            splitName: "Push - Full",
            weight: 100,
            reps: 8,
            durationSeconds: 3_600,
            rating: 4
        )
        let pull = WorkoutSession(
            date: date(day: 9, hour: 12),
            splitNameSnapshot: "Pull - Full",
            durationSeconds: 2_700,
            perceivedDifficulty: 3,
            completed: true,
            exerciseLogs: [
                ExerciseLog(
                    exerciseId: UUID(),
                    exerciseNameSnapshot: "Lat Pulldown",
                    orderIndex: 0,
                    targetSets: 1,
                    minReps: 8,
                    maxReps: 12,
                    setLogs: [SetLog(setNumber: 1, weight: 80, reps: 10, completed: true)]
                )
            ]
        )
        let snapshots = [HistoryWorkoutSnapshot(push), HistoryWorkoutSnapshot(pull)]

        var filters = HistoryFilters()
        filters.splitName = "Push"
        let display = HistoryDisplaySnapshotBuilder.build(
            workouts: snapshots,
            filters: filters,
            trainingDaysPerWeek: 4,
            now: date(day: 10, hour: 12),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(display.sessionRows.count, 1)
        XCTAssertEqual(display.sessionRows.first?.splitName, "Push - Full")
        XCTAssertEqual(display.calendarDaySummaries.count, 1)
        XCTAssertEqual(display.overview.currentVisitCount, 2)
        XCTAssertEqual(display.overview.monthlyTarget, 18)
        XCTAssertEqual(display.overview.currentDurationText, "1 hr 45 min")
        XCTAssertEqual(display.splitOptions, ["Pull", "Push"])
    }

    func testPRTimelineFilterOptionsUseObservedBaseSplitNamesAndPreserveAll() {
        XCTAssertEqual(
            PRTimelineFilterOptions.options(from: [
                "Push - Full",
                "Lower - Quick",
                "Upper",
                "Custom Circuit - Recovery",
                "upper - Heavy",
                "",
                "   ",
                "All - Full"
            ]),
            ["All", "Custom Circuit", "Lower", "Push", "Upper"]
        )
    }

    func testHistoryMonthlyTargetsRespectCalendarMonthLengthAndMissingGoal() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func target(year: Int, month: Int) -> Int? {
            let now = calendar.date(from: DateComponents(year: year, month: month, day: 10, hour: 12))!
            return HistoryDisplaySnapshotBuilder.build(
                workouts: [],
                trainingDaysPerWeek: 4,
                now: now,
                calendar: calendar
            ).overview.monthlyTarget
        }

        XCTAssertEqual(target(year: 2025, month: 2), 16)
        XCTAssertEqual(target(year: 2024, month: 2), 17)
        XCTAssertEqual(target(year: 2026, month: 4), 17)
        XCTAssertEqual(target(year: 2026, month: 5), 18)

        let missingGoal = HistoryDisplaySnapshotBuilder.build(
            workouts: [],
            now: date(day: 10, hour: 12),
            calendar: calendar
        ).overview
        XCTAssertNil(missingGoal.monthlyTarget)
        XCTAssertNil(missingGoal.goalSourceText)
    }

    func testHistoryCountsMultipleCompletedWorkoutsOnOneDayAsOneVisit() {
        let first = workout(date: date(day: 8, hour: 9), splitName: "Push - Full", weight: 90, reps: 8, durationSeconds: 3_600, rating: 4)
        let second = workout(date: date(day: 8, hour: 18), splitName: "Pull - Quick", weight: 70, reps: 10, durationSeconds: 2_700, rating: 3)
        let overview = HistoryDisplaySnapshotBuilder.build(
            workouts: [HistoryWorkoutSnapshot(first), HistoryWorkoutSnapshot(second)],
            trainingDaysPerWeek: 3,
            now: date(day: 10, hour: 12),
            calendar: Calendar(identifier: .gregorian)
        ).overview

        XCTAssertEqual(overview.currentVisitCount, 1)
        XCTAssertEqual(overview.currentDurationText, "1 hr 45 min")
    }

    func testHistoryEndDateExcludesMidnightAtStartOfFollowingDay() {
        let included = workout(
            date: date(day: 10, hour: 23, minute: 59),
            splitName: "Push",
            weight: 90,
            reps: 8,
            durationSeconds: 3_600,
            rating: 4
        )
        let excluded = workout(
            date: date(day: 11, hour: 0),
            splitName: "Pull",
            weight: 70,
            reps: 10,
            durationSeconds: 2_700,
            rating: 3
        )
        var filters = HistoryFilters()
        filters.endDate = date(day: 10, hour: 12)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let display = HistoryDisplaySnapshotBuilder.build(
            workouts: [HistoryWorkoutSnapshot(included), HistoryWorkoutSnapshot(excluded)],
            filters: filters,
            now: date(day: 12, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(display.sessionRows.map(\.id), [included.id])
    }

    func testHistoryLegacyDurationSubtractsAccumulatedPausedSeconds() {
        let startedAt = date(day: 8, hour: 12)
        let session = WorkoutSession(
            date: startedAt,
            splitNameSnapshot: "Push",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(2 * 60 * 60),
            accumulatedPausedSeconds: 30 * 60,
            completed: true
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let display = HistoryDisplaySnapshotBuilder.build(
            workouts: [HistoryWorkoutSnapshot(session)],
            now: date(day: 10, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(display.sessionRows.first?.durationText, "1 hr 30 min")
        XCTAssertEqual(display.overview.currentDurationText, "1 hr 30 min")
    }

    func testWorkoutDurationCorrectionSynchronizesStoredFieldsAndEndTime() {
        let startedAt = date(day: 8, hour: 12)
        let loggedDate = date(day: 8, hour: 11)
        let session = WorkoutSession(
            date: loggedDate,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(9 * 3_600),
            durationMinutes: 540,
            durationSeconds: 9 * 3_600,
            accumulatedPausedSeconds: 300,
            completed: true
        )

        XCTAssertTrue(WorkoutSessionDurationService().apply(activeDurationSeconds: 5_400, to: session))
        XCTAssertEqual(session.durationSeconds, 5_400)
        XCTAssertEqual(session.durationMinutes, 90)
        XCTAssertEqual(session.endedAt, startedAt.addingTimeInterval(5_700))
        XCTAssertEqual(session.date, loggedDate)
    }

    func testWorkoutDurationCorrectionRejectsValuesBelowOneMinuteWithoutMutation() {
        let startedAt = date(day: 8, hour: 12)
        let originalEnd = startedAt.addingTimeInterval(3_600)
        let session = WorkoutSession(
            date: startedAt,
            startedAt: startedAt,
            endedAt: originalEnd,
            durationMinutes: 60,
            durationSeconds: 3_600,
            completed: true
        )
        let service = WorkoutSessionDurationService()

        XCTAssertFalse(service.apply(activeDurationSeconds: 0, to: session))
        XCTAssertFalse(service.apply(activeDurationSeconds: 59, to: session))
        XCTAssertEqual(session.durationSeconds, 3_600)
        XCTAssertEqual(session.durationMinutes, 60)
        XCTAssertEqual(session.endedAt, originalEnd)
        XCTAssertTrue(service.apply(activeDurationSeconds: 60, to: session))
        XCTAssertEqual(session.durationSeconds, 60)
        XCTAssertEqual(session.durationMinutes, 1)
    }

    func testWorkoutCompletionStateRestoresEveryMutatedTimingField() {
        let startedAt = date(day: 8, hour: 12)
        let originalEnd = startedAt.addingTimeInterval(3_600)
        let session = WorkoutSession(
            date: startedAt,
            startedAt: startedAt,
            endedAt: originalEnd,
            durationMinutes: 60,
            durationSeconds: 3_600,
            pausedAt: startedAt.addingTimeInterval(3_500),
            accumulatedPausedSeconds: 120,
            perceivedDifficulty: 3,
            completed: false
        )
        let original = WorkoutSessionCompletionState(session)

        session.date = startedAt.addingTimeInterval(86_400)
        session.endedAt = startedAt.addingTimeInterval(7_200)
        session.durationMinutes = 120
        session.durationSeconds = 7_200
        session.pausedAt = nil
        session.accumulatedPausedSeconds = 600
        session.perceivedDifficulty = 5
        session.completed = true
        original.restore(session)

        XCTAssertEqual(session.date, startedAt)
        XCTAssertEqual(session.endedAt, originalEnd)
        XCTAssertEqual(session.durationMinutes, 60)
        XCTAssertEqual(session.durationSeconds, 3_600)
        XCTAssertEqual(session.pausedAt, startedAt.addingTimeInterval(3_500))
        XCTAssertEqual(session.accumulatedPausedSeconds, 120)
        XCTAssertEqual(session.perceivedDifficulty, 3)
        XCTAssertFalse(session.completed)
    }

    func testWorkoutDurationCalibrationFiltersInvalidSamplesAtEveryBoundary() {
        let now = date(day: 20, hour: 12)
        let invalidOnly = WorkoutDurationCalibration(samples: [
            WorkoutDurationSample(date: now.addingTimeInterval(1), splitName: "Push", mode: .full, durationSeconds: 3_600, completedWorkingSetCount: 12),
            WorkoutDurationSample(date: now.addingTimeInterval(-181 * 86_400), splitName: "Push", mode: .full, durationSeconds: 3_600, completedWorkingSetCount: 12),
            WorkoutDurationSample(date: date(day: 19, hour: 12), splitName: "Push", mode: .full, durationSeconds: 599, completedWorkingSetCount: 2),
            WorkoutDurationSample(date: date(day: 18, hour: 12), splitName: "Push", mode: .full, durationSeconds: 4 * 3_600, completedWorkingSetCount: 12),
            WorkoutDurationSample(date: date(day: 17, hour: 12), splitName: "Push", mode: .full, durationSeconds: 3_600, completedWorkingSetCount: 0)
        ])

        XCTAssertNil(invalidOnly.minutesPerWorkingSet(splitName: "Push", mode: .full, now: now))

        let inclusiveLowerBoundary = WorkoutDurationCalibration(samples: [
            WorkoutDurationSample(date: date(day: 19, hour: 12), splitName: "Push", mode: .full, durationSeconds: 600, completedWorkingSetCount: 2),
            WorkoutDurationSample(date: date(day: 18, hour: 12), splitName: "Push", mode: .full, durationSeconds: 600, completedWorkingSetCount: 2),
            WorkoutDurationSample(date: date(day: 17, hour: 12), splitName: "Push", mode: .full, durationSeconds: 600, completedWorkingSetCount: 2)
        ])

        XCTAssertEqual(
            inclusiveLowerBoundary.minutesPerWorkingSet(splitName: "Push", mode: .full, now: now),
            5
        )
    }

    func testWorkoutDurationSampleRequiresCompletedWorkoutAndWorkingSet() {
        let session = WorkoutSession(
            date: date(day: 8, hour: 12),
            durationSeconds: 3_600,
            completed: false
        )
        XCTAssertNil(WorkoutDurationSample(session: session))

        session.completed = true
        XCTAssertNil(WorkoutDurationSample(session: session))

        let exerciseLog = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: UUID(),
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0
        )
        let workingSet = SetLog(
            exerciseLogId: exerciseLog.id,
            setNumber: 1,
            isWarmup: false,
            completed: true
        )
        workingSet.exerciseLog = exerciseLog
        exerciseLog.setLogs = [workingSet]
        session.exerciseLogs = [exerciseLog]

        XCTAssertEqual(WorkoutDurationSample(session: session)?.completedWorkingSetCount, 1)
    }

    func testFiveDayRotationAdvancesLegsUpperLowerAndWrapsToPush() {
        let rotation = rotationSnapshots(["Push", "Pull", "Legs", "Upper", "Lower"])
        let service = TrainingRotationService()

        XCTAssertEqual(
            service.nextSplit(activeSplits: rotation, completedSessions: [rotationSession(for: rotation[2])])?.name,
            "Upper"
        )
        XCTAssertEqual(
            service.nextSplit(activeSplits: rotation, completedSessions: [rotationSession(for: rotation[3])])?.name,
            "Lower"
        )
        XCTAssertEqual(
            service.nextSplit(activeSplits: rotation, completedSessions: [rotationSession(for: rotation[4])])?.name,
            "Push"
        )
    }

    func testBaselineConfidenceDoesNotResetAOneSessionRotation() {
        let rotation = rotationSnapshots(["Push", "Pull", "Legs", "Upper", "Lower"])
        let decision = TrainingDecisionService().decision(
            activeSplits: rotation,
            completedSessions: [rotationSession(for: rotation[2])]
        )

        XCTAssertEqual(decision.action, .buildBaseline)
        XCTAssertEqual(decision.recommendedSplitName, "Upper")
    }

    func testRotationUsesIDAfterRenameAndLegacyNameOnlyWhenUnique() {
        let rotation = rotationSnapshots(["Push", "Back Day", "Legs"])
        let renamedSession = rotationSession(for: rotation[1], splitName: "Pull")
        let legacySession = rotationSession(for: rotation[0], splitName: "Push - Full", usesLegacyName: true)
        let service = TrainingRotationService()

        XCTAssertEqual(service.nextSplit(activeSplits: rotation, completedSessions: [renamedSession])?.name, "Legs")
        XCTAssertEqual(service.nextSplit(activeSplits: rotation, completedSessions: [legacySession])?.name, "Back Day")
    }

    func testRotationIgnoresInactiveAndEmptySessionsAndHonoursReordering() {
        let rotation = [
            rotationSnapshot(name: "Lower", index: 0),
            rotationSnapshot(name: "Push", index: 1),
            rotationSnapshot(name: "Upper", index: 2)
        ]
        let inactiveSession = rotationSession(for: rotation[1], splitID: UUID(), splitName: "Push")
        let emptySession = WorkoutAnalyticsSession(
            id: UUID(),
            date: date(day: 26, hour: 12),
            splitId: rotation[2].id,
            splitNameSnapshot: rotation[2].name,
            completed: true,
            exerciseLogs: []
        )
        let service = TrainingRotationService()

        XCTAssertEqual(
            service.nextSplit(activeSplits: rotation, completedSessions: [inactiveSession, emptySession])?.name,
            "Lower"
        )
        XCTAssertEqual(
            service.nextSplit(activeSplits: rotation, completedSessions: [rotationSession(for: rotation[0])])?.name,
            "Push"
        )
    }

    func testLowerSplitNamesUseLegsIconWithoutBroadSubstringMatching() {
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Lower"), .legs)
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Lower Body"), .legs)
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Legs"), .legs)
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Upper"), .upperBody)
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Upper - Full"), .upperBody)
        XCTAssertEqual(ExerciseIconMapper.splitIconKey(for: "Upper Lower Mix"), .genericExercise)
    }

    private func analyticsSession(day: Int, weight: Double, reps: Int, setCount: Int = 1) -> WorkoutAnalyticsSession {
        analyticsSession(
            day: day,
            splitName: "Push",
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            weight: weight,
            reps: reps,
            setCount: setCount
        )
    }

    private func prRecord(
        index: Int,
        exerciseLogID: UUID,
        exerciseName: String
    ) -> PRRecord {
        PRRecord(
            id: "pr-\(index)",
            sessionId: UUID(),
            exerciseLogId: exerciseLogID,
            setLogId: UUID(),
            exerciseName: exerciseName,
            date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
            workoutSplitName: "Push",
            prType: index.isMultiple(of: 2) ? .estimatedOneRepMax : .heaviestWeight,
            value: Double(100 + index),
            displayValue: "\(100 + index) kg",
            previousDisplayValue: "100 kg",
            improvementDescription: "Improvement \(index)"
        )
    }

    private func rotationSnapshots(_ names: [String]) -> [TrainingSplitSnapshot] {
        names.enumerated().map { index, name in
            rotationSnapshot(name: name, index: index)
        }
    }

    private func rotationSnapshot(name: String, index: Int) -> TrainingSplitSnapshot {
        TrainingSplitSnapshot(
            id: UUID(),
            name: name,
            updatedAt: date(day: 1, hour: 12),
            activeRotationIndex: index,
            exercises: []
        )
    }

    private func rotationSession(
        for split: TrainingSplitSnapshot,
        splitID: UUID? = nil,
        splitName: String? = nil,
        usesLegacyName: Bool = false
    ) -> WorkoutAnalyticsSession {
        let log = ExerciseAnalyticsLog(
            id: UUID(),
            exerciseId: exerciseId,
            exerciseNameSnapshot: "Fixture Exercise",
            orderIndex: 0,
            notes: nil,
            setLogs: [
                SetAnalyticsLog(
                    id: UUID(),
                    setNumber: 1,
                    weight: 10,
                    reps: 10,
                    isWarmup: false,
                    completed: true
                )
            ]
        )
        return WorkoutAnalyticsSession(
            id: UUID(),
            date: date(day: 26, hour: 12),
            splitId: usesLegacyName ? nil : (splitID ?? split.id),
            splitNameSnapshot: splitName ?? split.name,
            completed: true,
            exerciseLogs: [log]
        )
    }

    private func analyticsSession(
        day: Int,
        splitName: String,
        exerciseId: UUID,
        exerciseName: String,
        weight: Double,
        reps: Int,
        setCount: Int = 1
    ) -> WorkoutAnalyticsSession {
        let log = ExerciseAnalyticsLog(
            id: UUID(),
            exerciseId: exerciseId,
            exerciseNameSnapshot: exerciseName,
            orderIndex: 0,
            notes: nil,
            setLogs: (1...setCount).map { setNumber in
                SetAnalyticsLog(
                    id: UUID(),
                    setNumber: setNumber,
                    weight: weight,
                    reps: reps,
                    isWarmup: false,
                    completed: true
                )
            }
        )

        return WorkoutAnalyticsSession(
            id: UUID(),
            date: date(day: day, hour: 12),
            splitNameSnapshot: splitName,
            completed: true,
            exerciseLogs: [log]
        )
    }

    private func splitSnapshot(name: String, exerciseId: UUID, exerciseName: String) -> TrainingSplitSnapshot {
        TrainingSplitSnapshot(
            id: UUID(),
            name: name,
            updatedAt: date(day: 1, hour: 12),
            exercises: [
                SplitExerciseSnapshot(
                    id: UUID(),
                    exerciseId: exerciseId,
                    exerciseNameSnapshot: exerciseName,
                    orderIndex: 0,
                    minReps: 8,
                    maxReps: 12
                )
            ]
        )
    }

    private func workout(date: Date, splitName: String, weight: Double, reps: Int, durationSeconds: Int, rating: Int) -> WorkoutSession {
        WorkoutSession(
            date: date,
            splitNameSnapshot: splitName,
            durationSeconds: durationSeconds,
            perceivedDifficulty: rating,
            completed: true,
            exerciseLogs: [
                exerciseLog(name: "Bench Press", setLogs: [
                    SetLog(setNumber: 1, weight: weight, reps: reps, completed: true)
                ])
            ]
        )
    }

    private func exerciseLog(name: String, setLogs: [SetLog]) -> ExerciseLog {
        ExerciseLog(
            exerciseId: exerciseId,
            exerciseNameSnapshot: name,
            orderIndex: 0,
            targetSets: 1,
            minReps: 6,
            maxReps: 10,
            setLogs: setLogs
        )
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour, minute: minute))!
    }

    private func readiness(confidence: ReadinessConfidence, category: ReadinessCategory, value: Int) -> ReadinessScore {
        ReadinessScore(
            value: value,
            category: category,
            confidence: confidence,
            recommendation: ReadinessCoachRecommendation(
                title: "Fixture readiness",
                summary: "Fixture readiness summary.",
                reasonBullets: [],
                suggestedActions: []
            ),
            factors: [],
            generatedAt: date(day: 26, hour: 9),
            checkIn: nil,
            workoutAdjustment: "Fixture adjustment.",
            recoveryNote: "Fixture note."
        )
    }

    private func fatigue(level: CoachFatigueRiskLevel, confidence: ReadinessConfidence) -> CoachFatigueRisk {
        CoachFatigueRisk(
            level: level,
            title: "Fixture fatigue",
            summary: "Fixture fatigue summary.",
            factors: ["Fixture fatigue factor."],
            recommendedAction: "Keep controlled.",
            confidence: confidence
        )
    }
}
