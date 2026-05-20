import Foundation

enum ExerciseIconMapper {
    static func iconKey(for exercise: Exercise) -> ExerciseIconKey {
        iconKey(
            forName: exercise.name,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            equipment: exercise.equipment,
            movementPattern: exercise.movementPattern
        )
    }

    static func iconKey(for splitExercise: SplitExercise) -> ExerciseIconKey {
        iconKey(forName: splitExercise.exerciseNameSnapshot)
    }

    static func iconKey(for exerciseLog: ExerciseLog) -> ExerciseIconKey {
        iconKey(forName: exerciseLog.exerciseNameSnapshot)
    }

    static func iconKey(for suggestion: TargetSuggestion) -> ExerciseIconKey {
        iconKey(forName: suggestion.exerciseName)
    }

    static func splitIconKey(for splitName: String) -> ExerciseIconKey {
        let normalized = normalized(splitName)
        if normalized == "push" || normalized.hasPrefix("push ") { return .genericPush }
        if normalized == "pull" || normalized.hasPrefix("pull ") { return .genericPull }
        if normalized == "legs" || normalized.hasPrefix("legs ") { return .legs }
        return .genericExercise
    }

    static func iconKey(
        forName name: String,
        primaryMuscleGroup: MuscleGroup? = nil,
        equipment: EquipmentType? = nil,
        movementPattern: MovementPattern? = nil
    ) -> ExerciseIconKey {
        let name = normalized(name)

        if name.contains("bicep preacher curl") || name.contains("preacher curl") || name.contains("bicep curl") { return .bicepCurl }
        if name.contains("chest fly") || name.contains("pec fly") { return .chestFly }
        if name.contains("diverging seated row") || name.contains("diverging lower lat row") { return .divergingRow }
        if name.contains("dumbbell shoulder press") { return .dumbbellShoulderPress }
        if name.contains("hack squat") { return .hackSquat }
        if name.contains("hip adduction") { return .hipAdduction }
        if name.contains("incline") && name.contains("chest press") && name.contains("smith") { return .inclineChestPress }
        if name.contains("incline") && name.contains("chest press") { return .inclineChestPress }
        if name.contains("lat pulldown") { return .latPulldown }
        if name.contains("seated leg curl") || name.contains("leg curl") { return .legCurl }
        if name.contains("quad extension") || name.contains("leg extension") { return .legExtension }
        if name.contains("leg press") { return .legPress }
        if name.contains("close grip") && (name.contains("weighted pull-up") || name.contains("weighted pull up") || name.contains("pull-up") || name.contains("pull up") || name.contains("pullup")) { return .pullUps }
        if name.contains("weighted pull-up") || name.contains("weighted pull up") || name.contains("pull-up") || name.contains("pull up") || name.contains("pullup") || name.contains("pull ups") { return .pullUps }
        if name.contains("standing calf raise") || name.contains("calf raise") { return .standingCalfRaise }
        if name.contains("triceps pushdown") || name.contains("tricep pushdown") || name.contains("tricep push down") { return .tricepPushDown }

        if name.contains("bench press") || name.contains("converging chest press") || name.contains("chest press") { return .inclineChestPress }
        if name.contains("shoulder press") { return .dumbbellShoulderPress }
        if name.contains("overhead triceps") { return .tricepPushDown }
        if name.contains("rear delt") || name.contains("seated row") || name.contains("lower lat row") { return .divergingRow }
        if name.contains("abdominal crunch") { return .abdominalCrunch }
        if name.contains("cable lateral raise") || name.contains("lateral raise") { return .cableLateralRaise }
        if name.contains("abdominal") || name.contains("core") { return .genericCore }
        if name.contains("squat") { return .hackSquat }

        if let primaryMuscleGroup {
            switch primaryMuscleGroup {
            case .chest, .shoulders, .triceps:
                return .genericPush
            case .back, .biceps:
                return .genericPull
            case .quads, .hamstrings, .glutes, .calves:
                return .genericLegs
            case .core:
                return .genericCore
            case .fullBody, .other:
                break
            }
        }

        if let movementPattern {
            switch movementPattern {
            case .push:
                return .genericPush
            case .pull:
                return .genericPull
            case .squat, .hinge:
                return .genericLegs
            case .core:
                return .genericCore
            case .carry, .isolation, .other:
                break
            }
        }

        if let equipment {
            switch equipment {
            case .cable:
                return .genericCable
            case .machine, .smithMachine:
                return .genericMachine
            case .dumbbell, .kettlebell:
                return .genericDumbbell
            case .barbell:
                return .genericBarbell
            case .bodyweight, .other:
                break
            }
        }

        return .genericExercise
    }

    private static func normalized(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }
}
