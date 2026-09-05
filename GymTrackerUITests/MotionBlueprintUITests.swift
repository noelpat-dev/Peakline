import XCTest

final class MotionBlueprintUITests: XCTestCase {
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

    func testHistoryCachedRowsDoNotShowLoadingPlaceholder() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10)
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["History"].tap()

        let history = app.descendants(matching: .any)["history-screen"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["history-session-row"].firstMatch.waitForExistence(timeout: 10),
            "Expected the cached History rows to be usable"
        )
        XCTAssertFalse(
            app.staticTexts["Loading history"].exists,
            "Cached History rows must not be replaced by the fake loading placeholder"
        )
    }
}
