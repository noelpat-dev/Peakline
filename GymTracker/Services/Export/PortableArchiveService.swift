import Foundation
import SwiftData

/// The on-disk wrapper is deliberately separate from the SwiftData schema and
/// from the cloud backup envelope. It can therefore evolve without changing
/// either of those compatibility surfaces.
struct PortableArchiveFile: Codable, Equatable, Sendable {
    static let currentFormatVersion = 4

    enum Protection: String, Codable, Sendable {
        case none
        case passphrase
    }

    let formatVersion: Int
    let appName: String
    let createdAt: Date
    let protection: Protection
    let crypto: BackupCryptoMetadata?
    let payload: Data

    init(
        formatVersion: Int = Self.currentFormatVersion,
        appName: String = "Peakline",
        createdAt: Date = Date(),
        protection: Protection,
        crypto: BackupCryptoMetadata? = nil,
        payload: Data
    ) {
        self.formatVersion = formatVersion
        self.appName = appName
        self.createdAt = createdAt
        self.protection = protection
        self.crypto = crypto
        self.payload = payload
    }
}

struct PortableArchivePayload: Codable, Sendable {
    let archiveVersion: Int
    let scope: Scope
    let exclusions: [String]
    let fullAppEnvelope: FullAppBackupEnvelope?
    /// Root-owned WorkspacePortableState is encoded here by the composition
    /// root. Keeping this as opaque Codable data avoids making the archive
    /// worker own SwiftData metadata or authentication types.
    let workspaceStateData: Data?

    enum Scope: String, Codable, Sendable {
        case fullWorkspace
        case workoutOnly
    }
}

struct PortableArchivePreview: Equatable, Sendable {
    let formatVersion: Int
    let scope: PortableArchivePayload.Scope
    let protection: PortableArchiveFile.Protection
    let createdAt: Date
    let counts: FullAppBackupCounts?
    let exclusions: [String]

    var title: String {
        scope == .fullWorkspace ? "Full Peakline workspace" : "Workout-only backup"
    }
}

enum PortableArchiveError: LocalizedError, Equatable {
    case malformedFile
    case wrongApplication(String)
    case unsupportedFormatVersion(Int)
    case unsupportedScope
    case passphraseRequired
    case payloadTooLarge
    case compressedPayloadTooLarge
    case legacyImportRequiresExplicitScope

    var errorDescription: String? {
        switch self {
        case .malformedFile:
            return "This file is not a valid Peakline archive."
        case .wrongApplication(let appName):
            return "This archive belongs to \(appName), not Peakline."
        case .unsupportedFormatVersion(let version):
            return "Archive format version \(version) is not supported by this version of Peakline."
        case .unsupportedScope:
            return "The archive does not declare a supported import scope."
        case .passphraseRequired:
            return "Enter the passphrase used to protect this archive."
        case .payloadTooLarge, .compressedPayloadTooLarge:
            return "The archive exceeds Peakline's safety limits."
        case .legacyImportRequiresExplicitScope:
            return "This older backup is narrower than a full workspace archive. Review its scope before importing."
        }
    }
}

@MainActor
struct PortableArchiveService {
    private let fullAppService: FullAppBackupService
    private let legacyExportService: LocalBackupExportService
    private let legacyImportService: LocalBackupImportService
    private let encryptionService: BackupEncryptionService

    init(
        fullAppService: FullAppBackupService? = nil,
        encryptionService: BackupEncryptionService? = nil
    ) {
        self.fullAppService = fullAppService ?? FullAppBackupService()
        self.legacyExportService = LocalBackupExportService()
        self.legacyImportService = LocalBackupImportService()
        self.encryptionService = encryptionService ?? BackupEncryptionService()
    }

    func makeFullArchive(
        in context: ModelContext,
        workspaceStateData: Data? = nil,
        passphrase: String? = nil
    ) throws -> Data {
        let envelope = try fullAppService.makeEnvelope(in: context)
        let state = try WorkspaceService.portableState(in: context)
        let stateData = try JSONEncoder().encode(state)
        let payload = PortableArchivePayload(
            archiveVersion: PortableArchiveFile.currentFormatVersion,
            scope: .fullWorkspace,
            exclusions: Self.defaultExclusions,
            fullAppEnvelope: envelope,
            workspaceStateData: workspaceStateData ?? stateData
        )
        return try encode(payload, passphrase: passphrase)
    }

    func writeArchive(_ data: Data, fileManager: FileManager = .default) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("PeaklineArchives", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "Peakline-Full-Archive-\(UUID().uuidString).peaklinearchive"
        )
        try data.write(to: url, options: [.atomic])
        return url
    }

    func makeFullArchive(
        in modelContainer: ModelContainer,
        workspaceStateData: Data? = nil,
        passphrase: String? = nil
    ) async throws -> Data {
        let envelope = try await fullAppService.makeEnvelope(in: modelContainer)
        let stateData = try JSONEncoder().encode(WorkspaceService.portableState(in: modelContainer.mainContext))
        let payload = PortableArchivePayload(
            archiveVersion: PortableArchiveFile.currentFormatVersion,
            scope: .fullWorkspace,
            exclusions: Self.defaultExclusions,
            fullAppEnvelope: envelope,
            workspaceStateData: workspaceStateData ?? stateData
        )
        return try encode(payload, passphrase: passphrase)
    }

    func preview(_ data: Data, passphrase: String? = nil) throws -> PortableArchivePreview {
        let decoded = try decode(data, passphrase: passphrase)
        return preview(decoded.file, payload: decoded.payload)
    }

    func importArchive(
        from data: Data,
        into context: ModelContext,
        replaceExisting: Bool,
        passphrase: String? = nil,
        applyWorkspaceState: ((Data) throws -> Void)? = nil
    ) throws -> FullAppBackupImportSummary {
        if passphrase == nil,
           let legacy = try? fullAppService.decodeEnvelope(from: data) {
            try fullAppService.validate(legacy)
            let summary = try fullAppService.importBackup(
                legacy,
                into: context,
                replaceExisting: replaceExisting
            )
            try WorkspaceService.applyPortableState(nil, in: context)
            try context.save()
            return summary
        }
        if passphrase == nil,
           let workoutOnly = try? legacyExportService.decodeEnvelope(from: data) {
            let imported = try legacyImportService.importBackup(
                workoutOnly,
                into: context,
                replaceSeedDataWhenNoWorkouts: false
            )
            return FullAppBackupImportSummary(
                counts: FullAppBackupCounts(
                    userProfileCount: 0,
                    exerciseCount: imported.exerciseCount,
                    splitCount: imported.splitCount,
                    workoutCount: imported.workoutCount,
                    recommendationCount: 0,
                    bodyweightCount: 0,
                    foodItemCount: 0,
                    foodLogCount: 0,
                    hydrationCount: 0,
                    sleepCount: 0,
                    napCount: 0,
                    coachRecordCount: 0,
                    userContentCount: imported.workoutCount,
                    workoutTemplateCount: nil
                ),
                importedAt: imported.importedAt
            )
        }
        let decoded = try decode(data, passphrase: passphrase)
        guard decoded.payload.scope == .fullWorkspace,
              let envelope = decoded.payload.fullAppEnvelope else {
            throw PortableArchiveError.legacyImportRequiresExplicitScope
        }
        let portableState: WorkspacePortableState?
        if let stateData = decoded.payload.workspaceStateData {
            do {
                portableState = try JSONDecoder().decode(WorkspacePortableState.self, from: stateData)
            } catch {
                throw PortableArchiveError.malformedFile
            }
        } else {
            portableState = nil
        }
        let summary = try fullAppService.importBackup(
            envelope,
            into: context,
            replaceExisting: replaceExisting,
            workspaceState: portableState
        )
        if let stateData = decoded.payload.workspaceStateData, let applyWorkspaceState {
            try applyWorkspaceState(stateData)
        }
        return summary
    }

    /// Reads the historical workout-only v2 JSON and full-app v2/v3 envelope.
    /// Callers must show the returned scope before allowing replacement.
    func previewLegacy(_ data: Data) throws -> PortableArchivePreview {
        if let envelope = try? fullAppService.decodeEnvelope(from: data) {
            try fullAppService.validate(envelope)
            return PortableArchivePreview(
                formatVersion: envelope.schemaVersion,
                scope: .fullWorkspace,
                protection: .none,
                createdAt: envelope.exportedAt,
                counts: envelope.counts,
                exclusions: Self.defaultExclusions
            )
        }
        let envelope = try legacyExportService.decodeEnvelope(from: data)
        return PortableArchivePreview(
            formatVersion: envelope.schemaVersion,
            scope: .workoutOnly,
            protection: .none,
            createdAt: envelope.exportedAt,
            counts: FullAppBackupCounts(
                userProfileCount: 0,
                exerciseCount: envelope.exercises.count,
                splitCount: envelope.splits.count,
                workoutCount: envelope.workouts.count,
                recommendationCount: 0,
                bodyweightCount: 0,
                foodItemCount: 0,
                foodLogCount: 0,
                hydrationCount: 0,
                sleepCount: 0,
                napCount: 0,
                coachRecordCount: 0,
                userContentCount: envelope.workouts.count,
                workoutTemplateCount: nil
            ),
            exclusions: Self.defaultExclusions
        )
    }

    private func encode(_ payload: PortableArchivePayload, passphrase: String?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        guard payloadData.count <= FullAppBackupLimits.maxDecompressedPayloadBytes else {
            throw PortableArchiveError.payloadTooLarge
        }
        let compressed = try (payloadData as NSData).compressed(using: .lzfse) as Data
        guard compressed.count <= FullAppBackupLimits.maxCompressedPayloadBytes else {
            throw PortableArchiveError.compressedPayloadTooLarge
        }

        let file: PortableArchiveFile
        if let passphrase {
            guard !passphrase.isEmpty else { throw BackupEncryptionError.passphraseRequired }
            let material = try encryptionService.deriveKey(
                passphrase: passphrase,
                salt: try encryptionService.randomData(count: BackupEncryptionService.saltByteCount)
            )
            let encrypted = try encryptionService.encrypt(plaintext: compressed, keyMaterial: material)
            file = PortableArchiveFile(
                protection: .passphrase,
                crypto: encrypted.crypto,
                payload: encrypted.ciphertext
            )
        } else {
            file = PortableArchiveFile(protection: .none, payload: compressed)
        }
        return try encoder.encode(file)
    }

    private func decode(_ data: Data, passphrase: String?) throws -> (file: PortableArchiveFile, payload: PortableArchivePayload) {
        guard data.count <= FullAppBackupLimits.maxDecompressedPayloadBytes else {
            throw PortableArchiveError.payloadTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: PortableArchiveFile
        do { file = try decoder.decode(PortableArchiveFile.self, from: data) }
        catch { throw PortableArchiveError.malformedFile }
        guard file.appName == "Peakline" else { throw PortableArchiveError.wrongApplication(file.appName) }
        guard file.formatVersion == PortableArchiveFile.currentFormatVersion else {
            throw PortableArchiveError.unsupportedFormatVersion(file.formatVersion)
        }
        let compressed: Data
        switch file.protection {
        case .none:
            guard file.crypto == nil else { throw PortableArchiveError.malformedFile }
            compressed = file.payload
        case .passphrase:
            guard let passphrase, !passphrase.isEmpty else { throw PortableArchiveError.passphraseRequired }
            guard let crypto = file.crypto else { throw PortableArchiveError.malformedFile }
            let material = try encryptionService.deriveKey(
                passphrase: passphrase,
                salt: crypto.saltData ?? Data(),
                iterationCount: crypto.iterationCount
            )
            compressed = try encryptionService.decrypt(
                ciphertext: file.payload,
                crypto: crypto,
                keyData: material.keyData
            )
        }
        guard compressed.count <= FullAppBackupLimits.maxCompressedPayloadBytes else {
            throw PortableArchiveError.compressedPayloadTooLarge
        }
        let payloadData: Data
        do { payloadData = try (compressed as NSData).decompressed(using: .lzfse) as Data }
        catch { throw PortableArchiveError.malformedFile }
        guard payloadData.count <= FullAppBackupLimits.maxDecompressedPayloadBytes else {
            throw PortableArchiveError.payloadTooLarge
        }
        let payload: PortableArchivePayload
        do { payload = try decoder.decode(PortableArchivePayload.self, from: payloadData) }
        catch { throw PortableArchiveError.malformedFile }
        guard payload.archiveVersion == PortableArchiveFile.currentFormatVersion,
              payload.scope == .fullWorkspace,
              payload.fullAppEnvelope != nil else {
            throw PortableArchiveError.unsupportedScope
        }
        return (file, payload)
    }

    private func preview(_ file: PortableArchiveFile, payload: PortableArchivePayload) -> PortableArchivePreview {
        PortableArchivePreview(
            formatVersion: file.formatVersion,
            scope: payload.scope,
            protection: file.protection,
            createdAt: file.createdAt,
            counts: payload.fullAppEnvelope?.counts,
            exclusions: payload.exclusions
        )
    }

    static let defaultExclusions = [
        "Firebase credentials and account bindings",
        "Backup passphrases and encryption keys",
        "Machine paths and cached derived values",
        "HealthKit permission state and automatic write consent",
        "Device-specific notification and permission state"
    ]
}
