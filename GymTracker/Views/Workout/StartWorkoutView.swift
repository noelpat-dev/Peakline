import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            List {
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
    @State private var activeSession: WorkoutSession?

    let split: TrainingSplit

    var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section {
                ForEach(orderedExercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.exerciseNameSnapshot)
                            .font(.headline)
                        Text("\(exercise.targetSets) sets x \(exercise.minReps)-\(exercise.maxReps) reps")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Start \(split.name)") {
                    activeSession = createWorkout(from: split)
                }
                    .font(.headline)
            }
        }
        .navigationTitle(split.name)
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
    }

    private func createWorkout(from split: TrainingSplit) -> WorkoutSession {
        let session = WorkoutSession(
            splitId: split.id,
            splitNameSnapshot: split.name
        )

        session.exerciseLogs = orderedExercises.map { splitExercise in
            let log = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: splitExercise.exerciseId,
                exerciseNameSnapshot: splitExercise.exerciseNameSnapshot,
                orderIndex: splitExercise.orderIndex,
                targetSets: splitExercise.targetSets,
                minReps: splitExercise.minReps,
                maxReps: splitExercise.maxReps
            )
            log.workoutSession = session
            return log
        }

        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
}
