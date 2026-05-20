import Foundation

struct SplitTemplateUpdateService {
    func replaceOrder(of split: TrainingSplit, with session: WorkoutSession) {
        let orderedLogs = session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
        guard !orderedLogs.isEmpty else { return }

        for (index, log) in orderedLogs.enumerated() {
            if let existing = split.exercises.first(where: { $0.exerciseId == log.exerciseId || $0.exerciseNameSnapshot == log.exerciseNameSnapshot }) {
                existing.orderIndex = index
                existing.exerciseId = log.exerciseId
                existing.exerciseNameSnapshot = log.exerciseNameSnapshot
                existing.targetSets = max(1, log.targetSets)
                existing.minReps = log.minReps == 0 ? existing.minReps : log.minReps
                existing.maxReps = log.maxReps == 0 ? existing.maxReps : log.maxReps
                existing.notes = mergedNotes(template: existing.notes, session: log.notes)
            } else {
                let splitExercise = SplitExercise(
                    splitId: split.id,
                    exerciseId: log.exerciseId,
                    exerciseNameSnapshot: log.exerciseNameSnapshot,
                    orderIndex: index,
                    targetSets: max(1, log.targetSets),
                    minReps: log.minReps == 0 ? 8 : log.minReps,
                    maxReps: log.maxReps == 0 ? 12 : log.maxReps,
                    restSeconds: nil,
                    notes: log.notes
                )
                splitExercise.split = split
                split.exercises.append(splitExercise)
            }
        }

        split.updatedAt = Date()
    }

    private func mergedNotes(template: String?, session: String?) -> String? {
        let template = template?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let session = session?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !template.isEmpty else { return session.isEmpty ? nil : session }
        guard !session.isEmpty, !template.localizedCaseInsensitiveContains(session) else { return template }
        return "\(template)\n\(session)"
    }
}
