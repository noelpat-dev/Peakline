import XCTest
@testable import GymTracker

/// Deterministic coverage for the shared swipe row, the stepper value motion,
/// and the trend-chart point inspection seam.
final class InteractionQualityTests: XCTestCase {
    // MARK: - SwipeRevealRow gesture ownership

    func testSwipeIntentStaysUndecidedUntilMovementIsMeaningful() {
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: 5, height: -6)),
            .undecided
        )
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -11, height: 0)),
            .undecided
        )
    }

    func testDiagonalAndVerticalDragsDoNotClaimTheRow() {
        // An even diagonal belongs to the scrolling list.
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -60, height: -60)),
            .vertical
        )
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -20, height: 90)),
            .vertical
        )
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: 70, height: 64)),
            .vertical
        )
    }

    func testHorizontalIntentCommitsOnceTheHorizontalAxisWins() {
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -90, height: 12)),
            .horizontal
        )
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: 90, height: -12)),
            .horizontal
        )
        // Mild downward drift still counts as a deliberate row swipe.
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -90, height: 40)),
            .horizontal
        )
        // At the dominance boundary the scrolling list keeps the gesture.
        XCTAssertEqual(
            SwipeRevealGesturePolicy.intent(for: CGSize(width: -50, height: 40)),
            .vertical
        )
    }

    func testSettlingKeepsOpenRowClosedOnReverseAndSmallGestures() {
        let revealWidth: CGFloat = 96

        // Reverse swipe from an open row settles back to closed.
        XCTAssertFalse(
            SwipeRevealGesturePolicy.shouldOpen(
                translation: CGSize(width: 40, height: 2),
                predictedEndTranslation: CGSize(width: 70, height: 2),
                dragStartOffset: -revealWidth,
                revealWidth: revealWidth
            )
        )

        // A small nudge reverses but never reaches the open threshold.
        XCTAssertFalse(
            SwipeRevealGesturePolicy.shouldOpen(
                translation: CGSize(width: -20, height: 4),
                predictedEndTranslation: CGSize(width: -28, height: 4),
                dragStartOffset: 0,
                revealWidth: revealWidth
            )
        )
    }

    func testSettlingOpensOnDeliberateTravelAndOnFastFlings() {
        let revealWidth: CGFloat = 96

        XCTAssertTrue(
            SwipeRevealGesturePolicy.shouldOpen(
                translation: CGSize(width: -52, height: 6),
                predictedEndTranslation: CGSize(width: -58, height: 6),
                dragStartOffset: 0,
                revealWidth: revealWidth
            )
        )

        // A short but fast fling still opens the row.
        XCTAssertTrue(
            SwipeRevealGesturePolicy.shouldOpen(
                translation: CGSize(width: -18, height: 5),
                predictedEndTranslation: CGSize(width: -150, height: 8),
                dragStartOffset: 0,
                revealWidth: revealWidth
            )
        )
    }

    func testSwipeOffsetStaysInsideTheSingleRevealWidth() {
        XCTAssertEqual(SwipeRevealGesturePolicy.clampedOffset(-240, revealWidth: 96), -96)
        XCTAssertEqual(SwipeRevealGesturePolicy.clampedOffset(40, revealWidth: 96), 0)
        XCTAssertEqual(SwipeRevealGesturePolicy.clampedOffset(-40, revealWidth: 96), -40)
    }

    // MARK: - StepperValueControl direction and Reduce Motion

    func testStepperDirectionFollowsTypedNumericValues() {
        XCTAssertEqual(StepperValueDirection.derived(from: 60, to: 62.5), .increment)
        XCTAssertEqual(StepperValueDirection.derived(from: 62.5, to: 60), .decrement)
        XCTAssertEqual(StepperValueDirection.derived(from: 60, to: 60), .neutral)
    }

    func testTypedChangeCanReverseTheLastButtonDirection() {
        var direction = StepperValueDirection.derived(from: 40, to: 42.5)
        XCTAssertEqual(direction, .increment)

        // The user types a smaller weight after tapping increment.
        direction = StepperValueDirection.derived(from: 42.5, to: 37.5)
        XCTAssertEqual(direction, .decrement)

        // Re-entering the same displayed value must not animate a fake change.
        direction = StepperValueDirection.derived(from: 37.5, to: 37.5)
        XCTAssertEqual(direction, .neutral)
    }

    func testRapidUpdatesKeepTheDirectionOfTheLatestRealChange() {
        var value = 20.0
        var direction = StepperValueDirection.neutral

        for step in [22.5, 25.0, 27.5] {
            direction = StepperValueDirection.derived(from: value, to: step)
            value = step
            XCTAssertEqual(direction, .increment)
        }

        direction = StepperValueDirection.derived(from: value, to: 25.0)
        XCTAssertEqual(direction, .decrement)
        XCTAssertEqual(StepperValueDirection.derived(from: 25.0, to: 25.0), .neutral)
    }

    func testReduceMotionUsesDirectStateInsteadOfTheNumericRoll() {
        XCTAssertEqual(
            StepperValueTransition.resolve(reduceMotion: true, direction: .increment),
            .immediate
        )
        XCTAssertEqual(
            StepperValueTransition.resolve(reduceMotion: true, direction: .decrement),
            .immediate
        )
        XCTAssertEqual(
            StepperValueTransition.resolve(reduceMotion: false, direction: .decrement),
            .numericRoll(direction: .decrement)
        )
        // A neutral change (for example re-entering the same value) has no
        // direction to roll, so it must resolve to direct state.
        XCTAssertEqual(
            StepperValueTransition.resolve(reduceMotion: false, direction: .neutral),
            .immediate
        )
        XCTAssertEqual(
            StepperValueTransition.resolve(reduceMotion: true, direction: .neutral),
            .immediate
        )
        XCTAssertEqual(
            StepperValueTransition.immediate.animation,
            AppMotion.reducedMotionAnimation(policy: .immediate)
        )
        XCTAssertEqual(
            StepperValueTransition.numericRoll(direction: .increment).animation,
            .easeInOut(duration: AppMotion.stepperRollDuration)
        )
        XCTAssertEqual(AppMotion.stepperRollDuration, 0.15, accuracy: 0.0001)
    }

    // MARK: - ExerciseTrendChart point inspection

    func testTrendPointSelectorHandlesEmptySingleAndMultiSessionStates() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = [base, base.addingTimeInterval(86_400), base.addingTimeInterval(172_800)]

        XCTAssertNil(ExerciseTrendPointSelector.nearestIndex(to: base, in: []))
        XCTAssertEqual(ExerciseTrendPointSelector.nearestIndex(to: base, in: [base]), 0)
        XCTAssertEqual(
            ExerciseTrendPointSelector.nearestDate(to: base.addingTimeInterval(90_000), in: dates),
            dates[1]
        )
    }

    func testTrendPointSelectorKeepsTiesAndEdgesDeterministic() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = [base, base.addingTimeInterval(86_400), base.addingTimeInterval(172_800)]

        // Halfway between two points keeps the earlier dated value.
        XCTAssertEqual(
            ExerciseTrendPointSelector.nearestIndex(to: base.addingTimeInterval(43_200), in: dates),
            0
        )
        XCTAssertEqual(
            ExerciseTrendPointSelector.nearestDate(to: base.addingTimeInterval(-500_000), in: dates),
            dates[0]
        )
        XCTAssertEqual(
            ExerciseTrendPointSelector.nearestDate(to: base.addingTimeInterval(500_000), in: dates),
            dates[2]
        )
    }
}
