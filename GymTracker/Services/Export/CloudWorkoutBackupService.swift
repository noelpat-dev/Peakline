import CloudKit
import Foundation
import SwiftData

struct CloudWorkoutBackupMetadata: Codable, Equatable {
    let createdAt: Date
    let exportedAt: Date
    let workoutCount: Int
    let exerciseCount: Int
    let splitCount: Int
    let compressedByteCount: Int
    let appVersion: String?
}

enum CloudWorkoutBackupMetadataOutcome: Equatable {
    case available(CloudWorkoutBackupMetadata)
    case noBackup
    case unavailable(String)
    case skippedUITestStore
    case failed(String)
}

enum CloudWorkoutBackupSaveOutcome: Equatable {
    case saved(CloudWorkoutBackupMetadata)
    case keptExistingWorkoutBackup(CloudWorkoutBackupMetadata)
    case skippedUITestStore
    case unavailable(String)
    case failed(String)
}

enum CloudWorkoutBackupRestoreOutcome: Equatable {
    case restored(LocalBackupImportSummary)
    case skippedStoreNotEmpty
    case skippedNoBackup
    case skippedUITestStore
    case unavailable(String)
    case failed(String)
}

@MainActor
struct CloudWorkoutBackupService {
    static let containerIdentifier = "iCloud.com.noel.GymTracker"

    private let recordType = "PeaklineWorkoutBackup"
    private let recordName = "latest-workout-backup-v1"
    private let container: CKContainer
    private let database: CKDatabase
    private let exportService = LocalBackupExportService()
    private let importService = LocalBackupImportService()

    init(container: CKContainer = CKContainer(identifier: CloudWorkoutBackupService.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func latestMetadata() async -> CloudWorkoutBackupMetadataOutcome {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") else {
            return .skippedUITestStore
        }

        do {
            try await validateAccount()
            guard let record = try await fetchLatestRecord() else {
                return .noBackup
            }
            return .available(try metadata(from: record))
        } catch let error as CloudWorkoutBackupError {
            return error.metadataOutcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func saveLatestBackup(in context: ModelContext) async -> CloudWorkoutBackupSaveOutcome {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") else {
            return .skippedUITestStore
        }

        do {
            let payload = try makePayload(in: context)
            try await validateAccount()

            if payload.metadata.workoutCount == 0,
               let existingRecord = try await fetchLatestRecord(),
               try metadata(from: existingRecord).workoutCount > 0 {
                return .keptExistingWorkoutBackup(try metadata(from: existingRecord))
            }

            let record = try await fetchLatestRecord() ?? CKRecord(
                recordType: recordType,
                recordID: CKRecord.ID(recordName: recordName)
            )
            let metadata = try await save(payload, into: record)
            return .saved(metadata)
        } catch let error as CloudWorkoutBackupError {
            return error.saveOutcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restoreIfNeeded(in context: ModelContext) async -> CloudWorkoutBackupRestoreOutcome {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") else {
            return .skippedUITestStore
        }

        do {
            try await validateAccount()
            guard let record = try await fetchLatestRecord() else {
                return .skippedNoBackup
            }
            let metadata = try metadata(from: record)
            guard try canAutomaticallyRestore(metadata, into: context) else {
                return .skippedStoreNotEmpty
            }

            let envelopeData = try envelopeData(from: record)
            let summary = try importService.importBackup(
                from: envelopeData,
                into: context,
                replaceSeedDataWhenNoWorkouts: true
            )
            return .restored(summary)
        } catch let error as CloudWorkoutBackupError {
            return error.restoreOutcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func makePayload(in context: ModelContext) throws -> CloudWorkoutBackupPayload {
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let splits = try context.fetch(FetchDescriptor<TrainingSplit>())
        let envelope = exportService.makeEnvelope(workouts: workouts, exercises: exercises, splits: splits)
        let envelopeData = try exportService.encode(envelope)
        let compressedData = try (envelopeData as NSData).compressed(using: .lzfse) as Data
        return CloudWorkoutBackupPayload(
            compressedData: compressedData,
            metadata: CloudWorkoutBackupMetadata(
                createdAt: Date(),
                exportedAt: envelope.exportedAt,
                workoutCount: envelope.workouts.count,
                exerciseCount: envelope.exercises.count,
                splitCount: envelope.splits.count,
                compressedByteCount: compressedData.count,
                appVersion: envelope.appVersion
            )
        )
    }

    private func save(
        _ payload: CloudWorkoutBackupPayload,
        into record: CKRecord
    ) async throws -> CloudWorkoutBackupMetadata {
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeaklineCloudWorkoutBackup-\(UUID().uuidString).json.lzfse")
        try payload.compressedData.write(to: assetURL, options: [.atomic])
        defer {
            try? FileManager.default.removeItem(at: assetURL)
        }

        record[CloudWorkoutBackupField.schemaVersion] = NSNumber(value: 1)
        record[CloudWorkoutBackupField.createdAt] = payload.metadata.createdAt as NSDate
        record[CloudWorkoutBackupField.exportedAt] = payload.metadata.exportedAt as NSDate
        record[CloudWorkoutBackupField.workoutCount] = NSNumber(value: payload.metadata.workoutCount)
        record[CloudWorkoutBackupField.exerciseCount] = NSNumber(value: payload.metadata.exerciseCount)
        record[CloudWorkoutBackupField.splitCount] = NSNumber(value: payload.metadata.splitCount)
        record[CloudWorkoutBackupField.compressedByteCount] = NSNumber(value: payload.metadata.compressedByteCount)
        if let appVersion = payload.metadata.appVersion {
            record[CloudWorkoutBackupField.appVersion] = appVersion as NSString
        } else {
            record[CloudWorkoutBackupField.appVersion] = nil
        }
        record[CloudWorkoutBackupField.backupAsset] = CKAsset(fileURL: assetURL)

        _ = try await save(record)
        return payload.metadata
    }

    private func canAutomaticallyRestore(
        _ metadata: CloudWorkoutBackupMetadata,
        into context: ModelContext
    ) throws -> Bool {
        let existingWorkoutCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        guard existingWorkoutCount == 0 else { return false }

        if metadata.workoutCount > 0 {
            return true
        }

        return try context.fetchCount(FetchDescriptor<Exercise>()) == 0
            && context.fetchCount(FetchDescriptor<TrainingSplit>()) == 0
    }

    private func envelopeData(from record: CKRecord) throws -> Data {
        guard let asset = record[CloudWorkoutBackupField.backupAsset] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudWorkoutBackupError.missingBackupAsset
        }

        let compressedData = try Data(contentsOf: fileURL)
        return try (compressedData as NSData).decompressed(using: .lzfse) as Data
    }

    private func metadata(from record: CKRecord) throws -> CloudWorkoutBackupMetadata {
        guard let createdAt = dateField(CloudWorkoutBackupField.createdAt, in: record),
              let exportedAt = dateField(CloudWorkoutBackupField.exportedAt, in: record),
              let workoutCount = intField(CloudWorkoutBackupField.workoutCount, in: record),
              let exerciseCount = intField(CloudWorkoutBackupField.exerciseCount, in: record),
              let splitCount = intField(CloudWorkoutBackupField.splitCount, in: record),
              let compressedByteCount = intField(CloudWorkoutBackupField.compressedByteCount, in: record) else {
            throw CloudWorkoutBackupError.missingMetadata
        }

        return CloudWorkoutBackupMetadata(
            createdAt: createdAt,
            exportedAt: exportedAt,
            workoutCount: workoutCount,
            exerciseCount: exerciseCount,
            splitCount: splitCount,
            compressedByteCount: compressedByteCount,
            appVersion: record[CloudWorkoutBackupField.appVersion] as? String
        )
    }

    private func dateField(_ field: CKRecord.FieldKey, in record: CKRecord) -> Date? {
        if let date = record[field] as? Date {
            return date
        }
        if let date = record[field] as? NSDate {
            return date as Date
        }
        return nil
    }

    private func intField(_ field: CKRecord.FieldKey, in record: CKRecord) -> Int? {
        if let value = record[field] as? Int {
            return value
        }
        if let number = record[field] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func validateAccount() async throws {
        let status = try await accountStatus()
        switch status {
        case .available:
            return
        case .noAccount:
            throw CloudWorkoutBackupError.unavailable("Sign in to iCloud on this iPhone to use the cloud backup database.")
        case .restricted:
            throw CloudWorkoutBackupError.unavailable("iCloud is restricted for this Apple ID or device.")
        case .couldNotDetermine:
            throw CloudWorkoutBackupError.unavailable("Peakline could not confirm iCloud availability right now.")
        @unknown default:
            throw CloudWorkoutBackupError.unavailable("iCloud is not available right now.")
        }
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func fetchLatestRecord() async throws -> CKRecord? {
        do {
            return try await fetchRecord(with: CKRecord.ID(recordName: recordName))
        } catch {
            if isUnknownItem(error) {
                return nil
            }
            throw error
        }
    }

    private func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CloudWorkoutBackupError.noRecordReturned)
                }
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CloudWorkoutBackupError.noRecordReturned)
                }
            }
        }
    }

    private func isUnknownItem(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            return ckError.code == .unknownItem
        }

        let nsError = error as NSError
        return nsError.domain == CKErrorDomain && nsError.code == CKError.Code.unknownItem.rawValue
    }
}

private struct CloudWorkoutBackupPayload {
    let compressedData: Data
    let metadata: CloudWorkoutBackupMetadata
}

private enum CloudWorkoutBackupField {
    static let schemaVersion = "schemaVersion"
    static let createdAt = "createdAt"
    static let exportedAt = "exportedAt"
    static let workoutCount = "workoutCount"
    static let exerciseCount = "exerciseCount"
    static let splitCount = "splitCount"
    static let compressedByteCount = "compressedByteCount"
    static let appVersion = "appVersion"
    static let backupAsset = "backupAsset"
}

private enum CloudWorkoutBackupError: LocalizedError {
    case unavailable(String)
    case missingBackupAsset
    case missingMetadata
    case noRecordReturned

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .missingBackupAsset:
            return "The iCloud backup record is missing its backup file."
        case .missingMetadata:
            return "The iCloud backup record is missing required metadata."
        case .noRecordReturned:
            return "CloudKit did not return a backup record."
        }
    }

    var metadataOutcome: CloudWorkoutBackupMetadataOutcome {
        switch self {
        case .unavailable(let message):
            return .unavailable(message)
        default:
            return .failed(localizedDescription)
        }
    }

    var saveOutcome: CloudWorkoutBackupSaveOutcome {
        switch self {
        case .unavailable(let message):
            return .unavailable(message)
        default:
            return .failed(localizedDescription)
        }
    }

    var restoreOutcome: CloudWorkoutBackupRestoreOutcome {
        switch self {
        case .unavailable(let message):
            return .unavailable(message)
        default:
            return .failed(localizedDescription)
        }
    }
}
