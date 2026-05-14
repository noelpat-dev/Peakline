import SwiftData
import SwiftUI

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private var orderedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Started", value: (session.startedAt ?? session.date).formatted(date: .omitted, time: .shortened))
                TextField("Session notes", text: Binding($session.notes, replacingNilWith: ""))
            }

            ForEach(orderedExerciseLogs) { exerciseLog in
                ExerciseLoggerSection(
                    exerciseLog: exerciseLog,
                    previousSummary: previousSummary(for: exerciseLog)
                )
            }

            Section {
                Button {
                    finishWorkout()
                } label: {
                    Label("Finish Workout", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
            }
        }
        .navigationTitle(session.splitNameSnapshot)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previousSummary(for exerciseLog: ExerciseLog) -> String {
        for previousSession in completedSessions where previousSession.id != session.id {
            if let previousLog = previousSession.exerciseLogs.first(where: { $0.exerciseId == exerciseLog.exerciseId }) {
                let workingSets = previousLog.setLogs
                    .filter { $0.completed && !$0.isWarmup }
                    .sorted { $0.setNumber < $1.setNumber }

                guard !workingSets.isEmpty else { return "No previous data" }

                return workingSets
                    .map { set in
                        "\(formatWeight(set.weight)) x \(set.reps)"
                    }
                    .joined(separator: ", ")
            }
        }

        return "No previous data"
    }

    private func finishWorkout() {
        let end = Date()
        session.endedAt = end
        session.completed = true

        if let startedAt = session.startedAt {
            session.durationMinutes = max(1, Int(end.timeIntervalSince(startedAt) / 60))
        }

        try? modelContext.save()
        dismiss()
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct ExerciseLoggerSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exerciseLog: ExerciseLog
    let previousSummary: String

    private var orderedSets: [SetLog] {
        exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(exerciseLog.exerciseNameSnapshot)
                    .font(.headline)
                Text(targetText)
                    .foregroundStyle(.secondary)
                Text("Last time: \(previousSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedSets) { setLog in
                SetRowView(setLog: setLog)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            delete(setLog)
                        }
                    }
            }

            HStack {
                Button {
                    addSet(copyPrevious: false)
                } label: {
                    Label("Add Set", systemImage: "plus.circle")
                }

                Spacer()

                Button {
                    addSet(copyPrevious: true)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(orderedSets.isEmpty)
            }
        }
    }

    private var targetText: String {
        guard exerciseLog.targetSets > 0 else { return "No target set" }
        return "Target: \(exerciseLog.targetSets) sets x \(exerciseLog.minReps)-\(exerciseLog.maxReps) reps"
    }

    private func addSet(copyPrevious: Bool) {
        let previous = orderedSets.last
        let set = SetLog(
            exerciseLogId: exerciseLog.id,
            setNumber: orderedSets.count + 1,
            weight: copyPrevious ? previous?.weight ?? 0 : 0,
            reps: copyPrevious ? previous?.reps ?? exerciseLog.minReps : exerciseLog.minReps,
            rpe: copyPrevious ? previous?.rpe : nil,
            isWarmup: copyPrevious ? previous?.isWarmup ?? false : false,
            completed: copyPrevious ? previous?.completed ?? false : false
        )

        set.exerciseLog = exerciseLog
        exerciseLog.setLogs.append(set)
        try? modelContext.save()
    }

    private func delete(_ setLog: SetLog) {
        exerciseLog.setLogs.removeAll { $0.id == setLog.id }
        modelContext.delete(setLog)

        for (index, set) in orderedSets.filter({ $0.id != setLog.id }).enumerated() {
            set.setNumber = index + 1
        }

        try? modelContext.save()
    }
}

private struct SetRowView: View {
    @Bindable var setLog: SetLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(setLog.setNumber)")
                    .font(.headline)
                Spacer()
                Toggle("Warm-up", isOn: $setLog.isWarmup)
                    .labelsHidden()
                Toggle("Done", isOn: $setLog.completed)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                NumberField(title: "Weight", value: $setLog.weight)
                StepperNumberField(title: "Reps", value: $setLog.reps)
                OptionalNumberField(title: "RPE", value: $setLog.rpe)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        TextField(title, value: $value, format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
    }
}

private struct StepperNumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        TextField(title, value: $value, format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
    }
}

private struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?

    private var text: Binding<String> {
        Binding {
            guard let value else { return "" }
            return value.formatted(.number.precision(.fractionLength(0...1)))
        } set: { newValue in
            value = Double(newValue)
        }
    }

    var body: some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
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
