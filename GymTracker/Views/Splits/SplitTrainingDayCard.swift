import SwiftUI

struct SplitTrainingDayCard: View {
    @Environment(\.appTheme) private var appTheme

    let split: TrainingSplit
    let status: SplitStatus
    let lastTrainedText: String
    let focusDescription: String

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .center, spacing: 14) {
                ExerciseIconTile(
                    iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                    title: nil,
                    size: 48,
                    style: .compact,
                    tint: iconTint
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(split.name)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(2)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            SplitStatusBadge(status: status)
                            trainingMetadata
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            SplitStatusBadge(status: status)
                            trainingMetadata
                        }
                    }

                    Text(focusDescription)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)
                }

                Image(systemName: "chevron.right")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var trainingMetadata: some View {
        Text(
            PeaklineText.joinedMetadata([
                PeaklineText.count(split.exercises.count, singular: "exercise"),
                lastTrainedText
            ])
        )
            .font(AppTypography.metadataEmphasis)
            .foregroundStyle(appTheme.colors.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
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
