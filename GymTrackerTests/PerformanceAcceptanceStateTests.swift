#if DEBUG
import XCTest
@testable import GymTracker

/// The canonical verifier reads History scroll protection from the in-app
/// acceptance summary instead of app stdout, so these tests pin the summary
/// contract the verifier depends on.
final class PerformanceAcceptanceStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PerformanceAcceptanceState.reset()
        PerformanceAcceptanceState.isEnabledForTesting = true
    }

    override func tearDown() {
        PerformanceAcceptanceState.isEnabledForTesting = false
        PerformanceAcceptanceState.reset()
        super.tearDown()
    }

    func testHistoryScrollObserverAttachmentIsCountedInTheSummary() {
        PerformanceTracer.mark(.historyScroll, "observer_retry_exhausted")
        XCTAssertEqual(summaryField("historyScrollObserverAttachments"), "0")

        PerformanceTracer.mark(.historyScroll, "observer_attached")

        XCTAssertEqual(summaryField("historyScrollObserverAttachments"), "1")
        XCTAssertTrue(
            PerformanceAcceptanceState.summary.contains("performance_acceptance=PASS"),
            PerformanceAcceptanceState.summary
        )
    }

    func testDisplaySnapshotRebuildDuringActiveScrollFailsAcceptance() {
        PerformanceTracer.mark(.historyScroll, "observer_attached")
        PerformanceTracer.mark(.historyScroll, "begin")

        PerformanceTracer.trace(.historyDisplaySnapshot) { 0 }

        let summary = PerformanceAcceptanceState.summary
        XCTAssertTrue(summary.contains("performance_acceptance=FAIL"), summary)
        XCTAssertTrue(summary.contains("history.display_snapshot"), summary)
    }

    func testDisplaySnapshotRebuildAfterScrollEndStaysLegal() {
        PerformanceTracer.mark(.historyScroll, "begin")
        PerformanceTracer.mark(.historyScroll, "end")

        PerformanceTracer.trace(.historyDisplaySnapshot) { 0 }

        let summary = PerformanceAcceptanceState.summary
        XCTAssertTrue(summary.contains("performance_acceptance=PASS"), summary)
        XCTAssertFalse(summary.contains("history.display_snapshot"), summary)
    }

    func testResetClearsHistoryScrollStateAndFailures() {
        PerformanceTracer.mark(.historyScroll, "observer_attached")
        PerformanceTracer.mark(.historyScroll, "begin")
        PerformanceTracer.trace(.historyDisplaySnapshot) { 0 }
        XCTAssertTrue(
            PerformanceAcceptanceState.summary.contains("performance_acceptance=FAIL"),
            PerformanceAcceptanceState.summary
        )

        PerformanceAcceptanceState.reset()

        let summary = PerformanceAcceptanceState.summary
        XCTAssertTrue(summary.contains("historyScrollObserverAttachments=0"), summary)
        XCTAssertTrue(summary.contains("performance_acceptance=PASS"), summary)

        // With the scroll interval cleared, a later refresh is legal again.
        PerformanceTracer.trace(.historyDisplaySnapshot) { 0 }
        XCTAssertTrue(
            PerformanceAcceptanceState.summary.contains("performance_acceptance=PASS"),
            PerformanceAcceptanceState.summary
        )
    }

    private func summaryField(_ name: String) -> String? {
        PerformanceAcceptanceState.summary
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(name)=") }?
            .replacingOccurrences(of: "\(name)=", with: "")
    }
}
#endif
