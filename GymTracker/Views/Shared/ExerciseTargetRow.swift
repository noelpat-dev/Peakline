import SwiftUI

struct ExerciseTargetRow: View {
    let suggestion: TargetSuggestion

    var body: some View {
        ExerciseTargetCard(
            suggestion: suggestion,
            targetDescription: targetDescription,
            confidenceDescription: confidenceDescription
        )
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

private struct ExerciseTargetCard: View {
    @Environment(\.appTheme) private var appTheme

    let suggestion: TargetSuggestion
    let targetDescription: String
    let confidenceDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 10) {
                ExerciseTargetMetricTile(
                    label: "Last best",
                    value: suggestion.lastBestSetDescription ?? "New",
                    systemImage: "clock.arrow.circlepath"
                )

                ExerciseTargetMetricTile(
                    label: "Target",
                    value: targetDescription,
                    caption: confidenceDescription,
                    systemImage: "target"
                )
            }

            Text(suggestion.reason)
                .font(.subheadline)
                .foregroundStyle(appTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: suggestion),
                size: 44,
                showBackground: true,
                isDecorative: true
            )

            Text(suggestion.exerciseName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .layoutPriority(1)

            Spacer(minLength: 8)

            CoachBadgeView(recommendationType: suggestion.recommendationType)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct ExerciseTargetMetricTile: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    var caption: String? = nil
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.accent)

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(appTheme.colors.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }
}
