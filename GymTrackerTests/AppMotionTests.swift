import XCTest
import SwiftUI
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

    func testRolesProduceTheirExpectedAnimations() {
        let springRoles: [(AppMotion.Preset, [AppMotion.Role])] = [
            (.snappy, [.tapRelease, .cardPress, .buttonPress, .primaryAction,
                       .secondaryAction, .chipSelect, .ratingSelect, .checkInSelect,
                       .rowReorder, .successConfirm, .swipeSnap]),
            (.smooth, [.modeChange, .cardAppear, .cardDisappear, .rowInsert,
                       .rowRemove, .sheetPresent, .sheetDismiss, .modalPresent,
                       .modalDismiss, .loadingReveal, .destructiveConfirm]),
            (.expressive, [.metricChange, .celebration])
        ]
        for (preset, roles) in springRoles {
            for role in roles {
                XCTAssertEqual(
                    AppMotion.animation(for: role, reduceMotion: false),
                    preset.animation,
                    role.rawValue
                )
            }
        }
        XCTAssertEqual(
            AppMotion.animation(for: AppMotion.Role.tapDown, reduceMotion: false),
            .easeOut(duration: AppMotion.navigationPressDownDuration)
        )
        for role in [AppMotion.Role.tabSelect, .routePush, .routePop, .reduceMotionFallback] {
            XCTAssertEqual(
                AppMotion.animation(for: role, reduceMotion: false),
                .easeOut(duration: AppMotion.reducedMotionImmediateDuration),
                role.rawValue
            )
        }
    }

    func testEveryRoleRespectsReduceMotion() {
        let immediateRoles: Set<AppMotion.Role> = [
            .routePush, .routePop, .tabSelect, .swipeSnap, .celebration,
            .successConfirm, .destructiveConfirm, .reduceMotionFallback
        ]
        for role in AppMotion.Role.allCases {
            let duration = immediateRoles.contains(role)
                ? AppMotion.reducedMotionImmediateDuration
                : AppMotion.reducedMotionOpacityDuration
            XCTAssertEqual(
                AppMotion.animation(for: role, reduceMotion: true),
                .easeOut(duration: duration),
                role.rawValue
            )
        }
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
    }
}
