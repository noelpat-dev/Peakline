import SwiftUI

struct SplitCardView: View {
    let splitName: String
    let lastTrainedText: String
    let estimatedDurationText: String
    let exerciseCount: Int
    let badgeState: CoachBadgeState
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        FitnessCard {
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
                        Text(lastTrainedText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
