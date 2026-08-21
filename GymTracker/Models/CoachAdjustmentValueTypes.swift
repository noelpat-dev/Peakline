import Foundation
import SwiftData

struct ManualDeloadPlan: Hashable {
    let duration: ManualDeloadDuration
    let volumeReduction: ManualDeloadVolumeReduction
    let focus: ManualDeloadFocus

    var title: String {
        "\(duration.displayName) deload"
    }

    var summary: String {
        switch focus {
        case .lowerVolume:
            return "Use about \(volumeReduction.displayName) less volume while keeping normal movement patterns."
        case .techniqueOnly:
            return "Keep effort low and use this block to reinforce clean reps."
        case .maintainFrequency:
            return "Keep your normal training rhythm, but lower effort and total sets."
        }
    }
}

struct CoachExerciseClassification: Hashable {
    let role: CoachExerciseRole
    let reason: String
    let source: CoachExerciseMetadataSource

    init(
        role: CoachExerciseRole,
        reason: String,
        source: CoachExerciseMetadataSource = .fallbackSlot
    ) {
        self.role = role
        self.reason = reason
        self.source = source
    }
}

struct CoachWorkoutActionRecommendation: Identifiable, Hashable {
    var id: CoachWorkoutAdjustmentAction { action }
    let action: CoachWorkoutAdjustmentAction
    let title: String
    let summary: String
    let isCoachSuggested: Bool
    let confidence: ReadinessConfidence
    let calibrationNote: String?
}

struct CoachWorkoutExerciseAdjustment: Identifiable, Hashable {
    var id: UUID { plannedExerciseId }
    let plannedExerciseId: UUID
    let exerciseId: UUID
    let name: String
    let beforeSets: Int
    let afterSets: Int
    let beforeNotes: String?
    let afterNotes: String?
    let reason: String

    var changed: Bool {
        beforeSets != afterSets || beforeNotes != afterNotes
    }
}

struct EditableCoachWorkoutExerciseAdjustment: Identifiable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let beforeSets: Int
    let suggestedSets: Int
    let beforeNotes: String?
    let suggestedNotes: String?
    let reason: String
    var editedSets: Int
    var editedNotes: String

    var editedNotesValue: String? {
        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var changedFromOriginal: Bool {
        beforeSets != editedSets || normalized(beforeNotes) != normalized(editedNotesValue)
    }

    var changedFromSuggestion: Bool {
        suggestedSets != editedSets || normalized(suggestedNotes) != normalized(editedNotesValue)
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct EditableCoachWorkoutAdjustmentDraft: Hashable {
    let basePreview: CoachWorkoutAdjustmentPreview
    var exerciseAdjustments: [EditableCoachWorkoutExerciseAdjustment]

    var beforeTotalSets: Int {
        basePreview.beforeTotalSets
    }

    var afterTotalSets: Int {
        exerciseAdjustments.reduce(0) { $0 + $1.editedSets }
    }

    var changedExerciseCount: Int {
        exerciseAdjustments.filter(\.changedFromOriginal).count
    }

    var hasWorkoutChanges: Bool {
        changedExerciseCount > 0
    }

    var hasUserEdits: Bool {
        exerciseAdjustments.contains(where: \.changedFromSuggestion)
    }
}

struct CoachWorkoutAdjustmentPreview: Identifiable, Hashable {
    let id: String
    let action: CoachWorkoutAdjustmentAction
    let deloadPlan: ManualDeloadPlan?
    let title: String
    let summary: String
    let confidence: ReadinessConfidence
    let whySuggested: String
    let contributingSignals: [String]
    let changes: [String]
    let unchanged: [String]
    let beforeExerciseCount: Int
    let afterExerciseCount: Int
    let beforeTotalSets: Int
    let afterTotalSets: Int
    let exerciseAdjustments: [CoachWorkoutExerciseAdjustment]
    let adjustedExercises: [PlannedWorkoutExercise]

    var changedExerciseAdjustments: [CoachWorkoutExerciseAdjustment] {
        exerciseAdjustments.filter(\.changed)
    }

    var hasWorkoutChanges: Bool {
        beforeTotalSets != afterTotalSets || !changedExerciseAdjustments.isEmpty
    }
}

struct CoachPreferencesSnapshot: Hashable {
    var aggressiveness: CoachAggressiveness
    var deloadWording: CoachDeloadWording
    var detailLevel: CoachDetailLevel
    var trainingPriority: CoachTrainingPriority
    var reductionPreference: CoachReductionPreference
    var recommendationFrequency: CoachRecommendationFrequency
    var showDiagnostics: Bool

    static let `default` = CoachPreferencesSnapshot(
        aggressiveness: .balanced,
        deloadWording: .gentle,
        detailLevel: .standard,
        trainingPriority: .balanced,
        reductionPreference: .protectPriorityLifts,
        recommendationFrequency: .standard,
        showDiagnostics: false
    )
}

struct CoachSplitMetadataSnapshot: Hashable {
    var splitId: UUID
    var splitName: String
    var priority: CoachSplitPriority
    var plannedIntensity: CoachPlannedIntensity
    var primaryGoal: CoachSplitGoal
    var expectedFatigue: CoachExpectedFatigue
    var protectCompounds: Bool
    var accessoriesFlexible: Bool
    var preferredAdjustmentStyle: CoachPreferredAdjustmentStyle
    var userNote: String?

    static func defaultFor(splitId: UUID, splitName: String) -> CoachSplitMetadataSnapshot {
        CoachSplitMetadataSnapshot(
            splitId: splitId,
            splitName: splitName,
            priority: .normal,
            plannedIntensity: .moderate,
            primaryGoal: .hypertrophy,
            expectedFatigue: .moderate,
            protectCompounds: true,
            accessoriesFlexible: true,
            preferredAdjustmentStyle: .protectMainLifts,
            userNote: nil
        )
    }
}

struct CoachCalibrationContext {
    let actionHistory: [CoachActionHistoryEntry]
    let feedback: [CoachRecommendationFeedback]
    let deloadBlocks: [SavedCoachDeloadBlock]
    let exerciseMetadata: [CoachExerciseMetadata]
    let preferences: CoachPreferencesSnapshot
    let splitMetadata: CoachSplitMetadataSnapshot?

    init(
        actionHistory: [CoachActionHistoryEntry],
        feedback: [CoachRecommendationFeedback],
        deloadBlocks: [SavedCoachDeloadBlock],
        exerciseMetadata: [CoachExerciseMetadata]
    ) {
        self.init(
            actionHistory: actionHistory,
            feedback: feedback,
            deloadBlocks: deloadBlocks,
            exerciseMetadata: exerciseMetadata,
            preferences: .default,
            splitMetadata: nil
        )
    }

    init(
        actionHistory: [CoachActionHistoryEntry],
        feedback: [CoachRecommendationFeedback],
        deloadBlocks: [SavedCoachDeloadBlock],
        exerciseMetadata: [CoachExerciseMetadata],
        preferences: CoachPreferencesSnapshot,
        splitMetadata: CoachSplitMetadataSnapshot? = nil
    ) {
        self.actionHistory = actionHistory
        self.feedback = feedback
        self.deloadBlocks = deloadBlocks
        self.exerciseMetadata = exerciseMetadata
        self.preferences = preferences
        self.splitMetadata = splitMetadata
    }

    static let empty = CoachCalibrationContext(
        actionHistory: [],
        feedback: [],
        deloadBlocks: [],
        exerciseMetadata: []
    )

    var recentFeedback: [CoachRecommendationFeedback] {
        Array(feedback.sorted { $0.createdAt > $1.createdAt }.prefix(20))
    }

    var activeDeloadBlocks: [SavedCoachDeloadBlock] {
        deloadBlocks.filter { $0.state == .active }
    }
}

struct CoachCalibrationResult: Hashable {
    let summarySuffix: String?
    let confidence: ReadinessConfidence
    let reason: String?
}

struct CoachActionHistoryFilter: Hashable {
    var outcome: CoachActionHistoryOutcome?
    var action: CoachWorkoutAdjustmentAction?
    var splitName: String?
    var readinessCategory: ReadinessCategory?
    var fatigueRiskLevel: CoachFatigueRiskLevel?

    static let empty = CoachActionHistoryFilter()

    var isActive: Bool {
        outcome != nil
            || action != nil
            || splitName != nil
            || readinessCategory != nil
            || fatigueRiskLevel != nil
    }
}

struct AppliedCoachWorkoutAdjustment: Identifiable, Hashable {
    let id = UUID()
    let preview: CoachWorkoutAdjustmentPreview

    var title: String { preview.action.displayName }
    var adjustedExercises: [PlannedWorkoutExercise] { preview.adjustedExercises }
}

struct CoachBulkMetadataUpdate: Hashable {
    var role: CoachExerciseMetadataRole?
    var priority: CoachExercisePriorityLevel?
    var primaryMuscleGroup: MuscleGroup?
    var secondaryMuscleGroups: [MuscleGroup]?
    var splitClassification: CoachSplitClassification?
    var movementPattern: MovementPattern?

    init(
        role: CoachExerciseMetadataRole? = nil,
        priority: CoachExercisePriorityLevel? = nil,
        primaryMuscleGroup: MuscleGroup? = nil,
        secondaryMuscleGroups: [MuscleGroup]? = nil,
        splitClassification: CoachSplitClassification? = nil,
        movementPattern: MovementPattern? = nil
    ) {
        self.role = role
        self.priority = priority
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.splitClassification = splitClassification
        self.movementPattern = movementPattern
    }

    var changedFieldNames: [String] {
        var names: [String] = []
        if role != nil { names.append("role") }
        if priority != nil { names.append("priority") }
        if primaryMuscleGroup != nil { names.append("primary muscle") }
        if secondaryMuscleGroups != nil { names.append("secondary muscles") }
        if splitClassification != nil { names.append("PPL context") }
        if movementPattern != nil { names.append("movement pattern") }
        return names
    }

    var hasChanges: Bool {
        changedFieldNames.isEmpty == false
    }
}

struct CoachBulkMetadataReview: Hashable {
    let scope: CoachBulkMetadataScope
    let matchedExerciseIds: [UUID]
    let matchedExerciseNames: [String]
    let changedFieldNames: [String]
    let willCreateCount: Int
    let willUpdateCount: Int
    let skippedExistingCount: Int

    var summary: String {
        let count = matchedExerciseIds.count
        let fieldText = changedFieldNames.isEmpty ? "No metadata fields" : changedFieldNames.joined(separator: ", ")
        return "\(fieldText) will be applied to \(count) exercise\(count == 1 ? "" : "s")."
    }
}

struct CoachWorkoutChangeExplanation: Hashable {
    let originalTotalSets: Int
    let adjustedTotalSets: Int
    let exercisesChanged: [String]
    let exercisesProtected: [String]
    let exercisesReduced: [String]
    let mainReason: String
    let readinessFatigueSignals: [String]
    let preferenceInfluence: String?
    let metadataInfluence: String?
    let confidence: ReadinessConfidence
}

struct CoachExerciseMetadataDraft: Hashable {
    var role: CoachExerciseMetadataRole
    var primaryMuscleGroup: MuscleGroup
    var secondaryMuscleGroups: [MuscleGroup]
    var movementPattern: MovementPattern
    var splitClassification: CoachSplitClassification
    var priority: CoachExercisePriorityLevel
    var userNote: String

    init(
        role: CoachExerciseMetadataRole,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup],
        movementPattern: MovementPattern,
        splitClassification: CoachSplitClassification,
        priority: CoachExercisePriorityLevel,
        userNote: String
    ) {
        self.role = role
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.splitClassification = splitClassification
        self.priority = priority
        self.userNote = userNote
    }

    init(exercise: Exercise, metadata: CoachExerciseMetadata? = nil) {
        self.role = metadata?.role ?? (exercise.isCompound ? .compound : .isolation)
        self.primaryMuscleGroup = metadata?.primaryMuscleGroup ?? exercise.primaryMuscleGroup
        self.secondaryMuscleGroups = metadata?.secondaryMuscleGroups ?? exercise.secondaryMuscleGroups
        self.movementPattern = metadata?.movementPattern ?? exercise.movementPattern
        self.splitClassification = metadata?.splitClassification ?? .unspecified
        self.priority = metadata?.priority ?? .normal
        self.userNote = metadata?.userNote ?? ""
    }
}

struct CoachDeloadCalendarPreview: Hashable {
    let plan: ManualDeloadPlan
    let startsAt: Date
    let endsAt: Date
    let estimatedAffectedTrainingDays: Int
    let volumeSummary: String
    let focusExplanation: String
    let affectedSplitNames: [String]
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
