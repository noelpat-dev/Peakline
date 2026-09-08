import Foundation
import SwiftData

struct WorkoutSessionReopenService {
    func reopen(_ session: WorkoutSession) {
        session.completed = false
        session.endedAt = nil
        session.durationSeconds = nil
        session.durationMinutes = nil
        session.pausedAt = nil
    }
}

struct WorkoutSessionCompletionState {
    let date: Date
    let endedAt: Date?
    let durationMinutes: Int?
    let durationSeconds: Int?
    let pausedAt: Date?
    let accumulatedPausedSeconds: Int
    let perceivedDifficulty: Int?
    let completed: Bool

    init(_ session: WorkoutSession) {
        date = session.date
        endedAt = session.endedAt
        durationMinutes = session.durationMinutes
        durationSeconds = session.durationSeconds
        pausedAt = session.pausedAt
        accumulatedPausedSeconds = session.accumulatedPausedSeconds
        perceivedDifficulty = session.perceivedDifficulty
        completed = session.completed
    }

    func restore(_ session: WorkoutSession) {
        session.date = date
        session.endedAt = endedAt
        session.durationMinutes = durationMinutes
        session.durationSeconds = durationSeconds
        session.pausedAt = pausedAt
        session.accumulatedPausedSeconds = accumulatedPausedSeconds
        session.perceivedDifficulty = perceivedDifficulty
        session.completed = completed
    }
}

private struct WorkoutExerciseLogPersistenceState {
    let id: UUID
    let workoutSessionId: UUID
    let exerciseId: UUID
    let exerciseNameSnapshot: String
    let orderIndex: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?
    let setLogs: [SetLog]
    let setStates: [UUID: WorkoutSetPersistenceState]

    init(_ exerciseLog: ExerciseLog) {
        id = exerciseLog.id
        workoutSessionId = exerciseLog.workoutSessionId
        exerciseId = exerciseLog.exerciseId
        exerciseNameSnapshot = exerciseLog.exerciseNameSnapshot
        orderIndex = exerciseLog.orderIndex
        targetSets = exerciseLog.targetSets
        minReps = exerciseLog.minReps
        maxReps = exerciseLog.maxReps
        notes = exerciseLog.notes
        setLogs = exerciseLog.setLogs
        setStates = Dictionary(uniqueKeysWithValues: exerciseLog.setLogs.map { ($0.id, WorkoutSetPersistenceState($0)) })
    }

    func restore(_ original: ExerciseLog, in context: ModelContext) -> ExerciseLog {
        let wasDeleted = context.deletedModelsArray.contains { ($0 as? ExerciseLog)?.id == id }
        // SwiftData keeps a deleted model's persistent identity retired even
        // after insert(oldModel). Recreate deleted nodes from captured values.
        let exerciseLog = wasDeleted ? ExerciseLog(
            id: id, workoutSessionId: workoutSessionId,
            exerciseId: exerciseId, exerciseNameSnapshot: exerciseNameSnapshot,
            orderIndex: orderIndex, targetSets: targetSets,
            minReps: minReps, maxReps: maxReps, notes: notes
        ) : original
        if wasDeleted { context.insert(exerciseLog) }
        exerciseLog.exerciseId = exerciseId
        exerciseLog.exerciseNameSnapshot = exerciseNameSnapshot
        exerciseLog.orderIndex = orderIndex
        exerciseLog.targetSets = targetSets
        exerciseLog.minReps = minReps
        exerciseLog.maxReps = maxReps
        exerciseLog.notes = notes

        let originalSetIDs = Set(setLogs.map(\.id))
        let deletedSetIDs = Set(context.deletedModelsArray.compactMap { ($0 as? SetLog)?.id })
        for set in exerciseLog.setLogs where !originalSetIDs.contains(set.id) {
            context.delete(set)
        }
        let restoredSets = setLogs.map { originalSet -> SetLog in
            guard let state = setStates[originalSet.id] else { return originalSet }
            if wasDeleted || deletedSetIDs.contains(originalSet.id) {
                context.delete(originalSet)
                let restored = state.makeSet(id: originalSet.id)
                context.insert(restored)
                return restored
            }
            state.restore(on: originalSet)
            return originalSet
        }
        exerciseLog.setLogs = restoredSets
        for set in restoredSets { set.exerciseLog = exerciseLog }
        return exerciseLog
    }

}

struct WorkoutSetPersistenceState {
    let exerciseLogId: UUID
    let setNumber: Int
    let weight: Double
    let reps: Int
    let rpe: Double?
    let isWarmup: Bool
    let completed: Bool

    init(_ set: SetLog) {
        exerciseLogId = set.exerciseLogId
        setNumber = set.setNumber
        weight = set.weight
        reps = set.reps
        rpe = set.rpe
        isWarmup = set.isWarmup
        completed = set.completed
    }

    func makeSet(id: UUID) -> SetLog {
        SetLog(id: id, exerciseLogId: exerciseLogId, setNumber: setNumber,
               weight: weight, reps: reps, rpe: rpe,
               isWarmup: isWarmup, completed: completed)
    }

    func restore(on set: SetLog) {
        set.exerciseLogId = exerciseLogId
        set.setNumber = setNumber
        set.weight = weight
        set.reps = reps
        set.rpe = rpe
        set.isWarmup = isWarmup
        set.completed = completed
    }
}

/// Narrow transaction for frequent edits to one existing set. Structural
/// logger mutations use `WorkoutLoggerPersistenceTransaction` below.
struct WorkoutSetPersistenceTransaction {
    private let set: SetLog
    private let state: WorkoutSetPersistenceState
    private let saveContext: (ModelContext) throws -> Void

    init(
        set: SetLog,
        saveContext: @escaping (ModelContext) throws -> Void = { context in
            try context.save()
        }
    ) {
        self.set = set
        state = WorkoutSetPersistenceState(set)
        self.saveContext = saveContext
    }

    func perform(in context: ModelContext, mutation: () -> Void) throws {
        mutation()
        do {
            try saveContext(context)
        } catch {
            state.restore(on: set)
            throw error
        }
    }
}

/// Captures the workout graph touched by a logger operation. Restoring this
/// state keeps unrelated pending ModelContext changes intact after a failed
/// save, including weights and reps entered before completion.
struct WorkoutLoggerPersistenceState {
    private let sessionState: WorkoutSessionCompletionState
    private let exerciseLogs: [ExerciseLog]
    private let exerciseLogStates: [UUID: WorkoutExerciseLogPersistenceState]

    init(_ session: WorkoutSession) {
        sessionState = WorkoutSessionCompletionState(session)
        exerciseLogs = session.exerciseLogs
        exerciseLogStates = Dictionary(uniqueKeysWithValues: session.exerciseLogs.map { ($0.id, WorkoutExerciseLogPersistenceState($0)) })
    }

    func restore(on session: WorkoutSession, in context: ModelContext) {
        sessionState.restore(session)

        let originalLogIDs = Set(exerciseLogs.map(\.id))
        for log in session.exerciseLogs where !originalLogIDs.contains(log.id) {
            context.delete(log)
        }
        let restoredLogs = exerciseLogs.map { log in
            exerciseLogStates[log.id]?.restore(log, in: context) ?? log
        }
        session.exerciseLogs = restoredLogs
        for log in restoredLogs { log.workoutSession = session }
    }
}

/// Runs one logger mutation and restores only its captured state on save
/// failure. The save closure is injectable so failure recovery can be tested
/// without making a shared ModelContext rollback.
struct WorkoutLoggerPersistenceTransaction {
    private let session: WorkoutSession
    private let state: WorkoutLoggerPersistenceState
    private let saveContext: (ModelContext) throws -> Void

    init(
        session: WorkoutSession,
        saveContext: @escaping (ModelContext) throws -> Void = { context in
            try context.save()
        }
    ) {
        self.session = session
        state = WorkoutLoggerPersistenceState(session)
        self.saveContext = saveContext
    }

    func perform(in context: ModelContext, mutation: () -> Void) throws {
        mutation()
        do {
            try saveContext(context)
        } catch {
            state.restore(on: session, in: context)
            throw error
        }
    }

    func restore(in context: ModelContext) {
        state.restore(on: session, in: context)
    }
}

struct WorkoutSessionDurationService {
    static let outlierThresholdSeconds = 4 * 60 * 60

    func recordedDurationSeconds(for session: WorkoutSession, now: Date = .now) -> Int? {
        if let durationSeconds = session.durationSeconds {
            return max(0, durationSeconds)
        }
        if let durationMinutes = session.durationMinutes {
            return max(0, durationMinutes * 60)
        }
        guard let startedAt = session.startedAt else { return nil }
        let end = session.endedAt ?? now
        return max(
            0,
            Int(end.timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds
        )
    }

    @discardableResult
    func apply(activeDurationSeconds: Int, to session: WorkoutSession) -> Bool {
        guard activeDurationSeconds >= 60 else { return false }

        session.durationSeconds = activeDurationSeconds
        session.durationMinutes = max(1, Int(ceil(Double(activeDurationSeconds) / 60)))
        if let startedAt = session.startedAt {
            session.endedAt = startedAt.addingTimeInterval(
                TimeInterval(activeDurationSeconds + max(0, session.accumulatedPausedSeconds))
            )
        }
        return true
    }
}
