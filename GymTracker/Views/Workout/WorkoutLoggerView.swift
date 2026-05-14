import Foundation
import SwiftData
import SwiftUI

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession
    var isEditingCompletedWorkout = false

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @State private var selectedExerciseId: UUID?
    @State private var currentExerciseIndex = 0
    @State private var showingMotivation = false
    @State private var motivationMessage = "Keep going."
    @State private var motivationDetail = "One exercise banked. Keep the reps clean and own the next set."
    @State private var motivationButtonTitle = "Next Exercise"
    @State private var motivationSystemImage = "arrow.right.circle.fill"
    @State private var pendingExerciseIndex: Int?
    @State private var shouldDismissAfterMotivation = false
    @State private var showingWorkoutRating = false
    @State private var pendingWorkoutRating: WorkoutRating?

    private var orderedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var currentExerciseLog: ExerciseLog? {
        guard orderedExerciseLogs.indices.contains(currentExerciseIndex) else {
            return orderedExerciseLogs.first
        }

        return orderedExerciseLogs[currentExerciseIndex]
    }

    private var availableExercises: [Exercise] {
        guard
            let splitId = session.splitId,
            let split = activeSplits.first(where: { $0.id == splitId })
        else { return exercises }

        let allowedExerciseIds = Set(split.exercises.map(\.exerciseId))
        return exercises.filter { exercise in
            allowedExerciseIds.contains(exercise.id) || exercise.name == "Abdominal Crunch"
        }
    }

    var body: some View {
        List {
            if isEditingCompletedWorkout {
                editSessionContent
            } else {
                liveSessionContent
            }

            Section("Add Exercise") {
                Picker("Exercise", selection: $selectedExerciseId) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(availableExercises) { exercise in
                        Text(exercise.name).tag(Optional(exercise.id))
                    }
                }

                Button {
                    addSelectedExercise()
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
                .disabled(selectedExerciseId == nil)
                .buttonStyle(.borderless)
            }

            Section {
                Button {
                    finishWorkout()
                } label: {
                    Label(isEditingCompletedWorkout ? "Save Changes" : "Finish Workout", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
            }
        }
        .navigationTitle(session.splitNameSnapshot)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMotivation, onDismiss: handleMotivationDismiss) {
            MotivationView(
                message: motivationMessage,
                detail: motivationDetail,
                buttonTitle: motivationButtonTitle,
                systemImage: motivationSystemImage
            ) {
                showingMotivation = false
            }
        }
        .sheet(isPresented: $showingWorkoutRating, onDismiss: handleRatingDismiss) {
            WorkoutRatingView { rating in
                pendingWorkoutRating = rating
                showingWorkoutRating = false
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: orderedExerciseLogs.count) { _, _ in
            currentExerciseIndex = min(currentExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
        }
    }

    @ViewBuilder
    private var liveSessionContent: some View {
        Section {
            WorkoutTimerHeader(
                title: session.splitNameSnapshot,
                startedAt: session.startedAt ?? session.date,
                endedAt: session.endedAt,
                completedCount: min(currentExerciseIndex + 1, max(orderedExerciseLogs.count, 1)),
                totalCount: orderedExerciseLogs.count
            )
            TextField("Session notes", text: Binding($session.notes, replacingNilWith: ""))
        }

        if let currentExerciseLog {
            ExerciseLoggerSection(
                exerciseLog: currentExerciseLog,
                previousPerformance: previousPerformance(for: currentExerciseLog)
            )

            Section {
                Button {
                    continueToNextExercise()
                } label: {
                    Label(isLastExercise ? "Finish Workout" : "Continue", systemImage: isLastExercise ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.headline)
                }
            } footer: {
                Text(isLastExercise ? "Finish when today's final exercise is logged." : "Move forward when this exercise is done.")
            }
        } else {
            ContentUnavailableView(
                "No Exercises Selected",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Add an exercise below or start again from a split.")
            )
        }
    }

    @ViewBuilder
    private var editSessionContent: some View {
        Section("Session") {
            LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
            if let duration = sessionDurationText {
                LabeledContent("Duration", value: duration)
            }
            TextField("Session notes", text: Binding($session.notes, replacingNilWith: ""))
        }

        if orderedExerciseLogs.isEmpty {
            ContentUnavailableView(
                "No Exercises Logged",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Add an exercise below to repair this workout.")
            )
        } else {
            ForEach(orderedExerciseLogs) { exerciseLog in
                ExerciseLoggerSection(
                    exerciseLog: exerciseLog,
                    previousPerformance: previousPerformance(for: exerciseLog)
                )
            }
        }
    }

    private var isLastExercise: Bool {
        currentExerciseIndex >= orderedExerciseLogs.count - 1
    }

    private func previousPerformance(for exerciseLog: ExerciseLog) -> PreviousExercisePerformance? {
        for previousSession in completedSessions where previousSession.id != session.id {
            if let previousLog = previousSession.exerciseLogs.first(where: { $0.exerciseId == exerciseLog.exerciseId }) {
                let workingSets = previousLog.setLogs
                    .filter { !$0.isWarmup && ($0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil) }
                    .sorted { $0.setNumber < $1.setNumber }

                guard !workingSets.isEmpty else { return nil }

                let snapshots = workingSets.map { set in
                    PreviousSetSnapshot(weight: set.weight, reps: set.reps, rpe: set.rpe)
                }
                let summary = snapshots
                    .map { "\($0.formattedWeight)kg x \($0.reps)" }
                    .joined(separator: ", ")

                return PreviousExercisePerformance(summary: summary, workingSets: snapshots)
            }
        }

        return nil
    }

    private func addSelectedExercise() {
        guard
            let selectedExerciseId,
            let exercise = exercises.first(where: { $0.id == selectedExerciseId })
        else { return }

        let log = ExerciseLog(
            workoutSessionId: session.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: orderedExerciseLogs.count,
            targetSets: 2,
            minReps: 8,
            maxReps: 12
        )
        log.workoutSession = session
        session.exerciseLogs.append(log)
        self.selectedExerciseId = nil
        if orderedExerciseLogs.count == 1 {
            currentExerciseIndex = 0
        }
        try? modelContext.save()
    }

    private func continueToNextExercise() {
        guard !orderedExerciseLogs.isEmpty else { return }

        if isLastExercise {
            finishWorkout()
            return
        }

        pendingExerciseIndex = currentExerciseIndex + 1
        configureMotivation(
            message: MotivationMessage.next(),
            detail: "One exercise banked. Keep the reps clean and own the next set.",
            buttonTitle: "Next Exercise",
            systemImage: "arrow.right.circle.fill"
        )
        showingMotivation = true
    }

    private func handleMotivationDismiss() {
        if shouldDismissAfterMotivation {
            shouldDismissAfterMotivation = false
            dismiss()
            return
        }

        if let pendingExerciseIndex {
            currentExerciseIndex = min(pendingExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
            self.pendingExerciseIndex = nil
        }
    }

    private func handleRatingDismiss() {
        guard let pendingWorkoutRating else { return }
        self.pendingWorkoutRating = nil
        completeWorkout(rating: pendingWorkoutRating)
    }

    private func finishWorkout() {
        guard !isEditingCompletedWorkout else {
            markEnteredSetsComplete()
            try? modelContext.save()
            dismiss()
            return
        }

        if session.endedAt == nil {
            session.endedAt = Date()
        }

        markEnteredSetsComplete()
        showingWorkoutRating = true
    }

    private func completeWorkout(rating: WorkoutRating) {
        let end = Date()
        session.endedAt = session.endedAt ?? end
        session.completed = true
        session.perceivedDifficulty = rating.score

        if let startedAt = session.startedAt {
            session.durationMinutes = max(1, Int((session.endedAt ?? end).timeIntervalSince(startedAt) / 60))
        }

        try? modelContext.save()
        shouldDismissAfterMotivation = true
        configureMotivation(
            message: rating.completionTitle,
            detail: "\(rating.completionMessage) You spent \(durationText(startedAt: session.startedAt, endedAt: session.endedAt ?? end)) in the gym.",
            buttonTitle: "Done",
            systemImage: rating.systemImage
        )
        showingMotivation = true
    }

    private func markEnteredSetsComplete() {
        for set in session.exerciseLogs.flatMap(\.setLogs) where set.weight > 0 || set.reps > 0 || set.rpe != nil {
            set.completed = true
            set.isWarmup = false
        }
    }

    private func configureMotivation(message: String, detail: String, buttonTitle: String, systemImage: String) {
        motivationMessage = message
        motivationDetail = detail
        motivationButtonTitle = buttonTitle
        motivationSystemImage = systemImage
    }

    private var sessionDurationText: String? {
        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return durationText(startedAt: startedAt, endedAt: endedAt)
        }

        if let minutes = session.durationMinutes {
            return "\(minutes) min"
        }

        return nil
    }

    private func durationText(startedAt: Date?, endedAt: Date) -> String {
        guard let startedAt else { return "time" }
        return durationText(startedAt: startedAt, endedAt: endedAt)
    }

    private func durationText(startedAt: Date, endedAt: Date) -> String {
        let totalSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min \(seconds) sec"
        }

        if minutes > 0 {
            return "\(minutes) min \(seconds) sec"
        }

        return "\(seconds) sec"
    }
}

private struct PreviousExercisePerformance {
    let summary: String
    let workingSets: [PreviousSetSnapshot]
}

private struct WorkoutTimerHeader: View {
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let displayDate = endedAt ?? timeline.date

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(totalCount == 0 ? "No exercises selected" : "Exercise \(completedCount) of \(totalCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(elapsedText(at: displayDate))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.blue)
                }

                SwiftUI.ProgressView(value: totalCount == 0 ? 0 : Double(completedCount), total: Double(max(totalCount, 1)))
            }
            .padding(.vertical, 4)
        }
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct MotivationView: View {
    let message: String
    let detail: String
    let buttonTitle: String
    let systemImage: String
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)

            Text(message)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(detail)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.82))

            Button {
                continueAction()
            } label: {
                Label(buttonTitle, systemImage: systemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.blue)
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [.blue, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .presentationDetents([.medium])
    }
}

private struct WorkoutRating: Identifiable {
    let id: Int
    let face: String
    let title: String
    let completionTitle: String
    let completionMessage: String
    let systemImage: String

    var score: Int { id }

    static let options = [
        WorkoutRating(
            id: 1,
            face: "☹",
            title: "Rough",
            completionTitle: "Still logged.",
            completionMessage: "A rough workout still gives you data. Recover, eat, sleep, and let the next session be cleaner.",
            systemImage: "heart.fill"
        ),
        WorkoutRating(
            id: 2,
            face: "😐",
            title: "Okay",
            completionTitle: "Work done.",
            completionMessage: "Not every session has to feel electric. You showed up and kept the habit alive.",
            systemImage: "checkmark.circle.fill"
        ),
        WorkoutRating(
            id: 3,
            face: "🙂",
            title: "Good",
            completionTitle: "Good session.",
            completionMessage: "That was a solid training day. Keep the same intent next time and build from it.",
            systemImage: "hand.thumbsup.fill"
        ),
        WorkoutRating(
            id: 4,
            face: "😄",
            title: "Great",
            completionTitle: "Strong session.",
            completionMessage: "That one moved well. Use this as your signal to keep pushing progressive overload carefully.",
            systemImage: "bolt.fill"
        ),
        WorkoutRating(
            id: 5,
            face: "🤩",
            title: "Excellent",
            completionTitle: "Excellent work.",
            completionMessage: "That is exactly the kind of session worth remembering. Lock in the lesson and chase the next small jump.",
            systemImage: "star.fill"
        )
    ]
}

private struct WorkoutRatingView: View {
    let selectRating: (WorkoutRating) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How did it go?")
                    .font(.largeTitle.bold())
                Text("Rate the workout so the app can remember how the session felt, not just what you lifted.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(WorkoutRating.options) { rating in
                    Button {
                        selectRating(rating)
                    } label: {
                        VStack(spacing: 8) {
                            Text(rating.face)
                                .font(.system(size: 34))
                            Text(rating.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Your rating changes the completion message and is saved with this workout.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

private enum MotivationMessage {
    static let messages = [
        "Strong start.",
        "Keep going.",
        "Clean reps. Next one.",
        "That is momentum.",
        "Stack the work."
    ]

    static func next() -> String {
        messages.randomElement() ?? "Keep going."
    }
}

private struct PreviousSetSnapshot {
    let weight: Double
    let reps: Int
    let rpe: Double?

    var formattedWeight: String {
        weight.formatted(.number.precision(.fractionLength(weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct ExerciseLoggerSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exerciseLog: ExerciseLog
    let previousPerformance: PreviousExercisePerformance?

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
                Text("Last time: \(previousPerformance?.summary ?? "No previous data")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = exerciseLog.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper("Today's target sets: \(exerciseLog.targetSets)", value: $exerciseLog.targetSets, in: 1...10)
                    .font(.subheadline)
            }
            .swipeActions(edge: .trailing) {
                Button("Remove", role: .destructive) {
                    removeExerciseFromSession()
                }
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
                    addSet(copyPrevious: !orderedSets.isEmpty)
                } label: {
                    Label("Add Set", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var targetText: String {
        guard exerciseLog.targetSets > 0 else { return "No target set" }
        return "Target: \(exerciseLog.targetSets) sets x \(exerciseLog.minReps)-\(exerciseLog.maxReps) reps"
    }

    private func addSet(copyPrevious: Bool) {
        let previous = orderedSets.last
        let previousSessionSet = previousPerformance?.workingSets[safe: orderedSets.count] ?? previousPerformance?.workingSets.last
        let set = SetLog(
            exerciseLogId: exerciseLog.id,
            setNumber: orderedSets.count + 1,
            weight: setWeight(copyPrevious: copyPrevious, currentPrevious: previous, sessionPrevious: previousSessionSet),
            reps: setReps(copyPrevious: copyPrevious, currentPrevious: previous, sessionPrevious: previousSessionSet),
            rpe: copyPrevious ? previous?.rpe ?? previousSessionSet?.rpe : previousSessionSet?.rpe,
            isWarmup: false,
            completed: false
        )

        set.exerciseLog = exerciseLog
        exerciseLog.setLogs.append(set)
        try? modelContext.save()
    }

    private func setWeight(copyPrevious: Bool, currentPrevious: SetLog?, sessionPrevious: PreviousSetSnapshot?) -> Double {
        if copyPrevious, let currentPrevious {
            return currentPrevious.weight
        }

        return sessionPrevious?.weight ?? 0
    }

    private func setReps(copyPrevious: Bool, currentPrevious: SetLog?, sessionPrevious: PreviousSetSnapshot?) -> Int {
        if copyPrevious, let currentPrevious {
            return currentPrevious.reps
        }

        return sessionPrevious?.reps ?? exerciseLog.minReps
    }

    private func delete(_ setLog: SetLog) {
        exerciseLog.setLogs.removeAll { $0.id == setLog.id }
        modelContext.delete(setLog)

        for (index, set) in orderedSets.filter({ $0.id != setLog.id }).enumerated() {
            set.setNumber = index + 1
        }

        try? modelContext.save()
    }

    private func removeExerciseFromSession() {
        guard let session = exerciseLog.workoutSession else {
            modelContext.delete(exerciseLog)
            try? modelContext.save()
            return
        }

        session.exerciseLogs.removeAll { $0.id == exerciseLog.id }
        modelContext.delete(exerciseLog)

        for (index, log) in session.exerciseLogs.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            log.orderIndex = index
        }

        try? modelContext.save()
    }
}

private struct SetRowView: View {
    @Bindable var setLog: SetLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(setLog.setNumber)")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                SetValueEditor(
                    title: "Weight kg",
                    valueText: format(setLog.weight),
                    decrement: { setLog.weight = max(0, setLog.weight - 2.5) },
                    increment: { setLog.weight += 2.5 }
                ) {
                    NumberField(title: "Weight kg", value: $setLog.weight)
                }

                SetValueEditor(
                    title: "Reps",
                    valueText: "\(setLog.reps)",
                    decrement: { setLog.reps = max(0, setLog.reps - 1) },
                    increment: { setLog.reps += 1 }
                ) {
                    StepperNumberField(title: "Reps", value: $setLog.reps)
                }

                OptionalNumberField(title: "RPE", value: $setLog.rpe)
            }
        }
        .padding(.vertical, 4)
    }

    private func format(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct SetValueEditor<Field: View>: View {
    let title: String
    let valueText: String
    let decrement: () -> Void
    let increment: () -> Void
    let field: () -> Field

    init(
        title: String,
        valueText: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        @ViewBuilder field: @escaping () -> Field
    ) {
        self.title = title
        self.valueText = valueText
        self.decrement = decrement
        self.increment = increment
        self.field = field
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)

                Text(valueText)
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 36)

                Button(action: increment) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            field()
        }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
