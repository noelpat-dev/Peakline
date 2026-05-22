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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: splitName),
                        size: 46,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(splitName)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text(lastTrainedText)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()
                    CoachBadgeView(state: badgeState)
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Exercises", value: "\(exerciseCount)", caption: nil, systemImage: "list.bullet")
                    MetricTile(label: "Estimate", value: estimatedDurationText, caption: nil, systemImage: "clock")
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                }
            }
        }
    }
}
