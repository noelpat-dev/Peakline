import XCTest
@testable import GymTracker

@MainActor
final class NutritionExportReliabilityTests: XCTestCase {
    func testEmptyNutritionGoalHasStableTimestampForDashboardSignatures() {
        let first = NutritionGoal.empty
        let second = NutritionGoal.empty

        XCTAssertFalse(first.hasTargets)
        XCTAssertEqual(first.updatedAt, second.updatedAt)
        XCTAssertEqual(first.updatedAt.timeIntervalSince1970, 0)
    }

    func testNutritionCalculatorScalesClampsAndTotalsSnapshots() {
        let calculator = NutritionCalculatorService()
        let food = FoodItem(
            name: "Greek Yogurt",
            caloriesPer100g: 120,
            proteinPer100g: 10,
            carbsPer100g: 4,
            fatPer100g: 3,
            sugarPer100g: 2,
            fibrePer100g: nil,
            saltPer100g: 0.1
        )

        let scaled = calculator.calculate(for: food, consumedAmount: 150, unit: .grams)
        XCTAssertEqual(scaled.calories, 180, accuracy: 0.001)
        XCTAssertEqual(scaled.protein, 15, accuracy: 0.001)
        XCTAssertEqual(scaled.sugar, 3)
        XCTAssertNil(scaled.fibre)

        let clamped = calculator.calculate(for: food, consumedAmount: -50, unit: .grams)
        XCTAssertEqual(clamped.calories, 0)
        XCTAssertEqual(clamped.protein, 0)

        let totals = calculator.totals(from: [
            foodLog(calories: 100, protein: 10, carbs: 20, fat: 2, sugar: nil),
            foodLog(calories: 250, protein: 25, carbs: 30, fat: 8, sugar: 4)
        ])
        XCTAssertEqual(totals.calories, 350)
        XCTAssertEqual(totals.protein, 35)
        XCTAssertEqual(totals.sugar, 4)
        XCTAssertNil(totals.fibre)
    }

    func testHydrationSummaryFiltersByDateAndStatusThresholds() {
        let calendar = utcCalendar()
        let targetDay = date(day: 8, hour: 12)
        let entries = [
            HydrationEntry(amountML: 500, loggedAt: date(day: 8, hour: 8)),
            HydrationEntry(amountML: 750, loggedAt: date(day: 8, hour: 14)),
            HydrationEntry(amountML: 1_000, loggedAt: date(day: 7, hour: 20))
        ]

        let summary = HydrationService().summary(for: targetDay, entries: entries, targetML: 2_500, calendar: calendar)

        XCTAssertEqual(summary.totalML, 1_250)
        XCTAssertEqual(summary.targetML, 2_500)
        XCTAssertEqual(summary.status, .behind)
        XCTAssertEqual(summary.remainingML, 1_250)
        XCTAssertEqual(summary.progress, 0.5, accuracy: 0.001)
    }

    func testNutritionComparisonFlagsMajorDifferencesWithoutGuessingFinalValue() throws {
        let result = NutritionComparisonService().compare(
            imported: NutritionSourceSnapshot(
                source: .openFoodFacts,
                basis: .per100g,
                calories: 420,
                protein: 8,
                confidence: 0.9
            ),
            label: NutritionSourceSnapshot(
                source: .labelScan,
                basis: .per100g,
                calories: 210,
                protein: 8.2,
                confidence: 0.9
            ),
            local: nil
        )

        let calories = try XCTUnwrap(result.rows.first { $0.nutrient == .calories })
        XCTAssertEqual(calories.status, .majorDifference)
        XCTAssertNil(calories.finalValue)

        let protein = try XCTUnwrap(result.rows.first { $0.nutrient == .protein })
        XCTAssertEqual(protein.status, .match)
        XCTAssertEqual(protein.finalValue, 8.2)
    }

    func testWorkoutCSVExporterSortsRowsAndEscapesUserData() {
        let older = workout(
            date: date(day: 7, hour: 10),
            splitName: "Push - Full",
            exerciseName: "Bench \"Press\"",
            weight: 100,
            reps: 6
        )
        let newer = workout(
            date: date(day: 8, hour: 10),
            splitName: "Pull - Quick",
            exerciseName: "Cable Row, Close Grip",
            weight: 80,
            reps: 10
        )

        let csv = WorkoutCSVExporter().makeCSV(from: [newer, older])

        XCTAssertTrue(csv.hasPrefix("Date,Split,Workout Mode"))
        XCTAssertTrue(csv.contains("\"Push\",\"Full\",\"Bench \"\"Press\"\"\""))
        XCTAssertTrue(csv.contains("\"Pull\",\"Quick\",\"Cable Row, Close Grip\""))
        XCTAssertLessThan(
            try XCTUnwrap(csv.range(of: "Bench \"\"Press\"\"")?.lowerBound),
            try XCTUnwrap(csv.range(of: "Cable Row, Close Grip")?.lowerBound)
        )
    }

    private func foodLog(calories: Double, protein: Double, carbs: Double, fat: Double, sugar: Double?) -> FoodLogEntry {
        FoodLogEntry(
            foodItemId: UUID(),
            foodNameSnapshot: "Food",
            consumedAmount: 100,
            amountUnit: .grams,
            mealType: .snack,
            caloriesSnapshot: calories,
            proteinSnapshot: protein,
            carbsSnapshot: carbs,
            fatSnapshot: fat,
            sugarSnapshot: sugar
        )
    }

    private func workout(date: Date, splitName: String, exerciseName: String, weight: Double, reps: Int) -> WorkoutSession {
        WorkoutSession(
            date: date,
            splitNameSnapshot: splitName,
            durationSeconds: 1_800,
            perceivedDifficulty: 4,
            completed: true,
            exerciseLogs: [
                ExerciseLog(
                    exerciseId: UUID(),
                    exerciseNameSnapshot: exerciseName,
                    orderIndex: 0,
                    targetSets: 1,
                    minReps: 6,
                    maxReps: 10,
                    setLogs: [
                        SetLog(setNumber: 1, weight: weight, reps: reps, rpe: 8, completed: true)
                    ]
                )
            ]
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
