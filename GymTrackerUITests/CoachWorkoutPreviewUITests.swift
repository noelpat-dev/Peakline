import XCTest

final class CoachWorkoutPreviewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(arguments: [String] = [], performance: Bool = false) {
        app.launchArguments = ["-UITestInMemoryStore"] + arguments
        if performance {
            app.launchArguments.append("-PerformanceAcceptanceMode")
            app.launchEnvironment["PERFORMANCE_ACCEPTANCE_MODE"] = "1"
        }
        app.launch()
    }

    func testBrandedStartupWaitsForCriticalReadyThenShowsToday() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestStartupAnimationMaxMS", "1500", "-UITestStartupPreparationDelayMS", "350"])

        let splash = app.descendants(matching: .any)["startup-brand-screen"]
        let criticalReady = app.descendants(matching: .any)["startup-critical-ready"]
        // XCTest can finish attaching after the normal one-shot splash has
        // completed. The reducer tests cover both readiness/animation orders;
        // this path verifies the resulting usable Today screen.
        XCTAssertTrue(criticalReady.waitForExistence(timeout: 12))
        XCTAssertTrue(splash.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 5))
    }

    func testBrandedStartupSlowPathSettlesAndShowsTruthfulProgress() throws {
        // Hold actual preparation long enough for XCTest to attach and inspect
        // the slow state; this uses the existing debug-only preparation delay.
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestStartupAnimationMaxMS", "250", "-UITestStartupPreparationDelayMS", "12000"])

        let splash = app.descendants(matching: .any)["startup-brand-screen"]
        XCTAssertTrue(splash.waitForExistence(timeout: 3))

        let slowStatusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", "Preparing"),
            object: splash
        )
        XCTAssertEqual(XCTWaiter.wait(for: [slowStatusExpectation], timeout: 2), .completed)
        let criticalReady = app.descendants(matching: .any)["startup-critical-ready"]
        XCTAssertFalse(criticalReady.isHittable)

        XCTAssertTrue(
            criticalReady.waitForExistence(timeout: 12)
        )
        XCTAssertTrue(splash.waitForNonExistence(timeout: 3))
    }

    func testPreviewCancelApplyResetAndStartOriginalFlows() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

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
        launch(arguments: ["-UITestCoachFatigueFixture"])

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
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openExerciseLibrary()

        tapElement(identifier: "exercise-library-row-Bench Press", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))

        tapButton(containing: "Coaching preferences", maxSwipes: 10)
        tapElement(identifier: "coach-metadata-note", maxSwipes: 8)
        let noteField = app.descendants(matching: .any)["coach-metadata-note"]
        noteField.tap()
        noteField.typeText("Priority bench for UI test")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))

        tapElement(identifier: "exercise-library-row-Bench Press", maxSwipes: 8)
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
        tapButton(containing: "Coaching preferences", maxSwipes: 10)
        tapElement(identifier: "coach-metadata-note", maxSwipes: 8)
        let savedValue = app.descendants(matching: .any)["coach-metadata-note"].value as? String
        XCTAssertEqual(savedValue, "Priority bench for UI test")
    }

    func testCoachActionHistoryDetailCanSubmitFeedbackAndReturn() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

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
        launch(arguments: ["-UITestCoachFatigueFixture"])

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
        launch(arguments: ["-UITestCoachFatigueFixture"])

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
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture"])

        tapTodayMenuAction(title: "Progress & Charts")
        XCTAssertTrue(app.descendants(matching: .any)["progress-pr-timeline-open"].waitForExistence(timeout: 8))
        tapElement(identifier: "progress-pr-timeline-open", maxSwipes: 2)
        XCTAssertTrue(app.staticTexts["PR Timeline"].waitForExistence(timeout: 8))
        tapBackButton()
        tapBackButton()

        tapElement(identifier: "today-readiness-hero", maxSwipes: 5)
        XCTAssertTrue(waitForCoachScreen(), "Expected quick action readiness to open Coach")
        tapElement(identifier: "coach-preferences-open", maxSwipes: 18)
        XCTAssertTrue(app.staticTexts["Coach Preferences"].waitForExistence(timeout: 8))
        tapBackButton()

        tapElement(identifier: "coach-weekly-review-open", maxSwipes: 10)
        XCTAssertTrue(app.staticTexts["Weekly Review"].waitForExistence(timeout: 8))
    }

    func testBulkMetadataEditorReviewAndApply() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openExerciseLibrary()

        tapElement(identifier: "bulk-metadata-open", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Bulk Metadata"].waitForExistence(timeout: 5))

        tapElement(identifier: "bulk-metadata-review", maxSwipes: 6)
        tapElement(identifier: "bulk-metadata-apply", maxSwipes: 6)
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))
    }

    func testPerformanceAcceptanceRoutes() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["startup-critical-ready"].waitForExistence(timeout: 5),
            "Expected the DEBUG performance summary to remain mounted for the full route journey"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["today-readiness-hero"].waitForExistence(timeout: 10),
            "Expected Today to expose the redesigned readiness hero"
        )

        tapElement(identifier: "today-readiness-hero", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        let coachCall = app.descendants(matching: .any)["coach-todays-call"]
        XCTAssertTrue(coachCall.waitForExistence(timeout: 12))
        XCTAssertFalse(coachCall.label.isEmpty, "Expected Coach call to contain the prepared training decision")
        XCTAssertFalse(coachCall.label.contains("Mode"), "Coach hero should show only the split name, not (coachCall.label)")
        let expectedSplit = ["Push", "Pull", "Legs", "Upper", "Lower"].first {
            coachCall.label.localizedCaseInsensitiveContains($0)
        }
        XCTAssertNotNil(expectedSplit, "Expected Coach call to expose the recommended split")

        tapElement(identifier: "coach-primary-action", maxSwipes: 10)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Coach -> Preview to open")
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10), "Expected Preview to expose its prepared route")
        let previewSplit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", expectedSplit ?? "")).firstMatch
        XCTAssertTrue(previewSplit.waitForExistence(timeout: 10))
        tapButton(containing: "Quick", maxSwipes: 4)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Preview to remain visible after mode change")
        tapBackButton(from: "Preview")
        XCTAssertTrue(waitForCoachScreen(), "Expected one back from Preview to return to Coach")

        tapBackButton(from: "Coach")
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapButton(containing: "Coach", maxSwipes: 5)
        XCTAssertTrue(waitForCoachScreen(), "Expected Workout -> Coach to open")
        tapBackButton(from: "Coach")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected one back from Coach to return to Workout")

        assertPerformanceAcceptancePassed()
    }

    func testReviewTodayPlanOpensPreparedPreviewWithoutStartingLogger() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapElement(identifier: "today-review-plan", maxSwipes: 8)

        XCTAssertTrue(waitForPreviewScreen(), "Expected Review Today’s Plan to open Preview")
        XCTAssertTrue(
            app.buttons["workout-preview-start"].waitForExistence(timeout: 8)
                || app.buttons["workout-preview-start-footer"].waitForExistence(timeout: 8),
            "Expected the prepared Preview start action to remain available"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["workout-logger-screen"].exists,
            "Reviewing Today’s Plan must not start the Logger"
        )
    }

    func testTodayCoachSupportsNativeEdgeSwipeBack() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["today-coach-brief-open"].exists)
        XCTAssertTrue(app.buttons["quick-action-nutrition"].exists)

        for _ in 0..<3 {
            tapElement(identifier: "today-readiness-hero", maxSwipes: 4)
            XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
            let call = app.descendants(matching: .any)["coach-todays-call"]
            XCTAssertTrue(call.exists)
            XCTAssertFalse(call.label.localizedCaseInsensitiveContains("preparing"))
            XCTAssertTrue(app.descendants(matching: .any)["coach-why-this-section"].exists)
            edgeSwipeBack()
            XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        }
        assertPerformanceAcceptancePassed()
    }

    func testCoachAndWeeklyReviewRemainHydratedAcrossBackgrounding() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapElement(identifier: "today-readiness-hero", maxSwipes: 8)
        XCTAssertTrue(waitForCoachScreen(), "Expected Readiness to use the warmed Coach route")
        XCTAssertTrue(app.descendants(matching: .any)["coach-todays-call"].waitForExistence(timeout: 3))

        let evidenceToggle = app.descendants(matching: .any)["coach-why-this-toggle"]
        XCTAssertTrue(evidenceToggle.waitForExistence(timeout: 5), "Expected Coach evidence disclosure toggle")
        XCTAssertEqual(evidenceToggle.value as? String, "Collapsed")
        let tapEvidenceHeader = {
            // SwiftUI exposes the disclosure's state on its enclosing AX group.
            // Tap the native header button, not the centre of expanded details.
            let header = evidenceToggle.elementType == .button
                ? evidenceToggle
                : evidenceToggle.buttons.firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            XCTAssertTrue(header.isHittable)
            header.tap()
        }

        tapEvidenceHeader()
        XCTAssertTrue(
            waitUntil(timeout: 2) { evidenceToggle.value as? String == "Expanded" },
            "Expected the Coach evidence disclosure to expand"
        )

        tapEvidenceHeader()
        XCTAssertTrue(
            waitUntil(timeout: 2) { evidenceToggle.value as? String == "Collapsed" },
            "Expected the Coach evidence disclosure to collapse after a repeated toggle.\n\(evidenceToggle.debugDescription)"
        )

        tapEvidenceHeader()
        XCTAssertTrue(
            waitUntil(timeout: 2) { evidenceToggle.value as? String == "Expanded" },
            "Expected the Coach evidence disclosure to expand again after repeated toggles"
        )

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["coach-todays-call"].waitForExistence(timeout: 3), "Expected Coach content to remain mounted after reactivation")
        XCTAssertTrue(evidenceToggle.waitForExistence(timeout: 3), "Expected Coach evidence disclosure to remain mounted after reactivation")
        XCTAssertEqual(
            evidenceToggle.value as? String,
            "Expanded",
            "Expected Coach evidence disclosure state to survive backgrounding and re-entry"
        )

        tapElement(identifier: "coach-weekly-review-open", maxSwipes: 12)
        XCTAssertTrue(app.navigationBars["Weekly Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Preparing weekly review"].exists)

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.activate()
        XCTAssertTrue(app.navigationBars["Weekly Review"].waitForExistence(timeout: 5), "Expected Weekly Review navigation state to survive backgrounding")
        XCTAssertFalse(app.staticTexts["Preparing weekly review"].exists)
    }

    func testTodayStartWorkoutCoachOpensAndReturnsResponsively() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTodayMenuAction(title: "Start Workout")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Today -> Start Workout to open")

        tapButton(containing: "Coach", maxSwipes: 5)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Start Workout -> Coach to open")
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-why-this-section"].waitForExistence(timeout: 1),
            "Expected the first supporting Coach card to mount with the prepared hero"
        )

        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Coach back navigation to return to Workout")
    }

    func testWorkoutRecommendedStartOpensLoggerDirectly() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-start", maxSwipes: 8)

        XCTAssertTrue(
            app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 8),
            "Expected Start Workout to open the logger directly"
        )

        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen())
        tapElement(identifier: "workout-active-resume")
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 8))

        tapBackButton()
        tapElement(identifier: "workout-active-discard")
        let confirmation = app.alerts["Discard active workout?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["workout-active-resume"].exists)
        tapElement(identifier: "workout-active-discard")
        confirmation.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["workout-recommended-start"].waitForExistence(timeout: 5))
    }

    func testPreviewStartDoubleTapShowsOneLogger() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout tab preview to open")

        let start = app.buttons["workout-preview-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Expected Preview start button to be available")
        start.doubleTap()

        let logger = app.otherElements["workout-logger-screen"]
        XCTAssertTrue(logger.waitForExistence(timeout: 5), "Expected one live workout logger after a rapid repeated tap")
        XCTAssertEqual(app.otherElements.matching(identifier: "workout-logger-screen").count, 1)
    }

    func testQuickActionsPreviewShowsPreparedContent() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapElement(identifier: "quick-action-workout", maxSwipes: 5)
        XCTAssertTrue(waitForWorkoutScreen(), "Expected Quick Actions -> Start Workout to open Workout")

        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Quick Actions -> Start Workout -> Preview to open")

        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-hydrated-content"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["workout-preview-start"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-basic-exercise-rows"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 4))

        XCTAssertFalse(app.staticTexts["Targets loading"].exists)
        XCTAssertFalse(app.staticTexts["Coach details are preparing."].exists)

        tapBackButton(from: "Preview")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected back navigation from Preview to return to Workout")
        assertPerformanceAcceptancePassed()
    }

    func testWorkoutPreviewShowsExerciseRowsAndCoachGuidance() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout tab preview to open")

        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-basic-exercise-rows"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 4))

        tapBackButton(from: "Preview")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected back navigation from Preview to return to Workout")
        assertPerformanceAcceptancePassed()
    }

    func testRepeatLastWorkoutPreviewShowsPreparedContent() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapButton(containing: "Repeat Last Workout", maxSwipes: 10)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Repeat Last Workout to open Preview")

        XCTAssertTrue(app.buttons["workout-preview-start"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-basic-exercise-rows"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 4))

        tapBackButton(from: "Preview")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected back navigation from repeated Preview to return to Workout")
        assertPerformanceAcceptancePassed()
    }

    func testPreviewStartButtonRemainsAvailableDuringHydration() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout tab preview to open")

        let startButton = app.buttons["workout-preview-start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3), "Expected start button before full coach hydration")
        XCTAssertTrue(startButton.isEnabled, "Expected start button to stay enabled during hydration")
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-guidance-chips"].waitForExistence(timeout: 4))
        XCTAssertTrue(startButton.exists || app.buttons["workout-preview-start-footer"].exists, "Expected a start control to remain available after hydration")

        tapBackButton(from: "Preview")
        XCTAssertTrue(waitForWorkoutScreen(), "Expected back navigation from Preview to return to Workout")
        assertPerformanceAcceptancePassed()
    }

    func testWorkoutPreviewModeChangeDoesNotOverRefreshAfterMotionRehaul() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        openWorkoutPreview()
        tapButton(containing: "Quick", maxSwipes: 4)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Preview to remain visible after motion-aware mode change")
        assertPerformanceAcceptancePassed()
    }

    func testWorkoutPreviewShowsReorderHandleAndRetainsContentAfterScrolling() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        openWorkoutPreview()

        let reorderHandle = app.descendants(matching: .any)["workout-preview-reorder-handle"].firstMatch
        var swipes = 0
        while !reorderHandle.waitForExistence(timeout: 1), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(reorderHandle.waitForExistence(timeout: 3), "Expected Exercise Order to expose a dedicated reorder handle")

        for _ in 0..<5 { app.swipeUp() }
        for _ in 0..<5 { app.swipeDown() }

        XCTAssertTrue(waitForPreviewScreen(), "Expected Preview to remain stable during sustained scrolling")
        XCTAssertTrue(app.descendants(matching: .any)["workout-preview-hydrated-content"].exists)
    }

    func testWorkoutPreviewReordersByDroppingOnRowAndLoggerKeepsThatOrder() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openWorkoutPreview()

        let firstExercise = "Incline Chest Press (Smith)"
        let secondExercise = "Bench Press"
        var firstRow = app.staticTexts["workout-preview-exercise-name-\(firstExercise)"]
        var secondHandle = previewReorderHandle(named: secondExercise)
        var swipes = 0
        while (!firstRow.waitForExistence(timeout: 1) || !secondHandle.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
            firstRow = app.staticTexts["workout-preview-exercise-name-\(firstExercise)"]
            secondHandle = previewReorderHandle(named: secondExercise)
        }

        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Expected the first Preview exercise row")
        XCTAssertTrue(secondHandle.waitForExistence(timeout: 5), "Expected the second exercise's reorder handle")
        XCTAssertTrue(secondHandle.isHittable, "Expected the dedicated drag source to be hittable")

        secondHandle.tap()
        XCTAssertEqual(secondHandle.value as? String, "Position 2 of 10", "A quick touch must not pick up or reorder an exercise")
        XCTAssertEqual(previewReorderHandle(named: firstExercise).value as? String, "Position 1 of 10")

        secondHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2)
        XCTAssertEqual(
            previewReorderHandle(named: secondExercise).value as? String,
            "Position 2 of 10",
            "A short hold without a drop target must cancel without reordering the exercise"
        )
        XCTAssertEqual(
            previewReorderHandle(named: firstExercise).value as? String,
            "Position 1 of 10",
            "A canceled reorder must leave the first exercise in place"
        )

        let destination = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.58))
        secondHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.2,
                thenDragTo: destination,
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let first = self.app.staticTexts["workout-preview-exercise-name-\(firstExercise)"]
                let second = self.app.staticTexts["workout-preview-exercise-name-\(secondExercise)"]
                return first.exists && second.exists && second.frame.minY < first.frame.minY
            },
            "Expected dropping the second handle on the first row body to reverse their visible order"
        )

        tapElement(identifier: "workout-preview-start-footer", maxSwipes: 18)
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 10))

        let currentExerciseName = app.staticTexts["workout-logger-current-exercise-name"]
        XCTAssertTrue(currentExerciseName.waitForExistence(timeout: 5))
        XCTAssertEqual(currentExerciseName.label, secondExercise)

        tapButton(containing: "Workout Order", maxSwipes: 6)

        let firstLoggerRow = app.staticTexts["workout-logger-order-name-\(secondExercise)"]
        let secondLoggerRow = app.staticTexts["workout-logger-order-name-\(firstExercise)"]
        XCTAssertTrue(firstLoggerRow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondLoggerRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(firstLoggerRow.frame.minY, secondLoggerRow.frame.minY)

        let moveSecondExerciseUp = app.buttons["workout-logger-order-move-up-\(secondExercise)"]
        let moveFirstExerciseDown = app.buttons["workout-logger-order-move-down-\(firstExercise)"]
        XCTAssertTrue(moveSecondExerciseUp.waitForExistence(timeout: 5))
        XCTAssertTrue(moveFirstExerciseDown.waitForExistence(timeout: 5))
        XCTAssertEqual(moveSecondExerciseUp.label, "Move \(secondExercise) up")
        XCTAssertEqual(moveFirstExerciseDown.label, "Move \(firstExercise) down")
    }

    func testWorkoutPreviewOptionalExerciseMenuSelectsAndAddsExercise() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openWorkoutPreview()

        let menu = assertReachable(
            app.descendants(matching: .any)["workout-preview-optional-exercise-menu"],
            named: "optional-exercise menu"
        )
        menu.tap()

        let exerciseName = "Lat Pulldown"
        let option = app.descendants(matching: .any)["workout-preview-optional-exercise-option-\(exerciseName)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected the menu to retain every addable exercise")
        option.tap()

        let selectedMenu = app.descendants(matching: .any)["workout-preview-optional-exercise-menu"]
        XCTAssertTrue(selectedMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedMenu.value as? String, exerciseName)

        tapElement(identifier: "workout-preview-add-selected-exercise", maxSwipes: 2)
        XCTAssertTrue(
            app.staticTexts["workout-preview-exercise-name-\(exerciseName)"].waitForExistence(timeout: 5),
            "Expected the selected exercise to join the prepared workout"
        )
    }

    func testWorkoutPreviewFullModeDoesNotScrollHorizontally() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openWorkoutPreview(splitName: "Legs")

        let content = app.descendants(matching: .any)["workout-preview-hydrated-content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5), "Expected hydrated Full-mode Preview content")
        let initialMinX = content.frame.minX

        app.swipeLeft()

        XCTAssertEqual(
            content.frame.minX,
            initialMinX,
            accuracy: 1,
            "Expected Full-mode Preview content to remain locked to the viewport after a horizontal swipe"
        )
    }

    func testWorkoutPreviewActionsUseAnchoredNamedMenuAndAccessibleTarget() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openWorkoutPreview()

        var actions = app.buttons["workout-preview-exercise-actions"].firstMatch
        var swipes = 0
        while (!actions.waitForExistence(timeout: 1) || !actions.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
            actions = app.buttons["workout-preview-exercise-actions"].firstMatch
        }

        XCTAssertTrue(actions.waitForExistence(timeout: 5), "Expected an exercise actions control")
        XCTAssertTrue(actions.label.hasPrefix("Actions for "), "Expected the menu label to name its exercise")
        XCTAssertGreaterThanOrEqual(actions.frame.width, 43.5)
        XCTAssertGreaterThanOrEqual(actions.frame.height, 43.5)
        actions.tap()

        XCTAssertTrue(app.buttons["Choose Substitute"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Move to Bottom"].exists || app.buttons["Move to Top"].exists)
        XCTAssertTrue(app.buttons["Remove"].exists)
    }

    func testWorkoutPreviewStateSurvivesAnimatedTabRoundTrip() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openWorkoutPreview()
        XCTAssertTrue(app.buttons["workout-preview-start"].waitForExistence(timeout: 5))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 8))

        tabBar.buttons["Workout"].tap()
        XCTAssertTrue(waitForPreviewScreen(), "Expected the Workout tab to preserve its Preview route")
        XCTAssertTrue(app.buttons["workout-preview-start"].waitForExistence(timeout: 5))
    }

    func testAppearanceChoicesCanBeSelectedAndRemainSelected() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openSettingsFromToday()
        tapElement(identifier: "settings-appearance", maxSwipes: 8)

        let greenTheme = app.descendants(matching: .any)["theme-option-appleGreen"]
        XCTAssertTrue(greenTheme.waitForExistence(timeout: 5))
        greenTheme.tap()
        XCTAssertEqual(greenTheme.value as? String, "Selected")

        tapBackButton(from: "Appearance")
        tapElement(identifier: "settings-appearance", maxSwipes: 8)
        XCTAssertEqual(
            app.descendants(matching: .any)["theme-option-appleGreen"].value as? String,
            "Selected"
        )
    }

    func testSettingsIsReachableFromTodayProfileMenuAndDismisses() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertEqual(tabBar.buttons.count, 4)
        for title in ["Today", "Workout", "Splits", "History"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "Expected \(title) root tab")
        }
        XCTAssertFalse(tabBar.buttons["Settings"].exists)

        openSettingsFromToday()

        XCTAssertTrue(app.descendants(matching: .any)["settings-screen"].exists)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-screen"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].exists)
    }

    func testSettingsProfileWorkoutToolsAndAppearanceAreTruthfulAndReachable() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        openSettingsFromToday()
        tapElement(identifier: "settings-profile", maxSwipes: 4)

        XCTAssertTrue(app.descendants(matching: .any)["profile-editor-screen"].waitForExistence(timeout: 5))
        let overview = app.descendants(matching: .any)["profile-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.value as? String, "Hypertrophy, Beginner")

        let goal = assertReachable(
            app.descendants(matching: .any)["profile-goal-menu"],
            named: "goal menu"
        )
        XCTAssertEqual(goal.value as? String, "Hypertrophy")

        let experience = assertReachable(
            app.descendants(matching: .any)["profile-experience-menu"],
            named: "experience menu"
        )
        XCTAssertEqual(experience.value as? String, "Beginner")

        let trainingDays = assertReachable(
            app.descendants(matching: .any)["profile-training-days-value"],
            named: "training-days value"
        )
        XCTAssertEqual(trainingDays.value as? String, "4 days")

        let liftingStart = assertReachable(
            app.descendants(matching: .any)["profile-lifting-start"],
            named: "lifting-start control"
        )
        XCTAssertFalse((liftingStart.value as? String ?? "").isEmpty)

        let bodyweight = assertReachable(
            app.descendants(matching: .any)["profile-bodyweight-field"],
            named: "bodyweight field"
        )
        XCTAssertEqual(bodyweight.value as? String, "Not set")

        assertReachable(
            app.staticTexts["Private reference notes. Workouts are not changed automatically."],
            named: "truthful injury-note explanation"
        )
        let injuryNotes = assertReachable(
            app.descendants(matching: .any)["profile-injury-notes"],
            named: "injury notes field"
        )
        XCTAssertEqual(injuryNotes.value as? String, "Not set")
        XCTAssertTrue(app.staticTexts["No injury notes added"].exists)
        XCTAssertFalse(app.staticTexts["Preferred split"].exists)
        XCTAssertFalse(app.staticTexts["Units"].exists)

        tapBackButton(from: "Profile")
        assertReachable(
            app.staticTexts["Calculate metric plates here or beside each live set."],
            named: "live-set Plate Calculator discoverability copy",
            maxSwipes: 10
        )
        tapElement(identifier: "settings-plate-calculator", maxSwipes: 10)

        XCTAssertTrue(app.navigationBars["Plate Calculator"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["plate-calculator-screen"].waitForExistence(timeout: 5))
        let plateExplanation = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "Metric only. Enter the total barbell weight in kilograms. During a live workout, open this calculator beside a set to prefill that set's load."
            )
        ).firstMatch
        XCTAssertTrue(plateExplanation.waitForExistence(timeout: 5))
        let targetWeight = app.descendants(matching: .any)["plate-calculator-target"]
        XCTAssertTrue(targetWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(targetWeight.value as? String, "100 kilograms")
        let barWeight = app.descendants(matching: .any)["plate-calculator-bar"]
        XCTAssertTrue(barWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(barWeight.value as? String, "20 kilograms")

        tapBackButton(from: "Plate Calculator")
        tapElement(identifier: "settings-appearance", maxSwipes: 6)

        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appearance-settings-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["theme-option-appleGreen"].exists)
        let modeOption = assertReachable(
            app.descendants(matching: .any)["appearance-option-system"],
            named: "labelled appearance mode option"
        )
        XCTAssertEqual(modeOption.label, "System appearance")
        XCTAssertTrue(
            (modeOption.value as? String).map { ["Selected", "Not selected"].contains($0) } ?? false
        )
    }

    func testAccountBackupPassphraseAcceptsInputWhenAccountIsReady() throws {
        openSettingsFromToday()
        tapElement(identifier: "settings-account-backup", maxSwipes: 12)
        XCTAssertTrue(app.navigationBars["Account & Backup"].waitForExistence(timeout: 8))

        let passphrase = app.descendants(matching: .any)["account-backup-passphrase"]
        XCTAssertTrue(passphrase.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == YES"),
            object: passphrase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)

        passphrase.tap()
        passphrase.typeText("correct horse battery staple")
        XCTAssertFalse((passphrase.value as? String ?? "").isEmpty)
    }

    func testHistoryRowsOpenAfterMotionRehaul() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture"])

        tapTab(at: 3, expectedTitle: "History")
        tapHistorySessionRow(containing: "Push")
        XCTAssertTrue(
            app.descendants(matching: .any)["history-detail-hero"].waitForExistence(timeout: 8) ||
                app.descendants(matching: .any)["history-workout-detail"].waitForExistence(timeout: 8),
            "Expected History row to open workout detail"
        )
    }

    func testPerformanceAcceptanceRootTabTransitionsRemainResponsive() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["startup-critical-ready"].waitForExistence(timeout: 5),
            "Expected startup-critical work to settle before measuring root tab transitions"
        )

        tapTabAndAssertResponsive(at: 1, expectedTitle: "Workout")
        tapTabAndAssertResponsive(at: 2, expectedTitle: "Splits")
        tapTabAndAssertResponsive(at: 3, expectedTitle: "History")
        tapTabAndAssertResponsive(at: 1, expectedTitle: "Workout")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["workout-recommended-preview"].waitForExistence(timeout: 5))
        tapTabAndAssertResponsive(at: 0, expectedTitle: "Today")

        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichReadinessRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        measurePrimaryQuickAction(
            identifier: "today-readiness-hero",
            routeIdentifier: "coach-route-screen",
            route: "readiness",
            actionable: {
                let call = self.app.descendants(matching: .any)["coach-todays-call"]
                return call.exists && !call.label.localizedCaseInsensitiveContains("preparing")
            }
        )
        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichSleepRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        measurePrimaryQuickAction(
            identifier: "quick-action-sleep",
            routeIdentifier: "sleep-screen",
            route: "sleep",
            actionable: {
                self.app.descendants(matching: .any)["sleep-no-data-hero"].exists
                    || self.app.descendants(matching: .any)["sleep-last-night-duration"].exists
                    || self.app.descendants(matching: .any)["sleep-active-hero"].exists
            }
        )
        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichNutritionRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        measurePrimaryQuickAction(
            identifier: "quick-action-nutrition",
            routeIdentifier: "nutrition-screen",
            route: "nutrition",
            actionable: {
                !self.app.descendants(matching: .any)["nutrition-loading"].exists
                    && self.app.descendants(matching: .any)["nutrition-hero"].exists
            }
        )
        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichProgressRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        measurePrimaryQuickAction(
            identifier: "quick-action-progress",
            routeIdentifier: "progress-screen",
            route: "progress",
            actionable: {
                self.app.buttons["progress-pr-timeline-open"].exists
                    && !self.app.staticTexts["Loading progress data"].exists
            }
        )
        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichHydrationRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        measurePrimaryQuickAction(
            identifier: "quick-action-hydration",
            routeIdentifier: "hydration-screen",
            route: "hydration",
            actionable: {
                self.app.progressIndicators["Hydration progress"].exists
            }
        )
        assertPerformanceAcceptancePassed()
    }

    func testPerformanceAcceptanceDataRichPreviewRoute() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"], performance: true)

        prepareDataRichPerformanceRoute()
        scrollTodayToTop()
        tapElement(identifier: "quick-action-workout", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Next Lift to open its prepared Preview directly")
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-preview-hydrated-content"].waitForExistence(timeout: 5),
            "Expected Preview's actionable hydrated content"
        )
        assertPerformanceAcceptancePassed()
    }

    func testDataRichPrimaryQuickActionsRemainPopulated() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["startup-critical-ready"].waitForExistence(timeout: 5))
        waitForDataRichFixtureInsertionToSettle()

        measurePrimaryQuickAction(
            identifier: "today-readiness-hero",
            routeIdentifier: "coach-route-screen",
            route: "readiness",
            actionable: {
                let call = self.app.descendants(matching: .any)["coach-todays-call"]
                return call.exists && !call.label.localizedCaseInsensitiveContains("preparing")
            }
        )
        tapBackButton(from: "Coach")

        measurePrimaryQuickAction(
            identifier: "quick-action-sleep",
            routeIdentifier: "sleep-screen",
            route: "sleep",
            actionable: {
                self.app.descendants(matching: .any)["sleep-no-data-hero"].exists
                    || self.app.descendants(matching: .any)["sleep-last-night-duration"].exists
                    || self.app.descendants(matching: .any)["sleep-active-hero"].exists
            }
        )
        tapBackButton(from: "Sleep")

        measurePrimaryQuickAction(
            identifier: "quick-action-nutrition",
            routeIdentifier: "nutrition-screen",
            route: "nutrition",
            actionable: {
                !self.app.descendants(matching: .any)["nutrition-loading"].exists
                    && self.app.descendants(matching: .any)["nutrition-hero"].exists
            }
        )
        tapBackButton(from: "Nutrition")

        measurePrimaryQuickAction(
            identifier: "quick-action-progress",
            routeIdentifier: "progress-screen",
            route: "progress",
            actionable: {
                self.app.buttons["progress-pr-timeline-open"].exists
                    && !self.app.staticTexts["Loading progress data"].exists
            }
        )
        tapBackButton(from: "Progress")

        measurePrimaryQuickAction(
            identifier: "quick-action-hydration",
            routeIdentifier: "hydration-screen",
            route: "hydration",
            actionable: {
                self.app.progressIndicators["Hydration progress"].exists
            }
        )
        tapBackButton(from: "Hydration")

        scrollTodayToTop()
        tapElement(identifier: "quick-action-workout", maxSwipes: 8)
        XCTAssertTrue(waitForWorkoutScreen(), "Expected the Workout quick action to open Start Workout")
        let previewButton = tappableElement(identifier: "workout-recommended-preview")
        XCTAssertTrue(previewButton.waitForExistence(timeout: 8))
        let startedAt = Date()
        previewButton.tap()
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout Preview to open")
        let hydrated = app.descendants(matching: .any)["workout-preview-hydrated-content"]
        XCTAssertTrue(hydrated.waitForExistence(timeout: 5), "Expected Preview's actionable hydrated content")
        let previewMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        print("PRIMARY_QUICK_ACTION_UI_METRIC route=preview elapsed_ms=\(previewMilliseconds)")
        tapBackButton(from: "Preview")
        tapBackButton(from: "Workout")

    }

    func testDataRichRootTabsRemainPopulated() throws {
        launch(arguments: ["-UITestCoachFatigueFixture", "-UITestLargeHistoryFixture", "-UITestSavedFoodsFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["startup-critical-ready"].waitForExistence(timeout: 5))
        waitForDataRichFixtureInsertionToSettle()

        tapTabAndAssertResponsive(at: 1, expectedTitle: "Workout")
        tapTabAndAssertResponsive(at: 2, expectedTitle: "Splits")
        tapTabAndAssertResponsive(at: 3, expectedTitle: "History")

    }

    func testCoachOmitsDuplicateCheckIn() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        tapElement(identifier: "today-readiness-hero", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        for _ in 0..<18 { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["Today's Check-In"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["coach-check-in-open"].exists)
    }

    func testReadinessV2ShowsProvisionalCoverageAndMissingSignals() throws {
        launch()

        let provisional = app.descendants(matching: .any)["readiness-provisional-status"].firstMatch
        let coverage = app.descendants(matching: .any)["readiness-signal-coverage"]
        let score = app.descendants(matching: .any)["today-readiness-score-value"]

        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertEqual(score.label, "—")
        XCTAssertFalse(provisional.exists, "Zero-evidence readiness should show an unavailable score without a provisional badge")
        XCTAssertTrue(coverage.waitForExistence(timeout: 3))
        XCTAssertEqual(coverage.label, "0 of 5 signals included")

        tapElement(identifier: "today-readiness-hero", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        let coachHeadline = app.descendants(matching: .any)["coach-todays-call"]
        XCTAssertTrue(coachHeadline.waitForExistence(timeout: 2))
        XCTAssertFalse(
            coachHeadline.label.localizedCaseInsensitiveContains("readiness pending"),
            "Expected the split name to remain the Coach headline while Provisional carries readiness status"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-why-this-section"].waitForExistence(timeout: 1),
            "Expected prepared Coach context without a blank supporting-content gap"
        )

        let missingTraining = assertReachable(
            app.descendants(matching: .any)["readiness-factor-training"],
            named: "missing training readiness factor",
            maxSwipes: 30
        )
        XCTAssertTrue(
            missingTraining.label.localizedCaseInsensitiveContains("not included"),
            "Expected an unavailable readiness factor to say Not included; got \(missingTraining.label)"
        )
    }

    func testReadinessV2CheckInSaveRefreshesScoreImmediately() throws {
        launch()

        let score = app.descendants(matching: .any)["today-readiness-score-value"]
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertEqual(score.label, "—")

        tapTodayCheckIn()
        XCTAssertTrue(app.descendants(matching: .any)["check-in-sheet"].waitForExistence(timeout: 3))

        assertCheckInSelectionResponds(row: "energy", rating: 5)
        assertCheckInSelectionResponds(row: "soreness", rating: 1)
        assertCheckInSelectionResponds(row: "stress", rating: 1)
        assertCheckInSelectionResponds(row: "motivation", rating: 5)
        tapButton(containing: "Save check-in", maxSwipes: 8)

        XCTAssertTrue(
            app.descendants(matching: .any)["check-in-sheet"].waitForNonExistence(timeout: 3),
            "Expected the saved check-in sheet to dismiss"
        )
        XCTAssertTrue(
            waitUntil(timeout: 3) { score.exists && score.label == "82" },
            "Expected the single strong check-in to refresh readiness from 70 to 82; got \(score.label)"
        )
    }

    func testTodayCheckInPresentsDismissesAndReopensSmoothly() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTodayCheckIn()
        XCTAssertTrue(app.descendants(matching: .any)["check-in-sheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Check-In"].waitForExistence(timeout: 2))

        app.buttons["Done"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["check-in-sheet"].waitForNonExistence(timeout: 2),
            "Expected Check-In to dismiss once"
        )

        tapTodayCheckIn()
        XCTAssertTrue(app.descendants(matching: .any)["check-in-sheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Check-In"].waitForExistence(timeout: 2))
    }

    func testPerformanceAcceptanceManualBlockerFlow() throws {
        launch(arguments: ["-UITestCoachFatigueFixture"], performance: true)

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapElement(identifier: "quick-action-sleep", maxSwipes: 5)
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 8) || app.staticTexts["Sleep"].waitForExistence(timeout: 8))
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        tapTab(at: 1, expectedTitle: "Workout")
        tapElement(identifier: "workout-recommended-preview", maxSwipes: 8)
        XCTAssertTrue(waitForPreviewScreen(), "Expected Workout Preview to open")
        tapBackButton()
        XCTAssertTrue(waitForWorkoutScreen(), "Expected one back from Preview to return to Workout")

        tapTab(at: 0, expectedTitle: "Today")
        tapElement(identifier: "today-readiness-hero", maxSwipes: 8)
        XCTAssertTrue(waitForCoachScreen(), "Expected Today -> Coach to open")
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))

        assertPerformanceAcceptancePassed()
    }

    private func openWorkoutPreview(splitName: String = "Push") {
        tapTab(at: 1, expectedTitle: "Workout")
        let splitButton = app.buttons["start-split-\(splitName)"]
        XCTAssertTrue(splitButton.waitForExistence(timeout: 10))
        splitButton.tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 10))
    }

    private func openExerciseLibrary() {
        openSettingsFromToday()
        let libraryLink = app.descendants(matching: .any)["settings-exercise-library"]
        if libraryLink.waitForExistence(timeout: 8) {
            libraryLink.tap()
        } else {
            tapElement(identifier: "settings-exercise-library", maxSwipes: 4)
        }
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))
    }

    private func openCoachHub() {
        openSettingsFromToday()
        tapElement(identifier: "settings-coach", maxSwipes: 4)
        XCTAssertTrue(waitForCoachScreen(), "Expected Settings -> Coach to open")
    }

    private func tapTodayCheckIn() {
        let directAction = tappableElement(identifier: "today-check-in-open")
        if directAction.waitForExistence(timeout: 1), directAction.isHittable {
            directAction.tap()
            return
        }

        tapElement(identifier: "today-profile-menu", maxSwipes: 2)
        tapButton(containing: "Check In", maxSwipes: 2)
    }

    private func tapTodayMenuAction(title: String) {
        tapElement(identifier: "today-profile-menu", maxSwipes: 2)
        tapButton(containing: title, maxSwipes: 2)
    }

    private func openSettingsFromToday() {
        if app.descendants(matching: .any)["settings-screen"].exists {
            return
        }
        if !app.descendants(matching: .any)["today-screen"].exists {
            tapTab(at: 0, expectedTitle: "Today")
        }
        tapElement(identifier: "today-profile-menu", maxSwipes: 2)
        tapButton(containing: "Settings", maxSwipes: 2)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
    }

    private func openProgressHub() {
        openSettingsFromToday()
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

    private func tapTabAndAssertResponsive(
        at index: Int,
        expectedTitle: String
    ) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let namedTab = tabBar.buttons[expectedTitle]
        let tab = namedTab.exists ? namedTab : tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        guard let identifier = tabScreenIdentifier(for: expectedTitle) else {
            XCTFail("Missing screen marker for \(expectedTitle)")
            return
        }

        XCTAssertTrue(tab.isHittable, "Expected \(expectedTitle) tab to be hittable before tapping")
        tab.tap()
        // A simulator/XCTest delivery miss can leave the control unselected and
        // produce no route marker. Retry that delivery case once only; a
        // selected tab with a slow destination must still fail the 3 s budget.
        if !tab.isSelected {
            tab.tap()
        }
        let destination = app.descendants(matching: .any)[identifier]
        let destinationAppeared = destination.waitForExistence(timeout: 3)
        if !destinationAppeared {
            print("Missing root screen marker \(identifier):\n\(app.debugDescription)")
        }
        XCTAssertTrue(destinationAppeared, "Expected \(expectedTitle) screen marker")
        assertPopulatedRootTab(expectedTitle)
    }

    private func assertPopulatedRootTab(_ title: String) {
        switch title {
        case "Today":
            XCTAssertTrue(
                app.descendants(matching: .any)["today-readiness-hero"].waitForExistence(timeout: 3),
                "Expected Today to expose its actionable readiness hero"
            )
        case "Workout":
            XCTAssertTrue(
                app.buttons["workout-recommended-preview"].waitForExistence(timeout: 3)
                    || app.buttons["start-split-Push"].waitForExistence(timeout: 3),
                "Expected Workout to expose a prepared Preview action"
            )
        case "Splits":
            XCTAssertTrue(
                app.descendants(matching: .any)["split-card-Push"].waitForExistence(timeout: 3),
                "Expected Splits to expose a seeded Push card"
            )
        case "History":
            XCTAssertTrue(
                app.buttons.matching(
                    NSPredicate(format: "identifier == %@", "history-session-row")
                ).firstMatch.waitForExistence(timeout: 3),
                "Expected History to expose at least one populated session row"
            )
        default:
            XCTFail("Missing populated-root assertion for \(title)")
        }
    }

    private func measurePrimaryQuickAction(
        identifier: String,
        routeIdentifier: String,
        route: String,
        actionable: @escaping () -> Bool
    ) {
        // Avoid introducing scroll gestures when the action is already visible.
        let entryIdentifier = todayMenuTitle(for: identifier) == nil ? identifier : "today-profile-menu"
        if !tappableElement(identifier: entryIdentifier).isHittable {
            scrollTodayToTop()
        }
        let startedAt: Date
        if let menuTitle = todayMenuTitle(for: identifier) {
            tapElement(identifier: "today-profile-menu", maxSwipes: 2)
            let menuAction = buttonContaining(menuTitle)
            XCTAssertTrue(menuAction.waitForExistence(timeout: 3), "Expected Today menu action \(menuTitle) to exist")
            XCTAssertTrue(menuAction.isHittable, "Expected Today menu action \(menuTitle) to be hittable")
            startedAt = Date()
            menuAction.tap()
        } else {
            var element = tappableElement(identifier: identifier)
            var swipes = 0
            while (!element.waitForExistence(timeout: 1) || !element.isHittable) && swipes < 8 {
                app.swipeUp()
                swipes += 1
                element = tappableElement(identifier: identifier)
            }
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
            startedAt = Date()
            element.tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)[routeIdentifier].waitForExistence(timeout: 8),
            "Expected \(routeIdentifier) after \(identifier)"
        )
        XCTAssertTrue(waitUntil(timeout: 3, condition: actionable), "Expected populated actionable content for \(route)")
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        // XCUI polling and cross-process accessibility transport dominate this
        // client-side number. The production NavigationInteraction timer,
        // surfaced in the acceptance summary, remains the threshold authority.
        print("PRIMARY_QUICK_ACTION_UI_METRIC route=\(route) elapsed_ms=\(elapsedMilliseconds)")
    }

    private func todayMenuTitle(for identifier: String) -> String? {
        switch identifier {
        case "quick-action-progress":
            return "Progress & Charts"
        default:
            return nil
        }
    }

    private func scrollTodayToTop() {
        for _ in 0..<3 {
            app.swipeDown()
        }
    }

    private func waitForDataRichFixtureInsertionToSettle() {
        // The UI fixture creates thousands of SwiftData objects during this
        // launch; real large-history users do not reinsert their history on
        // every cold start. Keep fixture construction outside the measured
        // navigation sample while preserving the production route thresholds.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    private func prepareDataRichPerformanceRoute() {
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["startup-critical-ready"].waitForExistence(timeout: 5))
        waitForDataRichFixtureInsertionToSettle()
    }

    private func waitForTabContent(_ expectedTitle: String, timeout: TimeInterval) -> Bool {
        if let identifier = tabScreenIdentifier(for: expectedTitle) {
            return app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.navigationBars[expectedTitle].exists || app.staticTexts[expectedTitle].exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        return app.navigationBars[expectedTitle].exists || app.staticTexts[expectedTitle].exists
    }

    private func tabScreenIdentifier(for title: String) -> String? {
        switch title {
        case "Today":
            return "today-screen"
        case "Workout":
            return "workout-screen"
        case "Splits":
            return "splits-screen"
        case "History":
            return "history-screen"
        default:
            return nil
        }
    }

    private func tapBackButton(from navigationTitle: String? = nil) {
        if let navigationTitle {
            let navigationBackButton = app.navigationBars[navigationTitle].buttons.element(boundBy: 0)
            XCTAssertTrue(navigationBackButton.waitForExistence(timeout: 5))
            navigationBackButton.tap()
            return
        }

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
        while (!element.waitForExistence(timeout: 1) || !hasUnobscuredTapPoint(element)) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            element = tappableElement(identifier: identifier)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        if !hasUnobscuredTapPoint(element) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(
            hasUnobscuredTapPoint(element),
            "Expected \(identifier) to have a tap point clear of navigation chrome. \(element.debugDescription)"
        )
        element.tap()
    }

    private func hasUnobscuredTapPoint(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }

        let windowFrame = app.windows.firstMatch.frame
        var unobscuredBottom = windowFrame.maxY
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.isHittable {
            unobscuredBottom = min(unobscuredBottom, tabBar.frame.minY)
        }

        // XCUIElement.tap() synthesizes at the element centre. Keep that point
        // away from the tab-bar boundary so a partially visible control cannot
        // accidentally reactivate the current tab instead of invoking itself.
        return windowFrame.contains(
            CGPoint(x: element.frame.midX, y: element.frame.midY)
        ) && element.frame.midY <= unobscuredBottom - 8
    }

    @discardableResult
    private func assertReachable(
        _ element: XCUIElement,
        named name: String,
        maxSwipes: Int = 8
    ) -> XCUIElement {
        let viewport = app.windows.firstMatch.frame
        var swipes = 0
        while (!element.waitForExistence(timeout: 1) || !element.frame.intersects(viewport)), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(name) to exist")
        XCTAssertTrue(element.frame.intersects(viewport), "Expected \(name) to be reachable on screen")
        return element
    }

    private func tappableElement(identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.exists {
            return button
        }

        return app.descendants(matching: .any)[identifier]
    }

    private func previewReorderHandle(named exerciseName: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "workout-preview-reorder-handle",
                    "Reorder \(exerciseName)"
                )
            )
            .firstMatch
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
        let summaryElement = app.descendants(matching: .any)["startup-critical-ready"]
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected startup root with performance summary to exist")

        let deadline = Date().addingTimeInterval(3)
        var summary = summaryElement.value as? String ?? ""
        while !summary.contains("performance_acceptance="), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            summary = summaryElement.value as? String ?? ""
        }

        print("PERF_ACCEPTANCE_UI_SUMMARY \(summary)")
        XCTAssertTrue(summary.contains("performance_acceptance=PASS"), summary)
        XCTAssertFalse(summary.contains("FAIL"), summary)
    }

    private func assertCheckInSelectionResponds(row: String, rating: Int) {
        let button = app.buttons["check-in-rating-\(row)-\(rating)"]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Expected \(row) rating \(rating)")

        var swipeCount = 0
        while !button.isHittable, swipeCount < 5 {
            app.swipeUp()
            swipeCount += 1
        }
        XCTAssertTrue(button.isHittable, "Expected \(row) rating \(rating) to be hittable")

        let startedAt = Date()
        button.tap()
        XCTAssertTrue(
            waitUntil(timeout: 1) { button.value as? String == "Selected" },
            "Expected \(row) rating \(rating) to become selected"
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        print("CHECKIN_RATING_RESPONSE row=\(row) rating=\(rating) elapsed=\(elapsed)")
    }
}
