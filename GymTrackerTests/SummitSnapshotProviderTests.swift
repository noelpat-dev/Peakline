import Observation
import SwiftData
import XCTest
@testable import GymTracker

@MainActor
final class SummitSnapshotProviderTests: XCTestCase {
    func testProjectionMatchesSummitSnapshotBuilderInputs() {
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell, isCompound: true)
        let earlier = workout(
            date: date(daysAgo: 4),
            exercise: bench,
            exerciseNameSnapshot: "",
            sets: [
                (weight: 100, reps: 6, completed: true, warmup: false),
                (weight: 80, reps: 8, completed: true, warmup: true),
                (weight: 70, reps: 0, completed: true, warmup: false),
                (weight: 60, reps: 8, completed: false, warmup: false)
            ]
        )
        let later = workout(
            date: date(daysAgo: 2),
            exercise: bench,
            sets: [(weight: 120, reps: 5, completed: true, warmup: false)]
        )
        let unfinished = workout(
            date: date(daysAgo: 1),
            completed: false,
            exercise: bench,
            sets: [(weight: 200, reps: 1, completed: true, warmup: false)]
        )

        let sourceSessions = [later, unfinished, earlier]
        let expected = SummitSnapshotBuilder.inputs(
            from: sourceSessions,
            exercises: [bench],
            unitSystem: .imperial
        )
        let projected = SummitSnapshotProviderProjection.inputs(
            from: sourceSessions,
            exercises: [bench],
            unitSystem: .imperial
        )

        XCTAssertEqual(projected, expected)
        XCTAssertEqual(projected.map(\.id), [earlier.id, later.id])
        XCTAssertEqual(projected.first?.sets.first?.exerciseName, "Bench press")
        XCTAssertEqual(projected.first?.sets.first?.weightKg, SummitWeightFormatting.kilograms(100, unitSystem: .imperial))
    }

    func testRefreshPublishesExactlyOneSnapshot() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell, isCompound: true)
        context.insert(bench)
        context.insert(workout(
            date: date(daysAgo: 1),
            exercise: bench,
            sets: [(weight: 80, reps: 8, completed: true, warmup: false)]
        ))
        context.insert(UserProfile(bodyweight: 80, unitSystem: .metric))
        try context.save()

        let provider = SummitSnapshotProvider()
        let publications = PublicationCounter()
        withObservationTracking {
            _ = provider.snapshot
        } onChange: {
            publications.increment()
        }

        await provider.refresh(container: container)

        XCTAssertNotNil(provider.snapshot)
        XCTAssertEqual(publications.value, 1)
        XCTAssertEqual(provider.totalMetres, provider.snapshot?.altitude.totalMetres)
    }

    func testCancelledRefreshDoesNotPublishAfterItsCallerLeavesTheRoute() async throws {
        let container = try makeContainer()
        let provider = SummitSnapshotProvider()
        let publications = PublicationCounter()
        withObservationTracking {
            _ = provider.snapshot
        } onChange: {
            publications.increment()
        }

        let refreshTask = Task { @MainActor in
            // Cancel the caller before refresh installs its cancellation
            // handler, exercising the same path as a route disappearing just
            // before its refresh task starts.
            withUnsafeCurrentTask { $0?.cancel() }
            await provider.refresh(container: container)
        }
        await refreshTask.value

        XCTAssertNil(provider.snapshot)
        XCTAssertEqual(publications.value, 0)
    }

    func testMetresForCompletedMatchesSnapshotEngineWithCachedInputs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pullUp = exercise(name: "Pull-up", pattern: .pull, equipment: .bodyweight, isCompound: true)
        let weightDate = date(daysAgo: 3)
        let bodyweight = BodyweightLog(date: weightDate, weight: 185, unit: .imperial)
        let profile = UserProfile(bodyweight: 180, unitSystem: .imperial)
        context.insert(pullUp)
        context.insert(bodyweight)
        context.insert(profile)
        try context.save()

        let provider = SummitSnapshotProvider()
        await provider.refresh(container: container)

        let completed = workout(
            date: date(daysAgo: 1),
            exercise: pullUp,
            sets: [(weight: 20, reps: 8, completed: true, warmup: false)]
        )
        let engineInputs = SummitSnapshotBuilder.inputs(
            from: [completed],
            exercises: [pullUp],
            unitSystem: .imperial
        )
        let engineSnapshot = SummitSnapshotBuilder.build(
            sessions: engineInputs,
            bodyweights: SummitSnapshotBuilder.bodyweightInputs(from: [bodyweight]),
            profileBodyweightKg: SummitWeightFormatting.kilograms(180, unitSystem: .imperial),
            expeditionStart: nil,
            now: Date(),
            calendar: .current
        )

        XCTAssertEqual(provider.metres(forCompleted: completed), engineSnapshot.log.first?.metres)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            BodyweightLog.self,
            UserProfile.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func exercise(
        name: String,
        pattern: MovementPattern,
        equipment: EquipmentType,
        isCompound: Bool
    ) -> Exercise {
        Exercise(
            name: name,
            primaryMuscleGroup: .chest,
            movementPattern: pattern,
            equipment: equipment,
            isCompound: isCompound
        )
    }

    private func workout(
        date: Date,
        completed: Bool = true,
        exercise: Exercise,
        exerciseNameSnapshot: String? = nil,
        sets: [(weight: Double, reps: Int, completed: Bool, warmup: Bool)]
    ) -> WorkoutSession {
        let sessionID = UUID()
        let exerciseLogID = UUID()
        let setLogs = sets.enumerated().map { index, values in
            SetLog(
                exerciseLogId: exerciseLogID,
                setNumber: index + 1,
                weight: values.weight,
                reps: values.reps,
                isWarmup: values.warmup,
                completed: values.completed
            )
        }
        let exerciseLog = ExerciseLog(
            id: exerciseLogID,
            workoutSessionId: sessionID,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exerciseNameSnapshot ?? exercise.name,
            orderIndex: 0,
            setLogs: setLogs
        )
        return WorkoutSession(
            id: sessionID,
            date: date,
            splitNameSnapshot: "Strength",
            durationMinutes: 45,
            completed: completed,
            exerciseLogs: [exerciseLog]
        )
    }

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }
}

private final class PublicationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
