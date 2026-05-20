import Foundation

struct LocalBackupExportService {
    private let appName = "Peakline"
    private let schemaVersion = 1

    func exportJSON(
        workouts: [WorkoutSession],
        exercises: [Exercise],
        splits: [TrainingSplit]
    ) throws -> URL {
        let envelope = PeaklineExportEnvelope(
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            appName: appName,
            appVersion: appVersion,
            workouts: workouts
                .sorted { $0.date < $1.date }
                .map(WorkoutSessionExportDTO.init),
            exercises: exercises
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(ExerciseExportDTO.init),
            splits: splits
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(TrainingSplitExportDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(envelope)
        let url = exportURL(prefix: "Peakline-Workout-Backup", fileExtension: "json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func exportCSV(workouts: [WorkoutSession]) throws -> URL {
        let csv = WorkoutCSVExporter().makeCSV(from: workouts)
        let url = exportURL(prefix: "Peakline-Workout-Export", fileExtension: "csv")
        try csv.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }

    private var appVersion: String? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return nil
        }
    }

    private func exportURL(prefix: String, fileExtension: String) -> URL {
        let date = Date().formatted(.iso8601.year().month().day())
        let filename = "\(prefix)-\(date).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

private extension WorkoutSessionExportDTO {
    init(_ session: WorkoutSession) {
        id = session.id
        date = session.date
        splitId = session.splitId
        splitName = session.splitNameSnapshot
        workoutMode = session.workoutModeSnapshot
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationMinutes = session.durationMinutes
        durationSeconds = session.durationSeconds
        perceivedDifficulty = session.perceivedDifficulty
        notes = session.notes
        completed = session.completed
        exerciseLogs = session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(ExerciseLogExportDTO.init)
    }
}

private extension ExerciseLogExportDTO {
    init(_ exerciseLog: ExerciseLog) {
        id = exerciseLog.id
        exerciseId = exerciseLog.exerciseId
        exerciseName = exerciseLog.exerciseNameSnapshot
        orderIndex = exerciseLog.orderIndex
        targetSets = exerciseLog.targetSets
        minReps = exerciseLog.minReps
        maxReps = exerciseLog.maxReps
        notes = exerciseLog.notes
        setLogs = exerciseLog.setLogs
            .sorted { $0.setNumber < $1.setNumber }
            .map(SetLogExportDTO.init)
    }
}

private extension SetLogExportDTO {
    init(_ setLog: SetLog) {
        id = setLog.id
        setNumber = setLog.setNumber
        weight = setLog.weight
        reps = setLog.reps
        rpe = setLog.rpe
        isWarmup = setLog.isWarmup
        completed = setLog.completed
    }
}

private extension ExerciseExportDTO {
    init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        primaryMuscleGroup = exercise.primaryMuscleGroup.rawValue
        secondaryMuscleGroups = exercise.secondaryMuscleGroups.map(\.rawValue)
        movementPattern = exercise.movementPattern.rawValue
        equipment = exercise.equipment.rawValue
        isCompound = exercise.isCompound
        isArchived = exercise.isArchived
        createdAt = exercise.createdAt
        updatedAt = exercise.updatedAt
    }
}

private extension TrainingSplitExportDTO {
    init(_ split: TrainingSplit) {
        id = split.id
        name = split.name
        splitType = split.splitType.rawValue
        createdAt = split.createdAt
        updatedAt = split.updatedAt
        isActive = split.isActive
        daysPerWeek = split.daysPerWeek
        exercises = split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(SplitExerciseExportDTO.init)
    }
}

private extension SplitExerciseExportDTO {
    init(_ splitExercise: SplitExercise) {
        id = splitExercise.id
        splitId = splitExercise.splitId
        exerciseId = splitExercise.exerciseId
        exerciseName = splitExercise.exerciseNameSnapshot
        orderIndex = splitExercise.orderIndex
        targetSets = splitExercise.targetSets
        minReps = splitExercise.minReps
        maxReps = splitExercise.maxReps
        restSeconds = splitExercise.restSeconds
        notes = splitExercise.notes
    }
}

private extension WorkoutSession {
    var workoutModeSnapshot: String? {
        let pieces = splitNameSnapshot.components(separatedBy: " - ")
        guard pieces.count > 1 else { return nil }
        return pieces.last
    }
}
