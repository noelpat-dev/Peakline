import Foundation
import Observation
import OSLog
import SwiftData

private enum SummitSnapshotProviderConstants {
    static let expeditionStartKey = "summit.expedition.machame.start"
}

@MainActor
@Observable
final class SummitSnapshotProvider {
    private(set) var snapshot: SummitSnapshot?
    private(set) var unitSystem: UnitSystem = .metric

    private var exerciseMetadata: [UUID: SummitExerciseMetadata] = [:]
    private var bodyweights: [SummitBodyweightInput] = []
    private var profileBodyweightKg: Double?
    private var latestRefreshID = UUID()

    var totalMetres: Int? { snapshot?.altitude.totalMetres }

    func refresh(container: ModelContainer) async {
        let refreshID = UUID()
        latestRefreshID = refreshID

        let result = await Task.detached(priority: .utility) {
            try? SummitSnapshotRefreshWorker.makeSnapshot(container: container)
        }.value

        guard latestRefreshID == refreshID, let result else { return }

        // Keep only value data from the background context. In particular, no
        // SwiftData model instance is retained or sent back to the main actor.
        unitSystem = result.unitSystem
        exerciseMetadata = result.exerciseMetadata
        bodyweights = result.bodyweights
        profileBodyweightKg = result.profileBodyweightKg
        snapshot = result.snapshot
    }

    func metres(forCompleted session: WorkoutSession) -> Int {
        guard session.completed else { return 0 }

        let sets = session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .flatMap { exerciseLog -> [SummitSetInput] in
                let metadata = exerciseMetadata[exerciseLog.exerciseId]
                return exerciseLog.setLogs
                    .filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { set in
                        SummitSetInput(
                            id: set.id,
                            exerciseID: exerciseLog.exerciseId,
                            exerciseName: exerciseLog.exerciseNameSnapshot.isEmpty
                                ? metadata?.name ?? "Exercise"
                                : exerciseLog.exerciseNameSnapshot,
                            pattern: metadata?.pattern ?? .other,
                            isBodyweight: metadata?.isBodyweight ?? false,
                            isCompound: metadata?.isCompound ?? false,
                            weightKg: SummitWeightFormatting.kilograms(set.weight, unitSystem: unitSystem),
                            reps: set.reps
                        )
                    }
            }

        let bodyweightKg = bodyweights.last(where: { $0.date <= session.date })?.weightKg
            ?? profileBodyweightKg
            ?? 75
        let metres = SummitProgressService.metres(for: sets, bodyweightKg: bodyweightKg)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SummitForceCrossing"),
           let totalMetres,
           let nextPeak = SummitProgressService.altitude(totalMetres: totalMetres, gainedToday: nil).next {
            return max(metres, nextPeak.metres - totalMetres)
        }
        #endif

        return metres
    }

    func setOff(container: ModelContainer) async {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: SummitSnapshotProviderConstants.expeditionStartKey
        )
        await refresh(container: container)
    }
}

/// Keeps Summit's model projection identical to the builder used by refresh.
/// It is also directly testable without exposing refresh's internal cache.
enum SummitSnapshotProviderProjection {
    static func inputs(
        from sessions: [WorkoutSession],
        exercises: [Exercise],
        unitSystem: UnitSystem
    ) -> [SummitSessionInput] {
        SummitSnapshotBuilder.inputs(from: sessions, exercises: exercises, unitSystem: unitSystem)
    }
}

private struct SummitExerciseMetadata: @unchecked Sendable {
    let name: String
    let pattern: MovementPattern
    let isBodyweight: Bool
    let isCompound: Bool

    init(_ exercise: Exercise) {
        name = exercise.name
        pattern = exercise.movementPattern
        isBodyweight = exercise.equipment == .bodyweight
        isCompound = exercise.isCompound
    }
}

private struct SummitSnapshotRefreshResult: @unchecked Sendable {
    let snapshot: SummitSnapshot
    let unitSystem: UnitSystem
    let exerciseMetadata: [UUID: SummitExerciseMetadata]
    let bodyweights: [SummitBodyweightInput]
    let profileBodyweightKg: Double?
}

private struct SummitFetchedInputs {
    let sessions: [SummitSessionInput]
    let bodyweights: [SummitBodyweightInput]
    let profileBodyweightKg: Double?
    let unitSystem: UnitSystem
    let exerciseMetadata: [UUID: SummitExerciseMetadata]
}

private enum SummitSnapshotRefreshWorker {
    private static let signposter = OSSignposter(
        subsystem: "com.peakline.GymTracker",
        category: "SummitSnapshotProvider"
    )

    static func makeSnapshot(container: ModelContainer) throws -> SummitSnapshotRefreshResult {
        let fetched = try fetchInputs(container: container)
        let expeditionTimestamp = UserDefaults.standard.double(
            forKey: SummitSnapshotProviderConstants.expeditionStartKey
        )
        let expeditionStart = expeditionTimestamp > 0
            ? Date(timeIntervalSince1970: expeditionTimestamp)
            : nil
        let now = Date()
        let calendar = Calendar.current

        let snapshot = withRefreshInterval(stage: "build") {
            SummitSnapshotBuilder.build(
                sessions: fetched.sessions,
                bodyweights: fetched.bodyweights,
                profileBodyweightKg: fetched.profileBodyweightKg,
                expeditionStart: expeditionStart,
                now: now,
                calendar: calendar
            )
        }

        return SummitSnapshotRefreshResult(
            snapshot: snapshot,
            unitSystem: fetched.unitSystem,
            exerciseMetadata: fetched.exerciseMetadata,
            bodyweights: fetched.bodyweights.sorted { $0.date < $1.date },
            profileBodyweightKg: fetched.profileBodyweightKg
        )
    }

    private static func fetchInputs(container: ModelContainer) throws -> SummitFetchedInputs {
        try withRefreshInterval(stage: "fetch") {
            let context = ModelContext(container)
            var sessionDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate<WorkoutSession> { $0.completed }
            )
            sessionDescriptor.relationshipKeyPathsForPrefetching = [\WorkoutSession.exerciseLogs]

            let sessions = try context.fetch(sessionDescriptor)
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let weightLogs = try context.fetch(FetchDescriptor<BodyweightLog>())
            let profile = try context.fetch(FetchDescriptor<UserProfile>()).first

            // Resolve each set relationship while these models still belong to
            // this background context, before projecting to value inputs.
            for session in sessions {
                for exerciseLog in session.exerciseLogs {
                    _ = exerciseLog.setLogs.count
                }
            }

            let unitSystem = profile?.unitSystem ?? .metric
            let sessionsInput = SummitSnapshotProviderProjection.inputs(
                from: sessions,
                exercises: exercises,
                unitSystem: unitSystem
            )
            let bodyweights = SummitSnapshotBuilder.bodyweightInputs(from: weightLogs)
            let profileBodyweightKg = profile?.bodyweight.map {
                SummitWeightFormatting.kilograms($0, unitSystem: unitSystem)
            }

            return SummitFetchedInputs(
                sessions: sessionsInput,
                bodyweights: bodyweights,
                profileBodyweightKg: profileBodyweightKg,
                unitSystem: unitSystem,
                exerciseMetadata: Dictionary(
                    exercises.map { ($0.id, SummitExerciseMetadata($0)) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
    }

    private static func withRefreshInterval<Value>(
        stage: String,
        operation: () throws -> Value
    ) rethrows -> Value {
        let interval = signposter.beginInterval("SummitSnapshotRefresh", "stage: \(stage)")
        defer { signposter.endInterval("SummitSnapshotRefresh", interval) }
        return try operation()
    }
}
