import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var primaryMuscleGroup: MuscleGroup
    var secondaryMuscleGroups: [MuscleGroup]
    var movementPattern: MovementPattern
    var equipment: EquipmentType
    var isCompound: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        movementPattern: MovementPattern,
        equipment: EquipmentType,
        isCompound: Bool,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.equipment = equipment
        self.isCompound = isCompound
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
