import SwiftUI

struct WorkoutPreviewExerciseCard: View {
    @Environment(\.appTheme) private var appTheme

    let exercise: PlannedWorkoutExercise
    let suggestion: TargetSuggestion
    let alternatives: [Exercise]
    let isFirst: Bool
    let isLast: Bool
    let substitute: (Exercise) -> Void
    let requestSubstitute: () -> Void
    let moveToTop: () -> Void
    let moveToBottom: () -> Void
    let remove: () -> Void

    var body: some View {
        FitnessCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                ExerciseIconView(
                    iconKey: ExerciseIconMapper.iconKey(forName: exercise.exerciseNameSnapshot),
                    size: 44,
                    showBackground: true,
                    isDecorative: true
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(exercise.exerciseNameSnapshot)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        CoachBadgeView(recommendationType: suggestion.recommendationType)

                        actionMenu
                    }

                    Text("\(exercise.targetSets) sets · \(exercise.minReps)-\(exercise.maxReps) reps")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(appTheme.colors.textSecondary)

                    targetSummary

                    Text(suggestion.reason)
                        .font(.footnote)
                        .foregroundStyle(appTheme.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(notes, systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionMenu: some View {
        Menu {
            if alternatives.isEmpty {
                Text("No close alternatives")
            } else {
                Section("Substitute") {
                    Button {
                        requestSubstitute()
                    } label: {
                        Label("Choose with Reason", systemImage: "arrow.triangle.2.circlepath")
                    }

                    ForEach(alternatives) { alternative in
                        Button(alternative.name) {
                            substitute(alternative)
                        }
                    }
                }
            }

            Section {
                Button {
                    moveToTop()
                } label: {
                    Label("Move to Top", systemImage: "arrow.up.to.line")
                }
                .disabled(isFirst)

                Button {
                    moveToBottom()
                } label: {
                    Label("Move to Bottom", systemImage: "arrow.down.to.line")
                }
                .disabled(isLast)
            }

            Section {
                Button(role: .destructive) {
                    remove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(width: 34, height: 34)
                .background(appTheme.elevatedCardBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exercise actions")
    }

    private var targetSummary: some View {
        HStack(spacing: 6) {
            if let lastBest = suggestion.lastBestSetDescription {
                Text("Last: \(lastBest)")
                    .foregroundStyle(appTheme.colors.textSecondary)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }

            Text("Target: \(targetDescription)")
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var targetDescription: String {
        switch (suggestion.suggestedWeight, suggestion.suggestedReps) {
        case let (.some(weight), .some(reps)):
            return "\(format(weight))kg x \(reps)"
        case let (.some(weight), .none):
            return "\(format(weight))kg"
        case let (.none, .some(reps)):
            return "\(reps)+ reps"
        case (.none, .none):
            return "Log sets"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
