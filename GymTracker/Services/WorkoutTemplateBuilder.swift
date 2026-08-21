import Foundation

struct WorkoutTemplateBuilder {
    func makeTemplate(from session: WorkoutSession, name: String, notes: String?) -> CustomWorkoutTemplate {
        CustomWorkoutTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceSplitName: baseSplitName(session.splitNameSnapshot),
            sourceWorkoutModeRawValue: workoutMode(from: session.splitNameSnapshot),
            sourceWorkoutStartedAt: session.startedAt,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            exercises: session.exerciseLogs
                .sorted { $0.orderIndex < $1.orderIndex }
                .enumerated()
                .map { index, log in
                    let bestSet = bestWorkingSet(in: log)
                    return CustomWorkoutTemplateExercise(
                        exerciseId: log.exerciseId,
                        exerciseName: log.exerciseNameSnapshot,
                        orderIndex: index,
                        plannedSets: log.targetSets,
                        targetRepMin: log.minReps,
                        targetRepMax: log.maxReps,
                        lastUsedWeight: bestSet?.weight,
                        lastUsedReps: bestSet?.reps,
                        notes: log.notes
                    )
                }
        )
    }

    func defaultName(for session: WorkoutSession) -> String {
        let baseName = baseSplitName(session.splitNameSnapshot)
        if ["Push", "Pull", "Legs"].contains(baseName) {
            return "\(baseName) Template"
        }
        return "Custom Workout"
    }

    private func bestWorkingSet(in log: ExerciseLog) -> SetLog? {
        log.setLogs
            .filter { !$0.isWarmup && ($0.completed || $0.weight > 0 || $0.reps > 0) }
            .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func workoutMode(from snapshot: String) -> String? {
        let pieces = snapshot.components(separatedBy: " - ")
        guard pieces.count > 1 else { return nil }
        return pieces.last
    }
}

