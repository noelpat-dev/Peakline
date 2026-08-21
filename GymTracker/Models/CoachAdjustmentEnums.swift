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
