import Charts
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
            Section("Progress Charts") {
                if exercises.isEmpty {
                    Text("Add exercises to unlock progress charts.")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        ExerciseProgressChartsIndexView(exercises: exercises, sessions: completedSessions)
                    } label: {
                        Label("Exercise Progress Charts", systemImage: "chart.xyaxis.line")
                    }
                }
            }

            Section("Exercises") {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseProgressDetailView(exercise: exercise, sessions: completedSessions)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(exercise.primaryMuscleGroup.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
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
                    LabeledContent("Best-set volume", value: latest.bestSetVolumeText)
                    LabeledContent("Sets", value: "\(latest.completedSets)")
                }
            }

            Section("Chart") {
                if entries.count < 2 {
                    Text("Log this exercise at least twice to see a trend line.")
                        .foregroundStyle(.secondary)
                } else {
                    ExerciseTrendChart(entries: entries.reversed())
                        .frame(height: 220)
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
                            Text("Best-set volume \(entry.bestSetVolumeText) - est. 1RM \(entry.estimatedOneRepMaxText)")
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

private struct ExerciseProgressChartsIndexView: View {
    let exercises: [Exercise]
    let sessions: [WorkoutSession]

    var body: some View {
        List {
            Section("Exercises") {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseProgressDetailView(exercise: exercise, sessions: sessions)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(exercise.primaryMuscleGroup.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress Charts")
    }
}

private struct ExerciseTrendChart: View {
    @Environment(\.appTheme) private var appTheme
    let entries: ReversedCollection<[ExerciseProgressEntry]>

    var body: some View {
        Chart(Array(entries)) { entry in
            LineMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.primaryColor)

            PointMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.primaryColor)
        }
        .chartYAxisLabel("Est. 1RM kg")
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
        "\(format(estimatedOneRepMax))kg"
    }

    var estimatedOneRepMax: Double {
        estimatedOneRepMax(for: bestSet)
    }

    var bestSetVolumeText: String {
        "\(format(bestSetVolume))kg"
    }

    var bestSetVolume: Double {
        bestSet.weight * Double(bestSet.reps)
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
