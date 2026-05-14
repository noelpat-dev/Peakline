import Foundation
import SwiftData

@Model
final class TrainingSplit {
    @Attribute(.unique) var id: UUID
    var name: String
    var splitType: SplitType
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var daysPerWeek: Int

    @Relationship(deleteRule: .cascade, inverse: \SplitExercise.split)
    var exercises: [SplitExercise]

    init(
        id: UUID = UUID(),
        name: String,
        splitType: SplitType,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isActive: Bool = true,
        daysPerWeek: Int = 3,
        exercises: [SplitExercise] = []
    ) {
        self.id = id
        self.name = name
        self.splitType = splitType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.daysPerWeek = daysPerWeek
        self.exercises = exercises
    }
}

@Model
final class SplitExercise {
    @Attribute(.unique) var id: UUID
    var splitId: UUID
    var exerciseId: UUID
    var exerciseNameSnapshot: String
    var orderIndex: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var restSeconds: Int?
    var notes: String?
    var split: TrainingSplit?

    init(
        id: UUID = UUID(),
        splitId: UUID = UUID(),
        exerciseId: UUID,
        exerciseNameSnapshot: String,
        orderIndex: Int,
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        restSeconds: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.splitId = splitId
        self.exerciseId = exerciseId
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.restSeconds = restSeconds
        self.notes = notes
    }
}
