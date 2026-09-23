import SwiftData
import XCTest
@testable import GymTracker

@MainActor
final class PortableArchiveServiceTests: XCTestCase {
    func testFullArchivePreviewAndPassphraseRoundTrip() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        container.mainContext.insert(UserProfile(trainingDaysPerWeek: 4))
        try container.mainContext.save()

        let service = PortableArchiveService()
        let archive = try service.makeFullArchive(
            in: container.mainContext,
            passphrase: "test-only passphrase"
        )
        let preview = try service.preview(archive, passphrase: "test-only passphrase")

        XCTAssertEqual(preview.formatVersion, PortableArchiveFile.currentFormatVersion)
        XCTAssertEqual(preview.scope, .fullWorkspace)
        XCTAssertEqual(preview.protection, .passphrase)
        XCTAssertThrowsError(try service.preview(archive, passphrase: "wrong")) { error in
            XCTAssertEqual(error as? BackupEncryptionError, .invalidPassphrase)
        }
    }

    func testLegacyWorkoutExportIsIdentifiedAsNarrowScope() throws {
        let service = PortableArchiveService()
        let legacy = LocalBackupExportService().makeEnvelope(workouts: [], exercises: [], splits: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)

        let preview = try service.previewLegacy(data)
        XCTAssertEqual(preview.scope, .workoutOnly)
        XCTAssertEqual(preview.formatVersion, 2)
    }

    func testOversizedArchiveIsRejectedBeforeDecode() throws {
        let service = PortableArchiveService()
        let oversized = Data(repeating: 0, count: FullAppBackupLimits.maxDecompressedPayloadBytes + 1)
        XCTAssertThrowsError(try service.preview(oversized)) { error in
            XCTAssertEqual(error as? PortableArchiveError, .payloadTooLarge)
        }
    }
}
