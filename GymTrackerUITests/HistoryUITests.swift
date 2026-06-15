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
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-overview-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-calendar-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history-filter-chips"].waitForExistence(timeout: 5))

        let firstRow = firstSessionRow()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8), "Expected at least one History session row")
        XCTAssertTrue(firstRow.isHittable, "Expected first History session row to be tappable above the tab bar")

        app.swipeUp()
        XCTAssertTrue(firstSessionRow().waitForExistence(timeout: 5), "Expected History list to remain scrollable")
    }

    func testHistoryCalendarFiltersAndSessionDetailOpen() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.descendants(matching: .any)["history-calendar-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-filter-chips"].waitForExistence(timeout: 5))

        let filterButton = app.buttons["history-filter-button"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        let pushFilter = app.buttons.matching(identifier: "Push").firstMatch
        if pushFilter.waitForExistence(timeout: 3) {
            pushFilter.tap()
        }
        app.navigationBars["Filters"].buttons["Done"].tap()

        let firstRow = firstSessionRow()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8), "Expected a filtered History session row")
        XCTAssertTrue(firstRow.isHittable, "Expected filtered History row to be tappable")
        firstRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["history-detail-hero"].waitForExistence(timeout: 8))
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 8))
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

    private func tapBackButton() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }
}
