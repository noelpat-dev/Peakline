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

    /// Returns artwork metadata for an exercise without changing or inferring
    /// the exercise's saved name, equipment, muscles, or movement pattern.
    /// Exact and semantically equivalent catalog matches are preferred; when
    /// no exact entry exists, the returned entry is representative artwork.
    static func illustrationEntry(for exercise: Exercise) -> ExerciseGuideEntry? {
        illustrationEntry(
            forName: exercise.name,
            equipment: exercise.equipment,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            movementPattern: exercise.movementPattern
        )
    }

    static func illustrationEntry(
        forName name: String,
        equipment: EquipmentType? = nil,
        primaryMuscleGroup: MuscleGroup? = nil,
        movementPattern: MovementPattern? = nil
    ) -> ExerciseGuideEntry? {
        if let exact = guideEntry(forName: name, equipment: equipment) {
            return exact
        }

        let key = iconKey(
            forName: name,
            primaryMuscleGroup: primaryMuscleGroup,
            equipment: equipment,
            movementPattern: movementPattern
        )
        guard let slug = key.workoutGuideSlug else {
            return nil
        }
        return ExerciseGuideCatalog.entry(forSlug: slug)
    }

    /// Resolves a seeded exercise to Workout Guide metadata when the name and
    /// equipment identify one exact upstream entry. This stays separate from
    /// `illustrationEntry`: callers that display saved exercise details can
    /// distinguish an exact metadata match from representative artwork.
    static func guideEntry(for exercise: Exercise) -> ExerciseGuideEntry? {
        guideEntry(forName: exercise.name, equipment: exercise.equipment)
    }

    static func guideEntry(
        forName name: String,
        equipment: EquipmentType? = nil
    ) -> ExerciseGuideEntry? {
        let normalizedName = normalized(name)
        let guideEquipment = equipment.flatMap { guideEquipmentName(for: $0) }

        // The seeded Standing Calf Raise is dumbbell-based, while Workout
        // Guide's same-name entry is machine-based. A snapshot has no
        // equipment field, so suppress this one ambiguous name rather than
        // presenting a machine illustration as an exact match.
        let hasKnownEquipmentCollision = equipment == nil
            && normalizedName == "standing calf raise"

        if equipment == nil, !hasKnownEquipmentCollision {
            if let exact = ExerciseGuideCatalog.entry(forName: name) {
                return exact
            }
        } else if let guideEquipment,
                  let exact = ExerciseGuideCatalog.entry(forName: name, equipment: guideEquipment) {
            return exact
        }

        // The starter library uses a few familiar names that differ from the
        // Workout Guide canonical names. Each alias is constrained to the
        // matching equipment variant before it is accepted.
        let alias: (slug: String, equipment: String)?
        switch normalizedName {
        case "converging chest press":
            alias = ("machine-chest-press", "Machine")
        case "chest fly":
            alias = ("pec-deck", "Machine")
        case "rear delt machine":
            alias = ("reverse-pec-deck", "Machine")
        case "rear delt cable":
            alias = ("cable-rear-delt-fly", "Cable")
        case "incline dumbbell bench press":
            alias = ("incline-dumbbell-press", "Dumbbell")
        case "dumbbell bicep curl":
            alias = ("bicep-curl", "Dumbbell")
        case "triceps pushdown", "tricep pushdown", "tricep push down":
            alias = ("tricep-pushdown", "Cable")
        case "overhead triceps extension", "overhead tricep extension":
            alias = ("overhead-tricep-extension", "Cable")
        case "quad extension":
            alias = ("leg-extension", "Machine")
        case "hamstring curl":
            alias = ("leg-curl", "Machine")
        case "hip adduction":
            alias = ("hip-adduction-machine", "Machine")
        case "bicep preacher curl machine":
            alias = ("preacher-curl", "Machine")
        default:
            alias = nil
        }

        guard let alias,
              equipment == nil || guideEquipment == alias.equipment else {
            return nil
        }
        return ExerciseGuideCatalog.entry(forSlug: alias.slug)
    }

    static func splitIconKey(for splitName: String) -> ExerciseIconKey {
        let normalized = normalized(splitName)
        if normalized == "push" || normalized.hasPrefix("push ") { return .genericPush }
        if normalized == "pull" || normalized.hasPrefix("pull ") { return .genericPull }
        if normalized == "legs" || normalized.hasPrefix("legs ") { return .legs }
        if normalized == "lower" || normalized.hasPrefix("lower ") { return .legs }
        if normalized == "upper"
            || normalized.hasPrefix("upper -")
            || normalized == "upper body"
            || normalized.hasPrefix("upper body ")
            || (normalized.hasPrefix("upper ") && !normalized.hasPrefix("upper lower")) {
            return .upperBody
        }
        return .genericExercise
    }

    static func iconKey(
        forName name: String,
        primaryMuscleGroup: MuscleGroup? = nil,
        equipment: EquipmentType? = nil,
        movementPattern: MovementPattern? = nil
    ) -> ExerciseIconKey {
        let name = normalized(name)

        if let guideEntry = guideEntry(forName: name, equipment: equipment),
           let guideKey = ExerciseIconKey.guideKey(forSlug: guideEntry.slug) {
            return guideKey
        }

        if name.contains("incline") && name.contains("chest press") && name.contains("smith") { return .inclineChestPressSmith }
        if name.contains("bench press") { return .benchPress }
        if name.contains("converging chest press") { return .convergingChestPress }
        if name.contains("incline") && name.contains("chest press") { return .inclineChestPress }
        if name.contains("low-high chest fly") || name.contains("low high chest fly") { return .genericCable }
        if name.contains("close grip") && (name.contains("weighted pull-up") || name.contains("weighted pull up") || name.contains("pull-up") || name.contains("pull up") || name.contains("pullup")) { return .closeGripWeightedPullUp }
        if name.contains("weighted pull-up") || name.contains("weighted pull up") || name.contains("weighted pullup") { return .closeGripWeightedPullUp }
        if name.contains("pull ups") { return .pullUps }
        if name.contains("pull-up") || name.contains("pull up") || name.contains("pullup") { return .pullUp }
        if name.contains("diverging seated row") { return .divergingSeatedRow }
        if name.contains("diverging lower lat row") || name.contains("lower lat row") { return .divergingLowerLatRow }
        if name.contains("seated t-bar row") || name.contains("t-bar row") { return .divergingRow }
        if name.contains("seated row") { return .seatedRow }
        if name.contains("rear delt cable") { return .rearDeltCable }
        if name.contains("shoulder press") && name.contains("smith") { return .shoulderPressSmith }
        if name.contains("overhead triceps") { return .overheadTricepsExtension }
        if name.contains("triceps pushdown") || name.contains("tricep pushdown") || name.contains("tricep push down") { return .tricepsPushdown }
        if name.contains("jm press") { return .guideCloseGripBenchPress }
        if name.contains("triceps cable") || name.contains("one-arm triceps cable") || name.contains("seated triceps press") { return .tricepsPushdown }
        if name.contains("seated leg curl") { return .seatedLegCurl }
        if name.contains("hamstring curl") { return .legCurl }
        if name.contains("quad extension") { return .quadExtension }
        if name.contains("bicep preacher curl") && name.contains("machine") { return .bicepPreacherCurlMachine }
        if name.contains("bicep preacher curl") || name.contains("preacher curl") { return .bicepPreacherCurl }
        if name.contains("bicep curl") { return .bicepCurl }
        if name.contains("chest fly") || name.contains("pec fly") { return .chestFly }
        if name.contains("diverging seated row") || name.contains("diverging lower lat row") { return .divergingRow }
        if name.contains("dumbbell shoulder press") { return .dumbbellShoulderPress }
        if name.contains("hack squat") { return .hackSquat }
        if name.contains("hip adduction") { return .hipAdduction }
        if name.contains("lat pulldown") { return .latPulldown }
        if name.contains("seated leg curl") || name.contains("leg curl") { return .legCurl }
        if name.contains("quad extension") || name.contains("leg extension") { return .legExtension }
        if name.contains("leg press") { return .legPress }
        if name.contains("standing calf raise") || name.contains("calf raise") { return .standingCalfRaise }

        if name.contains("chest press") { return .chestPress }
        if name.contains("shoulder press") { return .dumbbellShoulderPress }
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

    private static func guideEquipmentName(for equipment: EquipmentType) -> String? {
        switch equipment {
        case .barbell:
            return "Barbell"
        case .dumbbell:
            return "Dumbbell"
        case .machine:
            return "Machine"
        case .cable:
            return "Cable"
        case .bodyweight:
            return "Bodyweight"
        case .kettlebell:
            return "Kettlebell"
        case .smithMachine, .other:
            return nil
        }
    }
}
