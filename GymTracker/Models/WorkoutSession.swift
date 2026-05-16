import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var splitId: UUID?
    var splitNameSnapshot: String
    var startedAt: Date?
    var endedAt: Date?
    var durationMinutes: Int?
    var durationSeconds: Int?
    var pausedAt: Date?
    var accumulatedPausedSeconds: Int = 0
    var perceivedDifficulty: Int?
    var energyLevel: Int?
    var sorenessLevel: Int?
    var notes: String?
    var completed: Bool

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.workoutSession)
    var exerciseLogs: [ExerciseLog]

    init(
        id: UUID = UUID(),
        date: Date = .now,
        splitId: UUID? = nil,
        splitNameSnapshot: String = "Empty Workout",
        startedAt: Date? = .now,
        endedAt: Date? = nil,
        durationMinutes: Int? = nil,
        durationSeconds: Int? = nil,
        pausedAt: Date? = nil,
        accumulatedPausedSeconds: Int = 0,
        perceivedDifficulty: Int? = nil,
        energyLevel: Int? = nil,
        sorenessLevel: Int? = nil,
        notes: String? = nil,
        completed: Bool = false,
        exerciseLogs: [ExerciseLog] = []
    ) {
        self.id = id
        self.date = date
        self.splitId = splitId
        self.splitNameSnapshot = splitNameSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.durationSeconds = durationSeconds
        self.pausedAt = pausedAt
        self.accumulatedPausedSeconds = accumulatedPausedSeconds
        self.perceivedDifficulty = perceivedDifficulty
        self.energyLevel = energyLevel
        self.sorenessLevel = sorenessLevel
        self.notes = notes
        self.completed = completed
        self.exerciseLogs = exerciseLogs
    }
}
