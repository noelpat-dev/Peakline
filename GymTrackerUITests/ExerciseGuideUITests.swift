import XCTest

final class ExerciseGuideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testPosePlaybackRepeatsAndContinuesAfterSelection() {
        launch(appearance: "dark", theme: "black")
        openGuide()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Weighted Crunch")
        tap("exercise-guide-row-weighted-crunch")
        XCTAssertFalse(app.buttons["exercise-preview-playback"].exists)
        let illustration = app.images["exercise-guide-illustration"]
        app.buttons["exercise-guide-pose-1"].tap()
        var observed = [1]
        let deadline = Date().addingTimeInterval(9)
        while observed.count < 9 && Date() < deadline {
            let label = illustration.label
            if let frame = (1...3).first(where: { label.contains("pose \($0) of 3") }), frame != observed.last {
                observed.append(frame)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(observed, [1, 2, 3, 2, 1, 2, 3, 2, 1])
        app.buttons["exercise-guide-pose-3"].tap()
        XCTAssertTrue(app.buttons["exercise-guide-pose-3"].isSelected)
        let returnsToMiddle = NSPredicate(format: "label CONTAINS %@", "pose 2 of 3")
        expectation(for: returnsToMiddle, evaluatedWith: illustration)
        waitForExpectations(timeout: 2)
        XCUIDevice.shared.press(.home)
        app.activate()
        var resumedLabels = Set<String>()
        let resumeDeadline = Date().addingTimeInterval(4)
        while resumedLabels.count < 3 && Date() < resumeDeadline {
            resumedLabels.insert(illustration.label)
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(resumedLabels, Set((1...3).map { "Weighted Crunch, pose \($0) of 3" }))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Exercise Guide"].waitForExistence(timeout: 5))
    }

    func testGuideSearchDetailsPosesAndReturnToLibrary() {
        launch(appearance: "dark", theme: "blue")
        openGuide()
        XCTAssertEqual(app.staticTexts["exercise-guide-result-count"].label, "302 exercises")
        capture("Exercise guide — blue dark")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Bench Press")
        tap("exercise-guide-row-bench-press")
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
        for label in ["Equipment, Barbell", "Primary muscle, Chest", "Secondary muscles, Triceps, Shoulders"] {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch.exists)
        }
        app.buttons["exercise-guide-pose-2"].tap()
        XCTAssertTrue(app.buttons["exercise-guide-pose-2"].isSelected)
        XCTAssertEqual(app.images["exercise-guide-illustration"].label, "Bench Press, pose 2 of 3")
        capture("Bench press — pose 2 blue dark")
        app.buttons["exercise-guide-pose-3"].tap()
        XCTAssertTrue(app.buttons["exercise-guide-pose-3"].isSelected)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Exercise Guide"].waitForExistence(timeout: 5))
        search.tap()
        if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }
        search.typeText("NoSuchExercise999")
        XCTAssertEqual(app.staticTexts["exercise-guide-result-count"].label, "0 exercises")
    }

    func testGuideSupportsLargeTextAndExistingExerciseEditor() {
        launch(appearance: "light", theme: "black", largeText: true)
        openLibrary()
        tap("exercise-library-row-Bench Press")
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exercise-guide-pose-1"].waitForExistence(timeout: 5))
        app.buttons["exercise-guide-pose-2"].tap()
        XCTAssertTrue(app.buttons["exercise-guide-pose-2"].isSelected)
        capture("Unified exercise editor — large text light")
        app.buttons["exercise-editor-credits"].tap()
        XCTAssertTrue(app.navigationBars["Artwork Credits"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exercise-guide-pose-1"].exists)
    }

    func testWorkoutGuideSheetsReturnToPreviewAndLogger() {
        launch(appearance: "dark", theme: "appleGreen")
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        app.tabBars.buttons.element(boundBy: 1).tap()
        tap("workout-recommended-preview")
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 8))
        let actions = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            "workout-preview-exercise-actions", "Actions for Bench Press"
        )).firstMatch
        reveal(actions)
        actions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let guideAction = app.buttons["Exercise Guide"]
        XCTAssertTrue(guideAction.waitForExistence(timeout: 5))
        guideAction.tap()
        XCTAssertTrue(app.buttons["exercise-guide-pose-1"].waitForExistence(timeout: 5))
        capture("Workout exercise guide — fitness green")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        reveal(actions)
        actions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let moveToTop = app.buttons["Move to Top"]
        XCTAssertTrue(moveToTop.waitForExistence(timeout: 5))
        moveToTop.tap()
        for _ in 0..<4 { app.swipeDown() }
        tap("workout-preview-start")
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 8))
        tap("workout-logger-exercise-guide")
        XCTAssertTrue(app.buttons["exercise-guide-pose-1"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-logger-screen"].waitForExistence(timeout: 5))
    }

    private func launch(appearance: String, theme: String, largeText: Bool = false) {
        app.launchArguments = ["-UITestInMemoryStore", "-UITestCoachFatigueFixture", "-UITestAppearance", appearance, "-appTheme", theme]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
    }

    private func openLibrary() {
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        let workoutTab = app.tabBars.buttons["Workout"]
        XCTAssertTrue(workoutTab.waitForExistence(timeout: 5))
        workoutTab.tap()
        let workoutScreen = app.descendants(matching: .any)["workout-screen"].firstMatch
        // The launch transition can consume the first tab tap. Confirm arrival before scrolling.
        if !workoutScreen.waitForExistence(timeout: 3) { workoutTab.tap() }
        XCTAssertTrue(workoutScreen.waitForExistence(timeout: 5))
        tap("workout-tool-exercise-library")
        XCTAssertTrue(app.navigationBars["Exercise Library"].waitForExistence(timeout: 5))
    }

    private func openGuide() {
        openLibrary()
        tap("exercise-library-guide")
        XCTAssertTrue(app.navigationBars["Exercise Guide"].waitForExistence(timeout: 5))
    }

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        reveal(element)
        element.tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.waitForExistence(timeout: 1) {
                let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.windows.firstMatch.frame.minY
                let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.windows.firstMatch.frame.maxY
                if element.isHittable, element.frame.midY > top + 8, element.frame.midY < bottom - 8 { return }
                if element.frame.midY <= top + 8 {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                        .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)))
                    continue
                }
            }
            app.swipeUp()
        }
        XCTFail("Could not reveal \(element)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
