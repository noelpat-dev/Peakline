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
    @State private var energyLevel = ReadinessLevel.normal
    @State private var sorenessLevel = SorenessLevel.mild
    @State private var availableMinutes = 60
    @State private var motivationLevel = ReadinessLevel.normal

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

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
            Section {
                Picker("Energy", selection: $energyLevel) {
                    ForEach(ReadinessLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Soreness", selection: $sorenessLevel) {
                    ForEach(SorenessLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Time", selection: $availableMinutes) {
                    ForEach([20, 40, 60, 90], id: \.self) { minutes in
                        Text("\(minutes)m").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Motivation", selection: $motivationLevel) {
                    ForEach(ReadinessLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Readiness")
            } footer: {
                Text("Quick check-in for coach recommendations. Defaults are ready to go if you want to start fast.")
            }

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
            splitNameSnapshot: split.name,
            energyLevel: energyLevel.rawValue,
            sorenessLevel: sorenessLevel.rawValue
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

        let readinessCheck = ReadinessCheck(
            energyLevel: energyLevel.rawValue,
            sorenessLevel: sorenessLevel.rawValue,
            availableMinutes: availableMinutes,
            motivationLevel: motivationLevel.rawValue
        )

        modelContext.insert(readinessCheck)
        modelContext.insert(session)
        try? modelContext.save()
        return session
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
