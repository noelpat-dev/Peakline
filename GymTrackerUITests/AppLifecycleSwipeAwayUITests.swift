import XCTest

final class AppLifecycleSwipeAwayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testRepeatedBackgroundTerminateRelaunchLifecycle() throws {
        let cycles = 10

        for cycle in 1...cycles {
            app = makeApp()
            app.launch()
            print("LIFECYCLE_SWIPE_AWAY cycle=\(cycle) launched")

            waitForToday(cycle: cycle)

            if cycle == 1 {
                primeLifecycleRelatedRoutes()
            }

            XCUIDevice.shared.press(.home)
            print("LIFECYCLE_SWIPE_AWAY cycle=\(cycle) backgrounded")
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))

            app.terminate()
            print("LIFECYCLE_SWIPE_AWAY cycle=\(cycle) terminated")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemoryStore",
            "-UITestCoachFatigueFixture",
            "-PerformanceAcceptanceMode"
        ]
        return app
    }

    private func waitForToday(cycle: Int) {
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 10) ||
                app.staticTexts["Today"].waitForExistence(timeout: 10),
            "Expected Today to settle in lifecycle cycle \(cycle)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["today-suggested-split"].waitForExistence(timeout: 10),
            "Expected Today suggested split in lifecycle cycle \(cycle)"
        )
    }

    private func primeLifecycleRelatedRoutes() {
        tapElement(identifier: "quick-action-sleep", maxSwipes: 5)
        XCTAssertTrue(
            app.navigationBars["Sleep"].waitForExistence(timeout: 8) ||
                app.staticTexts["Sleep"].waitForExistence(timeout: 8)
        )
        tapBackButton()
        waitForToday(cycle: 1)

        tapElement(identifier: "quick-action-readiness", maxSwipes: 8)
        XCTAssertTrue(waitForCoachScreen(), "Expected Coach to open during lifecycle priming")
        tapBackButton()
        waitForToday(cycle: 1)

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout Preview to open during lifecycle priming")
        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Workout to return after lifecycle priming")
        tapTab(at: 0, expectedTitle: "Today")
        waitForToday(cycle: 1)
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

    private func tapBackButton() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }

    private func tapElement(identifier: String, maxSwipes: Int = 6) {
        var element = tappableElement(identifier: identifier)
        var swipes = 0
        while (!element.waitForExistence(timeout: 1) || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            element = tappableElement(identifier: identifier)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        element.tap()
    }

    private func tappableElement(identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.exists {
            return button
        }

        return app.descendants(matching: .any)[identifier]
    }

    private func waitForCoachScreen() -> Bool {
        app.descendants(matching: .any)["coach-route-screen"].waitForExistence(timeout: 12) ||
            app.descendants(matching: .any)["coach-screen"].waitForExistence(timeout: 12) ||
            app.navigationBars["Coach"].waitForExistence(timeout: 12) ||
            app.staticTexts["Coach"].waitForExistence(timeout: 12)
    }

    private func waitForWorkoutScreen() -> Bool {
        app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 12) ||
            app.buttons["workout-recommended-preview"].waitForExistence(timeout: 12) ||
            app.buttons["start-split-Push"].waitForExistence(timeout: 12) ||
            app.navigationBars["Workout"].waitForExistence(timeout: 12) ||
            app.staticTexts["Workout"].waitForExistence(timeout: 12)
    }

    private func waitForPreviewScreen() -> Bool {
        app.navigationBars["Preview"].waitForExistence(timeout: 15) ||
            app.staticTexts["Preview"].waitForExistence(timeout: 15) ||
            app.buttons["workout-preview-start"].waitForExistence(timeout: 15)
    }
}
