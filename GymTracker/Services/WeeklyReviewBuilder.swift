import Foundation
import SwiftData

struct TrainingSplitSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let exercises: [SplitExerciseSnapshot]

    init(id: UUID, name: String, updatedAt: Date, exercises: [SplitExerciseSnapshot]) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.exercises = exercises
    }

    init(split: TrainingSplit) {
        self.id = split.id
        self.name = split.name
        self.updatedAt = split.updatedAt
        self.exercises = split.exercises.map(SplitExerciseSnapshot.init)
    }
}

struct SplitExerciseSnapshot: Sendable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let exerciseNameSnapshot: String
    let orderIndex: Int
    let minReps: Int
    let maxReps: Int

    init(id: UUID, exerciseId: UUID, exerciseNameSnapshot: String, orderIndex: Int, minReps: Int, maxReps: Int) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.orderIndex = orderIndex
        self.minReps = minReps
        self.maxReps = maxReps
    }

    init(splitExercise: SplitExercise) {
        self.id = splitExercise.id
        self.exerciseId = splitExercise.exerciseId
        self.exerciseNameSnapshot = splitExercise.exerciseNameSnapshot
        self.orderIndex = splitExercise.orderIndex
        self.minReps = splitExercise.minReps
        self.maxReps = splitExercise.maxReps
    }
}

enum TrainingSplitSnapshotBuilder {
    @MainActor
    static func snapshots(from splits: [TrainingSplit], in modelContext: ModelContext) throws -> [TrainingSplitSnapshot] {
        guard !splits.isEmpty else { return [] }

        let splitIds = splits.map(\.id)
        var exerciseDescriptor = FetchDescriptor<SplitExercise>(
            predicate: #Predicate<SplitExercise> { splitIds.contains($0.splitId) },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        exerciseDescriptor.includePendingChanges = true

        let exercises = try modelContext.fetch(exerciseDescriptor)
        let exercisesBySplitId = Dictionary(grouping: exercises, by: \.splitId)

        return splits.map { split in
            let exerciseSnapshots = (exercisesBySplitId[split.id] ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { exercise in
                    SplitExerciseSnapshot(
                        id: exercise.id,
                        exerciseId: exercise.exerciseId,
                        exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                        orderIndex: exercise.orderIndex,
                        minReps: exercise.minReps,
                        maxReps: exercise.maxReps
                    )
                }

            return TrainingSplitSnapshot(
                id: split.id,
                name: split.name,
                updatedAt: split.updatedAt,
                exercises: exerciseSnapshots
            )
        }
    }
}

struct WeeklyReview: Equatable, Sendable {
    let title: String
    let dateRangeDescription: String
    let completedWorkouts: Int
    let workingSets: Int
    let prCount: Int
    let splitConsistency: SplitConsistencySummary
    let highlights: [CoachInsight]
    let watchlist: [CoachInsight]
    let nextDecision: TrainingDecision
}

struct CoachInsight: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
    let severity: CoachInsightSeverity
    let relatedExerciseName: String?
    let relatedSplitName: String?

    init(
        id: String? = nil,
        title: String,
        message: String,
        severity: CoachInsightSeverity,
        relatedExerciseName: String?,
        relatedSplitName: String?
    ) {
        self.title = title
        self.message = message
        self.severity = severity
        self.relatedExerciseName = relatedExerciseName
        self.relatedSplitName = relatedSplitName
        self.id = id ?? [
            title,
            message,
            severity.rawValue,
            relatedExerciseName ?? "",
            relatedSplitName ?? ""
        ].joined(separator: "|")
    }
}

enum CoachInsightSeverity: String, Codable, Sendable {
    case info
    case positive
    case warning
    case recovery
}

struct TrainingDecision: Equatable, Sendable {
    let recommendedSplitName: String?
    let recommendedMode: WorkoutMode
    let action: TrainingDecisionAction
    let title: String
    let reason: String
}

enum TrainingDecisionAction: String, Codable, Sendable {
    case push
    case repeatTarget
    case recover
    case rebalance
    case buildBaseline

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .repeatTarget:
            return "Repeat"
        case .recover:
            return "Recover"
        case .rebalance:
            return "Rebalance"
        case .buildBaseline:
            return "Build baseline"
        }
    }
}

struct WeeklyReviewBuilder {
    private let analytics = TrainingAnalyticsService()
    private let targetService = TargetSuggestionService()

    func build(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> WeeklyReview {
        build(
            activeSplits: activeSplits.map(TrainingSplitSnapshot.init),
            completedSessions: completedSessions.map(WorkoutAnalyticsSession.init)
        )
    }

    func build(activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession]) -> WeeklyReview {
        let prRecords = analytics.prTimeline(from: completedSessions)
        let weekly = analytics.weeklySummary(from: completedSessions, prRecords: prRecords)
        let consistency = analytics.splitConsistency(from: completedSessions)
        let decision = TrainingDecisionService().decision(activeSplits: activeSplits, completedSessions: completedSessions)
        let recentPRs = prRecords.prefix(3)

        let highlights = recentPRs.map { pr in
            CoachInsight(
                title: pr.exerciseName,
                message: pr.improvementDescription,
                severity: .positive,
                relatedExerciseName: pr.exerciseName,
                relatedSplitName: pr.workoutSplitName
            )
        }

        let watchlist = makeWatchlist(activeSplits: activeSplits, completedSessions: completedSessions, consistency: consistency)

        return WeeklyReview(
            title: "This Week Review",
            dateRangeDescription: "\(weekly.weekStart.formatted(date: .abbreviated, time: .omitted)) - \(weekly.weekEnd.formatted(date: .abbreviated, time: .omitted))",
            completedWorkouts: weekly.completedWorkouts,
            workingSets: weekly.workingSets,
            prCount: weekly.prCount,
            splitConsistency: consistency,
            highlights: highlights,
            watchlist: watchlist,
            nextDecision: decision
        )
    }

    private func makeWatchlist(activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession], consistency: SplitConsistencySummary) -> [CoachInsight] {
        var insights: [CoachInsight] = []

        if let missed = consistency.missedSplitName {
            insights.append(
                CoachInsight(
                    title: "\(missed) due",
                    message: "Rebalance your week with \(missed) next.",
                    severity: .warning,
                    relatedExerciseName: nil,
                    relatedSplitName: missed
                )
            )
        }

        for split in activeSplits {
            for exercise in split.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }).prefix(4) {
                let suggestion = targetService.suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
                if suggestion.recommendationType == .fatigueRisk || suggestion.recommendationType == .possiblePlateau {
                    insights.append(
                        CoachInsight(
                            title: suggestion.exerciseName,
                            message: suggestion.reason,
                            severity: suggestion.recommendationType == .fatigueRisk ? .recovery : .warning,
                            relatedExerciseName: suggestion.exerciseName,
                            relatedSplitName: split.name
                        )
                    )
                }
            }
        }

        return Array(insights.prefix(5))
    }
}

struct TrainingDecisionService {
    private let targetService = TargetSuggestionService()
    private let analytics = TrainingAnalyticsService()

    func decision(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> TrainingDecision {
        decision(
            activeSplits: activeSplits.map(TrainingSplitSnapshot.init),
            completedSessions: completedSessions.map(WorkoutAnalyticsSession.init)
        )
    }

    func decision(activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession]) -> TrainingDecision {
        guard completedSessions.count >= 2 else {
            return TrainingDecision(
                recommendedSplitName: activeSplits.first?.name,
                recommendedMode: .full,
                action: .buildBaseline,
                title: "Build a baseline",
                reason: "Log clean sets so Peakline can make better targets."
            )
        }

        let consistency = analytics.splitConsistency(from: completedSessions)
        if let missed = consistency.missedSplitName, let split = activeSplits.first(where: { $0.name == missed }) {
            return TrainingDecision(
                recommendedSplitName: split.name,
                recommendedMode: .full,
                action: .rebalance,
                title: "Rebalance with \(split.name)",
                reason: "\(split.name) has not been trained this week."
            )
        }

        let split = recommendedSplit(from: activeSplits, completedSessions: completedSessions)
        let suggestions = split?.exercises.map {
            targetService.suggestion(
                exerciseId: $0.exerciseId,
                exerciseName: $0.exerciseNameSnapshot,
                minReps: $0.minReps,
                maxReps: $0.maxReps,
                completedSessions: completedSessions
            )
        } ?? []

        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) || recentSkippedFatigue(in: completedSessions) {
            return TrainingDecision(
                recommendedSplitName: split?.name,
                recommendedMode: .recovery,
                action: .recover,
                title: "Recovery mode makes sense",
                reason: "Recent logs show fatigue risk or skipped work. Keep form clean and avoid forcing PRs."
            )
        }

        if suggestions.contains(where: { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }) {
            return TrainingDecision(
                recommendedSplitName: split?.name,
                recommendedMode: .full,
                action: .push,
                title: "Push today",
                reason: "There are clear progression opportunities and no major drop-off on this split."
            )
        }

        return TrainingDecision(
            recommendedSplitName: split?.name,
            recommendedMode: .full,
            action: .repeatTarget,
            title: "Repeat targets",
            reason: "Aim for cleaner reps or one extra rep where possible."
        )
    }

    private func recommendedSplit(from activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession]) -> TrainingSplitSnapshot? {
        let orderedSplits = PPLReviewRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
        guard !orderedSplits.isEmpty else { return activeSplits.first }

        let completedNames = Set(recentPPLCycleNames(from: completedSessions))
        if let missingSplit = orderedSplits.first(where: { !completedNames.contains($0.name) }) {
            return missingSplit
        }

        guard
            let mostRecentName = completedSessions.compactMap({ pplName(for: $0.splitNameSnapshot) }).first,
            let mostRecentIndex = PPLReviewRotation.names.firstIndex(of: mostRecentName)
        else {
            return orderedSplits.first
        }

        let nextName = PPLReviewRotation.names[(mostRecentIndex + 1) % PPLReviewRotation.names.count]
        return orderedSplits.first { $0.name == nextName } ?? orderedSplits.first
    }

    private func recentPPLCycleNames(from completedSessions: [WorkoutAnalyticsSession]) -> [String] {
        var names: [String] = []

        for session in completedSessions {
            guard let name = pplName(for: session.splitNameSnapshot) else { continue }

            if names.contains(name) {
                break
            }

            names.append(name)

            if names.count == PPLReviewRotation.names.count {
                break
            }
        }

        return names
    }

    private func pplName(for splitNameSnapshot: String) -> String? {
        PPLReviewRotation.names.first { name in
            splitNameSnapshot == name || splitNameSnapshot.hasPrefix("\(name) - ")
        }
    }

    private func recentSkippedFatigue(in sessions: [WorkoutAnalyticsSession]) -> Bool {
        sessions.prefix(3).contains { session in
            session.exerciseLogs.contains { log in
                let notes = log.notes ?? ""
                return notes.localizedCaseInsensitiveContains("Too fatigued") || notes.localizedCaseInsensitiveContains("Pain / discomfort")
            }
        }
    }
}

private enum PPLReviewRotation {
    static let names = ["Push", "Pull", "Legs"]
}
