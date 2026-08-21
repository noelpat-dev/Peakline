import XCTest
@testable import GymTracker

@MainActor
final class AppMotionTests: XCTestCase {
    func testPresetMetadataMatchesBlueprintPhysics() {
        XCTAssertEqual(AppMotion.Preset.snappy.response, 0.32, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.Preset.snappy.dampingFraction, 0.85, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.Preset.smooth.response, 0.42, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.Preset.smooth.dampingFraction, 0.92, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.Preset.expressive.response, 0.55, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.Preset.expressive.dampingFraction, 0.75, accuracy: 0.0001)
    }

    func testRoleMappingKeepsInteractionMotionBounded() {
        XCTAssertEqual(AppMotion.preset(for: .tapRelease), .snappy)
        XCTAssertEqual(AppMotion.preset(for: .chipSelect), .snappy)
        XCTAssertEqual(AppMotion.preset(for: .swipeSnap), .snappy)
        XCTAssertEqual(AppMotion.preset(for: .rowRemove), .smooth)
        XCTAssertEqual(AppMotion.preset(for: .sheetPresent), .smooth)
        XCTAssertEqual(AppMotion.preset(for: .metricChange), .expressive)
        XCTAssertEqual(AppMotion.preset(for: .celebration), .expressive)
        XCTAssertNil(AppMotion.preset(for: .routePush))
        XCTAssertNil(AppMotion.preset(for: .tabSelect))
    }

    func testDurationLadderAndDocumentedFeatureExceptions() {
        XCTAssertLessThanOrEqual(
            AppMotion.Duration.micro.seconds,
            AppMotion.microDurationMaximum
        )
        XCTAssertTrue(AppMotion.standardDurationRange.contains(AppMotion.Duration.standard.seconds))
        XCTAssertTrue(AppMotion.expressiveDurationRange.contains(AppMotion.Duration.expressive.seconds))
        XCTAssertEqual(AppMotion.stepperRollDuration, 0.15, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.setCheckmarkDuration, 0.18, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.chartDrawInDuration, 0.40, accuracy: 0.0001)
    }

    func testStaggerUsesThirtyFiveMillisecondsAndGroupsAfterEightItems() {
        XCTAssertEqual(AppMotion.staggerDelay(index: 0, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: 1, reduceMotion: false), 0.035, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: 7, reduceMotion: false), 0.245, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: 8, reduceMotion: false), 0.245, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: 100, reduceMotion: false), 0.245, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: -1, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.staggerDelay(index: 7, reduceMotion: true), 0, accuracy: 0.0001)
    }

    func testReduceMotionPolicyRemovesSpatialMotionWhereRequired() {
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .metricChange), .opacity)
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .cardAppear), .opacity)
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .routePush), .immediate)
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .swipeSnap), .immediate)
        XCTAssertEqual(AppMotion.reduceMotionPolicy(for: .celebration), .immediate)
        XCTAssertEqual(AppMotion.sheetInnerContentOffset, 12, accuracy: 0.0001)
        XCTAssertEqual(AppMotion.sheetInnerContentRevealDelay, 70_000_000)
    }
}
