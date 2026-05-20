import SwiftUI

struct SplitExerciseRow: View {
    @Environment(\.appTheme) private var appTheme

    let exercise: SplitExercise
    let suggestion: TargetSuggestion?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: exercise),
                size: 38,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exercise.exerciseNameSnapshot)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let suggestion {
                        CoachBadgeView(recommendationType: suggestion.recommendationType)
                    }
                }

                Text("\(exercise.targetSets) sets - \(exercise.minReps)-\(exercise.maxReps) reps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)

                if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        if let lastBest = suggestion?.lastBestSetDescription {
            return "Latest best: \(lastBest)"
        }

        return "Target controlled reps before adding load."
    }
}
