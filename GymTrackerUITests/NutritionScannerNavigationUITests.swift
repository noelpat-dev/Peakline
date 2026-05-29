import XCTest

final class NutritionScannerNavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let savedFoodFixtureNames = [
        "Banana",
        "Blueberries",
        "Chicken Breast",
        "Cottage Cheese",
        "Eggs",
        "Final Scroll Marker Food",
        "Greek Yogurt",
        "Jasmine Rice",
        "Lean Mince",
        "Oats",
        "Pasta",
        "Peanut Butter",
        "Protein Bar",
        "Tuna",
        "Whey Protein",
        "Whole Milk"
    ]

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

        openNutritionFromQuickAction()

        tapButton(containing: "Add Food", maxSwipes: 3)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Scan Barcode", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Scan Barcode"].waitForExistence(timeout: 5))

        navigateBack(from: "Scan Barcode", to: "Add Food")
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

    func testSavedFoodsNativeSwipeDeleteShowsConfirmationWithoutBreakingScroll() throws {
        openSavedFoods()
        XCTAssertTrue(app.staticTexts["Banana"].waitForExistence(timeout: 5))

        scrollToSavedFood(named: "Final Scroll Marker Food")
        revealNativeDeleteAction(for: "Final Scroll Marker Food").tap()

        let alert = app.alerts["Delete food?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected native swipe delete to show confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Final Scroll Marker Food"].waitForExistence(timeout: 2), "Expected cancel to keep the saved food")

        cancelContextMenuDelete(for: "Final Scroll Marker Food")
        searchSavedFoods(query: "tuna", expectedResult: "Tuna")
    }

    func testSavedFoodsDeleteCancelAndConfirmRemainSafe() throws {
        openSavedFoods()
        XCTAssertTrue(app.staticTexts["Banana"].waitForExistence(timeout: 5))
        assertSavedFoodPrimaryActionsWork(for: "Banana")

        revealNativeDeleteAction(for: "Banana").tap()
        var alert = app.alerts["Delete food?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected delete confirmation alert")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Banana"].waitForExistence(timeout: 2), "Expected cancel to keep Banana")

        revealNativeDeleteAction(for: "Banana").tap()
        alert = app.alerts["Delete food?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected delete confirmation alert")
        alert.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Banana"].waitForExistence(timeout: 2), "Expected Banana to be removed after confirming delete")

        searchSavedFoods(query: "tuna", expectedResult: "Tuna")
    }

    private func openSavedFoods() {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        openNutritionFromQuickAction()

        tapButton(containing: "Add Food", maxSwipes: 3)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))

        tapButton(containing: "Saved Foods", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5))
    }

    private func openNutritionFromQuickAction() {
        tapElement(identifier: "quick-action-nutrition", maxSwipes: 5)
        if app.navigationBars["Nutrition"].waitForExistence(timeout: 8) {
            return
        }

        tapElement(identifier: "quick-action-nutrition", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 8), "Expected Nutrition after tapping the quick action")
    }

    private func scrollToSavedFood(named foodName: String) {
        var contentDrags = 0
        while !app.staticTexts[foodName].exists && contentDrags < 8 {
            dragSavedFoodCardContentUp()
            contentDrags += 1
        }
        XCTAssertTrue(app.staticTexts[foodName].waitForExistence(timeout: 5), "Expected \(foodName) after dragging Saved Foods content")
    }

    private func revealNativeDeleteAction(for foodName: String) -> XCUIElement {
        let row = savedFoodRow(named: foodName)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Expected \(foodName) row before swiping")

        let deleteButton = app.buttons["Delete"]
        for _ in 0..<2 where !deleteButton.exists {
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.28))
            let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.28))
            start.press(forDuration: 0.05, thenDragTo: end)
            if deleteButton.waitForExistence(timeout: 2) {
                return deleteButton
            }
            row.swipeLeft()
        }

        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Expected native trailing Delete action for \(foodName)")
        return deleteButton
    }

    private func savedFoodRow(named foodName: String, waitTimeout: TimeInterval = 1) -> XCUIElement {
        let identifiedRow = app.descendants(matching: .any)["saved-food-row-\(foodName)"]
        if waitTimeout > 0 {
            if identifiedRow.waitForExistence(timeout: waitTimeout) {
                return identifiedRow
            }
        } else if identifiedRow.exists {
            return identifiedRow
        }

        return app.staticTexts[foodName]
    }

    private func cancelContextMenuDelete(for foodName: String) {
        let foodLabel = app.staticTexts[foodName]
        XCTAssertTrue(foodLabel.waitForExistence(timeout: 5), "Expected \(foodName) before opening its context menu")
        closeOpenSwipeAction(for: foodName)

        for attempt in 0..<2 {
            foodLabel.press(forDuration: 1.0)
            let deleteFoodAction = app.buttons["Delete Food"]
            XCTAssertTrue(deleteFoodAction.waitForExistence(timeout: 5), "Expected context menu delete action for \(foodName)")
            deleteFoodAction.tap()

            let alert = app.alerts["Delete food?"]
            if alert.waitForExistence(timeout: 5) {
                alert.buttons["Cancel"].tap()
                XCTAssertTrue(foodLabel.waitForExistence(timeout: 2), "Expected context menu cancel to keep \(foodName)")
                return
            }

            if attempt == 0 {
                closeOpenSwipeAction(for: foodName)
            }
        }

        XCTFail("Expected context menu delete to keep confirmation")
    }

    private func closeOpenSwipeAction(for foodName: String) {
        guard app.buttons["Delete"].exists else { return }

        let row = savedFoodRow(named: foodName, waitTimeout: 0)
        if row.exists {
            row.swipeRight()
        } else {
            app.tap()
        }
    }

    private func searchSavedFoods(query: String, expectedResult: String) {
        let searchField = app.textFields["Search foods or brands"]
        var swipes = 0
        while (!searchField.waitForExistence(timeout: 1) || !searchField.isHittable) && swipes < 5 {
            app.swipeDown()
            swipes += 1
        }

        var repositionAttempts = 0
        while searchField.exists
            && searchField.frame.minY < app.frame.minY + 120
            && repositionAttempts < 3 {
            app.swipeDown()
            repositionAttempts += 1
        }

        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(query)
        XCTAssertTrue(app.staticTexts[expectedResult].waitForExistence(timeout: 5))
    }

    private func assertSavedFoodPrimaryActionsWork(for foodName: String) {
        let logButton = app.buttons["log-saved-food-\(foodName)"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 5), "Expected visible Log action for \(foodName)")
        logButton.tap()
        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 5), "Expected Log Food to open for \(foodName)")
        XCTAssertTrue(app.staticTexts[foodName].waitForExistence(timeout: 5), "Expected Log Food to show \(foodName)")
        navigateBack(from: "Log Food", to: "Saved Foods")
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5), "Expected to return from Log Food")

        let editButton = app.buttons["edit-saved-food-\(foodName)"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Expected visible Edit action for \(foodName)")
        editButton.tap()
        XCTAssertTrue(app.navigationBars["Edit Food"].waitForExistence(timeout: 5), "Expected Edit Food to open for \(foodName)")
        XCTAssertTrue(app.textFields[foodName].waitForExistence(timeout: 5), "Expected Edit Food to load \(foodName)")
        app.navigationBars["Edit Food"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5), "Expected to return from Edit Food")
    }

    private func dragSavedFoodCardContentUp() {
        let appFrame = app.frame
        let contentLabel = savedFoodFixtureNames
            .map { app.staticTexts[$0] }
            .filter { label in
                label.exists
                    && label.isHittable
                    && label.frame.intersects(appFrame)
                    && label.frame.midY > appFrame.minY + 120
            }
            .max { lhs, rhs in
                lhs.frame.midY < rhs.frame.midY
            }

        guard let contentLabel else {
            app.swipeUp()
            return
        }

        let start = contentLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: contentLabel.frame.midX / appFrame.width,
                dy: 0.16
            )
        )
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func navigateBack(from navigationTitle: String? = nil, to expectedNavigationTitle: String? = nil) {
        let navigationBar = navigationTitle.map { app.navigationBars[$0] } ?? app.navigationBars.element(boundBy: 0)
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "Expected a navigation bar before going back")

        let namedBackButtons = [expectedNavigationTitle, "Back", "BackButton"].compactMap { $0 }
        for buttonName in namedBackButtons {
            let button = navigationBar.buttons[buttonName]
            guard button.exists && button.isHittable else { continue }
            button.tap()
            if waitForNavigationBar(expectedNavigationTitle) {
                return
            }
        }

        let backButton = navigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Expected a back button")
        backButton.tap()
        if waitForNavigationBar(expectedNavigationTitle) {
            return
        }

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.50))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.50))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(waitForNavigationBar(expectedNavigationTitle), "Expected to navigate back")
    }

    private func waitForNavigationBar(_ navigationTitle: String?) -> Bool {
        guard let navigationTitle else { return true }
        return app.navigationBars[navigationTitle].waitForExistence(timeout: 5)
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
