import SwiftUI

struct SplitProgrammeCard: View {
    @Environment(\.appTheme) private var appTheme

    let splits: [TrainingSplit]
    let trainingCall: TrainingCallSnapshot
    let onEditRotation: () -> Void

    private var exerciseCount: Int {
        splits.reduce(0) { $0 + $1.exercises.count }
    }

    private var programmeTitle: String {
        "\(splits.count)-day rotation"
    }

    private var programmeDays: String {
        splits.map(\.name).joined(separator: PeaklineText.metadataSeparator)
    }

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Active Programme")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
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
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                            .background(
                                appTheme.colors.accentSurface,
                                in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                                    .stroke(appTheme.colors.accent.opacity(0.18), lineWidth: 0.75)
                            }
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityLabel("Edit active rotation")
                    .accessibilityIdentifier("edit-rotation-button")
                }

                Text(programmeDays)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

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
        }
    }
}
