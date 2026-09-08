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
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let resolvedStartedAt: Date
        if arguments.contains("-UITestLongWorkoutFixture") {
            resolvedStartedAt = startedAt.addingTimeInterval(-5 * 60 * 60)
        } else if arguments.contains("-UITestInMemoryStore") {
            // UI automation completes flows faster than a real workout. Give
            // test-only sessions a valid duration without weakening production's
            // one-minute completion contract.
            resolvedStartedAt = startedAt.addingTimeInterval(-2 * 60)
        } else {
            resolvedStartedAt = startedAt
        }
#else
        let resolvedStartedAt = startedAt
#endif
        let session = WorkoutSession(
            date: resolvedStartedAt,
            splitId: splitId,
            splitNameSnapshot: splitNameSnapshot,
            startedAt: resolvedStartedAt
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

    func estimatedDurationMinutes(
        for exercises: [PlannedWorkoutExercise],
        mode: WorkoutMode,
        calibration: WorkoutDurationCalibration = .empty,
        splitName: String? = nil,
        now: Date = .now
    ) -> ClosedRange<Int> {
        let totalSets = exercises.reduce(0) { $0 + $1.targetSets }
        guard totalSets > 0 else { return 0...0 }

        let minutesPerSet = calibration.minutesPerWorkingSet(
            splitName: splitName,
            mode: mode,
            now: now
        ) ?? fallbackMinutesPerSet(for: mode)
        let midpoint = Double(totalSets) * minutesPerSet
        let lower = max(5, Int(floor((midpoint * 0.85) / 5)) * 5)
        let estimatedUpper = Int(ceil((midpoint * 1.15) / 5)) * 5
        return lower...max(estimatedUpper, lower + 10)
    }

    func modeAdjustedSuggestion(
        _ suggestion: TargetSuggestion,
        mode: WorkoutMode,
        trainingCall: TrainingCallSnapshot? = nil
    ) -> TargetSuggestion {
        let conservativeReason = trainingCall.flatMap { $0.isConservative ? $0.reason : nil }
        guard mode == .recovery || conservativeReason != nil else { return suggestion }

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
                reason: mode == .recovery
                    ? "Recovery mode: keep this lighter and repeat the target with clean reps."
                    : conservativeReason ?? suggestion.reason,
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

    private func fallbackMinutesPerSet(for mode: WorkoutMode) -> Double {
        switch mode {
        case .full, .quick:
            return 5
        case .recovery:
            return 4.5
        case .heavy:
            return 6
        }
    }
}

struct WorkoutDurationSample: Hashable, Sendable {
    let date: Date
    let splitName: String
    let mode: WorkoutMode?
    let durationSeconds: Int
    let completedWorkingSetCount: Int

    @MainActor
    init?(session: WorkoutSession) {
        guard session.completed else { return nil }

        let resolvedDuration: Int
        if let seconds = session.durationSeconds {
            resolvedDuration = seconds
        } else if let minutes = session.durationMinutes {
            resolvedDuration = minutes * 60
        } else if let startedAt = session.startedAt, let endedAt = session.endedAt {
            resolvedDuration = max(
                0,
                Int(endedAt.timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds
            )
        } else {
            return nil
        }

        let completedWorkingSets = session.exerciseLogs
            .flatMap(\.setLogs)
            .filter { $0.completed && !$0.isWarmup }
            .count
        guard completedWorkingSets > 0 else { return nil }

        date = session.date
        splitName = Self.baseSplitName(session.splitNameSnapshot)
        mode = Self.mode(from: session.splitNameSnapshot)
        durationSeconds = resolvedDuration
        completedWorkingSetCount = completedWorkingSets
    }

    init(
        date: Date,
        splitName: String,
        mode: WorkoutMode?,
        durationSeconds: Int,
        completedWorkingSetCount: Int
    ) {
        self.date = date
        self.splitName = Self.baseSplitName(splitName)
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.completedWorkingSetCount = completedWorkingSetCount
    }

    private static func baseSplitName(_ value: String) -> String {
        value.components(separatedBy: " - ").first ?? value
    }

    private static func mode(from value: String) -> WorkoutMode? {
        guard let suffix = value.components(separatedBy: " - ").last else { return nil }
        return WorkoutMode.allCases.first { $0.displayName.caseInsensitiveCompare(suffix) == .orderedSame }
    }
}

struct WorkoutDurationCalibration: Hashable, Sendable {
    let samples: [WorkoutDurationSample]

    static let empty = WorkoutDurationCalibration(samples: [])

    func minutesPerWorkingSet(
        splitName: String?,
        mode: WorkoutMode,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let earliestDate = calendar.date(byAdding: .day, value: -180, to: now) ?? now.addingTimeInterval(-180 * 86_400)
        let validSamples = samples
            .filter {
                $0.date >= earliestDate &&
                    $0.date <= now &&
                    $0.durationSeconds >= 10 * 60 &&
                    $0.durationSeconds < 4 * 60 * 60 &&
                    $0.completedWorkingSetCount > 0
            }
            .sorted { $0.date > $1.date }

        let normalizedSplit = splitName?.components(separatedBy: " - ").first
        let sameSplitAndMode = validSamples.filter {
            matchesSplit($0.splitName, normalizedSplit) && $0.mode == mode
        }
        if sameSplitAndMode.count >= 3 {
            return medianMinutesPerSet(Array(sameSplitAndMode.prefix(20)))
        }

        let sameSplit = validSamples.filter { matchesSplit($0.splitName, normalizedSplit) }
        if sameSplit.count >= 3 {
            return medianMinutesPerSet(Array(sameSplit.prefix(20)))
        }

        guard validSamples.count >= 3 else { return nil }
        return medianMinutesPerSet(Array(validSamples.prefix(20)))
    }

    private func matchesSplit(_ sampleSplit: String, _ requestedSplit: String?) -> Bool {
        guard let requestedSplit else { return false }
        return sampleSplit.caseInsensitiveCompare(requestedSplit) == .orderedSame
    }

    private func medianMinutesPerSet(_ samples: [WorkoutDurationSample]) -> Double? {
        let ratios = samples
            .map { Double($0.durationSeconds) / 60 / Double($0.completedWorkingSetCount) }
            .sorted()
        guard !ratios.isEmpty else { return nil }

        let middle = ratios.count / 2
        let median = ratios.count.isMultiple(of: 2)
            ? (ratios[middle - 1] + ratios[middle]) / 2
            : ratios[middle]
        return min(8, max(3.5, median))
    }
}
