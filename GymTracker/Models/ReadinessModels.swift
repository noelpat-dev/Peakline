import Foundation
import SwiftData

enum ReadinessCategory: String, CaseIterable, Hashable {
    case peak
    case ready
    case cautious
    case low
    case recovery

    init(score: Int) {
        switch score {
        case 85...100:
            self = .peak
        case 70...84:
            self = .ready
        case 55...69:
            self = .cautious
        case 40...54:
            self = .low
        default:
            self = .recovery
        }
    }

    var displayName: String {
        switch self {
        case .peak:
            return "Peak"
        case .ready:
            return "Ready"
        case .cautious:
            return "Cautious"
        case .low:
            return "Low"
        case .recovery:
            return "Recovery"
        }
    }

    var meaning: String {
        switch self {
        case .peak:
            return "Strong day to push progression."
        case .ready:
            return "Normal training day."
        case .cautious:
            return "Train, but control intensity."
        case .low:
            return "Reduce volume or intensity."
        case .recovery:
            return "Recovery-focused day recommended."
        }
    }
}

enum ReadinessConfidence: String, CaseIterable, Hashable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Low confidence"
        }
    }

    var note: String {
        switch self {
        case .high:
            return "Sleep, training, hydration, nutrition, and check-in data are recent."
        case .medium:
            return "Some recent signals are available. More logs will refine the brief."
        case .low:
            return "Based on limited data. Log sleep, hydration, and a check-in to improve this."
        }
    }
}

enum ReadinessImpact: String, CaseIterable, Hashable {
    case positive
    case neutral
    case negative
}

enum ReadinessFactorKind: String, CaseIterable, Hashable {
    case sleep
    case training
    case hydration
    case checkIn
    case nutrition

    var displayName: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .training:
            return "Training fatigue"
        case .hydration:
            return "Hydration"
        case .checkIn:
            return "Check-in"
        case .nutrition:
            return "Nutrition"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .training:
            return "figure.strengthtraining.traditional"
        case .hydration:
            return "drop.fill"
        case .checkIn:
            return "slider.horizontal.3"
        case .nutrition:
            return "fork.knife"
        }
    }
}

struct ReadinessFactor: Identifiable, Hashable {
    let id = UUID()
    let kind: ReadinessFactorKind
    let title: String
    let detail: String
    let impact: ReadinessImpact
    let contribution: Double
    let score: Int?
    let isDataAvailable: Bool
}

struct ReadinessCoachRecommendation: Hashable {
    let title: String
    let summary: String
    let reasonBullets: [String]
    let suggestedActions: [String]
}

struct ReadinessScore: Identifiable {
    let id = UUID()
    let value: Int
    let category: ReadinessCategory
    let confidence: ReadinessConfidence
    let recommendation: ReadinessCoachRecommendation
    let factors: [ReadinessFactor]
    let generatedAt: Date
    let checkIn: DailyCoachCheckIn?
    let workoutAdjustment: String
    let recoveryNote: String

    var hasCompletedTodayCheckIn: Bool {
        checkIn != nil
    }

    var topFactors: [ReadinessFactor] {
        Array(
            factors
                .sorted {
                    abs($0.contribution) == abs($1.contribution)
                        ? $0.kind.rawValue < $1.kind.rawValue
                        : abs($0.contribution) > abs($1.contribution)
                }
                .prefix(3)
        )
    }
}

struct CoachIntelligenceSnapshot {
    let readiness: ReadinessScore
    let weeklySummary: WeeklyCoachSummary
    let trends: CoachTrendSummary
    let insights: [CoachIntelligenceInsight]
    let fatigueRisk: CoachFatigueRisk
    let muscleFatigue: [MuscleGroupFatigue]
    let liftInsights: [LiftProgressInsight]
    let adaptiveGuidance: AdaptiveWorkoutGuidance
    let diagnostics: CoachDiagnostics
}

enum CoachTrendDirection: String, CaseIterable, Hashable {
    case improving
    case stable
    case declining
    case insufficientData

    var displayName: String {
        switch self {
        case .improving:
            return "Improving"
        case .stable:
            return "Stable"
        case .declining:
            return "Declining"
        case .insufficientData:
            return "Building"
        }
    }
}

struct CoachTrend: Hashable {
    let title: String
    let direction: CoachTrendDirection
    let summary: String
    let currentValue: Double?
    let previousValue: Double?
    let confidence: ReadinessConfidence
}

struct CoachTrendSummary: Hashable {
    let readiness: CoachTrend
    let sleepDuration: CoachTrend
    let sleepQuality: CoachTrend
    let hydrationConsistency: CoachTrend
    let nutritionConsistency: CoachTrend
    let workoutFrequency: CoachTrend
    let setVolume: CoachTrend
    let hardSessionFrequency: CoachTrend
    let energy: CoachTrend
    let soreness: CoachTrend
    let stress: CoachTrend
    let motivation: CoachTrend

    var keyTrends: [CoachTrend] {
        [
            readiness,
            sleepDuration,
            hydrationConsistency,
            nutritionConsistency,
            workoutFrequency,
            setVolume,
            hardSessionFrequency,
            energy,
            soreness,
            stress,
            motivation
        ]
    }
}

enum CoachInsightCategory: String, CaseIterable, Hashable {
    case readiness
    case recovery
    case sleep
    case hydration
    case nutrition
    case training
    case fatigue
    case muscleGroup
    case plateau
    case habit

    var displayName: String {
        switch self {
        case .readiness:
            return "Readiness"
        case .recovery:
            return "Recovery"
        case .sleep:
            return "Sleep"
        case .hydration:
            return "Hydration"
        case .nutrition:
            return "Nutrition"
        case .training:
            return "Training"
        case .fatigue:
            return "Fatigue"
        case .muscleGroup:
            return "Muscle"
        case .plateau:
            return "Lift"
        case .habit:
            return "Habit"
        }
    }

    var systemImage: String {
        switch self {
        case .readiness:
            return "gauge.with.dots.needle.bottom.50percent"
        case .recovery:
            return "leaf.fill"
        case .sleep:
            return "moon.zzz.fill"
        case .hydration:
            return "drop.fill"
        case .nutrition:
            return "fork.knife"
        case .training:
            return "figure.strengthtraining.traditional"
        case .fatigue:
            return "bolt.slash.fill"
        case .muscleGroup:
            return "figure.strengthtraining.functional"
        case .plateau:
            return "chart.line.flattrend.xyaxis"
        case .habit:
            return "checkmark.seal.fill"
        }
    }
}

enum CoachIntelligenceSeverity: String, CaseIterable, Hashable {
    case positive
    case neutral
    case caution
    case important
}

struct CoachIntelligenceInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let category: CoachInsightCategory
    let severity: CoachIntelligenceSeverity
    let confidence: ReadinessConfidence
    let supportingFactors: [String]
    let recommendedAction: String
    let relatedArea: String?
}

enum CoachFatigueRiskLevel: String, CaseIterable, Hashable {
    case low
    case moderate
    case high
    case deloadWatch

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        case .deloadWatch:
            return "Deload watch"
        }
    }
}

struct CoachFatigueRisk: Hashable {
    let level: CoachFatigueRiskLevel
    let title: String
    let summary: String
    let factors: [String]
    let recommendedAction: String
    let confidence: ReadinessConfidence
}

enum MuscleFatigueState: String, CaseIterable, Hashable {
    case fresh
    case normal
    case loaded
    case fatigued
    case unknown

    var displayName: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .normal:
            return "Normal"
        case .loaded:
            return "Loaded"
        case .fatigued:
            return "Fatigued"
        case .unknown:
            return "Unknown"
        }
    }
}

struct MuscleGroupFatigue: Identifiable, Hashable {
    var id: String { muscleGroup.rawValue }
    let muscleGroup: MuscleGroup
    let state: MuscleFatigueState
    let recentSetCount: Int
    let daysSinceLastTrained: Int?
    let detail: String
}

enum LiftProgressState: String, CaseIterable, Hashable {
    case improving
    case steady
    case declining

    var displayName: String {
        switch self {
        case .improving:
            return "Improving"
        case .steady:
            return "Steady"
        case .declining:
            return "Flat"
        }
    }
}

struct LiftProgressInsight: Identifiable, Hashable {
    let id: String
    let exerciseName: String
    let state: LiftProgressState
    let summary: String
    let recommendation: String
    let confidence: ReadinessConfidence
}

enum AdaptiveWorkoutMode: String, CaseIterable, Hashable {
    case push
    case maintain
    case reduce
    case recoveryFocus

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .maintain:
            return "Maintain"
        case .reduce:
            return "Reduce"
        case .recoveryFocus:
            return "Recovery Focus"
        }
    }
}

struct AdaptiveWorkoutGuidance: Hashable {
    let mode: AdaptiveWorkoutMode
    let readinessCategory: ReadinessCategory
    let fatigueContext: String
    let title: String
    let summary: String
    let primarySuggestion: String
    let adjustmentChips: [String]
}

struct CoachDiagnostics: Hashable {
    let readinessInputs: [String]
    let fatigueInputs: [String]
    let confidence: ReadinessConfidence
    let missingDataReasons: [String]
    let adaptiveActionReason: String
    let deloadTriggerReason: String?
    let exerciseMetadataInputs: [String]
    let feedbackInfluence: [String]
    let confidenceAdjustmentReasons: [String]
    let deloadBlockInfluence: String?
    let actionHistoryInfluence: String?
    let coachPreferenceInfluence: [String]
    let splitMetadataInfluence: [String]
    let bulkMetadataInfluence: [String]
    let urgencyAdjustmentReasons: [String]
}

struct WeeklyCoachSummary: Hashable {
    let averageReadiness: Int?
    let trainingSessionsCompleted: Int
    let recoveryTrend: CoachTrendDirection
    let topPositiveFactor: String
    let topLimitingFactor: String
    let recommendedFocus: String
}

@Model
final class DailyCoachCheckIn {
    @Attribute(.unique) var id: UUID
    var date: Date
    var energy: Int
    var soreness: Int
    var stress: Int
    var motivation: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        energy: Int,
        soreness: Int,
        stress: Int,
        motivation: Int,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        self.energy = Self.clampedRating(energy)
        self.soreness = Self.clampedRating(soreness)
        self.stress = Self.clampedRating(stress)
        self.motivation = Self.clampedRating(motivation)
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(
        energy: Int,
        soreness: Int,
        stress: Int,
        motivation: Int,
        note: String?
    ) {
        self.energy = Self.clampedRating(energy)
        self.soreness = Self.clampedRating(soreness)
        self.stress = Self.clampedRating(stress)
        self.motivation = Self.clampedRating(motivation)
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = .now
    }

    private static func clampedRating(_ value: Int) -> Int {
        min(5, max(1, value))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
