import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    var body: some View {
        NavigationStack {
            StartWorkoutContentView()
        }
    }
}

struct StartWorkoutContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { !$0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var unfinishedSessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?

    var body: some View {
        List {
            if let unfinishedSession = unfinishedSessions.first {
                Section("Resume") {
                    Button {
                        activeSession = unfinishedSession
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unfinishedSession.splitNameSnapshot)
                                .font(.headline)
                            Text(resumeSummary(for: unfinishedSession))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Start From Split") {
                ForEach(activeSplits) { split in
                    NavigationLink {
                        WorkoutPreviewView(split: split)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(split.name)
                                .font(.headline)
                            Text("\(split.exercises.count) exercises")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Start Empty Workout") {
                    activeSession = createEmptyWorkout()
                }
            }
        }
        .navigationTitle("Workout")
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
    }

    private func resumeSummary(for session: WorkoutSession) -> String {
        let started = (session.startedAt ?? session.date).formatted(date: .abbreviated, time: .shortened)
        let completedSets = session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        return "Started \(started) - \(completedSets) completed sets"
    }

    private func createEmptyWorkout() -> WorkoutSession {
        let session = WorkoutSession()
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
}

private struct WorkoutPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @State private var activeSession: WorkoutSession?
    @State private var selectedExerciseIds: [UUID] = []

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    let split: TrainingSplit

    private var orderedExercises: [WorkoutSelectableExercise] {
        var items = split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(WorkoutSelectableExercise.init)

        if
            !items.contains(where: { $0.name == "Abdominal Crunch" }),
            let abdominalCrunch = exercises.first(where: { $0.name == "Abdominal Crunch" })
        {
            items.append(
                WorkoutSelectableExercise(
                    id: abdominalCrunch.id,
                    exerciseId: abdominalCrunch.id,
                    name: abdominalCrunch.name,
                    targetSets: 2,
                    minReps: 8,
                    maxReps: 15,
                    notes: "Optional core work."
                )
            )
        }

        return items
    }

    private var selectedExercises: [WorkoutSelectableExercise] {
        selectedExerciseIds.compactMap { selectedId in
            orderedExercises.first { $0.id == selectedId }
        }
    }

    var body: some View {
        List {
            Section("Today's Exercises") {
                ForEach(orderedExercises) { exercise in
                    Button {
                        toggle(exercise)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedExerciseIds.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedExerciseIds.contains(exercise.id) ? appTheme.primaryColor : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.exerciseNameSnapshot)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(exercise.targetSets) sets x \(exercise.minReps)-\(exercise.maxReps) reps")
                                    .foregroundStyle(.secondary)
                                ExerciseTargetPreviewView(preview: targetPreview(for: exercise))
                                if let notes = exercise.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                HStack {
                    Button("Select All") {
                        selectedExerciseIds = orderedExercises.map(\.id)
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text(selectedExercises.isEmpty ? "Choose the exercises you plan to do today before starting." : "\(selectedExercises.count) selected for this session.")
            }

            Section {
                Button("Start \(split.name)") {
                    activeSession = createWorkout(from: split)
                }
                .font(.headline)
                .disabled(selectedExercises.isEmpty)
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle(split.name)
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
    }

    private func toggle(_ exercise: WorkoutSelectableExercise) {
        if selectedExerciseIds.contains(exercise.id) {
            selectedExerciseIds.removeAll { $0 == exercise.id }
        } else {
            selectedExerciseIds.append(exercise.id)
        }
    }

    private func createWorkout(from split: TrainingSplit) -> WorkoutSession {
        let session = WorkoutSession(
            splitId: split.id,
            splitNameSnapshot: split.name
        )

        session.exerciseLogs = selectedExercises.enumerated().map { index, splitExercise in
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: splitExercise.exerciseId,
                exerciseNameSnapshot: splitExercise.exerciseNameSnapshot,
                orderIndex: index,
                targetSets: splitExercise.targetSets,
                minReps: splitExercise.minReps,
                maxReps: splitExercise.maxReps,
                notes: splitExercise.notes
            )
            log.workoutSession = session
            return log
        }

        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    private func targetPreview(for exercise: WorkoutSelectableExercise) -> ExerciseTargetPreview {
        guard let previousLog = lastCompletedLog(for: exercise) else {
            return ExerciseTargetPreview(
                lastPerformance: "Last time: no previous data",
                target: "Today: establish a clean baseline",
                priority: .baseline
            )
        }

        let workingSets = completedWorkingSets(from: previousLog)
        guard !workingSets.isEmpty else {
            return ExerciseTargetPreview(
                lastPerformance: "Last time: no completed working sets",
                target: "Today: log controlled working sets",
                priority: .baseline
            )
        }

        let bestSet = workingSets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) } ?? workingSets[0]
        let allAtTop = workingSets.allSatisfy { $0.reps >= exercise.maxReps }
        let anyBelowRange = workingSets.contains { $0.reps < exercise.minReps }
        let lastPerformance = "Last time: \(format(bestSet.weight))kg x \(bestSet.reps)"

        if allAtTop, bestSet.weight > 0 {
            return ExerciseTargetPreview(
                lastPerformance: lastPerformance,
                target: "Today: try \(format(bestSet.weight + 2.5))kg for \(exercise.minReps)+ reps",
                priority: .increaseLoad
            )
        }

        if anyBelowRange {
            return ExerciseTargetPreview(
                lastPerformance: lastPerformance,
                target: "Today: repeat until every set reaches \(exercise.minReps)+ reps",
                priority: .repeatLoad
            )
        }

        return ExerciseTargetPreview(
            lastPerformance: lastPerformance,
            target: "Today: keep load and add reps toward \(exercise.maxReps)",
            priority: .addReps
        )
    }

    private func lastCompletedLog(for exercise: WorkoutSelectableExercise) -> ExerciseLog? {
        for session in completedSessions {
            if let log = session.exerciseLogs.first(where: { $0.exerciseId == exercise.exerciseId }) {
                return log
            }
        }

        return nil
    }

    private func completedWorkingSets(from exerciseLog: ExerciseLog) -> [SetLog] {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct WorkoutSelectableExercise: Identifiable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?

    var exerciseNameSnapshot: String {
        name
    }

    init(_ splitExercise: SplitExercise) {
        id = splitExercise.id
        exerciseId = splitExercise.exerciseId
        name = splitExercise.exerciseNameSnapshot
        targetSets = splitExercise.targetSets
        minReps = splitExercise.minReps
        maxReps = splitExercise.maxReps
        notes = splitExercise.notes
    }

    init(id: UUID, exerciseId: UUID, name: String, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.notes = notes
    }
}

private struct ExerciseTargetPreview {
    let lastPerformance: String
    let target: String
    let priority: TargetPriority
}

private enum TargetPriority {
    case baseline
    case addReps
    case repeatLoad
    case increaseLoad

    var systemImage: String {
        switch self {
        case .baseline:
            return "scope"
        case .addReps:
            return "plusminus"
        case .repeatLoad:
            return "repeat"
        case .increaseLoad:
            return "arrow.up.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .baseline:
            return "Baseline"
        case .addReps:
            return "Add reps"
        case .repeatLoad:
            return "Repeat"
        case .increaseLoad:
            return "Increase"
        }
    }
}

private struct ExerciseTargetPreviewView: View {
    @Environment(\.appTheme) private var appTheme

    let preview: ExerciseTargetPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preview.lastPerformance)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: preview.priority.systemImage)
                    .font(.caption2.weight(.semibold))
                Text(preview.target)
                    .font(.caption)
            }
            .foregroundStyle(appTheme.primaryColor)
            .accessibilityLabel("\(preview.priority.label). \(preview.target)")
        }
    }
}
