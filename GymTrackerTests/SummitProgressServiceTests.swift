import XCTest
@testable import GymTracker

final class SummitProgressServiceTests: XCTestCase {
    func testPushSetsConvertVolumeToRoundedMetres() {
        let sets = (0..<18).map { _ in set(pattern: .push, weightKg: 60, reps: 8) }

        XCTAssertEqual(SummitProgressService.metres(for: sets, bodyweightKg: 80), 49)
    }

    func testBodyweightPullupsIncludeBodyweightAndAddedLoad() {
        let bodyweightOnly = [set(pattern: .pull, isBodyweight: true, reps: 8)]
        let withAddedLoad = [set(pattern: .pull, isBodyweight: true, weightKg: 20, reps: 8)]

        XCTAssertEqual(SummitProgressService.metres(for: bodyweightOnly, bodyweightKg: 80), 4)
        XCTAssertEqual(SummitProgressService.metres(for: withAddedLoad, bodyweightKg: 80), 6)
    }

    func testAltitudePassesMontBlancAtExactBoundary() {
        let altitude = SummitProgressService.altitude(totalMetres: 4_808, gainedToday: 20)

        XCTAssertTrue(altitude.passed.contains { $0.id == "mont-blanc" })
        XCTAssertEqual(altitude.next?.id, "kilimanjaro")
        XCTAssertEqual(altitude.metresToNext, 1_087)
    }

    func testAltitudeGeneratesLapsBeyondEverest() {
        let altitude = SummitProgressService.altitude(totalMetres: 9_000, gainedToday: nil)

        XCTAssertEqual(altitude.next?.id, "everest-lap-2")
        XCTAssertEqual(altitude.next?.name, "Everest × 2")
        XCTAssertEqual(altitude.metresToNext, 8_698)
    }

    func testPassingSeveralPeaksReturnsTheHighest() {
        let peak = SummitProgressService.didPassPeak(before: 1_000, after: 4_000)

        XCTAssertEqual(peak?.id, "fuji")
    }

    func testExpeditionStartsAtMachameGate() {
        let progress = expedition(climbed: 0)

        XCTAssertEqual(progress.currentAltitude, 1_800)
        XCTAssertEqual(progress.reachedCampIDs, ["machame-gate"])
        XCTAssertEqual(progress.nextCamp?.id, "machame-camp")
        XCTAssertEqual(progress.remainingAscent, 4_765)
        XCTAssertNil(progress.estimatedSessionsLeft)
    }

    func testExpeditionProgressAtTwoThousandTwoHundredTwelveMetres() {
        let progress = expedition(climbed: 2_212)

        XCTAssertEqual(progress.currentAltitude, 4_012)
        XCTAssertEqual(progress.nextCamp?.id, "lava-tower")
        XCTAssertEqual(progress.metresToNextCamp, 618)
    }

    func testExpeditionPassesBarrancoAfterReachingLavaTower() {
        let progress = expedition(climbed: 2_830)

        XCTAssertEqual(progress.currentAltitude, 3_960)
        XCTAssertTrue(progress.reachedCampIDs.contains("lava-tower"))
        XCTAssertTrue(progress.reachedCampIDs.contains("barranco-camp"))
        XCTAssertEqual(progress.nextCamp?.id, "karanga-camp")
        XCTAssertEqual(progress.metresToNextCamp, 35)
    }

    func testExpeditionPastUhuruHasNoRemainingAscent() {
        let progress = expedition(climbed: 6_000)

        XCTAssertEqual(progress.currentAltitude, 5_895)
        XCTAssertNil(progress.nextCamp)
        XCTAssertNil(progress.metresToNextCamp)
        XCTAssertEqual(progress.remainingAscent, 0)
        XCTAssertTrue(progress.reachedCampIDs.contains("uhuru-peak"))
    }

    func testCairnCountsConsecutiveTwoSessionWeeks() {
        let now = date(2026, 9, 23)
        let state = SummitProgressService.cairn(
            sessionDates: [date(2026, 9, 7), date(2026, 9, 9), date(2026, 9, 14), date(2026, 9, 16)],
            now: now,
            calendar: calendar(firstWeekday: 1)
        )

        XCTAssertEqual(state.stones, 2)
        XCTAssertEqual(state.recentWeeks.suffix(2).map(\.climbs), [2, 0])
    }

    func testCairnTurnsAStreakIntoAPastCairnAfterAnEmptyWeek() {
        let state = SummitProgressService.cairn(
            sessionDates: [date(2026, 9, 7), date(2026, 9, 9), date(2026, 9, 21), date(2026, 9, 23)],
            now: date(2026, 9, 30),
            calendar: calendar()
        )

        XCTAssertEqual(state.stones, 1)
        XCTAssertEqual(state.pastCairns.first?.height, 1)
        XCTAssertEqual(state.pastCairns.first?.endedWeek, calendar().startOfDay(for: date(2026, 9, 7)))
    }

    func testOneSessionInCurrentWeekDoesNotBreakCompletedStreak() {
        let state = SummitProgressService.cairn(
            sessionDates: [date(2026, 9, 14), date(2026, 9, 16), date(2026, 9, 22)],
            now: date(2026, 9, 23),
            calendar: calendar()
        )

        XCTAssertEqual(state.climbsThisWeek, 1)
        XCTAssertEqual(state.climbsNeeded, 2)
        XCTAssertEqual(state.stones, 1)
    }

    func testCairnUsesMondayAsTheWeekBoundary() {
        let state = SummitProgressService.cairn(
            sessionDates: [date(2026, 9, 20), date(2026, 9, 21), date(2026, 9, 22)],
            now: date(2026, 9, 22),
            calendar: calendar(firstWeekday: 1)
        )

        XCTAssertEqual(state.climbsThisWeek, 2)
        XCTAssertEqual(state.stones, 1)
    }

    func testCairnFreshnessTracksTheSessionThatQualifiesTheNewestStone() {
        let state = SummitProgressService.cairn(
            sessionDates: [date(2026, 9, 21), date(2026, 9, 22)],
            now: date(2026, 9, 23),
            calendar: calendar()
        )

        XCTAssertTrue(state.newestIsFresh)
    }

    func testRoutePlanCoversEveryReadinessCategory() {
        XCTAssertEqual(SummitProgressService.routePlan(category: .peak, plannedTitle: "Push"), .planned)
        XCTAssertEqual(SummitProgressService.routePlan(category: .ready, plannedTitle: "Push"), .planned)
        XCTAssertEqual(
            SummitProgressService.routePlan(category: .cautious, plannedTitle: "Push"),
            .steady(note: "Train as planned, skip the max attempts.")
        )
        XCTAssertEqual(
            SummitProgressService.routePlan(category: .low, plannedTitle: "Push"),
            .steady(note: "Trim volume and keep effort moderate.")
        )
        XCTAssertEqual(
            SummitProgressService.routePlan(category: .recovery, plannedTitle: nil),
            .lowerRoute(
                plannedTitle: "Planned session",
                alternative: SummitLowerRoute(
                    title: "Mobility + zone 2 walk",
                    detail: "Hips and T-spine, then an easy 20 min walk",
                    minutes: 30
                )
            )
        )
    }

    func testAppIconsUnlockAtTheirExactThresholds() {
        XCTAssertEqual(SummitProgressService.unlockedAppIcons(totalMetres: 0), [.topo])
        XCTAssertEqual(SummitProgressService.unlockedAppIcons(totalMetres: 1_344), [.topo])
        XCTAssertEqual(SummitProgressService.unlockedAppIcons(totalMetres: 1_345), [.topo, .night])
        XCTAssertEqual(SummitProgressService.unlockedAppIcons(totalMetres: 4_808), [.topo, .night, .alpenglow])
        XCTAssertEqual(SummitProgressService.unlockedAppIcons(totalMetres: 8_849), SummitAppIcon.allCases)
    }

    private func set(
        pattern: MovementPattern,
        isBodyweight: Bool = false,
        weightKg: Double = 0,
        reps: Int
    ) -> SummitSetInput {
        SummitSetInput(
            exerciseID: UUID(),
            exerciseName: "Test",
            pattern: pattern,
            isBodyweight: isBodyweight,
            isCompound: true,
            weightKg: weightKg,
            reps: reps
        )
    }

    private func expedition(climbed: Int) -> ExpeditionProgress {
        SummitProgressService.expeditionProgress(
            route: SummitCatalog.machame,
            startDate: date(2026, 8, 1),
            climbedSinceStart: climbed,
            recentSessionMetres: [100, 120, 140]
        )
    }

    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
