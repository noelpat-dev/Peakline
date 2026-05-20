import Foundation

struct PeaklineExportEnvelope: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let appName: String
    let appVersion: String?
    let workouts: [WorkoutSessionExportDTO]
    let exercises: [ExerciseExportDTO]
    let splits: [TrainingSplitExportDTO]
}

struct WorkoutSessionExportDTO: Codable {
    let id: UUID
    let date: Date
    let splitId: UUID?
    let splitName: String
    let workoutMode: String?
    let startedAt: Date?
    let endedAt: Date?
    let durationMinutes: Int?
    let durationSeconds: Int?
    let perceivedDifficulty: Int?
    let notes: String?
    let completed: Bool
    let exerciseLogs: [ExerciseLogExportDTO]
}

struct ExerciseLogExportDTO: Codable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let orderIndex: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?
    let setLogs: [SetLogExportDTO]
}

struct SetLogExportDTO: Codable {
    let id: UUID
    let setNumber: Int
    let weight: Double
    let reps: Int
    let rpe: Double?
    let isWarmup: Bool
    let completed: Bool
}

struct ExerciseExportDTO: Codable {
    let id: UUID
    let name: String
    let primaryMuscleGroup: String
    let secondaryMuscleGroups: [String]
    let movementPattern: String
    let equipment: String
    let isCompound: Bool
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct TrainingSplitExportDTO: Codable {
    let id: UUID
    let name: String
    let splitType: String
    let createdAt: Date
    let updatedAt: Date
    let isActive: Bool
    let daysPerWeek: Int
    let exercises: [SplitExerciseExportDTO]
}

struct SplitExerciseExportDTO: Codable {
    let id: UUID
    let splitId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let orderIndex: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let restSeconds: Int?
    let notes: String?
}
