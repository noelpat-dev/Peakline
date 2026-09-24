import XCTest
@testable import GymTracker

final class CompleteQueryServiceTests: XCTestCase {
    func testCollectReadsBeyondWarmPrefix() throws {
        let values = Array(0..<421)
        let result = try CompleteQueryService.collect(pageSize: 37) { offset, limit in
            Array(values.dropFirst(offset).prefix(limit))
        }
        XCTAssertEqual(result, values)
    }

    func testCollectHandlesEmptyAndExactPageBoundaries() throws {
        XCTAssertEqual(
            try CompleteQueryService.collect(pageSize: 3) { _, _ -> [Int] in [] },
            [Int]()
        )
        let values = Array(0..<6)
        let result = try CompleteQueryService.collect(pageSize: 3) { offset, limit in
            Array(values.dropFirst(offset).prefix(limit))
        }
        XCTAssertEqual(result, values)
    }

    func testSavedFoodSearchReachesFoodBeyondWarmCataloguePrefix() {
        let foods = (0..<241).map { SavedFoodSnapshot(FoodItem(name: "Food \($0)")) }
        let catalog = SavedFoodCatalogSnapshot(foods: foods)

        XCTAssertEqual(catalog.foods.count, 241)
        XCTAssertEqual(catalog.filtered(by: "Food 240").count, 1)
    }

    func testHistoryFilterMatchesSparseOlderWorkoutSnapshot() {
        let oldWorkout = HistoryWorkoutSnapshot(
            id: UUID(), date: Date(timeIntervalSince1970: 1), splitName: "Pull",
            startedAt: nil, endedAt: nil, durationMinutes: nil, durationSeconds: nil,
            accumulatedPausedSeconds: 0, rating: 5, notes: nil,
            exercises: [.init(name: "Old Pulldown", orderIndex: 0, sets: [
                .init(completed: true, weight: 40, reps: 8, rpe: nil)
            ])]
        )
        let filtered = HistoryDisplaySnapshotBuilder.build(
            workouts: [oldWorkout],
            filters: HistoryFilters(splitName: nil, exerciseNameQuery: "Old Pulldown")
        )

        XCTAssertEqual(filtered.sessionRows.count, 1)
    }
}
