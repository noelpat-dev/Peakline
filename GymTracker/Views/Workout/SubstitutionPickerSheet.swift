import SwiftUI

struct SubstitutionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    let title: String
    let candidatesProvider: (ExerciseSubstitutionReason) -> [ExerciseSubstitutionCandidate]
    let select: (ExerciseSubstitutionCandidate, ExerciseSubstitutionReason) -> Void

    @State private var selectedReason: ExerciseSubstitutionReason = .equipmentBusy

    private var candidates: [ExerciseSubstitutionCandidate] {
        candidatesProvider(selectedReason)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ExerciseSubstitutionReason.allCases) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Alternatives") {
                    if candidates.isEmpty {
                        Text("No close alternatives found.")
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                select(candidate, selectedReason)
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
                                        Text([candidate.primaryMuscle, candidate.movementPattern, candidate.equipment].compactMap { $0 }.joined(separator: " - "))
                                            .font(.caption)
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
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
    }
}
