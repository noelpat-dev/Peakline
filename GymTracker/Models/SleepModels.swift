import Foundation
import SwiftData

enum SleepSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case inAppTimer
    case appleHealth
    case manual
    case merged
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inAppTimer:
            return "Sleep Mode Estimate"
        case .appleHealth:
            return "Apple Health"
        case .manual:
            return "Manual"
        case .merged:
            return "Merged"
        case .unknown:
            return "Unknown"
        }
    }
}

enum PreferredSleepSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case appleHealth
    case sleepMode
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .appleHealth:
            return "Apple Health"
        case .sleepMode:
            return "Sleep Mode"
        case .manual:
            return "Manual"
        }
    }
}

enum SleepConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case estimatedConfirmed

    var displayName: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Low confidence"
        case .estimatedConfirmed:
            return "Confirmed estimate"
        }
    }
}

enum SleepSessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case discarded

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        case .discarded:
            return "Discarded"
        }
    }
}

enum SleepTag: String, Codable, CaseIterable, Identifiable {
    case caffeineLate
    case trainedLate
    case highStress
    case wokeDuringNight
    case ateLate
    case illness
    case travel
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .caffeineLate:
            return "Caffeine late"
        case .trainedLate:
            return "Trained late"
        case .highStress:
            return "High stress"
        case .wokeDuringNight:
            return "Woke during night"
        case .ateLate:
            return "Ate late"
        case .illness:
            return "Illness"
        case .travel:
            return "Travel"
        case .other:
            return "Other"
        }
    }
}

enum NapSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case napTimer
    case appleHealth
    case inferred

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .napTimer:
            return "Nap Timer"
        case .appleHealth:
            return "Apple Health"
        case .inferred:
            return "Inferred"
        }
    }
}

enum NapTimingCategory: String, Codable, CaseIterable, Identifiable {
    case morning
    case earlyAfternoon
    case lateAfternoon
    case evening
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning:
            return "Morning"
        case .earlyAfternoon:
            return "Early afternoon"
        case .lateAfternoon:
            return "Late afternoon"
        case .evening:
            return "Evening"
        case .unknown:
            return "Unknown"
        }
    }
}

enum RecoveryState: String, Codable, CaseIterable {
    case high
    case good
    case moderate
    case low
    case veryLow
    case unknown

    var displayName: String {
        switch self {
        case .high:
            return "High Recovery"
        case .good:
            return "Good Recovery"
        case .moderate:
            return "Moderate Recovery"
        case .low:
            return "Low Recovery"
        case .veryLow:
            return "Very Low Recovery"
        case .unknown:
            return "No Data"
        }
    }

    var shortLabel: String {
        switch self {
        case .high:
            return "Push progression"
        case .good:
            return "Train normally"
        case .moderate:
            return "Train with caution"
        case .low:
            return "Reduce volume"
        case .veryLow:
            return "Recovery focus"
        case .unknown:
            return "Track sleep"
        }
    }
}

@Model
final class SleepSession {
    @Attribute(.unique) var id: UUID
    var sleepModeStartedAt: Date?
    var windDownDurationMinutes: Int?
    var estimatedSleepStartAt: Date?
    var confirmedSleepStartAt: Date
    var wakeAt: Date
    var durationMinutes: Int
    var qualityRating: Int?
    var tagRawValues: [String]
    var notes: String?
    var source: SleepSource
    var confidence: SleepConfidence
    var status: SleepSessionStatus
    var healthKitSampleIds: [String]
    var morningReminderSentAt: Date?
    var unfinishedReminderSentAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sleepModeStartedAt: Date? = nil,
        windDownDurationMinutes: Int? = nil,
        estimatedSleepStartAt: Date? = nil,
        confirmedSleepStartAt: Date,
        wakeAt: Date,
        durationMinutes: Int,
        qualityRating: Int? = nil,
        tags: [SleepTag] = [],
        notes: String? = nil,
        source: SleepSource,
        confidence: SleepConfidence,
        status: SleepSessionStatus,
        healthKitSampleIds: [String] = [],
        morningReminderSentAt: Date? = nil,
        unfinishedReminderSentAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sleepModeStartedAt = sleepModeStartedAt
        self.windDownDurationMinutes = windDownDurationMinutes
        self.estimatedSleepStartAt = estimatedSleepStartAt
        self.confirmedSleepStartAt = confirmedSleepStartAt
        self.wakeAt = wakeAt
        self.durationMinutes = durationMinutes
        self.qualityRating = qualityRating
        self.tagRawValues = tags.map(\.rawValue)
        self.notes = notes
        self.source = source
        self.confidence = confidence
        self.status = status
        self.healthKitSampleIds = healthKitSampleIds
        self.morningReminderSentAt = morningReminderSentAt
        self.unfinishedReminderSentAt = unfinishedReminderSentAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var tags: [SleepTag] {
        get { tagRawValues.compactMap(SleepTag.init(rawValue:)) }
        set { tagRawValues = newValue.map(\.rawValue) }
    }

    var isCompleted: Bool {
        status == .completed
    }

    var nightDate: Date {
        SleepCalendar.nightDate(for: confirmedSleepStartAt)
    }
}

@Model
final class NapSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var durationMinutes: Int
    var qualityRating: Int?
    var source: NapSource
    var timingCategory: NapTimingCategory
    var note: String?
    var healthKitSampleIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        qualityRating: Int? = nil,
        source: NapSource,
        timingCategory: NapTimingCategory = .unknown,
        note: String? = nil,
        healthKitSampleIds: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = max(0, Int(endDate.timeIntervalSince(startDate) / 60))
        self.qualityRating = qualityRating
        self.source = source
        self.timingCategory = timingCategory == .unknown ? NapSession.timingCategory(for: startDate) : timingCategory
        self.note = note
        self.healthKitSampleIds = healthKitSampleIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval {
        TimeInterval(durationMinutes * 60)
    }

    var napDate: Date {
        Calendar.current.startOfDay(for: startDate)
    }

    static func timingCategory(for startDate: Date, calendar: Calendar = .current) -> NapTimingCategory {
        let hour = calendar.component(.hour, from: startDate)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<15:
            return .earlyAfternoon
        case 15..<18:
            return .lateAfternoon
        case 18..<22:
            return .evening
        default:
            return .unknown
        }
    }
}

struct SleepSummary: Identifiable {
    var id: Date { date }
    var date: Date
    var primarySession: SleepSession?
    var totalSleepMinutes: Int
    var timeInBedMinutes: Int?
    var qualityRating: Int?
    var source: SleepSource?
    var sleepScore: Int?
    var recoveryState: RecoveryState
    var confidence: SleepConfidence
    var sourceConflict: SleepSourceConflict?
    var stageBreakdown: SleepStageBreakdown?
    var napCreditMinutes: Int
    var recoveryBreakdown: RecoveryScoreBreakdown?
}

struct SleepDashboardSummary {
    var lastNightSession: SleepSession?
    var lastNightDurationMinutes: Int?
    var lastNightQualityRating: Int?
    var sleepScore: Int?
    var recoveryState: RecoveryState
    var recommendation: String
    var sevenDaySummaries: [DailySleepSummary]
    var averageSleepMinutes: Int?
    var weeklySleepDebtMinutes: Int?
    var trackedNightCount: Int
    var consistencySummary: SleepConsistencySummary
    var sourceLabel: String?
    var confidence: SleepConfidence?
    var sourceConflict: SleepSourceConflict?
    var lastHealthKitSleepSyncAt: Date?
    var coachingInsights: [SleepCoachingInsight]
    var adaptiveRecommendation: AdaptiveTrainingRecommendation?
    var napCreditMinutes: Int
    var recentNaps: [NapSession]
    var recoveryBreakdown: RecoveryScoreBreakdown?
}

struct DailySleepSummary: Identifiable {
    var id: String { date.formatted(.iso8601.year().month().day()) }
    var date: Date
    var durationMinutes: Int?
    var qualityRating: Int?
    var source: SleepSource?
    var isBelowTarget: Bool
    var isUnderSixHours: Bool
}

struct SleepConsistencySummary {
    var status: SleepConsistencyStatus
    var averageSleepStart: Date?
    var averageWakeTime: Date?
    var approximateVariationMinutes: Int?
    var message: String

    var displayName: String {
        status.displayName
    }
}

enum SleepSourceConflict: String, Codable, Equatable {
    case appleHealthShorter
    case appEstimateShorter
    case largeMismatch
    case lowConfidenceHealthKit

    var displayMessage: String {
        switch self {
        case .appleHealthShorter:
            return "Apple Health recorded less sleep than Sleep Mode estimated."
        case .appEstimateShorter:
            return "Sleep Mode estimated less sleep than Apple Health recorded."
        case .largeMismatch:
            return "Apple Health and Sleep Mode do not match closely. Review your sleep entry to improve today's recovery score."
        case .lowConfidenceHealthKit:
            return "Apple Health sleep data is low confidence, so Sleep Mode is being used for recovery."
        }
    }
}

struct SleepStageBreakdown: Codable, Equatable {
    var awakeMinutes: Int?
    var coreMinutes: Int?
    var deepMinutes: Int?
    var remMinutes: Int?

    var hasStages: Bool {
        coreMinutes != nil || deepMinutes != nil || remMinutes != nil
    }
}

struct ResolvedSleepSession: Identifiable, Codable, Equatable {
    let id: UUID
    let sleepDate: Date
    let startDate: Date
    let endDate: Date
    let asleepDuration: TimeInterval
    let inBedDuration: TimeInterval?
    let qualityRating: Int?
    let dataSource: SleepSource
    let confidence: SleepConfidence
    let appleHealthSummary: HealthSleepSummary?
    let appSessionID: UUID?
    let notes: String?
    let conflict: SleepSourceConflict?
    let stageBreakdown: SleepStageBreakdown?
}

struct SleepWorkoutCorrelation: Identifiable, Codable, Equatable {
    var id: UUID { workoutID }
    let workoutID: UUID
    let workoutDate: Date
    let splitName: String?
    let resolvedSleepSession: ResolvedSleepSession?
    let sleepDuration: TimeInterval?
    let sleepQuality: Int?
    let recoveryScore: Int?
    let performanceScore: Int?
    let volumeCompletedRatio: Double?
    let estimatedEffort: Double?
    let completedVolume: Double
}

struct WorkoutPerformanceScore: Codable, Equatable {
    let score: Int
    let label: WorkoutPerformanceLabel
    let contributingFactors: [WorkoutPerformanceFactor]
}

enum WorkoutPerformanceLabel: String, Codable, Equatable {
    case strong
    case good
    case moderate
    case reduced
    case incomplete

    var displayName: String {
        switch self {
        case .strong:
            return "Strong session"
        case .good:
            return "Good session"
        case .moderate:
            return "Moderate session"
        case .reduced:
            return "Reduced performance"
        case .incomplete:
            return "Incomplete"
        }
    }
}

enum WorkoutPerformanceFactor: String, Codable, Equatable {
    case completedMostSets
    case volumeAboveAverage
    case volumeBelowAverage
    case strengthProgressed
    case repsDropped
    case shorterThanUsual
    case highDifficulty
    case missedWorkout
    case highEnergy
    case highSoreness

    var displayName: String {
        switch self {
        case .completedMostSets:
            return "completed most sets"
        case .volumeAboveAverage:
            return "volume above baseline"
        case .volumeBelowAverage:
            return "volume below baseline"
        case .strengthProgressed:
            return "strength progressed"
        case .repsDropped:
            return "reps dropped"
        case .shorterThanUsual:
            return "shorter than usual"
        case .highDifficulty:
            return "high difficulty"
        case .missedWorkout:
            return "missed workout"
        case .highEnergy:
            return "high energy"
        case .highSoreness:
            return "high soreness"
        }
    }
}

struct SleepCoachingInsight: Identifiable, Codable, Equatable {
    let id: UUID
    let type: SleepCoachingInsightType
    let title: String
    let message: String
    let confidence: InsightConfidence
    let severity: InsightSeverity
    let relatedWorkoutIDs: [UUID]
    let relatedSleepSessionIDs: [UUID]
    let basedOn: [RecommendationInput]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: SleepCoachingInsightType,
        title: String,
        message: String,
        confidence: InsightConfidence,
        severity: InsightSeverity,
        relatedWorkoutIDs: [UUID] = [],
        relatedSleepSessionIDs: [UUID] = [],
        basedOn: [RecommendationInput] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.confidence = confidence
        self.severity = severity
        self.relatedWorkoutIDs = relatedWorkoutIDs
        self.relatedSleepSessionIDs = relatedSleepSessionIDs
        self.basedOn = basedOn
        self.createdAt = createdAt
    }
}

enum SleepCoachingInsightType: String, Codable, Equatable {
    case sleepImprovesPerformance
    case poorSleepReducesPerformance
    case consistentSleepImprovesRecovery
    case sleepDebtAccumulating
    case goodSleepBeforeStrongSession
    case poorSleepBeforeMissedSession
    case lateWorkoutAffectsSleep
    case recoveryTrendImproving
    case recoveryTrendDeclining
    case deloadSuggested
    case bedtimeConsistencyOpportunity
    case notEnoughData
    case missingSleepData
    case missingWorkoutData
}

enum InsightConfidence: String, Codable, Equatable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:
            return "Low confidence"
        case .medium:
            return "Medium confidence"
        case .high:
            return "High confidence"
        }
    }
}

enum InsightSeverity: String, Codable, Equatable {
    case positive
    case neutral
    case caution
    case important
}

enum TrainingReadinessRecommendation: String, Codable, Equatable {
    case push
    case normal
    case moderate
    case light
    case recovery
    case rest

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .normal:
            return "Normal"
        case .moderate:
            return "Moderate"
        case .light:
            return "Light"
        case .recovery:
            return "Recovery"
        case .rest:
            return "Rest"
        }
    }
}

struct AdaptiveTrainingRecommendation: Codable, Equatable {
    let level: TrainingReadinessRecommendation
    let title: String
    let message: String
    let suggestedActions: [TrainingAdjustment]
    let confidence: InsightConfidence
    let basedOn: [RecommendationInput]
}

enum TrainingAdjustment: String, Codable, Equatable, Identifiable {
    case trainAsPlanned
    case reduceVolume
    case reduceLoad
    case increaseRest
    case avoidPR
    case focusTechnique
    case considerRest
    case deload
    case keepRepsInReserve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trainAsPlanned:
            return "Train as planned"
        case .reduceVolume:
            return "Reduce volume"
        case .reduceLoad:
            return "Reduce load"
        case .increaseRest:
            return "Increase rest"
        case .avoidPR:
            return "Avoid PR attempts"
        case .focusTechnique:
            return "Technique focus"
        case .considerRest:
            return "Consider rest"
        case .deload:
            return "Deload"
        case .keepRepsInReserve:
            return "Keep reps in reserve"
        }
    }
}

enum RecommendationInput: String, Codable, Equatable, Identifiable {
    case lastNightSleep
    case sevenDaySleepDebt
    case sleepQuality
    case recoveryScore
    case recentPerformance
    case trainingFrequency
    case soreness
    case sleepConsistency
    case sleepSourceConflict

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastNightSleep:
            return "last night's sleep"
        case .sevenDaySleepDebt:
            return "7-day sleep debt"
        case .sleepQuality:
            return "sleep quality"
        case .recoveryScore:
            return "recovery score"
        case .recentPerformance:
            return "recent performance"
        case .trainingFrequency:
            return "training frequency"
        case .soreness:
            return "soreness"
        case .sleepConsistency:
            return "sleep consistency"
        case .sleepSourceConflict:
            return "sleep source confidence"
        }
    }
}

enum RecoveryLabel: String, Codable, CaseIterable, DisplayableEnum {
    case strong
    case good
    case moderate
    case low
    case veryLow
}

enum RecoveryConfidence: String, Codable, CaseIterable, DisplayableEnum {
    case high
    case medium
    case low
}

enum RecoveryFactor: String, Codable, CaseIterable, DisplayableEnum {
    case sleptAboveTarget
    case sleptBelowTarget
    case sleepDebtHigh
    case sleepConsistent
    case sleepInconsistent
    case napImprovedRecovery
    case lateNapMayAffectSleep
    case poorSleepQuality
    case strongSleepQuality
    case highTrainingLoad
    case recentPerformanceDip
    case recentPerformanceStrong
    case missingSleepData
    case lowConfidenceData

    var coachingText: String {
        switch self {
        case .sleptAboveTarget:
            return "Overnight sleep met your target."
        case .sleptBelowTarget:
            return "Overnight sleep was below target."
        case .sleepDebtHigh:
            return "Sleep debt is still elevated."
        case .sleepConsistent:
            return "Sleep timing has been consistent."
        case .sleepInconsistent:
            return "Sleep timing has varied recently."
        case .napImprovedRecovery:
            return "A nap recovered part of the deficit."
        case .lateNapMayAffectSleep:
            return "A late nap may affect tonight's bedtime."
        case .poorSleepQuality:
            return "Sleep quality was low."
        case .strongSleepQuality:
            return "Sleep quality was strong."
        case .highTrainingLoad:
            return "Recent training load is high."
        case .recentPerformanceDip:
            return "Recent performance has dipped."
        case .recentPerformanceStrong:
            return "Recent performance is stable or strong."
        case .missingSleepData:
            return "Sleep data is incomplete."
        case .lowConfidenceData:
            return "Sleep data confidence is limited."
        }
    }
}

struct NapRecoveryCredit: Codable, Equatable {
    let totalCreditMinutes: Int
    let cappedCreditMinutes: Int
    let factors: [RecoveryFactor]
    let notes: [String]
}

struct RecoveryScoreBreakdown: Codable, Equatable {
    let finalScore: Int
    let label: RecoveryLabel
    let overnightSleepComponent: Double
    let sleepDebtComponent: Double
    let consistencyComponent: Double
    let qualityComponent: Double?
    let napComponent: Double
    let trainingLoadComponent: Double?
    let performanceTrendComponent: Double?
    let confidence: RecoveryConfidence
    let contributingFactors: [RecoveryFactor]
}

struct RecoveryCoachingRecommendation: Codable, Equatable {
    let readiness: TrainingReadinessRecommendation
    let title: String
    let message: String
    let suggestedAdjustments: [TrainingAdjustment]
    let reasons: [RecoveryFactor]
    let confidence: RecoveryConfidence
}

enum RecoveryInterventionType: String, Codable, Equatable {
    case reduceVolume
    case reduceLoad
    case avoidPR
    case techniqueFocus
    case mobilityRecovery
    case restDay
    case deloadWeek

    var displayName: String {
        switch self {
        case .reduceVolume:
            return "Reduce volume"
        case .reduceLoad:
            return "Reduce load"
        case .avoidPR:
            return "Avoid max effort"
        case .techniqueFocus:
            return "Technique focus"
        case .mobilityRecovery:
            return "Mobility recovery"
        case .restDay:
            return "Rest day"
        case .deloadWeek:
            return "Deload week"
        }
    }
}

struct RecoveryIntervention: Identifiable, Codable, Equatable {
    let id: UUID
    let type: RecoveryInterventionType
    let title: String
    let message: String
    let severity: InsightSeverity
    let basedOn: [RecommendationInput]

    init(
        id: UUID = UUID(),
        type: RecoveryInterventionType,
        title: String,
        message: String,
        severity: InsightSeverity,
        basedOn: [RecommendationInput]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.severity = severity
        self.basedOn = basedOn
    }
}

struct SleepPerformanceBaseline: Codable, Equatable {
    let averageSleepDuration: TimeInterval
    let averageSleepQuality: Double?
    let averageRecoveryScore: Double
    let averagePerformanceScore: Double
    let bestPerformanceSleepRange: ClosedRange<TimeInterval>?
    let lowPerformanceSleepThreshold: TimeInterval?
}

enum HealthSleepStage: String, Codable, Equatable {
    case inBed
    case asleep
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
    case unknown

    var countsAsAsleep: Bool {
        switch self {
        case .asleep, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .inBed, .awake, .unknown:
            return false
        }
    }
}

struct HealthSleepSample: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let value: HealthSleepStage
    let sourceName: String?
    let sourceBundleIdentifier: String?
}

struct HealthSleepSummary: Codable, Equatable {
    let sleepDate: Date
    let intervalStart: Date
    let intervalEnd: Date
    let totalInBedDuration: TimeInterval
    let totalAsleepDuration: TimeInterval
    let totalAwakeDuration: TimeInterval?
    let coreDuration: TimeInterval?
    let deepDuration: TimeInterval?
    let remDuration: TimeInterval?
    let sampleCount: Int
    let sourceNames: [String]
    let confidence: SleepConfidence

    var stageBreakdown: SleepStageBreakdown? {
        let breakdown = SleepStageBreakdown(
            awakeMinutes: totalAwakeDuration.map { Int($0 / 60) },
            coreMinutes: coreDuration.map { Int($0 / 60) },
            deepMinutes: deepDuration.map { Int($0 / 60) },
            remMinutes: remDuration.map { Int($0 / 60) }
        )
        return breakdown.hasStages ? breakdown : nil
    }
}

enum SleepConsistencyStatus: String, Codable {
    case strong
    case moderate
    case inconsistent
    case notEnoughData

    var displayName: String {
        switch self {
        case .strong:
            return "Strong"
        case .moderate:
            return "Moderate"
        case .inconsistent:
            return "Inconsistent"
        case .notEnoughData:
            return "Not enough data"
        }
    }
}

struct SleepSettings: Codable, Equatable, Sendable {
    var defaultWindDownMinutes: Int
    var targetSleepMinutes: Int
    var enableAppleHealthImport: Bool
    var enableAppleHealthExport: Bool
    var bedtimeReminderEnabled: Bool
    var morningConfirmationReminderEnabled: Bool
    var recoveryCoachingEnabled: Bool
    var preferredSource: PreferredSleepSource
    var notificationPreferences: SleepNotificationPreferences
    var coachingPreferences: SleepCoachingPreferences
    var lastHealthKitSleepSyncAt: Date?

    static let `default` = SleepSettings(
        defaultWindDownMinutes: 30,
        targetSleepMinutes: 480,
        enableAppleHealthImport: false,
        enableAppleHealthExport: false,
        bedtimeReminderEnabled: false,
        morningConfirmationReminderEnabled: false,
        recoveryCoachingEnabled: true,
        preferredSource: .automatic,
        notificationPreferences: .default,
        coachingPreferences: .default,
        lastHealthKitSleepSyncAt: nil
    )

    static let windDownOptions = [10, 20, 30, 45, 60]
    static let targetHourOptions = [6, 7, 8, 9, 10]

    init(
        defaultWindDownMinutes: Int,
        targetSleepMinutes: Int,
        enableAppleHealthImport: Bool,
        enableAppleHealthExport: Bool,
        bedtimeReminderEnabled: Bool,
        morningConfirmationReminderEnabled: Bool,
        recoveryCoachingEnabled: Bool,
        preferredSource: PreferredSleepSource = .automatic,
        notificationPreferences: SleepNotificationPreferences = .default,
        coachingPreferences: SleepCoachingPreferences = .default,
        lastHealthKitSleepSyncAt: Date? = nil
    ) {
        self.defaultWindDownMinutes = defaultWindDownMinutes
        self.targetSleepMinutes = targetSleepMinutes
        self.enableAppleHealthImport = enableAppleHealthImport
        self.enableAppleHealthExport = enableAppleHealthExport
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.morningConfirmationReminderEnabled = morningConfirmationReminderEnabled
        self.recoveryCoachingEnabled = recoveryCoachingEnabled
        self.preferredSource = preferredSource
        self.notificationPreferences = notificationPreferences
        self.coachingPreferences = coachingPreferences
        self.lastHealthKitSleepSyncAt = lastHealthKitSleepSyncAt
    }

    enum CodingKeys: String, CodingKey {
        case defaultWindDownMinutes
        case targetSleepMinutes
        case enableAppleHealthImport
        case enableAppleHealthExport
        case bedtimeReminderEnabled
        case morningConfirmationReminderEnabled
        case recoveryCoachingEnabled
        case preferredSource
        case notificationPreferences
        case coachingPreferences
        case lastHealthKitSleepSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SleepSettings.default
        defaultWindDownMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultWindDownMinutes) ?? defaults.defaultWindDownMinutes
        targetSleepMinutes = try container.decodeIfPresent(Int.self, forKey: .targetSleepMinutes) ?? defaults.targetSleepMinutes
        enableAppleHealthImport = try container.decodeIfPresent(Bool.self, forKey: .enableAppleHealthImport) ?? defaults.enableAppleHealthImport
        enableAppleHealthExport = try container.decodeIfPresent(Bool.self, forKey: .enableAppleHealthExport) ?? defaults.enableAppleHealthExport
        bedtimeReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .bedtimeReminderEnabled) ?? defaults.bedtimeReminderEnabled
        morningConfirmationReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .morningConfirmationReminderEnabled) ?? defaults.morningConfirmationReminderEnabled
        recoveryCoachingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recoveryCoachingEnabled) ?? defaults.recoveryCoachingEnabled
        preferredSource = try container.decodeIfPresent(PreferredSleepSource.self, forKey: .preferredSource) ?? defaults.preferredSource
        notificationPreferences = try container.decodeIfPresent(SleepNotificationPreferences.self, forKey: .notificationPreferences) ?? defaults.notificationPreferences
        coachingPreferences = try container.decodeIfPresent(SleepCoachingPreferences.self, forKey: .coachingPreferences) ?? defaults.coachingPreferences
        lastHealthKitSleepSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastHealthKitSleepSyncAt)
    }
}

struct SleepCoachingPreferences: Codable, Equatable, Sendable {
    var sleepCoachingInsightsEnabled: Bool
    var adaptiveWorkoutRecommendationsEnabled: Bool
    var deloadSuggestionsEnabled: Bool
    var sleepPerformanceInsightsEnabled: Bool

    static let `default` = SleepCoachingPreferences(
        sleepCoachingInsightsEnabled: true,
        adaptiveWorkoutRecommendationsEnabled: true,
        deloadSuggestionsEnabled: true,
        sleepPerformanceInsightsEnabled: true
    )
}

struct SleepNotificationPreferences: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var bedtimeReminderEnabled: Bool
    var bedtimeReminderTime: DateComponents
    var windDownReminderEnabled: Bool
    var windDownOffsetMinutes: Int
    var morningConfirmationEnabled: Bool
    var morningConfirmationTime: DateComponents
    var missedSleepReminderEnabled: Bool
    var trainingAwareRemindersEnabled: Bool
    var recoveryCoachingNotificationsEnabled: Bool
    var quietWeekdays: [Int]

    static let `default` = SleepNotificationPreferences(
        isEnabled: false,
        bedtimeReminderEnabled: true,
        bedtimeReminderTime: DateComponents(hour: 22, minute: 30),
        windDownReminderEnabled: false,
        windDownOffsetMinutes: 30,
        morningConfirmationEnabled: true,
        morningConfirmationTime: DateComponents(hour: 7, minute: 30),
        missedSleepReminderEnabled: true,
        trainingAwareRemindersEnabled: true,
        recoveryCoachingNotificationsEnabled: false,
        quietWeekdays: []
    )

    static let windDownOffsetOptions = [15, 30, 45, 60]

    func isQuietDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return quietWeekdays.contains(weekday)
    }
}

enum SleepNotificationDestination: Identifiable, Equatable {
    case sleepMode
    case wakeConfirmation(sessionID: UUID)
    case manualBackfill
    case sleepDashboard
    case recoverySummary

    var id: String {
        switch self {
        case .sleepMode:
            return "sleepMode"
        case .wakeConfirmation(let sessionID):
            return "wakeConfirmation.\(sessionID.uuidString)"
        case .manualBackfill:
            return "manualBackfill"
        case .sleepDashboard:
            return "sleepDashboard"
        case .recoverySummary:
            return "recoverySummary"
        }
    }

    var userInfo: [String: String] {
        switch self {
        case .sleepMode:
            return ["sleepDestination": "sleepMode"]
        case .wakeConfirmation(let sessionID):
            return ["sleepDestination": "wakeConfirmation", "sessionID": sessionID.uuidString]
        case .manualBackfill:
            return ["sleepDestination": "manualBackfill"]
        case .sleepDashboard:
            return ["sleepDestination": "sleepDashboard"]
        case .recoverySummary:
            return ["sleepDestination": "recoverySummary"]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let value = userInfo["sleepDestination"] as? String else { return nil }
        switch value {
        case "sleepMode":
            self = .sleepMode
        case "wakeConfirmation":
            if let rawID = userInfo["sessionID"] as? String, let id = UUID(uuidString: rawID) {
                self = .wakeConfirmation(sessionID: id)
            } else {
                self = .sleepDashboard
            }
        case "manualBackfill":
            self = .manualBackfill
        case "recoverySummary":
            self = .recoverySummary
        default:
            self = .sleepDashboard
        }
    }
}

extension Notification.Name {
    static let sleepNotificationTapped = Notification.Name("sleepNotificationTapped")
    static let appWillResignActiveForCleanup = Notification.Name("appWillResignActiveForCleanup")
    static let appDidEnterBackgroundForCleanup = Notification.Name("appDidEnterBackgroundForCleanup")
}

enum SleepCalendar {
    static func nightDate(for date: Date, calendar: Calendar = .current) -> Date {
        let adjusted = calendar.date(byAdding: .hour, value: -12, to: date) ?? date
        return calendar.startOfDay(for: adjusted)
    }

    static func queryWindow(for sleepDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfSleepDate = calendar.startOfDay(for: sleepDate)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfSleepDate) ?? startOfSleepDate.addingTimeInterval(-86_400)
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay) ?? previousDay.addingTimeInterval(18 * 3_600)
        let end = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: startOfSleepDate) ?? startOfSleepDate.addingTimeInterval(14 * 3_600)
        return (start, end)
    }

    static func displayTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }

        return date.formatted(.dateTime.weekday(.wide))
    }
}
