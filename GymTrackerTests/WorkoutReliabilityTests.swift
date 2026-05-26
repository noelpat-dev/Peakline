import XCTest
@testable import GymTracker

@MainActor
final class WorkoutReliabilityTests: XCTestCase {
    private let exerciseId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

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
}
