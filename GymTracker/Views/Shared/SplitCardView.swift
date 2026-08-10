import SwiftUI

struct SplitCardView: View {
    @Environment(\.appTheme) private var appTheme

    let splitName: String
    let lastTrainedText: String
    let estimatedDurationText: String
    let exerciseCount: Int
    let badgeState: CoachBadgeState
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: splitName),
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(splitName)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)

                        Text(
                            PeaklineText.joinedMetadata([
                                PeaklineText.count(exerciseCount, singular: "exercise"),
                                estimatedDurationText,
                                lastTrainedText
                            ])
                        )
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                    CoachBadgeView(state: badgeState)

                    if actionTitle == nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }

                if let actionTitle, let action {
                    Button {
                        AppHaptics.selection()
                        action()
                    } label: {
                        Label(actionTitle, systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                }
            }
        }
    }
}
