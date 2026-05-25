import XCTest
@testable import GymTracker

@MainActor
final class SleepRecoveryReliabilityTests: XCTestCase {
    func testSleepScoreAndRecoveryStateBoundariesAreStable() {
        let service = SleepScoringService()

        XCTAssertEqual(service.durationScore(minutes: 480, targetMinutes: 480), 100)
        XCTAssertEqual(service.durationScore(minutes: 420, targetMinutes: 480), 85)
        XCTAssertEqual(service.durationScore(minutes: 360, targetMinutes: 480), 65)
        XCTAssertEqual(service.durationScore(minutes: 300, targetMinutes: 480), 45)
        XCTAssertEqual(service.durationScore(minutes: 240, targetMinutes: 480), 25)

        XCTAssertEqual(service.recoveryState(for: 85), .high)
        XCTAssertEqual(service.recoveryState(for: 70), .good)
        XCTAssertEqual(service.recoveryState(for: 55), .moderate)
        XCTAssertEqual(service.recoveryState(for: 40), .low)
        XCTAssertEqual(service.recoveryState(for: 39), .veryLow)
        XCTAssertEqual(service.recoveryState(for: nil), .unknown)

        XCTAssertEqual(service.confidenceScore(.high, source: .appleHealth), 90)
        XCTAssertEqual(service.confidenceScore(.estimatedConfirmed, source: .inAppTimer), 80)
        XCTAssertEqual(service.confidenceScore(.low, source: .manual), 45)
    }

    func testSleepScoreUsesConfidenceAndRecentConsistencyWithoutLeavingBounds() {
        let service = SleepScoringService()
        let session = sleepSession(day: 8, startHour: 23, durationMinutes: 480, quality: 5, confidence: .high, source: .appleHealth)
        let recent = [
            session,
            sleepSession(day: 7, startHour: 23, durationMinutes: 470, quality: 4, confidence: .high, source: .appleHealth),
            sleepSession(day: 6, startHour: 23, durationMinutes: 460, quality: 4, confidence: .high, source: .appleHealth)
        ]

        let strongScore = service.score(for: session, recentSessions: recent, settings: .default)
        XCTAssertGreaterThanOrEqual(strongScore, 90)
        XCTAssertLessThanOrEqual(strongScore, 100)

        let lowConfidenceShortSleep = sleepSession(day: 9, startHour: 2, durationMinutes: 240, quality: 1, confidence: .low, source: .manual)
        let lowScore = service.score(for: lowConfidenceShortSleep, recentSessions: [lowConfidenceShortSleep], settings: .default)
        XCTAssertLessThan(lowScore, 40)
        XCTAssertGreaterThanOrEqual(lowScore, 0)
    }

    func testNapCreditCapsRecoveryAndFlagsLateNaps() {
        let calendar = utcCalendar()
        let overnight = ResolvedSleepSession(
            id: UUID(),
            sleepDate: date(day: 8, hour: 0),
            startDate: date(day: 7, hour: 23),
            endDate: date(day: 8, hour: 4),
            asleepDuration: 5 * 3_600,
            inBedDuration: nil,
            qualityRating: 3,
            dataSource: .manual,
            confidence: .medium,
            appleHealthSummary: nil,
            appSessionID: UUID(),
            notes: nil,
            conflict: nil,
            stageBreakdown: nil
        )
        let naps = [
            nap(day: 8, startHour: 13, minutes: 30, timing: .earlyAfternoon),
            nap(day: 8, startHour: 19, minutes: 45, timing: .evening)
        ]

        let credit = NapRecoveryCalculator().calculateNapCredit(
            naps: naps,
            overnightSleep: overnight,
            sleepTarget: 8 * 3_600,
            calendar: calendar
        )

        XCTAssertGreaterThan(credit.totalCreditMinutes, 0)
        XCTAssertLessThanOrEqual(credit.cappedCreditMinutes, 90)
        XCTAssertTrue(credit.factors.contains(.napImprovedRecovery))
        XCTAssertTrue(credit.factors.contains(.lateNapMayAffectSleep))
    }

    func testRecoveryRecommendationBoundariesStayConservativeForLowScores() {
        let service = RecoveryCoachingRecommendationService()
        let lowRecovery = RecoveryScoreBreakdown(
            finalScore: 35,
            label: .veryLow,
            overnightSleepComponent: 25,
            sleepDebtComponent: 35,
            consistencyComponent: 45,
            qualityComponent: 20,
            napComponent: 0,
            trainingLoadComponent: nil,
            performanceTrendComponent: nil,
            confidence: .medium,
            contributingFactors: [.sleepDebtHigh, .sleptBelowTarget]
        )
        let recommendation = service.buildRecommendation(
            recovery: lowRecovery,
            plannedWorkout: WorkoutSession(splitNameSnapshot: "Legs - Full"),
            naps: []
        )

        XCTAssertEqual(recommendation.readiness, .recovery)
        XCTAssertTrue(recommendation.suggestedAdjustments.contains(.considerRest))
        XCTAssertEqual(recommendation.confidence, .medium)
    }

    private func sleepSession(
        day: Int,
        startHour: Int,
        durationMinutes: Int,
        quality: Int?,
        confidence: SleepConfidence,
        source: SleepSource
    ) -> SleepSession {
        let start = date(day: day, hour: startHour)
        let wake = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: wake,
            durationMinutes: durationMinutes,
            qualityRating: quality,
            source: source,
            confidence: confidence,
            status: .completed
        )
    }

    private func nap(day: Int, startHour: Int, minutes: Int, timing: NapTimingCategory) -> NapSession {
        let start = date(day: day, hour: startHour)
        return NapSession(
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
            qualityRating: 3,
            source: .manual,
            timingCategory: timing
        )
    }

    private func date(day: Int, hour: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
