import Foundation

struct WorkoutCSVExporter {
    func makeCSV(from workouts: [WorkoutSession]) -> String {
        let header = [
            "Date",
            "Split",
            "Workout Mode",
            "Exercise",
            "Set Number",
            "Weight",
            "Reps",
            "RPE",
            "Completed",
            "Duration Seconds",
            "Rating"
        ].joined(separator: ",")

        let rows = workouts
            .sorted { $0.date < $1.date }
            .flatMap(rows)

        return ([header] + rows).joined(separator: "\n")
    }

    private func rows(for session: WorkoutSession) -> [String] {
        session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .flatMap { exerciseLog in
                exerciseLog.setLogs
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { setLog in
                        csvRow(session: session, exerciseLog: exerciseLog, setLog: setLog)
                    }
            }
    }

    private func csvRow(session: WorkoutSession, exerciseLog: ExerciseLog, setLog: SetLog) -> String {
        [
            csv(session.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))),
            csv(baseSplitName(session.splitNameSnapshot)),
            csv(workoutMode(from: session.splitNameSnapshot) ?? ""),
            csv(exerciseLog.exerciseNameSnapshot),
            csv("\(setLog.setNumber)"),
            csv(format(setLog.weight)),
            csv("\(setLog.reps)"),
            csv(setLog.rpe.map(format) ?? ""),
            csv(setLog.completed ? "true" : "false"),
            csv(session.durationSeconds.map(String.init) ?? ""),
            csv(session.perceivedDifficulty.map(String.init) ?? "")
        ].joined(separator: ",")
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func workoutMode(from snapshot: String) -> String? {
        let pieces = snapshot.components(separatedBy: " - ")
        guard pieces.count > 1 else { return nil }
        return pieces.last
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
