import XCTest

final class CoachWorkoutPreviewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var launchArguments = [
            "-UITestInMemoryStore",
            "-UITestCoachFatigueFixture"
        ]
        if name.contains("QuickActionProblemPaths") {
            launchArguments.append("-UITestLargeHistoryFixture")
        }
        app.launchArguments = launchArguments
        app.launch()
    }

    func testPreviewCancelApplyResetAndStartOriginalFlows() throws {
        openWorkoutPreview()

        tapElement(identifier: "coach-action-reduceAccessories")
        XCTAssertTrue(app.navigationBars["Preview Action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Exercise Preview"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["why-this-changed-card"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))

        tapElement(identifier: "coach-action-reduceAccessories")
        XCTAssertTrue(app.navigationBars["Preview Action"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.staticTexts["Reduce accessories applied"].waitForExistence(timeout: 5))

        tapElement(identifier: "workout-preview-reset-original")
        XCTAssertFalse(app.staticTexts["Reduce accessories applied"].waitForExistence(timeout: 2))

        tapElement(identifier: "coach-action-reduceAccessories")
        XCTAssertTrue(app.navigationBars["Preview Action"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.staticTexts["Reduce accessories applied"].waitForExistence(timeout: 5))

        tapElement(identifier: "workout-preview-start-original")
        XCTAssertTrue(app.staticTexts["Workout Order"].waitForExistence(timeout: 8))
    }

    func testManualDeloadPlannerCanOpenAndSaveBlock() throws {
        openWorkoutPreview()

        tapElement(identifier: "coach-action-deloadStyleSession")
        XCTAssertTrue(app.navigationBars["Deload"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manual Deload Planner"].exists)

        tapElement(identifier: "manual-deload-save-block")
        XCTAssertTrue(app.descendants(matching: .any)["manual-deload-calendar-review"].waitForExistence(timeout: 5))
        tapElement(identifier: "manual-deload-confirm-save")
        XCTAssertTrue(app.buttons["Deload Block Saved"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
    }

    func testExerciseMetadataEditorCanSaveCoachContext() throws {
        openExerciseLibrary()

        tapElement(identifier: "exercise-library-row-Bench Press", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))

        tapElement(identifier: "coach-metadata-note", maxSwipes: 8)
        let noteField = app.descendants(matching: .any)["coach-metadata-note"]
        noteField.tap()
        noteField.typeText("Priority bench for UI test")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))

        tapElement(identifier: "exercise-library-row-Bench Press", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
        tapElement(identifier: "coach-metadata-note", maxSwipes: 8)
        let savedValue = app.descendants(matching: .any)["coach-metadata-note"].value as? String
        XCTAssertEqual(savedValue, "Priority bench for UI test")
    }

    func testCoachActionHistoryDetailFiltersAndSavesFeedback() throws {
        openCoachHub()

        tapElement(identifier: "coach-history-detail-open", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Coach History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export CSV"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.descendants(matching: .any)["coach-history-filter-outcome"].waitForExistence(timeout: 5))

        let appliedRow = app.buttons.containing(.staticText, identifier: "Reduce accessories applied").firstMatch
        XCTAssertTrue(appliedRow.waitForExistence(timeout: 5))
        appliedRow.tap()

        XCTAssertTrue(app.navigationBars["Action Detail"].waitForExistence(timeout: 5))
        tapElement(identifier: "coach-feedback-helpful", maxSwipes: 6)
        tapElement(identifier: "coach-history-save-feedback", maxSwipes: 6)
        XCTAssertTrue(app.navigationBars["Coach History"].waitForExistence(timeout: 5))
    }

    func testCoachPreferencesAndSplitIntentOpen() throws {
        openCoachHub()

        tapElement(identifier: "coach-preferences-open", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Coach Preferences"].waitForExistence(timeout: 5))

        tapElement(identifier: "coach-preferences-aggressiveness", maxSwipes: 2)
        let assertive = app.buttons["Assertive"]
        if assertive.waitForExistence(timeout: 2) {
            assertive.tap()
        }

        tapElement(identifier: "split-metadata-open-Push", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Split Intent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["split-metadata-priority"].exists)
    }

    func testProblemNavigationCardsOpenWithoutFreezing() throws {
        openCoachHub()

        tapElement(identifier: "coach-preferences-open", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Coach Preferences"].waitForExistence(timeout: 5))
        tapBackButton()

        tapElement(identifier: "coach-weekly-review-open", maxSwipes: 10)
        XCTAssertTrue(app.navigationBars["Weekly Review"].waitForExistence(timeout: 5))
        tapBackButton()
        tapBackButton()

        openProgressHub()
        tapElement(identifier: "progress-pr-timeline-open", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["PR Timeline"].waitForExistence(timeout: 5))
    }

    func testQuickActionProblemPathsOpenUnderLargeHistoryFixture() throws {
        tapElement(identifier: "quick-action-progress", maxSwipes: 5)
        XCTAssertTrue(app.descendants(matching: .any)["progress-pr-timeline-open"].waitForExistence(timeout: 8))
        tapElement(identifier: "progress-pr-timeline-open", maxSwipes: 2)
        XCTAssertTrue(app.staticTexts["PR Timeline"].waitForExistence(timeout: 8))
        tapBackButton()
        tapBackButton()

        tapElement(identifier: "quick-action-readiness", maxSwipes: 5)
        XCTAssertTrue(app.descendants(matching: .any)["coach-preferences-open"].waitForExistence(timeout: 8))
        tapElement(identifier: "coach-preferences-open", maxSwipes: 8)
        XCTAssertTrue(app.staticTexts["Coach Preferences"].waitForExistence(timeout: 8))
        tapBackButton()

        tapElement(identifier: "coach-weekly-review-open", maxSwipes: 10)
        XCTAssertTrue(app.staticTexts["Weekly Review"].waitForExistence(timeout: 8))
    }

    func testBulkMetadataEditorReviewAndApply() throws {
        openExerciseLibrary()

        tapElement(identifier: "bulk-metadata-open", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Bulk Metadata"].waitForExistence(timeout: 5))

        tapElement(identifier: "bulk-metadata-review", maxSwipes: 6)
        tapElement(identifier: "bulk-metadata-apply", maxSwipes: 6)
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))
    }

    private func openWorkoutPreview() {
        tapTab(at: 1, expectedTitle: "Workout")
        let pushSplit = app.buttons["start-split-Push"]
        XCTAssertTrue(pushSplit.waitForExistence(timeout: 10))
        pushSplit.tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))
    }

    private func openExerciseLibrary() {
        tapTab(at: 4, expectedTitle: "Settings")
        let libraryLink = app.descendants(matching: .any)["settings-exercise-library"]
        if libraryLink.waitForExistence(timeout: 8) {
            libraryLink.tap()
        } else {
            tapElement(identifier: "settings-exercise-library", maxSwipes: 4)
        }
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))
    }

    private func openCoachHub() {
        tapTab(at: 4, expectedTitle: "Settings")
        tapElement(identifier: "settings-coach", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["coach-preferences-open"].waitForExistence(timeout: 8))
    }

    private func openProgressHub() {
        tapTab(at: 4, expectedTitle: "Settings")
        tapElement(identifier: "settings-progress", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["progress-pr-timeline-open"].waitForExistence(timeout: 8))
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
}
