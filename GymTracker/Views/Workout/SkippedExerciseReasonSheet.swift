import SwiftUI

struct SkippedExerciseReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    let skippedLogs: [ExerciseLog]
    let save: ([UUID: SkippedExerciseReason]) -> Void
    let finishWithoutReasons: () -> Void

    @State private var selections: [UUID: SkippedExerciseReason] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You can tag why planned exercises were skipped. This appends a short note and keeps your workout history intact.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Section("Skipped Exercises") {
                    ForEach(skippedLogs) { log in
                        Picker(log.exerciseNameSnapshot, selection: selectionBinding(for: log)) {
                            Text("No reason").tag(Optional<SkippedExerciseReason>.none)
                            ForEach(SkippedExerciseReason.allCases) { reason in
                                Text(reason.displayName).tag(Optional(reason))
                            }
                        }
                    }
                }
            }
            .peaklineGroupedContent()
            .navigationTitle("Skipped Reasons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Finish Anyway") {
                        dismiss()
                        finishWithoutReasons()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Finish") {
                        dismiss()
                        save(selections)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func selectionBinding(for log: ExerciseLog) -> Binding<SkippedExerciseReason?> {
        Binding {
            selections[log.id]
        } set: { newValue in
            selections[log.id] = newValue
        }
    }
}
