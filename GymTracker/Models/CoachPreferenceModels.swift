import Foundation
import SwiftData

@Model
final class CoachPreferences {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var aggressivenessRawValue: String
    var deloadWordingRawValue: String
    var detailLevelRawValue: String
    var trainingPriorityRawValue: String
    var reductionPreferenceRawValue: String
    var recommendationFrequencyRawValue: String
    var showDiagnostics: Bool

    init(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000601") ?? UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        aggressiveness: CoachAggressiveness = .balanced,
        deloadWording: CoachDeloadWording = .gentle,
        detailLevel: CoachDetailLevel = .standard,
        trainingPriority: CoachTrainingPriority = .balanced,
        reductionPreference: CoachReductionPreference = .protectPriorityLifts,
        recommendationFrequency: CoachRecommendationFrequency = .standard,
        showDiagnostics: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aggressivenessRawValue = aggressiveness.rawValue
        self.deloadWordingRawValue = deloadWording.rawValue
        self.detailLevelRawValue = detailLevel.rawValue
        self.trainingPriorityRawValue = trainingPriority.rawValue
        self.reductionPreferenceRawValue = reductionPreference.rawValue
        self.recommendationFrequencyRawValue = recommendationFrequency.rawValue
        self.showDiagnostics = showDiagnostics
    }

    var aggressiveness: CoachAggressiveness {
        get { CoachAggressiveness(rawValue: aggressivenessRawValue) ?? .balanced }
        set {
            aggressivenessRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var deloadWording: CoachDeloadWording {
        get { CoachDeloadWording(rawValue: deloadWordingRawValue) ?? .gentle }
        set {
            deloadWordingRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var detailLevel: CoachDetailLevel {
        get { CoachDetailLevel(rawValue: detailLevelRawValue) ?? .standard }
        set {
            detailLevelRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var trainingPriority: CoachTrainingPriority {
        get { CoachTrainingPriority(rawValue: trainingPriorityRawValue) ?? .balanced }
        set {
            trainingPriorityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var reductionPreference: CoachReductionPreference {
        get { CoachReductionPreference(rawValue: reductionPreferenceRawValue) ?? .protectPriorityLifts }
        set {
            reductionPreferenceRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var recommendationFrequency: CoachRecommendationFrequency {
        get { CoachRecommendationFrequency(rawValue: recommendationFrequencyRawValue) ?? .standard }
        set {
            recommendationFrequencyRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var snapshot: CoachPreferencesSnapshot {
        CoachPreferencesSnapshot(
            aggressiveness: aggressiveness,
            deloadWording: deloadWording,
            detailLevel: detailLevel,
            trainingPriority: trainingPriority,
            reductionPreference: reductionPreference,
            recommendationFrequency: recommendationFrequency,
            showDiagnostics: showDiagnostics
        )
    }

    func update(from snapshot: CoachPreferencesSnapshot) {
        aggressivenessRawValue = snapshot.aggressiveness.rawValue
        deloadWordingRawValue = snapshot.deloadWording.rawValue
        detailLevelRawValue = snapshot.detailLevel.rawValue
        trainingPriorityRawValue = snapshot.trainingPriority.rawValue
        reductionPreferenceRawValue = snapshot.reductionPreference.rawValue
        recommendationFrequencyRawValue = snapshot.recommendationFrequency.rawValue
        showDiagnostics = snapshot.showDiagnostics
        updatedAt = .now
    }
}

@Model
final class CoachSplitMetadata {
    @Attribute(.unique) var id: UUID
    var splitId: UUID
    var splitName: String
    var createdAt: Date
    var updatedAt: Date
    var priorityRawValue: String
    var plannedIntensityRawValue: String
    var primaryGoalRawValue: String
    var expectedFatigueRawValue: String
    var protectCompounds: Bool
    var accessoriesFlexible: Bool
    var preferredAdjustmentStyleRawValue: String
    var userNote: String?

    init(
        id: UUID = UUID(),
        splitId: UUID,
        splitName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        priority: CoachSplitPriority = .normal,
        plannedIntensity: CoachPlannedIntensity = .moderate,
        primaryGoal: CoachSplitGoal = .hypertrophy,
        expectedFatigue: CoachExpectedFatigue = .moderate,
        protectCompounds: Bool = true,
        accessoriesFlexible: Bool = true,
        preferredAdjustmentStyle: CoachPreferredAdjustmentStyle = .protectMainLifts,
        userNote: String? = nil
    ) {
        self.id = id
        self.splitId = splitId
        self.splitName = splitName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.priorityRawValue = priority.rawValue
        self.plannedIntensityRawValue = plannedIntensity.rawValue
        self.primaryGoalRawValue = primaryGoal.rawValue
        self.expectedFatigueRawValue = expectedFatigue.rawValue
        self.protectCompounds = protectCompounds
        self.accessoriesFlexible = accessoriesFlexible
        self.preferredAdjustmentStyleRawValue = preferredAdjustmentStyle.rawValue
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var priority: CoachSplitPriority {
        get { CoachSplitPriority(rawValue: priorityRawValue) ?? .normal }
        set {
            priorityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var plannedIntensity: CoachPlannedIntensity {
        get { CoachPlannedIntensity(rawValue: plannedIntensityRawValue) ?? .moderate }
        set {
            plannedIntensityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var primaryGoal: CoachSplitGoal {
        get { CoachSplitGoal(rawValue: primaryGoalRawValue) ?? .hypertrophy }
        set {
            primaryGoalRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var expectedFatigue: CoachExpectedFatigue {
        get { CoachExpectedFatigue(rawValue: expectedFatigueRawValue) ?? .moderate }
        set {
            expectedFatigueRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var preferredAdjustmentStyle: CoachPreferredAdjustmentStyle {
        get { CoachPreferredAdjustmentStyle(rawValue: preferredAdjustmentStyleRawValue) ?? .protectMainLifts }
        set {
            preferredAdjustmentStyleRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var snapshot: CoachSplitMetadataSnapshot {
        CoachSplitMetadataSnapshot(
            splitId: splitId,
            splitName: splitName,
            priority: priority,
            plannedIntensity: plannedIntensity,
            primaryGoal: primaryGoal,
            expectedFatigue: expectedFatigue,
            protectCompounds: protectCompounds,
            accessoriesFlexible: accessoriesFlexible,
            preferredAdjustmentStyle: preferredAdjustmentStyle,
            userNote: userNote
        )
    }

    func update(from snapshot: CoachSplitMetadataSnapshot) {
        splitId = snapshot.splitId
        splitName = snapshot.splitName
        priorityRawValue = snapshot.priority.rawValue
        plannedIntensityRawValue = snapshot.plannedIntensity.rawValue
        primaryGoalRawValue = snapshot.primaryGoal.rawValue
        expectedFatigueRawValue = snapshot.expectedFatigue.rawValue
        protectCompounds = snapshot.protectCompounds
        accessoriesFlexible = snapshot.accessoriesFlexible
        preferredAdjustmentStyleRawValue = snapshot.preferredAdjustmentStyle.rawValue
        userNote = snapshot.userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = .now
    }
}

@Model
final class CoachExerciseMetadata {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date
    var roleRawValue: String
    var primaryMuscleGroupRawValue: String
    var secondaryMuscleGroupRawValues: [String]
    var movementPatternRawValue: String
    var splitClassificationRawValue: String
    var priorityRawValue: String
    var userNote: String?

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        role: CoachExerciseMetadataRole,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        movementPattern: MovementPattern,
        splitClassification: CoachSplitClassification = .unspecified,
        priority: CoachExercisePriorityLevel = .normal,
        userNote: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.roleRawValue = role.rawValue
        self.primaryMuscleGroupRawValue = primaryMuscleGroup.rawValue
        self.secondaryMuscleGroupRawValues = secondaryMuscleGroups.map(\.rawValue)
        self.movementPatternRawValue = movementPattern.rawValue
        self.splitClassificationRawValue = splitClassification.rawValue
        self.priorityRawValue = priority.rawValue
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var role: CoachExerciseMetadataRole {
        get { CoachExerciseMetadataRole(rawValue: roleRawValue) ?? .compound }
        set { roleRawValue = newValue.rawValue }
    }

    var primaryMuscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleGroupRawValue) ?? .other }
        set { primaryMuscleGroupRawValue = newValue.rawValue }
    }

    var secondaryMuscleGroups: [MuscleGroup] {
        get { secondaryMuscleGroupRawValues.compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryMuscleGroupRawValues = newValue.map(\.rawValue) }
    }

    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRawValue) ?? .other }
        set { movementPatternRawValue = newValue.rawValue }
    }

    var splitClassification: CoachSplitClassification {
        get { CoachSplitClassification(rawValue: splitClassificationRawValue) ?? .unspecified }
        set { splitClassificationRawValue = newValue.rawValue }
    }

    var priority: CoachExercisePriorityLevel {
        get { CoachExercisePriorityLevel(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    func update(
        role: CoachExerciseMetadataRole,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup],
        movementPattern: MovementPattern,
        splitClassification: CoachSplitClassification,
        priority: CoachExercisePriorityLevel,
        userNote: String?
    ) {
        self.role = role
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.splitClassification = splitClassification
        self.priority = priority
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = .now
    }
}
