import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "clock",
                        description: Text("Finished workouts will appear here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            WorkoutHistoryDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.splitNameSnapshot)
                                    .font(.headline)
                                Text(summary(for: session))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func summary(for session: WorkoutSession) -> String {
        let date = session.date.formatted(date: .abbreviated, time: .omitted)
        let setCount = session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        return "\(date) - \(session.exerciseLogs.count) exercises - \(setCount) sets"
    }
}

private struct WorkoutHistoryDetailView: View {
    let session: WorkoutSession

    private var orderedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                if let duration = session.durationMinutes {
                    LabeledContent("Duration", value: "\(duration) min")
                }
                if let notes = session.notes, !notes.isEmpty {
                    Text(notes)
                }
            }

            ForEach(orderedExerciseLogs) { exerciseLog in
                Section(exerciseLog.exerciseNameSnapshot) {
                    let sets = exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
                    if sets.isEmpty {
                        Text("No sets logged")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sets) { set in
                            HStack {
                                Text("Set \(set.setNumber)")
                                Spacer()
                                Text("\(formatWeight(set.weight)) x \(set.reps)")
                                    .font(.headline)
                                if let rpe = set.rpe {
                                    Text("RPE \(formatWeight(rpe))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.splitNameSnapshot)
    }

    private func formatWeight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
