import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggested today")
                            .font(.headline)

                        Text(activeSplits.first?.name ?? "Create a split")
                            .font(.largeTitle.bold())

                        Text(recommendationReason)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Quick Actions") {
                    Button("Start Workout") {}
                    Button("Rest Day") {}
                    Button("Daily Check-In") {}
                }

                Section("Last Workout") {
                    if let last = completedSessions.first {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(last.splitNameSnapshot)
                                .font(.headline)
                            Text(last.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            Text("\(last.exerciseLogs.count) exercises")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No workouts logged yet")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Today")
        }
    }

    private var recommendationReason: String {
        guard let split = activeSplits.first else {
            return "Starter Push/Pull/Legs templates will appear after seed data is created."
        }

        return "\(split.name) is ready from your active split templates."
    }
}
