import XCTest
@testable import GymTracker

@MainActor
final class MotionBlueprintTests: XCTestCase {
    func testRoleSpecsKeepReleaseAndExpressiveAccessibilityContracts() {
        let release = AppMotion.spec(for: .tapRelease)
        XCTAssertTrue(release.duration.upperBound <= AppMotion.microDurationMaximum)
        XCTAssertTrue(release.feel.localizedCaseInsensitiveContains("snappy"))

        let metric = AppMotion.spec(for: .metricChange)
        XCTAssertEqual(metric.duration, AppMotion.expressiveDurationRange)
        XCTAssertTrue(metric.feel.localizedCaseInsensitiveContains("without layout shift"))

        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .metricChange), .opacity)
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .celebration), .immediate)
    }

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

    func testRestTimerProgressClampsBeforeStartAndAfterEnd() {
        let start = Date(timeIntervalSince1970: 20_000)
        var state = RestTimerState()
        state.start(durationSeconds: 60, now: start)

        XCTAssertEqual(state.progress(at: start.addingTimeInterval(-1)), 0, accuracy: 0.0001)
        XCTAssertEqual(state.progress(at: start.addingTimeInterval(30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.progress(at: start.addingTimeInterval(61)), 1, accuracy: 0.0001)
    }

    func testCompletionPresentationIsExclusivelyPROrOrdinary() throws {
        let rating = try XCTUnwrap(WorkoutRating.options.first { $0.id == 4 })
        let pr = PRRecord(
            id: "motion-pr",
            sessionId: UUID(),
            exerciseLogId: UUID(),
            setLogId: UUID(),
            exerciseName: "Bench Press",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            workoutSplitName: "Push",
            prType: .estimatedOneRepMax,
            value: 82,
            displayValue: "82 kg",
            previousDisplayValue: "80 kg",
            improvementDescription: "Estimated 1RM 80kg → 82kg"
        )

        let ordinary = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "42m",
            prs: []
        )
        let personalRecord = WorkoutCelebrationPresentation.completion(
            rating: rating,
            durationText: "42m",
            prs: [pr]
        )

        XCTAssertEqual(ordinary.style, .completedWorkout)
        XCTAssertNotEqual(ordinary.systemImage, "trophy.fill")
        XCTAssertEqual(personalRecord.style, .pr)
        XCTAssertEqual(personalRecord.systemImage, "trophy.fill")
        XCTAssertNotEqual(ordinary.title, personalRecord.title)
    }
}
