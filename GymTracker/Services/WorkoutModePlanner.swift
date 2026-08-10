import Foundation

enum WorkoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case quick
    case recovery
    case heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full:
            return "Full"
        case .quick:
            return "Quick"
        case .recovery:
            return "Recovery"
        case .heavy:
            return "Heavy"
        }
    }

    var subtitle: String {
        switch self {
        case .full:
            return "Normal plan"
        case .quick:
            return "Main lifts only"
        case .recovery:
            return "Lower volume"
        case .heavy:
            return "Load focus"
        }
    }

    var systemImage: String {
        switch self {
        case .full:
            return "figure.strengthtraining.traditional"
        case .quick:
            return "timer"
        case .recovery:
            return "leaf"
        case .heavy:
            return "bolt.fill"
        }
    }
}

struct PlannedWorkoutExercise: Identifiable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?

    var exerciseNameSnapshot: String { name }
}

struct WorkoutLaunchExerciseDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let orderIndex: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?

    init(_ exercise: PlannedWorkoutExercise, orderIndex: Int) {
        id = exercise.id
        exerciseId = exercise.exerciseId
        name = exercise.exerciseNameSnapshot
        self.orderIndex = orderIndex
        targetSets = exercise.targetSets
        minReps = exercise.minReps
        maxReps = exercise.maxReps
        notes = exercise.notes
    }
}

struct WorkoutLaunchDraft: Hashable, Sendable {
    let splitId: UUID
    let splitNameSnapshot: String
    let exercises: [WorkoutLaunchExerciseDraft]

    init(
        splitId: UUID,
        splitName: String,
        modeLabel: String,
        exercises: [PlannedWorkoutExercise]
    ) {
        self.splitId = splitId
        splitNameSnapshot = "\(splitName) - \(modeLabel)"
        self.exercises = exercises.enumerated().map {
            WorkoutLaunchExerciseDraft($0.element, orderIndex: $0.offset)
        }
    }

    @MainActor
    func makeSession(startedAt: Date = .now) -> WorkoutSession {
        let session = WorkoutSession(
            date: startedAt,
            splitId: splitId,
            splitNameSnapshot: splitNameSnapshot,
            startedAt: startedAt
        )
        session.exerciseLogs = exercises.map { exercise in
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: exercise.exerciseId,
                exerciseNameSnapshot: exercise.name,
                orderIndex: exercise.orderIndex,
                targetSets: exercise.targetSets,
                minReps: exercise.minReps,
                maxReps: exercise.maxReps,
                notes: exercise.notes
            )
            log.workoutSession = session
            return log
        }
        return session
    }
}

enum WorkoutPreviewOrderReducer {
    static func move(
        _ ids: [UUID],
        sourceID: UUID,
        destinationID: UUID
    ) -> [UUID] {
        guard
            sourceID != destinationID,
            Set(ids).count == ids.count,
            let sourceIndex = ids.firstIndex(of: sourceID),
            let destinationIndex = ids.firstIndex(of: destinationID)
        else {
            return ids
        }

        var reordered = ids
        let movedID = reordered.remove(at: sourceIndex)
        reordered.insert(movedID, at: min(destinationIndex, reordered.endIndex))
        return reordered
    }
}

struct WorkoutModePlanner {
    func plannedExercises(
        from exercises: [WorkoutSelectableExercise],
        mode: WorkoutMode
    ) -> [PlannedWorkoutExercise] {
        let candidates = prioritizedExercises(from: exercises, mode: mode)

        return candidates.map { exercise in
            PlannedWorkoutExercise(
                id: exercise.id,
                exerciseId: exercise.exerciseId,
                name: exercise.name,
                targetSets: adjustedSetCount(for: exercise, mode: mode),
                minReps: exercise.minReps,
                maxReps: exercise.maxReps,
                notes: exercise.notes
            )
        }
    }

    func estimatedDurationMinutes(for exercises: [PlannedWorkoutExercise], mode: WorkoutMode) -> ClosedRange<Int> {
        let totalSets = exercises.reduce(0) { $0 + $1.targetSets }
        let baseMinutes = max(15, totalSets * minutesPerSet(for: mode))

        switch mode {
        case .full:
            return baseMinutes...(baseMinutes + 15)
        case .quick:
            return min(baseMinutes, 35)...min(baseMinutes + 10, 40)
        case .recovery:
            return max(20, baseMinutes - 5)...(baseMinutes + 8)
        case .heavy:
            return baseMinutes...(baseMinutes + 20)
        }
    }

    func modeAdjustedSuggestion(_ suggestion: TargetSuggestion, mode: WorkoutMode) -> TargetSuggestion {
        guard mode == .recovery else { return suggestion }

        switch suggestion.recommendationType {
        case .increaseLoad, .addReps:
            return TargetSuggestion(
                exerciseName: suggestion.exerciseName,
                lastBestSetDescription: suggestion.lastBestSetDescription,
                lastBestWeight: suggestion.lastBestWeight,
                lastBestReps: suggestion.lastBestReps,
                suggestedWeight: suggestion.lastBestWeight ?? suggestion.suggestedWeight,
                suggestedReps: suggestion.lastBestReps ?? suggestion.suggestedReps,
                recommendationType: .repeatTarget,
                reason: "Recovery mode: keep this lighter and repeat the target with clean reps.",
                confidence: min(suggestion.confidence, 0.7)
            )
        default:
            return suggestion
        }
    }

    private func prioritizedExercises(
        from exercises: [WorkoutSelectableExercise],
        mode: WorkoutMode
    ) -> [WorkoutSelectableExercise] {
        switch mode {
        case .full, .recovery:
            return exercises
        case .quick:
            return Array(exercises.prefix(min(4, exercises.count)))
        case .heavy:
            let mainExercises = Array(exercises.prefix(min(4, exercises.count)))
            let accessories = exercises.dropFirst(mainExercises.count).prefix(2)
            return mainExercises + Array(accessories)
        }
    }

    private func adjustedSetCount(for exercise: WorkoutSelectableExercise, mode: WorkoutMode) -> Int {
        switch mode {
        case .full:
            return max(1, exercise.targetSets)
        case .quick:
            return max(2, min(exercise.targetSets, 3))
        case .recovery:
            return max(1, exercise.targetSets - 1)
        case .heavy:
            return max(2, exercise.targetSets)
        }
    }

    private func minutesPerSet(for mode: WorkoutMode) -> Int {
        switch mode {
        case .full, .recovery:
            return 3
        case .quick:
            return 2
        case .heavy:
            return 4
        }
    }
}
