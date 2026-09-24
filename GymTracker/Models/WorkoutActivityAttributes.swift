import ActivityKit
import Foundation

/// The shared payload used by the app and the Live Activity extension.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct PRFlash: Codable, Hashable {
        let exerciseName: String
        let weightKg: Double
        let reps: Int
        let until: Date
    }

    struct ContentState: Codable, Hashable {
        let exerciseName: String
        let setIndexInExercise: Int
        let setsInExercise: Int
        let overallSetIndex: Int
        let overallSetCount: Int
        let completedSetCount: Int
        let exercisesLeft: Int
        let nextWeightKg: Double?
        let nextReps: Int?
        var restEndsAt: Date?
        let metresGained: Int
        var pr: PRFlash?
        /// Use `metric` or `imperial`.
        let unitSystem: String
        let pausedAt: Date?
        let accumulatedPausedSeconds: Int
    }

    let sessionID: UUID
    let sessionTitle: String
    let startedAt: Date
}
