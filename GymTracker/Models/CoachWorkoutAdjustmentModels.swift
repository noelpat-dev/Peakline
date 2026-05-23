import Foundation
import SwiftData

enum CoachWorkoutAdjustmentAction: String, CaseIterable, Identifiable, Hashable {
    case keepPlan
    case reduceAccessories
    case reduceTotalVolume
    case techniqueFocus
    case avoidPRAttempts
    case recoveryFocusedSession
    case deloadStyleSession

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keepPlan:
            return "Keep plan"
        case .reduceAccessories:
            return "Reduce accessories"
        case .reduceTotalVolume:
            return "Reduce total volume"
        case .techniqueFocus:
            return "Technique focus"
        case .avoidPRAttempts:
            return "Avoid PR attempts"
        case .recoveryFocusedSession:
            return "Recovery-focused session"
        case .deloadStyleSession:
            return "Deload-style session"
        }
    }

    var systemImage: String {
        switch self {
        case .keepPlan:
            return "checkmark.circle"
        case .reduceAccessories:
            return "minus.circle"
        case .reduceTotalVolume:
            return "chart.bar.fill"
        case .techniqueFocus:
            return "scope"
        case .avoidPRAttempts:
            return "shield"
        case .recoveryFocusedSession:
            return "leaf"
        case .deloadStyleSession:
            return "arrow.down.forward.circle"
        }
    }
}

enum CoachExerciseMetadataRole: String, CaseIterable, Identifiable, Hashable, Codable {
    case priorityLift
    case compound
    case accessory
    case isolation
    case warmUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .priorityLift:
            return "Priority lift"
        case .compound:
            return "Compound"
        case .accessory:
            return "Accessory"
        case .isolation:
            return "Isolation"
        case .warmUp:
            return "Warm-up"
        }
    }

    var exerciseRole: CoachExerciseRole {
        switch self {
        case .priorityLift:
            return .priorityLift
        case .compound:
            return .primaryCompound
        case .accessory:
            return .accessory
        case .isolation:
            return .isolation
        case .warmUp:
            return .warmUpOrLowPriority
        }
    }
}

enum CoachExercisePriorityLevel: String, CaseIterable, Identifiable, Hashable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }
}

enum CoachSplitClassification: String, CaseIterable, Identifiable, Hashable, Codable {
    case unspecified
    case push
    case pull
    case legs
    case fullBody

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified:
            return "Any"
        case .push:
            return "Push"
        case .pull:
            return "Pull"
        case .legs:
            return "Legs"
        case .fullBody:
            return "Full body"
        }
    }
}

enum CoachAggressiveness: String, CaseIterable, Identifiable, Hashable, Codable {
    case conservative
    case balanced
    case assertive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative:
            return "Conservative"
        case .balanced:
            return "Balanced"
        case .assertive:
            return "Assertive"
        }
    }
}

enum CoachDeloadWording: String, CaseIterable, Identifiable, Hashable, Codable {
    case gentle
    case direct
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle:
            return "Gentle"
        case .direct:
            return "Direct"
        case .minimal:
            return "Minimal"
        }
    }
}

enum CoachDetailLevel: String, CaseIterable, Identifiable, Hashable, Codable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .standard:
            return "Standard"
        case .detailed:
            return "Detailed"
        }
    }
}

enum CoachTrainingPriority: String, CaseIterable, Identifiable, Hashable, Codable {
    case strength
    case hypertrophy
    case recovery
    case consistency
    case balanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength:
            return "Strength"
        case .hypertrophy:
            return "Hypertrophy"
        case .recovery:
            return "Recovery"
        case .consistency:
            return "Consistency"
        case .balanced:
            return "Balanced"
        }
    }
}

enum CoachReductionPreference: String, CaseIterable, Identifiable, Hashable, Codable {
    case reduceAccessoriesFirst
    case reduceTotalVolumeEvenly
    case protectPriorityLifts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reduceAccessoriesFirst:
            return "Accessories first"
        case .reduceTotalVolumeEvenly:
            return "Even reduction"
        case .protectPriorityLifts:
            return "Protect priority lifts"
        }
    }
}

enum CoachRecommendationFrequency: String, CaseIterable, Identifiable, Hashable, Codable {
    case minimal
    case standard
    case proactive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal:
            return "Minimal"
        case .standard:
            return "Standard"
        case .proactive:
            return "Proactive"
        }
    }
}

enum CoachSplitPriority: String, CaseIterable, Identifiable, Hashable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }
}

enum CoachPlannedIntensity: String, CaseIterable, Identifiable, Hashable, Codable {
    case light
    case moderate
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:
            return "Light"
        case .moderate:
            return "Moderate"
        case .hard:
            return "Hard"
        }
    }
}

enum CoachSplitGoal: String, CaseIterable, Identifiable, Hashable, Codable {
    case strength
    case hypertrophy
    case recovery
    case maintenance
    case technique

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength:
            return "Strength"
        case .hypertrophy:
            return "Hypertrophy"
        case .recovery:
            return "Recovery"
        case .maintenance:
            return "Maintenance"
        case .technique:
            return "Technique"
        }
    }
}

enum CoachExpectedFatigue: String, CaseIterable, Identifiable, Hashable, Codable {
    case low
    case moderate
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        }
    }
}

enum CoachPreferredAdjustmentStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    case reduceAccessoriesFirst
    case reduceVolumeEvenly
    case techniqueFocus
    case protectMainLifts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reduceAccessoriesFirst:
            return "Accessories first"
        case .reduceVolumeEvenly:
            return "Even reduction"
        case .techniqueFocus:
            return "Technique focus"
        case .protectMainLifts:
            return "Protect main lifts"
        }
    }
}

enum CoachExerciseMetadataSource: String, CaseIterable, Identifiable, Hashable, Codable {
    case userMetadata
    case exerciseLibrary
    case fallbackName
    case fallbackSlot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .userMetadata:
            return "User metadata"
        case .exerciseLibrary:
            return "Exercise library"
        case .fallbackName:
            return "Name fallback"
        case .fallbackSlot:
            return "Slot fallback"
        }
    }
}

enum CoachRecommendationFeedbackTag: String, CaseIterable, Identifiable, Hashable, Codable {
    case helpful
    case notHelpful
    case tooAggressive
    case tooConservative
    case feltAccurate
    case feltInaccurate
    case ignoredIntentionally
    case pushedThroughAnyway
    case preferredRecovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .helpful:
            return "Helpful"
        case .notHelpful:
            return "Not helpful"
        case .tooAggressive:
            return "Too aggressive"
        case .tooConservative:
            return "Too conservative"
        case .feltAccurate:
            return "Felt accurate"
        case .feltInaccurate:
            return "Felt inaccurate"
        case .ignoredIntentionally:
            return "Ignored intentionally"
        case .pushedThroughAnyway:
            return "Pushed through anyway"
        case .preferredRecovery:
            return "Preferred recovery"
        }
    }
}

enum CoachActionHistoryOutcome: String, CaseIterable, Identifiable, Hashable, Codable {
    case applied
    case cancelled
    case reset
    case bypassed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applied:
            return "Applied"
        case .cancelled:
            return "Cancelled"
        case .reset:
            return "Reset"
        case .bypassed:
            return "Bypassed"
        }
    }

    var systemImage: String {
        switch self {
        case .applied:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle"
        case .reset:
            return "arrow.counterclockwise"
        case .bypassed:
            return "arrow.uturn.backward.circle"
        }
    }
}

enum ManualDeloadDuration: String, CaseIterable, Identifiable, Hashable {
    case threeDays
    case fiveDays
    case sevenDays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeDays:
            return "3 days"
        case .fiveDays:
            return "5 days"
        case .sevenDays:
            return "7 days"
        }
    }

    var dayCount: Int {
        switch self {
        case .threeDays:
            return 3
        case .fiveDays:
            return 5
        case .sevenDays:
            return 7
        }
    }
}

enum ManualDeloadVolumeReduction: String, CaseIterable, Identifiable, Hashable {
    case twentyFivePercent
    case fortyPercent
    case techniqueOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twentyFivePercent:
            return "25%"
        case .fortyPercent:
            return "40%"
        case .techniqueOnly:
            return "Technique only"
        }
    }

    var multiplier: Double {
        switch self {
        case .twentyFivePercent:
            return 0.75
        case .fortyPercent:
            return 0.60
        case .techniqueOnly:
            return 0.50
        }
    }
}

enum ManualDeloadFocus: String, CaseIterable, Identifiable, Hashable {
    case lowerVolume
    case techniqueOnly
    case maintainFrequency

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lowerVolume:
            return "Lower volume"
        case .techniqueOnly:
            return "Technique only"
        case .maintainFrequency:
            return "Maintain frequency"
        }
    }
}

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

enum CoachDeloadBlockState: String, CaseIterable, Identifiable, Hashable, Codable {
    case active
    case completed
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .active:
            return "clock.badge.checkmark"
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }
}

enum CoachExerciseRole: String, CaseIterable, Identifiable, Hashable {
    case priorityLift
    case primaryCompound
    case secondaryCompound
    case accessory
    case isolation
    case warmUpOrLowPriority

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .priorityLift:
            return "Priority lift"
        case .primaryCompound:
            return "Primary compound"
        case .secondaryCompound:
            return "Secondary compound"
        case .accessory:
            return "Accessory"
        case .isolation:
            return "Isolation"
        case .warmUpOrLowPriority:
            return "Warm-up / low priority"
        }
    }

    var receivesAccessoryReduction: Bool {
        switch self {
        case .priorityLift:
            return false
        case .accessory, .isolation, .warmUpOrLowPriority:
            return true
        case .primaryCompound, .secondaryCompound:
            return false
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

enum CoachBulkMetadataScope: String, CaseIterable, Identifiable, Hashable {
    case selectedExercises
    case muscleGroup
    case splitClassification
    case accessories
    case isolation
    case priorityLifts
    case warmUps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectedExercises:
            return "Selected"
        case .muscleGroup:
            return "Muscle group"
        case .splitClassification:
            return "PPL category"
        case .accessories:
            return "Accessories"
        case .isolation:
            return "Isolation"
        case .priorityLifts:
            return "Priority lifts"
        case .warmUps:
            return "Warm-ups"
        }
    }
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

@Model
final class CoachPreferences {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var aggressivenessRawValue: String
    var deloadWordingRawValue: String
    var detailLevelRawValue: String
    var trainingPriorityRawValue: String
    var reductionPreferenceRawValue: String
    var recommendationFrequencyRawValue: String
    var showDiagnostics: Bool

    init(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000601") ?? UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        aggressiveness: CoachAggressiveness = .balanced,
        deloadWording: CoachDeloadWording = .gentle,
        detailLevel: CoachDetailLevel = .standard,
        trainingPriority: CoachTrainingPriority = .balanced,
        reductionPreference: CoachReductionPreference = .protectPriorityLifts,
        recommendationFrequency: CoachRecommendationFrequency = .standard,
        showDiagnostics: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aggressivenessRawValue = aggressiveness.rawValue
        self.deloadWordingRawValue = deloadWording.rawValue
        self.detailLevelRawValue = detailLevel.rawValue
        self.trainingPriorityRawValue = trainingPriority.rawValue
        self.reductionPreferenceRawValue = reductionPreference.rawValue
        self.recommendationFrequencyRawValue = recommendationFrequency.rawValue
        self.showDiagnostics = showDiagnostics
    }

    var aggressiveness: CoachAggressiveness {
        get { CoachAggressiveness(rawValue: aggressivenessRawValue) ?? .balanced }
        set {
            aggressivenessRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var deloadWording: CoachDeloadWording {
        get { CoachDeloadWording(rawValue: deloadWordingRawValue) ?? .gentle }
        set {
            deloadWordingRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var detailLevel: CoachDetailLevel {
        get { CoachDetailLevel(rawValue: detailLevelRawValue) ?? .standard }
        set {
            detailLevelRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var trainingPriority: CoachTrainingPriority {
        get { CoachTrainingPriority(rawValue: trainingPriorityRawValue) ?? .balanced }
        set {
            trainingPriorityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var reductionPreference: CoachReductionPreference {
        get { CoachReductionPreference(rawValue: reductionPreferenceRawValue) ?? .protectPriorityLifts }
        set {
            reductionPreferenceRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var recommendationFrequency: CoachRecommendationFrequency {
        get { CoachRecommendationFrequency(rawValue: recommendationFrequencyRawValue) ?? .standard }
        set {
            recommendationFrequencyRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var snapshot: CoachPreferencesSnapshot {
        CoachPreferencesSnapshot(
            aggressiveness: aggressiveness,
            deloadWording: deloadWording,
            detailLevel: detailLevel,
            trainingPriority: trainingPriority,
            reductionPreference: reductionPreference,
            recommendationFrequency: recommendationFrequency,
            showDiagnostics: showDiagnostics
        )
    }

    func update(from snapshot: CoachPreferencesSnapshot) {
        aggressivenessRawValue = snapshot.aggressiveness.rawValue
        deloadWordingRawValue = snapshot.deloadWording.rawValue
        detailLevelRawValue = snapshot.detailLevel.rawValue
        trainingPriorityRawValue = snapshot.trainingPriority.rawValue
        reductionPreferenceRawValue = snapshot.reductionPreference.rawValue
        recommendationFrequencyRawValue = snapshot.recommendationFrequency.rawValue
        showDiagnostics = snapshot.showDiagnostics
        updatedAt = .now
    }
}

@Model
final class CoachSplitMetadata {
    @Attribute(.unique) var id: UUID
    var splitId: UUID
    var splitName: String
    var createdAt: Date
    var updatedAt: Date
    var priorityRawValue: String
    var plannedIntensityRawValue: String
    var primaryGoalRawValue: String
    var expectedFatigueRawValue: String
    var protectCompounds: Bool
    var accessoriesFlexible: Bool
    var preferredAdjustmentStyleRawValue: String
    var userNote: String?

    init(
        id: UUID = UUID(),
        splitId: UUID,
        splitName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        priority: CoachSplitPriority = .normal,
        plannedIntensity: CoachPlannedIntensity = .moderate,
        primaryGoal: CoachSplitGoal = .hypertrophy,
        expectedFatigue: CoachExpectedFatigue = .moderate,
        protectCompounds: Bool = true,
        accessoriesFlexible: Bool = true,
        preferredAdjustmentStyle: CoachPreferredAdjustmentStyle = .protectMainLifts,
        userNote: String? = nil
    ) {
        self.id = id
        self.splitId = splitId
        self.splitName = splitName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.priorityRawValue = priority.rawValue
        self.plannedIntensityRawValue = plannedIntensity.rawValue
        self.primaryGoalRawValue = primaryGoal.rawValue
        self.expectedFatigueRawValue = expectedFatigue.rawValue
        self.protectCompounds = protectCompounds
        self.accessoriesFlexible = accessoriesFlexible
        self.preferredAdjustmentStyleRawValue = preferredAdjustmentStyle.rawValue
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var priority: CoachSplitPriority {
        get { CoachSplitPriority(rawValue: priorityRawValue) ?? .normal }
        set {
            priorityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var plannedIntensity: CoachPlannedIntensity {
        get { CoachPlannedIntensity(rawValue: plannedIntensityRawValue) ?? .moderate }
        set {
            plannedIntensityRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var primaryGoal: CoachSplitGoal {
        get { CoachSplitGoal(rawValue: primaryGoalRawValue) ?? .hypertrophy }
        set {
            primaryGoalRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var expectedFatigue: CoachExpectedFatigue {
        get { CoachExpectedFatigue(rawValue: expectedFatigueRawValue) ?? .moderate }
        set {
            expectedFatigueRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var preferredAdjustmentStyle: CoachPreferredAdjustmentStyle {
        get { CoachPreferredAdjustmentStyle(rawValue: preferredAdjustmentStyleRawValue) ?? .protectMainLifts }
        set {
            preferredAdjustmentStyleRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var snapshot: CoachSplitMetadataSnapshot {
        CoachSplitMetadataSnapshot(
            splitId: splitId,
            splitName: splitName,
            priority: priority,
            plannedIntensity: plannedIntensity,
            primaryGoal: primaryGoal,
            expectedFatigue: expectedFatigue,
            protectCompounds: protectCompounds,
            accessoriesFlexible: accessoriesFlexible,
            preferredAdjustmentStyle: preferredAdjustmentStyle,
            userNote: userNote
        )
    }

    func update(from snapshot: CoachSplitMetadataSnapshot) {
        splitId = snapshot.splitId
        splitName = snapshot.splitName
        priorityRawValue = snapshot.priority.rawValue
        plannedIntensityRawValue = snapshot.plannedIntensity.rawValue
        primaryGoalRawValue = snapshot.primaryGoal.rawValue
        expectedFatigueRawValue = snapshot.expectedFatigue.rawValue
        protectCompounds = snapshot.protectCompounds
        accessoriesFlexible = snapshot.accessoriesFlexible
        preferredAdjustmentStyleRawValue = snapshot.preferredAdjustmentStyle.rawValue
        userNote = snapshot.userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = .now
    }
}

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
final class CoachExerciseMetadata {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date
    var roleRawValue: String
    var primaryMuscleGroupRawValue: String
    var secondaryMuscleGroupRawValues: [String]
    var movementPatternRawValue: String
    var splitClassificationRawValue: String
    var priorityRawValue: String
    var userNote: String?

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        role: CoachExerciseMetadataRole,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        movementPattern: MovementPattern,
        splitClassification: CoachSplitClassification = .unspecified,
        priority: CoachExercisePriorityLevel = .normal,
        userNote: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.roleRawValue = role.rawValue
        self.primaryMuscleGroupRawValue = primaryMuscleGroup.rawValue
        self.secondaryMuscleGroupRawValues = secondaryMuscleGroups.map(\.rawValue)
        self.movementPatternRawValue = movementPattern.rawValue
        self.splitClassificationRawValue = splitClassification.rawValue
        self.priorityRawValue = priority.rawValue
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var role: CoachExerciseMetadataRole {
        get { CoachExerciseMetadataRole(rawValue: roleRawValue) ?? .compound }
        set { roleRawValue = newValue.rawValue }
    }

    var primaryMuscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleGroupRawValue) ?? .other }
        set { primaryMuscleGroupRawValue = newValue.rawValue }
    }

    var secondaryMuscleGroups: [MuscleGroup] {
        get { secondaryMuscleGroupRawValues.compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryMuscleGroupRawValues = newValue.map(\.rawValue) }
    }

    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRawValue) ?? .other }
        set { movementPatternRawValue = newValue.rawValue }
    }

    var splitClassification: CoachSplitClassification {
        get { CoachSplitClassification(rawValue: splitClassificationRawValue) ?? .unspecified }
        set { splitClassificationRawValue = newValue.rawValue }
    }

    var priority: CoachExercisePriorityLevel {
        get { CoachExercisePriorityLevel(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    func update(
        role: CoachExerciseMetadataRole,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup],
        movementPattern: MovementPattern,
        splitClassification: CoachSplitClassification,
        priority: CoachExercisePriorityLevel,
        userNote: String?
    ) {
        self.role = role
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.splitClassification = splitClassification
        self.priority = priority
        self.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = .now
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
