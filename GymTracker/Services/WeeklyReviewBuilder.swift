import Foundation
import SwiftData

struct TrainingSplitSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let activeRotationIndex: Int?
    let exercises: [SplitExerciseSnapshot]

    init(
        id: UUID,
        name: String,
        updatedAt: Date,
        activeRotationIndex: Int? = nil,
        exercises: [SplitExerciseSnapshot]
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.activeRotationIndex = activeRotationIndex
        self.exercises = exercises
    }

    init(split: TrainingSplit) {
        self.id = split.id
        self.name = split.name
        self.updatedAt = split.updatedAt
        self.activeRotationIndex = split.activeRotationIndex
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
                activeRotationIndex: split.activeRotationIndex,
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

struct TrainingCallSnapshot: Equatable, Sendable {
    let recommendedSplitName: String?
    let recommendedMode: WorkoutMode
    let action: TrainingDecisionAction
    let title: String
    let reason: String
    let confidence: ReadinessConfidence
    let targetSummary: String?
    let sourceSignals: [String]
    let missingOrStaleInputs: [String]
    let guardrailNotes: [String]
    let isConservative: Bool

    var headline: String {
        guard let recommendedSplitName else { return title }
        return "\(recommendedSplitName) - \(recommendedMode.displayName)"
    }

    var auditSignals: [String] {
        Array((sourceSignals + guardrailNotes).prefix(5))
    }

    static let placeholder = TrainingCallSnapshot(
        recommendedSplitName: nil,
        recommendedMode: .full,
        action: .buildBaseline,
        title: "Preparing training call",
        reason: "Peakline is preparing the latest local training call.",
        confidence: .low,
        targetSummary: nil,
        sourceSignals: ["Recent workout history is being checked."],
        missingOrStaleInputs: ["Readiness inputs are still loading."],
        guardrailNotes: ["Limited data keeps this call conservative."],
        isConservative: true
    )
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
        let orderedActiveSplits = TrainingRotationService().orderedSplits(activeSplits)
        let consistency = analytics.splitConsistency(
            from: completedSessions,
            activeSplitNames: orderedActiveSplits.map(\.name)
        )
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

