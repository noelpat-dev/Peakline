import SwiftUI

struct SplitProgrammeCard: View {
    @Environment(\.appTheme) private var appTheme

    let splits: [TrainingSplit]
    let statuses: [String: SplitStatus]

    private var exerciseCount: Int {
        splits.reduce(0) { $0 + $1.exercises.count }
    }

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconTile(
                        iconKey: .genericExercise,
                        title: nil,
                        size: 58,
                        style: .compact
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Active Programme")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text("Push/Pull/Legs")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("\(splits.count) training days - \(exerciseCount) exercises")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 0)
                }

                Text("This is your active training programme.")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)

                HStack(spacing: 8) {
                    ForEach(splits) { split in
                        ProgrammeSplitChip(
                            name: split.name,
                            status: statuses[split.name] ?? .ready
                        )
                    }
                }
            }
        }
    }
}

private struct ProgrammeSplitChip: View {
    @Environment(\.appTheme) private var appTheme

    let name: String
    let status: SplitStatus

    var body: some View {
        HStack(spacing: 7) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.splitIconKey(for: name),
                size: 24,
                tint: tint,
                showBackground: true,
                isDecorative: true
            )

            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel("\(name), \(status.title)")
    }

    private var tint: Color {
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
