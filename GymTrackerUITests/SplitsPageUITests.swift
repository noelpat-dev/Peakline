import XCTest

final class SplitsPageUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore", "-UITestSplitsFixture"]
        app.launch()
    }

    func testSeededSplitsOpenDetailAndAddSheet() throws {
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 10) ||
                app.staticTexts["Today"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 2, expectedTitle: "Splits")
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))

        for splitName in ["Push", "Pull", "Legs", "Upper", "Lower"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["split-card-\(splitName)"].waitForExistence(timeout: 5),
                "Expected seeded \(splitName) split card"
            )
        }

        app.descendants(matching: .any)["split-card-Push"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["split-detail-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["split-detail-title-Push"].waitForExistence(timeout: 5))

        app.buttons["split-edit-button"].tap()
        XCTAssertTrue(app.navigationBars["Edit Split"].waitForExistence(timeout: 5))
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["Template note"].exists)
        XCTAssertFalse(app.staticTexts["Felt strong"].exists)
        tapBackButton()

        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))

        app.buttons["add-split-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["add-split-screen"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["splits-screen"].waitForExistence(timeout: 5))
    }

    func testFiveDayRotationCanBeOpenedAndSaved() throws {
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 10) ||
                app.staticTexts["Today"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )
        tapTab(at: 2, expectedTitle: "Splits")

        let editButton = app.buttons["edit-rotation-button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["edit-active-rotation-screen"].waitForExistence(timeout: 5))

        for splitName in ["Push", "Pull", "Legs", "Upper", "Lower"] {
            XCTAssertTrue(app.staticTexts[splitName].firstMatch.waitForExistence(timeout: 3))
        }

        app.buttons["save-active-rotation-button"].tap()
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
