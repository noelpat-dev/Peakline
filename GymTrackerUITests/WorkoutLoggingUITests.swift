import XCTest

final class WorkoutLoggingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(arguments: [String] = []) {
        app.launchArguments = ["-UITestInMemoryStore"] + arguments
        app.launch()
    }

    func testLiveActivityDemoExpandsOnIsland() throws {
        app.launchArguments = ["-LiveActivityDemo", "-LiveActivityDemoNoRest"]
        app.launch()
        if !app.staticTexts["Live Activity Demo"].waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.staticTexts["Live Activity Demo"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045))
        island.press(forDuration: 1.2)
        XCTAssertTrue(
            springboard.staticTexts["Bench press"].waitForExistence(timeout: 5),
            "Expected the workout name in the expanded Dynamic Island"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = "live-activity-expanded-island"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLiveActivityRestIslandShowsCountdownAndMetrics() throws {
        app.launchArguments = ["-LiveActivityDemo"]
        app.launch()
        if !app.staticTexts["Live Activity Demo"].waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.staticTexts["Live Activity Demo"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.staticTexts["7/18"].waitForExistence(timeout: 10))
        let compactScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        compactScreenshot.name = "live-activity-compact-rest"
        compactScreenshot.lifetime = .keepAlways
        add(compactScreenshot)

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045))
            .press(forDuration: 1.2)
        XCTAssertTrue(springboard.staticTexts["Bench press"].waitForExistence(timeout: 5))
        XCTAssertTrue(springboard.staticTexts["REST"].exists)
        XCTAssertTrue(springboard.staticTexts["▲ +32 M"].exists)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let expandedScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        expandedScreenshot.name = "live-activity-expanded-rest"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)
    }

    func testLiveActivityPRFlagAppearsAndExpires() throws {
        app.launchArguments = ["-LiveActivityDemo", "-LiveActivityDemoNoRest"]
        app.launch()
        if !app.buttons["Show PR"].waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
        }
        let trigger = app.buttons["Show PR"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        trigger.tap()

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045)).press(forDuration: 1.2)
        let flag = springboard.staticTexts["NEW PR FLAG"]
        XCTAssertTrue(flag.waitForExistence(timeout: 4), "PR flag should appear in the expanded Island")
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = "live-activity-pr-flag"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(
            waitUntil(timeout: 10) { !flag.exists },
            "PR flag should retire after its eight-second window"
        )
    }

    func testLiveActivityFollowsTwoLoggedSetsAndFinish() throws {
        launch(arguments: ["-UITestAppearance", "dark"])
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 10))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let compactProgress = springboard.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+/[0-9]+")
        ).firstMatch
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(compactProgress.waitForExistence(timeout: 10), "Activity should start with the workout")
        app.activate()

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        tapButton(identifier: "stepper-weight-increment", times: 2)
        tapButton(identifier: "stepper-reps-increment", times: 6)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "1 of [0-9]+ working sets? entered"))
                .firstMatch.waitForExistence(timeout: 5)
        )

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        let secondRepsIncrement = app.buttons.matching(identifier: "stepper-reps-increment").element(boundBy: 1)
        for _ in 0..<5 where !secondRepsIncrement.isHittable { app.swipeUp() }
        XCTAssertTrue(secondRepsIncrement.waitForExistence(timeout: 5))
        secondRepsIncrement.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "2 of [0-9]+ working sets? entered"))
                .firstMatch.waitForExistence(timeout: 5)
        )

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(compactProgress.waitForExistence(timeout: 8), "Activity should still exist after two sets")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045)).press(forDuration: 1.2)
        XCTAssertTrue(
            springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SET 3 OF"))
                .firstMatch.waitForExistence(timeout: 5),
            "Activity should advance to the third set after two entered sets"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let updatedScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        updatedScreenshot.name = "live-activity-two-sets"
        updatedScreenshot.lifetime = .keepAlways
        add(updatedScreenshot)

        app.activate()
        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }
        tapModalElement(identifier: "workout-rating-3")
        if app.buttons["workout-celebration-primary"].waitForExistence(timeout: 3) {
            app.buttons["workout-celebration-primary"].tap()
        }
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            waitUntil(timeout: 10) { !compactProgress.exists },
            "Activity should leave the Island after workout finish"
        )
    }

    func testLiveActivityRecountsTargetAndDeletedEnteredSet() throws {
        launch(arguments: ["-UITestAppearance", "dark"])
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 10))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let compactProgress = springboard.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+/[0-9]+")
        ).firstMatch
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(compactProgress.waitForExistence(timeout: 10))
        let initialProgress = compactProgress.label.split(separator: "/").compactMap { Int($0) }
        guard initialProgress.count == 2 else {
            XCTFail("Expected a compact set count")
            return
        }
        app.activate()

        let increaseTarget = app.buttons["Increase target sets"]
        for _ in 0..<6 where !increaseTarget.isHittable { app.swipeUp() }
        XCTAssertTrue(increaseTarget.waitForExistence(timeout: 5))
        increaseTarget.tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                compactProgress.label == "\(initialProgress[0])/\(initialProgress[1] + 1)"
            },
            "The Island total should follow a target-set change"
        )
        app.activate()

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        tapButton(identifier: "stepper-weight-increment", times: 1)
        tapButton(identifier: "stepper-reps-increment", times: 1)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                compactProgress.label == "\(initialProgress[0] + 1)/\(initialProgress[1] + 1)"
            },
            "The Island should count the entered set"
        )
        app.activate()

        let setActions = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workout-logger-set-actions-")
        ).firstMatch
        for _ in 0..<6 where !setActions.isHittable { app.swipeUp() }
        XCTAssertTrue(setActions.waitForExistence(timeout: 5))
        setActions.tap()
        XCTAssertTrue(app.buttons["Delete Set"].waitForExistence(timeout: 5))
        app.buttons["Delete Set"].tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                compactProgress.label == "\(initialProgress[0])/\(initialProgress[1] + 1)"
            },
            "Deleting the entered set should remove its progress"
        )
        app.activate()

        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }
        tapModalElement(identifier: "workout-rating-3")
        if app.buttons["workout-celebration-primary"].waitForExistence(timeout: 3) {
            app.buttons["workout-celebration-primary"].tap()
        }
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
    }

    func testSeededWorkoutCanLogSetPauseFinishAndReachHistory() throws {
        launch(arguments: ["-UITestAppearance", "dark"])
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 10))

        let exerciseName = app.staticTexts["workout-logger-current-exercise-name"]
        for _ in 0..<6 where !exerciseName.isHittable { app.swipeUp() }
        app.swipeUp()
        exerciseName.swipeLeft()
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        let removeScreenshot = XCTAttachment(screenshot: app.screenshot())
        removeScreenshot.name = "workout-remove-action"
        removeScreenshot.lifetime = .keepAlways
        add(removeScreenshot)
        exerciseName.swipeRight()

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        XCTAssertTrue(app.descendants(matching: .any)["set-row-1"].waitForExistence(timeout: 5))
        assertAccessibilityLabel(identifier: "stepper-weight-decrement", expectedLabel: "Decrease Weight")
        assertAccessibilityLabel(identifier: "stepper-weight-edit", expectedLabel: "Edit Weight")
        assertAccessibilityLabel(identifier: "stepper-weight-increment", expectedLabel: "Increase Weight")
        assertAccessibilityLabel(identifier: "stepper-reps-decrement", expectedLabel: "Decrease Reps")
        assertAccessibilityLabel(identifier: "stepper-reps-edit", expectedLabel: "Edit Reps")
        assertAccessibilityLabel(identifier: "stepper-reps-increment", expectedLabel: "Increase Reps")
        let setActionsMenu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-logger-set-actions-"))
            .firstMatch
        XCTAssertTrue(setActionsMenu.waitForExistence(timeout: 5), "Expected a per-set actions menu")
        XCTAssertEqual(setActionsMenu.label, "Actions for set 1")
        XCTAssertFalse(app.staticTexts["Draft"].exists, "Incomplete set data should remain editable without a decorative Draft badge")

        tapButton(identifier: "stepper-weight-increment", times: 2)
        tapButton(identifier: "stepper-reps-increment", times: 6)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "1 of [0-9]+ working sets? entered")).firstMatch.waitForExistence(timeout: 5),
            "The live working-set count should follow entered data without a separate completion action"
        )

        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-logger-complete-set-")).firstMatch.exists,
            "Set rows should not show a separate Complete Set action"
        )
        let timerPreset = app.buttons["1:00"]
        for _ in 0..<8 where !timerPreset.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(timerPreset.waitForExistence(timeout: 5))
        timerPreset.tap()
        let restTimer = app.descendants(matching: .any)["workout-rest-timer-active"]
        XCTAssertTrue(restTimer.waitForExistence(timeout: 5), "Expected the manual rest timer to remain available")
        for duration in ["1:00", "1:30", "2:00", "3:00"] {
            XCTAssertEqual(
                app.buttons.matching(NSPredicate(format: "label == %@", duration)).count,
                1,
                "Expected one \(duration) manual timer preset while an active timer is visible"
            )
        }

        tapElement(identifier: "workout-logger-pause", maxSwipes: 6, swipeUp: false)
        tapElement(identifier: "workout-logger-resume", maxSwipes: 2, swipeUp: false)

        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }

        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 5))
        let ratingScreenshot = XCTAttachment(screenshot: app.screenshot())
        ratingScreenshot.name = "workout-compact-rating"
        ratingScreenshot.lifetime = .keepAlways
        add(ratingScreenshot)
        XCTAssertTrue(
            waitUntil(timeout: 3) { !self.app.buttons["workout-logger-finish"].isHittable },
            "Expected the rating overlay to block interaction with the logger controls behind it"
        )
        for rating in 1...5 {
            let ratingControl = tappableElement(identifier: "workout-rating-\(rating)")
            XCTAssertTrue(ratingControl.waitForExistence(timeout: 2), "Expected rating \(rating) to be visible")
            XCTAssertTrue(ratingControl.isEnabled, "Expected rating \(rating) to remain enabled")
        }

        tapModalElement(identifier: "workout-rating-3")

        XCTAssertFalse(
            app.buttons["workout-celebration-primary"].waitForExistence(timeout: 2),
            "Routine non-PR completion must navigate directly to Summary"
        )
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
        let summaryStatus = app.staticTexts["session-summary-status"]
        XCTAssertTrue(summaryStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(summaryStatus.label, "Completed")
        XCTAssertFalse(
            app.buttons["workout-celebration-primary"].waitForExistence(timeout: 2),
            "Expected the completion overlay to retire after Summary reaches its first stable frame"
        )

        tapElement(identifier: "session-summary-done", maxSwipes: 12)
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 8),
            "Expected returning from Summary to retire the completed logger"
        )

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Push")).firstMatch.waitForExistence(timeout: 8))
    }

    func testGenuinePRUsesStarburstCompletionAndReachesSummary() throws {
        launch(arguments: ["-UITestPRCelebrationFixture"])

        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        XCTAssertTrue(app.descendants(matching: .any)["set-row-1"].waitForExistence(timeout: 5))
        tapButton(identifier: "stepper-weight-increment", times: 2)
        tapButton(identifier: "stepper-reps-increment", times: 2)

        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }
        tapModalElement(identifier: "workout-rating-4")

        let completion = app.descendants(matching: .any)["workout-completion-copy"]
        XCTAssertTrue(completion.waitForExistence(timeout: 8))
        XCTAssertEqual(completion.label, "Personal record workout completion")
        let completionCopy = completion.value as? String ?? completion.label
        XCTAssertTrue(completionCopy.contains("New bests unlocked."))
        XCTAssertTrue(completionCopy.contains("PRs on Incline Chest Press (Smith)."))
        XCTAssertFalse(
            app.buttons["workout-logger-finish"].exists,
            "Expected the PR completion overlay to isolate the logger controls behind it"
        )

        let done = app.buttons["workout-celebration-primary"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        XCTAssertTrue(done.isHittable, "PR animation must not block the completion action")
        done.tap()

        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["New Bests"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["workout-celebration-primary"].waitForExistence(timeout: 2),
            "Expected the PR overlay to retire after Summary reaches its first stable frame"
        )
    }

    func testSummitPeakCrossingShowsReachedViewThenDoneOpensSummary() throws {
        openForcedSummitReached()

        XCTAssertTrue(
            app.staticTexts["SUMMIT REACHED"].waitForExistence(timeout: 10),
            "Expected the forced peak crossing to present SummitReachedView after workout completion"
        )
        XCTAssertTrue(app.descendants(matching: .any)["workout-completion-copy"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH[c] %@", "Send a postcard from")
            ).firstMatch.exists,
            "Expected the summit screen to expose its direct postcard share action"
        )
        // Capture the settled screen before querying lower content can move the scroll position.
        RunLoop.current.run(until: Date().addingTimeInterval(2.3))
        attachScreenshot(named: "fix1-summit-reached-default-dark")
        XCTAssertFalse(app.navigationBars["Push - Full"].exists, "The logger title must be hidden")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The tab bar must be hidden")
        XCTAssertTrue(app.staticTexts["Snowdon"].isHittable, "Expected the peak title on screen")
        XCTAssertTrue(
            app.descendants(matching: .any)["1,085 metres"].isHittable,
            "Expected the completed metres on screen"
        )
        let statistics = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Altitude gained today")
        ).firstMatch
        XCTAssertTrue(statistics.exists && statistics.isHittable, "Expected the complete stats row on screen")
        let fact = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "The highest point in Wales")
        ).firstMatch
        XCTAssertTrue(fact.exists && fact.isHittable, "Expected the full fact line on screen")
        let nextSummit = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Next summit,")
        ).firstMatch
        XCTAssertTrue(nextSummit.exists && nextSummit.isHittable, "Expected the next-summit tape on screen")
        let personalRecord = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "new personal record")
        ).firstMatch
        XCTAssertTrue(personalRecord.exists && personalRecord.isHittable, "Expected the fixture's PR row on screen")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Expected SummitReachedView to offer Done")
        done.tap()
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
    }

    func testSummitReachedAccessibilityMediumKeepsContentScrollable() throws {
        openForcedSummitReached(accessibilityMedium: true)

        XCTAssertTrue(app.staticTexts["SUMMIT REACHED"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Push - Full"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["Done"].firstMatch.isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(2.3))
        attachScreenshot(named: "fix1-summit-reached-accessibility-medium-top-dark")

        let fact = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "The highest point in Wales")
        ).firstMatch
        let statistics = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Altitude gained today")
        ).firstMatch
        let personalRecord = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "new personal record")
        ).firstMatch
        let nextSummit = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Next summit,")
        ).firstMatch
        let postcard = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Send a postcard from")
        ).firstMatch
        XCTAssertTrue(postcard.exists && postcard.isHittable, "The postcard action must remain pinned")
        for (element, description) in [
            (app.staticTexts["Snowdon"], "peak title"),
            (app.descendants(matching: .any)["1,085 metres"], "completed metres"),
            (fact, "full fact line"),
            (statistics, "stats row"),
            (personalRecord, "fixture PR row"),
            (nextSummit, "next-summit tape")
        ] {
            XCTAssertTrue(element.waitForExistence(timeout: 8), "Expected \(description) to exist")
        }
        XCTAssertTrue(app.staticTexts["Snowdon"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["1,085 metres"].isHittable)
        XCTAssertTrue(fact.isHittable && statistics.isHittable, "Expected the opening content above the footer")
        for _ in 0..<6 {
            if personalRecord.frame.maxY < postcard.frame.minY,
               nextSummit.frame.maxY < postcard.frame.minY {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(personalRecord.isHittable && nextSummit.isHittable)
        XCTAssertLessThan(personalRecord.frame.maxY, postcard.frame.minY, "PR row must clear the pinned footer")
        XCTAssertLessThan(nextSummit.frame.maxY, postcard.frame.minY, "Tape must clear the pinned footer")
        XCTAssertTrue(app.buttons["Done"].firstMatch.isHittable, "The footer must remain pinned")
        attachScreenshot(named: "fix1-summit-reached-accessibility-medium-bottom-dark")
    }

    private func openForcedSummitReached(accessibilityMedium: Bool = false) {
        var arguments = [
            "-SummitForceCrossing",
            "-UITestPRCelebrationFixture",
            "-UITestAppearance", "dark"
        ]
        if accessibilityMedium {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        }
        launch(arguments: arguments)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH[c] %@", "Altitude,")
            ).firstMatch.waitForExistence(timeout: 15),
            "Expected the Summit snapshot before starting the peak-crossing workout"
        )
        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))
        tapElement(identifier: "workout-preview-start", maxSwipes: 5)
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        XCTAssertTrue(app.descendants(matching: .any)["set-row-1"].waitForExistence(timeout: 5))
        tapButton(identifier: "stepper-weight-increment", times: 2)
        tapButton(identifier: "stepper-reps-increment", times: 2)

        tapElement(identifier: "workout-logger-finish", maxSwipes: 8, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }
        tapModalElement(identifier: "workout-rating-3")
    }

    func testSubstitutePresentsOnFirstTapAndCanReopen() throws {
        launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-logger-substitute", maxSwipes: 8)
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-substitution-sheet"].waitForExistence(timeout: 5),
            "Expected Substitute to present on the first tap"
        )
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["workout-substitution-sheet"].waitForExistence(timeout: 2))

        tapElement(identifier: "workout-logger-substitute", maxSwipes: 2, swipeUp: false)
        XCTAssertTrue(app.descendants(matching: .any)["workout-substitution-sheet"].waitForExistence(timeout: 5))
    }

    func testContinueAdvancesImmediatelyWithNonblockingFeedback() throws {
        launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-logger-continue", maxSwipes: 14)
        var transitionCopy = app.descendants(matching: .any)["workout-transition-feedback"]
        XCTAssertTrue(transitionCopy.waitForExistence(timeout: 5))
        let firstCopy = transitionCopy.value as? String ?? transitionCopy.label
        XCTAssertFalse(firstCopy.isEmpty)
        XCTAssertFalse(app.buttons["workout-celebration-primary"].exists)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let position = self.app.descendants(matching: .any)["workout-logger-current-position"]
                return position.exists && position.label.contains("2 of")
            },
            "Expected Continue to advance directly to exercise two"
        )

        tapElement(identifier: "workout-logger-continue", maxSwipes: 10)
        transitionCopy = app.descendants(matching: .any)["workout-transition-feedback"]
        XCTAssertTrue(transitionCopy.waitForExistence(timeout: 5))
        let secondCopy = transitionCopy.value as? String ?? transitionCopy.label

        XCTAssertFalse(secondCopy.isEmpty)
        XCTAssertNotEqual(firstCopy, secondCopy)

        XCTAssertFalse(app.buttons["workout-celebration-primary"].exists)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let position = self.app.descendants(matching: .any)["workout-logger-current-position"]
                return position.exists && position.label.contains("3 of")
            },
            "Expected the second Continue to advance directly to exercise three"
        )
    }

    func testLongWorkoutRequiresDurationConfirmationBeforeRating() throws {
        launch(arguments: ["-UITestLongWorkoutFixture"])

        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )
        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        tapElement(identifier: "workout-preview-start", maxSwipes: 4)
        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }

        XCTAssertTrue(app.buttons["Edit Duration"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["workout-rating-3"].exists)
        app.buttons["Edit Duration"].tap()
        XCTAssertTrue(app.steppers["workout-duration-correction-hours"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 5))

        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }
        XCTAssertTrue(app.buttons["Use Recorded Time"].waitForExistence(timeout: 5))
        app.buttons["Use Recorded Time"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-rating-3"].waitForExistence(timeout: 5))
    }

    private func tapButton(identifier: String, times: Int) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        for _ in 0..<times {
            button.tap()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertAccessibilityLabel(identifier: String, expectedLabel: String) {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        XCTAssertEqual(element.label, expectedLabel)
    }

    private func tapTab(at index: Int, expectedTitle: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let namedTab = tabBar.buttons[expectedTitle]
        let tab = namedTab.waitForExistence(timeout: 2) ? namedTab : tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        tab.tap()
        if !app.navigationBars[expectedTitle].waitForExistence(timeout: 2),
           !app.staticTexts[expectedTitle].waitForExistence(timeout: 2) {
            tab.tap()
        }
        XCTAssertTrue(
            app.navigationBars[expectedTitle].waitForExistence(timeout: 5) ||
                app.staticTexts[expectedTitle].waitForExistence(timeout: 5),
            "Expected \(expectedTitle) tab to be visible"
        )
    }

    private func tapElement(identifier: String, maxSwipes: Int, swipeUp: Bool = true) {
        var element = tappableElement(identifier: identifier)
        var swipes = 0
        while (!element.waitForExistence(timeout: 1) || !element.isHittable) && swipes < maxSwipes {
            if swipeUp {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
            swipes += 1
            element = tappableElement(identifier: identifier)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        element.tap()
    }

    private func tapModalElement(identifier: String, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        var element = tappableElement(identifier: identifier)

        while (!element.exists || !element.isHittable) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            element = tappableElement(identifier: identifier)
        }

        XCTAssertTrue(element.exists, "Expected \(identifier) to exist")
        XCTAssertTrue(element.isHittable, "Expected \(identifier) to be hittable")
        element.tap()
    }

    private func tappableElement(identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.exists {
            return button
        }

        return app.descendants(matching: .any)[identifier]
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return condition()
    }
}
