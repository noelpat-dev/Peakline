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
        if name.contains("HistoryRowsOpenAfterMotionRehaul") {
            launchArguments.append("-UITestLargeHistoryFixture")
        }
        if name.contains("PerformanceAcceptance") {
            launchArguments.append("-PerformanceAcceptanceMode")
        }
        if name.contains("ModeChangeDoesNotOverRefreshAfterMotionRehaul") {
            launchArguments.append("-PerformanceAcceptanceMode")
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

        tapElement(identifier: "coach-preferences-open", maxSwipes: 18)
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

        tapElement(identifier: "coach-preferences-open", maxSwipes: 18)
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
        XCTAssertTrue(waitForCoachScreen(), "Expected quick action readiness to open Coach")
        tapElement(identifier: "coach-preferences-open", maxSwipes: 18)
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

    func testPerformanceAcceptanceRoutes() throws {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))
        let todaySuggestedSplit = app.descendants(matching: .any)["today-suggested-split"]
        XCTAssertTrue(todaySuggestedSplit.waitForExistence(timeout: 10))
        let suggestedSplit = todaySuggestedSplit.label
        XCTAssertTrue(app.descendants(matching: .any)["today-suggested-chips"].exists)

        tapElement(identifier: "today-coach-brief-open", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        let coachCall = dailyCallElement(containing: suggestedSplit)
        XCTAssertTrue(coachCall.waitForExistence(timeout: 12))
        XCTAssertTrue(coachCall.label.contains(suggestedSplit), "Expected Coach call \(coachCall.label) to match Today split \(suggestedSplit)")
        XCTAssertFalse(coachCall.label.contains("Mode"), "Coach hero should show only the split name, not \(coachCall.label)")

        tapElement(identifier: "coach-primary-action", maxSwipes: 10)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Coach -> Preview to open")
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 10))
        let previewSplit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", suggestedSplit)).firstMatch
        XCTAssertTrue(previewSplit.waitForExistence(timeout: 10))
        XCTAssertTrue(previewSplit.label.contains(suggestedSplit), "Expected Preview split \(previewSplit.label) to match Coach split \(suggestedSplit)")
        tapButton(containing: "Quick", maxSwipes: 4)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Preview to remain visible after mode change")
        tapBackButton()
        XCTAssertTrue(waitForCoachScreen(), "Expected one back from Preview to return to Coach")

        tapBackButton()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapButton(containing: "Coach", maxSwipes: 5)
        XCTAssertTrue(waitForCoachScreen(), "Expected Workout -> Coach to open")
        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected one back from Coach to return to Workout")

        assertPerformanceAcceptancePassed()
    }

    func testWorkoutPreviewModeChangeDoesNotOverRefreshAfterMotionRehaul() throws {
        openWorkoutPreview()
        tapButton(containing: "Quick", maxSwipes: 4)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Preview to remain visible after motion-aware mode change")
        assertPerformanceAcceptancePassed()
    }

    func testHistoryRowsOpenAfterMotionRehaul() throws {
        tapTab(at: 3, expectedTitle: "History")
        tapHistorySessionRow(containing: "Push")
        XCTAssertTrue(
            app.descendants(matching: .any)["history-workout-detail"].waitForExistence(timeout: 8),
            "Expected History row to open workout detail"
        )
    }

    func testTabSelectionStillWorksAfterMotionRehaul() throws {
        tapTab(at: 1, expectedTitle: "Workout")
        tapTab(at: 2, expectedTitle: "Splits")
        tapTab(at: 3, expectedTitle: "History")
        tapTab(at: 4, expectedTitle: "Settings")
        tapTab(at: 0, expectedTitle: "Today")
    }

    func testTodayCoachSupportsNativeEdgeSwipeBack() throws {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapElement(identifier: "today-coach-brief-open", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")

        edgeSwipeBack()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))
    }

    func testTodayStartWorkoutCoachOpensAndReturnsResponsively() throws {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapButton(containing: "Start Workout", maxSwipes: 2)
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Today -> Start Workout to open")

        tapButton(containing: "Coach", maxSwipes: 5)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Start Workout -> Coach to open")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 2), "Expected app window to remain responsive")

        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Coach back navigation to return to Workout")
    }

    func testRecoveryCheckInRatingControlsRenderWithoutValueBadges() throws {
        tapElement(identifier: "today-coach-brief-open", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")

        tapElement(identifier: "coach-check-in-open", maxSwipes: 18)
        XCTAssertTrue(app.navigationBars["Check-In"].waitForExistence(timeout: 5))

        assertCheckInRatingRow("energy")
        assertCheckInRatingRow("soreness")
        assertCheckInRatingRow("stress")
        assertCheckInRatingRow("motivation")
    }

    func testPerformanceAcceptanceManualBlockerFlow() throws {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapElement(identifier: "quick-action-sleep", maxSwipes: 5)
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 8) || app.staticTexts["Sleep"].waitForExistence(timeout: 8))
        tapBackButton()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout Preview to open")
        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected one back from Preview to return to Workout")

        tapTab(at: 0, expectedTitle: "Today")
        tapElement(identifier: "quick-action-readiness", maxSwipes: 8)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        tapBackButton()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        app.activate()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10) || app.staticTexts["Today"].waitForExistence(timeout: 10))

        assertPerformanceAcceptancePassed()
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
        XCTAssertTrue(waitForCoachScreen(), "Expected Settings -> Coach to open")
    }

    private func openProgressHub() {
        tapTab(at: 4, expectedTitle: "Settings")
        tapElement(identifier: "settings-progress", maxSwipes: 4)
        XCTAssertTrue(app.descendants(matching: .any)["progress-pr-timeline-open"].waitForExistence(timeout: 8))
    }

    private func tapTab(at index: Int, expectedTitle: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let namedTab = tabBar.buttons[expectedTitle]
        let tab = namedTab.exists ? namedTab : tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        tab.tap()

        if !waitForTabContent(expectedTitle, timeout: 8), namedTab.exists {
            namedTab.tap()
        }

        XCTAssertTrue(waitForTabContent(expectedTitle, timeout: 10), "Expected \(expectedTitle) tab to be visible")
    }

    private func waitForTabContent(_ expectedTitle: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.navigationBars[expectedTitle].exists || app.staticTexts[expectedTitle].exists {
                return true
            }

            if let identifier = tabScreenIdentifier(for: expectedTitle),
               app.descendants(matching: .any)[identifier].exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        return app.navigationBars[expectedTitle].exists || app.staticTexts[expectedTitle].exists
    }

    private func tabScreenIdentifier(for title: String) -> String? {
        switch title {
        case "Workout":
            return "workout-screen"
        case "Settings":
            return "settings-screen"
        default:
            return nil
        }
    }

    private func tapBackButton() {
        let explicitBackButton = app.buttons["BackButton"]
        let backButton = explicitBackButton.exists ? explicitBackButton : app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }

    private func edgeSwipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
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

    private func tapButton(containing title: String, maxSwipes: Int = 6) {
        var button = buttonContaining(title)
        var swipes = 0
        while (!button.waitForExistence(timeout: 1) || !button.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            button = buttonContaining(title)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected button containing \(title) to exist")
        button.tap()
    }

    private func buttonContaining(_ title: String) -> XCUIElement {
        let exact = app.buttons[title]
        if exact.exists {
            return exact
        }

        return app.buttons.containing(.staticText, identifier: title).firstMatch
    }

    private func tapHistorySessionRow(containing title: String, maxSwipes: Int = 8) {
        let predicate = NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "history-session-row",
            title
        )
        var row = app.buttons.matching(predicate).firstMatch
        var swipes = 0
        while (!row.waitForExistence(timeout: 1) || !row.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            row = app.buttons.matching(predicate).firstMatch
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Expected History row containing \(title) to exist")
        row.tap()
    }

    private func waitForCoachScreen() -> Bool {
        app.descendants(matching: .any)["coach-route-screen"].waitForExistence(timeout: 12) ||
            app.descendants(matching: .any)["coach-screen"].waitForExistence(timeout: 12) ||
            app.navigationBars["Coach"].waitForExistence(timeout: 12) ||
            app.staticTexts["Coach"].waitForExistence(timeout: 12)
    }

    private func waitForCoachDismissed() -> Bool {
        waitUntil(timeout: 12) {
            !app.descendants(matching: .any)["coach-screen"].exists &&
                !app.navigationBars["Coach"].exists
        }
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

    private func dailyCallElement(containing splitName: String) -> XCUIElement {
        let identified = app.descendants(matching: .any)["coach-todays-call"]
        if identified.exists {
            return identified
        }

        return app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", splitName)).firstMatch
    }

    private func waitForPreviewDismissed() -> Bool {
        waitUntil(timeout: 12) {
            !app.buttons["workout-preview-start"].exists &&
                !app.navigationBars["Preview"].exists
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return condition()
    }

    private func assertPerformanceAcceptancePassed() {
        let summaryElement = app.descendants(matching: .any)["performance-acceptance-summary"]
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected performance acceptance summary to exist")

        let deadline = Date().addingTimeInterval(3)
        var summary = summaryElement.label
        while !summary.contains("performance_acceptance="), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            summary = summaryElement.label
        }

        print("PERF_ACCEPTANCE_UI_SUMMARY \(summary)")
        XCTAssertTrue(summary.contains("performance_acceptance=PASS"), summary)
        XCTAssertFalse(summary.contains("FAIL"), summary)
    }

    private func assertCheckInRatingRow(_ suffix: String) {
        let title = app.staticTexts["check-in-title-\(suffix)"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Expected check-in title \(suffix)")
        XCTAssertFalse(app.staticTexts["check-in-value-\(suffix)"].exists, "Did not expect old \(suffix) value badge")

        var previousMidX: CGFloat?
        for rating in 1...5 {
            let button = app.buttons["check-in-rating-\(suffix)-\(rating)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Expected \(suffix) rating \(rating)")
            XCTAssertGreaterThan(button.frame.width, 0, "Expected \(suffix) rating \(rating) to have width")

            if let previousMidX {
                XCTAssertGreaterThan(button.frame.midX, previousMidX, "Expected \(suffix) rating buttons to render left-to-right")
            }
            previousMidX = button.frame.midX
        }
    }
}
