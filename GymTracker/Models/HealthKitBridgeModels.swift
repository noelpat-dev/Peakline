import Foundation

enum HealthKitPermissionState: String, Codable, Equatable, Sendable {
    case unavailable
    case notRequested
    case sharingAuthorized
    case partiallyAuthorized
    case sharingDenied
    case readOnlyRequested

    var displayName: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .notRequested:
            return "Not connected"
        case .sharingAuthorized:
            return "Connected"
        case .partiallyAuthorized:
            return "Partial access"
        case .sharingDenied:
            return "Permission needed"
        case .readOnlyRequested:
            return "Read context requested"
        }
    }
}

enum HealthKitSyncStatus: String, Codable, Equatable, Sendable {
    case notEnabled
    case pending
    case synced
    case skipped
    case failed
    case needsResync
    case unavailable

    var displayName: String {
        switch self {
        case .notEnabled:
            return "Apple Health off"
        case .pending:
            return "Not synced"
        case .synced:
            return "Synced to Apple Health"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Sync failed"
        case .needsResync:
            return "Review needed"
        case .unavailable:
            return "Unavailable"
        }
    }
}

enum HealthKitSyncError: Error, Equatable {
    case unavailable
    case authorizationDenied
    case missingQuantityType(String)
    case invalidNutritionValue(String)
    case noSupportedValues
    case saveFailed(String)
    case deleteFailed(String)
    case readFailed(String)
    case unknown(String)
}

extension HealthKitSyncError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .authorizationDenied:
            return "Permission is needed to sync nutrition."
        case .missingQuantityType(let name):
            return "Apple Health does not support \(name) on this device."
        case .invalidNutritionValue(let name):
            return "\(name) has an unsupported nutrition value."
        case .noSupportedValues:
            return "This food log has no supported nutrition values to sync."
        case .saveFailed(let message):
            return "Sync failed. \(message)"
        case .deleteFailed(let message):
            return "Apple Health cleanup failed. \(message)"
        case .readFailed(let message):
            return "Apple Health read failed. \(message)"
        case .unknown(let message):
            return message
        }
    }
}

struct HealthKitSyncPreferences: Codable, Equatable, Sendable {
    var isHealthKitEnabled: Bool
    var writeNutritionToHealthKit: Bool
    var readBodyWeight: Bool
    var readActiveEnergy: Bool
    var readStepCount: Bool
    var readWorkouts: Bool
    var autoSyncNewFoodLogs: Bool
    var includeSugarAndFibreIfAvailable: Bool
    var includeSodiumIfAvailable: Bool
    var syncOnlyUserConfirmedEntries: Bool

    static let `default` = HealthKitSyncPreferences(
        isHealthKitEnabled: false,
        writeNutritionToHealthKit: false,
        readBodyWeight: false,
        readActiveEnergy: false,
        readStepCount: false,
        readWorkouts: false,
        autoSyncNewFoodLogs: false,
        includeSugarAndFibreIfAvailable: true,
        includeSodiumIfAvailable: false,
        syncOnlyUserConfirmedEntries: true
    )

    var requestsAnyHealthData: Bool {
        writeNutritionToHealthKit || readBodyWeight || readActiveEnergy || readStepCount || readWorkouts
    }

    var requestsAnyReadData: Bool {
        readBodyWeight || readActiveEnergy || readStepCount || readWorkouts
    }
}

struct HealthKitFoodLogSyncRecord: Identifiable, Codable, Equatable {
    var id: UUID { foodLogEntryId }
    var foodLogEntryId: UUID
    var foodItemId: UUID?
    var foodName: String
    var sampleIdentifiers: [String]
    var status: HealthKitSyncStatus
    var lastSyncedAt: Date?
    var sourceUpdatedAt: Date?
    var errorMessage: String?
    var syncVersion: Int

    init(
        foodLogEntryId: UUID,
        foodItemId: UUID? = nil,
        foodName: String = "Food log",
        sampleIdentifiers: [String] = [],
        status: HealthKitSyncStatus,
        lastSyncedAt: Date? = nil,
        sourceUpdatedAt: Date? = nil,
        errorMessage: String? = nil,
        syncVersion: Int = HealthKitFoodLogSyncRecord.currentSyncVersion
    ) {
        self.foodLogEntryId = foodLogEntryId
        self.foodItemId = foodItemId
        self.foodName = foodName
        self.sampleIdentifiers = sampleIdentifiers
        self.status = status
        self.lastSyncedAt = lastSyncedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.errorMessage = errorMessage
        self.syncVersion = syncVersion
    }

    static let currentSyncVersion = 1
}

struct HealthKitFoodLogSyncResult: Equatable {
    var foodLogEntryId: UUID
    var status: HealthKitSyncStatus
    var sampleIdentifiers: [String]
    var syncedAt: Date?
    var errorMessage: String?
}

struct HealthKitSyncSummary: Equatable {
    var attempted: Int = 0
    var synced: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var warnings: [String] = []
    var finishedAt: Date = .now

    var displayMessage: String {
        if attempted == 0 {
            return "No eligible food logs found."
        }

        if failed > 0 {
            return "Synced \(synced), skipped \(skipped), failed \(failed)."
        }

        return "Synced \(synced) food log\(synced == 1 ? "" : "s"). Skipped \(skipped)."
    }
}

struct HealthKitDailyContext: Codable, Equatable {
    var date: Date
    var bodyMassKg: Double?
    var activeEnergyKcal: Double?
    var stepCount: Double?
    var workoutCount: Int?
    var sourceLabel = "Apple Health"

    var hasAnyValue: Bool {
        bodyMassKg != nil || activeEnergyKcal != nil || stepCount != nil || workoutCount != nil
    }
}

struct HealthKitDailyMetric: Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var value: Double
    var unit: String
}

struct HealthKitBodyMassSample: Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kilograms: Double
}
