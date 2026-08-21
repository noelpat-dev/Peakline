import Foundation
import SwiftData
import XCTest
@testable import GymTracker

private enum SleepRepositoryInjectedSaveFailure: Error, Equatable {
    case expected
}

private enum SleepRollbackFixture {
    // Unix timestamps are absolute instants, independent of the test machine's
    // local calendar and time zone.
    static let sleepStart = Date(timeIntervalSince1970: 1_700_000_000)
    static let sleepWake = sleepStart.addingTimeInterval(8 * 60 * 60)
    static let createdAt = Date(timeIntervalSince1970: 1_699_900_000)
    static let updatedAt = Date(timeIntervalSince1970: 1_699_950_000)
    static let napStart = Date(timeIntervalSince1970: 1_700_010_000)

    static let persistedSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    static let unrelatedSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
}

@MainActor
final class SleepRepositoryRollbackTests: XCTestCase {
    func testCleanManualSleepSaveFailureRollsBackInsertedSession() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = SleepSessionRepository(saveContext: { _ in
            throw SleepRepositoryInjectedSaveFailure.expected
        })

        XCTAssertThrowsError(
            try repository.startManualSession(
                start: SleepRollbackFixture.sleepStart,
                wake: SleepRollbackFixture.sleepWake,
                quality: 4,
                tags: [.trainedLate],
                notes: "Injected save failure",
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? SleepRepositoryInjectedSaveFailure, .expected)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<SleepSession>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testDirtyCompletedSleepSaveFailureRestoresOnlySleepChanges() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let persistedSession = SleepSession(
            id: SleepRollbackFixture.persistedSessionID,
            confirmedSleepStartAt: SleepRollbackFixture.sleepStart,
            wakeAt: SleepRollbackFixture.sleepWake,
            durationMinutes: 480,
            qualityRating: 3,
            tags: [.trainedLate],
            notes: "Baseline notes",
            source: .manual,
            confidence: .medium,
            status: .completed,
            createdAt: SleepRollbackFixture.createdAt,
            updatedAt: SleepRollbackFixture.updatedAt
        )
        context.insert(persistedSession)
        try context.save()

        let unrelatedPendingSession = SleepSession(
            id: SleepRollbackFixture.unrelatedSessionID,
            confirmedSleepStartAt: SleepRollbackFixture.sleepStart.addingTimeInterval(-24 * 60 * 60),
            wakeAt: SleepRollbackFixture.sleepStart.addingTimeInterval(-16 * 60 * 60),
            durationMinutes: 480,
            qualityRating: 2,
            tags: [.highStress],
            notes: "Unrelated pending insert",
            source: .manual,
            confidence: .medium,
            status: .completed,
            createdAt: SleepRollbackFixture.createdAt.addingTimeInterval(-60),
            updatedAt: SleepRollbackFixture.updatedAt.addingTimeInterval(-60)
        )
        context.insert(unrelatedPendingSession)
        context.processPendingChanges()
        XCTAssertTrue(context.hasChanges)

        let repository = SleepSessionRepository(saveContext: { _ in
            throw SleepRepositoryInjectedSaveFailure.expected
        })
        let changedStart = SleepRollbackFixture.sleepStart.addingTimeInterval(-30 * 60)
        let changedWake = SleepRollbackFixture.sleepWake.addingTimeInterval(30 * 60)

        XCTAssertThrowsError(
            try repository.updateCompletedSession(
                persistedSession,
                sleepStart: changedStart,
                wake: changedWake,
                quality: 5,
                tags: [.caffeineLate, .ateLate],
                notes: "Changed notes",
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? SleepRepositoryInjectedSaveFailure, .expected)
        }

        XCTAssertEqual(persistedSession.confirmedSleepStartAt, SleepRollbackFixture.sleepStart)
        XCTAssertEqual(persistedSession.wakeAt, SleepRollbackFixture.sleepWake)
        XCTAssertEqual(persistedSession.durationMinutes, 480)
        XCTAssertEqual(persistedSession.qualityRating, 3)
        XCTAssertEqual(persistedSession.tagRawValues, [SleepTag.trainedLate.rawValue])
        XCTAssertEqual(persistedSession.notes, "Baseline notes")
        XCTAssertEqual(persistedSession.confidence.rawValue, SleepConfidence.medium.rawValue)
        XCTAssertEqual(persistedSession.status.rawValue, SleepSessionStatus.completed.rawValue)
        XCTAssertEqual(persistedSession.updatedAt, SleepRollbackFixture.updatedAt)

        let afterFailure = try context.fetch(FetchDescriptor<SleepSession>())
        XCTAssertTrue(context.hasChanges)
        XCTAssertNotNil(afterFailure.first(where: { $0.id == SleepRollbackFixture.unrelatedSessionID }))

        try context.save()
        let afterRecoverySave = try context.fetch(FetchDescriptor<SleepSession>())
        XCTAssertEqual(afterRecoverySave.count, 2)
        let savedBaseline = try XCTUnwrap(
            afterRecoverySave.first(where: { $0.id == SleepRollbackFixture.persistedSessionID })
        )
        XCTAssertEqual(savedBaseline.confirmedSleepStartAt, SleepRollbackFixture.sleepStart)
        XCTAssertEqual(savedBaseline.wakeAt, SleepRollbackFixture.sleepWake)
        XCTAssertEqual(savedBaseline.durationMinutes, 480)
        XCTAssertEqual(savedBaseline.notes, "Baseline notes")
    }

    func testCleanNapSaveFailureRollsBackInsertedNap() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = NapSessionRepository(saveContext: { _ in
            throw SleepRepositoryInjectedSaveFailure.expected
        })
        let napEnd = SleepRollbackFixture.napStart.addingTimeInterval(30 * 60)

        XCTAssertThrowsError(
            try repository.addNap(
                start: SleepRollbackFixture.napStart,
                end: napEnd,
                quality: 4,
                note: "Injected save failure",
                source: .napTimer,
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? SleepRepositoryInjectedSaveFailure, .expected)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<NapSession>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }
}
