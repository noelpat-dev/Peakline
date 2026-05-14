import Foundation
import SwiftData

@MainActor
enum SeedDataService {
    static func seedIfNeeded(in context: ModelContext) async {
        do {
            let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
            guard exerciseCount == 0 else { return }

            let exercises = starterExercises()
            exercises.forEach(context.insert)

            let profileCount = try context.fetchCount(FetchDescriptor<UserProfile>())
            if profileCount == 0 {
                context.insert(UserProfile())
            }

            starterSplits(using: exercises).forEach(context.insert)
            try context.save()
        } catch {
            assertionFailure("Seed data failed: \(error)")
        }
    }

    private static func starterExercises() -> [Exercise] {
        [
            Exercise(name: "Barbell Bench Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell Bench Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Incline Dumbbell Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.shoulders, .triceps], movementPattern: .push, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Machine Chest Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .machine, isCompound: true),
            Exercise(name: "Cable Fly", primaryMuscleGroup: .chest, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Push-Up", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Pull-Up", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Lat Pulldown", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .cable, isCompound: true),
            Exercise(name: "Barbell Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Seated Cable Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .cable, isCompound: true),
            Exercise(name: "Machine Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .machine, isCompound: true),
            Exercise(name: "Overhead Press", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell Shoulder Press", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Lateral Raise", primaryMuscleGroup: .shoulders, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Rear Delt Fly", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.back], movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Face Pull", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.back], movementPattern: .pull, equipment: .cable, isCompound: false),
            Exercise(name: "Back Squat", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes, .hamstrings], movementPattern: .squat, equipment: .barbell, isCompound: true),
            Exercise(name: "Front Squat", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes], movementPattern: .squat, equipment: .barbell, isCompound: true),
            Exercise(name: "Leg Press", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes], movementPattern: .squat, equipment: .machine, isCompound: true),
            Exercise(name: "Romanian Deadlift", primaryMuscleGroup: .hamstrings, secondaryMuscleGroups: [.glutes, .back], movementPattern: .hinge, equipment: .barbell, isCompound: true),
            Exercise(name: "Leg Curl", primaryMuscleGroup: .hamstrings, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Leg Extension", primaryMuscleGroup: .quads, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Walking Lunge", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes, .hamstrings], movementPattern: .squat, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Calf Raise", primaryMuscleGroup: .calves, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Barbell Curl", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .barbell, isCompound: false),
            Exercise(name: "Dumbbell Curl", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Hammer Curl", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Triceps Pushdown", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Overhead Triceps Extension", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Skullcrusher", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .barbell, isCompound: false),
            Exercise(name: "Plank", primaryMuscleGroup: .core, movementPattern: .core, equipment: .bodyweight, isCompound: false),
            Exercise(name: "Hanging Leg Raise", primaryMuscleGroup: .core, movementPattern: .core, equipment: .bodyweight, isCompound: false),
            Exercise(name: "Cable Crunch", primaryMuscleGroup: .core, movementPattern: .core, equipment: .cable, isCompound: false),
            Exercise(name: "Ab Wheel Rollout", primaryMuscleGroup: .core, movementPattern: .core, equipment: .bodyweight, isCompound: false)
        ]
    }

    private static func starterSplits(using exercises: [Exercise]) -> [TrainingSplit] {
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        return [
            makeSplit(name: "Push", exercises: [
                ("Barbell Bench Press", 3, 6, 10),
                ("Incline Dumbbell Press", 3, 8, 12),
                ("Dumbbell Shoulder Press", 3, 6, 10),
                ("Lateral Raise", 3, 12, 20),
                ("Triceps Pushdown", 3, 10, 15)
            ], lookup: byName),
            makeSplit(name: "Pull", exercises: [
                ("Lat Pulldown", 3, 6, 12),
                ("Seated Cable Row", 3, 8, 12),
                ("Dumbbell Row", 2, 8, 12),
                ("Face Pull", 3, 12, 20),
                ("Dumbbell Curl", 3, 10, 15)
            ], lookup: byName),
            makeSplit(name: "Legs", exercises: [
                ("Back Squat", 3, 6, 10),
                ("Romanian Deadlift", 3, 8, 12),
                ("Leg Curl", 3, 10, 15),
                ("Leg Extension", 3, 10, 15),
                ("Calf Raise", 3, 10, 20)
            ], lookup: byName)
        ]
    }

    private static func makeSplit(
        name: String,
        exercises exerciseSpecs: [(String, Int, Int, Int)],
        lookup: [String: Exercise]
    ) -> TrainingSplit {
        let split = TrainingSplit(name: name, splitType: .pushPullLegs)
        split.exercises = exerciseSpecs.enumerated().compactMap { index, spec in
            guard let exercise = lookup[spec.0] else { return nil }

            let splitExercise = SplitExercise(
                splitId: split.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: index,
                targetSets: spec.1,
                minReps: spec.2,
                maxReps: spec.3
            )
            splitExercise.split = split
            return splitExercise
        }
        return split
    }
}
