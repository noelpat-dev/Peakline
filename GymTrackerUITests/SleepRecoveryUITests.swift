import XCTest

final class SleepRecoveryUITests: XCTestCase {
    private var app: XCUIApplication!

    private enum TapPointPosition {
        case aboveSafeBand
        case insideSafeBand
        case belowSafeBand
    }

    private enum VerticalNudgeDirection: Equatable {
        case up
        case down
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testQuickActionSleepRouteUsesOneNativeBack() throws {
        launch()
        openSleep()

        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].exists)
        tapNativeBack()
        XCTAssertTrue(waitForToday(), "One native back should return from Sleep to Today")
    }

    func testNoDataFirstFrameShowsTrackingCTAAndNeverPushesProgression() throws {
        launch()
        openSleep()

        XCTAssertTrue(waitForIdentifier("sleep-no-data-hero"), "The first Sleep dashboard state should be the no-data hero")
        XCTAssertTrue(waitForText("No sleep tracked yet"))
        XCTAssertTrue(waitForIdentifier("sleep-start-mode"))
        XCTAssertTrue(waitForIdentifier("sleep-add-manual"))
        XCTAssertTrue(waitForIdentifier("sleep-log-nap"))
        XCTAssertFalse(textContaining("Push progression").exists)
        XCTAssertFalse(app.descendants(matching: .any)["sleep-populated-hero"].exists)
    }

    func testStaleHistoryIsNotPresentedAsLastNightAndRemainsReachable() throws {
        launch(arguments: ["-UITestSleepStaleFixture"])

        openSleep()

        XCTAssertTrue(waitForIdentifier("sleep-no-overnight-hero"))
        XCTAssertTrue(waitForText("No sleep recorded last night"))
        XCTAssertFalse(app.descendants(matching: .any)["sleep-populated-hero"].exists)
        XCTAssertFalse(waitForText("Last night's sleep", timeout: 0.5))
        XCTAssertTrue(waitForIdentifier("sleep-start-mode"))
        XCTAssertTrue(waitForIdentifier("sleep-add-manual"))
        XCTAssertTrue(waitForIdentifier("sleep-log-nap"))
        XCTAssertTrue(waitForText("7h 50m", maxSwipes: 12), "The older session should remain visible in History")

        tapAction(identifier: "sleep-add-manual", maxSwipes: 12)
        XCTAssertTrue(waitForNavigationTitle("Add Sleep"))
    }

    func testPopulatedFixtureShowsTrendsSourcesReadinessHistoryAndEditableScoreParity() throws {
        launch(arguments: ["-UITestSleepPopulatedFixture"])
        openSleep()

        XCTAssertTrue(waitForIdentifier("sleep-populated-hero"))
        XCTAssertTrue(waitForIdentifier("sleep-last-night-duration"))
        XCTAssertTrue(waitForText("6h 30m"), "The latest fixture night should be a stable 390-minute session")
        XCTAssertTrue(waitForIdentifier("sleep-readiness-support"))
        XCTAssertTrue(waitForText("Provisional readiness"))
        XCTAssertTrue(waitForText("Missing signals do not lower your score."))
        XCTAssertFalse(textContaining("Push progression").exists)
        XCTAssertFalse(textContaining("Train normally").exists)
        XCTAssertFalse(textContaining("Recovery focus").exists)

        XCTAssertTrue(waitForText("Last 7 Days"))
        XCTAssertTrue(waitForText("Recovery Trends"))
        XCTAssertTrue(waitForText("Sleep Debt"))
        XCTAssertTrue(waitForText("Consistency"))
        XCTAssertTrue(waitForText("Naps"))
        XCTAssertTrue(waitForText("Manual", maxSwipes: 12))
        XCTAssertTrue(waitForText("Sleep Mode Estimate", maxSwipes: 12))
        XCTAssertTrue(waitForText("Apple Health", maxSwipes: 12))

        guard let latestManualRow = revealHistoryRow(containing: ["Manual", "6h 30m"]) else {
            return XCTFail("Expected the latest manual fixture row")
        }
        let initialHistoryScore = score(from: latestManualRow.label)
        XCTAssertNotNil(initialHistoryScore, "The history row should expose its quality score")
        latestManualRow.tap()

        XCTAssertTrue(waitForNavigationTitle("Sleep Detail"))
        XCTAssertTrue(waitForText("Session quality: \(initialHistoryScore ?? -1)"))
        XCTAssertTrue(waitForText("Manual"))

        tapAction(identifier: "sleep-detail-edit", maxSwipes: 10)
        XCTAssertTrue(waitForNavigationTitle("Edit Sleep"))
        tapAction(identifier: "sleep-editor-quality", maxSwipes: 8)
        tapAction(labels: ["Excellent"], maxSwipes: 4)
        tapAction(identifier: "sleep-editor-save", maxSwipes: 10)

        XCTAssertTrue(waitForNavigationTitle("Sleep Detail"))
        let editedDetailElement = textContaining("Session quality:")
        XCTAssertTrue(editedDetailElement.waitForExistence(timeout: 5))
        let editedDetailScore = score(from: editedDetailElement.label)
        XCTAssertNotNil(editedDetailScore, "The edited detail should expose its quality score")
        XCTAssertNotEqual(editedDetailScore, initialHistoryScore, "Changing quality should update the detail score")

        tapNativeBack()
        XCTAssertTrue(waitForSleep())
        guard let editedHistoryRow = revealHistoryRow(containing: ["Manual", "6h 30m"]) else {
            return XCTFail("Expected the edited manual fixture row")
        }
        let editedHistoryScore = score(from: editedHistoryRow.label)
        XCTAssertTrue(editedHistoryRow.isHittable)
        editedHistoryRow.tap()
        XCTAssertTrue(waitForNavigationTitle("Sleep Detail"))
        XCTAssertNotNil(editedHistoryScore)
        XCTAssertTrue(waitForText("Session quality: \(editedHistoryScore ?? -1)"), "History and detail should use the same scoring inputs")
    }

    func testActiveFixtureCanConfirmWithoutAutomaticMorningSheet() throws {
        launch(arguments: ["-UITestSleepActiveFixture"])
        openSleep()

        XCTAssertTrue(waitForIdentifier("sleep-active-hero"))
        XCTAssertTrue(waitForText("Sleep Mode Active"))
        XCTAssertFalse(waitForNavigationTitle("Good morning"), "A 90-minute active session must remain below the four-hour morning-confirmation threshold")

        tapAction(identifier: "sleep-active-confirm", maxSwipes: 8)
        XCTAssertTrue(waitForNavigationTitle("Good morning"))
        tapAction(identifier: "sleep-morning-confirm", maxSwipes: 10)

        XCTAssertTrue(waitForIdentifierGone("sleep-active-hero", timeout: 8))
        XCTAssertTrue(waitForText("Last night's sleep"))
    }

    func testActiveFixtureDiscardRequiresConfirmationAndRemovesSession() throws {
        launch(arguments: ["-UITestSleepActiveFixture"])
        openSleep()

        tapAction(identifier: "sleep-active-discard", maxSwipes: 8)
        XCTAssertTrue(waitForAlert("Discard active sleep?"))
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertTrue(waitForIdentifier("sleep-active-hero"))

        tapAction(identifier: "sleep-active-discard", maxSwipes: 8)
        XCTAssertTrue(waitForAlert("Discard active sleep?"))
        app.alerts.firstMatch.buttons["Discard"].tap()
        XCTAssertTrue(waitForIdentifierGone("sleep-active-hero", timeout: 8))
        XCTAssertTrue(waitForIdentifier("sleep-no-data-hero"))
    }

    func testMorningFixturePresentsDestructiveDiscardConfirmation() throws {
        launch(arguments: ["-UITestSleepMorningFixture"])
        openSleep()

        XCTAssertTrue(waitForNavigationTitle("Good morning"))
        tapAction(identifier: "sleep-morning-discard", maxSwipes: 10)

        XCTAssertTrue(
            waitForAlertAny(["Discard this sleep session?", "Discard sleep session?"]),
            "Morning discard should ask for destructive confirmation"
        )
        tapAlertButton(named: ["Keep Session", "Cancel"])
        XCTAssertTrue(waitForNavigationTitle("Good morning"))

        tapAction(identifier: "sleep-morning-discard", maxSwipes: 10)
        XCTAssertTrue(waitForAlertAny(["Discard this sleep session?", "Discard sleep session?"]))
        tapAlertButton(named: ["Discard"])
        XCTAssertTrue(waitForIdentifierGone("sleep-active-hero", timeout: 8))
    }

    func testManualSleepEntryShowsEditorAndSavesValidSession() throws {
        launch()
        openSleep()

        tapAction(identifier: "sleep-add-manual", maxSwipes: 8)
        XCTAssertTrue(waitForNavigationTitle("Add Sleep"))
        XCTAssertTrue(waitForText("Duration"))
        XCTAssertTrue(waitForText("Sleep start"))
        XCTAssertTrue(waitForText("Wake time"))

        // The editor starts with a valid eight-hour range. Repository-level
        // tests cover invalid dates without depending on locale-specific
        // date-picker wheel ordering.
        tapAction(identifier: "sleep-editor-save", maxSwipes: 10)
        XCTAssertTrue(waitForIdentifierGone("sleep-add-manual", timeout: 8))
        XCTAssertTrue(waitForIdentifier("sleep-populated-hero"))
        XCTAssertTrue(waitForText("Manual"))
    }

    func testInvalidManualSleepEntryKeepsEditorOpenAndShowsValidationError() throws {
        launch(arguments: ["-UITestSleepInvalidEditorFixture"])
        openSleep()

        tapAction(identifier: "sleep-add-manual", maxSwipes: 8)
        XCTAssertTrue(waitForNavigationTitle("Add Sleep"))
        XCTAssertTrue(waitForIdentifier("sleep-editor-start"))
        XCTAssertTrue(waitForIdentifier("sleep-editor-wake"))

        tapAction(identifier: "sleep-editor-save", maxSwipes: 10)

        let editorError = app.descendants(matching: .any)["sleep-editor-error"]
        XCTAssertTrue(editorError.waitForExistence(timeout: 5))
        XCTAssertEqual(editorError.label, "Wake time must be after sleep start.")
        XCTAssertTrue(waitForNavigationTitle("Add Sleep"), "Validation must keep the manual editor open")
        XCTAssertTrue(app.descendants(matching: .any)["sleep-editor-save"].exists)
    }

    func testNapTimerStartsProgressesClosesAndRejectsUnderMinimumWithoutSaving() throws {
        launch(arguments: ["-UITestSleepPopulatedFixture"])
        openSleep()

        tapAction(identifier: "sleep-nap-timer", maxSwipes: 10)
        XCTAssertTrue(waitForNavigationTitle("Nap Timer"))
        XCTAssertTrue(waitForText("30:00"))

        tapAction(identifier: "sleep-nap-timer-primary", maxSwipes: 10)
        XCTAssertTrue(waitForText("Nap in progress"))
        let runningTimer = napTimerValue()
        XCTAssertTrue(runningTimer.waitForExistence(timeout: 3))
        let initialTimerLabel = runningTimer.label
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertNotEqual(runningTimer.label, initialTimerLabel, "The nap timer should derive its display from elapsed date time")

        tapAction(identifier: "sleep-nap-timer-close", maxSwipes: 4)
        XCTAssertTrue(
            waitForAlertAny(["Discard nap timer?", "Close nap timer?"], timeout: 2),
            "Closing an active nap timer must require confirmation"
        )
        tapAlertButton(named: ["Keep Timer", "Cancel"])
        tapAction(identifier: "sleep-nap-timer-close", maxSwipes: 4)
        XCTAssertTrue(waitForAlertAny(["Discard nap timer?", "Close nap timer?"]))
        tapAlertButton(named: ["Discard", "Close"])
        XCTAssertTrue(waitForSleep())

        tapAction(identifier: "sleep-nap-timer", maxSwipes: 10)
        XCTAssertTrue(waitForNavigationTitle("Nap Timer"))
        tapAction(identifier: "sleep-nap-timer-primary", maxSwipes: 10)
        let rejectionTimer = napTimerValue()
        XCTAssertTrue(rejectionTimer.waitForExistence(timeout: 3), "Expected a visible timer value before the under-minimum finish")
        XCTAssertTrue(rejectionTimer.label.hasPrefix("0:"), "The rejection case must start from now, got \(rejectionTimer.label)")
        tapAction(identifier: "sleep-nap-timer-primary", maxSwipes: 10)

        XCTAssertTrue(waitForNavigationTitle("Nap Timer"))
        let napTimerError = textContaining("Keep the timer running for at least 10 minutes before saving a nap.")
        XCTAssertTrue(napTimerError.waitForExistence(timeout: 0.75), "The under-minimum error should be visible immediately after Finish")
        XCTAssertEqual(napTimerError.identifier, "sleep-nap-timer-error")
        XCTAssertTrue(app.descendants(matching: .any)["sleep-nap-timer-primary"].label.contains("Finish Nap"))

        tapAction(identifier: "sleep-nap-timer-close", maxSwipes: 4)
        XCTAssertTrue(
            waitForAlertAny(["Discard nap timer?", "Close nap timer?"], timeout: 2),
            "Closing after an under-minimum nap rejection must require confirmation"
        )
        tapAlertButton(named: ["Discard", "Close"])
        XCTAssertTrue(waitForSleep())
    }

    func testNapTimerElapsedFixtureShowsCompletedDoneAndPersistsNapTimerSourceAndDuration() throws {
        launch(arguments: ["-UITestSleepPopulatedFixture", "-UITestNapElapsedFixture"])
        openSleep()

        tapAction(identifier: "sleep-nap-timer", maxSwipes: 12)
        XCTAssertTrue(waitForNavigationTitle("Nap Timer"))
        tapAction(identifier: "sleep-nap-timer-primary", maxSwipes: 10)
        XCTAssertTrue(waitForText("Nap in progress") || waitForText("Target reached"))

        tapAction(identifier: "sleep-nap-timer-primary", maxSwipes: 10)
        XCTAssertTrue(waitForText("Nap saved"))
        let completedPrimary = app.descendants(matching: .any)["sleep-nap-timer-primary"]
        XCTAssertTrue(completedPrimary.waitForExistence(timeout: 5))
        XCTAssertTrue(completedPrimary.label.contains("Done"), "A successful finish must expose the completed Done action")

        completedPrimary.tap()
        XCTAssertTrue(waitForSleep())
        XCTAssertTrue(
            waitForElement(containing: ["11m", "Nap Timer"], maxSwipes: 12),
            "The saved nap must retain its Nap Timer source and date-derived 11-minute duration"
        )
    }

    func testSleepSettingsAdaptsSourceLabelsAndTruthfullyReportsHealthKit() throws {
        launch()
        openSleep()

        tapAction(identifier: "sleep-settings-button", maxSwipes: 4)
        XCTAssertTrue(waitForNavigationTitle("Sleep Settings"))
        XCTAssertTrue(waitForText("Preferred Sleep Source"))

        tapAction(identifier: "sleep-settings-preferred-source", maxSwipes: 10)
        XCTAssertTrue(waitForText("Automatic"))
        XCTAssertTrue(waitForText("Apple Health"))
        XCTAssertTrue(waitForText("Sleep Mode"))
        XCTAssertTrue(waitForText("Manual"))
        tapAction(labels: ["Automatic"], maxSwipes: 4)

        let unavailable = textContaining("Apple Health unavailable")
        let available = textContaining("Apple Health sleep access")
        XCTAssertTrue(
            unavailable.waitForExistence(timeout: 3) || available.waitForExistence(timeout: 3),
            "Settings must report the actual Apple Health availability state"
        )

        if unavailable.exists {
            XCTAssertTrue(waitForText("This device does not support HealthKit sleep access."))
            let connect = buttonContaining("Apple Health Unavailable")
            XCTAssertTrue(connect.waitForExistence(timeout: 3))
            XCTAssertFalse(connect.isEnabled, "The unavailable HealthKit state must not offer an actionable connect button")

            let importToggle = toggleContaining("Apple Health import")
            XCTAssertTrue(importToggle.waitForExistence(timeout: 3))
            XCTAssertFalse(importToggle.isEnabled)
            let exportToggle = toggleContaining("Save Sleep to Apple Health")
            XCTAssertTrue(exportToggle.waitForExistence(timeout: 3))
            XCTAssertFalse(exportToggle.isEnabled)
        } else {
            XCTAssertTrue(available.exists)
            let connect = buttonContaining("Request Sleep Access")
            XCTAssertTrue(connect.waitForExistence(timeout: 3))
            XCTAssertTrue(connect.isEnabled)
            let importToggle = toggleContaining("Apple Health import")
            XCTAssertTrue(importToggle.waitForExistence(timeout: 3))
            XCTAssertTrue(importToggle.isEnabled)
            let exportToggle = toggleContaining("Save Sleep to Apple Health")
            XCTAssertTrue(exportToggle.waitForExistence(timeout: 3))
            XCTAssertTrue(exportToggle.isEnabled)
        }

        tapAction(identifier: "sleep-settings-done", maxSwipes: 12)
        XCTAssertTrue(waitForSleep())
    }

    private func launch(arguments: [String] = []) {
        app.launchArguments = ["-UITestInMemoryStore", "-UITestSleepUI"] + arguments
        app.launch()
        XCTAssertTrue(waitForStartupReady(), "Expected startup-critical-ready after launch")
        XCTAssertTrue(waitForToday(), "Expected the app to settle on a hittable Today screen")
    }

    private func openSleep() {
        XCTAssertTrue(waitForToday(), "Expected a hittable Today screen before opening Sleep")
        tapAction(identifier: "quick-action-sleep", maxSwipes: 8)
        XCTAssertTrue(waitForSleep(), "Expected Today quick action to open Sleep")
    }

    @discardableResult
    private func waitForStartupReady(timeout: TimeInterval = 12) -> Bool {
        let criticalReady = app.descendants(matching: .any)["startup-critical-ready"]
        guard criticalReady.waitForExistence(timeout: timeout) else { return false }

        let splash = app.descendants(matching: .any)["startup-brand-screen"]
        guard splash.waitForNonExistence(timeout: 3) else { return false }
        return waitForHittable(criticalReady, timeout: timeout)
    }

    @discardableResult
    private func waitForToday(timeout: TimeInterval = 12) -> Bool {
        let todayScreen = app.descendants(matching: .any)["today-screen"]
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if todayScreen.exists && todayScreen.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return todayScreen.exists && todayScreen.isHittable
    }

    @discardableResult
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return element.exists && element.isHittable
    }

    @discardableResult
    private func waitForSleep(timeout: TimeInterval = 12) -> Bool {
        app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: timeout)
            || app.navigationBars["Sleep"].waitForExistence(timeout: timeout)
    }

    @discardableResult
    private func waitForNavigationTitle(_ title: String, timeout: TimeInterval = 8) -> Bool {
        app.navigationBars[title].waitForExistence(timeout: timeout)
            || app.staticTexts[title].waitForExistence(timeout: timeout)
    }

    @discardableResult
    private func waitForIdentifier(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }

    @discardableResult
    private func waitForIdentifierGone(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        app.descendants(matching: .any)[identifier].waitForNonExistence(timeout: timeout)
    }

    @discardableResult
    private func waitForText(_ value: String, maxSwipes: Int = 0, timeout: TimeInterval = 5) -> Bool {
        var swipes = 0
        while swipes <= maxSwipes {
            let match = textContaining(value)
            if match.waitForExistence(timeout: timeout / Double(max(1, maxSwipes + 1))) {
                return true
            }
            guard swipes < maxSwipes else { break }
            app.swipeUp()
            swipes += 1
        }
        return false
    }

    @discardableResult
    private func waitForAlert(_ title: String, timeout: TimeInterval = 5) -> Bool {
        app.alerts[title].waitForExistence(timeout: timeout)
            || (app.alerts.firstMatch.waitForExistence(timeout: timeout) && textContaining(title).exists)
    }

    @discardableResult
    private func waitForAlertAny(_ titles: [String], timeout: TimeInterval = 5) -> Bool {
        titles.contains { waitForAlert($0, timeout: timeout / Double(max(1, titles.count))) }
    }

    private func tapAlertButton(named names: [String]) {
        let alert = app.alerts.firstMatch
        for name in names {
            let button = alert.buttons[name]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }
        XCTFail("Expected alert button \(names.joined(separator: " / "))")
    }

    private func tapNativeBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Expected a native navigation back button")
        back.tap()
    }

    private func tapAction(identifier: String? = nil, labels: [String] = [], maxSwipes: Int) {
        var swipes = 0
        while swipes <= maxSwipes {
            if let action = hittableElement(identifier: identifier, labels: labels) {
                switch tapPointPosition(for: action) {
                case .insideSafeBand:
                    action
                        .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        .tap()
                    return
                case .aboveSafeBand:
                    guard swipes < maxSwipes else { break }
                    nudgeScroll(direction: .down)
                    swipes += 1
                    continue
                case .belowSafeBand:
                    guard swipes < maxSwipes else { break }
                    nudgeScroll(direction: .up)
                    swipes += 1
                    continue
                }
            }
            guard swipes < maxSwipes else { break }
            nudgeScroll(direction: .up)
            swipes += 1
        }

        let name = identifier ?? labels.joined(separator: " / ")
        XCTFail("Expected tappable Sleep UI action \(name)")
    }

    private func hittableElement(identifier: String?, labels: [String]) -> XCUIElement? {
        if let identifier {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            return element.exists && element.isHittable ? element : nil
        }

        for label in labels {
            let button = app.buttons[label]
            if button.exists && button.isHittable { return button }
        }
        return nil
    }

    private func tapPointPosition(for element: XCUIElement) -> TapPointPosition {
        if isNavigationBarControl(element) {
            return .insideSafeBand
        }

        let safeBand = safeVerticalBand()
        let tapPoint = CGPoint(x: element.frame.midX, y: element.frame.midY)
        if tapPoint.y < safeBand.top {
            return .aboveSafeBand
        }
        if tapPoint.y > safeBand.bottom {
            return .belowSafeBand
        }
        return .insideSafeBand
    }

    private func safeVerticalBand() -> (top: CGFloat, bottom: CGFloat) {
        let windowFrame = app.windows.firstMatch.frame
        var safeTop = windowFrame.minY
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists {
            safeTop = navigationBar.frame.maxY + 8
        }

        var safeBottom = windowFrame.maxY
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.isHittable {
            // iOS 26's floating tab/dimming region begins above the
            // accessibility tab-bar frame. Keep synthesized center taps clear
            // of that overlay, not merely clear of the reported tab bar.
            let floatingTabExclusionMargin: CGFloat = 72
            safeBottom = min(
                safeBottom,
                tabBar.frame.minY - floatingTabExclusionMargin - 8
            )
        }

        return (safeTop, safeBottom)
    }

    private func nudgeScroll(direction: VerticalNudgeDirection) {
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let safeBand = safeVerticalBand()
        let scrollView = app.scrollViews.firstMatch

        var contentFrame = CGRect(
            x: windowFrame.minX + 16,
            y: safeBand.top,
            width: max(1, windowFrame.width - 32),
            height: max(1, safeBand.bottom - safeBand.top)
        )
        if scrollView.exists, scrollView.isHittable {
            contentFrame = contentFrame.intersection(scrollView.frame)
        }

        let availableTravel = contentFrame.height - 24
        guard contentFrame.width > 1, availableTravel > 1 else { return }

        let travel = min(110, availableTravel)
        let centerY = contentFrame.midY
        let startY = direction == .up ? centerY + travel / 2 : centerY - travel / 2
        let endY = direction == .up ? centerY - travel / 2 : centerY + travel / 2
        let startPoint = CGPoint(x: contentFrame.midX, y: startY)
        let endPoint = CGPoint(x: contentFrame.midX, y: endY)
        let start = window.coordinate(
            withNormalizedOffset: CGVector(
                dx: (startPoint.x - windowFrame.minX) / windowFrame.width,
                dy: (startPoint.y - windowFrame.minY) / windowFrame.height
            )
        )
        let end = window.coordinate(
            withNormalizedOffset: CGVector(
                dx: (endPoint.x - windowFrame.minX) / windowFrame.width,
                dy: (endPoint.y - windowFrame.minY) / windowFrame.height
            )
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func isNavigationBarControl(_ element: XCUIElement) -> Bool {
        let navigationBarButtons = app.navigationBars.buttons
        for index in 0..<navigationBarButtons.count {
            let button = navigationBarButtons.element(boundBy: index)
            guard button.exists else { continue }

            if !element.identifier.isEmpty, element.identifier == button.identifier {
                return true
            }
            if element.label == button.label, element.frame == button.frame {
                return true
            }
        }
        return false
    }

    private func historyRow(containing fragments: [String]) -> XCUIElement {
        var query = app.buttons
        for fragment in fragments {
            query = query.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
        }
        return query.firstMatch
    }

    private func revealHistoryRow(containing fragments: [String], maxSwipes: Int = 12) -> XCUIElement? {
        for _ in 0...maxSwipes {
            let row = historyRow(containing: fragments)
            if row.exists && row.isHittable {
                return row
            }
            app.swipeUp()
        }
        return nil
    }

    @discardableResult
    private func waitForElement(containing fragments: [String], maxSwipes: Int = 0, timeout: TimeInterval = 5) -> Bool {
        var swipes = 0
        while swipes <= maxSwipes {
            var query = app.descendants(matching: .any)
            for fragment in fragments {
                query = query.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
            }
            if query.firstMatch.waitForExistence(timeout: timeout / Double(max(1, maxSwipes + 1))) {
                return true
            }
            guard swipes < maxSwipes else { break }
            app.swipeUp()
            swipes += 1
        }
        return false
    }

    private func score(from label: String) -> Int? {
        let pattern = "Session quality\\s*:?[ \\t]+(\\d+)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label)
        else {
            return nil
        }
        return Int(label[range])
    }

    private func textContaining(_ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }

    private func napTimerValue() -> XCUIElement {
        app.staticTexts["sleep-nap-timer-value"]
    }

    private func buttonContaining(_ value: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }

    private func toggleContaining(_ value: String) -> XCUIElement {
        app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }
}
