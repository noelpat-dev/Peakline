import Foundation
import Security
import SwiftData

struct EmergencyBackupMetadata: Codable, Equatable {
    let createdAt: Date
    let exportedAt: Date
    let workoutCount: Int
    let exerciseCount: Int
    let splitCount: Int
    let appVersion: String?
}

enum EmergencyBackupSaveOutcome: Equatable {
    case saved(EmergencyBackupMetadata)
    case keptExistingWorkoutBackup(EmergencyBackupMetadata)
    case skippedUITestStore
    case failed(String)
}

enum EmergencyBackupRestoreOutcome: Equatable {
    case restored(LocalBackupImportSummary)
    case skippedStoreNotEmpty
    case skippedNoBackup
    case skippedUITestStore
    case failed(String)
}

protocol EmergencyBackupStoring {
    func readBackupRecord() throws -> Data?
    func writeBackupRecord(_ data: Data) throws
    func deleteBackupRecord() throws
}

struct KeychainEmergencyBackupStore: EmergencyBackupStoring {
    private let service = "PeaklineEmergencyBackup"
    private let account = "latest-workout-backup"

    func readBackupRecord() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainEmergencyBackupError.unhandledStatus(status)
        }
        return result as? Data
    }

    func writeBackupRecord(_ data: Data) throws {
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw KeychainEmergencyBackupError.unhandledStatus(addStatus)
        }

        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainEmergencyBackupError.unhandledStatus(updateStatus)
        }
    }

    func deleteBackupRecord() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainEmergencyBackupError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainEmergencyBackupError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain backup failed with status \(status)."
        }
    }
}

@MainActor
struct EmergencyBackupService {
    private let store: EmergencyBackupStoring
    private let exportService = LocalBackupExportService()
    private let importService = LocalBackupImportService()

    init(store: EmergencyBackupStoring = KeychainEmergencyBackupStore()) {
        self.store = store
    }

    func latestMetadata() -> EmergencyBackupMetadata? {
        do {
            return try loadRecord()?.metadata
        } catch {
            return nil
        }
    }

    func saveLatestBackup(in context: ModelContext) -> EmergencyBackupSaveOutcome {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") else {
            return .skippedUITestStore
        }

        do {
            let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let splits = try context.fetch(FetchDescriptor<TrainingSplit>())
            if workouts.isEmpty,
               let existingMetadata = try loadRecord()?.metadata,
               existingMetadata.workoutCount > 0 {
                return .keptExistingWorkoutBackup(existingMetadata)
            }
            let metadata = try saveBackup(workouts: workouts, exercises: exercises, splits: splits)
            return .saved(metadata)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func saveBackup(
        workouts: [WorkoutSession],
        exercises: [Exercise],
        splits: [TrainingSplit]
    ) throws -> EmergencyBackupMetadata {
        let envelope = exportService.makeEnvelope(workouts: workouts, exercises: exercises, splits: splits)
        let envelopeData = try exportService.encode(envelope)
        let record = try EmergencyBackupRecord(
            envelopeData: envelopeData,
            metadata: EmergencyBackupMetadata(
                createdAt: Date(),
                exportedAt: envelope.exportedAt,
                workoutCount: envelope.workouts.count,
                exerciseCount: envelope.exercises.count,
                splitCount: envelope.splits.count,
                appVersion: envelope.appVersion
            )
        )
        try store.writeBackupRecord(record.encoded())
        return record.metadata
    }

    func restoreIfNeeded(in context: ModelContext) -> EmergencyBackupRestoreOutcome {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") else {
            return .skippedUITestStore
        }

        do {
            guard let record = try loadRecord() else {
                return .skippedNoBackup
            }
            guard try canAutomaticallyRestore(record.metadata, into: context) else {
                return .skippedStoreNotEmpty
            }
            let envelopeData = try record.envelopeData()
            let summary = try importService.importBackup(
                from: envelopeData,
                into: context,
                replaceSeedDataWhenNoWorkouts: true
            )
            return .restored(summary)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func clearBackup() -> EmergencyBackupSaveOutcome {
        do {
            try store.deleteBackupRecord()
            return .saved(
                EmergencyBackupMetadata(
                    createdAt: Date(),
                    exportedAt: Date(),
                    workoutCount: 0,
                    exerciseCount: 0,
                    splitCount: 0,
                    appVersion: nil
                )
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func canAutomaticallyRestore(
        _ metadata: EmergencyBackupMetadata,
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

    private func loadRecord() throws -> EmergencyBackupRecord? {
        guard let data = try store.readBackupRecord() else { return nil }
        return try EmergencyBackupRecord.decode(from: data)
    }
}

private struct EmergencyBackupRecord: Codable {
    private let schemaVersion: Int
    private let compressionAlgorithm: String
    let metadata: EmergencyBackupMetadata
    let compressedEnvelopeData: Data

    init(envelopeData: Data, metadata: EmergencyBackupMetadata) throws {
        schemaVersion = 1
        compressionAlgorithm = "lzfse"
        self.metadata = metadata
        compressedEnvelopeData = try (envelopeData as NSData).compressed(using: .lzfse) as Data
    }

    func envelopeData() throws -> Data {
        guard schemaVersion == 1 else {
            throw EmergencyBackupRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        guard compressionAlgorithm == "lzfse" else {
            throw EmergencyBackupRecordError.unsupportedCompression
        }
        return try (compressedEnvelopeData as NSData).decompressed(using: .lzfse) as Data
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> EmergencyBackupRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EmergencyBackupRecord.self, from: data)
    }
}

private enum EmergencyBackupRecordError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case unsupportedCompression

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported emergency backup schema version \(version)."
        case .unsupportedCompression:
            "Unsupported emergency backup compression."
        }
    }
}
