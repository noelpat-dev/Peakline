import XCTest

final class HistoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemoryStore",
            "-UITestLargeHistoryFixture"
        ]
        app.launch()
    }

    func testHistoryOverviewIsCleanInformativeAndScrollable() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-overview-card"].waitForExistence(timeout: 10))
        let editGoal = app.buttons["Edit Goal"]
        let setGoal = app.buttons["Set Goal"]
        XCTAssertTrue(
            editGoal.waitForExistence(timeout: 3) || setGoal.waitForExistence(timeout: 2),
            "Expected the monthly attendance hero to expose its goal action"
        )
        XCTAssertTrue(app.descendants(matching: .any)["history-calendar-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history-filter-chips"].waitForExistence(timeout: 5))

        let firstRow = firstSessionRow()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8), "Expected at least one History session row")
        scrollIntoHittableRegion(firstRow)
        XCTAssertTrue(firstRow.isHittable, "Expected first History session row to be tappable above the tab bar")

        for _ in 0..<4 {
            app.swipeUp()
        }
        for _ in 0..<3 {
            app.swipeDown()
        }
        XCTAssertTrue(firstSessionRow().waitForExistence(timeout: 5), "Expected History list to remain scrollable")
    }

    func testHistoryCalendarFiltersAndSessionDetailOpen() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.descendants(matching: .any)["history-calendar-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-filter-chips"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.buttons["history-filter-button"].exists)
        let ratingFilterChip = app.buttons["Rating"].firstMatch
        XCTAssertTrue(ratingFilterChip.waitForExistence(timeout: 5))
        ratingFilterChip.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        let pushFilter = app.buttons.matching(identifier: "Push").firstMatch
        XCTAssertTrue(pushFilter.waitForExistence(timeout: 3), "Expected the Push split filter")
        pushFilter.tap()
        app.navigationBars["Filters"].buttons["Done"].tap()

        let firstRow = firstSessionRow()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8), "Expected a filtered History session row")
        let filteredRows = app.buttons.matching(identifier: "history-session-row").allElementsBoundByIndex
        XCTAssertTrue(filteredRows.allSatisfy { $0.label.contains("Push") }, "Push filtering must exclude other splits")
        scrollIntoHittableRegion(firstRow)
        XCTAssertTrue(firstRow.isHittable, "Expected filtered History row to be tappable")
        firstRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["history-detail-hero"].waitForExistence(timeout: 8))
        let editButton = app.buttons["history-workout-edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Expected the History workout Edit action")
        XCTAssertTrue(editButton.isHittable, "Expected Edit to remain tappable after opening a workout")
        editButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 8),
            "Expected History Edit to reach the completed-workout editor without freezing"
        )
        XCTAssertTrue(app.steppers["workout-edit-duration-hours"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.steppers["workout-edit-duration-minutes"].waitForExistence(timeout: 5))
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["history-detail-hero"].waitForExistence(timeout: 8))
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 8))
    }

    func testHistoryMonthNavigationKeepsOverviewAlignedAfterRapidSwitching() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 3, expectedTitle: "History")
        let selectedMonthTitle = app.staticTexts["history-selected-month-title"]
        let overviewMonthTitle = app.staticTexts["history-overview-month-title"]
        XCTAssertTrue(selectedMonthTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(overviewMonthTitle.waitForExistence(timeout: 10))

        let previousMonthButton = app.buttons["Previous month"]
        XCTAssertTrue(previousMonthButton.waitForExistence(timeout: 5))
        previousMonthButton.tap()
        previousMonthButton.tap()

        XCTAssertTrue(selectedMonthTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(overviewMonthTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(overviewMonthTitle.label, "\(selectedMonthTitle.label) attendance")
    }

    private func tapTab(at index: Int, expectedTitle: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let namedTab = tabBar.buttons[expectedTitle]
        let tab = namedTab.exists ? namedTab : tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        tab.tap()
        XCTAssertTrue(
            app.navigationBars[expectedTitle].waitForExistence(timeout: 8) ||
                app.staticTexts[expectedTitle].waitForExistence(timeout: 8) ||
                app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 8),
            "Expected \(expectedTitle) tab to be visible"
        )
    }

    private func firstSessionRow() -> XCUIElement {
        app.buttons.matching(identifier: "history-session-row").firstMatch
    }

    private func scrollIntoHittableRegion(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while element.exists && !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func tapBackButton() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }
}
