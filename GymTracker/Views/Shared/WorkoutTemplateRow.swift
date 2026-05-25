import SwiftUI

struct WorkoutTemplateRow: View {
    @Environment(\.appTheme) private var appTheme

    let template: CustomWorkoutTemplate
    let start: () -> Void
    let delete: () -> Void

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: template.sourceSplitName ?? template.name),
                        size: 42,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                        Text(detailText)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()

                    Menu {
                        Button(role: .destructive) {
                            AppHaptics.warning()
                            delete()
                        } label: {
                            Label("Delete Template", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                if let notes = template.notes, !notes.isEmpty {
                    Text(notes)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Button {
                    AppHaptics.mediumImpact()
                    start()
                } label: {
                    Label("Start from Template", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
            }
        }
    }

    private var detailText: String {
        let source = template.sourceSplitName ?? "Custom"
        return "\(source) - \(template.exercises.count) exercises - updated \(template.updatedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
