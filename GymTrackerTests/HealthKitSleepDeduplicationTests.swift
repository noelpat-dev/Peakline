import Foundation
import XCTest
@testable import GymTracker

@MainActor
final class HealthKitSleepDeduplicationTests: XCTestCase {
    private let sleepStart = Date(timeIntervalSince1970: 1_700_000_000)

    func testExistingSnapshotCollectsHealthKitIDsFromEveryLocalSource() {
        let sessions = [
            makeSleepSession(source: .manual, healthKitSampleIds: ["manual-export-id"]),
            makeSleepSession(source: .inAppTimer, healthKitSampleIds: ["timer-export-id"]),
            makeSleepSession(source: .appleHealth, healthKitSampleIds: ["health-import-id"]),
            makeSleepSession(source: .merged, healthKitSampleIds: ["merged-id"]),
            makeSleepSession(source: .unknown, healthKitSampleIds: ["unknown-id"])
        ]
        let naps = [
            makeNap(source: .manual, healthKitSampleIds: ["manual-nap-export-id"]),
            makeNap(source: .napTimer, healthKitSampleIds: ["timer-nap-export-id"]),
            makeNap(source: .appleHealth, healthKitSampleIds: ["health-nap-import-id"]),
            makeNap(source: .inferred, healthKitSampleIds: ["inferred-nap-id"])
        ]

        let snapshot = HealthKitSleepImportExistingSnapshot(sessions: sessions, naps: naps)

        XCTAssertEqual(
            snapshot.healthSampleIds,
            Set([
                "manual-export-id",
                "timer-export-id",
                "health-import-id",
                "merged-id",
                "unknown-id",
                "manual-nap-export-id",
                "timer-nap-export-id",
                "health-nap-import-id",
                "inferred-nap-id"
            ])
        )
    }

    func testExistingSnapshotUsesEveryLocalSourceForOverlapDeduplication() {
        let manualSessionStart = sleepStart
        let timerSessionStart = sleepStart.addingTimeInterval(24 * 60 * 60)
        let manualNapStart = sleepStart.addingTimeInterval(12 * 60 * 60)
        let snapshot = HealthKitSleepImportExistingSnapshot(
            sessions: [
                makeSleepSession(source: .manual, start: manualSessionStart),
                makeSleepSession(source: .inAppTimer, start: timerSessionStart)
            ],
            naps: [makeNap(source: .manual, start: manualNapStart)]
        )

        XCTAssertTrue(
            snapshot.hasOverlappingAppleHealthSession(
                start: manualSessionStart.addingTimeInterval(30 * 60),
                end: manualSessionStart.addingTimeInterval(60 * 60)
            )
        )
        XCTAssertTrue(
            snapshot.hasOverlappingAppleHealthSession(
                start: timerSessionStart.addingTimeInterval(7 * 60 * 60),
                end: timerSessionStart.addingTimeInterval(9 * 60 * 60)
            )
        )
        XCTAssertTrue(
            snapshot.hasOverlappingAppleHealthNap(
                start: manualNapStart.addingTimeInterval(5 * 60),
                end: manualNapStart.addingTimeInterval(20 * 60)
            )
        )
        XCTAssertFalse(
            snapshot.hasOverlappingAppleHealthSession(
                start: sleepStart.addingTimeInterval(7 * 24 * 60 * 60),
                end: sleepStart.addingTimeInterval(7 * 24 * 60 * 60 + 60 * 60)
            )
        )
    }

    func testExistingSnapshotIsImmutableAfterModelsChange() {
        let session = makeSleepSession(source: .manual, healthKitSampleIds: ["exported-id"])
        let nap = makeNap(source: .manual, healthKitSampleIds: ["exported-nap-id"])
        let snapshot = HealthKitSleepImportExistingSnapshot(sessions: [session], naps: [nap])

        session.healthKitSampleIds = ["replacement-id"]
        session.confirmedSleepStartAt = sleepStart.addingTimeInterval(3 * 24 * 60 * 60)
        session.wakeAt = session.confirmedSleepStartAt.addingTimeInterval(8 * 60 * 60)
        nap.healthKitSampleIds = ["replacement-nap-id"]

        XCTAssertEqual(snapshot.healthSampleIds, Set(["exported-id", "exported-nap-id"]))
        XCTAssertTrue(
            snapshot.hasOverlappingAppleHealthSession(
                start: sleepStart.addingTimeInterval(30 * 60),
                end: sleepStart.addingTimeInterval(60 * 60)
            )
        )
        XCTAssertFalse(
            snapshot.hasOverlappingAppleHealthSession(
                start: sleepStart.addingTimeInterval(3 * 24 * 60 * 60 + 30 * 60),
                end: sleepStart.addingTimeInterval(3 * 24 * 60 * 60 + 60 * 60)
            )
        )
    }

    private func makeSleepSession(
        source: SleepSource,
        start: Date? = nil,
        healthKitSampleIds: [String] = []
    ) -> SleepSession {
        let start = start ?? sleepStart
        let end = start.addingTimeInterval(8 * 60 * 60)
        return SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: end,
            durationMinutes: 8 * 60,
            source: source,
            confidence: .medium,
            status: .completed,
            healthKitSampleIds: healthKitSampleIds
        )
    }

    private func makeNap(
        source: NapSource,
        start: Date? = nil,
        healthKitSampleIds: [String] = []
    ) -> NapSession {
        let start = start ?? sleepStart
        return NapSession(
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            source: source,
            healthKitSampleIds: healthKitSampleIds
        )
    }
}
