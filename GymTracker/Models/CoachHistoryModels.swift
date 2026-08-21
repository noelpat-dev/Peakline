import Foundation
import SwiftData

@Model
final class CoachActionHistoryEntry {
    @Attribute(.unique) var id: UUID
    var actionRawValue: String
    var outcomeRawValue: String
    var createdAt: Date
    var readinessCategoryRawValue: String
    var fatigueRiskRawValue: String
    var confidenceRawValue: String
    var shortReason: String
    var workoutName: String?
    var splitName: String?
    var beforeTotalSets: Int
    var afterTotalSets: Int
    var contributingSignals: [String]
    var diagnosticSummary: String?

    init(
        id: UUID = UUID(),
        action: CoachWorkoutAdjustmentAction,
        outcome: CoachActionHistoryOutcome,
        createdAt: Date = .now,
        readinessCategory: ReadinessCategory,
        fatigueRiskLevel: CoachFatigueRiskLevel,
        confidence: ReadinessConfidence,
        shortReason: String,
        workoutName: String? = nil,
        splitName: String? = nil,
        beforeTotalSets: Int = 0,
        afterTotalSets: Int = 0,
        contributingSignals: [String] = [],
        diagnosticSummary: String? = nil
    ) {
        self.id = id
        self.actionRawValue = action.rawValue
        self.outcomeRawValue = outcome.rawValue
        self.createdAt = createdAt
        self.readinessCategoryRawValue = readinessCategory.rawValue
        self.fatigueRiskRawValue = fatigueRiskLevel.rawValue
        self.confidenceRawValue = confidence.rawValue
        self.shortReason = shortReason
        self.workoutName = workoutName
        self.splitName = splitName
        self.beforeTotalSets = beforeTotalSets
        self.afterTotalSets = afterTotalSets
        self.contributingSignals = contributingSignals
        self.diagnosticSummary = diagnosticSummary
    }

    var action: CoachWorkoutAdjustmentAction {
        CoachWorkoutAdjustmentAction(rawValue: actionRawValue) ?? .keepPlan
    }

    var outcome: CoachActionHistoryOutcome {
        CoachActionHistoryOutcome(rawValue: outcomeRawValue) ?? .cancelled
    }

    var readinessCategory: ReadinessCategory {
        ReadinessCategory(rawValue: readinessCategoryRawValue) ?? .ready
    }

    var fatigueRiskLevel: CoachFatigueRiskLevel {
        CoachFatigueRiskLevel(rawValue: fatigueRiskRawValue) ?? .low
    }

    var confidence: ReadinessConfidence {
        ReadinessConfidence(rawValue: confidenceRawValue) ?? .low
    }
}

@Model
final class SavedCoachDeloadBlock {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var startsAt: Date
    var endsAt: Date
    var durationRawValue: String
    var volumeReductionRawValue: String
    var focusRawValue: String
    var stateRawValue: String
    var reason: String
    var splitName: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        startsAt: Date = .now,
        endsAt: Date,
        duration: ManualDeloadDuration,
        volumeReduction: ManualDeloadVolumeReduction,
        focus: ManualDeloadFocus,
        state: CoachDeloadBlockState = .active,
        reason: String,
        splitName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.durationRawValue = duration.rawValue
        self.volumeReductionRawValue = volumeReduction.rawValue
        self.focusRawValue = focus.rawValue
        self.stateRawValue = state.rawValue
        self.reason = reason
        self.splitName = splitName
    }

    var duration: ManualDeloadDuration {
        ManualDeloadDuration(rawValue: durationRawValue) ?? .fiveDays
    }

    var volumeReduction: ManualDeloadVolumeReduction {
        ManualDeloadVolumeReduction(rawValue: volumeReductionRawValue) ?? .twentyFivePercent
    }

    var focus: ManualDeloadFocus {
        ManualDeloadFocus(rawValue: focusRawValue) ?? .maintainFrequency
    }

    var state: CoachDeloadBlockState {
        get { CoachDeloadBlockState(rawValue: stateRawValue) ?? .active }
        set {
            stateRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var plan: ManualDeloadPlan {
        ManualDeloadPlan(duration: duration, volumeReduction: volumeReduction, focus: focus)
    }
}

@Model
final class CoachRecommendationFeedback {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var historyEntryId: UUID?
    var actionRawValue: String?
    var feedbackRawValues: [String]
    var note: String?
    var splitName: String?
    var readinessCategoryRawValue: String?
    var fatigueRiskRawValue: String?
    var confidenceRawValue: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        historyEntryId: UUID? = nil,
        action: CoachWorkoutAdjustmentAction? = nil,
        tags: [CoachRecommendationFeedbackTag],
        note: String? = nil,
        splitName: String? = nil,
        readinessCategory: ReadinessCategory? = nil,
        fatigueRiskLevel: CoachFatigueRiskLevel? = nil,
        confidence: ReadinessConfidence? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.historyEntryId = historyEntryId
        self.actionRawValue = action?.rawValue
        self.feedbackRawValues = tags.map(\.rawValue)
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.splitName = splitName
        self.readinessCategoryRawValue = readinessCategory?.rawValue
        self.fatigueRiskRawValue = fatigueRiskLevel?.rawValue
        self.confidenceRawValue = confidence?.rawValue
    }

    var action: CoachWorkoutAdjustmentAction? {
        guard let actionRawValue else { return nil }
        return CoachWorkoutAdjustmentAction(rawValue: actionRawValue)
    }

    var tags: [CoachRecommendationFeedbackTag] {
        feedbackRawValues.compactMap(CoachRecommendationFeedbackTag.init(rawValue:))
    }

    var readinessCategory: ReadinessCategory? {
        guard let readinessCategoryRawValue else { return nil }
        return ReadinessCategory(rawValue: readinessCategoryRawValue)
    }

    var fatigueRiskLevel: CoachFatigueRiskLevel? {
        guard let fatigueRiskRawValue else { return nil }
        return CoachFatigueRiskLevel(rawValue: fatigueRiskRawValue)
    }

    var confidence: ReadinessConfidence? {
        guard let confidenceRawValue else { return nil }
        return ReadinessConfidence(rawValue: confidenceRawValue)
    }
}
