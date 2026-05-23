import Foundation

struct TargetSuggestion: Hashable, Sendable {
    let exerciseName: String
    let lastBestSetDescription: String?
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let recommendationType: TargetRecommendationType
    let reason: String
    let confidence: Double
}

enum TargetRecommendationType: String, Codable, CaseIterable, Hashable, Sendable {
    case baseline
    case addReps
    case repeatTarget
    case increaseLoad
    case reduceLoad
    case possiblePlateau
    case fatigueRisk
    case ready
}

struct TargetSuggestionService {
    func suggestion(
        for splitExercise: SplitExercise,
        completedSessions: [WorkoutSession]
    ) -> TargetSuggestion {
        suggestion(
            exerciseId: splitExercise.exerciseId,
            exerciseName: splitExercise.exerciseNameSnapshot,
            minReps: splitExercise.minReps,
            maxReps: splitExercise.maxReps,
            completedSessions: completedSessions
        )
    }

    func suggestion(
        exerciseId: UUID,
        exerciseName: String,
        minReps: Int,
        maxReps: Int,
        completedSessions: [WorkoutSession]
    ) -> TargetSuggestion {
        suggestion(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            minReps: minReps,
            maxReps: maxReps,
            completedSessions: completedSessions.map(WorkoutAnalyticsSession.init)
        )
    }

    func suggestion(
        exerciseId: UUID,
        exerciseName: String,
        minReps: Int,
        maxReps: Int,
        completedSessions: [WorkoutAnalyticsSession]
    ) -> TargetSuggestion {
        let history = exerciseHistory(exerciseId: exerciseId, completedSessions: completedSessions)

        guard let latest = history.first else {
            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: nil,
                suggestedWeight: nil,
                suggestedReps: minReps,
                recommendationType: .baseline,
                reason: "No history yet. Establish a controlled baseline in the \(minReps)-\(maxReps) rep range.",
                confidence: 0.45
            )
        }

        let latestWorkingSets = completedWorkingSets(from: latest.log)
        guard !latestWorkingSets.isEmpty else {
            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: nil,
                suggestedWeight: nil,
                suggestedReps: minReps,
                recommendationType: .baseline,
                reason: "The last workout has no completed working sets. Log clean sets before changing load.",
                confidence: 0.5
            )
        }

        let bestSet = bestCompletedSet(from: latestWorkingSets)
        let bestDescription = "\(format(bestSet.weight))kg x \(bestSet.reps)"
        let recentBestSets = history
            .prefix(3)
            .compactMap { entry -> SetAnalyticsLog? in
                let sets = completedWorkingSets(from: entry.log)
                return sets.isEmpty ? nil : bestCompletedSet(from: sets)
            }

        if performanceDropped(in: recentBestSets) {
            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: bestDescription,
                suggestedWeight: bestSet.weight,
                suggestedReps: max(minReps, bestSet.reps),
                recommendationType: .fatigueRisk,
                reason: "Recent best sets are trending down. Repeat the load and keep the session controlled.",
                confidence: 0.7
            )
        }

        if possiblePlateau(in: recentBestSets) {
            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: bestDescription,
                suggestedWeight: bestSet.weight,
                suggestedReps: min(maxReps, bestSet.reps + 1),
                recommendationType: .possiblePlateau,
                reason: "Progress has been flat across recent appearances. Aim for one cleaner rep before adding load.",
                confidence: 0.68
            )
        }

        let allAtTop = latestWorkingSets.allSatisfy { $0.reps >= maxReps }
        let anyBelowRange = latestWorkingSets.contains { $0.reps < minReps }

        if allAtTop, bestSet.weight > 0 {
            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: bestDescription,
                suggestedWeight: bestSet.weight + 2.5,
                suggestedReps: minReps,
                recommendationType: .increaseLoad,
                reason: "You reached the top of the rep range. Add a small load jump and rebuild from \(minReps) reps.",
                confidence: 0.78
            )
        }

        if anyBelowRange {
            let type: TargetRecommendationType = bestSet.reps < max(1, minReps - 2) ? .reduceLoad : .repeatTarget
            let suggestedWeight = type == .reduceLoad ? max(0, bestSet.weight - 2.5) : bestSet.weight
            let reason = type == .reduceLoad
                ? "Last time fell well below the rep floor. Reduce slightly and rebuild clean reps."
                : "Some sets missed the rep floor. Repeat the load until every working set reaches \(minReps)+ reps."

            return TargetSuggestion(
                exerciseName: exerciseName,
                lastBestSetDescription: bestDescription,
                suggestedWeight: suggestedWeight,
                suggestedReps: minReps,
                recommendationType: type,
                reason: reason,
                confidence: 0.72
            )
        }

        return TargetSuggestion(
            exerciseName: exerciseName,
            lastBestSetDescription: bestDescription,
            suggestedWeight: bestSet.weight,
            suggestedReps: min(maxReps, bestSet.reps + 1),
            recommendationType: .addReps,
            reason: "Load is in range. Keep it steady and push reps toward \(maxReps).",
            confidence: 0.74
        )
    }

    private func exerciseHistory(
        exerciseId: UUID,
        completedSessions: [WorkoutSession]
    ) -> [(date: Date, log: ExerciseLog)] {
        var history: [(date: Date, log: ExerciseLog)] = []

        for session in completedSessions {
            for log in session.exerciseLogs where log.exerciseId == exerciseId {
                history.append((date: session.date, log: log))

                if history.count == 3 {
                    return history.sorted { $0.date > $1.date }
                }
            }
        }

        return history.sorted { $0.date > $1.date }
    }

    private func exerciseHistory(
        exerciseId: UUID,
        completedSessions: [WorkoutAnalyticsSession]
    ) -> [(date: Date, log: ExerciseAnalyticsLog)] {
        var history: [(date: Date, log: ExerciseAnalyticsLog)] = []

        for session in completedSessions {
            for log in session.exerciseLogs where log.exerciseId == exerciseId {
                history.append((date: session.date, log: log))

                if history.count == 3 {
                    return history.sorted { $0.date > $1.date }
                }
            }
        }

        return history.sorted { $0.date > $1.date }
    }

    private func completedWorkingSets(from exerciseLog: ExerciseLog) -> [SetLog] {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func completedWorkingSets(from exerciseLog: ExerciseAnalyticsLog) -> [SetAnalyticsLog] {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func bestCompletedSet(from sets: [SetLog]) -> SetLog {
        sets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } ?? sets[0]
    }

    private func bestCompletedSet(from sets: [SetAnalyticsLog]) -> SetAnalyticsLog {
        sets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } ?? sets[0]
    }

    private func performanceDropped(in sets: [SetLog]) -> Bool {
        guard sets.count == 3 else { return false }
        let scores = sets.map(estimatedOneRepMax)
        return scores[0] < scores[1] && scores[1] < scores[2]
    }

    private func performanceDropped(in sets: [SetAnalyticsLog]) -> Bool {
        guard sets.count == 3 else { return false }
        let scores = sets.map(estimatedOneRepMax)
        return scores[0] < scores[1] && scores[1] < scores[2]
    }

    private func possiblePlateau(in sets: [SetLog]) -> Bool {
        guard sets.count == 3 else { return false }
        let scores = sets.map(estimatedOneRepMax)
        let newest = scores[0]
        let bestOlder = scores.dropFirst().max() ?? newest
        let loadHasNotMoved = sets.allSatisfy { $0.weight <= sets[0].weight }
        return newest <= bestOlder && loadHasNotMoved
    }

    private func possiblePlateau(in sets: [SetAnalyticsLog]) -> Bool {
        guard sets.count == 3 else { return false }
        let scores = sets.map(estimatedOneRepMax)
        let newest = scores[0]
        let bestOlder = scores.dropFirst().max() ?? newest
        let loadHasNotMoved = sets.allSatisfy { $0.weight <= sets[0].weight }
        return newest <= bestOlder && loadHasNotMoved
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func estimatedOneRepMax(_ set: SetAnalyticsLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
