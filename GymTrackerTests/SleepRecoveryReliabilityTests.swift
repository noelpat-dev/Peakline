import XCTest
import SwiftData
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

    func testSleepAnalyticsWarmSnapshotCarriesItsInputSignature() {
        let sessions = [sleepSession(day: 9, startHour: 23, durationMinutes: 480, quality: 4, confidence: .high, source: .manual)]
        let snapshot = SleepAnalyticsSnapshotStore.shared.snapshot(
            sessions: sessions,
            naps: [],
            workouts: [],
            settings: .default,
            force: true
        )

        XCTAssertEqual(
            snapshot.inputSignature,
            SleepAnalyticsInputSignature(sessions: sessions, naps: [], workouts: [], settings: .default)
        )
    }

    func testSleepAnalyticsCacheKeepsTwentyAndTwentyEightWorkoutProfilesDistinct() {
        let sessions = [sleepSession(day: 9, startHour: 23, durationMinutes: 480, quality: 4, confidence: .high, source: .manual)]
        let workouts = (0..<28).map { index in
            WorkoutSession(
                date: Date(timeIntervalSince1970: TimeInterval(2_000 + index)),
                splitNameSnapshot: "Push",
                durationMinutes: 60,
                completed: true
            )
        }
        let store = SleepAnalyticsSnapshotStore.shared
        let profile20 = store.snapshot(
            sessions: sessions,
            naps: [],
            workouts: Array(workouts.prefix(20)),
            settings: .default,
            sessionLimit: 90,
            workoutLimit: 20,
            force: true
        )
        let profile28 = store.snapshot(
            sessions: sessions,
            naps: [],
            workouts: workouts,
            settings: .default,
            sessionLimit: 90,
            workoutLimit: 28,
            force: true
        )
        guard let signature20 = profile20.inputSignature,
              let signature28 = profile28.inputSignature else {
            XCTFail("Expected both cache profiles to retain their input signatures")
            return
        }

        XCTAssertNotEqual(signature20, signature28)
        XCTAssertEqual(store.cachedAnalytics(matching: signature20)?.signature, signature20)
        XCTAssertEqual(store.cachedAnalytics(matching: signature28)?.signature, signature28)
        XCTAssertEqual(store.cachedAnalytics?.signature.workoutLimit, 28)
    }

    func testLastNightDoesNotPromoteAnOlderFridaySessionOnMonday() {
        let calendar = utcCalendar()
        let mondayNoon = date(day: 18, hour: 12)
        let fridaySession = sleepSession(
            day: 15,
            startHour: 23,
            durationMinutes: 480,
            quality: 4,
            confidence: .high,
            source: .manual
        )
        let scoring = SleepScoringService()

        let lastNight = scoring.latestSummary(
            from: [fridaySession],
            settings: .default,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertNil(lastNight.primarySession)
        XCTAssertEqual(lastNight.date, calendar.startOfDay(for: date(day: 17, hour: 12)))

        let notYetWokenSession = sleepSession(
            day: 17,
            startHour: 22,
            durationMinutes: 16 * 60,
            quality: 4,
            confidence: .high,
            source: .manual
        )
        let futureLastNight = scoring.latestSummary(
            from: [notYetWokenSession],
            settings: .default,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertNil(futureLastNight.primarySession)

        let summaries = scoring.summaries(
            from: [fridaySession],
            settings: .default,
            days: 7,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertEqual(
            summaries.first(where: { calendar.isDate($0.date, inSameDayAs: date(day: 15, hour: 12)) })?.primarySession?.id,
            fridaySession.id
        )

        let snapshot = SleepAnalyticsService().snapshot(
            sessions: [fridaySession],
            workouts: [],
            settings: .default,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertNil(snapshot.latestSummary.primarySession)
        XCTAssertEqual(snapshot.dashboardSummary.lastNightSession, nil)
        XCTAssertTrue(snapshot.summaries.contains { $0.primarySession?.id == fridaySession.id })
    }

    func testSundayNightSessionWakingMondayIsTheEvaluatedLastNight() {
        let calendar = utcCalendar()
        let mondayNoon = date(day: 18, hour: 12)
        let sundaySession = sleepSession(
            day: 17,
            startHour: 22,
            durationMinutes: 480,
            quality: 4,
            confidence: .high,
            source: .manual
        )
        let scoring = SleepScoringService()

        let lastNight = scoring.latestSummary(
            from: [sundaySession],
            settings: .default,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertEqual(lastNight.primarySession?.id, sundaySession.id)
        XCTAssertEqual(lastNight.date, calendar.startOfDay(for: date(day: 17, hour: 12)))

        let snapshot = SleepAnalyticsService().snapshot(
            sessions: [sundaySession],
            workouts: [],
            settings: .default,
            endingOn: mondayNoon,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.latestSummary.primarySession?.id, sundaySession.id)
        XCTAssertEqual(snapshot.dashboardSummary.lastNightSession?.id, sundaySession.id)
    }

    func testSleepAnalyticsSignatureInvalidatesAtFutureWakeBoundaryWithoutClockChurn() {
        let calendar = utcCalendar()
        let wake = date(day: 18, hour: 11)
        let futureCompletedSession = SleepSession(
            confirmedSleepStartAt: date(day: 18, hour: 2),
            wakeAt: wake,
            durationMinutes: 9 * 60,
            source: .manual,
            confidence: .medium,
            status: .completed
        )

        let beforeWake = SleepAnalyticsInputSignature(
            sessions: [futureCompletedSession],
            workouts: [],
            settings: .default,
            now: date(day: 18, hour: 9),
            calendar: calendar
        )
        let sameDayBeforeWake = SleepAnalyticsInputSignature(
            sessions: [futureCompletedSession],
            workouts: [],
            settings: .default,
            now: date(day: 18, hour: 9).addingTimeInterval(30 * 60),
            calendar: calendar
        )
        let afterWake = SleepAnalyticsInputSignature(
            sessions: [futureCompletedSession],
            workouts: [],
            settings: .default,
            now: wake.addingTimeInterval(1),
            calendar: calendar
        )

        XCTAssertEqual(beforeWake.nextSleepEligibilityBoundary, wake)
        XCTAssertEqual(beforeWake, sameDayBeforeWake)
        XCTAssertNil(afterWake.nextSleepEligibilityBoundary)
        XCTAssertNotEqual(beforeWake, afterWake)
    }

    func testSleepNotificationNightBucketsStayStableBeforeAndAfterNoon() {
        let calendar = utcCalendar()
        let sundaySession = sleepSession(day: 17, startHour: 22, durationMinutes: 480, quality: 4, confidence: .high, source: .manual)
        let mondaySession = sleepSession(day: 18, startHour: 13, durationMinutes: 120, quality: 4, confidence: .high, source: .manual)
        let scheduler = SleepNotificationScheduler()
        let sundaySnapshots = SleepNotificationScheduler.sessionSnapshots(from: [sundaySession])
        let mondaySnapshots = SleepNotificationScheduler.sessionSnapshots(from: [mondaySession])
        let beforeNoon = date(day: 18, hour: 9)
        let afterNoon = date(day: 18, hour: 15)

        XCTAssertTrue(scheduler.hasSessionForLastNight(sessions: sundaySnapshots, now: beforeNoon, calendar: calendar))
        XCTAssertTrue(scheduler.hasSessionForLastNight(sessions: sundaySnapshots, now: afterNoon, calendar: calendar))
        XCTAssertFalse(scheduler.hasSessionForLastNight(sessions: mondaySnapshots, now: beforeNoon, calendar: calendar))
        XCTAssertFalse(scheduler.hasSessionForLastNight(sessions: mondaySnapshots, now: afterNoon, calendar: calendar))

        XCTAssertFalse(scheduler.hasSessionForUpcomingNight(sessions: mondaySnapshots, now: beforeNoon, calendar: calendar))
        XCTAssertTrue(scheduler.hasSessionForUpcomingNight(sessions: mondaySnapshots, now: afterNoon, calendar: calendar))
        XCTAssertFalse(scheduler.hasSessionForUpcomingNight(sessions: sundaySnapshots, now: beforeNoon, calendar: calendar))
        XCTAssertFalse(scheduler.hasSessionForUpcomingNight(sessions: sundaySnapshots, now: afterNoon, calendar: calendar))
    }

    func testSleepNotificationPredicatesRejectCompletedFutureWakes() {
        let calendar = utcCalendar()
        let scheduler = SleepNotificationScheduler()
        let lastNightSession = SleepSession(
            confirmedSleepStartAt: date(day: 17, hour: 22),
            wakeAt: date(day: 18, hour: 8),
            durationMinutes: 600,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        let lastNightSnapshots = SleepNotificationScheduler.sessionSnapshots(from: [lastNightSession])

        XCTAssertFalse(
            scheduler.hasSessionForLastNight(
                sessions: lastNightSnapshots,
                now: date(day: 18, hour: 7),
                calendar: calendar
            )
        )
        XCTAssertTrue(
            scheduler.hasSessionForLastNight(
                sessions: lastNightSnapshots,
                now: date(day: 18, hour: 8),
                calendar: calendar
            )
        )

        let upcomingNightSession = SleepSession(
            confirmedSleepStartAt: date(day: 18, hour: 22),
            wakeAt: date(day: 18, hour: 23).addingTimeInterval(30 * 60),
            durationMinutes: 90,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        let upcomingNightSnapshots = SleepNotificationScheduler.sessionSnapshots(from: [upcomingNightSession])

        XCTAssertFalse(
            scheduler.hasSessionForUpcomingNight(
                sessions: upcomingNightSnapshots,
                now: date(day: 18, hour: 23),
                calendar: calendar
            )
        )
        XCTAssertTrue(
            scheduler.hasSessionForUpcomingNight(
                sessions: upcomingNightSnapshots,
                now: date(day: 18, hour: 23).addingTimeInterval(31 * 60),
                calendar: calendar
            )
        )
    }

    func testSleepResolvedSessionsAndCorrelationRejectFutureWakesAtEvaluationBoundary() {
        let calendar = utcCalendar()
        let beforeWake = date(day: 18, hour: 7)
        let afterWake = date(day: 18, hour: 9)
        let futureCompletedSession = SleepSession(
            confirmedSleepStartAt: date(day: 17, hour: 22),
            wakeAt: date(day: 18, hour: 8),
            durationMinutes: 600,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        let resolver = SleepSourceResolver()
        let beforeResolved = resolver.resolvedSessions(
            from: [futureCompletedSession],
            settings: .default,
            days: 2,
            endingOn: beforeWake,
            calendar: calendar
        )
        let afterResolved = resolver.resolvedSessions(
            from: [futureCompletedSession],
            settings: .default,
            days: 2,
            endingOn: afterWake,
            calendar: calendar
        )

        XCTAssertTrue(beforeResolved.isEmpty)
        XCTAssertEqual(afterResolved.map(\.id), [futureCompletedSession.id])

        let workout = WorkoutSession(
            date: date(day: 18, hour: 12),
            splitNameSnapshot: "Upper",
            completed: true
        )
        let correlationService = SleepWorkoutCorrelationService()
        let beforeCorrelation = correlationService.correlate(
            workouts: [workout],
            sleepSessions: afterResolved,
            historicalSleepSessions: [futureCompletedSession],
            settings: .default,
            endingOn: beforeWake,
            calendar: calendar
        )
        let afterCorrelation = correlationService.correlate(
            workouts: [workout],
            sleepSessions: afterResolved,
            historicalSleepSessions: [futureCompletedSession],
            settings: .default,
            endingOn: afterWake,
            calendar: calendar
        )

        XCTAssertNil(beforeCorrelation.first?.resolvedSleepSession)
        XCTAssertNil(beforeCorrelation.first?.recoveryScore)
        XCTAssertEqual(afterCorrelation.first?.resolvedSleepSession?.id, futureCompletedSession.id)
        XCTAssertNotNil(afterCorrelation.first?.recoveryScore)
    }

    func testSleepSourceResolverUsesInjectedCalendarForNightBucket() throws {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = date(day: 17, hour: 18) // Sunday 11:00 in Pacific time.
        let session = SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: start.addingTimeInterval(8 * 60 * 60),
            durationMinutes: 8 * 60,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        let expectedBucket = SleepCalendar.nightDate(for: start, calendar: pacific)
        let expectedComponents = pacific.dateComponents([.year, .month, .day], from: expectedBucket)

        XCTAssertEqual(expectedComponents.day, 16)
        let resolved = SleepSourceResolver().resolvedSession(
            for: expectedBucket,
            sessions: [session],
            settings: .default,
            endingOn: session.wakeAt.addingTimeInterval(1),
            calendar: pacific
        )
        XCTAssertEqual(resolved?.id, session.id)
        XCTAssertEqual(resolved?.sleepDate, expectedBucket)
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

    func testManualSleepValidationRejectsFutureStartWakeBeforeStartAndTooShort() {
        let repository = SleepSessionRepository()
        let now = Date.now

        XCTAssertThrowsError(
            try repository.validate(
                start: now.addingTimeInterval(5 * 60),
                wake: now.addingTimeInterval(8 * 60 * 60)
            )
        ) { error in
            XCTAssertEqual(error as? SleepSessionValidationError, .startInFuture)
        }

        let pastStart = now.addingTimeInterval(-8 * 60 * 60)
        XCTAssertThrowsError(
            try repository.validate(
                start: pastStart,
                wake: pastStart.addingTimeInterval(-1)
            )
        ) { error in
            XCTAssertEqual(error as? SleepSessionValidationError, .wakeBeforeStart)
        }

        XCTAssertThrowsError(
            try repository.validate(
                start: pastStart,
                wake: pastStart.addingTimeInterval(59 * 60)
            )
        ) { error in
            XCTAssertEqual(error as? SleepSessionValidationError, .tooShort)
        }
    }

    func testManualSleepValidationRejectsFutureWakeAndAcceptsPastIntervalInFixedTimeZone() {
        let repository = SleepSessionRepository()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let referenceNow = Date.now
        let pastStart = calendar.date(byAdding: .hour, value: -8, to: referenceNow)!
        let pastWake = calendar.date(byAdding: .hour, value: -1, to: referenceNow)!
        XCTAssertNoThrow(
            try repository.validate(start: pastStart, wake: pastWake)
        )

        let futureWake = calendar.date(byAdding: .hour, value: 24, to: referenceNow)!
        XCTAssertThrowsError(
            try repository.validate(start: pastStart, wake: futureWake)
        ) { error in
            XCTAssertEqual(error as? SleepSessionValidationError, .wakeInFuture)
            XCTAssertEqual(error.localizedDescription, "Wake time cannot be in the future.")
        }
    }

    func testManualSleepPersistenceStoresValidCompletedSession() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date.now
        let start = now.addingTimeInterval(-8 * 60 * 60)
        let wake = now.addingTimeInterval(-60 * 60)

        try SleepSessionRepository().startManualSession(
            start: start,
            wake: wake,
            quality: 4,
            tags: [.trainedLate],
            notes: "Unit-test manual session",
            in: context
        )

        let sessions = try context.fetch(FetchDescriptor<SleepSession>())
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.source, .manual)
        XCTAssertEqual(session.confidence, .medium)
        XCTAssertEqual(session.durationMinutes, 7 * 60)
        XCTAssertEqual(session.confirmedSleepStartAt, start)
        XCTAssertEqual(session.wakeAt, wake)
        XCTAssertLessThanOrEqual(session.wakeAt, Date.now)
    }

    func testNapRepositoryRejectsFutureEndDate() {
        let start = Date.now.addingTimeInterval(-20 * 60)
        let end = Date.now.addingTimeInterval(60)

        XCTAssertThrowsError(try NapSessionRepository().validate(start: start, end: end)) { error in
            XCTAssertEqual(error as? NapSessionValidationError, .endInFuture)
            XCTAssertEqual(error.localizedDescription, "Nap end time cannot be in the future.")
        }
    }

    func testNapRepositoryRejectsTooShortAndDoesNotPersistNap() throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_010_000)
        let end = start.addingTimeInterval(9 * 60 + 59)

        XCTAssertThrowsError(
            try NapSessionRepository().addNap(
                start: start,
                end: end,
                quality: 3,
                note: "Too short",
                source: .napTimer,
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? NapSessionValidationError, .tooShort)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<NapSession>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testNapTimerDerivesElapsedAndNeverPersistsFutureEndDate() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let idle = NapTimerMachineState.idle(selectedMinutes: 20)
        let started = NapTimerStateMachine.reduce(idle, .start(now: start))

        XCTAssertEqual(started.state.phase, .running)
        XCTAssertEqual(started.state.elapsed(at: start), 0, accuracy: 0.001)
        XCTAssertEqual(started.state.remaining(at: start), 20 * 60, accuracy: 0.001)

        let elapsed = NapTimerStateMachine.reduce(
            started.state,
            .tick(now: start.addingTimeInterval(20 * 60))
        )
        XCTAssertEqual(elapsed.state.phase, .elapsed)
        XCTAssertEqual(elapsed.state.elapsed(at: start.addingTimeInterval(25 * 60)), 20 * 60, accuracy: 0.001)
        XCTAssertEqual(elapsed.state.remaining(at: start.addingTimeInterval(25 * 60)), 0, accuracy: 0.001)

        let tooShort = NapTimerStateMachine.reduce(
            started.state,
            .finish(now: start.addingTimeInterval(9 * 60 + 59))
        )
        XCTAssertEqual(tooShort.state.phase, .running)
        XCTAssertEqual(tooShort.effect, .error(.tooShort))
        XCTAssertNil(tooShort.state.endDate)

        let earlyFinishDate = start.addingTimeInterval(12 * 60)
        let earlyFinish = NapTimerStateMachine.reduce(
            started.state,
            .finish(now: earlyFinishDate)
        )
        guard case .persist(let earlyCompletion) = earlyFinish.effect else {
            return XCTFail("A valid early finish should request persistence")
        }
        XCTAssertEqual(earlyFinish.state.phase, .finishing)
        XCTAssertEqual(earlyCompletion.endDate, earlyFinishDate)

        let lateFinishDate = start.addingTimeInterval(25 * 60)
        let lateFinish = NapTimerStateMachine.reduce(
            started.state,
            .finish(now: lateFinishDate)
        )
        guard case .persist(let lateCompletion) = lateFinish.effect else {
            return XCTFail("A valid late finish should request persistence")
        }
        XCTAssertEqual(lateFinish.state.phase, .finishing)
        XCTAssertEqual(lateCompletion.endDate, start.addingTimeInterval(20 * 60))
        XCTAssertLessThanOrEqual(lateCompletion.endDate, lateFinishDate)

        let completed = NapTimerStateMachine.reduce(lateFinish.state, .finishSucceeded)
        XCTAssertEqual(completed.state.phase, .completed)
        XCTAssertEqual(completed.state.elapsed(at: lateFinishDate), 20 * 60, accuracy: 0.001)
    }

    func testNapTimerDiscardRequiresConfirmationAndCanBeCancelled() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let started = NapTimerStateMachine.reduce(
            NapTimerMachineState.idle(selectedMinutes: 30),
            .start(now: start)
        )

        let requested = NapTimerStateMachine.reduce(started.state, .requestDiscard)
        XCTAssertEqual(requested.state.phase, .discardConfirmation)
        XCTAssertEqual(requested.effect, .none)

        let cancelled = NapTimerStateMachine.reduce(
            requested.state,
            .cancelDiscard(now: start.addingTimeInterval(5 * 60))
        )
        XCTAssertEqual(cancelled.state.phase, .running)

        let confirmed = NapTimerStateMachine.reduce(requested.state, .confirmDiscard)
        XCTAssertEqual(confirmed.state.phase, .idle)
        XCTAssertEqual(confirmed.effect, .discard)
    }

    func testCanonicalSleepSessionScoreMapMatchesDirectScoring() {
        let sessions = [
            sleepSession(day: 9, startHour: 23, durationMinutes: 480, quality: 4, confidence: .high, source: .manual),
            sleepSession(day: 8, startHour: 23, durationMinutes: 420, quality: 3, confidence: .medium, source: .manual),
            sleepSession(day: 7, startHour: 23, durationMinutes: 390, quality: 3, confidence: .medium, source: .manual)
        ]
        let map = SleepSessionScoreMap(sessions: sessions, settings: .default)
        let service = SleepScoringService()

        XCTAssertEqual(map.contextSessionIDs, sessions.map(\.id))
        for session in sessions {
            XCTAssertEqual(
                map.score(for: session.id),
                service.score(for: session, recentSessions: sessions, settings: .default)
            )
        }

        let snapshot = map.snapshot(for: sessions[0].id)
        XCTAssertEqual(snapshot?.score, map.score(for: sessions[0].id))
        XCTAssertEqual(snapshot?.contextSessionIDs, sessions.map(\.id))
    }

    func testSleepAnalyticsSignatureIncludesPreviouslyEasyToMissInputs() {
        let calendar = utcCalendar()
        let now = date(day: 17, hour: 12)
        let session = sleepSession(day: 9, startHour: 23, durationMinutes: 480, quality: 4, confidence: .high, source: .manual)
        let baseline = SleepAnalyticsInputSignature(
            sessions: [session],
            naps: [],
            workouts: [],
            settings: .default,
            now: now,
            calendar: calendar
        )

        session.sleepModeStartedAt = session.confirmedSleepStartAt.addingTimeInterval(-30 * 60)
        let changedSession = SleepAnalyticsInputSignature(
            sessions: [session],
            naps: [],
            workouts: [],
            settings: .default,
            now: now,
            calendar: calendar
        )
        XCTAssertNotEqual(baseline, changedSession)

        let napItem = nap(day: 9, startHour: 13, minutes: 30, timing: .earlyAfternoon)
        let napBaseline = SleepAnalyticsInputSignature(
            sessions: [],
            naps: [napItem],
            workouts: [],
            settings: .default,
            now: now,
            calendar: calendar
        )
        napItem.timingCategory = .evening
        let napChanged = SleepAnalyticsInputSignature(
            sessions: [],
            naps: [napItem],
            workouts: [],
            settings: .default,
            now: now,
            calendar: calendar
        )
        XCTAssertNotEqual(napBaseline, napChanged)

        let set = SetLog(setNumber: 1, weight: 40, reps: 8, completed: true)
        let log = ExerciseLog(
            exerciseId: UUID(),
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0,
            setLogs: [set]
        )
        let workout = WorkoutSession(
            date: date(day: 9, hour: 10),
            splitNameSnapshot: "Upper",
            completed: true,
            exerciseLogs: [log]
        )
        let workoutBaseline = SleepAnalyticsInputSignature(
            sessions: [],
            naps: [],
            workouts: [workout],
            settings: .default,
            now: now,
            calendar: calendar
        )
        set.weight = 42
        let workoutChanged = SleepAnalyticsInputSignature(
            sessions: [],
            naps: [],
            workouts: [workout],
            settings: .default,
            now: now,
            calendar: calendar
        )
        XCTAssertNotEqual(workoutBaseline, workoutChanged)

        let nextDay = SleepAnalyticsInputSignature(
            sessions: [session],
            naps: [],
            workouts: [],
            settings: .default,
            now: date(day: 18, hour: 12),
            calendar: calendar
        )
        XCTAssertNotEqual(changedSession, nextDay)
    }

    func testHealthKitAccessAndImportPresentationAvoidsFalseReadAuthorization() {
        let unavailable = HealthKitSleepAccessResolver.resolve(
            HealthKitSleepAccessInput(
                isAvailable: false,
                readEnabled: true,
                writeEnabled: true,
                authorizationWasRequested: true,
                writeAuthorization: .authorized
            )
        )
        XCTAssertEqual(unavailable.overall, .unavailable)
        XCTAssertEqual(unavailable.read, .unavailable)

        let notRequested = HealthKitSleepAccessResolver.resolve(
            HealthKitSleepAccessInput(
                isAvailable: true,
                readEnabled: true,
                writeEnabled: false,
                authorizationWasRequested: false
            )
        )
        XCTAssertEqual(notRequested.read, .notDetermined)
        XCTAssertEqual(notRequested.overall, .notDetermined)

        let unverified = HealthKitSleepAccessResolver.resolve(
            HealthKitSleepAccessInput(
                isAvailable: true,
                readEnabled: true,
                writeEnabled: false,
                authorizationWasRequested: true
            )
        )
        XCTAssertEqual(unverified.read, .enabledUnverified)
        XCTAssertEqual(unverified.overall, .enabledUnverified)

        let writeAuthorized = HealthKitSleepAccessResolver.resolve(
            HealthKitSleepAccessInput(
                isAvailable: true,
                readEnabled: false,
                writeEnabled: true,
                authorizationWasRequested: true,
                writeAuthorization: .authorized
            )
        )
        XCTAssertEqual(writeAuthorized.write, .authorized)
        XCTAssertEqual(writeAuthorized.overall, .authorized)

        let syncDate = date(day: 17, hour: 8)
        XCTAssertEqual(
            HealthKitSleepImportPresentation.make(
                result: .noNewData(lastSyncedAt: syncDate)
            ),
            .noNewData(lastSyncedAt: syncDate)
        )

        let candidate = HealthKitSleepImportCandidate.nap(
            startDate: date(day: 17, hour: 13),
            endDate: date(day: 17, hour: 13).addingTimeInterval(30 * 60),
            healthKitSampleIds: ["nap-sample"]
        )
        let imported = HealthKitSleepImportResult.imported(candidates: [candidate], lastSyncedAt: nil)
        XCTAssertEqual(imported.importedCount, 1)
        XCTAssertEqual(
            HealthKitSleepImportPresentation.make(result: imported, lastSyncedAt: syncDate),
            .imported(count: 1, lastSyncedAt: syncDate)
        )

        let failed = HealthKitSleepImportResult.error(.readFailed("permission response unavailable"))
        XCTAssertEqual(
            HealthKitSleepImportPresentation.make(result: failed),
            .error("Apple Health sleep read failed. permission response unavailable")
        )
    }

    func testHealthKitImportBoundaryRejectsFutureStartAndEndWithFixedReferenceTime() {
        let referenceNow = Date(timeIntervalSince1970: 1_800_000_000)
        let pastStart = referenceNow.addingTimeInterval(-8 * 60 * 60)
        let pastEnd = referenceNow.addingTimeInterval(-60 * 60)

        XCTAssertTrue(
            HealthKitSleepImportCandidate.isValidImportInterval(
                startDate: pastStart,
                endDate: pastEnd,
                referenceNow: referenceNow
            )
        )
        XCTAssertFalse(
            HealthKitSleepImportCandidate.isValidImportInterval(
                startDate: pastStart,
                endDate: referenceNow.addingTimeInterval(60),
                referenceNow: referenceNow
            )
        )
        XCTAssertFalse(
            HealthKitSleepImportCandidate.isValidImportInterval(
                startDate: referenceNow.addingTimeInterval(60),
                endDate: referenceNow.addingTimeInterval(2 * 60 * 60),
                referenceNow: referenceNow
            )
        )
        XCTAssertFalse(
            HealthKitSleepImportCandidate.isValidImportInterval(
                startDate: pastEnd,
                endDate: pastStart,
                referenceNow: referenceNow
            )
        )

        let futureNap = HealthKitSleepImportCandidate.nap(
            startDate: pastStart,
            endDate: referenceNow.addingTimeInterval(60),
            healthKitSampleIds: ["future-nap"]
        )
        XCTAssertFalse(futureNap.isValidForImport(at: referenceNow))
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
