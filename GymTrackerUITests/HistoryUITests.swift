import XCTest

final class HistoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemoryStore",
            "-UITestLargeHistoryFixture",
            "-PerformanceAcceptanceMode"
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

    func testHistoryShowsSummitRidgeAndRowLines() throws {
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10))
        // Give Today's post-reveal Summit refresh time to publish.
        RunLoop.current.run(until: Date().addingTimeInterval(6))

        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history-summit-month"].waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        attachScreenshot(named: "history-summit-top")

        let firstRow = firstSessionRow()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        scrollIntoHittableRegion(firstRow)
        XCTAssertTrue(
            firstRow.label.contains("Climbed") || firstRow.label.contains("metres"),
            "Expected History rows to carry the Summit line: \(firstRow.label)"
        )
        attachScreenshot(named: "history-summit-rows")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    /// History must stay mounted and interactive when the tab is left and
    /// re-entered, and a fast fling must not leave it suspended while a source
    /// refresh is pending.
    func testHistoryStaysMountedAndInteractiveAcrossTabReentry() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 10),
            "Expected Today to be ready after launch"
        )

        tapTab(at: 3, expectedTitle: "History")
        let calendarCard = app.descendants(matching: .any)["history-calendar-card"]
        let overviewCard = app.descendants(matching: .any)["history-overview-card"]
        XCTAssertTrue(calendarCard.waitForExistence(timeout: 10))
        XCTAssertTrue(overviewCard.waitForExistence(timeout: 5))

        let monthTitle = app.staticTexts["history-selected-month-title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        let previousMonth = app.buttons["Previous month"]
        XCTAssertTrue(previousMonth.waitForExistence(timeout: 5))
        previousMonth.tap()
        let selectedMonth = monthTitle.label

        // Leaving and returning must keep the calendar mounted instead of
        // tearing it down and reinserting it behind a delay, and must keep the
        // selected month.
        tapTab(at: 0, expectedTitle: "Today")
        tapTab(at: 3, expectedTitle: "History")
        XCTAssertTrue(
            calendarCard.waitForExistence(timeout: 5),
            "Expected the History calendar to stay mounted across tab re-entry"
        )
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            monthTitle.label,
            selectedMonth,
            "Expected the selected month to survive tab re-entry"
        )

        // Fling while the re-entry refresh is still pending. Protected scrolling
        // defers the rebuild instead of competing with deceleration, and the list
        // must be usable once it settles.
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 5))

        scrollToHistoryTop(previousMonth)
        XCTAssertTrue(previousMonth.isHittable, "Expected History to settle at the top after a fast fling")

        let settledRow = firstSessionRow()
        XCTAssertTrue(settledRow.waitForExistence(timeout: 8), "Expected History rows after the fling settled")
        scrollIntoHittableRegion(settledRow)
        XCTAssertTrue(settledRow.isHittable, "Expected a History row to be tappable after the fling settled")

        // The in-app acceptance summary is the reliable channel for the History
        // scroll instrumentation: app-side print output is not captured in
        // `xcodebuild test` logs. Attachment proves the observer bound to the
        // real History scroll view, and the summary fails if a display snapshot
        // was rebuilt while History was scrolling or decelerating.
        let summaryRoot = app.descendants(matching: .any)["startup-critical-ready"]
        XCTAssertTrue(
            summaryRoot.waitForExistence(timeout: 5),
            "Expected the Debug acceptance summary to stay mounted for the History journey"
        )
        var summary = summaryRoot.value as? String ?? ""
        let attachmentDeadline = Date().addingTimeInterval(5)
        while historyScrollObserverAttachments(in: summary) < 1, Date() < attachmentDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            summary = summaryRoot.value as? String ?? ""
        }
        print("PERF_ACCEPTANCE_UI_SUMMARY \(summary)")
        XCTAssertGreaterThanOrEqual(
            historyScrollObserverAttachments(in: summary),
            1,
            "Expected the History scroll observer to attach; got \(summary)"
        )
        XCTAssertFalse(
            summary.contains("history.display_snapshot"),
            "Expected no History display snapshot rebuild during scrolling; got \(summary)"
        )

        settledRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["history-detail-hero"].waitForExistence(timeout: 8),
            "Expected a settled History row to open the workout detail"
        )
        tapBackButton()
        XCTAssertTrue(app.descendants(matching: .any)["history-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            firstSessionRow().waitForExistence(timeout: 5),
            "Expected History rows to remain available after closing a workout"
        )
    }

    private func tapTab(at index: Int, expectedTitle: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Expected tab bar to exist")
        let namedTab = tabBar.buttons[expectedTitle]
        let tab = namedTab.exists ? namedTab : tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Expected tab \(index) to exist")
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[rootScreenIdentifier(for: expectedTitle)]
                .waitForExistence(timeout: 8),
            "Expected \(expectedTitle) tab to be visible"
        )
    }

    private func rootScreenIdentifier(for title: String) -> String {
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
            return title
        }
    }

    private func firstSessionRow() -> XCUIElement {
        app.buttons.matching(identifier: "history-session-row").firstMatch
    }

    private func historyScrollObserverAttachments(in summary: String) -> Int {
        let field = summary
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("historyScrollObserverAttachments=") }
        guard let field else { return 0 }
        return Int(field.replacingOccurrences(of: "historyScrollObserverAttachments=", with: "")) ?? 0
    }

    private func scrollIntoHittableRegion(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while element.exists && !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func scrollToHistoryTop(_ element: XCUIElement, maxSwipes: Int = 12) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeDown(velocity: .fast)
            swipes += 1
        }
    }

    private func tapBackButton() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }
}
