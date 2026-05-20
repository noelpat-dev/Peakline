import SwiftUI

struct WorkoutTemplateSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    let session: WorkoutSession
    let onSave: () -> Void

    @State private var templateName: String
    @State private var notes = ""
    @State private var errorText: String?

    private let builder = WorkoutTemplateBuilder()
    private let store = WorkoutTemplateStore()

    init(session: WorkoutSession, onSave: @escaping () -> Void = {}) {
        self.session = session
        self.onSave = onSave
        _templateName = State(initialValue: WorkoutTemplateBuilder().defaultName(for: session))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Template name", text: $templateName)
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Exercises Included") {
                    ForEach(session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }) { log in
                        HStack {
                            ExerciseIconView(
                                iconKey: ExerciseIconMapper.iconKey(for: log),
                                size: 30,
                                showBackground: true,
                                isDecorative: true
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.exerciseNameSnapshot)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(max(log.targetSets, 1)) sets - \(log.minReps)-\(log.maxReps) reps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(appTheme.dangerColor)
                    }
                }
            }
            .navigationTitle("Save Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            let template = builder.makeTemplate(from: session, name: templateName, notes: notes)
            try store.save(template)
            onSave()
            dismiss()
        } catch {
            errorText = "Could not save template: \(error.localizedDescription)"
        }
    }
}

