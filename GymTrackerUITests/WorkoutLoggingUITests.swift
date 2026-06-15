import XCTest

final class WorkoutLoggingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
    }

    func testSeededWorkoutCanLogSetPauseFinishAndReachHistory() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "start-split-Push", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-preview-start", maxSwipes: 12)
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 10))

        tapElement(identifier: "workout-logger-add-set", maxSwipes: 8)
        XCTAssertTrue(app.descendants(matching: .any)["set-row-1"].waitForExistence(timeout: 5))

        tapButton(identifier: "stepper-weight-increment", times: 2)
        tapButton(identifier: "stepper-reps-increment", times: 6)
        tapElement(identifier: "quick-set-complete", maxSwipes: 2)

        tapElement(identifier: "workout-logger-pause", maxSwipes: 6, swipeUp: false)
        tapElement(identifier: "workout-logger-resume", maxSwipes: 2, swipeUp: false)

        tapElement(identifier: "workout-logger-finish", maxSwipes: 6, swipeUp: false)
        if app.buttons["Finish Anyway"].waitForExistence(timeout: 3) {
            app.buttons["Finish Anyway"].tap()
        }

        tapModalElement(identifier: "workout-rating-3")

        tapModalElement(identifier: "workout-celebration-primary")
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Push")).firstMatch.waitForExistence(timeout: 8))
    }

    private func tapButton(identifier: String, times: Int) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        for _ in 0..<times {
            button.tap()
        }
    }

    private func tapTab(at index: Int, expectedTitle: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let tab = tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        tab.tap()
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
}
