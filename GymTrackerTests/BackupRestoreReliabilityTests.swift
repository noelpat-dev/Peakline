import SwiftData
import XCTest
@testable import GymTracker

private enum ExerciseLibraryInjectedSaveFailure: Error, Equatable {
    case expected
}

@MainActor
final class BackupRestoreReliabilityTests: XCTestCase {
    func testExerciseLibrarySaveFailureRestoresTouchedRecordsAndKeepsUnrelatedChanges() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let baselineDate = Date(timeIntervalSince1970: 1_800_000_000)
        let exercise = Exercise(
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            movementPattern: .push,
            equipment: .barbell,
            isCompound: true,
            updatedAt: baselineDate
        )
        let metadata = CoachExerciseMetadata(
            exerciseId: exercise.id,
            role: .accessory,
            primaryMuscleGroup: .chest,
            movementPattern: .push,
            userNote: "Keep form strict"
        )
        context.insert(exercise)
        context.insert(metadata)
        try context.save()

        let unrelatedPendingExercise = Exercise(
            name: "Unrelated pending change",
            primaryMuscleGroup: .back,
            movementPattern: .pull,
            equipment: .cable,
            isCompound: false
        )
        context.insert(unrelatedPendingExercise)

        let persistence = ExerciseLibraryPersistence(saveContext: { _ in
            throw ExerciseLibraryInjectedSaveFailure.expected
        })

        XCTAssertThrowsError(try persistence.archive([exercise], in: context)) { error in
            XCTAssertEqual(error as? ExerciseLibraryInjectedSaveFailure, .expected)
        }
        XCTAssertFalse(exercise.isArchived)
        XCTAssertEqual(exercise.updatedAt, baselineDate)

        XCTAssertThrowsError(
            try persistence.applyMetadata(existingMetadata: [metadata], in: context) {
                metadata.role = .priorityLift
                metadata.userNote = "Changed before failure"
                let inserted = CoachExerciseMetadata(
                    exerciseId: UUID(),
                    role: .warmUp,
                    primaryMuscleGroup: .chest,
                    movementPattern: .push
                )
                context.insert(inserted)
                return [inserted]
            }
        ) { error in
            XCTAssertEqual(error as? ExerciseLibraryInjectedSaveFailure, .expected)
        }
        XCTAssertEqual(metadata.role, .accessory)
        XCTAssertEqual(metadata.userNote, "Keep form strict")
        XCTAssertTrue(context.hasChanges)
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<Exercise>()).first {
                $0.id == unrelatedPendingExercise.id
            }
        )
    }

    func testExerciseLibraryCreateFailureRemovesOnlyFailedInsertion() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let unrelatedPendingExercise = Exercise(
            name: "Existing pending exercise",
            primaryMuscleGroup: .quads,
            movementPattern: .squat,
            equipment: .barbell,
            isCompound: true
        )
        context.insert(unrelatedPendingExercise)
        let insertedExercise = Exercise(
            name: "Failed create",
            primaryMuscleGroup: .chest,
            movementPattern: .push,
            equipment: .barbell,
            isCompound: true
        )

        let persistence = ExerciseLibraryPersistence(saveContext: { _ in
            throw ExerciseLibraryInjectedSaveFailure.expected
        })

        XCTAssertThrowsError(try persistence.insert(insertedExercise, in: context)) { error in
            XCTAssertEqual(error as? ExerciseLibraryInjectedSaveFailure, .expected)
        }
        XCTAssertNil(
            try context.fetch(FetchDescriptor<Exercise>()).first {
                $0.id == insertedExercise.id
            }
        )
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<Exercise>()).first {
                $0.id == unrelatedPendingExercise.id
            }
        )
    }

    func testSessionSummarySplitSaveFailureRestoresTemplateOrderAndRemovesInsertedRows() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let baselineDate = Date(timeIntervalSince1970: 1_800_000_000)
        let split = TrainingSplit(
            name: "Push",
            splitType: .custom,
            updatedAt: baselineDate
        )
        let existing = SplitExercise(
            splitId: split.id,
            exerciseId: UUID(),
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 4,
            targetSets: 2,
            minReps: 5,
            maxReps: 8,
            notes: "Baseline"
        )
        let unmatched = SplitExercise(
            splitId: split.id,
            exerciseId: UUID(),
            exerciseNameSnapshot: "Lateral Raise",
            orderIndex: 9,
            targetSets: 3,
            minReps: 10,
            maxReps: 15,
            notes: "Keep as a template fallback"
        )
        existing.split = split
        unmatched.split = split
        split.exercises = [existing, unmatched]

        let session = WorkoutSession(
            splitId: split.id,
            splitNameSnapshot: "Push",
            completed: true
        )
        let matchingLog = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: existing.exerciseId,
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0,
            targetSets: 3,
            minReps: 6,
            maxReps: 10,
            notes: "Session note"
        )
        let newLog = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: UUID(),
            exerciseNameSnapshot: "Cable Fly",
            orderIndex: 1,
            targetSets: 2,
            minReps: 10,
            maxReps: 15
        )
        matchingLog.workoutSession = session
        newLog.workoutSession = session
        session.exerciseLogs = [matchingLog, newLog]
        context.insert(split)
        context.insert(session)
        try context.save()

        let persistence = SessionSummarySplitPersistence(saveContext: { _ in
            throw ExerciseLibraryInjectedSaveFailure.expected
        })

        XCTAssertThrowsError(try persistence.update(split, with: session, in: context)) { error in
            XCTAssertEqual(error as? ExerciseLibraryInjectedSaveFailure, .expected)
        }
        XCTAssertEqual(split.updatedAt, baselineDate)
        XCTAssertEqual(split.exercises.count, 2)
        XCTAssertEqual(existing.orderIndex, 4)
        XCTAssertEqual(existing.targetSets, 2)
        XCTAssertEqual(existing.notes, "Baseline")
        XCTAssertEqual(unmatched.orderIndex, 9)
    }

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

    func testVersionTwoExportPreservesCustomRotationOrder() throws {
        let lower = TrainingSplit(
            name: "Lower",
            splitType: .custom,
            activeRotationIndex: 0
        )
        let push = TrainingSplit(
            name: "Push",
            splitType: .custom,
            activeRotationIndex: 1
        )
        let service = LocalBackupExportService()
        let envelope = service.makeEnvelope(workouts: [], exercises: [], splits: [push, lower])

        XCTAssertEqual(envelope.schemaVersion, 2)

        let target = try makeContainer()
        _ = try LocalBackupImportService().importBackup(
            from: service.encode(envelope),
            into: target.mainContext
        )
        let restored = try target.mainContext.fetch(FetchDescriptor<TrainingSplit>())
        XCTAssertEqual(TrainingRotationService().orderedActiveSplits(restored).map(\.name), ["Lower", "Push"])
    }

    func testVersionOneExportWithoutIndexesBootstrapsFiveDayRotation() throws {
        let sourceSplits = ["Lower", "Upper", "Pull", "Legs", "Push"].map {
            TrainingSplit(name: $0, splitType: .custom, activeRotationIndex: nil)
        }
        let service = LocalBackupExportService()
        let currentData = try service.encode(
            service.makeEnvelope(workouts: [], exercises: [], splits: sourceSplits)
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        json["schemaVersion"] = 1
        var splitObjects = try XCTUnwrap(json["splits"] as? [[String: Any]])
        for index in splitObjects.indices {
            splitObjects[index].removeValue(forKey: "activeRotationIndex")
        }
        json["splits"] = splitObjects
        let versionOneData = try JSONSerialization.data(withJSONObject: json)

        let target = try makeContainer()
        _ = try LocalBackupImportService().importBackup(from: versionOneData, into: target.mainContext)
        let restored = try target.mainContext.fetch(FetchDescriptor<TrainingSplit>())
        let ordered = TrainingRotationService().orderedActiveSplits(restored)

        XCTAssertEqual(ordered.map(\.name), ["Push", "Pull", "Legs", "Upper", "Lower"])
        XCTAssertEqual(ordered.map(\.activeRotationIndex), [0, 1, 2, 3, 4])
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

    func testEmergencyBackupRejectsUnsupportedRecordSchemaWithoutMutatingStore() throws {
        let sourceContainer = try makeContainer()
        let sample = try insertSampleData(in: sourceContainer.mainContext)
        let store = InMemoryEmergencyBackupStore()
        let service = EmergencyBackupService(store: store)

        _ = try service.saveBackup(
            workouts: [sample.workout],
            exercises: [sample.exercise],
            splits: [sample.split]
        )
        try store.mutateRecord { json in
            json["schemaVersion"] = 99
        }

        let targetContainer = try makeContainer()
        let restoreOutcome = service.restoreIfNeeded(in: targetContainer.mainContext)

        guard case .failed(let message) = restoreOutcome else {
            return XCTFail("Expected unsupported record failure, got \(restoreOutcome)")
        }
        XCTAssertTrue(message.contains("schema version 99"))
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
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

    func mutateRecord(_ mutation: (inout [String: Any]) -> Void) throws {
        guard let data else {
            return XCTFail("Expected an emergency backup record before mutation")
        }
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("Expected the emergency backup record to be a JSON object")
        }
        mutation(&json)
        self.data = try JSONSerialization.data(withJSONObject: json)
    }

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
