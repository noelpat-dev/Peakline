import XCTest
@testable import GymTracker

@MainActor
final class CoachIntelligenceServiceTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date!
    private var service: CoachIntelligenceService!
    private var adjustmentService: CoachWorkoutAdjustmentService!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        today = calendar.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 12))!
        service = CoachIntelligenceService(calendar: calendar)
        adjustmentService = CoachWorkoutAdjustmentService()
    }

    func testReadinessCategoryMappingIsDeterministic() {
        XCTAssertEqual(ReadinessCategory(score: 100), .peak)
        XCTAssertEqual(ReadinessCategory(score: 85), .peak)
        XCTAssertEqual(ReadinessCategory(score: 84), .ready)
        XCTAssertEqual(ReadinessCategory(score: 70), .ready)
        XCTAssertEqual(ReadinessCategory(score: 69), .cautious)
        XCTAssertEqual(ReadinessCategory(score: 55), .cautious)
        XCTAssertEqual(ReadinessCategory(score: 54), .low)
        XCTAssertEqual(ReadinessCategory(score: 40), .low)
        XCTAssertEqual(ReadinessCategory(score: 39), .recovery)
    }

    func testReadinessRefreshClockStartIsIdempotent() {
        let clock = ReadinessRefreshClock.shared

        clock.start()
        let firstToken = clock.token
        clock.start()

        XCTAssertEqual(clock.token, firstToken)
    }

    func testReadinessV2LockedAggregationFixtures() {
        let scorer = ReadinessScoringService()
        let signal: (ReadinessFactorKind, Int) -> ReadinessSignalEvidence = { kind, score in
            ReadinessSignalEvidence(kind: kind, detail: "Fixture", rawScore: score)
        }

        let noInputs = scorer.score([])
        let strongCheckInOnly = scorer.score([signal(.checkIn, 100)])
        let lowSleepOnly = scorer.score([signal(.sleep, 45)])
        let strongTrainingAndCheckIn = scorer.score([signal(.training, 86), signal(.checkIn, 100)])
        let lowTrainingAndCheckIn = scorer.score([signal(.training, 30), signal(.checkIn, 45)])
        let poorSleepWithNeutralCore = scorer.score([
            signal(.sleep, 45),
            signal(.training, 70),
            signal(.checkIn, 70)
        ])
        let allStrong = scorer.score(ReadinessFactorKind.allCases.map { signal($0, 91) })

        XCTAssertEqual(noInputs.value, 70)
        XCTAssertTrue(noInputs.isProvisional)
        XCTAssertEqual(strongCheckInOnly.value, 82)
        XCTAssertTrue(strongCheckInOnly.isProvisional)
        XCTAssertEqual(lowSleepOnly.value, 60)
        XCTAssertTrue(lowSleepOnly.isProvisional)
        XCTAssertEqual(strongTrainingAndCheckIn.value, 88)
        XCTAssertEqual(lowTrainingAndCheckIn.value, 43)
        XCTAssertEqual(poorSleepWithNeutralCore.value, 62)
        XCTAssertEqual(allStrong.value, 91)
        XCTAssertEqual(allStrong.confidence, .high)
        XCTAssertTrue(allStrong.diagnosticSummary.contains("readiness-v2"))
    }

    func testReadinessV2CapsSingleSignalAndKeepsMissingDataNeutral() throws {
        let scorer = ReadinessScoringService()
        let checkIn = ReadinessSignalEvidence(kind: .checkIn, detail: "Strong", rawScore: 100)
        let missingSleep = ReadinessSignalEvidence(kind: .sleep, detail: "Missing", rawScore: nil, reliability: 0)

        let single = scorer.score([checkIn])
        let explicitMissing = scorer.score([checkIn, missingSleep])
        let factor = try XCTUnwrap(single.factors.first { $0.kind == .checkIn })
        let sleepFactor = try XCTUnwrap(explicitMissing.factors.first { $0.kind == .sleep })

        XCTAssertEqual(factor.effectiveWeight, 0.40, accuracy: 0.0001)
        XCTAssertEqual(single.value, explicitMissing.value)
        XCTAssertNil(sleepFactor.score)
        XCTAssertEqual(sleepFactor.contribution, 0)
        XCTAssertFalse(sleepFactor.isDataAvailable)
    }

    func testReadinessV2CapsNutritionAggregateInfluenceAtTenPercent() throws {
        let scorer = ReadinessScoringService()
        let result = scorer.score([
            ReadinessSignalEvidence(
                kind: .nutrition,
                detail: "Qualified nutrition modifier",
                rawScore: 95,
                reliability: 1
            )
        ])
        let factor = try XCTUnwrap(result.factors.first { $0.kind == .nutrition })

        XCTAssertEqual(factor.effectiveWeight, 0.10, accuracy: 0.0001)
        XCTAssertEqual(factor.contribution, 2.5, accuracy: 0.0001)
        XCTAssertEqual(result.value, 73)
        XCTAssertTrue(result.isProvisional)
    }

    func testReadinessV2ConfidenceBoundaries() {
        let scorer = ReadinessScoringService()
        let signal: (ReadinessFactorKind, Int, Double) -> ReadinessSignalEvidence = { kind, score, reliability in
            ReadinessSignalEvidence(kind: kind, detail: "Fixture", rawScore: score, reliability: reliability)
        }

        XCTAssertEqual(scorer.score([signal(.sleep, 80, 1)]).confidence, .low)
        XCTAssertEqual(
            scorer.score([signal(.sleep, 80, 1), signal(.training, 80, 1)]).confidence,
            .medium
        )
        XCTAssertEqual(
            scorer.score([
                signal(.sleep, 80, 1),
                signal(.training, 80, 1),
                signal(.checkIn, 80, 1),
                signal(.nutrition, 80, 1)
            ]).confidence,
            .high
        )
        XCTAssertEqual(
            scorer.score([signal(.sleep, 80, 0.50), signal(.hydration, 80, 0.25)]).confidence,
            .low
        )
    }

    func testReadinessV2PersonalCalibrationActivatesAtFiveSamplesAndCapsAtEightPoints() throws {
        let scorer = ReadinessScoringService()
        let fourSamples = scorer.score([
            ReadinessSignalEvidence(
                kind: .sleep,
                detail: "Four samples",
                rawScore: 80,
                historicalScores: [20, 20, 20, 20]
            )
        ])
        let fiveLowSamples = scorer.score([
            ReadinessSignalEvidence(
                kind: .sleep,
                detail: "Five samples",
                rawScore: 80,
                historicalScores: [20, 20, 20, 20, 20]
            )
        ])
        let fiveHighSamples = scorer.score([
            ReadinessSignalEvidence(
                kind: .training,
                detail: "Five samples",
                rawScore: 20,
                historicalScores: [100, 100, 100, 100, 100]
            )
        ])

        XCTAssertEqual(try XCTUnwrap(fourSamples.factors.first { $0.kind == .sleep }).calibrationAdjustment, 0)
        XCTAssertEqual(try XCTUnwrap(fiveLowSamples.factors.first { $0.kind == .sleep }).calibrationAdjustment, 8)
        XCTAssertEqual(try XCTUnwrap(fiveLowSamples.factors.first { $0.kind == .sleep }).score, 88)
        XCTAssertEqual(try XCTUnwrap(fiveHighSamples.factors.first { $0.kind == .training }).calibrationAdjustment, -8)
        XCTAssertEqual(try XCTUnwrap(fiveHighSamples.factors.first { $0.kind == .training }).score, 12)
    }

    func testReadinessV2UsesNeutralCentredCheckInAnchors() throws {
        let readiness = makeReadiness(
            checkIns: [checkIn(daysAgo: 0, energy: 3, soreness: 3, stress: 3, motivation: 3)]
        )
        let factor = try XCTUnwrap(readiness.factors.first { $0.kind == .checkIn })

        XCTAssertEqual(factor.rawScore, 70)
        XCTAssertEqual(readiness.value, 70)
        XCTAssertTrue(readiness.isProvisional)
    }

    func testReadinessV2ExcludesStaleSleepAndNapOnlyEvidence() throws {
        let napStart = date(daysAgo: 0, hour: 10)
        let readiness = makeReadiness(
            sleepSessions: [sleep(daysAgo: 1, minutes: 480, quality: 4)],
            napSessions: [NapSession(startDate: napStart, endDate: napStart.addingTimeInterval(30 * 60), source: .manual)]
        )
        let factor = try XCTUnwrap(readiness.factors.first { $0.kind == .sleep })

        XCTAssertNil(factor.score)
        XCTAssertFalse(factor.isDataAvailable)
        XCTAssertTrue(factor.detail.localizedCaseInsensitiveContains("nap"))
    }

    func testReadinessV2HydrationReliabilityFollowsPacingPhase() throws {
        let entry = HydrationEntry(amountML: 500, loggedAt: date(daysAgo: 0, hour: 8))
        let morning = makeReadiness(for: date(daysAgo: 0, hour: 9), hydrationEntries: [entry])
        let evening = makeReadiness(for: date(daysAgo: 0, hour: 18), hydrationEntries: [entry])
        let morningFactor = try XCTUnwrap(morning.factors.first { $0.kind == .hydration })
        let eveningFactor = try XCTUnwrap(evening.factors.first { $0.kind == .hydration })

        XCTAssertEqual(morningFactor.reliability, 0.25, accuracy: 0.0001)
        XCTAssertEqual(eveningFactor.reliability, 0.90, accuracy: 0.0001)
        XCTAssertLessThan(morningFactor.effectiveWeight, 0.40)
        XCTAssertGreaterThan(morningFactor.score ?? 0, eveningFactor.score ?? 100)
    }

    func testReadinessV2NutritionRequiresThreeQualifiedCompletedDaysAndExcludesToday() throws {
        let goal = NutritionGoal(
            dailyCaloriesTarget: 2_500,
            dailyProteinTarget: 160,
            dailyCarbsTarget: nil,
            dailyFatTarget: nil,
            trainingDayCaloriesTarget: nil,
            restDayCaloriesTarget: nil,
            isEnabled: true,
            updatedAt: today
        )
        let twoCompletedDays = [1, 2].flatMap { day in
            (0..<3).map { _ in food(daysAgo: day, calories: 800, protein: 55) }
        }
        let todayLogs = (0..<3).map { _ in food(daysAgo: 0, calories: 800, protein: 55) }
        let unqualified = makeReadiness(foodLogs: twoCompletedDays + todayLogs, nutritionGoal: goal)
        let qualified = makeReadiness(
            foodLogs: twoCompletedDays + (0..<3).map { _ in food(daysAgo: 3, calories: 800, protein: 55) },
            nutritionGoal: goal
        )
        let unqualifiedFactor = try XCTUnwrap(unqualified.factors.first { $0.kind == .nutrition })
        let qualifiedFactor = try XCTUnwrap(qualified.factors.first { $0.kind == .nutrition })

        XCTAssertNil(unqualifiedFactor.score)
        XCTAssertNotNil(qualifiedFactor.score)
        XCTAssertLessThanOrEqual(qualifiedFactor.rawScore ?? 100, 95)
        XCTAssertEqual(qualifiedFactor.reliability, 0.60, accuracy: 0.0001)
    }

    func testReadinessV2RejectsFutureWorkoutData() throws {
        let exercise = exercise(name: "Future Press", primary: .chest, compound: true)
        let futureWorkout = workout(daysAgo: 0, exercise: exercise, setCount: 3, weight: 80, reps: 8, rpe: 7, difficulty: 3)
        let readiness = makeReadiness(completedWorkouts: [futureWorkout])
        let factor = try XCTUnwrap(readiness.factors.first { $0.kind == .training })

        XCTAssertNil(factor.score)
        XCTAssertEqual(readiness.value, 70)
    }

    func testProvisionalReadinessCannotDrivePushRecoveryOrLowReadinessWarning() {
        let strong = makeSnapshot(
            checkIns: [checkIn(daysAgo: 0, energy: 5, soreness: 1, stress: 1, motivation: 5)]
        )
        let low = makeSnapshot(
            checkIns: [checkIn(daysAgo: 0, energy: 1, soreness: 5, stress: 5, motivation: 1)]
        )

        XCTAssertTrue(strong.readiness.isProvisional)
        XCTAssertEqual(strong.readiness.recommendation.title, "Provisional readiness")
        XCTAssertNotEqual(strong.adaptiveGuidance.mode, .push)
        XCTAssertTrue(low.readiness.isProvisional)
        XCTAssertNotEqual(low.adaptiveGuidance.mode, .recoveryFocus)
        XCTAssertFalse(low.fatigueRisk.factors.contains("Readiness is low or trending down."))
    }

    func testWeeklyReadinessTrendOmitsProvisionalDays() {
        let snapshot = makeSnapshot(
            checkIns: [checkIn(daysAgo: 0, energy: 4, soreness: 2, stress: 2, motivation: 4)]
        )

        XCTAssertEqual(snapshot.trends.readiness.direction, .insufficientData)
        XCTAssertNil(snapshot.trends.readiness.currentValue)
        XCTAssertNil(snapshot.trends.readiness.previousValue)
    }

    func testMissingDataProducesLowConfidenceNewUserGuidance() {
        let snapshot = makeSnapshot()

        XCTAssertEqual(snapshot.readiness.confidence, .low)
        XCTAssertFalse(snapshot.readiness.hasCompletedTodayCheckIn)
        XCTAssertTrue(snapshot.readiness.factors.contains { !$0.isDataAvailable })
        XCTAssertEqual(snapshot.insights.first?.id, "baseline-building")
        XCTAssertEqual(snapshot.fatigueRisk.level, .low)
    }

    func testReadinessScorerUsesNeutralPriorWhenNoEvidenceIsAvailable() {
        let result = ReadinessScoringService().score([])

        XCTAssertEqual(result.value, ReadinessScoringService.neutralPrior)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.availableSignalCount, 0)
        XCTAssertEqual(result.effectiveEvidenceWeight, 0, accuracy: 0.001)
        XCTAssertEqual(result.factors.count, ReadinessFactorKind.allCases.count)
        XCTAssertTrue(result.factors.allSatisfy { !$0.isDataAvailable })
    }

    func testReadinessScorerCapsSingleSignalInfluence() throws {
        let result = ReadinessScoringService().score([
            ReadinessSignalEvidence(
                kind: .sleep,
                detail: "Excellent sleep.",
                rawScore: 100
            )
        ])

        let sleep = try XCTUnwrap(result.factors.first { $0.kind == .sleep })
        XCTAssertEqual(result.value, 82)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.availableSignalCount, 1)
        XCTAssertEqual(result.effectiveEvidenceWeight, 0.4, accuracy: 0.001)
        XCTAssertEqual(sleep.effectiveWeight, 0.4, accuracy: 0.001)
        XCTAssertEqual(sleep.impact, .positive)
    }

    func testReadinessScorerReachesHighConfidenceOnlyWithBroadReliableCoverage() {
        let evidence = ReadinessFactorKind.allCases.map {
            ReadinessSignalEvidence(kind: $0, detail: "Available.", rawScore: 80)
        }

        let result = ReadinessScoringService().score(evidence)

        XCTAssertEqual(result.value, 80)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.availableSignalCount, ReadinessFactorKind.allCases.count)
        XCTAssertEqual(result.effectiveEvidenceWeight, 1, accuracy: 0.001)
        XCTAssertTrue(result.diagnosticSummary.contains(ReadinessScoringService.version))
    }

    func testReadinessScorerClampsInputsAndAppliesBoundedPersonalCalibration() throws {
        let result = ReadinessScoringService().score([
            ReadinessSignalEvidence(
                kind: .sleep,
                detail: "Above personal baseline.",
                rawScore: 120,
                reliability: 2,
                historicalScores: [40, 45, 50, 55, 60]
            )
        ])

        let sleep = try XCTUnwrap(result.factors.first { $0.kind == .sleep })
        XCTAssertEqual(sleep.rawScore, 100)
        XCTAssertEqual(sleep.reliability, 1, accuracy: 0.001)
        XCTAssertEqual(sleep.calibrationAdjustment, 8)
        XCTAssertEqual(sleep.score, 100)
        XCTAssertEqual(result.value, 82)
    }

    func testWeeklyCheckInTrendDetectsImprovingEnergy() {
        let checkIns = [
            checkIn(daysAgo: 0, energy: 5, soreness: 2, stress: 2, motivation: 5),
            checkIn(daysAgo: 1, energy: 5, soreness: 2, stress: 2, motivation: 5),
            checkIn(daysAgo: 2, energy: 4, soreness: 2, stress: 2, motivation: 4),
            checkIn(daysAgo: 7, energy: 2, soreness: 3, stress: 4, motivation: 2),
            checkIn(daysAgo: 8, energy: 2, soreness: 3, stress: 4, motivation: 2),
            checkIn(daysAgo: 9, energy: 2, soreness: 3, stress: 4, motivation: 2)
        ]

        let snapshot = makeSnapshot(checkIns: checkIns)

        XCTAssertEqual(snapshot.trends.energy.direction, .improving)
        XCTAssertEqual(snapshot.trends.motivation.direction, .improving)
    }

    func testFatigueRiskDetectsDeloadWatchSignals() {
        let exercise = exercise(name: "Leg Press", primary: .quads, secondary: [.glutes], compound: true)
        let workouts = (0..<4).map { offset in
            workout(daysAgo: offset, exercise: exercise, setCount: 18, weight: 120, reps: 8, rpe: 9, difficulty: 5)
        }
        let snapshot = makeSnapshot(
            exercises: [exercise],
            completedWorkouts: workouts,
            checkIns: [checkIn(daysAgo: 0, energy: 1, soreness: 5, stress: 4, motivation: 2)]
        )

        XCTAssertEqual(snapshot.fatigueRisk.level, .deloadWatch)
        XCTAssertTrue(snapshot.fatigueRisk.recommendedAction.localizedCaseInsensitiveContains("lighter"))
        XCTAssertEqual(snapshot.adaptiveGuidance.mode, .recoveryFocus)
    }

    func testMuscleGroupFatigueUsesRecentLocalLoadAndSoreness() throws {
        let exercise = exercise(name: "Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let workouts = [
            workout(daysAgo: 1, exercise: exercise, setCount: 6, weight: 80, reps: 8, rpe: 8, difficulty: 4),
            workout(daysAgo: 2, exercise: exercise, setCount: 6, weight: 78, reps: 8, rpe: 8, difficulty: 4)
        ]

        let snapshot = makeSnapshot(
            exercises: [exercise],
            completedWorkouts: workouts,
            checkIns: [checkIn(daysAgo: 0, energy: 3, soreness: 4, stress: 2, motivation: 3)]
        )

        let chest = try XCTUnwrap(snapshot.muscleFatigue.first { $0.muscleGroup == .chest })
        XCTAssertEqual(chest.state, .fatigued)
        XCTAssertEqual(chest.recentSetCount, 12)
    }

    func testConservativeLiftProgressDetectsDecliningHistory() throws {
        let exercise = exercise(name: "Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let workouts = [
            workout(daysAgo: 1, exercise: exercise, setCount: 3, weight: 90, reps: 6, rpe: 8, difficulty: 3),
            workout(daysAgo: 3, exercise: exercise, setCount: 3, weight: 95, reps: 6, rpe: 8, difficulty: 3),
            workout(daysAgo: 5, exercise: exercise, setCount: 3, weight: 100, reps: 6, rpe: 8, difficulty: 3)
        ]

        let snapshot = makeSnapshot(exercises: [exercise], completedWorkouts: workouts)

        let benchInsight = try XCTUnwrap(snapshot.liftInsights.first { $0.exerciseName == "Bench Press" })
        XCTAssertEqual(benchInsight.state, .declining)
        XCTAssertEqual(benchInsight.confidence, .medium)
    }

    func testAdaptiveGuidancePushModeWhenRecoverySignalsAreStrong() {
        let plannedBench = exercise(name: "Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let recentLegs = exercise(name: "Leg Press", primary: .quads, secondary: [.glutes], compound: true)
        let snapshot = makeSnapshot(
            exercises: [plannedBench, recentLegs],
            plannedExerciseIDs: [plannedBench.id],
            sleepSessions: [sleep(daysAgo: 0, minutes: 540, quality: 5)],
            hydrationEntries: [hydration(daysAgo: 0, amount: 2_600)],
            completedWorkouts: [
                workout(daysAgo: 2, exercise: recentLegs, setCount: 3, weight: 120, reps: 8, rpe: 7, difficulty: 3)
            ],
            foodLogs: [food(daysAgo: 0, calories: 2_600, protein: 170)],
            checkIns: [checkIn(daysAgo: 0, energy: 5, soreness: 1, stress: 1, motivation: 5)],
            nutritionGoal: NutritionGoal(
                dailyCaloriesTarget: 2_500,
                dailyProteinTarget: 160,
                dailyCarbsTarget: nil,
                dailyFatTarget: nil,
                trainingDayCaloriesTarget: nil,
                restDayCaloriesTarget: nil,
                isEnabled: true,
                updatedAt: today
            )
        )

        XCTAssertEqual(snapshot.readiness.category, .peak)
        XCTAssertEqual(snapshot.adaptiveGuidance.mode, .push)
    }

    func testAdaptiveWorkoutActionPreviewIsUserControlledAndDoesNotMutateOriginalPlan() {
        let exercise = exercise(name: "Cable Fly", primary: .chest, secondary: [], compound: false)
        let plan = [
            plannedExercise(name: "Bench Press", exerciseId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, sets: 4),
            plannedExercise(name: "Cable Fly", exerciseId: exercise.id, sets: 3),
            plannedExercise(name: "Triceps Pushdown", exerciseId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, sets: 3)
        ]
        let snapshot = makeSnapshot(
            exercises: [exercise],
            checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)]
        )

        let preview = adjustmentService.makePreview(
            action: .reduceAccessories,
            plannedExercises: plan,
            snapshot: snapshot,
            exercises: [exercise],
            plannedMuscleFatigue: []
        )

        XCTAssertEqual(plan.reduce(0) { $0 + $1.targetSets }, 10)
        XCTAssertLessThan(preview.afterTotalSets, preview.beforeTotalSets)
        XCTAssertEqual(preview.unchanged.first, "Original split template")
        XCTAssertEqual(plan[1].targetSets, 3)
    }

    func testDeloadRiskGuidanceOffersManualDeloadPlanWhenElevated() {
        let exercise = exercise(name: "Hack Squat", primary: .quads, secondary: [.glutes], compound: true)
        let workouts = (0..<4).map { offset in
            workout(daysAgo: offset, exercise: exercise, setCount: 18, weight: 100, reps: 8, rpe: 9, difficulty: 5)
        }
        let snapshot = makeSnapshot(
            exercises: [exercise],
            completedWorkouts: workouts,
            checkIns: [checkIn(daysAgo: 0, energy: 1, soreness: 5, stress: 4, motivation: 1)]
        )
        let recommendations = adjustmentService.recommendations(
            for: snapshot,
            plannedExercises: [plannedExercise(name: "Hack Squat", exerciseId: exercise.id, sets: 4)],
            plannedMuscleFatigue: snapshot.muscleFatigue.filter { $0.muscleGroup == .quads }
        )

        XCTAssertEqual(snapshot.fatigueRisk.level, .deloadWatch)
        XCTAssertTrue(adjustmentService.deloadPlannerIsUseful(for: snapshot.fatigueRisk))
        XCTAssertTrue(recommendations.contains { $0.action == .deloadStyleSession && $0.isCoachSuggested })
        XCTAssertEqual(adjustmentService.defaultDeloadPlan(for: snapshot.fatigueRisk).duration, .sevenDays)
    }

    func testEditedAdjustmentPreviewUpdatesOnlyDraftPlan() throws {
        let accessory = exercise(name: "Cable Fly", primary: .chest, compound: false)
        let plan = [
            plannedExercise(name: "Bench Press", exerciseId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, sets: 4),
            plannedExercise(name: "Cable Fly", exerciseId: accessory.id, sets: 3)
        ]
        let snapshot = makeSnapshot(checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)])
        let preview = adjustmentService.makePreview(
            action: .reduceAccessories,
            plannedExercises: plan,
            snapshot: snapshot,
            exercises: [accessory],
            plannedMuscleFatigue: [],
            splitName: "Push"
        )
        var draft = adjustmentService.editableDraft(from: preview)
        let cableIndex = try XCTUnwrap(draft.exerciseAdjustments.firstIndex { $0.name == "Cable Fly" })

        draft.exerciseAdjustments[cableIndex].editedSets = 1
        draft.exerciseAdjustments[cableIndex].editedNotes = "Keep this easy today."
        let editedPreview = adjustmentService.makePreview(from: draft)
        let editedCable = try XCTUnwrap(editedPreview.adjustedExercises.first { $0.exerciseNameSnapshot == "Cable Fly" })

        XCTAssertEqual(editedCable.targetSets, 1)
        XCTAssertEqual(editedCable.notes, "Keep this easy today.")
        XCTAssertEqual(plan[1].targetSets, 3)
        XCTAssertTrue(editedPreview.summary.localizedCaseInsensitiveContains("user-reviewed"))
    }

    func testAdjustmentDraftResetsIndividualAndAllExercises() throws {
        let accessory = exercise(name: "Triceps Pushdown", primary: .triceps, compound: false)
        let plan = [
            plannedExercise(name: "Bench Press", exerciseId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, sets: 4),
            plannedExercise(name: "Triceps Pushdown", exerciseId: accessory.id, sets: 3)
        ]
        let snapshot = makeSnapshot(checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)])
        let preview = adjustmentService.makePreview(
            action: .reduceAccessories,
            plannedExercises: plan,
            snapshot: snapshot,
            exercises: [accessory],
            plannedMuscleFatigue: [],
            splitName: "Push"
        )
        let draft = adjustmentService.editableDraft(from: preview)
        let triceps = try XCTUnwrap(draft.exerciseAdjustments.first { $0.name == "Triceps Pushdown" })

        let singleReset = adjustmentService.resetAdjustment(exerciseId: triceps.id, in: draft)
        let singleResetPreview = adjustmentService.makePreview(from: singleReset)
        let resetTriceps = try XCTUnwrap(singleResetPreview.exerciseAdjustments.first { $0.name == "Triceps Pushdown" })
        XCTAssertEqual(resetTriceps.afterSets, resetTriceps.beforeSets)

        let allResetPreview = adjustmentService.makePreview(from: adjustmentService.resetAllAdjustments(in: draft))
        XCTAssertEqual(allResetPreview.beforeTotalSets, allResetPreview.afterTotalSets)
        XCTAssertFalse(allResetPreview.hasWorkoutChanges)
    }

    func testCoachActionHistoryEntryCapturesOutcomeAndContext() {
        let snapshot = makeSnapshot(checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)])
        let preview = adjustmentService.makePreview(
            action: .techniqueFocus,
            plannedExercises: [plannedExercise(name: "Bench Press", exerciseId: UUID(), sets: 4)],
            snapshot: snapshot,
            exercises: [],
            plannedMuscleFatigue: [],
            splitName: "Push"
        )
        let entry = CoachActionHistoryService().makeEntry(
            preview: preview,
            outcome: .applied,
            snapshot: snapshot,
            splitName: "Push",
            date: today
        )

        XCTAssertEqual(entry.action, .techniqueFocus)
        XCTAssertEqual(entry.outcome, .applied)
        XCTAssertEqual(entry.readinessCategory, snapshot.readiness.category)
        XCTAssertEqual(entry.fatigueRiskLevel, snapshot.fatigueRisk.level)
        XCTAssertEqual(entry.confidence, preview.confidence)
        XCTAssertEqual(entry.workoutName, "Push")
        XCTAssertEqual(entry.beforeTotalSets, 4)
        XCTAssertEqual(entry.afterTotalSets, 4)
    }

    func testSavedDeloadBlockStateTransitions() {
        let service = SavedCoachDeloadBlockService(calendar: calendar)
        let plan = ManualDeloadPlan(duration: .threeDays, volumeReduction: .fortyPercent, focus: .techniqueOnly)
        let block = service.makeBlock(plan: plan, startDate: today, reason: "Fatigue is elevated.", splitName: "Legs")

        XCTAssertEqual(block.state, .active)
        XCTAssertEqual(block.duration, .threeDays)
        XCTAssertEqual(calendar.dateComponents([.day], from: block.startsAt, to: block.endsAt).day, 2)

        service.complete(block, date: date(daysAgo: 0, hour: 14))
        XCTAssertEqual(block.state, .completed)

        service.cancel(block, date: date(daysAgo: 0, hour: 15))
        XCTAssertEqual(block.state, .cancelled)
    }

    func testSplitAwareAccessoryClassificationUsesStructuredMetadata() {
        let bench = exercise(name: "Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let pushdown = exercise(name: "Triceps Pushdown", primary: .triceps, compound: false)
        let benchPlan = plannedExercise(name: "Bench Press", exerciseId: bench.id, sets: 4)
        let pushdownPlan = plannedExercise(name: "Triceps Pushdown", exerciseId: pushdown.id, sets: 3)

        let benchRole = adjustmentService.classify(exercise: benchPlan, index: 0, metadata: bench, splitName: "Push").role
        let pushdownRole = adjustmentService.classify(exercise: pushdownPlan, index: 4, metadata: pushdown, splitName: "Push").role

        XCTAssertEqual(benchRole, .primaryCompound)
        XCTAssertEqual(pushdownRole, .accessory)
    }

    func testExerciseMetadataDraftAndServiceRoundTrip() {
        let exercise = exercise(name: "Paused Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let draft = CoachExerciseMetadataDraft(
            role: .priorityLift,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            movementPattern: .push,
            splitClassification: .push,
            priority: .high,
            userNote: "Keep one hard top set when readiness is high."
        )
        let metadataService = CoachExerciseMetadataService()
        let metadata = metadataService.makeMetadata(from: draft, exercise: exercise)

        XCTAssertEqual(metadata.exerciseId, exercise.id)
        XCTAssertEqual(metadata.role, .priorityLift)
        XCTAssertEqual(metadata.primaryMuscleGroup, .chest)
        XCTAssertEqual(metadata.secondaryMuscleGroups, [.triceps, .shoulders])
        XCTAssertEqual(metadata.splitClassification, .push)
        XCTAssertEqual(metadata.priority, .high)
        XCTAssertEqual(metadata.userNote, "Keep one hard top set when readiness is high.")

        let updatedDraft = CoachExerciseMetadataDraft(
            role: .accessory,
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            movementPattern: .push,
            splitClassification: .push,
            priority: .low,
            userNote: "  "
        )
        metadataService.update(metadata, from: updatedDraft)

        XCTAssertEqual(metadata.role, .accessory)
        XCTAssertEqual(metadata.primaryMuscleGroup, .triceps)
        XCTAssertEqual(metadata.priority, .low)
        XCTAssertNil(metadata.userNote)
    }

    func testUnifiedExerciseEditorSynchronizesSharedFieldsWithoutRepeatedWrites() {
        let exercise = Exercise(name: "Bench Press", primaryMuscleGroup: .chest,
                                secondaryMuscleGroups: [.triceps], movementPattern: .push,
                                equipment: .barbell, isCompound: true)
        let originalDate = Date(timeIntervalSince1970: 100)
        let metadata = CoachExerciseMetadata(exerciseId: exercise.id, updatedAt: originalDate,
            role: .priorityLift, primaryMuscleGroup: .back, secondaryMuscleGroups: [.biceps],
            movementPattern: .pull, splitClassification: .push, priority: .high, userNote: "Keep my note")
        let service = CoachExerciseMetadataService()
        let draft = service.editorDraft(for: exercise, metadata: metadata)
        XCTAssertEqual(draft.primaryMuscleGroup, .chest)
        XCTAssertEqual(draft.secondaryMuscleGroups, [.triceps])
        XCTAssertEqual(draft.movementPattern, .push)
        XCTAssertEqual(draft.role, .priorityLift)
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.userNote, "Keep my note")
        XCTAssertTrue(service.updateIfNeeded(metadata, from: draft))
        let settledDate = metadata.updatedAt
        XCTAssertFalse(service.updateIfNeeded(metadata, from: draft))
        XCTAssertEqual(metadata.updatedAt, settledDate)
        exercise.primaryMuscleGroup = .shoulders
        exercise.secondaryMuscleGroups = [.triceps, .shoulders]
        let changed = service.editorDraft(for: exercise, metadata: metadata)
        XCTAssertTrue(service.updateIfNeeded(metadata, from: changed))
        XCTAssertEqual(metadata.primaryMuscleGroup, .shoulders)
        XCTAssertEqual(metadata.secondaryMuscleGroups, [.triceps])
        XCTAssertEqual(metadata.priority, .high)
    }

    func testUserExerciseMetadataOverridesFallbackClassification() throws {
        let exerciseId = UUID()
        let plan = plannedExercise(name: "Mystery Press", exerciseId: exerciseId, sets: 5)
        let metadata = CoachExerciseMetadata(
            exerciseId: exerciseId,
            role: .priorityLift,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            splitClassification: .push,
            priority: .high,
            userNote: "Main press for this block."
        )

        let classification = adjustmentService.classify(
            exercise: plan,
            index: 3,
            metadata: nil,
            coachMetadata: metadata,
            splitName: "Push"
        )

        XCTAssertEqual(classification.role, .priorityLift)
        XCTAssertEqual(classification.source, .userMetadata)
        XCTAssertTrue(classification.reason.localizedCaseInsensitiveContains("priority"))

        let preview = adjustmentService.makePreview(
            action: .reduceTotalVolume,
            plannedExercises: [plan],
            snapshot: makeSnapshot(checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)]),
            exercises: [],
            plannedMuscleFatigue: [],
            splitName: "Push",
            exerciseMetadata: [metadata]
        )
        let adjustedExercise = try XCTUnwrap(preview.adjustedExercises.first)
        XCTAssertEqual(adjustedExercise.targetSets, 5)
        XCTAssertTrue(preview.contributingSignals.contains { $0.localizedCaseInsensitiveContains("user metadata") })
    }

    func testUserAccessoryMetadataAllowsConfidentAccessoryReduction() throws {
        let exerciseId = UUID()
        let plan = plannedExercise(name: "Cable Chest Press", exerciseId: exerciseId, sets: 3)
        let metadata = CoachExerciseMetadata(
            exerciseId: exerciseId,
            role: .accessory,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            splitClassification: .push,
            priority: .normal
        )

        let preview = adjustmentService.makePreview(
            action: .reduceAccessories,
            plannedExercises: [plan],
            snapshot: makeSnapshot(checkIns: [checkIn(daysAgo: 0, energy: 2, soreness: 4, stress: 3, motivation: 2)]),
            exercises: [],
            plannedMuscleFatigue: [],
            splitName: "Push",
            exerciseMetadata: [metadata]
        )
        let adjustedExercise = try XCTUnwrap(preview.adjustedExercises.first)

        XCTAssertEqual(adjustedExercise.targetSets, 2)
        XCTAssertTrue(adjustedExercise.notes?.localizedCaseInsensitiveContains("accessory") == true)
    }

    func testAccessoryClassificationFallsBackConservativelyWhenMetadataIsMissing() {
        let earlyUnknown = plannedExercise(name: "Mystery Press", exerciseId: UUID(), sets: 3)
        let warmup = PlannedWorkoutExercise(
            id: UUID(),
            exerciseId: UUID(),
            name: "Band Warm-up",
            targetSets: 1,
            minReps: 10,
            maxReps: 15,
            notes: "Optional activation."
        )

        let earlyClassification = adjustmentService.classify(exercise: earlyUnknown, index: 0, metadata: nil, splitName: "Push")
        let warmupClassification = adjustmentService.classify(exercise: warmup, index: 5, metadata: nil, splitName: "Push")

        XCTAssertEqual(earlyClassification.role, .primaryCompound)
        XCTAssertEqual(earlyClassification.source, .fallbackName)
        XCTAssertEqual(warmupClassification.role, .warmUpOrLowPriority)
        XCTAssertEqual(warmupClassification.source, .fallbackName)
    }

    func testTrendThresholdBoundaryIsDeterministic() {
        let checkIns = [
            checkIn(daysAgo: 0, energy: 4, soreness: 2, stress: 2, motivation: 4),
            checkIn(daysAgo: 1, energy: 3, soreness: 2, stress: 2, motivation: 4),
            checkIn(daysAgo: 7, energy: 3, soreness: 2, stress: 2, motivation: 4),
            checkIn(daysAgo: 8, energy: 3, soreness: 2, stress: 2, motivation: 4)
        ]

        let snapshot = makeSnapshot(checkIns: checkIns)

        XCTAssertEqual(snapshot.trends.energy.currentValue, 3.5)
        XCTAssertEqual(snapshot.trends.energy.previousValue, 3.0)
        XCTAssertEqual(snapshot.trends.energy.direction, .improving)
    }

    func testLowConfidenceRecommendationsAvoidAggressiveSuggestions() {
        let snapshot = makeSnapshot()
        let recommendations = adjustmentService.recommendations(
            for: snapshot,
            plannedExercises: [plannedExercise(name: "Bench Press", exerciseId: UUID(), sets: 4)],
            plannedMuscleFatigue: []
        )

        XCTAssertTrue(recommendations.contains { $0.action == .keepPlan && $0.isCoachSuggested })
        XCTAssertTrue(recommendations.contains { $0.action == .techniqueFocus && $0.isCoachSuggested })
        XCTAssertFalse(recommendations.contains { $0.action == .reduceTotalVolume && $0.isCoachSuggested })
        XCTAssertFalse(recommendations.contains { $0.action == .recoveryFocusedSession && $0.isCoachSuggested })
    }

    func testFeedbackCreationAndDiagnosticsSummariseLocalSignals() {
        let entry = CoachActionHistoryEntry(
            action: .reduceAccessories,
            outcome: .cancelled,
            createdAt: today,
            readinessCategory: .cautious,
            fatigueRiskLevel: .high,
            confidence: .medium,
            shortReason: "Preview closed.",
            workoutName: "Push",
            splitName: "Push",
            beforeTotalSets: 18,
            afterTotalSets: 15
        )
        let feedbackService = CoachRecommendationFeedbackService()
        let feedback = feedbackService.makeFeedback(
            for: entry,
            tags: [.tooAggressive, .feltInaccurate, .preferredRecovery],
            note: "Wanted a softer option.",
            date: today
        )
        let context = CoachCalibrationContext(
            actionHistory: [entry],
            feedback: [feedback],
            deloadBlocks: [],
            exerciseMetadata: []
        )

        XCTAssertEqual(feedback.historyEntryId, entry.id)
        XCTAssertEqual(feedback.action, .reduceAccessories)
        XCTAssertTrue(feedback.tags.contains(.tooAggressive))
        XCTAssertEqual(feedback.note, "Wanted a softer option.")
        XCTAssertTrue(feedbackService.feedbackSummary([feedback]).localizedCaseInsensitiveContains("lighter confidence"))
        XCTAssertTrue(feedbackService.calibrationDiagnostics(from: context).contains { $0.localizedCaseInsensitiveContains("too aggressive") })
    }

    func testCalibrationLowersConfidenceAndExplainsFeedbackInfluence() {
        let feedback = CoachRecommendationFeedback(
            createdAt: today,
            action: .reduceTotalVolume,
            tags: [.tooAggressive, .feltInaccurate],
            splitName: "Legs",
            readinessCategory: .low,
            fatigueRiskLevel: .high,
            confidence: .high
        )
        let context = CoachCalibrationContext(
            actionHistory: [],
            feedback: [feedback],
            deloadBlocks: [],
            exerciseMetadata: []
        )

        let result = adjustmentService.calibratedRecommendation(
            action: .reduceTotalVolume,
            baseConfidence: .high,
            calibration: context
        )

        XCTAssertEqual(result.confidence, .medium)
        XCTAssertTrue(result.summarySuffix?.localizedCaseInsensitiveContains("optional") == true)
        XCTAssertTrue(result.reason?.localizedCaseInsensitiveContains("too aggressive") == true)
    }

    func testRepeatedDeloadCancellationsReduceUrgencyUnlessFatigueIsReviewed() {
        let entries = [
            CoachActionHistoryEntry(
                action: .deloadStyleSession,
                outcome: .cancelled,
                createdAt: today,
                readinessCategory: .low,
                fatigueRiskLevel: .high,
                confidence: .medium,
                shortReason: "Cancelled",
                splitName: "Legs"
            ),
            CoachActionHistoryEntry(
                action: .deloadStyleSession,
                outcome: .bypassed,
                createdAt: date(daysAgo: 1, hour: 18),
                readinessCategory: .cautious,
                fatigueRiskLevel: .high,
                confidence: .medium,
                shortReason: "Bypassed",
                splitName: "Pull"
            )
        ]
        let context = CoachCalibrationContext(
            actionHistory: entries,
            feedback: [],
            deloadBlocks: [],
            exerciseMetadata: []
        )

        let result = adjustmentService.calibratedRecommendation(
            action: .deloadStyleSession,
            baseConfidence: .medium,
            calibration: context
        )

        XCTAssertEqual(result.confidence, .low)
        XCTAssertTrue(result.summarySuffix?.localizedCaseInsensitiveContains("review step") == true)
    }

    func testCoachActionHistoryFilteringByOutcomeActionAndContext() {
        let entries = [
            CoachActionHistoryEntry(
                action: .reduceAccessories,
                outcome: .applied,
                createdAt: today,
                readinessCategory: .cautious,
                fatigueRiskLevel: .high,
                confidence: .medium,
                shortReason: "Applied",
                splitName: "Push",
                beforeTotalSets: 18,
                afterTotalSets: 15
            ),
            CoachActionHistoryEntry(
                action: .keepPlan,
                outcome: .bypassed,
                createdAt: date(daysAgo: 1, hour: 18),
                readinessCategory: .peak,
                fatigueRiskLevel: .low,
                confidence: .high,
                shortReason: "Original",
                splitName: "Pull",
                beforeTotalSets: 14,
                afterTotalSets: 14
            )
        ]
        let filtered = CoachActionHistoryFilterService().filter(
            entries,
            using: CoachActionHistoryFilter(
                outcome: .applied,
                action: .reduceAccessories,
                splitName: "Push",
                readinessCategory: .cautious,
                fatigueRiskLevel: .high
            )
        )

        XCTAssertEqual(filtered.map(\.id), [entries[0].id])
        XCTAssertEqual(CoachActionHistoryFilterService().filter(entries, using: .empty).count, 2)
    }

    func testDeloadCalendarPreviewEstimatesTrainingImpact() {
        let splits = [
            TrainingSplit(name: "Push", splitType: .pushPullLegs, daysPerWeek: 6),
            TrainingSplit(name: "Pull", splitType: .pushPullLegs, daysPerWeek: 6),
            TrainingSplit(name: "Legs", splitType: .pushPullLegs, daysPerWeek: 6)
        ]
        let plan = ManualDeloadPlan(duration: .sevenDays, volumeReduction: .fortyPercent, focus: .techniqueOnly)
        let preview = CoachDeloadCalendarReviewService(calendar: calendar).preview(
            plan: plan,
            startDate: today,
            activeSplits: splits
        )

        XCTAssertEqual(preview.plan, plan)
        XCTAssertEqual(preview.estimatedAffectedTrainingDays, 6)
        XCTAssertEqual(preview.affectedSplitNames, ["Push", "Pull", "Legs"])
        XCTAssertTrue(preview.volumeSummary.localizedCaseInsensitiveContains("40%"))
        XCTAssertTrue(preview.focusExplanation.localizedCaseInsensitiveContains("clean reps"))
    }

    func testCoachDiagnosticsExposeMissingInputsAndAdaptiveReason() {
        let snapshot = makeSnapshot()

        XCTAssertEqual(snapshot.diagnostics.confidence, .low)
        XCTAssertFalse(snapshot.diagnostics.missingDataReasons.isEmpty)
        XCTAssertTrue(snapshot.diagnostics.adaptiveActionReason.localizedCaseInsensitiveContains(snapshot.adaptiveGuidance.mode.displayName))
    }

    func testCoachDiagnosticsExposeMetadataFeedbackDeloadAndHistoryInfluence() {
        let exerciseId = UUID()
        let metadata = CoachExerciseMetadata(
            exerciseId: exerciseId,
            role: .accessory,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            splitClassification: .push,
            priority: .normal
        )
        let historyEntry = CoachActionHistoryEntry(
            action: .reduceAccessories,
            outcome: .applied,
            createdAt: today,
            readinessCategory: .cautious,
            fatigueRiskLevel: .high,
            confidence: .medium,
            shortReason: "Applied",
            splitName: "Push"
        )
        let feedback = CoachRecommendationFeedback(
            createdAt: today,
            historyEntryId: historyEntry.id,
            action: .reduceAccessories,
            tags: [.feltInaccurate],
            splitName: "Push",
            readinessCategory: .cautious,
            fatigueRiskLevel: .high,
            confidence: .medium
        )
        let block = SavedCoachDeloadBlock(
            startsAt: today,
            endsAt: today,
            duration: .threeDays,
            volumeReduction: .twentyFivePercent,
            focus: .maintainFrequency,
            reason: "Fatigue review.",
            splitName: "Push"
        )

        let snapshot = makeSnapshot(
            plannedExerciseIDs: [exerciseId],
            exerciseMetadata: [metadata],
            coachActionHistory: [historyEntry],
            recommendationFeedback: [feedback],
            savedDeloadBlocks: [block]
        )

        XCTAssertTrue(snapshot.diagnostics.exerciseMetadataInputs.contains { $0.localizedCaseInsensitiveContains("accessory") })
        XCTAssertTrue(snapshot.diagnostics.feedbackInfluence.contains { $0.localizedCaseInsensitiveContains("feedback") })
        XCTAssertTrue(snapshot.diagnostics.confidenceAdjustmentReasons.contains { $0.localizedCaseInsensitiveContains("inaccurate") })
        XCTAssertTrue(snapshot.diagnostics.deloadBlockInfluence?.localizedCaseInsensitiveContains("active") == true)
        XCTAssertTrue(snapshot.diagnostics.actionHistoryInfluence?.localizedCaseInsensitiveContains("coach actions") == true)
    }

    func testCoachPreferencesDefaultsAndCalibrationInfluence() {
        let preferences = CoachPreferences()
        XCTAssertEqual(preferences.aggressiveness, .balanced)
        XCTAssertEqual(preferences.deloadWording, .gentle)
        XCTAssertFalse(preferences.showDiagnostics)

        var snapshot = CoachPreferencesSnapshot.default
        snapshot.aggressiveness = .conservative
        snapshot.reductionPreference = .protectPriorityLifts
        let context = CoachCalibrationContext(
            actionHistory: [],
            feedback: [],
            deloadBlocks: [],
            exerciseMetadata: [],
            preferences: snapshot
        )

        let result = adjustmentService.calibratedRecommendation(
            action: .reduceTotalVolume,
            baseConfidence: .high,
            calibration: context
        )

        XCTAssertEqual(result.confidence, .medium)
        XCTAssertTrue(result.reason?.localizedCaseInsensitiveContains("conservative") == true)
    }

    func testSplitMetadataProtectsCompoundsDuringVolumeReduction() throws {
        let bench = exercise(name: "Bench Press", primary: .chest, secondary: [.triceps], compound: true)
        let fly = exercise(name: "Cable Fly", primary: .chest, compound: false)
        let splitMetadata = CoachSplitMetadataSnapshot(
            splitId: UUID(),
            splitName: "Push",
            priority: .high,
            plannedIntensity: .hard,
            primaryGoal: .strength,
            expectedFatigue: .moderate,
            protectCompounds: true,
            accessoriesFlexible: true,
            preferredAdjustmentStyle: .protectMainLifts,
            userNote: nil
        )
        let preview = adjustmentService.makePreview(
            action: .reduceTotalVolume,
            plannedExercises: [
                plannedExercise(name: "Bench Press", exerciseId: bench.id, sets: 4),
                plannedExercise(name: "Cable Fly", exerciseId: fly.id, sets: 3)
            ],
            snapshot: makeSnapshot(exercises: [bench, fly]),
            exercises: [bench, fly],
            plannedMuscleFatigue: [],
            splitName: "Push",
            preferences: .default,
            splitMetadata: splitMetadata
        )

        let adjustedBench = try XCTUnwrap(preview.adjustedExercises.first { $0.exerciseNameSnapshot == "Bench Press" })
        let adjustedFly = try XCTUnwrap(preview.adjustedExercises.first { $0.exerciseNameSnapshot == "Cable Fly" })
        XCTAssertEqual(adjustedBench.targetSets, 4)
        XCTAssertLessThan(adjustedFly.targetSets, 3)
        XCTAssertTrue(preview.contributingSignals.contains { $0.localizedCaseInsensitiveContains("split intent") })
    }

    func testBulkMetadataReviewAndOverwriteBehaviour() throws {
        let bench = exercise(name: "Bench Press", primary: .chest, compound: true)
        let fly = exercise(name: "Cable Fly", primary: .chest, compound: false)
        let existing = CoachExerciseMetadata(
            exerciseId: bench.id,
            role: .priorityLift,
            primaryMuscleGroup: .chest,
            movementPattern: .push,
            priority: .high
        )
        let bulkService = CoachBulkMetadataService()
        let update = CoachBulkMetadataUpdate(role: .accessory, priority: .low)

        let review = bulkService.review(
            scope: .selectedExercises,
            selectedExerciseIds: [bench.id, fly.id],
            exercises: [bench, fly],
            existingMetadata: [existing],
            update: update,
            overwriteExisting: false
        )

        XCTAssertEqual(review.willCreateCount, 1)
        XCTAssertEqual(review.willUpdateCount, 0)
        XCTAssertEqual(review.skippedExistingCount, 1)
        XCTAssertNil(bulkService.updatedDraft(for: bench, existingMetadata: existing, update: update, overwriteExisting: false))

        let overwrittenDraft = try XCTUnwrap(bulkService.updatedDraft(for: bench, existingMetadata: existing, update: update, overwriteExisting: true))
        XCTAssertEqual(overwrittenDraft.role, .accessory)
        XCTAssertEqual(overwrittenDraft.priority, .low)
    }

    func testWhyThisChangedExplanationIncludesPreferencesAndMetadata() {
        let fly = exercise(name: "Cable Fly", primary: .chest, compound: false)
        var preferences = CoachPreferencesSnapshot.default
        preferences.aggressiveness = .assertive
        preferences.reductionPreference = .reduceAccessoriesFirst
        let splitMetadata = CoachSplitMetadataSnapshot.defaultFor(splitId: UUID(), splitName: "Push")
        let preview = adjustmentService.makePreview(
            action: .reduceAccessories,
            plannedExercises: [plannedExercise(name: "Cable Fly", exerciseId: fly.id, sets: 3)],
            snapshot: makeSnapshot(exercises: [fly]),
            exercises: [fly],
            plannedMuscleFatigue: [],
            splitName: "Push",
            preferences: preferences,
            splitMetadata: splitMetadata
        )

        let explanation = CoachWorkoutChangeExplanationService().explanation(
            for: preview,
            preferences: preferences,
            splitMetadata: splitMetadata
        )

        XCTAssertEqual(explanation.originalTotalSets, 3)
        XCTAssertEqual(explanation.adjustedTotalSets, 2)
        XCTAssertEqual(explanation.exercisesReduced, ["Cable Fly"])
        XCTAssertTrue(explanation.preferenceInfluence?.localizedCaseInsensitiveContains("accessories") == true)
        XCTAssertTrue(explanation.metadataInfluence?.localizedCaseInsensitiveContains("Push") == true)
    }

    func testCoachHistoryCSVExportIncludesFeedbackAndSetChanges() {
        let entry = CoachActionHistoryEntry(
            action: .reduceAccessories,
            outcome: .applied,
            createdAt: today,
            readinessCategory: .cautious,
            fatigueRiskLevel: .high,
            confidence: .medium,
            shortReason: "Accessory trim applied.",
            splitName: "Push",
            beforeTotalSets: 12,
            afterTotalSets: 10
        )
        let feedback = CoachRecommendationFeedback(
            historyEntryId: entry.id,
            action: .reduceAccessories,
            tags: [.helpful, .feltAccurate],
            splitName: "Push",
            readinessCategory: .cautious,
            fatigueRiskLevel: .high,
            confidence: .medium
        )

        let csv = CoachHistoryExportService().csv(entries: [entry], feedback: [feedback])

        XCTAssertTrue(csv.contains("action_type,outcome"))
        XCTAssertTrue(csv.contains("Reduce accessories"))
        XCTAssertTrue(csv.contains("Helpful; Felt accurate"))
        XCTAssertTrue(csv.contains(",12,10"))
    }

    func testDiagnosticsExposePreferencesSplitMetadataAndUrgency() {
        var preferences = CoachPreferencesSnapshot.default
        preferences.aggressiveness = .conservative
        preferences.recommendationFrequency = .minimal
        let split = TrainingSplit(name: "Legs", splitType: .pushPullLegs, daysPerWeek: 2)
        let splitMetadata = CoachSplitMetadata(
            splitId: split.id,
            splitName: "Legs",
            priority: .high,
            plannedIntensity: .hard,
            primaryGoal: .strength,
            expectedFatigue: .high,
            protectCompounds: true,
            accessoriesFlexible: false,
            preferredAdjustmentStyle: .protectMainLifts
        )

        let snapshot = makeSnapshot(
            activeSplits: [split],
            checkIns: [checkIn(daysAgo: 0, energy: 3, soreness: 3, stress: 3, motivation: 3)],
            coachPreferences: preferences,
            splitMetadata: [splitMetadata]
        )

        XCTAssertTrue(snapshot.diagnostics.coachPreferenceInfluence.contains { $0.localizedCaseInsensitiveContains("conservative") })
        XCTAssertTrue(snapshot.diagnostics.splitMetadataInfluence.contains { $0.localizedCaseInsensitiveContains("Legs") })
        XCTAssertTrue(snapshot.diagnostics.urgencyAdjustmentReasons.contains { $0.localizedCaseInsensitiveContains("conservative") })
    }

    private func makeReadiness(
        for date: Date? = nil,
        sleepSessions: [SleepSession] = [],
        napSessions: [NapSession] = [],
        hydrationEntries: [HydrationEntry] = [],
        completedWorkouts: [WorkoutSession] = [],
        foodLogs: [FoodLogEntry] = [],
        checkIns: [DailyCoachCheckIn] = [],
        nutritionGoal: NutritionGoal = .empty
    ) -> ReadinessScore {
        service.readiness(
            for: date ?? today,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: .default,
            hydrationTargetML: 2_500,
            nutritionGoal: nutritionGoal
        )
    }

    private func makeSnapshot(
        exercises: [Exercise] = [],
        plannedExerciseIDs: [UUID] = [],
        activeSplits: [TrainingSplit] = [],
        sleepSessions: [SleepSession] = [],
        napSessions: [NapSession] = [],
        hydrationEntries: [HydrationEntry] = [],
        completedWorkouts: [WorkoutSession] = [],
        foodLogs: [FoodLogEntry] = [],
        checkIns: [DailyCoachCheckIn] = [],
        nutritionGoal: NutritionGoal = .empty,
        exerciseMetadata: [CoachExerciseMetadata] = [],
        coachActionHistory: [CoachActionHistoryEntry] = [],
        recommendationFeedback: [CoachRecommendationFeedback] = [],
        savedDeloadBlocks: [SavedCoachDeloadBlock] = [],
        coachPreferences: CoachPreferencesSnapshot = .default,
        splitMetadata: [CoachSplitMetadata] = []
    ) -> CoachIntelligenceSnapshot {
        service.snapshot(
            for: today,
            activeSplits: activeSplits,
            exercises: exercises,
            plannedExerciseIDs: plannedExerciseIDs,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: .default,
            hydrationTargetML: 2_500,
            nutritionGoal: nutritionGoal,
            exerciseMetadata: exerciseMetadata,
            coachActionHistory: coachActionHistory,
            recommendationFeedback: recommendationFeedback,
            savedDeloadBlocks: savedDeloadBlocks,
            coachPreferences: coachPreferences,
            splitMetadata: splitMetadata
        )
    }

    private func exercise(
        id: UUID = UUID(),
        name: String,
        primary: MuscleGroup,
        secondary: [MuscleGroup] = [],
        compound: Bool
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: primary,
            secondaryMuscleGroups: secondary,
            movementPattern: primary == .back ? .pull : .push,
            equipment: .barbell,
            isCompound: compound
        )
    }

    private func workout(
        daysAgo: Int,
        exercise: Exercise,
        setCount: Int,
        weight: Double,
        reps: Int,
        rpe: Double,
        difficulty: Int
    ) -> WorkoutSession {
        let sessionDate = date(daysAgo: daysAgo, hour: 18)
        let session = WorkoutSession(
            date: sessionDate,
            splitNameSnapshot: "Fixture",
            durationMinutes: 70,
            perceivedDifficulty: difficulty,
            completed: true
        )
        let log = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: setCount,
            minReps: 6,
            maxReps: 10
        )
        log.setLogs = (1...setCount).map { index in
            let set = SetLog(
                exerciseLogId: log.id,
                setNumber: index,
                weight: weight,
                reps: reps,
                rpe: rpe,
                isWarmup: false,
                completed: true
            )
            set.exerciseLog = log
            return set
        }
        log.workoutSession = session
        session.exerciseLogs = [log]
        return session
    }

    private func checkIn(daysAgo: Int, energy: Int, soreness: Int, stress: Int, motivation: Int) -> DailyCoachCheckIn {
        DailyCoachCheckIn(
            date: date(daysAgo: daysAgo, hour: 9),
            energy: energy,
            soreness: soreness,
            stress: stress,
            motivation: motivation,
            calendar: calendar
        )
    }

    private func sleep(daysAgo: Int, minutes: Int, quality: Int) -> SleepSession {
        let wake = date(daysAgo: daysAgo, hour: 7)
        let start = wake.addingTimeInterval(TimeInterval(-minutes * 60))
        return SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: wake,
            durationMinutes: minutes,
            qualityRating: quality,
            source: .manual,
            confidence: .high,
            status: .completed
        )
    }

    private func hydration(daysAgo: Int, amount: Int) -> HydrationEntry {
        HydrationEntry(amountML: amount, loggedAt: date(daysAgo: daysAgo, hour: 10))
    }

    private func food(daysAgo: Int, calories: Double, protein: Double) -> FoodLogEntry {
        FoodLogEntry(
            foodItemId: UUID(),
            foodNameSnapshot: "Fixture meal",
            consumedAmount: 1,
            amountUnit: .serving,
            mealType: .postWorkout,
            caloriesSnapshot: calories,
            proteinSnapshot: protein,
            carbsSnapshot: 250,
            fatSnapshot: 70,
            loggedAt: date(daysAgo: daysAgo, hour: 12)
        )
    }

    private func plannedExercise(name: String, exerciseId: UUID, sets: Int) -> PlannedWorkoutExercise {
        PlannedWorkoutExercise(
            id: exerciseId,
            exerciseId: exerciseId,
            name: name,
            targetSets: sets,
            minReps: 6,
            maxReps: 10,
            notes: nil
        )
    }

    private func date(daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: today))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }
}
