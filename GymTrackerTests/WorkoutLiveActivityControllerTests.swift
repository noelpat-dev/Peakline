import XCTest
import SwiftData
@testable import GymTracker

@MainActor
final class WorkoutLiveActivityControllerTests: XCTestCase {
    func testStateMappingCountsOnlyCompletedOrExplicitlyEditedWorkingSets() {
        let sessionID = UUID()
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell)
        let row = exercise(name: "Cable row", pattern: .pull, equipment: .cable)
        let loggedSet = SetSpec(number: 1, weight: 60, reps: 8, completed: true)
        let editedSet = SetSpec(number: 2, weight: 90, reps: 5)
        let untouchedPrefill = SetSpec(number: 3, weight: 100, reps: 5)
        let warmup = SetSpec(number: 4, weight: 40, reps: 5, isWarmup: true, completed: true)
        let benchLog = exerciseLog(
            sessionID: sessionID,
            exercise: bench,
            orderIndex: 0,
            targetSets: 3,
            sets: [loggedSet, editedSet, untouchedPrefill, warmup]
        )
        let rowLog = exerciseLog(sessionID: sessionID, exercise: row, orderIndex: 1, targetSets: 2, sets: [])
        let session = WorkoutSession(
            id: sessionID,
            date: date(2026, 9, 24),
            splitNameSnapshot: "Upper",
            exerciseLogs: [benchLog, rowLog]
        )

        let state = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [bench.id: bench, row.id: row],
            enteredSetIDs: [editedSet.id],
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil,
            now: date(2026, 9, 24)
        )

        XCTAssertEqual(state.exerciseName, "Bench press")
        XCTAssertEqual(state.setIndexInExercise, 3)
        XCTAssertEqual(state.setsInExercise, 3)
        XCTAssertEqual(state.overallSetIndex, 3)
        XCTAssertEqual(state.overallSetCount, 5)
        XCTAssertEqual(state.completedSetCount, 2)
        XCTAssertEqual(state.exercisesLeft, 2)
        XCTAssertEqual(state.nextWeightKg, 100)
        XCTAssertEqual(state.nextReps, 5)
        XCTAssertEqual(state.metresGained, 5)
    }

    func testCompletedSessionShowsFullSetProgressAndPreservesPauseTime() {
        let start = date(2026, 9, 24)
        let pausedAt = start.addingTimeInterval(15 * 60)
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell)
        let firstSet = SetSpec(number: 1, weight: 60, reps: 8, completed: true)
        let secondSet = SetSpec(number: 2, weight: 60, reps: 8, completed: true)
        let log = exerciseLog(
            sessionID: UUID(),
            exercise: bench,
            orderIndex: 0,
            targetSets: 2,
            sets: [firstSet, secondSet]
        )
        let session = WorkoutSession(
            date: start,
            splitNameSnapshot: "Upper",
            startedAt: start,
            pausedAt: pausedAt,
            accumulatedPausedSeconds: 45,
            exerciseLogs: [log]
        )

        let state = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [bench.id: bench],
            enteredSetIDs: [],
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil,
            now: pausedAt.addingTimeInterval(30)
        )

        XCTAssertEqual(state.completedSetCount, 2)
        XCTAssertEqual(state.overallSetIndex, 2)
        XCTAssertEqual(state.overallSetCount, 2)
        XCTAssertEqual(state.pausedAt, pausedAt)
        XCTAssertEqual(state.accumulatedPausedSeconds, 45)
    }

    func testDeletingEnteredSetAndChangingWorkoutStructureRecomputesProgress() {
        let sessionID = UUID()
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell)
        let row = exercise(name: "Cable row", pattern: .pull, equipment: .cable)
        let enteredSet = SetSpec(number: 1, weight: 60, reps: 8)
        let benchLog = exerciseLog(
            sessionID: sessionID,
            exercise: bench,
            orderIndex: 0,
            targetSets: 2,
            sets: [enteredSet]
        )
        let rowLog = exerciseLog(
            sessionID: sessionID,
            exercise: row,
            orderIndex: 1,
            targetSets: 2,
            sets: []
        )
        let session = WorkoutSession(
            id: sessionID,
            date: date(2026, 9, 24),
            splitNameSnapshot: "Upper",
            exerciseLogs: [benchLog, rowLog]
        )
        let exercises = [bench.id: bench, row.id: row]
        let initialEnteredIDs = WorkoutLiveActivityStateMapper.enteredSetIDs(
            afterEditing: enteredSet.id,
            in: session,
            previouslyEntered: []
        )

        benchLog.setLogs.removeAll { $0.id == enteredSet.id }
        let enteredIDsAfterDeletion = WorkoutLiveActivityStateMapper.enteredSetIDs(
            afterEditing: enteredSet.id,
            in: session,
            previouslyEntered: initialEnteredIDs
        )
        let afterDeletion = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: exercises,
            enteredSetIDs: enteredIDsAfterDeletion,
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil
        )
        XCTAssertFalse(enteredIDsAfterDeletion.contains(enteredSet.id))
        XCTAssertEqual(afterDeletion.completedSetCount, 0)
        XCTAssertEqual(afterDeletion.overallSetCount, 4)
        XCTAssertEqual(afterDeletion.exerciseName, "Bench press")

        benchLog.targetSets = 1
        session.exerciseLogs.removeAll { $0.id == rowLog.id }
        let afterStructureChange = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: exercises,
            enteredSetIDs: enteredIDsAfterDeletion,
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil
        )
        XCTAssertEqual(afterStructureChange.overallSetCount, 1)
        XCTAssertEqual(afterStructureChange.exercisesLeft, 1)
        XCTAssertEqual(afterStructureChange.setIndexInExercise, 1)
    }

    func testMetresUseLatestPriorBodyweightLogAndIgnoreWarmups() {
        let sessionID = UUID()
        let pullUp = exercise(name: "Pull-up", pattern: .pull, equipment: .bodyweight)
        let workingSet = SetSpec(number: 1, weight: 0, reps: 8)
        let warmup = SetSpec(number: 2, weight: 0, reps: 3, isWarmup: true, completed: true)
        let log = exerciseLog(
            sessionID: sessionID,
            exercise: pullUp,
            orderIndex: 0,
            targetSets: 2,
            sets: [workingSet, warmup]
        )
        let sessionDate = date(2026, 9, 20)
        let session = WorkoutSession(
            id: sessionID,
            date: sessionDate,
            splitNameSnapshot: "Pull",
            exerciseLogs: [log]
        )
        let bodyweightLogs = [
            BodyweightLog(date: date(2026, 9, 1), weight: 176, unit: .imperial),
            BodyweightLog(date: date(2026, 9, 25), weight: 120, unit: .metric)
        ]
        let bodyweightKg = WorkoutLiveActivityStateMapper.bodyweightKilograms(
            for: sessionDate,
            bodyweightLogs: bodyweightLogs,
            profileBodyweightKg: 90
        )

        let state = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [pullUp.id: pullUp],
            enteredSetIDs: [workingSet.id],
            bodyweightKg: bodyweightKg,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil,
            now: sessionDate
        )

        XCTAssertEqual(
            bodyweightKg,
            SummitWeightFormatting.kilograms(176, unitSystem: .imperial),
            accuracy: 0.001
        )
        XCTAssertEqual(state.metresGained, 4)
        XCTAssertEqual(
            WorkoutLiveActivityStateMapper.bodyweightKilograms(
                for: sessionDate,
                bodyweightLogs: [],
                profileBodyweightKg: 82
            ),
            82
        )
        XCTAssertEqual(
            WorkoutLiveActivityStateMapper.bodyweightKilograms(
                for: sessionDate,
                bodyweightLogs: [],
                profileBodyweightKg: nil
            ),
            75
        )
    }

    func testEditedSetNeedsPositiveRepsButBodyweightNeedsNoAddedLoad() {
        let sessionID = UUID()
        let bodyweight = exercise(name: "Push-up", pattern: .push, equipment: .bodyweight)
        let loadOnlySet = SetSpec(number: 1, weight: 40, reps: 0)
        let bodyweightSet = SetSpec(number: 2, weight: 0, reps: 8)
        let log = exerciseLog(
            sessionID: sessionID,
            exercise: bodyweight,
            orderIndex: 0,
            targetSets: 2,
            sets: [loadOnlySet, bodyweightSet]
        )
        let session = WorkoutSession(
            id: sessionID,
            date: date(2026, 9, 24),
            splitNameSnapshot: "Upper",
            exerciseLogs: [log]
        )

        let afterLoadOnlyEdit = WorkoutLiveActivityStateMapper.enteredSetIDs(
            afterEditing: loadOnlySet.id,
            in: session,
            previouslyEntered: []
        )
        let afterBodyweightEdit = WorkoutLiveActivityStateMapper.enteredSetIDs(
            afterEditing: bodyweightSet.id,
            in: session,
            previouslyEntered: afterLoadOnlyEdit
        )

        XCTAssertFalse(afterLoadOnlyEdit.contains(loadOnlySet.id))
        XCTAssertTrue(afterBodyweightEdit.contains(bodyweightSet.id))
    }

    func testPRFlashExpiresAtItsDeadlineAndBecomesTheActivityStaleDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(WorkoutLiveActivityPRTracker.prFlashDuration)
        let session = WorkoutSession(date: now, splitNameSnapshot: "Upper")
        let exercise = exercise(name: "Bench press", pattern: .push, equipment: .barbell)
        let flash = WorkoutActivityAttributes.PRFlash(
            exerciseName: "Bench press",
            weightKg: 100,
            reps: 5,
            until: deadline
        )

        let visibleState = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [exercise.id: exercise],
            enteredSetIDs: [],
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: flash,
            now: now
        )
        let expiredState = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [exercise.id: exercise],
            enteredSetIDs: [],
            bodyweightKg: 80,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: flash,
            now: deadline
        )

        XCTAssertEqual(visibleState.pr?.until, deadline)
        XCTAssertEqual(WorkoutLiveActivityStateMapper.staleDate(for: visibleState, now: now), deadline)
        XCTAssertNil(expiredState.pr)
    }

    func testPRRequiresAnEarlierBestAndOnlyTheCurrentSessionBestCanFlash() {
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell)
        let historySessionID = UUID()
        let previousSet = SetSpec(number: 1, weight: 60, reps: 8, completed: true)
        let historyLog = exerciseLog(
            sessionID: historySessionID,
            exercise: bench,
            orderIndex: 0,
            targetSets: 1,
            sets: [previousSet]
        )
        let history = WorkoutSession(
            id: historySessionID,
            date: date(2026, 9, 10),
            splitNameSnapshot: "Upper",
            completed: true,
            exerciseLogs: [historyLog]
        )
        let currentSessionID = UUID()
        let recordSet = SetSpec(number: 1, weight: 70, reps: 8)
        let lowerSet = SetSpec(number: 2, weight: 50, reps: 8)
        let currentLog = exerciseLog(
            sessionID: currentSessionID,
            exercise: bench,
            orderIndex: 0,
            targetSets: 2,
            sets: [recordSet, lowerSet]
        )
        let currentSession = WorkoutSession(
            id: currentSessionID,
            date: date(2026, 9, 24),
            splitNameSnapshot: "Upper",
            exerciseLogs: [currentLog]
        )
        let exercises = [bench]
        let currentSetInputs = WorkoutLiveActivityStateMapper.setInputs(
            from: currentSession,
            exercisesByID: [bench.id: bench],
            unitSystem: .metric,
            enteredSetIDs: [recordSet.id, lowerSet.id]
        )
        let previousBest = WorkoutLiveActivityPRTracker.previousBestE1RMByExercise(
            in: [history],
            exercises: exercises,
            bodyweightLogs: [],
            profileBodyweightKg: 80,
            unitSystem: .metric
        )

        let newRecord = WorkoutLiveActivityPRTracker.newPRCandidate(
            for: recordSet.id,
            currentSetInputs: currentSetInputs,
            previousBestE1RMByExercise: previousBest,
            bodyweightKg: 80
        )
        let lowerSetCannotFlash = WorkoutLiveActivityPRTracker.newPRCandidate(
            for: lowerSet.id,
            currentSetInputs: currentSetInputs,
            previousBestE1RMByExercise: previousBest,
            bodyweightKg: 80
        )
        let firstSessionCannotFlash = WorkoutLiveActivityPRTracker.newPRCandidate(
            for: recordSet.id,
            currentSetInputs: currentSetInputs,
            previousBestE1RMByExercise: [:],
            bodyweightKg: 80
        )

        XCTAssertEqual(newRecord?.id, recordSet.id)
        XCTAssertNil(lowerSetCannotFlash)
        XCTAssertNil(firstSessionCannotFlash)
    }

    func testUpdateThrottleSendsOnlyChangedContent() {
        let session = WorkoutSession(date: date(2026, 9, 24), splitNameSnapshot: "Upper")
        let initial = WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: [:],
            enteredSetIDs: [],
            bodyweightKg: 75,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil,
            now: date(2026, 9, 24)
        )
        let changedSession = WorkoutSession(
            date: date(2026, 9, 24),
            splitNameSnapshot: "Lower"
        )
        let changed = WorkoutLiveActivityStateMapper.makeState(
            from: changedSession,
            exercisesByID: [:],
            enteredSetIDs: [],
            bodyweightKg: 75,
            unitSystem: .metric,
            restEndsAt: nil,
            prFlash: nil,
            now: date(2026, 9, 24)
        )
        var throttle = WorkoutLiveActivityUpdateThrottle()

        XCTAssertTrue(throttle.shouldSend(initial))
        XCTAssertFalse(throttle.shouldSend(initial))
        XCTAssertTrue(throttle.shouldSend(changed))
        XCTAssertFalse(throttle.shouldSend(changed))

        throttle.reset(initialState: initial)
        XCTAssertFalse(throttle.shouldSend(initial))
    }

    private func exercise(
        name: String,
        pattern: MovementPattern,
        equipment: EquipmentType
    ) -> Exercise {
        Exercise(
            name: name,
            primaryMuscleGroup: .chest,
            movementPattern: pattern,
            equipment: equipment,
            isCompound: true
        )
    }

    private func exerciseLog(
        sessionID: UUID,
        exercise: Exercise,
        orderIndex: Int,
        targetSets: Int,
        sets: [SetSpec]
    ) -> ExerciseLog {
        let exerciseLogID = UUID()
        let setLogs = sets.map {
            SetLog(
                id: $0.id,
                exerciseLogId: exerciseLogID,
                setNumber: $0.number,
                weight: $0.weight,
                reps: $0.reps,
                isWarmup: $0.isWarmup,
                completed: $0.completed
            )
        }
        return ExerciseLog(
            id: exerciseLogID,
            workoutSessionId: sessionID,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: orderIndex,
            targetSets: targetSets,
            minReps: 5,
            maxReps: 8,
            setLogs: setLogs
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private struct SetSpec {
        var id: UUID = UUID()
        let number: Int
        let weight: Double
        let reps: Int
        var isWarmup = false
        var completed = false
    }
}
