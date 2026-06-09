import XCTest

final class SplitsPageUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
    }

    func testSeededSplitsOpenDetailAndAddSheet() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 2, expectedTitle: "Splits")
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))

        for splitName in ["Push", "Pull", "Legs"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["split-card-\(splitName)"].waitForExistence(timeout: 5),
                "Expected seeded \(splitName) split card"
            )
        }

        app.descendants(matching: .any)["split-card-Push"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["split-detail-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["split-detail-title-Push"].waitForExistence(timeout: 5))

        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))

        app.buttons["add-split-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["add-split-screen"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Expected a back button")
        backButton.tap()
    }
}
