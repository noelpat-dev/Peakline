import SwiftUI

struct SplitTrainingDayCard: View {
    @Environment(\.appTheme) private var appTheme

    let split: TrainingSplit
    let status: SplitStatus
    let lastTrainedText: String
    let focusDescription: String
    let exerciseCount: Int
    let relativeVolumes: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseIconTile(
                iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                title: nil,
                size: 40,
                style: .compact,
                tint: appTheme.colors.textPrimary
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(split.name)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        TrailSignTag(text: split.splitType.displayName)
                        statusLabel
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        TrailSignTag(text: split.splitType.displayName)
                        statusLabel
                    }
                }

                trainingMetadata

                Text(focusDescription)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                SplitRelativeVolumeProfile(volumes: relativeVolumes)

                Image(systemName: "chevron.right")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var trainingMetadata: some View {
        Text(
            PeaklineText.joinedMetadata([
                PeaklineText.count(exerciseCount, singular: "exercise"),
                lastTrainedText
            ])
        )
            .font(AppTypography.metadataEmphasis)
            .foregroundStyle(appTheme.colors.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusLabel: some View {
        Text(status.title.uppercased())
            .modifier(AppTypography.waypointLabelSmall)
            .foregroundStyle(appTheme.colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct SplitRelativeVolumeProfile: View {
    @Environment(\.appTheme) private var appTheme

    let volumes: [Double]

    private var normalizedVolumes: [CGFloat] {
        let maximum = volumes.max() ?? 0
        guard maximum > 0 else { return volumes.map { _ in 0 } }
        return volumes.map { CGFloat($0 / maximum) }
    }

    var body: some View {
        Group {
            if normalizedVolumes.isEmpty {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 17))
                    path.addLine(to: CGPoint(x: 60, y: 17))
                }
                .stroke(
                    appTheme.colors.textTertiary,
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 2])
                )
            } else {
                SplitElevationPolyline(values: normalizedVolumes)
                    .stroke(
                        appTheme.colors.textPrimary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .frame(width: 60, height: 18)
        .accessibilityHidden(true)
    }
}

private struct SplitElevationPolyline: Shape {
    let values: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let inset: CGFloat = 1
        let usableWidth = max(0, rect.width - inset * 2)
        let baseline = rect.maxY - 1
        let peakHeight = max(0, rect.height - 4)

        for (index, value) in values.enumerated() {
            let x: CGFloat
            if values.count == 1 {
                x = rect.midX
            } else {
                x = rect.minX + inset + usableWidth * CGFloat(index) / CGFloat(values.count - 1)
            }
            let y = baseline - peakHeight * min(max(value, 0), 1)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: CGPoint(x: rect.minX, y: baseline))
                path.addLine(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))
        return path
    }
}

private enum SplitTrainingDayCardPreviewData {
    static func make(
        name: String,
        type: SplitType,
        volumes: [(sets: Int, minReps: Int, maxReps: Int)]
    ) -> (split: TrainingSplit, exerciseCount: Int, relativeVolumes: [Double]) {
        let id = UUID()
        let exercises = volumes.enumerated().map { index, volume in
            SplitExercise(
                splitId: id,
                exerciseId: UUID(),
                exerciseNameSnapshot: "Exercise \(index + 1)",
                orderIndex: index,
                targetSets: volume.sets,
                minReps: volume.minReps,
                maxReps: volume.maxReps
            )
        }
        let split = TrainingSplit(
            id: id,
            name: name,
            splitType: type,
            activeRotationIndex: 0,
            daysPerWeek: 5,
            exercises: exercises
        )
        let relativeVolumes = exercises.map { exercise in
            Double(max(exercise.targetSets, 0)) * max((Double(exercise.minReps) + Double(exercise.maxReps)) / 2, 0)
        }
        return (split, exercises.count, relativeVolumes)
    }
}

#Preview("Training day · Light") {
    let sample = SplitTrainingDayCardPreviewData.make(
        name: "Push",
        type: .pushPullLegs,
        volumes: [(4, 6, 8), (3, 8, 12), (3, 10, 14), (2, 12, 15)]
    )
    SplitTrainingDayCard(
        split: sample.split,
        status: .ready,
        lastTrainedText: "Last trained 4 days ago",
        focusDescription: "Chest · Shoulders · Triceps",
        exerciseCount: sample.exerciseCount,
        relativeVolumes: sample.relativeVolumes
    )
    .padding()
}

#Preview("Training day · Dark · Empty") {
    let sample = SplitTrainingDayCardPreviewData.make(name: "Recovery", type: .custom, volumes: [])
    SplitTrainingDayCard(
        split: sample.split,
        status: .inactive,
        lastTrainedText: "No history yet",
        focusDescription: "Custom",
        exerciseCount: sample.exerciseCount,
        relativeVolumes: sample.relativeVolumes
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Training day · Extreme profile") {
    let sample = SplitTrainingDayCardPreviewData.make(
        name: "Upper Strength and Hypertrophy",
        type: .upperLower,
        volumes: (0..<12).map { index in
            (index.isMultiple(of: 3) ? 5 : 2, 5 + index, 8 + index)
        }
    )
    SplitTrainingDayCard(
        split: sample.split,
        status: .prioritise,
        lastTrainedText: "Last trained 12 days ago",
        focusDescription: "Upper body · Chest · Back · Arms",
        exerciseCount: sample.exerciseCount,
        relativeVolumes: sample.relativeVolumes
    )
    .padding()
}
