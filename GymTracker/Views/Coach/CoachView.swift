import SwiftData
import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            CoachContentView()
        }
    }
}

struct CoachContentView: View {
    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(sort: \ReadinessCheck.date, order: .reverse)
    private var readinessChecks: [ReadinessCheck]

    private let coachEngine = CoachRecommendationEngine()

    private var summary: CoachRecommendationSummary {
        coachEngine.makeSummary(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    var body: some View {
        List {
            Section("Next Workout") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.recommendedSplitName.map { "Suggested today: \($0)" } ?? "No recommendation yet")
                        .font(.headline)
                    Text(summary.reason)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Readiness") {
                if let latestReadiness = readinessChecks.first {
                    LabeledContent("Energy", value: readinessText(ReadinessLevel(rawValue: latestReadiness.energyLevel)))
                    LabeledContent("Soreness", value: sorenessText(SorenessLevel(rawValue: latestReadiness.sorenessLevel)))
                    LabeledContent("Time", value: "\(latestReadiness.availableMinutes) min")
                    LabeledContent("Motivation", value: readinessText(ReadinessLevel(rawValue: latestReadiness.motivationLevel)))
                    Text(readinessMessage(for: latestReadiness))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start a workout with a readiness check to unlock this card.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercise Recommendations") {
                if summary.exerciseRecommendations.isEmpty {
                    Text("Complete a workout from your split to get load and rep targets.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.exerciseRecommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(recommendation.exerciseName)
                                    .font(.headline)
                                Spacer()
                                Text(recommendation.priority.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(priorityColor(recommendation.priority))
                            }
                            Text(recommendation.message)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Recovery Warnings") {
                if summary.recoveryWarnings.isEmpty {
                    Text("No major recovery warnings right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.recoveryWarnings) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(warning.title)
                                    .font(.headline)
                                Spacer()
                                Text(warning.severity.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(priorityColor(warning.severity))
                            }
                            Text(warning.message)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Weekly Summary") {
                if summary.weeklyInsights.isEmpty {
                    Text("Finish workouts to build a weekly summary.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.weeklyInsights, id: \.self) { insight in
                        Text(insight)
                    }
                }
            }
        }
        .navigationTitle("Coach")
    }

    private func priorityColor(_ priority: CoachPriority) -> Color {
        switch priority {
        case .low:
            return .secondary
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func readinessText(_ level: ReadinessLevel?) -> String {
        level?.displayName ?? "Unknown"
    }

    private func sorenessText(_ level: SorenessLevel?) -> String {
        level?.displayName ?? "Unknown"
    }

    private func readinessMessage(for check: ReadinessCheck) -> String {
        if check.energyLevel == ReadinessLevel.low.rawValue || check.sorenessLevel == SorenessLevel.high.rawValue {
            return "Consider a shorter, cleaner session today. Keep reps controlled and avoid forcing load jumps."
        }

        if check.energyLevel == ReadinessLevel.high.rawValue && check.motivationLevel == ReadinessLevel.high.rawValue {
            return "Good day to push progression, as long as warm-ups move well."
        }

        return "A normal session fits today's check-in. Progress through reps before load."
    }
}
