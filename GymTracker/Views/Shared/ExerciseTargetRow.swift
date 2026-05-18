import SwiftUI

struct ExerciseTargetRow: View {
    @Environment(\.appTheme) private var appTheme

    let suggestion: TargetSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: suggestion),
                size: 42,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(suggestion.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    CoachBadgeView(recommendationType: suggestion.recommendationType)
                }

                HStack(alignment: .top, spacing: 10) {
                    MetricTile(
                        label: "Last best",
                        value: suggestion.lastBestSetDescription ?? "New",
                        caption: nil,
                        systemImage: "clock.arrow.circlepath"
                    )

                    MetricTile(
                        label: "Target",
                        value: targetDescription,
                        caption: confidenceDescription,
                        systemImage: "target"
                    )
                }

                Text(suggestion.reason)
                    .font(.footnote)
                    .foregroundStyle(appTheme.mutedText)
            }
        }
        .accessibilityElement(children: .combine)
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

    private var confidenceDescription: String {
        let percentage = Int((suggestion.confidence * 100).rounded())
        return "\(percentage)% confidence"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
