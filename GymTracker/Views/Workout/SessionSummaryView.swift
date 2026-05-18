import SwiftData
import SwiftUI

struct SessionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    let session: WorkoutSession
    private let builder = SessionSummaryBuilder()

    private var summary: SessionSummary {
        builder.build(from: session, completedSessions: completedSessions, activeSplits: activeSplits)
    }

    var body: some View {
        FitnessScreen(
            title: "Session Summary",
            subtitle: summary.splitName,
            systemImage: "checkmark.circle.fill"
        ) {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary.takeaway)
                        .font(.headline)

                    HStack(spacing: 10) {
                        MetricTile(label: "Duration", value: summary.durationText, caption: nil, systemImage: "timer")
                        MetricTile(label: "Sets", value: "\(summary.workingSetCount)", caption: "Working", systemImage: "checkmark.circle")
                    }

                    HStack(spacing: 10) {
                        MetricTile(label: "Exercises", value: "\(summary.completedExerciseCount)", caption: "Completed", systemImage: "list.bullet")
                        MetricTile(label: "Rating", value: summary.ratingText ?? "-", caption: "Session feel", systemImage: "face.smiling")
                    }
                }
            }

            FitnessCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Best Set Improvements")
                            .font(.headline)
                        Spacer()
                        CoachBadgeView(state: summary.bestSetImprovements.isEmpty ? .ready : .pr)
                    }

                    if summary.bestSetImprovements.isEmpty {
                        Text("No best-set improvements detected this time. A repeatable session still keeps the trend alive.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        ForEach(summary.bestSetImprovements, id: \.self) { improvement in
                            Label(improvement, systemImage: "arrow.up.circle.fill")
                                .font(.subheadline)
                        }
                    }
                }
            }

            if let suggestedNextSplit = summary.suggestedNextSplit {
                FitnessCard {
                    HStack {
                        ExerciseIconView(
                            iconKey: ExerciseIconMapper.splitIconKey(for: suggestedNextSplit),
                            size: 44,
                            showBackground: true,
                            isDecorative: true
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .textCase(.uppercase)
                            Text(suggestedNextSplit)
                                .font(.title2.bold())
                        }

                        Spacer()
                        CoachBadgeView(state: .ready)
                    }
                }
            }

            if !completedExerciseLogs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Completed Exercises")
                        .font(.headline)

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(completedExerciseLogs.enumerated()), id: \.element.id) { index, exerciseLog in
                                if index > 0 {
                                    Divider()
                                }

                                SessionSummaryExerciseRow(exerciseLog: exerciseLog)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
            .font(.headline)
        }
        .navigationBarBackButtonHidden()
    }

    private var completedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { exerciseLog in
                exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
            }
    }
}

private struct SessionSummaryExerciseRow: View {
    @Environment(\.appTheme) private var appTheme

    let exerciseLog: ExerciseLog

    private var bestSet: SetLog? {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }

    var body: some View {
        HStack(spacing: 10) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                size: 34,
                showBackground: true,
                isDecorative: true
            )

            Text(exerciseLog.exerciseNameSnapshot)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(bestSetDescription)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var bestSetDescription: String {
        guard let bestSet else { return "Logged" }
        return "\(format(bestSet.weight))kg x \(bestSet.reps)"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
