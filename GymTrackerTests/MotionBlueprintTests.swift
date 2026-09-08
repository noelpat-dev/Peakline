import XCTest
@testable import GymTracker

@MainActor
final class MotionBlueprintTests: XCTestCase {
    func testCustomStaggerStepStillCapsTrailingItemsAsOneGroup() {
        let step = 0.04

        XCTAssertEqual(
            AppMotion.staggerDelay(index: 3, reduceMotion: false, step: step),
            0.12,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppMotion.staggerDelay(index: AppMotion.staggerItemCap, reduceMotion: false, step: step),
            0.28,
            accuracy: 0.0001
        )
        XCTAssertEqual(AppMotion.staggerDelay(index: 99, reduceMotion: true, step: step), 0, accuracy: 0.0001)
    }

    func testRestTimerStateHasStableWarningAndCompletionBoundaries() {
        let start = Date(timeIntervalSince1970: 10_000)
        var state = RestTimerState()
        state.start(durationSeconds: 90, exerciseName: "Bench Press", nextSetNumber: 3, now: start)

        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(80)), 10)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(81)), 9)
        XCTAssertFalse(state.isComplete)

        state.markComplete(at: start.addingTimeInterval(90))
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(90)), 0)

        // Completion is idempotent: a late timeline tick cannot replace the
        // original completion boundary or resurrect a running timer.
        state.markComplete(at: start.addingTimeInterval(91))
        XCTAssertEqual(state.completionDate, start.addingTimeInterval(90))
        XCTAssertFalse(state.isRunning)

        state.reset()
        XCTAssertFalse(state.isComplete)
        XCTAssertEqual(state.remainingSeconds(at: start), 0)
    }

    func testRestTimerRemainingSecondsCeilsFractionalDeadlineAndExtension() {
        let start = Date(timeIntervalSince1970: 15_000)
        var state = RestTimerState()
        state.start(durationSeconds: 90, now: start)

        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(89.25)), 1)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(90)), 0)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(90.25)), 0)

        state.extend(by: 30, now: start.addingTimeInterval(89.25))

        XCTAssertEqual(state.endDate, start.addingTimeInterval(120))
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(119.25)), 1)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(120)), 0)
    }

    func testRestTimerProgressClampsBeforeStartAndAfterEnd() {
        let start = Date(timeIntervalSince1970: 20_000)
        var state = RestTimerState()
        state.start(durationSeconds: 60, now: start)

        XCTAssertEqual(state.progress(at: start.addingTimeInterval(-1)), 0, accuracy: 0.0001)
        XCTAssertEqual(state.progress(at: start.addingTimeInterval(30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.progress(at: start.addingTimeInterval(61)), 1, accuracy: 0.0001)
    }
}
