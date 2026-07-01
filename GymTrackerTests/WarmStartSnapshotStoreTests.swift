import XCTest
@testable import GymTracker

final class WarmStartSnapshotStoreTests: XCTestCase {
    func testSaveAndLoadMatchingSnapshot() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        let payload = TestWarmStartPayload(title: "History", count: 3)

        await store.save(payload, screenKey: "history", sourceSignature: "source-a")

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "history", matching: "source-a")
        XCTAssertEqual(envelope?.payload, payload)
        XCTAssertEqual(envelope?.sourceSignature, "source-a")
        XCTAssertEqual(envelope?.screenKey, "history")
    }

    func testLoadRejectsMismatchedSourceSignature() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        await store.save(TestWarmStartPayload(title: "Workout", count: 2), screenKey: "workout_start", sourceSignature: "old-source")

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "workout_start", matching: "new-source")
        XCTAssertNil(envelope)
    }

    func testCorruptSnapshotReturnsNilAndClearsFile() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = WarmStartSnapshotStore(directoryURL: directoryURL)
        let fileURL = await store.snapshotFileURL(forTesting: "history")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let envelope = await store.load(TestWarmStartPayload.self, screenKey: "history")
        XCTAssertNil(envelope)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarmStartSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct TestWarmStartPayload: Codable, Equatable {
    let title: String
    let count: Int
}
