import Foundation

struct CoachRecommendationSummary {
    let recommendedSplitName: String?
    let reason: String
    let exerciseRecommendations: [ExerciseRecommendation]
    let recoveryWarnings: [CoachWarning]
    let weeklyInsights: [String]
}

struct ExerciseRecommendation: Identifiable, Hashable {
    let exerciseName: String
    let message: String
    let priority: CoachPriority

    var id: String {
        "\(exerciseName)-\(priority.rawValue)-\(message)"
    }
}

struct CoachWarning: Identifiable, Hashable {
    let title: String
    let message: String
    let severity: CoachPriority

    var id: String {
        "\(title)-\(severity.rawValue)-\(message)"
    }
}

enum CoachPriority: String, Hashable {
    case low
    case medium
    case high
}

struct CoachRecommendationEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeSummary(
        activeSplits: [TrainingSplit],
        completedSessions: [WorkoutSession],
        now: Date = .now
    ) -> CoachRecommendationSummary {
        let recommendedSplit = recommendedSplit(from: activeSplits, completedSessions: completedSessions)
        let warnings = recoveryWarnings(from: completedSessions, now: now)
        let missedWarnings = missedSplitWarnings(activeSplits: activeSplits, completedSessions: completedSessions, now: now)

        return CoachRecommendationSummary(
            recommendedSplitName: recommendedSplit?.name,
            reason: recommendationReason(
                for: recommendedSplit,
                activeSplits: activeSplits,
                completedSessions: completedSessions
            ),
            exerciseRecommendations: exerciseRecommendations(
                for: recommendedSplit,
                completedSessions: completedSessions
            ),
            recoveryWarnings: warnings + missedWarnings,
            weeklyInsights: weeklyInsights(from: completedSessions, now: now)
        )
    }

    private func recommendedSplit(
        from activeSplits: [TrainingSplit],
        completedSessions: [WorkoutSession]
    ) -> TrainingSplit? {
        let orderedSplits = pplOrderedSplits(from: activeSplits)
        guard !orderedSplits.isEmpty else { return activeSplits.first }

        let completedNames = Set(recentPPLCycleNames(from: completedSessions))
        if let missingSplit = orderedSplits.first(where: { !completedNames.contains($0.name) }) {
            return missingSplit
        }

        guard
            let mostRecentName = completedSessions.compactMap({ pplName(for: $0.splitNameSnapshot) }).first,
            let mostRecentIndex = PPLRotation.names.firstIndex(of: mostRecentName)
        else {
            return orderedSplits.first
        }

        let nextName = PPLRotation.names[(mostRecentIndex + 1) % PPLRotation.names.count]
        return orderedSplits.first { $0.name == nextName } ?? orderedSplits.first
    }

    private func recommendationReason(
        for split: TrainingSplit?,
        activeSplits: [TrainingSplit],
        completedSessions: [WorkoutSession]
    ) -> String {
        guard let split else {
            if activeSplits.isEmpty {
                return "Create or activate Push, Pull, and Legs splits before the coach can plan the next session."
            }

            return "Finish a workout so the coach can compare your recent split rotation."
        }

        if completedSessions.isEmpty {
            return "\(split.name) is the first available day in your active Push/Pull/Legs setup."
        }

        if !recentPPLCycleNames(from: completedSessions).contains(split.name) {
            return "\(split.name) is the next missing day in your current Push/Pull/Legs rotation."
        }

        return "You have completed the current Push/Pull/Legs round. \(split.name) starts the next rotation."
    }

    private func exerciseRecommendations(
        for split: TrainingSplit?,
        completedSessions: [WorkoutSession]
    ) -> [ExerciseRecommendation] {
        guard let split else { return [] }

        return split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(6)
            .map { splitExercise in
                recommendation(for: splitExercise, completedSessions: completedSessions)
            }
    }

    private func recommendation(
        for splitExercise: SplitExercise,
        completedSessions: [WorkoutSession]
    ) -> ExerciseRecommendation {
        let previousLogs = completedSessions
            .flatMap(\.exerciseLogs)
            .filter { $0.exerciseId == splitExercise.exerciseId }

        guard let lastLog = previousLogs.first else {
            return ExerciseRecommendation(
                exerciseName: splitExercise.exerciseNameSnapshot,
                message: "Establish a clean baseline in the \(splitExercise.minReps)-\(splitExercise.maxReps) rep range.",
                priority: .low
            )
        }

        let workingSets = completedWorkingSets(from: lastLog)
        guard !workingSets.isEmpty else {
            return ExerciseRecommendation(
                exerciseName: splitExercise.exerciseNameSnapshot,
                message: "Log working sets before changing load.",
                priority: .low
            )
        }

        if isPlateauing(previousLogs: previousLogs, minReps: splitExercise.minReps) {
            return ExerciseRecommendation(
                exerciseName: splitExercise.exerciseNameSnapshot,
                message: "Possible plateau: keep load stable, clean up execution, and aim for one more rep before adding weight.",
                priority: .high
            )
        }

        let bestSet = workingSets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } ?? workingSets[0]
        let allAtTop = workingSets.allSatisfy { $0.reps >= splitExercise.maxReps }
        let anyBelowRange = workingSets.contains { $0.reps < splitExercise.minReps }

        if allAtTop {
            return ExerciseRecommendation(
                exerciseName: splitExercise.exerciseNameSnapshot,
                message: "Add load next time; last best was \(format(bestSet.weight))kg x \(bestSet.reps).",
                priority: .medium
            )
        }

        if anyBelowRange {
            return ExerciseRecommendation(
                exerciseName: splitExercise.exerciseNameSnapshot,
                message: "Repeat or reduce slightly until every working set reaches \(splitExercise.minReps)+ reps.",
                priority: .medium
            )
        }

        return ExerciseRecommendation(
            exerciseName: splitExercise.exerciseNameSnapshot,
            message: "Keep load and add reps toward \(splitExercise.maxReps).",
            priority: .low
        )
    }

    private func recoveryWarnings(
        from completedSessions: [WorkoutSession],
        now: Date
    ) -> [CoachWarning] {
        let recentSessions = completedSessions.filter {
            guard let days = calendar.dateComponents([.day], from: $0.date, to: now).day else { return false }
            return days < 7
        }

        var warnings: [CoachWarning] = []
        let recentWorkingSets = recentSessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
        }

        if recentSessions.count >= 4 {
            warnings.append(
                CoachWarning(
                    title: "High training frequency",
                    message: "You have logged \(recentSessions.count) workouts in the last 7 days. Keep today's session controlled if joints or performance feel off.",
                    severity: .medium
                )
            )
        }

        if recentWorkingSets >= 40 {
            warnings.append(
                CoachWarning(
                    title: "High weekly set count",
                    message: "\(recentWorkingSets) working sets are logged this week. Consider a shorter session if performance drops.",
                    severity: .medium
                )
            )
        }

        if let lastSession = completedSessions.first, calendar.isDateInYesterday(lastSession.date), recentSessions.count >= 3 {
            warnings.append(
                CoachWarning(
                    title: "Watch fatigue",
                    message: "You trained yesterday and have multiple recent sessions. Warm up carefully before pushing load.",
                    severity: .low
                )
            )
        }

        return warnings
    }

    private func missedSplitWarnings(
        activeSplits: [TrainingSplit],
        completedSessions: [WorkoutSession],
        now: Date
    ) -> [CoachWarning] {
        pplOrderedSplits(from: activeSplits).compactMap { split in
            guard let lastSession = completedSessions.first(where: { pplName(for: $0.splitNameSnapshot) == split.name }) else {
                return CoachWarning(
                    title: "\(split.name) has no history yet",
                    message: "Log one \(split.name) workout so the coach can track your rotation.",
                    severity: .low
                )
            }

            let daysAway = calendar.dateComponents([.day], from: lastSession.date, to: now).day ?? 0
            guard daysAway >= 10 else { return nil }

            return CoachWarning(
                title: "\(split.name) is overdue",
                message: "It has been \(daysAway) days since your last \(split.name) session.",
                severity: .medium
            )
        }
    }

    private func weeklyInsights(from completedSessions: [WorkoutSession], now: Date) -> [String] {
        let thisWeeksSessions = completedSessions.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear)
        }

        let workingSets = thisWeeksSessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
        }

        let bestSetVolume = thisWeeksSessions.reduce(0.0) { total, session in
            let sessionBestSetVolume = session.exerciseLogs.reduce(0.0) { exerciseTotal, exerciseLog in
                let bestSet = completedWorkingSets(from: exerciseLog)
                    .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }

                let bestWeight = bestSet?.weight ?? 0
                let bestReps = bestSet?.reps ?? 0
                let exerciseBestSetVolume = bestWeight * Double(bestReps)
                return exerciseTotal + exerciseBestSetVolume
            }

            return total + sessionBestSetVolume
        }

        return [
            "\(thisWeeksSessions.count) completed workouts this week.",
            "\(workingSets) completed working sets this week.",
            "\(format(bestSetVolume))kg best-set volume this week."
        ]
    }

    private func isPlateauing(previousLogs: [ExerciseLog], minReps: Int) -> Bool {
        let bestSets = previousLogs
            .prefix(3)
            .compactMap { completedWorkingSets(from: $0).max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } }

        guard bestSets.count == 3 else { return false }

        let first = bestSets[0]
        let others = bestSets.dropFirst()
        let noLoadIncrease = others.allSatisfy { $0.weight <= first.weight }
        let repsNearFloor = bestSets.allSatisfy { $0.reps <= minReps + 1 }

        return noLoadIncrease && repsNearFloor
    }

    private func completedWorkingSets(from exerciseLog: ExerciseLog) -> [SetLog] {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func pplOrderedSplits(from activeSplits: [TrainingSplit]) -> [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
    }

    private func recentPPLCycleNames(from completedSessions: [WorkoutSession]) -> [String] {
        var names: [String] = []

        for session in completedSessions {
            guard let name = pplName(for: session.splitNameSnapshot) else { continue }

            if names.contains(name) {
                break
            }

            names.append(name)

            if names.count == PPLRotation.names.count {
                break
            }
        }

        return names
    }

    private func pplName(for splitNameSnapshot: String) -> String? {
        PPLRotation.names.first { name in
            splitNameSnapshot == name || splitNameSnapshot.hasPrefix("\(name) - ")
        }
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private enum PPLRotation {
    static let names = ["Push", "Pull", "Legs"]
}
