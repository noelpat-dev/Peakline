import XCTest

final class NutritionScannerNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
    }

    func testQuickActionNutritionCanOpenScannerSurfaces() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapElement(identifier: "quick-action-nutrition", maxSwipes: 5)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))

        tapButton(containing: "Add Food", maxSwipes: 3)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Scan Barcode", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Scan Barcode"].waitForExistence(timeout: 5))

        navigateBack()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Scan Label", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Scan Label"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scan nutrition label"].waitForExistence(timeout: 5))
    }

    func testTodayNutritionCardCanReachFoodLoggingEntryPoint() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapElement(identifier: "today-nutrition-summary", maxSwipes: 5)
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))

        tapElement(identifier: "nutrition-insights-log-food", maxSwipes: 4)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Scan Barcode", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Scan Barcode"].waitForExistence(timeout: 5))
    }

    private func navigateBack() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Expected a back button")
        backButton.tap()
    }

    private func tapButton(containing text: String, maxSwipes: Int) {
        var button = app.buttons.containing(.staticText, identifier: text).firstMatch
        var swipes = 0
        while (!button.waitForExistence(timeout: 1) || !button.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            button = app.buttons.containing(.staticText, identifier: text).firstMatch
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected button containing \(text)")
        button.tap()
    }

    private func tapElement(identifier: String, maxSwipes: Int) {
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
}
