import SwiftData
import SwiftUI

struct ProgressView: View {
    var body: some View {
        NavigationStack {
            ProgressContentView()
        }
    }
}

struct ProgressContentView: View {
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    var body: some View {
        List {
            Section("Exercises") {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseProgressDetailView(exercise: exercise, sessions: completedSessions)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(summary(for: exercise))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }

    private func summary(for exercise: Exercise) -> String {
        let entries = progressEntries(for: exercise)
        guard let latest = entries.first else {
            return exercise.primaryMuscleGroup.displayName
        }

        return "Latest: \(latest.bestSetText) - \(latest.completedSets) sets"
    }

    private func progressEntries(for exercise: Exercise) -> [ExerciseProgressEntry] {
        completedSessions.compactMap { session in
            guard let exerciseLog = session.exerciseLogs.first(where: { $0.exerciseId == exercise.id }) else {
                return nil
            }

            let sets = exerciseLog.setLogs
                .filter { $0.completed && !$0.isWarmup }
                .sorted { $0.setNumber < $1.setNumber }

            guard !sets.isEmpty else { return nil }
            return ExerciseProgressEntry(session: session, sets: sets)
        }
    }
}

private struct ExerciseProgressDetailView: View {
    let exercise: Exercise
    let sessions: [WorkoutSession]

    private var entries: [ExerciseProgressEntry] {
        sessions.compactMap { session in
            guard let exerciseLog = session.exerciseLogs.first(where: { $0.exerciseId == exercise.id }) else {
                return nil
            }

            let sets = exerciseLog.setLogs
                .filter { $0.completed && !$0.isWarmup }
                .sorted { $0.setNumber < $1.setNumber }

            guard !sets.isEmpty else { return nil }
            return ExerciseProgressEntry(session: session, sets: sets)
        }
    }

    var body: some View {
        List {
            if let latest = entries.first {
                Section("Latest") {
                    LabeledContent("Best set", value: latest.bestSetText)
                    LabeledContent("Estimated 1RM", value: latest.estimatedOneRepMaxText)
                    LabeledContent("Volume", value: latest.volumeText)
                    LabeledContent("Sets", value: "\(latest.completedSets)")
                }
            }

            Section("History") {
                if entries.isEmpty {
                    Text("No completed working sets yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.session.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline)
                            Text(entry.setsText)
                                .foregroundStyle(.secondary)
                            Text("Volume \(entry.volumeText) - est. 1RM \(entry.estimatedOneRepMaxText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}

private struct ExerciseProgressEntry: Identifiable {
    let id = UUID()
    let session: WorkoutSession
    let sets: [SetLog]

    var completedSets: Int {
        sets.count
    }

    var bestSet: SetLog {
        sets.max { estimatedOneRepMax(for: $0) < estimatedOneRepMax(for: $1) } ?? sets[0]
    }

    var bestSetText: String {
        "\(format(bestSet.weight))kg x \(bestSet.reps)"
    }

    var estimatedOneRepMaxText: String {
        "\(format(estimatedOneRepMax(for: bestSet)))kg"
    }

    var volumeText: String {
        "\(format(sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }))kg"
    }

    var setsText: String {
        sets.map { "\(format($0.weight))kg x \($0.reps)" }.joined(separator: ", ")
    }

    private func estimatedOneRepMax(for set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
