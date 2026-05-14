import Foundation
import SwiftData

@Model
final class SetLog {
    @Attribute(.unique) var id: UUID
    var exerciseLogId: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
    var completed: Bool
    var exerciseLog: ExerciseLog?

    init(
        id: UUID = UUID(),
        exerciseLogId: UUID = UUID(),
        setNumber: Int,
        weight: Double = 0,
        reps: Int = 0,
        rpe: Double? = nil,
        isWarmup: Bool = false,
        completed: Bool = false
    ) {
        self.id = id
        self.exerciseLogId = exerciseLogId
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.completed = completed
    }
}
