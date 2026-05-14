import SwiftData
import SwiftUI

struct SplitsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    @State private var showingAddSplit = false

    private var pplSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            splits.first { $0.name == name && $0.isActive }
        }
    }

    private var otherSplits: [TrainingSplit] {
        splits.filter { !PPLRotation.names.contains($0.name) || !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                if !pplSplits.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Push/Pull/Legs")
                                .font(.headline)
                            Text("\(pplSplits.count) training days - \(pplSplits.reduce(0) { $0 + $1.exercises.count }) exercises")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Training Days") {
                        ForEach(pplSplits) { split in
                            splitRow(split)
                        }
                    }
                }

                if !otherSplits.isEmpty {
                    Section(pplSplits.isEmpty ? "Splits" : "Other Splits") {
                        ForEach(otherSplits) { split in
                            splitRow(split)
                        }
                        .onDelete(perform: deleteOtherSplits)
                    }
                }
            }
            .navigationTitle("Splits")
            .toolbar {
                Button {
                    showingAddSplit = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingAddSplit) {
                AddSplitView()
            }
        }
    }

    private func splitRow(_ split: TrainingSplit) -> some View {
        NavigationLink {
            SplitDetailView(split: split)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(split.name)
                        .font(.headline)
                    if !split.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(split.exercises.count) exercises - PPL training day")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteOtherSplits(at offsets: IndexSet) {
        let deletableSplits = offsets.map { otherSplits[$0] }
        for split in deletableSplits {
            modelContext.delete(split)
        }
        try? modelContext.save()
    }

    private func deleteSplits(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(splits[index])
        }
        try? modelContext.save()
    }
}

private enum PPLRotation {
    static let names = ["Push", "Pull", "Legs"]
}

private struct SplitDetailView: View {
    @Bindable var split: TrainingSplit

    private var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: split.splitType.displayName)
                LabeledContent("Days per week", value: "\(split.daysPerWeek)")
                LabeledContent("Status", value: split.isActive ? "Active" : "Inactive")
            }

            Section("Exercises") {
                if orderedExercises.isEmpty {
                    Text("No exercises yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedExercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.exerciseNameSnapshot)
                                .font(.headline)
                            Text("\(exercise.targetSets) sets, \(exercise.minReps)-\(exercise.maxReps) reps")
                                .foregroundStyle(.secondary)
                            if let notes = exercise.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(split.name)
        .toolbar {
            NavigationLink {
                SplitEditorView(split: split)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}

private struct AddSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var splitType = SplitType.custom
    @State private var daysPerWeek = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Split") {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $splitType) {
                        ForEach(SplitType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Stepper("Days per week: \(daysPerWeek)", value: $daysPerWeek, in: 1...7)
                }
            }
            .navigationTitle("New Split")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSplit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createSplit() {
        let split = TrainingSplit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            splitType: splitType,
            daysPerWeek: daysPerWeek
        )
        modelContext.insert(split)
        try? modelContext.save()
        dismiss()
    }
}

private struct SplitEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var split: TrainingSplit

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var selectedExerciseId: UUID?

    private var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        Form {
            Section("Split") {
                TextField("Name", text: $split.name)

                Picker("Type", selection: $split.splitType) {
                    ForEach(SplitType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                Stepper("Days per week: \(split.daysPerWeek)", value: $split.daysPerWeek, in: 1...7)
                Toggle("Active", isOn: $split.isActive)
            }

            Section("Add Exercise") {
                Picker("Exercise", selection: $selectedExerciseId) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(exercises) { exercise in
                        Text(exercise.name).tag(Optional(exercise.id))
                    }
                }

                Button {
                    addSelectedExercise()
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
                .disabled(selectedExerciseId == nil)
            }

            Section("Exercises") {
                if orderedExercises.isEmpty {
                    Text("No exercises yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedExercises) { splitExercise in
                        SplitExerciseEditorRow(splitExercise: splitExercise)
                    }
                    .onDelete(perform: deleteExercises)
                    .onMove(perform: moveExercises)
                }
            }
        }
        .navigationTitle("Edit Split")
        .toolbar {
            EditButton()
        }
        .onDisappear {
            split.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func addSelectedExercise() {
        guard
            let selectedExerciseId,
            let exercise = exercises.first(where: { $0.id == selectedExerciseId })
        else { return }

        let splitExercise = SplitExercise(
            splitId: split.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: orderedExercises.count,
            targetSets: 2,
            minReps: 8,
            maxReps: 12,
            restSeconds: 120,
            notes: "Use double progression: add reps inside the target range before adding load."
        )
        splitExercise.split = split
        split.exercises.append(splitExercise)
        self.selectedExerciseId = nil
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func deleteExercises(at offsets: IndexSet) {
        let exercisesToDelete = offsets.map { orderedExercises[$0] }
        for exercise in exercisesToDelete {
            split.exercises.removeAll { $0.id == exercise.id }
            modelContext.delete(exercise)
        }
        renumberExercises()
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = orderedExercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() {
            exercise.orderIndex = index
        }
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func renumberExercises() {
        for (index, exercise) in orderedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }
}

private struct SplitExerciseEditorRow: View {
    @Bindable var splitExercise: SplitExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(splitExercise.exerciseNameSnapshot)
                .font(.headline)

            Stepper("Sets: \(splitExercise.targetSets)", value: $splitExercise.targetSets, in: 1...10)
            Stepper("Min reps: \(splitExercise.minReps)", value: $splitExercise.minReps, in: 1...50)
            Stepper("Max reps: \(splitExercise.maxReps)", value: $splitExercise.maxReps, in: max(splitExercise.minReps, 1)...50)
            Stepper("Rest: \(restText)", value: Binding($splitExercise.restSeconds, replacingNilWith: 120), in: 30...300, step: 15)
            TextField("Progression note", text: Binding($splitExercise.notes, replacingNilWith: ""), axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(.vertical, 4)
    }

    private var restText: String {
        guard let restSeconds = splitExercise.restSeconds else { return "not set" }
        return "\(restSeconds)s"
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init {
            source.wrappedValue ?? fallback
        } set: { newValue in
            source.wrappedValue = newValue.isEmpty ? nil : newValue
        }
    }
}

private extension Binding where Value == Int {
    init(_ source: Binding<Int?>, replacingNilWith fallback: Int) {
        self.init {
            source.wrappedValue ?? fallback
        } set: { newValue in
            source.wrappedValue = newValue
        }
    }
}
