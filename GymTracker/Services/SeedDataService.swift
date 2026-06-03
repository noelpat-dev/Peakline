import Foundation
import SwiftData

@MainActor
enum SeedDataService {
    static func seedIfNeeded(in context: ModelContext) {
        do {
            var existingExercises = try context.fetch(FetchDescriptor<Exercise>())
            let existingExerciseNames = Set(existingExercises.map(\.name))
            let missingExercises = starterExercises().filter { !existingExerciseNames.contains($0.name) }
            missingExercises.forEach(context.insert)
            existingExercises.append(contentsOf: missingExercises)

            let profileCount = try context.fetchCount(FetchDescriptor<UserProfile>())
            if profileCount == 0 {
                context.insert(UserProfile(trainingDaysPerWeek: 4, preferredSplitType: .custom))
            }

            let existingSplits = try context.fetch(FetchDescriptor<TrainingSplit>())
            let hasPersonalPushSplit = existingSplits.contains { split in
                split.name == "Push" && split.exercises.contains { $0.exerciseNameSnapshot == "Incline Chest Press (Smith)" }
            }

            if !hasPersonalPushSplit {
                let previousTemplateNames = ["Push", "Pull", "Legs", "Chest + Triceps", "Back + Biceps", "Shoulders", "Legs + Core"]
                for split in existingSplits where previousTemplateNames.contains(split.name) {
                    split.isActive = false
                }

                starterSplits(using: existingExercises).forEach(context.insert)
            }

            if ProcessInfo.processInfo.arguments.contains("-UITestCoachFatigueFixture") {
                try seedCoachFatigueFixture(in: context, exercises: existingExercises)
            }

            if ProcessInfo.processInfo.arguments.contains("-UITestLargeHistoryFixture") {
                try seedLargeHistoryFixture(in: context, exercises: existingExercises)
            }

            if ProcessInfo.processInfo.arguments.contains("-UITestSavedFoodsFixture") {
                try seedSavedFoodsFixture(in: context)
            }

            if ProcessInfo.processInfo.arguments.contains("-UITestSplitsFixture") {
                try seedSplitsFixture(in: context, exercises: existingExercises)
            }

            try context.save()
        } catch {
            assertionFailure("Seed data failed: \(error)")
        }
    }

    private static func starterExercises() -> [Exercise] {
        [
            Exercise(name: "Incline Chest Press (Smith)", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .smithMachine, isCompound: true),
            Exercise(name: "Converging Chest Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .machine, isCompound: true),
            Exercise(name: "Chest Fly", primaryMuscleGroup: .chest, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Low-High Chest Fly", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.shoulders], movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Incline Chest Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .machine, isCompound: true),
            Exercise(name: "Bench Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders], movementPattern: .push, equipment: .barbell, isCompound: true),
            Exercise(name: "Triceps Pushdown", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Overhead Triceps Extension", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Triceps Cable Press", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "One-Arm Triceps Cable", primaryMuscleGroup: .triceps, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Seated Triceps Press", primaryMuscleGroup: .triceps, secondaryMuscleGroups: [.chest], movementPattern: .push, equipment: .machine, isCompound: true),
            Exercise(name: "JM Press", primaryMuscleGroup: .triceps, secondaryMuscleGroups: [.chest], movementPattern: .push, equipment: .barbell, isCompound: true),
            Exercise(name: "Lat Pulldown", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .cable, isCompound: true),
            Exercise(name: "Diverging Lower Lat Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .machine, isCompound: true),
            Exercise(name: "Diverging Seated Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .machine, isCompound: true),
            Exercise(name: "Close Grip Weighted Pull-Up", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Pull-Up", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Rear Delt Machine", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.back], movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Rear Delt Cable", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.back], movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Dumbbell Bicep Curl", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Bicep Preacher Curl", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Bicep Preacher Curl Machine", primaryMuscleGroup: .biceps, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Seated T-Bar Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps], movementPattern: .pull, equipment: .machine, isCompound: true),
            Exercise(name: "Dumbbell Shoulder Press", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Shoulder Press (Smith)", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.triceps], movementPattern: .push, equipment: .smithMachine, isCompound: true),
            Exercise(name: "Cable Lateral Raise", primaryMuscleGroup: .shoulders, movementPattern: .isolation, equipment: .cable, isCompound: false),
            Exercise(name: "Quad Extension", primaryMuscleGroup: .quads, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Single-Leg Quad Extension", primaryMuscleGroup: .quads, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Hamstring Curl", primaryMuscleGroup: .hamstrings, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Seated Leg Curl", primaryMuscleGroup: .hamstrings, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Leg Press", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes], movementPattern: .squat, equipment: .machine, isCompound: true),
            Exercise(name: "Standing Calf Raise", primaryMuscleGroup: .calves, movementPattern: .isolation, equipment: .dumbbell, isCompound: false),
            Exercise(name: "Hip Adduction", primaryMuscleGroup: .glutes, movementPattern: .isolation, equipment: .machine, isCompound: false),
            Exercise(name: "Abdominal Crunch", primaryMuscleGroup: .core, movementPattern: .core, equipment: .machine, isCompound: false),
            Exercise(name: "Hack Squat", primaryMuscleGroup: .quads, secondaryMuscleGroups: [.glutes], movementPattern: .squat, equipment: .machine, isCompound: true)
        ]
    }

    private static func starterSplits(using exercises: [Exercise]) -> [TrainingSplit] {
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        return [
            makeSplit(name: "Push", exercises: [
                ("Incline Chest Press (Smith)", 2, 6, 10, 150, "Baseline: 40kg each side x 8. Progress when both hard sets hit 10 reps."),
                ("Bench Press", 2, 4, 8, 180, "Baseline: 100kg x 5. Add load after 2 sessions at 8 reps with clean form."),
                ("Converging Chest Press", 2, 6, 10, 150, "Baseline: 86kg x 10. Hold load until both sets reach top of range."),
                ("Chest Fly", 2, 8, 15, 90, "Baseline: 136kg x 8. Keep controlled stretch; progress reps before load."),
                ("Dumbbell Shoulder Press", 2, 5, 9, 150, "Baseline: 42kg x 5."),
                ("Shoulder Press (Smith)", 2, 6, 10, 150, "Baseline: 25kg each side; next target 30kg each side when range is owned."),
                ("Cable Lateral Raise", 2, 8, 15, 75, "Baseline: 10.2kg x 5. Prioritize clean reps and side delt tension."),
                ("Triceps Pushdown", 2, 8, 12, 90, "Baseline: 42kg x 8."),
                ("Overhead Triceps Extension", 2, 8, 12, 90, "Baseline: 26kg.")
            ], lookup: byName),
            makeSplit(name: "Pull", exercises: [
                ("Lat Pulldown", 2, 5, 9, 150, "Baseline: 102kg x 5."),
                ("Close Grip Weighted Pull-Up", 2, 6, 10, 150, "Baseline: +15kg x 9."),
                ("Diverging Seated Row", 2, 6, 10, 150, "Baseline: 100kg x 7."),
                ("Diverging Lower Lat Row", 2, 8, 12, 120, "Baseline: 57.9kg x 9."),
                ("Rear Delt Cable", 2, 10, 15, 75, "Baseline: 12.5kg x 7."),
                ("Bicep Preacher Curl", 2, 8, 12, 90, "Baseline: 17.5kg x 10.")
            ], lookup: byName),
            makeSplit(name: "Legs", exercises: [
                ("Hack Squat", 2, 6, 10, 180, "Baseline: 70kg x 8."),
                ("Leg Press", 2, 6, 10, 180, "Baseline: 125kg each side x 6."),
                ("Quad Extension", 2, 8, 12, 90, "Baseline: 113kg x 5."),
                ("Seated Leg Curl", 2, 8, 12, 90, "Baseline: 66kg x 10."),
                ("Standing Calf Raise", 2, 10, 20, 75, "Baseline: holding 15kg x 20."),
                ("Hip Adduction", 2, 8, 15, 75, "Baseline: 100kg x 8."),
                ("Abdominal Crunch", 2, 8, 15, 75, "Baseline: 59kg x 8.")
            ], lookup: byName)
        ]
    }

    private static func makeSplit(
        name: String,
        exercises exerciseSpecs: [(String, Int, Int, Int, Int, String)],
        lookup: [String: Exercise]
    ) -> TrainingSplit {
        let split = TrainingSplit(name: name, splitType: .custom, daysPerWeek: 4)
        split.exercises = exerciseSpecs.enumerated().compactMap { index, spec in
            guard let exercise = lookup[spec.0] else { return nil }

            let splitExercise = SplitExercise(
                splitId: split.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: index,
                targetSets: spec.1,
                minReps: spec.2,
                maxReps: spec.3,
                restSeconds: spec.4,
                notes: spec.5
            )
            splitExercise.split = split
            return splitExercise
        }
        return split
    }

    private static func seedCoachFatigueFixture(in context: ModelContext, exercises: [Exercise]) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        guard existingCount == 0, let exercise = exercises.first(where: { $0.name == "Hack Squat" }) else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for offset in 1...4 {
            let sessionDate = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let session = WorkoutSession(
                date: sessionDate,
                splitId: nil,
                splitNameSnapshot: "UI Coach Fixture",
                durationMinutes: 95,
                perceivedDifficulty: 5,
                completed: true
            )
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: 0,
                targetSets: 18,
                minReps: 6,
                maxReps: 10
            )
            log.setLogs = (1...18).map { setNumber in
                let set = SetLog(
                    exerciseLogId: log.id,
                    setNumber: setNumber,
                    weight: 100,
                    reps: 8,
                    rpe: 9,
                    isWarmup: false,
                    completed: true
                )
                set.exerciseLog = log
                return set
            }
            log.workoutSession = session
            session.exerciseLogs = [log]
            context.insert(session)
        }

        let checkIn = DailyCoachCheckIn(
            date: today,
            energy: 1,
            soreness: 5,
            stress: 4,
            motivation: 1,
            calendar: calendar
        )
        context.insert(checkIn)

        if try context.fetchCount(FetchDescriptor<CoachActionHistoryEntry>()) == 0 {
            context.insert(
                CoachActionHistoryEntry(
                    action: .reduceAccessories,
                    outcome: .applied,
                    createdAt: today,
                    readinessCategory: .low,
                    fatigueRiskLevel: .high,
                    confidence: .medium,
                    shortReason: "Fixture coach action for UI history review.",
                    workoutName: "Push",
                    splitName: "Push",
                    beforeTotalSets: 18,
                    afterTotalSets: 15,
                    contributingSignals: ["Training fatigue: high local load", "Check-in: low energy"],
                    diagnosticSummary: "Fatigue and check-in signals suggested trimming accessories."
                )
            )
        }
    }

    private static func seedLargeHistoryFixture(in context: ModelContext, exercises: [Exercise]) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        guard existingCount < 90, !exercises.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let exercisePool = Array(exercises.prefix(12))
        let splitNames = ["Push", "Pull", "Legs"]

        for offset in 0..<150 {
            let sessionDate = calendar.date(byAdding: .day, value: -(offset + 1), to: today) ?? today
            let splitName = splitNames[offset % splitNames.count]
            let session = WorkoutSession(
                date: sessionDate,
                splitId: nil,
                splitNameSnapshot: splitName,
                durationMinutes: 72 + (offset % 5) * 4,
                perceivedDifficulty: 3 + (offset % 3),
                completed: true
            )

            let logs = (0..<5).map { logIndex in
                let exercise = exercisePool[(offset + logIndex) % exercisePool.count]
                let log = ExerciseLog(
                    workoutSessionId: session.id,
                    exerciseId: exercise.id,
                    exerciseNameSnapshot: exercise.name,
                    orderIndex: logIndex,
                    targetSets: 3,
                    minReps: 6,
                    maxReps: 12
                )
                log.setLogs = (1...3).map { setNumber in
                    let set = SetLog(
                        exerciseLogId: log.id,
                        setNumber: setNumber,
                        weight: Double(40 + ((offset + logIndex + setNumber) % 90)),
                        reps: 6 + ((offset + setNumber) % 7),
                        rpe: Double(7 + ((offset + setNumber) % 3)),
                        isWarmup: false,
                        completed: true
                    )
                    set.exerciseLog = log
                    return set
                }
                log.workoutSession = session
                return log
            }

            session.exerciseLogs = logs
            context.insert(session)
        }
    }

    private static func seedSavedFoodsFixture(in context: ModelContext) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<FoodItem>())
        guard existingCount < 18 else { return }

        let foods: [(String, String, Double, Double, Double, Double)] = [
            ("Greek Yogurt", "Peakline Test", 59, 10, 3.6, 0.4),
            ("Chicken Breast", "Peakline Test", 165, 31, 0, 3.6),
            ("Jasmine Rice", "Peakline Test", 130, 2.7, 28, 0.3),
            ("Whey Protein", "Peakline Test", 390, 78, 8, 6),
            ("Banana", "Peakline Test", 89, 1.1, 23, 0.3),
            ("Oats", "Peakline Test", 389, 17, 66, 7),
            ("Eggs", "Peakline Test", 143, 13, 1.1, 9.5),
            ("Tuna", "Peakline Test", 132, 29, 0, 1),
            ("Whole Milk", "Peakline Test", 64, 3.4, 4.8, 3.6),
            ("Peanut Butter", "Peakline Test", 588, 25, 20, 50),
            ("Protein Bar", "Peakline Test", 360, 30, 35, 10),
            ("Cottage Cheese", "Peakline Test", 98, 11, 3.4, 4.3),
            ("Blueberries", "Peakline Test", 57, 0.7, 14, 0.3),
            ("Pasta", "Peakline Test", 158, 5.8, 31, 0.9),
            ("Lean Mince", "Peakline Test", 176, 25, 0, 8),
            ("Final Scroll Marker Food", "Peakline Test", 210, 12, 22, 7)
        ]

        for (index, food) in foods.enumerated() {
            context.insert(
                FoodItem(
                    name: food.0,
                    brand: food.1,
                    servingSize: 100,
                    caloriesPer100g: food.2,
                    proteinPer100g: food.3,
                    carbsPer100g: food.4,
                    fatPer100g: food.5,
                    source: .manual,
                    verificationStatus: .userVerified,
                    createdAt: Date().addingTimeInterval(TimeInterval(index)),
                    updatedAt: Date().addingTimeInterval(TimeInterval(index))
                )
            )
        }
    }

    private static func seedSplitsFixture(in context: ModelContext, exercises: [Exercise]) throws {
        let existingSplits = try context.fetch(FetchDescriptor<TrainingSplit>())
        guard !existingSplits.contains(where: { $0.name == "UI Test Other Split" }) else { return }

        let exercise = exercises.first { $0.name == "Bench Press" } ?? exercises.first
        let split = TrainingSplit(
            name: "UI Test Other Split",
            splitType: .custom,
            isActive: false,
            daysPerWeek: 1
        )

        if let exercise {
            let splitExercise = SplitExercise(
                splitId: split.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: 0,
                targetSets: 2,
                minReps: 8,
                maxReps: 12,
                restSeconds: 120,
                notes: "UI test fixture exercise."
            )
            splitExercise.split = split
            split.exercises = [splitExercise]
        }

        context.insert(split)
    }
}
