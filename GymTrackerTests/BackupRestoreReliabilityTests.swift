import SwiftData
import XCTest
@testable import GymTracker

@MainActor
final class BackupRestoreReliabilityTests: XCTestCase {
    func testJSONBackupImportRestoresWorkoutGraph() throws {
        let sourceContainer = try makeContainer()
        let sample = try insertSampleData(in: sourceContainer.mainContext)
        let exportService = LocalBackupExportService()
        let envelope = exportService.makeEnvelope(
            workouts: [sample.workout],
            exercises: [sample.exercise],
            splits: [sample.split]
        )
        let data = try exportService.encode(envelope)

        let targetContainer = try makeContainer()
        let summary = try LocalBackupImportService().importBackup(from: data, into: targetContainer.mainContext)

        XCTAssertEqual(summary.workoutCount, 1)
        XCTAssertEqual(summary.exerciseCount, 1)
        XCTAssertEqual(summary.splitCount, 1)

        let restoredWorkouts = try targetContainer.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        let workout = try XCTUnwrap(restoredWorkouts.first)
        XCTAssertEqual(workout.id, sample.workout.id)
        XCTAssertEqual(workout.splitNameSnapshot, "Push")
        XCTAssertEqual(workout.energyLevel, 4)
        XCTAssertEqual(workout.sorenessLevel, 2)
        XCTAssertEqual(workout.exerciseLogs.count, 1)

        let log = try XCTUnwrap(workout.exerciseLogs.first)
        XCTAssertEqual(log.exerciseNameSnapshot, "Bench Press")
        XCTAssertEqual(log.setLogs.count, 1)
        XCTAssertEqual(log.setLogs.first?.weight, 100)
        XCTAssertEqual(log.setLogs.first?.reps, 6)

        let restoredSplits = try targetContainer.mainContext.fetch(FetchDescriptor<TrainingSplit>())
        XCTAssertEqual(restoredSplits.first?.exercises.first?.exerciseNameSnapshot, "Bench Press")
    }

    func testEmergencyBackupRestoresOnlyIntoEmptyStore() throws {
        let sourceContainer = try makeContainer()
        let sample = try insertSampleData(in: sourceContainer.mainContext)
        let store = InMemoryEmergencyBackupStore()
        let service = EmergencyBackupService(store: store)

        let metadata = try service.saveBackup(
            workouts: [sample.workout],
            exercises: [sample.exercise],
            splits: [sample.split]
        )
        XCTAssertEqual(metadata.workoutCount, 1)
        XCTAssertEqual(service.latestMetadata()?.workoutCount, 1)

        let targetContainer = try makeContainer()
        let restoreOutcome = service.restoreIfNeeded(in: targetContainer.mainContext)
        guard case .restored(let summary) = restoreOutcome else {
            return XCTFail("Expected emergency restore, got \(restoreOutcome)")
        }
        XCTAssertEqual(summary.workoutCount, 1)
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 1)

        let secondRestoreOutcome = service.restoreIfNeeded(in: targetContainer.mainContext)
        XCTAssertEqual(secondRestoreOutcome, .skippedStoreNotEmpty)
    }

    func testEmergencyBackupRestoresOverStarterDataWhenNoWorkoutsExist() throws {
        let sourceContainer = try makeContainer()
        let sample = try insertSampleData(in: sourceContainer.mainContext)
        let store = InMemoryEmergencyBackupStore()
        let service = EmergencyBackupService(store: store)

        _ = try service.saveBackup(
            workouts: [sample.workout],
            exercises: [sample.exercise],
            splits: [sample.split]
        )

        let targetContainer = try makeContainer()
        try insertStarterOnlyData(in: targetContainer.mainContext)

        let restoreOutcome = service.restoreIfNeeded(in: targetContainer.mainContext)
        guard case .restored(let summary) = restoreOutcome else {
            return XCTFail("Expected emergency restore over starter data, got \(restoreOutcome)")
        }

        XCTAssertEqual(summary.workoutCount, 1)
        let workouts = try targetContainer.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(workouts.map(\.id), [sample.workout.id])

        let exercises = try targetContainer.mainContext.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.map(\.name).sorted(), ["Bench Press"])

        let splits = try targetContainer.mainContext.fetch(FetchDescriptor<TrainingSplit>())
        XCTAssertEqual(splits.map(\.name).sorted(), ["Push"])
    }

    func testEmergencyBackupDoesNotOverwriteWorkoutBackupWithEmptyStore() throws {
        let sourceContainer = try makeContainer()
        let sample = try insertSampleData(in: sourceContainer.mainContext)
        let store = InMemoryEmergencyBackupStore()
        let service = EmergencyBackupService(store: store)

        let originalMetadata = try service.saveBackup(
            workouts: [sample.workout],
            exercises: [sample.exercise],
            splits: [sample.split]
        )

        let emptyContainer = try makeContainer()
        let saveOutcome = service.saveLatestBackup(in: emptyContainer.mainContext)
        guard case .keptExistingWorkoutBackup(let keptMetadata) = saveOutcome else {
            return XCTFail("Expected existing workout backup to be kept, got \(saveOutcome)")
        }
        XCTAssertEqual(keptMetadata.workoutCount, originalMetadata.workoutCount)
        XCTAssertEqual(keptMetadata.exerciseCount, originalMetadata.exerciseCount)
        XCTAssertEqual(keptMetadata.splitCount, originalMetadata.splitCount)
        XCTAssertEqual(service.latestMetadata()?.workoutCount, 1)

        let restoreTarget = try makeContainer()
        let restoreOutcome = service.restoreIfNeeded(in: restoreTarget.mainContext)
        guard case .restored(let summary) = restoreOutcome else {
            return XCTFail("Expected original workout backup to remain restorable, got \(restoreOutcome)")
        }
        XCTAssertEqual(summary.workoutCount, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            TrainingSplit.self,
            SplitExercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func insertSampleData(in context: ModelContext) throws -> SampleBackupData {
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let splitID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let workoutID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let logID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let setID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let exercise = Exercise(
            id: exerciseID,
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            equipment: .barbell,
            isCompound: true,
            createdAt: date,
            updatedAt: date
        )

        let split = TrainingSplit(
            id: splitID,
            name: "Push",
            splitType: .custom,
            createdAt: date,
            updatedAt: date,
            daysPerWeek: 4
        )
        let splitExercise = SplitExercise(
            splitId: split.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: 2,
            minReps: 4,
            maxReps: 8,
            restSeconds: 180,
            notes: "Progress slowly."
        )
        splitExercise.split = split
        split.exercises = [splitExercise]

        let workout = WorkoutSession(
            id: workoutID,
            date: date,
            splitId: split.id,
            splitNameSnapshot: split.name,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            durationMinutes: 60,
            durationSeconds: 3_600,
            perceivedDifficulty: 4,
            energyLevel: 4,
            sorenessLevel: 2,
            notes: "Felt strong.",
            completed: true
        )
        let log = ExerciseLog(
            id: logID,
            workoutSessionId: workout.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: 1,
            minReps: 4,
            maxReps: 8
        )
        let set = SetLog(
            id: setID,
            exerciseLogId: log.id,
            setNumber: 1,
            weight: 100,
            reps: 6,
            rpe: 8,
            completed: true
        )
        set.exerciseLog = log
        log.setLogs = [set]
        log.workoutSession = workout
        workout.exerciseLogs = [log]

        context.insert(exercise)
        context.insert(split)
        context.insert(workout)
        try context.save()

        return SampleBackupData(exercise: exercise, split: split, workout: workout)
    }

    private func insertStarterOnlyData(in context: ModelContext) throws {
        let exercise = Exercise(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Starter Press",
            primaryMuscleGroup: .chest,
            movementPattern: .push,
            equipment: .machine,
            isCompound: true
        )
        let split = TrainingSplit(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Starter Push",
            splitType: .custom
        )
        let splitExercise = SplitExercise(
            splitId: split.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 12
        )
        splitExercise.split = split
        split.exercises = [splitExercise]

        context.insert(exercise)
        context.insert(split)
        try context.save()
    }
}

private struct SampleBackupData {
    let exercise: Exercise
    let split: TrainingSplit
    let workout: WorkoutSession
}

private final class InMemoryEmergencyBackupStore: EmergencyBackupStoring {
    private var data: Data?

    func readBackupRecord() throws -> Data? {
        data
    }

    func writeBackupRecord(_ data: Data) throws {
        self.data = data
    }

    func deleteBackupRecord() throws {
        data = nil
    }
}
