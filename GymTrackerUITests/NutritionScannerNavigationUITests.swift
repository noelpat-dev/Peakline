import XCTest

final class NutritionScannerNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var launchArguments = ["-UITestInMemoryStore"]
        if name.contains("SavedFoods") {
            launchArguments.append("-UITestSavedFoodsFixture")
        }
        app.launchArguments = launchArguments
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
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))

        tapButton(containing: "Add Food", maxSwipes: 3)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Scan Barcode", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Scan Barcode"].waitForExistence(timeout: 5))
    }

    func testSavedFoodsScrollsFromListContentAndSearchStillWorks() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapElement(identifier: "quick-action-nutrition", maxSwipes: 5)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))

        tapButton(containing: "Add Food", maxSwipes: 3)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Saved Foods", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Banana"].waitForExistence(timeout: 5))

        var contentDrags = 0
        while !app.staticTexts["Final Scroll Marker Food"].exists && contentDrags < 6 {
            dragListContentUp()
            contentDrags += 1
        }
        XCTAssertTrue(app.staticTexts["Final Scroll Marker Food"].waitForExistence(timeout: 5))
        deleteVisibleSavedFood(named: "Final Scroll Marker Food")

        app.swipeDown()
        app.swipeDown()
        let searchField = app.textFields["Search foods or brands"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("tuna")
        XCTAssertTrue(app.staticTexts["Tuna"].waitForExistence(timeout: 5))
    }

    private func dragListContentUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.18))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func deleteVisibleSavedFood(named foodName: String) {
        let foodLabel = app.staticTexts[foodName]
        XCTAssertTrue(foodLabel.waitForExistence(timeout: 5), "Expected \(foodName) to be visible before deleting it")

        foodLabel.press(forDuration: 1.0)
        let deleteFoodAction = app.buttons["Delete Food"]
        XCTAssertTrue(deleteFoodAction.waitForExistence(timeout: 5), "Expected context menu delete action for \(foodName)")
        deleteFoodAction.tap()

        XCTAssertTrue(app.alerts["Delete food?"].waitForExistence(timeout: 5), "Expected delete confirmation alert")
        app.alerts["Delete food?"].buttons["Delete"].tap()
        XCTAssertFalse(foodLabel.waitForExistence(timeout: 2), "Expected \(foodName) to be removed after confirming delete")
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
