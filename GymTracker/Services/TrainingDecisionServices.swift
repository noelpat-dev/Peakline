import Foundation
import SwiftData

struct TrainingRotationService {
    private static let canonicalNames = ["Push", "Pull", "Legs", "Upper", "Lower"]

    func orderedActiveSplits(_ splits: [TrainingSplit]) -> [TrainingSplit] {
        splits
            .filter(\.isActive)
            .sorted(by: liveSplitPrecedes)
    }

    func orderedSplits(_ splits: [TrainingSplitSnapshot]) -> [TrainingSplitSnapshot] {
        splits.sorted(by: snapshotPrecedes)
    }

    func nextSplit(
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> TrainingSplitSnapshot? {
        let ordered = orderedSplits(activeSplits)
        guard !ordered.isEmpty else { return nil }

        for session in completedSessions
            .filter(isMeaningfulCompletedSession)
            .sorted(by: { $0.date > $1.date }) {
            if let splitId = session.splitId,
               let index = ordered.firstIndex(where: { $0.id == splitId }) {
                return ordered[(index + 1) % ordered.count]
            }

            guard session.splitId == nil else { continue }
            let legacyMatches = ordered.indices.filter { index in
                legacySessionName(session.splitNameSnapshot, matches: ordered[index].name)
            }
            if legacyMatches.count == 1, let index = legacyMatches.first {
                return ordered[(index + 1) % ordered.count]
            }
        }

        return ordered.first
    }

    private func isMeaningfulCompletedSession(_ session: WorkoutAnalyticsSession) -> Bool {
        session.completed && session.exerciseLogs.contains { exercise in
            exercise.setLogs.contains { set in
                set.completed || set.weight > 0 || set.reps > 0
            }
        }
    }

    @MainActor
    func normalizePersistedRotation(in context: ModelContext) throws {
        let splits = try context.fetch(FetchDescriptor<TrainingSplit>())
        let active = splits.filter(\.isActive)

        for split in splits where !split.isActive && split.activeRotationIndex != nil {
            split.activeRotationIndex = nil
            split.updatedAt = .now
        }

        let existingIndexes = active.compactMap(\.activeRotationIndex)
        let isAlreadyNormalised = existingIndexes.count == active.count
            && Set(existingIndexes).count == active.count
            && existingIndexes.sorted() == Array(0..<active.count)
        guard !isAlreadyNormalised else { return }

        for (index, split) in active.sorted(by: liveSplitPrecedes).enumerated() {
            split.activeRotationIndex = index
            split.updatedAt = .now
        }
    }

    @MainActor
    func applyRotation(
        orderedSplitIDs: [UUID],
        to splits: [TrainingSplit],
        in context: ModelContext
    ) throws {
        var seen = Set<UUID>()
        let uniqueIDs = orderedSplitIDs.filter { seen.insert($0).inserted }
        let orderByID = Dictionary(
            uniqueKeysWithValues: uniqueIDs.enumerated().map { ($0.element, $0.offset) }
        )

        for split in splits {
            if let index = orderByID[split.id] {
                split.isActive = true
                split.activeRotationIndex = index
            } else {
                split.isActive = false
                split.activeRotationIndex = nil
            }
            split.updatedAt = .now
        }

        try context.save()
    }

    func displayName(for splits: [TrainingSplit]) -> String {
        orderedActiveSplits(splits).map(\.name).joined(separator: " / ")
    }

    private func liveSplitPrecedes(_ lhs: TrainingSplit, _ rhs: TrainingSplit) -> Bool {
        switch (lhs.activeRotationIndex, rhs.activeRotationIndex) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            let leftRank = canonicalRank(for: lhs.name)
            let rightRank = canonicalRank(for: rhs.name)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func snapshotPrecedes(_ lhs: TrainingSplitSnapshot, _ rhs: TrainingSplitSnapshot) -> Bool {
        switch (lhs.activeRotationIndex, rhs.activeRotationIndex) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            let leftRank = canonicalRank(for: lhs.name)
            let rightRank = canonicalRank(for: rhs.name)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func canonicalRank(for name: String) -> Int {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.canonicalNames.firstIndex {
            baseName.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? Self.canonicalNames.count
    }

    private func legacySessionName(_ snapshot: String, matches splitName: String) -> Bool {
        snapshot.compare(splitName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || snapshot.range(
                of: "\(splitName) - ",
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
    }

}
struct TrainingCallSnapshotBuilder {
    private let targetService = TargetSuggestionService()

    func make(
        decision: TrainingDecision,
        activeSplits: [TrainingSplit],
        completedSessions: [WorkoutSession],
        readiness: ReadinessScore? = nil,
        fatigueRisk: CoachFatigueRisk? = nil,
        targetSuggestions: [TargetSuggestion]? = nil,
        selectedPreviewMode: WorkoutMode? = nil
    ) -> TrainingCallSnapshot {
        make(
            decision: decision,
            activeSplits: activeSplits.map(TrainingSplitSnapshot.init),
            completedSessions: completedSessions.map(WorkoutAnalyticsSession.init),
            readiness: readiness,
            fatigueRisk: fatigueRisk,
            targetSuggestions: targetSuggestions,
            selectedPreviewMode: selectedPreviewMode
        )
    }

    func make(
        decision: TrainingDecision,
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession],
        readiness: ReadinessScore? = nil,
        fatigueRisk: CoachFatigueRisk? = nil,
        targetSuggestions: [TargetSuggestion]? = nil,
        selectedPreviewMode: WorkoutMode? = nil
    ) -> TrainingCallSnapshot {
        let recommendedSplit = activeSplits.first { $0.name == decision.recommendedSplitName }
        let suggestions = targetSuggestions ?? targetSuggestionsForRecommendedSplit(
            recommendedSplit,
            completedSessions: completedSessions
        )
        let primaryTarget = primaryTarget(from: suggestions)
        let missingInputs = missingInputs(
            readiness: readiness,
            completedSessions: completedSessions,
            targetSuggestions: suggestions
        )
        let confidence = readiness?.confidence ?? (completedSessions.count >= 3 ? .medium : .low)
        let guarded = guardedDecision(
            decision: decision,
            confidence: confidence,
            readiness: readiness,
            fatigueRisk: fatigueRisk,
            suggestions: suggestions,
            selectedPreviewMode: selectedPreviewMode,
            completedSessions: completedSessions
        )
        let targetSummary = targetSummary(
            primaryTarget,
            confidence: confidence,
            mode: guarded.mode
        )
        let signals = sourceSignals(
            decision: decision,
            readiness: readiness,
            fatigueRisk: fatigueRisk,
            primaryTarget: primaryTarget,
            completedSessions: completedSessions,
            selectedPreviewMode: selectedPreviewMode
        )

        return TrainingCallSnapshot(
            recommendedSplitName: decision.recommendedSplitName,
            recommendedMode: guarded.mode,
            action: guarded.action,
            title: guarded.title,
            reason: guarded.reason,
            confidence: confidence,
            targetSummary: targetSummary,
            sourceSignals: signals,
            missingOrStaleInputs: missingInputs,
            guardrailNotes: guarded.guardrails,
            isConservative: guarded.isConservative
        )
    }

    private func targetSuggestionsForRecommendedSplit(
        _ split: TrainingSplitSnapshot?,
        completedSessions: [WorkoutAnalyticsSession]
    ) -> [TargetSuggestion] {
        guard let split else { return [] }
        return split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(6)
            .map { exercise in
                targetService.suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
            }
    }

    private func guardedDecision(
        decision: TrainingDecision,
        confidence: ReadinessConfidence,
        readiness: ReadinessScore?,
        fatigueRisk: CoachFatigueRisk?,
        suggestions: [TargetSuggestion],
        selectedPreviewMode: WorkoutMode?,
        completedSessions: [WorkoutAnalyticsSession]
    ) -> (
        mode: WorkoutMode,
        action: TrainingDecisionAction,
        title: String,
        reason: String,
        guardrails: [String],
        isConservative: Bool
    ) {
        var mode = decision.recommendedMode
        var action = decision.action
        var title = decision.title
        var reason = decision.reason
        var guardrails: [String] = []
        var isConservative = false
        let hasPushTarget = suggestions.contains { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }
        let hasFatigueTarget = suggestions.contains { $0.recommendationType == .fatigueRisk || $0.recommendationType == .reduceLoad }
        let readinessCategory = readiness?.category
        let fatigueLevel = fatigueRisk?.level
        let mixedSignals = (readinessCategory == .peak || readinessCategory == .ready)
            && (hasFatigueTarget || fatigueLevel == .moderate || fatigueLevel == .high || fatigueLevel == .deloadWatch)

        if completedSessions.count < 2 {
            mode = .full
            action = .buildBaseline
            title = "Build a baseline"
            reason = "Log a few clean sessions before Peakline pushes load or recovery urgency."
            guardrails.append("Fewer than two completed workouts keeps this call baseline-focused.")
            isConservative = true
        } else if confidence == .low {
            mode = decision.recommendedMode == .recovery ? .full : minStressMode(from: decision.recommendedMode)
            action = decision.action == .buildBaseline ? .buildBaseline : .repeatTarget
            title = action == .buildBaseline ? "Build a baseline" : "Repeat targets"
            reason = "Based on limited recent inputs, repeat known targets and keep the plan controlled."
            guardrails.append("Low confidence blocks heavy mode, load pushes, and strong recovery urgency.")
            isConservative = true
        } else if readinessCategory == .recovery || fatigueLevel == .deloadWatch {
            mode = .recovery
            action = .recover
            title = "Recovery mode makes sense"
            reason = "Recovery and fatigue signals are strong enough to keep today's plan lighter."
            guardrails.append("Recovery evidence is strong, so progression is paused for this call.")
            isConservative = true
        } else if readinessCategory == .low || fatigueLevel == .high || hasFatigueTarget {
            mode = .recovery
            action = .recover
            title = "Keep it controlled"
            reason = "Recent readiness, fatigue, or lift trends point to a controlled session."
            guardrails.append("Fatigue evidence overrides load progression for this call.")
            isConservative = true
        } else if mixedSignals {
            mode = .quick
            action = .repeatTarget
            title = "Mixed signals"
            reason = "Readiness looks useful, but fatigue signals are present. Keep main work and avoid chasing PRs."
            guardrails.append("Mixed readiness and fatigue signals choose the conservative path.")
            isConservative = true
        } else if readinessCategory == .cautious {
            mode = .quick
            action = .repeatTarget
            title = "Keep volume controlled"
            reason = "Readiness is workable but not strong enough for extra target pressure."
            guardrails.append("Cautious readiness trims the call toward main work and repeatable reps.")
            isConservative = true
        } else if hasPushTarget, readinessCategory == .peak, confidence == .high, (fatigueLevel == nil || fatigueLevel == .low) {
            mode = .heavy
            action = .push
            title = "Push one key lift"
            reason = "Readiness is high, fatigue looks manageable, and at least one target is ready to progress."
        } else if hasPushTarget, confidence != .low {
            mode = .full
            action = .push
            title = "Push today"
            reason = "There is a progression target, but the call stays within the normal full session."
        }

        if let selectedPreviewMode, selectedPreviewMode != mode {
            guardrails.append("\(selectedPreviewMode.displayName) mode is selected in Preview, but the coach call remains \(mode.displayName.lowercased()) based on current signals.")
        }

        return (mode, action, title, reason, Array(guardrails.prefix(3)), isConservative)
    }

    private func minStressMode(from mode: WorkoutMode) -> WorkoutMode {
        switch mode {
        case .heavy:
            return .full
        case .recovery:
            return .full
        case .full, .quick:
            return mode
        }
    }

    private func primaryTarget(from suggestions: [TargetSuggestion]) -> TargetSuggestion? {
        suggestions.max { lhs, rhs in
            let leftScore = targetRank(lhs.recommendationType)
            let rightScore = targetRank(rhs.recommendationType)
            if leftScore == rightScore {
                return lhs.confidence < rhs.confidence
            }
            return leftScore < rightScore
        }
    }

    private func targetRank(_ type: TargetRecommendationType) -> Int {
        switch type {
        case .fatigueRisk:
            return 90
        case .increaseLoad:
            return 88
        case .addReps:
            return 82
        case .reduceLoad:
            return 78
        case .possiblePlateau:
            return 74
        case .repeatTarget:
            return 70
        case .ready:
            return 64
        case .baseline:
            return 58
        }
    }

    private func targetSummary(
        _ target: TargetSuggestion?,
        confidence: ReadinessConfidence,
        mode: WorkoutMode
    ) -> String? {
        guard let target else { return nil }
        let targetText = targetDescription(for: target)

        if confidence == .low {
            return "\(target.exerciseName): repeat known work while confidence builds."
        }

        if mode == .recovery {
            return "\(target.exerciseName): keep this controlled rather than chasing progression."
        }

        return "\(target.exerciseName): \(targetText)"
    }

    private func targetDescription(for suggestion: TargetSuggestion) -> String {
        switch (suggestion.suggestedWeight, suggestion.suggestedReps) {
        case let (.some(weight), .some(reps)):
            return "\(format(weight))kg x \(reps)"
        case let (.some(weight), .none):
            return "\(format(weight))kg"
        case let (.none, .some(reps)):
            return "\(reps)+ reps"
        case (.none, .none):
            return "log clean sets"
        }
    }

    private func sourceSignals(
        decision: TrainingDecision,
        readiness: ReadinessScore?,
        fatigueRisk: CoachFatigueRisk?,
        primaryTarget: TargetSuggestion?,
        completedSessions: [WorkoutAnalyticsSession],
        selectedPreviewMode: WorkoutMode?
    ) -> [String] {
        var signals = [decision.reason]

        if let readiness {
            signals.append("Readiness \(readiness.value) - \(readiness.category.displayName), \(readiness.confidence.displayName.lowercased()).")
        }

        if let fatigueRisk {
            signals.append("\(fatigueRisk.title): \(fatigueRisk.summary)")
        }

        if let primaryTarget {
            signals.append("Primary target: \(primaryTarget.reason)")
        }

        if recentSkippedFatigue(in: completedSessions) {
            signals.append("Recent skipped work mentions fatigue or discomfort.")
        }

        if let selectedPreviewMode {
            signals.append("Preview mode selected: \(selectedPreviewMode.displayName).")
        }

        return Array(signals.prefix(5))
    }

    private func missingInputs(
        readiness: ReadinessScore?,
        completedSessions: [WorkoutAnalyticsSession],
        targetSuggestions: [TargetSuggestion]
    ) -> [String] {
        var inputs = readiness?.factors
            .filter { !$0.isDataAvailable }
            .map { "\($0.kind.displayName): missing or stale." } ?? ["Readiness: not available on this surface."]

        if completedSessions.count < 2 {
            inputs.append("Workout history: fewer than two completed sessions.")
        }

        if targetSuggestions.isEmpty {
            inputs.append("Targets: no exercise target history for this call yet.")
        }

        return Array(inputs.prefix(5))
    }

    private func recentSkippedFatigue(in sessions: [WorkoutAnalyticsSession]) -> Bool {
        sessions.prefix(3).contains { session in
            session.exerciseLogs.contains { log in
                let notes = log.notes ?? ""
                return notes.localizedCaseInsensitiveContains("Too fatigued") || notes.localizedCaseInsensitiveContains("Pain / discomfort")
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

struct TrainingDecisionService {
    private let targetService = TargetSuggestionService()
    private let analytics = TrainingAnalyticsService()
    private let rotationService = TrainingRotationService()

    func decision(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> TrainingDecision {
        decision(
            activeSplits: activeSplits.map(TrainingSplitSnapshot.init),
            completedSessions: completedSessions.map(WorkoutAnalyticsSession.init)
        )
    }

    func decision(activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession]) -> TrainingDecision {
        let split = rotationService.nextSplit(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )

        guard completedSessions.count >= 2 else {
            return TrainingDecision(
                recommendedSplitName: split?.name,
                recommendedMode: .full,
                action: .buildBaseline,
                title: "Build a baseline",
                reason: "Log clean sets so Peakline can make better targets."
            )
        }

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

    func weeklyBalanceContext(activeSplits: [TrainingSplitSnapshot], completedSessions: [WorkoutAnalyticsSession]) -> String? {
        let consistency = analytics.splitConsistency(
            from: completedSessions,
            activeSplitNames: rotationService.orderedSplits(activeSplits).map(\.name)
        )
        guard
            let missed = consistency.missedSplitName,
            activeSplits.contains(where: { $0.name == missed })
        else {
            return nil
        }

        return "\(missed) is lowest in this week's balance, but the daily call is following the active programme rotation."
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
