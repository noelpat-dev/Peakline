import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(filter: #Predicate<WorkoutSession> { !$0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var unfinishedSessions: [WorkoutSession]

    @State private var showingRestDayConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggested today")
                            .font(.headline)

                        Text(suggestedSplit?.name ?? "Create a split")
                            .font(.largeTitle.bold())

                        Text(recommendationReason)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Quick Actions") {
                    NavigationLink(value: TodayRoute.workout) {
                        Label(unfinishedSessions.isEmpty ? "Start Workout" : "Resume Workout", systemImage: "figure.strengthtraining.traditional")
                    }

                    Button {
                        showingRestDayConfirmation = true
                    } label: {
                        Label("Rest Day", systemImage: "moon")
                    }

                    NavigationLink(value: TodayRoute.coach) {
                        Label("Coach Check-In", systemImage: "sparkles")
                    }

                    NavigationLink(value: TodayRoute.progress) {
                        Label("Progress & Charts", systemImage: "chart.xyaxis.line")
                    }
                }

                Section("This Week") {
                    LabeledContent("Workouts", value: "\(workoutsThisWeek)")
                    LabeledContent("Working sets", value: "\(workingSetsThisWeek)")
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
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .workout:
                    StartWorkoutContentView()
                case .coach:
                    CoachContentView()
                case .progress:
                    ProgressContentView()
                }
            }
            .alert("Rest day noted", isPresented: $showingRestDayConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Persistent rest-day logging is still on the roadmap. For now, your workout history remains unchanged.")
            }
        }
    }

    private var recommendationReason: String {
        guard let split = suggestedSplit else {
            return "Starter Push/Pull/Legs templates will appear after seed data is created."
        }

        if recentPPLCycleNames.isEmpty {
            return "Start your Push/Pull/Legs rotation with \(split.name)."
        }

        if recentPPLCycleNames.contains(split.name) {
            return "You have completed this PPL round. \(split.name) starts the next rotation."
        }

        return "\(split.name) is next because it has not been completed in your current Push/Pull/Legs rotation."
    }

    private var suggestedSplit: TrainingSplit? {
        let orderedSplits = pplOrderedSplits
        guard !orderedSplits.isEmpty else { return activeSplits.first }

        let completedNames = Set(recentPPLCycleNames)
        if let missingSplit = orderedSplits.first(where: { !completedNames.contains($0.name) }) {
            return missingSplit
        }

        guard
            let mostRecentName = completedSessions.compactMap({ pplName(for: $0.splitNameSnapshot) }).first,
            let mostRecentIndex = PPLRotation.names.firstIndex(of: mostRecentName)
        else {
            return orderedSplits.first
        }

        let nextName = PPLRotation.names[(mostRecentIndex + 1) % PPLRotation.names.count]
        return orderedSplits.first { $0.name == nextName } ?? orderedSplits.first
    }

    private var pplOrderedSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
    }

    private var recentPPLCycleNames: [String] {
        var names: [String] = []

        for session in completedSessions {
            guard let name = pplName(for: session.splitNameSnapshot) else { continue }

            if names.contains(name) {
                break
            }

            names.append(name)

            if names.count == PPLRotation.names.count {
                break
            }
        }

        return names
    }

    private func pplName(for splitNameSnapshot: String) -> String? {
        PPLRotation.names.first { name in
            splitNameSnapshot == name || splitNameSnapshot.hasPrefix("\(name) - ")
        }
    }

    private var workoutsThisWeek: Int {
        completedSessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private var workingSetsThisWeek: Int {
        completedSessions
            .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(0) { total, session in
                total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
            }
    }
}

private enum PPLRotation {
    static let names = ["Push", "Pull", "Legs"]
}

private enum TodayRoute: Hashable, Identifiable {
    case workout
    case coach
    case progress

    var id: Self { self }
}
