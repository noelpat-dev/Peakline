import Foundation

struct WorkoutReuseBuilder {
    func previewSplit(from session: WorkoutSession, nameSuffix: String = "Repeat") -> WorkoutPreviewSplit {
        WorkoutPreviewSplit(
            id: session.splitId ?? UUID(),
            name: "\(baseSplitName(session.splitNameSnapshot)) - \(nameSuffix)",
            exercises: session.exerciseLogs
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { log in
                    WorkoutSelectableExercise(
                        id: log.id,
                        exerciseId: log.exerciseId,
                        name: log.exerciseNameSnapshot,
                        targetSets: max(log.targetSets, loggedWorkingSetCount(log)),
                        minReps: log.minReps == 0 ? 8 : log.minReps,
                        maxReps: log.maxReps == 0 ? 12 : log.maxReps,
                        notes: reuseNote(for: log)
                    )
                }
        )
    }

    func previewSplit(from template: CustomWorkoutTemplate) -> WorkoutPreviewSplit {
        WorkoutPreviewSplit(
            id: template.id,
            name: template.name,
            exercises: template.exercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { exercise in
                    WorkoutSelectableExercise(
                        id: exercise.id,
                        exerciseId: exercise.exerciseId ?? exercise.id,
                        name: exercise.exerciseName,
                        targetSets: exercise.plannedSets ?? 2,
                        minReps: exercise.targetRepMin ?? 8,
                        maxReps: exercise.targetRepMax ?? 12,
                        notes: exercise.notes
                    )
                }
        )
    }

    private func loggedWorkingSetCount(_ log: ExerciseLog) -> Int {
        log.setLogs.filter { !$0.isWarmup && ($0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil) }.count
    }

    private func reuseNote(for log: ExerciseLog) -> String? {
        let bestSet = log.setLogs
            .filter { !$0.isWarmup && ($0.completed || $0.weight > 0 || $0.reps > 0) }
            .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }

        let existing = log.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bestSet else { return existing?.isEmpty == false ? existing : nil }

        let suggestion = "Last used: \(format(bestSet.weight))kg x \(bestSet.reps)."
        guard let existing, !existing.isEmpty else { return suggestion }
        return "\(existing)\n\(suggestion)"
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

