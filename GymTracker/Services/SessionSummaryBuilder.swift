import Foundation

struct SessionSummary {
    let splitName: String
    let durationText: String
    let completedExerciseCount: Int
    let workingSetCount: Int
    let ratingText: String?
    let bestSetImprovements: [String]
    let suggestedNextSplit: String?
    let takeaway: String
}

struct SessionSummaryBuilder {
    func build(
        from session: WorkoutSession,
        completedSessions: [WorkoutSession],
        activeSplits: [TrainingSplit]
    ) -> SessionSummary {
        let workingSets = session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }
        let improvements = bestSetImprovements(for: session, completedSessions: completedSessions)
        let nextSplit = suggestedNextSplit(after: session, activeSplits: activeSplits)

        return SessionSummary(
            splitName: session.splitNameSnapshot,
            durationText: durationText(for: session),
            completedExerciseCount: session.exerciseLogs.filter { !$0.setLogs.filter(\.completed).isEmpty }.count,
            workingSetCount: workingSets.count,
            ratingText: ratingText(for: session.perceivedDifficulty),
            bestSetImprovements: improvements,
            suggestedNextSplit: nextSplit,
            takeaway: takeaway(improvements: improvements, workingSetCount: workingSets.count, rating: session.perceivedDifficulty)
        )
    }

    private func bestSetImprovements(
        for session: WorkoutSession,
        completedSessions: [WorkoutSession]
    ) -> [String] {
        session.exerciseLogs.compactMap { exerciseLog in
            guard let currentBest = bestSet(in: exerciseLog) else { return nil }

            let previousBest = completedSessions
                .filter { $0.id != session.id }
                .flatMap(\.exerciseLogs)
                .filter { $0.exerciseId == exerciseLog.exerciseId }
                .compactMap(bestSet(in:))
                .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }

            guard let previousBest else {
                return "\(exerciseLog.exerciseNameSnapshot): first logged best set at \(format(currentBest.weight))kg x \(currentBest.reps)."
            }

            guard estimatedOneRepMax(currentBest) > estimatedOneRepMax(previousBest) else { return nil }

            return "\(exerciseLog.exerciseNameSnapshot): improved from \(format(previousBest.weight))kg x \(previousBest.reps) to \(format(currentBest.weight))kg x \(currentBest.reps)."
        }
    }

    private func bestSet(in exerciseLog: ExerciseLog) -> SetLog? {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }
    }

    private func suggestedNextSplit(after session: WorkoutSession, activeSplits: [TrainingSplit]) -> String? {
        let names = ["Push", "Pull", "Legs"]
        let splitName = session.splitNameSnapshot.components(separatedBy: " - ").first ?? session.splitNameSnapshot

        guard let currentIndex = names.firstIndex(of: splitName) else {
            return activeSplits.first?.name
        }

        let nextName = names[(currentIndex + 1) % names.count]
        return activeSplits.first { $0.name == nextName }?.name ?? nextName
    }

    private func takeaway(improvements: [String], workingSetCount: Int, rating: Int?) -> String {
        if !improvements.isEmpty {
            return "Progress logged. Keep the next session focused and build from the best sets you earned today."
        }

        if let rating, rating <= 2 {
            return "Work completed on a tougher day. Recover well and keep the next target controlled."
        }

        if workingSetCount >= 12 {
            return "Solid volume banked. The next win is clean execution and one small progression."
        }

        return "Session logged. Keep stacking consistent work and let the targets guide the next lift."
    }

    private func ratingText(for score: Int?) -> String? {
        guard let score else { return nil }

        switch score {
        case 1:
            return "Rough"
        case 2:
            return "Okay"
        case 3:
            return "Good"
        case 4:
            return "Great"
        case 5:
            return "Excellent"
        default:
            return "\(score)/5"
        }
    }

    private func durationText(for session: WorkoutSession) -> String {
        if let durationSeconds = session.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return durationText(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let durationMinutes = session.durationMinutes {
            return "\(durationMinutes)m"
        }

        return "Not recorded"
    }

    private func durationText(seconds totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
