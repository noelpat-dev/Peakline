import Foundation

enum SkippedExerciseReason: String, CaseIterable, Identifiable {
    case noTime
    case equipmentBusy
    case tooFatigued
    case painOrDiscomfort
    case notNeededToday
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noTime:
            return "No time"
        case .equipmentBusy:
            return "Equipment busy"
        case .tooFatigued:
            return "Too fatigued"
        case .painOrDiscomfort:
            return "Pain / discomfort"
        case .notNeededToday:
            return "Not needed today"
        case .other:
            return "Other"
        }
    }
}

struct SkippedExerciseReasonService {
    func append(reason: SkippedExerciseReason, to exerciseLog: ExerciseLog) {
        let note = "[Skipped: \(reason.displayName)]"
        append(note, to: exerciseLog)
    }

    func skippedLogs(in session: WorkoutSession) -> [ExerciseLog] {
        session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { log in
                log.setLogs.allSatisfy { !$0.completed && $0.weight == 0 && $0.reps == 0 && $0.rpe == nil }
            }
    }

    private func append(_ text: String, to exerciseLog: ExerciseLog) {
        let existing = exerciseLog.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !existing.localizedCaseInsensitiveContains(text) else { return }
        exerciseLog.notes = existing.isEmpty ? text : "\(existing)\n\(text)"
    }
}

