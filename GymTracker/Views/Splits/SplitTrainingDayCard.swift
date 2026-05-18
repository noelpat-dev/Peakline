import SwiftUI

struct SplitTrainingDayCard: View {
    @Environment(\.appTheme) private var appTheme

    let split: TrainingSplit
    let status: SplitStatus
    let lastTrainedText: String
    let focusDescription: String

    var body: some View {
        FitnessCard(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                ExerciseIconTile(
                    iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                    title: nil,
                    size: 58,
                    style: .compact,
                    tint: iconTint
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(split.name)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        SplitStatusBadge(status: status)
                    }

                    Text("\(split.exercises.count) exercises")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(lastTrainedText)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Text(focusDescription)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconTint: Color {
        switch status {
        case .prioritise:
            return appTheme.colors.warning
        case .inactive, .recentlyTrained, .custom:
            return appTheme.colors.textSecondary
        case .ready, .progressOpportunity:
            return appTheme.colors.accent
        }
    }
}
