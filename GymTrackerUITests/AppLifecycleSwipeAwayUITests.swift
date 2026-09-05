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

    func testBackgroundTerminateAndRelaunchRemainsUsable() throws {
        app = makeApp()
        app.launch()
        waitForToday()
        primeLifecycleRelatedRoutes()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        waitForToday()

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        waitForToday()
        // The fixture is in-memory: verify a usable relaunch, not durable restoration.
        tapElement(identifier: "quick-action-sleep", maxSwipes: 5)
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 8))
        tapBackButton()
        waitForToday()
        print("LIFECYCLE_RELAUNCH_PASS")
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

    private func waitForToday() {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to settle"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["today-readiness-hero"].waitForExistence(timeout: 10),
            "Expected the Today readiness hero"
        )
    }

    private func primeLifecycleRelatedRoutes() {
        tapElement(identifier: "quick-action-sleep", maxSwipes: 5)
        XCTAssertTrue(
            app.navigationBars["Sleep"].waitForExistence(timeout: 8) ||
                app.staticTexts["Sleep"].waitForExistence(timeout: 8)
        )
        tapBackButton()
        waitForToday()

        tapElement(identifier: "today-readiness-hero", maxSwipes: 8)
        XCTAssertTrue(waitForCoachScreen(), "Expected Coach to open during lifecycle priming")
        tapBackButton()
        waitForToday()

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout Preview to open during lifecycle priming")
        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Workout to return after lifecycle priming")
        tapTab(at: 0, expectedTitle: "Today")
        waitForToday()
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
