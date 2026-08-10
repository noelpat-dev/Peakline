import SwiftUI

struct SubstitutionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    let title: String
    let candidates: [ExerciseSubstitutionCandidate]
    let select: (ExerciseSubstitutionCandidate) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Alternatives") {
                    if candidates.isEmpty {
                        Text("No close alternatives found.")
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                select(candidate)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    ExerciseIconView(
                                        iconKey: candidate.iconKey ?? .genericExercise,
                                        size: 34,
                                        showBackground: true,
                                        isDecorative: true
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.exerciseName)
                                            .font(.headline)
                                            .foregroundStyle(appTheme.colors.textPrimary)
                                        Text(candidate.reason)
                                            .font(.subheadline)
                                            .foregroundStyle(appTheme.colors.textSecondary)
                                        Text(PeaklineText.joinedMetadata([candidate.primaryMuscle, candidate.movementPattern, candidate.equipment].compactMap { $0 }))
                                            .font(.caption)
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-substitution-candidate-\(candidate.exerciseId.uuidString)")
                        }
                    }
                }
            }
            .peaklineGroupedContent()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("workout-substitution-sheet")
    }
}
