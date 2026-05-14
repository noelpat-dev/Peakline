import Foundation
import SwiftData

@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var workoutSessionId: UUID
    var exerciseId: UUID
    var exerciseNameSnapshot: String
    var orderIndex: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var notes: String?
    var workoutSession: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseLog)
    var setLogs: [SetLog]

    init(
        id: UUID = UUID(),
        workoutSessionId: UUID = UUID(),
        exerciseId: UUID,
        exerciseNameSnapshot: String,
        orderIndex: Int,
        targetSets: Int = 0,
        minReps: Int = 0,
        maxReps: Int = 0,
        notes: String? = nil,
        setLogs: [SetLog] = []
    ) {
        self.id = id
        self.workoutSessionId = workoutSessionId
        self.exerciseId = exerciseId
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.notes = notes
        self.setLogs = setLogs
    }
}
