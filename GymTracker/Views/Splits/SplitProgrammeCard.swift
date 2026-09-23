import SwiftUI

struct SplitProgrammeCard: View {
    @Environment(\.appTheme) private var appTheme

    let splits: [TrainingSplit]
    let trainingCall: TrainingCallSnapshot
    let exerciseCount: Int
    let onEditRotation: () -> Void

    private var programmeTitle: String {
        "\(splits.count)-day rotation"
    }

    private var programmeDays: String {
        splits.map(\.name).joined(separator: PeaklineText.metadataSeparator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(programmeTitle)
                        .font(AppTypography.heroTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .layoutPriority(1)
                    Text(PeaklineText.count(exerciseCount, singular: "exercise"))
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer(minLength: 8)

                Button(action: onEditRotation) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                        .background {
                            Circle()
                                .stroke(appTheme.colors.textPrimary, lineWidth: 1)
                        }
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("Edit active rotation")
                .accessibilityIdentifier("edit-rotation-button")
            }

            if !programmeDays.isEmpty {
                Text(programmeDays)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(trainingCall.reason)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let targetSummary = trainingCall.targetSummary {
                Label(targetSummary, systemImage: "target")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Active programme · Light") {
    SplitProgrammeCard(
        splits: [
            TrainingSplit(name: "Push", splitType: .pushPullLegs, activeRotationIndex: 0),
            TrainingSplit(name: "Pull", splitType: .pushPullLegs, activeRotationIndex: 1),
            TrainingSplit(name: "Legs", splitType: .pushPullLegs, activeRotationIndex: 2)
        ],
        trainingCall: .placeholder,
        exerciseCount: 6,
        onEditRotation: {}
    )
    .padding()
}

#Preview("Empty programme · Dark") {
    SplitProgrammeCard(splits: [], trainingCall: .placeholder, exerciseCount: 0, onEditRotation: {})
        .padding()
        .preferredColorScheme(.dark)
}
