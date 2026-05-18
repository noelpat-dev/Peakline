import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var showingAddExercise = false
    @State private var showingArchived = false

    private var visibleExercises: [Exercise] {
        exercises.filter { showingArchived || !$0.isArchived }
    }

    var body: some View {
        List {
            Section {
                Toggle("Show archived", isOn: $showingArchived)
            }

            Section("Exercises") {
                if visibleExercises.isEmpty {
                    Text(showingArchived ? "No exercises yet" : "No active exercises")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleExercises) { exercise in
                        NavigationLink {
                            ExerciseEditorView(exercise: exercise)
                        } label: {
                            ExerciseLibraryRow(exercise: exercise)
                        }
                    }
                    .onDelete(perform: archiveExercises)
                }
            }
        }
        .navigationTitle("Exercise Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                showingAddExercise = true
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseView()
        }
    }

    private func archiveExercises(at offsets: IndexSet) {
        for index in offsets {
            visibleExercises[index].isArchived = true
            visibleExercises[index].updatedAt = .now
        }
        try? modelContext.save()
    }
}

private struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: exercise),
                size: 34,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.name)
                        .font(.headline)

                    if exercise.isArchived {
                        Text("Archived")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(exercise.primaryMuscleGroup.displayName) - \(exercise.equipment.displayName) - \(exercise.movementPattern.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var primaryMuscleGroup = MuscleGroup.chest
    @State private var secondaryMuscleGroups: [MuscleGroup] = []
    @State private var movementPattern = MovementPattern.push
    @State private var equipment = EquipmentType.barbell
    @State private var isCompound = true

    var body: some View {
        NavigationStack {
            ExerciseForm(
                name: $name,
                primaryMuscleGroup: $primaryMuscleGroup,
                secondaryMuscleGroups: $secondaryMuscleGroups,
                movementPattern: $movementPattern,
                equipment: $equipment,
                isCompound: $isCompound
            )
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createExercise()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createExercise() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            movementPattern: movementPattern,
            equipment: equipment,
            isCompound: isCompound
        )
        modelContext.insert(exercise)
        try? modelContext.save()
        dismiss()
    }
}

private struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exercise: Exercise

    var body: some View {
        ExerciseForm(
            name: $exercise.name,
            primaryMuscleGroup: $exercise.primaryMuscleGroup,
            secondaryMuscleGroups: $exercise.secondaryMuscleGroups,
            movementPattern: $exercise.movementPattern,
            equipment: $exercise.equipment,
            isCompound: $exercise.isCompound,
            isArchived: $exercise.isArchived
        )
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            exercise.updatedAt = .now
            try? modelContext.save()
        }
    }
}

private struct ExerciseForm: View {
    @Binding var name: String
    @Binding var primaryMuscleGroup: MuscleGroup
    @Binding var secondaryMuscleGroups: [MuscleGroup]
    @Binding var movementPattern: MovementPattern
    @Binding var equipment: EquipmentType
    @Binding var isCompound: Bool
    var isArchived: Binding<Bool>?

    var body: some View {
        Form {
            Section("Exercise") {
                TextField("Name", text: $name)

                Picker("Primary muscle", selection: $primaryMuscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in
                        Text(group.displayName).tag(group)
                    }
                }

                DisclosureGroup("Secondary muscles") {
                    ForEach(MuscleGroup.allCases) { group in
                        if group != primaryMuscleGroup {
                            Toggle(group.displayName, isOn: secondaryMuscleBinding(for: group))
                        }
                    }
                }

                Picker("Pattern", selection: $movementPattern) {
                    ForEach(MovementPattern.allCases) { pattern in
                        Text(pattern.displayName).tag(pattern)
                    }
                }

                Picker("Equipment", selection: $equipment) {
                    ForEach(EquipmentType.allCases) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }

                Toggle("Compound lift", isOn: $isCompound)
            }

            if let isArchived {
                Section("Library") {
                    Toggle("Archived", isOn: isArchived)
                }
            }
        }
        .onChange(of: primaryMuscleGroup) { _, newPrimaryMuscleGroup in
            secondaryMuscleGroups.removeAll { $0 == newPrimaryMuscleGroup }
        }
    }

    private func secondaryMuscleBinding(for group: MuscleGroup) -> Binding<Bool> {
        Binding {
            secondaryMuscleGroups.contains(group)
        } set: { isSelected in
            if isSelected {
                if !secondaryMuscleGroups.contains(group) {
                    secondaryMuscleGroups.append(group)
                }
            } else {
                secondaryMuscleGroups.removeAll { $0 == group }
            }
        }
    }
}
