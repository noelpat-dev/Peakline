import SwiftData
import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            CoachContentView()
        }
    }
}

struct CoachContentView: View {
    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    var body: some View {
        List {
            Section("Recommendation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendedSplitName)
                        .font(.headline)
                    Text(recommendationReason)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("This Week") {
                LabeledContent("Completed workouts", value: "\(workoutsThisWeek)")
                LabeledContent("Working sets", value: "\(workingSetsThisWeek)")
                LabeledContent("Total volume", value: "\(format(totalVolumeThisWeek))kg")
            }

            Section("Progressive Overload") {
                if overloadRecommendations.isEmpty {
                    Text("Complete a workout from your split to get load and rep targets.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(overloadRecommendations, id: \.self) { recommendation in
                        Text(recommendation)
                    }
                }
            }

            Section("Recent Training") {
                if completedSessions.isEmpty {
                    Text("Finish a workout to unlock set-by-set recommendations.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedSessions.prefix(5)) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.splitNameSnapshot)
                                .font(.headline)
                            Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            Text("\(completedSetCount(for: session)) completed sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Coach")
    }

    private var recommendedSplitName: String {
        guard let split = recommendedSplit else {
            return completedSessions.isEmpty ? "Log your first workout" : "Create an active split"
        }

        return "Suggested today: \(split.name)"
    }

    private var recommendationReason: String {
        guard let split = recommendedSplit else {
            if activeSplits.isEmpty {
                return "Active split templates are needed before the coach can suggest what to train next."
            }

            return "Once you have workout history, the coach will compare how recently each split was trained."
        }

        if !recentPPLCycleNames.contains(split.name) {
            return "\(split.name) is the next missing day in your current Push/Pull/Legs rotation."
        }

        return "You have completed the current Push/Pull/Legs round. \(split.name) starts the next rotation."
    }

    private var recommendedSplit: TrainingSplit? {
        let orderedSplits = pplOrderedSplits
        guard !orderedSplits.isEmpty else { return activeSplits.first }

        let completedNames = Set(recentPPLCycleNames)
        if let missingSplit = orderedSplits.first(where: { !completedNames.contains($0.name) }) {
            return missingSplit
        }

        guard
            let mostRecentName = completedSessions.first(where: { PPLRotation.names.contains($0.splitNameSnapshot) })?.splitNameSnapshot,
            let mostRecentIndex = PPLRotation.names.firstIndex(of: mostRecentName)
        else {
            return orderedSplits.first
        }

        let nextName = PPLRotation.names[(mostRecentIndex + 1) % PPLRotation.names.count]
        return orderedSplits.first { $0.name == nextName } ?? orderedSplits.first
    }

    private var overloadRecommendations: [String] {
        guard let split = recommendedSplit else { return [] }

        return split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { recommendation(for: $0) }
            .prefix(5)
            .map { $0 }
    }

    private var workoutsThisWeek: Int {
        completedSessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private var workingSetsThisWeek: Int {
        thisWeeksSessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
        }
    }

    private var totalVolumeThisWeek: Double {
        thisWeeksSessions.reduce(0) { total, session in
            total + session.exerciseLogs
                .flatMap(\.setLogs)
                .filter { $0.completed && !$0.isWarmup }
                .reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }

    private var thisWeeksSessions: [WorkoutSession] {
        completedSessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    private var pplOrderedSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
    }

    private var recentPPLCycleNames: [String] {
        var names: [String] = []

        for session in completedSessions where PPLRotation.names.contains(session.splitNameSnapshot) {
            if names.contains(session.splitNameSnapshot) {
                break
            }

            names.append(session.splitNameSnapshot)

            if names.count == PPLRotation.names.count {
                break
            }
        }

        return names
    }

    private func completedSetCount(for session: WorkoutSession) -> Int {
        session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
    }

    private func recommendation(for splitExercise: SplitExercise) -> String? {
        guard let lastLog = latestCompletedLog(for: splitExercise) else {
            return "\(splitExercise.exerciseNameSnapshot): establish baseline in \(splitExercise.minReps)-\(splitExercise.maxReps) reps."
        }

        let workingSets = lastLog.setLogs.filter { $0.completed && !$0.isWarmup }
        guard !workingSets.isEmpty else {
            return "\(splitExercise.exerciseNameSnapshot): log working sets before changing load."
        }

        let bestSet = workingSets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } ?? workingSets[0]
        let allAtTop = workingSets.allSatisfy { $0.reps >= splitExercise.maxReps }
        let anyBelowRange = workingSets.contains { $0.reps < splitExercise.minReps }

        if allAtTop {
            return "\(splitExercise.exerciseNameSnapshot): add load next time; last best was \(format(bestSet.weight))kg x \(bestSet.reps)."
        }

        if anyBelowRange {
            return "\(splitExercise.exerciseNameSnapshot): repeat or reduce slightly until all sets reach \(splitExercise.minReps)+ reps."
        }

        return "\(splitExercise.exerciseNameSnapshot): keep load and add reps toward \(splitExercise.maxReps)."
    }

    private func latestCompletedLog(for splitExercise: SplitExercise) -> ExerciseLog? {
        completedSessions
            .flatMap(\.exerciseLogs)
            .first { $0.exerciseId == splitExercise.exerciseId }
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
