import CommonCrypto
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Security
import SwiftData

struct BackupCryptoMetadata: Codable, Equatable, Sendable {
    let algorithm: String
    let keyDerivation: String
    let iterationCount: Int
    let saltBase64: String
    let nonceBase64: String
    let tagBase64: String

    init(
        algorithm: String = "AES-GCM-256",
        keyDerivation: String = "PBKDF2-HMAC-SHA256",
        iterationCount: Int,
        salt: Data,
        nonce: Data,
        tag: Data
    ) {
        self.algorithm = algorithm
        self.keyDerivation = keyDerivation
        self.iterationCount = iterationCount
        saltBase64 = salt.base64EncodedString()
        nonceBase64 = nonce.base64EncodedString()
        tagBase64 = tag.base64EncodedString()
    }

    var saltData: Data? { Data(base64Encoded: saltBase64) }
    var nonceData: Data? { Data(base64Encoded: nonceBase64) }
    var tagData: Data? { Data(base64Encoded: tagBase64) }

    func validateSupported() throws {
        guard algorithm == "AES-GCM-256" else {
            throw BackupEncryptionError.unsupportedAlgorithm(algorithm)
        }
        guard keyDerivation == "PBKDF2-HMAC-SHA256" else {
            throw BackupEncryptionError.unsupportedKeyDerivation(keyDerivation)
        }
        guard (10_000...5_000_000).contains(iterationCount),
              saltData?.count == BackupEncryptionService.saltByteCount,
              nonceData?.count == BackupEncryptionService.nonceByteCount,
              tagData?.count == 16 else {
            throw BackupEncryptionError.missingCryptoMetadata
        }
    }
}

struct RemoteFullAppBackupHeader: Equatable, Sendable {
    let metadata: FullAppBackupMetadata
    let crypto: BackupCryptoMetadata
}

struct RemoteFullAppBackupRecord: Equatable, Sendable {
    let metadata: FullAppBackupMetadata
    let crypto: BackupCryptoMetadata
    let encryptedData: Data
}

protocol RemoteFullAppBackupStoring {
    func latestMetadata() async throws -> FullAppBackupMetadata?
    func latestHeader() async throws -> RemoteFullAppBackupHeader?
    func latestRecord() async throws -> RemoteFullAppBackupRecord?
    func saveRecord(_ record: RemoteFullAppBackupRecord) async throws
}

extension RemoteFullAppBackupStoring {
    func latestHeader() async throws -> RemoteFullAppBackupHeader? {
        guard let record = try await latestRecord() else { return nil }
        return RemoteFullAppBackupHeader(metadata: record.metadata, crypto: record.crypto)
    }
}

actor BackupPayloadWorker {
    func encodeAndCompress(_ envelope: FullAppBackupEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        return try (data as NSData).compressed(using: .lzfse) as Data
    }

    func deriveKey(passphrase: String, salt: Data, iterationCount: Int?) throws -> BackupKeyMaterial {
        try BackupEncryptionService().deriveKey(
            passphrase: passphrase,
            salt: salt,
            iterationCount: iterationCount
        )
    }

    func encrypt(_ data: Data, keyMaterial: BackupKeyMaterial) throws -> EncryptedBackupPayload {
        try BackupEncryptionService().encrypt(plaintext: data, keyMaterial: keyMaterial)
    }

    func decrypt(_ record: RemoteFullAppBackupRecord, keyData: Data) throws -> Data {
        try BackupEncryptionService().decrypt(
            ciphertext: record.encryptedData,
            crypto: record.crypto,
            keyData: keyData
        )
    }

    func decryptDecompressAndDecode(
        _ record: RemoteFullAppBackupRecord,
        keyData: Data
    ) throws -> (envelope: FullAppBackupEnvelope, compressedByteCount: Int) {
        let compressedData = try decrypt(record, keyData: keyData)
        let envelopeData = try (compressedData as NSData).decompressed(using: .lzfse) as Data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (
            try decoder.decode(FullAppBackupEnvelope.self, from: envelopeData),
            compressedData.count
        )
    }
}

enum BackupCoordinatorMetadataOutcome: Equatable {
    case available(FullAppBackupMetadata)
    case noBackup
    case unavailable(String)
    case failed(String)
}

enum BackupCoordinatorSaveOutcome: Equatable {
    case saved(FullAppBackupMetadata)
    case keptExistingBackup(FullAppBackupMetadata)
    case passphraseRequired
    case unavailable(String)
    case failed(String)
}

enum BackupCoordinatorRestoreOutcome: Equatable {
    case restored(FullAppBackupImportSummary)
    case skippedNoBackup
    case skippedStoreNotEmpty
    case passphraseRequired
    case unavailable(String)
    case failed(String)
}

@MainActor
struct BackupCoordinator {
    private let backupService: FullAppBackupService
    private let store: RemoteFullAppBackupStoring
    private let encryptionService: BackupEncryptionService
    private let keyCache: BackupEncryptionKeyCaching
    private let payloadWorker: BackupPayloadWorker

    init() {
        backupService = FullAppBackupService()
        store = FirebaseFullAppBackupStore()
        encryptionService = BackupEncryptionService()
        keyCache = KeychainBackupEncryptionKeyCache()
        payloadWorker = BackupPayloadWorker()
    }

    init(store: RemoteFullAppBackupStoring) {
        backupService = FullAppBackupService()
        self.store = store
        encryptionService = BackupEncryptionService()
        keyCache = InMemoryBackupEncryptionKeyCache()
        payloadWorker = BackupPayloadWorker()
    }

    init(
        backupService: FullAppBackupService,
        store: RemoteFullAppBackupStoring,
        encryptionService: BackupEncryptionService = BackupEncryptionService(),
        keyCache: BackupEncryptionKeyCaching = InMemoryBackupEncryptionKeyCache()
    ) {
        self.backupService = backupService
        self.store = store
        self.encryptionService = encryptionService
        self.keyCache = keyCache
        payloadWorker = BackupPayloadWorker()
    }

    func latestMetadata() async -> BackupCoordinatorMetadataOutcome {
        do {
            guard let metadata = try await store.latestMetadata() else {
                return .noBackup
            }
            return .available(metadata)
        } catch FirebaseFullAppBackupError.unavailable(let message) {
            return .unavailable(message)
        } catch let error as FirebaseFullAppBackupError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func saveLatestBackup(in context: ModelContext, passphrase: String? = nil) async -> BackupCoordinatorSaveOutcome {
        do {
            try Task.checkCancellation()
            // Persist any edits still pending in the UI context before the
            // background snapshot actor opens its own context.
            if context.hasChanges {
                try context.save()
            }
            let envelope = try await backupService.makeEnvelope(in: context.container)
            try Task.checkCancellation()
            let compressedData = try await payloadWorker.encodeAndCompress(envelope)
            try Task.checkCancellation()
            let metadata = FullAppBackupMetadata(
                createdAt: Date(),
                exportedAt: envelope.exportedAt,
                counts: envelope.counts,
                compressedByteCount: compressedData.count,
                appVersion: envelope.appVersion
            )
            let existingHeader = try await store.latestHeader()
            try Task.checkCancellation()

            if metadata.counts.userContentCount == 0,
               let existingHeader,
               existingHeader.metadata.counts.userContentCount > 0 {
                return .keptExistingBackup(existingHeader.metadata)
            }

            let keyMaterial = try await resolveKeyMaterial(
                passphrase: passphrase,
                existingCrypto: existingHeader?.crypto
            )
            if let existingHeader,
               existingHeader.metadata.counts.userContentCount > 0,
               !keyMaterial.loadedFromCache,
               let existingRecord = try await store.latestRecord() {
                _ = try await payloadWorker.decrypt(existingRecord, keyData: keyMaterial.keyData)
            }

            let encrypted = try await payloadWorker.encrypt(compressedData, keyMaterial: keyMaterial.material)
            try Task.checkCancellation()
            let record = RemoteFullAppBackupRecord(
                metadata: metadata,
                crypto: encrypted.crypto,
                encryptedData: encrypted.ciphertext
            )
            try await store.saveRecord(record)
            // Once saveRecord returns, its atomic pointer commit has completed.
            // Report success even if cancellation arrives after that commit so
            // the UI never claims the previous cloud copy was preserved when
            // the new generation is already live.
            try keyCache.write(keyMaterial.material)
            return .saved(metadata)
        } catch is CancellationError {
            return .failed("Backup was cancelled before it replaced the previous cloud copy.")
        } catch BackupEncryptionError.passphraseRequired {
            return .passphraseRequired
        } catch BackupEncryptionError.invalidPassphrase {
            return .failed("Backup passphrase did not unlock the existing backup.")
        } catch FirebaseFullAppBackupError.unavailable(let message) {
            return .unavailable(message)
        } catch let error as FirebaseFullAppBackupError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restoreLatestBackup(
        in context: ModelContext,
        replaceExisting: Bool,
        passphrase: String? = nil
    ) async -> BackupCoordinatorRestoreOutcome {
        do {
            try Task.checkCancellation()
            guard let record = try await store.latestRecord() else {
                return .skippedNoBackup
            }
            try Task.checkCancellation()
            if !replaceExisting, try backupService.userContentCount(in: context) > 0 {
                return .skippedStoreNotEmpty
            }
            let keyMaterial = try await resolveKeyMaterial(passphrase: passphrase, existingCrypto: record.crypto)
            let decoded = try await payloadWorker.decryptDecompressAndDecode(record, keyData: keyMaterial.keyData)
            try Task.checkCancellation()
            guard decoded.compressedByteCount == record.metadata.compressedByteCount else {
                throw FirebaseFullAppBackupError.integrityCheckFailed
            }
            try backupService.validate(decoded.envelope)
            guard decoded.envelope.counts == record.metadata.counts else {
                throw FirebaseFullAppBackupError.integrityCheckFailed
            }
            let summary = try backupService.importBackup(decoded.envelope, into: context, replaceExisting: true)
            try keyCache.write(keyMaterial.material)
            return .restored(summary)
        } catch is CancellationError {
            return .failed("Restore was cancelled before local data was replaced.")
        } catch BackupEncryptionError.passphraseRequired {
            return .passphraseRequired
        } catch BackupEncryptionError.invalidPassphrase {
            return .failed("Backup passphrase is incorrect.")
        } catch FirebaseFullAppBackupError.unavailable(let message) {
            return .unavailable(message)
        } catch let error as FirebaseFullAppBackupError {
            return .failed(error.localizedDescription)
        } catch FullAppBackupError.storeNotEmpty {
            return .skippedStoreNotEmpty
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func canPromptRestore(in context: ModelContext) throws -> Bool {
        try backupService.userContentCount(in: context) == 0
    }

    private func resolveKeyMaterial(
        passphrase: String?,
        existingCrypto: BackupCryptoMetadata?
    ) async throws -> ResolvedBackupKeyMaterial {
        try existingCrypto?.validateSupported()
        let existingSalt = existingCrypto?.saltData
        if let cached = try keyCache.read(),
           (existingSalt == nil || cached.salt == existingSalt),
           (existingCrypto == nil || cached.iterationCount == existingCrypto?.iterationCount) {
            return ResolvedBackupKeyMaterial(material: cached, loadedFromCache: true)
        }

        guard let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupEncryptionError.passphraseRequired
        }

        let salt = try existingSalt ?? encryptionService.randomData(count: BackupEncryptionService.saltByteCount)
        let material = try await payloadWorker.deriveKey(
            passphrase: passphrase,
            salt: salt,
            iterationCount: existingCrypto?.iterationCount
        )
        return ResolvedBackupKeyMaterial(material: material, loadedFromCache: false)
    }
}

struct FirebaseFullAppBackupStore: RemoteFullAppBackupStoring {
    private let chunkByteLimit = 480 * 1_024

    func latestMetadata() async throws -> FullAppBackupMetadata? {
        let backupReference = try backupDocumentReference()
        let snapshot = try await getDocument(backupReference)
        guard snapshot.exists, let data = snapshot.data() else {
            return nil
        }
        return try metadata(from: data)
    }

    func latestHeader() async throws -> RemoteFullAppBackupHeader? {
        let pointerReference = try backupDocumentReference()
        let snapshot = try await getDocument(pointerReference)
        guard snapshot.exists, let data = snapshot.data() else {
            return nil
        }
        return try header(from: data)
    }

    func latestRecord() async throws -> RemoteFullAppBackupRecord? {
        let pointerReference = try backupDocumentReference()
        let pointerSnapshot = try await getDocument(pointerReference)
        guard pointerSnapshot.exists, let pointerData = pointerSnapshot.data() else {
            return nil
        }

        if let generationID = pointerData["generationID"] as? String {
            let generationReference = pointerReference.collection("generations").document(generationID)
            let generationSnapshot = try await getDocument(generationReference)
            guard generationSnapshot.exists,
                  let generationData = generationSnapshot.data(),
                  generationData["generationID"] as? String == generationID else {
                throw FirebaseFullAppBackupError.missingRecordData
            }

            let chunkCount = try validatedChunkCount(from: generationData)
            let encryptedData = try await encryptedPayload(
                from: generationReference,
                chunkCount: chunkCount,
                expectedGenerationID: generationID
            )
            guard let expectedHash = generationData["payloadSHA256"] as? String,
                  expectedHash == Self.sha256Hex(encryptedData) else {
                throw FirebaseFullAppBackupError.integrityCheckFailed
            }
            let generationHeader = try header(from: generationData)
            return RemoteFullAppBackupRecord(
                metadata: generationHeader.metadata,
                crypto: generationHeader.crypto,
                encryptedData: encryptedData
            )
        }

        // Backward-compatible reader for the original mutable `latest/chunks` layout.
        let chunkCount = try validatedChunkCount(from: pointerData)
        let encryptedData = try await encryptedPayload(
            from: pointerReference,
            chunkCount: chunkCount,
            expectedGenerationID: nil
        )
        let legacyHeader = try header(from: pointerData)
        return RemoteFullAppBackupRecord(
            metadata: legacyHeader.metadata,
            crypto: legacyHeader.crypto,
            encryptedData: encryptedData
        )
    }

    func saveRecord(_ record: RemoteFullAppBackupRecord) async throws {
        try record.crypto.validateSupported()
        let pointerReference = try backupDocumentReference()
        let generationID = UUID().uuidString.lowercased()
        let generationReference = pointerReference.collection("generations").document(generationID)
        let chunks = Self.split(record.encryptedData, chunkByteLimit: chunkByteLimit)
        let payloadHash = Self.sha256Hex(record.encryptedData)

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            try await setData(
                [
                    "generationID": generationID,
                    "index": index,
                    "payloadBase64": chunk.base64EncodedString(),
                    "sha256": Self.sha256Hex(chunk)
                ],
                on: generationReference.collection("chunks").document(chunkID(index))
            )
        }

        try Task.checkCancellation()
        var manifest = try metadataData(for: record, chunkCount: chunks.count)
        manifest["storageSchemaVersion"] = 3
        manifest["generationID"] = generationID
        manifest["payloadSHA256"] = payloadHash
        manifest["state"] = "complete"
        try await setData(manifest, on: generationReference)

        // This single pointer write is the commit point. Until it succeeds, readers
        // continue to resolve the prior immutable generation.
        try Task.checkCancellation()
        try await setData(manifest, on: pointerReference)
    }

    private func backupDocumentReference() throws -> DocumentReference {
        guard FirebaseBootstrap.isConfigured else {
            throw FirebaseFullAppBackupError.unavailable("Firebase is not configured. Add GoogleService-Info.plist from your Firebase project.")
        }
        guard let userID = Auth.auth().currentUser?.uid else {
            throw FirebaseFullAppBackupError.unavailable("Sign in to your Peakline backup account first.")
        }
        return Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("backups")
            .document("latest")
    }

    private func metadataData(for record: RemoteFullAppBackupRecord, chunkCount: Int) throws -> [String: Any] {
        [
            "schemaVersion": 3,
            "createdAt": Timestamp(date: record.metadata.createdAt),
            "exportedAt": Timestamp(date: record.metadata.exportedAt),
            "countsJSON": String(data: try JSONEncoder().encode(record.metadata.counts), encoding: .utf8) ?? "{}",
            "userContentCount": record.metadata.counts.userContentCount,
            "totalRecordCount": record.metadata.counts.totalRecordCount,
            "workoutCount": record.metadata.counts.workoutCount,
            "foodLogCount": record.metadata.counts.foodLogCount,
            "sleepCount": record.metadata.counts.sleepCount,
            "hydrationCount": record.metadata.counts.hydrationCount,
            "compressedByteCount": record.metadata.compressedByteCount,
            "appVersion": record.metadata.appVersion ?? NSNull(),
            "chunkCount": chunkCount,
            "encryptionAlgorithm": record.crypto.algorithm,
            "keyDerivation": record.crypto.keyDerivation,
            "iterationCount": record.crypto.iterationCount,
            "saltBase64": record.crypto.saltBase64,
            "nonceBase64": record.crypto.nonceBase64,
            "tagBase64": record.crypto.tagBase64
        ]
    }

    private func metadata(from data: [String: Any]) throws -> FullAppBackupMetadata {
        let counts: FullAppBackupCounts
        if let countsJSON = data["countsJSON"] as? String,
           let countsData = countsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(FullAppBackupCounts.self, from: countsData) {
            counts = decoded
        } else {
            counts = FullAppBackupCounts(
                userProfileCount: 0,
                exerciseCount: 0,
                splitCount: 0,
                workoutCount: data["workoutCount"] as? Int ?? 0,
                recommendationCount: 0,
                bodyweightCount: 0,
                foodItemCount: 0,
                foodLogCount: data["foodLogCount"] as? Int ?? 0,
                hydrationCount: data["hydrationCount"] as? Int ?? 0,
                sleepCount: data["sleepCount"] as? Int ?? 0,
                napCount: 0,
                coachRecordCount: 0,
                userContentCount: data["userContentCount"] as? Int ?? 0
            )
        }
        return FullAppBackupMetadata(
            createdAt: try dateField("createdAt", in: data),
            exportedAt: try dateField("exportedAt", in: data),
            counts: counts,
            compressedByteCount: try intField("compressedByteCount", in: data),
            appVersion: data["appVersion"] as? String
        )
    }

    private func crypto(from data: [String: Any]) throws -> BackupCryptoMetadata {
        guard let salt = Data(base64Encoded: try stringField("saltBase64", in: data)),
              let nonce = Data(base64Encoded: try stringField("nonceBase64", in: data)),
              let tag = Data(base64Encoded: try stringField("tagBase64", in: data)) else {
            throw FirebaseFullAppBackupError.missingRecordData
        }
        let metadata = BackupCryptoMetadata(
            algorithm: try stringField("encryptionAlgorithm", in: data),
            keyDerivation: try stringField("keyDerivation", in: data),
            iterationCount: try intField("iterationCount", in: data),
            salt: salt,
            nonce: nonce,
            tag: tag
        )
        try metadata.validateSupported()
        return metadata
    }

    private func header(from data: [String: Any]) throws -> RemoteFullAppBackupHeader {
        RemoteFullAppBackupHeader(
            metadata: try metadata(from: data),
            crypto: try crypto(from: data)
        )
    }

    private func validatedChunkCount(from data: [String: Any]) throws -> Int {
        let count = try intField("chunkCount", in: data)
        guard (1...10_000).contains(count) else {
            throw FirebaseFullAppBackupError.missingRecordData
        }
        return count
    }

    private func encryptedPayload(
        from backupReference: DocumentReference,
        chunkCount: Int,
        expectedGenerationID: String?
    ) async throws -> Data {
        var data = Data()
        for index in 0..<chunkCount {
            try Task.checkCancellation()
            let snapshot = try await getDocument(backupReference.collection("chunks").document(chunkID(index)))
            guard let chunkData = snapshot.data(),
                  let storedIndex = chunkData["index"] as? Int,
                  storedIndex == index,
                  expectedGenerationID == nil || chunkData["generationID"] as? String == expectedGenerationID,
                  let payload = chunkData["payloadBase64"] as? String,
                  let chunk = Data(base64Encoded: payload),
                  chunkData["sha256"] == nil || chunkData["sha256"] as? String == Self.sha256Hex(chunk) else {
                throw FirebaseFullAppBackupError.missingRecordData
            }
            data.append(chunk)
        }
        return data
    }

    private func deleteChunks(after chunkCount: Int, from backupReference: DocumentReference) async throws {
        let snapshot = try await getDocuments(backupReference.collection("chunks"))
        for document in snapshot.documents {
            guard let index = document.data()["index"] as? Int, index >= chunkCount else { continue }
            try await delete(document.reference)
        }
    }

    static func split(_ data: Data, chunkByteLimit: Int) -> [Data] {
        precondition(chunkByteLimit > 0)
        guard !data.isEmpty else { return [Data()] }

        var chunks: [Data] = []
        var chunkStart = data.startIndex
        while chunkStart < data.endIndex {
            let chunkEnd = data.index(
                chunkStart,
                offsetBy: chunkByteLimit,
                limitedBy: data.endIndex
            ) ?? data.endIndex
            chunks.append(Data(data[chunkStart..<chunkEnd]))
            chunkStart = chunkEnd
        }
        return chunks
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func chunkID(_ index: Int) -> String {
        String(format: "%05d", index)
    }

    private func dateField(_ field: String, in data: [String: Any]) throws -> Date {
        if let timestamp = data[field] as? Timestamp { return timestamp.dateValue() }
        if let date = data[field] as? Date { return date }
        throw FirebaseFullAppBackupError.missingRecordData
    }

    private func intField(_ field: String, in data: [String: Any]) throws -> Int {
        if let value = data[field] as? Int { return value }
        if let number = data[field] as? NSNumber { return number.intValue }
        throw FirebaseFullAppBackupError.missingRecordData
    }

    private func stringField(_ field: String, in data: [String: Any]) throws -> String {
        guard let value = data[field] as? String else {
            throw FirebaseFullAppBackupError.missingRecordData
        }
        return value
    }

    private func getDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseFullAppBackupError.missingRecordData)
                }
            }
        }
    }

    private func getDocuments(_ reference: CollectionReference) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseFullAppBackupError.missingRecordData)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], on reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func delete(_ reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct BackupKeyMaterial: Codable, Equatable, Sendable {
    let keyData: Data
    let salt: Data
    let iterationCount: Int
}

private struct ResolvedBackupKeyMaterial {
    let material: BackupKeyMaterial
    let loadedFromCache: Bool

    var keyData: Data { material.keyData }
}

struct EncryptedBackupPayload: Sendable {
    let ciphertext: Data
    let crypto: BackupCryptoMetadata
}

struct BackupEncryptionService {
    static let saltByteCount = 16
    static let nonceByteCount = 12

    private let keyByteCount = 32
    private let defaultIterationCount = 210_000

    func deriveKey(
        passphrase: String,
        salt: Data,
        iterationCount: Int? = nil
    ) throws -> BackupKeyMaterial {
        let iterations = iterationCount ?? defaultIterationCount
        guard !passphrase.isEmpty else {
            throw BackupEncryptionError.passphraseRequired
        }
        guard (10_000...5_000_000).contains(iterations) else {
            throw BackupEncryptionError.invalidIterationCount(iterations)
        }

        let passwordData = Data(passphrase.utf8)
        var keyData = Data(count: keyByteCount)
        let status = keyData.withUnsafeMutableBytes { keyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw BackupEncryptionError.keyDerivationFailed
        }
        return BackupKeyMaterial(keyData: keyData, salt: salt, iterationCount: iterations)
    }

    func encrypt(plaintext: Data, keyMaterial: BackupKeyMaterial) throws -> EncryptedBackupPayload {
        let nonceData = try randomData(count: Self.nonceByteCount)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = SymmetricKey(data: keyMaterial.keyData)
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        return EncryptedBackupPayload(
            ciphertext: sealedBox.ciphertext,
            crypto: BackupCryptoMetadata(
                iterationCount: keyMaterial.iterationCount,
                salt: keyMaterial.salt,
                nonce: nonceData,
                tag: sealedBox.tag
            )
        )
    }

    func decrypt(ciphertext: Data, crypto: BackupCryptoMetadata, keyData: Data) throws -> Data {
        try crypto.validateSupported()
        guard let nonceData = crypto.nonceData,
              let tagData = crypto.tagData else {
            throw BackupEncryptionError.missingCryptoMetadata
        }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tagData
            )
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw BackupEncryptionError.invalidPassphrase
        }
    }

    func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BackupEncryptionError.randomGenerationFailed
        }
        return data
    }
}

protocol BackupEncryptionKeyCaching {
    func read() throws -> BackupKeyMaterial?
    func write(_ material: BackupKeyMaterial) throws
    func delete() throws
}

struct KeychainBackupEncryptionKeyCache: BackupEncryptionKeyCaching {
    private let service = "PeaklineFirebaseBackupEncryptionKey"
    private let accountIdentifierOverride: String?

    init(accountIdentifier: String? = nil) {
        accountIdentifierOverride = accountIdentifier
    }

    func read() throws -> BackupKeyMaterial? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw BackupEncryptionError.keychainStatus(status)
        }
        return try JSONDecoder().decode(BackupKeyMaterial.self, from: data)
    }

    func write(_ material: BackupKeyMaterial) throws {
        let data = try JSONEncoder().encode(material)
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else {
            throw BackupEncryptionError.keychainStatus(addStatus)
        }
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw BackupEncryptionError.keychainStatus(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackupEncryptionError.keychainStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private var account: String {
        if let accountIdentifierOverride {
            return "firebase-backup-key-\(accountIdentifierOverride)"
        }
        if FirebaseBootstrap.isConfigured, let userID = Auth.auth().currentUser?.uid {
            return "firebase-backup-key-\(userID)"
        }
        return "firebase-backup-key-primary"
    }
}

final class InMemoryBackupEncryptionKeyCache: BackupEncryptionKeyCaching {
    private var material: BackupKeyMaterial?

    func read() throws -> BackupKeyMaterial? {
        material
    }

    func write(_ material: BackupKeyMaterial) throws {
        self.material = material
    }

    func delete() throws {
        material = nil
    }
}

enum FirebaseFullAppBackupError: LocalizedError, Equatable {
    case unavailable(String)
    case missingRecordData
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .missingRecordData:
            return "The Firebase backup record is incomplete."
        case .integrityCheckFailed:
            return "The Firebase backup failed its integrity check and was not restored."
        }
    }
}

enum BackupEncryptionError: LocalizedError, Equatable {
    case passphraseRequired
    case invalidPassphrase
    case keyDerivationFailed
    case missingCryptoMetadata
    case unsupportedAlgorithm(String)
    case unsupportedKeyDerivation(String)
    case invalidIterationCount(Int)
    case randomGenerationFailed
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .passphraseRequired:
            return "Enter your backup passphrase."
        case .invalidPassphrase:
            return "Backup passphrase is incorrect."
        case .keyDerivationFailed:
            return "Could not derive the backup encryption key."
        case .missingCryptoMetadata:
            return "The encrypted backup is missing required security metadata."
        case .unsupportedAlgorithm(let algorithm):
            return "Backup encryption algorithm \(algorithm) is not supported."
        case .unsupportedKeyDerivation(let keyDerivation):
            return "Backup key derivation \(keyDerivation) is not supported."
        case .invalidIterationCount(let count):
            return "Backup key derivation iteration count \(count) is not supported."
        case .randomGenerationFailed:
            return "Could not create secure random backup data."
        case .keychainStatus(let status):
            return "Backup keychain storage failed with status \(status)."
        }
    }
}

final class InMemoryRemoteFullAppBackupStore: RemoteFullAppBackupStoring {
    var record: RemoteFullAppBackupRecord?

    func latestMetadata() async throws -> FullAppBackupMetadata? {
        record?.metadata
    }

    func latestRecord() async throws -> RemoteFullAppBackupRecord? {
        record
    }

    func saveRecord(_ record: RemoteFullAppBackupRecord) async throws {
        self.record = record
    }
}
