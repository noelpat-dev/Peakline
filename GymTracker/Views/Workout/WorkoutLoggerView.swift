import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var motivationPopupVisible = false
    @State private var motivationMessage = "Keep going."
    @State private var motivationDetail = "One exercise banked. Keep the reps clean and own the next set."
    @State private var motivationButtonTitle = "Next Exercise"
    @State private var motivationSystemImage = "arrow.right.circle.fill"
    @State private var pendingExerciseIndex: Int?
    @State private var shouldDismissAfterMotivation = false
    @State private var shouldShowSummaryAfterMotivation = false
    @State private var summarySession: WorkoutSession?
    @State private var showingWorkoutRating = false
    @State private var ratingPopupVisible = false
    @State private var restTimerState = RestTimerState()
    @State private var showingSkippedExerciseConfirmation = false
    @State private var showingSkippedReasonSheet = false
    @State private var showingWorkoutOrder = false
    @State private var motivationActionInFlight = false

    private let skippedReasonService = SkippedExerciseReasonService()

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
        ZStack {
            workoutList
                .blur(radius: reduceMotion ? 0 : (isPopupVisible ? 8 : 0))
                .allowsHitTesting(!isPopupMounted)

            if showingMotivation {
                motivationOverlay
                    .zIndex(10)
            }

            if showingWorkoutRating {
                WorkoutRatingOverlay(isVisible: ratingPopupVisible) { rating in
                    handleRatingSelection(rating)
                }
                .zIndex(20)
            }
        }
        .animation(AppMotion.popupEntrance(reduceMotion: reduceMotion), value: motivationPopupVisible)
        .animation(AppMotion.popupEntrance(reduceMotion: reduceMotion), value: ratingPopupVisible)
        .navigationTitle(session.splitNameSnapshot)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $summarySession) { session in
            SessionSummaryView(session: session)
        }
        .sheet(isPresented: $showingSkippedReasonSheet) {
            SkippedExerciseReasonSheet(
                skippedLogs: skippedReasonService.skippedLogs(in: session),
                save: applySkippedReasonsAndFinish,
                finishWithoutReasons: finishWorkout
            )
        }
        .alert("Finish with skipped exercises?", isPresented: $showingSkippedExerciseConfirmation) {
            Button("Keep Logging", role: .cancel) {}
            Button("Finish Anyway") {
                finishWorkout()
            }
            Button("Add Reasons") {
                showingSkippedReasonSheet = true
            }
        } message: {
            Text("Some planned exercises have no completed sets yet. You can finish anyway, or tag why they were skipped.")
        }
        .onChange(of: orderedExerciseLogs.count) { _, _ in
            withExerciseChangeAnimation {
                currentExerciseIndex = min(currentExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
            }
        }
    }

    private var isPopupMounted: Bool {
        showingMotivation || showingWorkoutRating
    }

    private var isPopupVisible: Bool {
        motivationPopupVisible || ratingPopupVisible
    }

    private var workoutList: some View {
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
                    requestFinishWorkout()
                } label: {
                    Label(isEditingCompletedWorkout ? "Save Changes" : "Finish Workout", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
        }
        .scrollContentBackground(.hidden)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .listSectionSpacing(12)
    }

    private var motivationOverlay: some View {
        WorkoutCelebrationOverlay(
            title: motivationMessage,
            message: motivationDetail,
            icon: motivationSystemImage,
            primaryActionTitle: motivationButtonTitle,
            primaryActionIcon: motivationSystemImage,
            style: motivationButtonTitle == "Done" ? .completedWorkout : .nextExercise,
            isVisible: motivationPopupVisible,
            isPrimaryActionDisabled: motivationActionInFlight
        ) {
            dismissMotivationOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var liveSessionContent: some View {
        Section {
            LiveWorkoutHeader(
                title: session.splitNameSnapshot,
                startedAt: session.startedAt ?? session.date,
                endedAt: session.endedAt,
                pausedAt: session.pausedAt,
                accumulatedPausedSeconds: session.accumulatedPausedSeconds,
                currentExerciseIndex: currentExerciseIndex,
                totalExercises: orderedExerciseLogs.count,
                togglePause: togglePause,
                finish: requestFinishWorkout
            )
        }

        Section {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Session notes", text: Binding($session.notes, replacingNilWith: ""))
                QuickNoteChipsView(text: Binding($session.notes, replacingNilWith: ""))
            }
        }

        Section("Rest Timer") {
            RestTimerView(state: $restTimerState)
        }

        Section {
            DisclosureGroup(isExpanded: $showingWorkoutOrder) {
                ForEach(Array(orderedExerciseLogs.enumerated()), id: \.element.id) { index, exerciseLog in
                    LiveWorkoutOrderRow(
                        exerciseName: exerciseLog.exerciseNameSnapshot,
                        iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                        positionText: "\(index + 1)",
                        isCurrent: exerciseLog.id == currentExerciseLog?.id,
                        canMoveUp: index > 0,
                        canMoveDown: index < orderedExerciseLogs.count - 1,
                        jump: {
                            withExerciseChangeAnimation {
                                currentExerciseIndex = index
                            }
                            showingWorkoutOrder = false
                        },
                        moveUp: {
                            moveExerciseLog(exerciseLog, offset: -1)
                        },
                        moveDown: {
                            moveExerciseLog(exerciseLog, offset: 1)
                        }
                    )
                }
            } label: {
                Label("Workout Order", systemImage: "arrow.up.arrow.down")
                    .font(.headline)
            }
            .tint(appTheme.actionColor)
        } footer: {
            Text("Reorder exercises if a station is busy, or jump straight to the machine that is free.")
        }

        if let currentExerciseLog {
            ExerciseLoggerSection(
                exerciseLog: currentExerciseLog,
                templateNote: templateNote(for: currentExerciseLog),
                previousPerformance: previousPerformance(for: currentExerciseLog),
                completedSessions: completedSessions,
                startRestTimer: startRestTimer
            )
            .id(currentExerciseLog.id)

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
                    templateNote: templateNote(for: exerciseLog),
                    previousPerformance: previousPerformance(for: exerciseLog),
                    completedSessions: completedSessions
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

    private func templateNote(for exerciseLog: ExerciseLog) -> String? {
        guard
            let splitId = session.splitId,
            let split = activeSplits.first(where: { $0.id == splitId })
        else { return nil }

        return split.exercises.first { splitExercise in
            splitExercise.exerciseId == exerciseLog.exerciseId
        }?.notes
    }

    private func moveExerciseLog(_ exerciseLog: ExerciseLog, offset: Int) {
        var logs = orderedExerciseLogs
        guard let index = logs.firstIndex(where: { $0.id == exerciseLog.id }) else { return }

        let newIndex = logs.index(index, offsetBy: offset)
        guard logs.indices.contains(newIndex) else { return }

        let currentId = currentExerciseLog?.id
        logs.swapAt(index, newIndex)

        for (orderIndex, log) in logs.enumerated() {
            log.orderIndex = orderIndex
        }

        if let currentId, let updatedCurrentIndex = logs.firstIndex(where: { $0.id == currentId }) {
            withExerciseChangeAnimation {
                currentExerciseIndex = updatedCurrentIndex
            }
        }

        try? modelContext.save()
    }

    private func continueToNextExercise() {
        guard !orderedExerciseLogs.isEmpty, !motivationActionInFlight, !showingMotivation else { return }

        if isLastExercise {
            requestFinishWorkout()
            return
        }

        pendingExerciseIndex = currentExerciseIndex + 1
        WorkoutFeedback.lightImpact()
        configureMotivation(
            message: MotivationMessage.next(),
            detail: "One exercise banked. Keep the reps clean and own the next set.",
            buttonTitle: "Next Exercise",
            systemImage: "arrow.right.circle.fill"
        )
        presentMotivationOverlay()
    }

    private func handleMotivationDismiss() {
        if shouldShowSummaryAfterMotivation {
            shouldShowSummaryAfterMotivation = false
            summarySession = session
            return
        }

        if shouldDismissAfterMotivation {
            shouldDismissAfterMotivation = false
            dismiss()
            return
        }

        if let pendingExerciseIndex {
            withExerciseChangeAnimation {
                currentExerciseIndex = min(pendingExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
            }
            self.pendingExerciseIndex = nil
        }
    }

    private func dismissMotivationOverlay() {
        guard showingMotivation, motivationPopupVisible, !motivationActionInFlight else { return }
        motivationActionInFlight = true

        Task { @MainActor in
            withAnimation(AppMotion.popupExit(reduceMotion: reduceMotion)) {
                motivationPopupVisible = false
            }

            try? await Task.sleep(nanoseconds: reduceMotion ? 10_000_000 : AppMotion.popupExitDuration)
            showingMotivation = false
            handleMotivationDismiss()
            motivationActionInFlight = false
        }
    }

    private func presentMotivationOverlay() {
        guard !showingMotivation else { return }

        showingMotivation = true
        motivationPopupVisible = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppMotion.popupMountDelay)
            guard showingMotivation else { return }

            withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                motivationPopupVisible = true
            }
        }
    }

    private func presentRatingOverlay() {
        guard !showingWorkoutRating else { return }

        showingWorkoutRating = true
        ratingPopupVisible = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppMotion.popupMountDelay)
            guard showingWorkoutRating else { return }

            withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                ratingPopupVisible = true
            }
        }
    }

    private func requestFinishWorkout() {
        if !isEditingCompletedWorkout && hasSkippedPlannedExercises {
            showingSkippedExerciseConfirmation = true
            return
        }

        finishWorkout()
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

        finalizePausedTime(at: session.endedAt ?? Date())
        markEnteredSetsComplete()
        restTimerState = RestTimerState()
        presentRatingOverlay()
    }

    private func handleRatingSelection(_ rating: WorkoutRating) {
        Task { @MainActor in
            withAnimation(AppMotion.popupExit(reduceMotion: reduceMotion)) {
                ratingPopupVisible = false
            }

            try? await Task.sleep(nanoseconds: reduceMotion ? 10_000_000 : AppMotion.popupExitDuration)
            showingWorkoutRating = false
            completeWorkout(rating: rating)
        }
    }

    private func applySkippedReasonsAndFinish(_ selections: [UUID: SkippedExerciseReason]) {
        for log in skippedReasonService.skippedLogs(in: session) {
            if let reason = selections[log.id] {
                skippedReasonService.append(reason: reason, to: log)
            }
        }

        try? modelContext.save()
        finishWorkout()
    }

    private func completeWorkout(rating: WorkoutRating) {
        let end = Date()
        session.endedAt = session.endedAt ?? end
        finalizePausedTime(at: session.endedAt ?? end)
        session.completed = true
        session.perceivedDifficulty = rating.score
        WorkoutSessionDateService.alignLoggedDateToStartDate(session)

        let activeSeconds = activeDurationSeconds(at: session.endedAt ?? end)
        session.durationSeconds = activeSeconds
        session.durationMinutes = max(1, Int(ceil(Double(activeSeconds) / 60)))

        try? modelContext.save()
        shouldShowSummaryAfterMotivation = true
        WorkoutFeedback.success()
        configureMotivation(
            message: rating.completionTitle,
            detail: "\(rating.completionMessage) You spent \(durationText(seconds: activeSeconds)) in the gym.",
            buttonTitle: "Done",
            systemImage: rating.systemImage
        )
        presentMotivationOverlay()
    }

    private func markEnteredSetsComplete() {
        for set in session.exerciseLogs.flatMap(\.setLogs) where set.weight > 0 || set.reps > 0 || set.rpe != nil {
            set.completed = true
        }
    }

    private func configureMotivation(message: String, detail: String, buttonTitle: String, systemImage: String) {
        motivationMessage = message
        motivationDetail = detail
        motivationButtonTitle = buttonTitle
        motivationSystemImage = systemImage
    }

    private func withExerciseChangeAnimation(_ update: @escaping () -> Void) {
        update()
    }

    private func togglePause() {
        let now = Date()

        if let pausedAt = session.pausedAt {
            session.accumulatedPausedSeconds += max(0, Int(now.timeIntervalSince(pausedAt)))
            session.pausedAt = nil
        } else {
            session.pausedAt = now
        }

        try? modelContext.save()
    }

    private func startRestTimer(exerciseName: String, nextSetNumber: Int) {
        restTimerState = RestTimerState(
            endDate: Date().addingTimeInterval(TimeInterval(restDuration(for: exerciseName))),
            exerciseName: exerciseName,
            nextSetNumber: nextSetNumber
        )
    }

    private func restDuration(for exerciseName: String) -> Int {
        guard let exercise = exercises.first(where: { $0.name == exerciseName }) else { return 90 }
        return exercise.isCompound ? 120 : 75
    }

    private var hasSkippedPlannedExercises: Bool {
        orderedExerciseLogs.contains { exerciseLog in
            exerciseLog.setLogs.allSatisfy { !$0.completed && $0.weight == 0 && $0.reps == 0 && $0.rpe == nil }
        }
    }

    private func finalizePausedTime(at date: Date) {
        guard let pausedAt = session.pausedAt else { return }
        session.accumulatedPausedSeconds += max(0, Int(date.timeIntervalSince(pausedAt)))
        session.pausedAt = nil
    }

    private func activeDurationSeconds(at date: Date) -> Int {
        guard let startedAt = session.startedAt else { return 0 }

        let livePauseSeconds: Int
        if let pausedAt = session.pausedAt {
            livePauseSeconds = max(0, Int(date.timeIntervalSince(pausedAt)))
        } else {
            livePauseSeconds = 0
        }

        return max(0, Int(date.timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds - livePauseSeconds)
    }

    private var sessionDurationText: String? {
        if let durationSeconds = session.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

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
        return durationText(seconds: totalSeconds)
    }

    private func durationText(seconds totalSeconds: Int) -> String {
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

private enum WorkoutFeedback {
    static func lightImpact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selectionChanged() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

private struct PreviousExercisePerformance {
    let summary: String
    let workingSets: [PreviousSetSnapshot]
}

private struct LiveWorkoutOrderRow: View {
    @Environment(\.appTheme) private var appTheme

    let exerciseName: String
    let iconKey: ExerciseIconKey
    let positionText: String
    let isCurrent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let jump: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ExerciseIconView(
                    iconKey: iconKey,
                    size: 36,
                    tint: isCurrent ? appTheme.colors.accent : appTheme.colors.textSecondary,
                    showBackground: true,
                    isDecorative: true
                )

                Text(positionText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? .white : appTheme.actionColor)
                    .frame(width: 16, height: 16)
                    .background(isCurrent ? appTheme.actionColor : appTheme.actionColor.opacity(0.14), in: Circle())
                    .offset(x: 4, y: -4)
            }

            Button {
                jump()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(isCurrent ? "Current exercise" : "Tap to jump here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.borderless)
            .tint(appTheme.actionColor)
        }
        .padding(.vertical, 4)
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

private struct WorkoutRatingOverlay: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isVisible: Bool
    let selectRating: (WorkoutRating) -> Void

    @State private var selectedRating: WorkoutRating?
    @State private var contentRevealed = false
    @State private var isTransitioning = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidGlassPopupBackdrop(isVisible: isVisible)
                .ignoresSafeArea()

            LiquidGlassPopupCard(cornerRadius: 32, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("How did it go?")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .minimumScaleFactor(0.82)

                        Text("Rate the workout so Peakline remembers how the session felt, not just what you lifted.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ratingOptions

                    Text("Saved with this workout and used for the completion message.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(contentRevealed ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (contentRevealed ? 0 : 8))
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .smoothPopupCardMotion(
                isVisible: isVisible,
                reduceMotion: reduceMotion,
                hiddenScale: 0.94,
                hiddenOffset: 30,
                anchor: .bottom
            )
        }
        .onAppear {
            updateContentVisibility(isVisible)
        }
        .onChange(of: isVisible) { _, newValue in
            updateContentVisibility(newValue)
        }
    }

    @ViewBuilder
    private var ratingOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(WorkoutRating.options) { rating in
                    ratingButton(for: rating)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], spacing: 10) {
                ForEach(WorkoutRating.options) { rating in
                    ratingButton(for: rating)
                }
            }
        }
    }

    private func ratingButton(for rating: WorkoutRating) -> some View {
        let isSelected = selectedRating?.id == rating.id

        return Button {
            choose(rating)
        } label: {
            VStack(spacing: 8) {
                Text(rating.face)
                    .font(.system(size: 34))

                Text(rating.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(WorkoutRatingButtonStyle(isSelected: isSelected))
        .disabled(selectedRating != nil || isTransitioning)
        .accessibilityLabel("\(rating.title) workout rating")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ rating: WorkoutRating) {
        guard selectedRating == nil, !isTransitioning else { return }

        isTransitioning = true
        WorkoutFeedback.selectionChanged()
        withAnimation(AppMotion.quickSpring(reduceMotion: reduceMotion)) {
            selectedRating = rating
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 40_000_000 : AppMotion.ratingSelectionDelay)
            selectRating(rating)
        }
    }

    private func updateContentVisibility(_ visible: Bool) {
        if reduceMotion {
            contentRevealed = visible
            return
        }

        if visible {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 70_000_000)
                guard isVisible else { return }

                withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                    contentRevealed = true
                }
            }
        } else {
            withAnimation(AppMotion.popupExit(reduceMotion: reduceMotion)) {
                contentRevealed = false
            }
        }
    }
}

private struct WorkoutRatingButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(appTheme.colors.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? appTheme.colors.accent.opacity(0.10) : .white.opacity(0.012))
            }
            .shadow(color: isSelected ? appTheme.colors.accent.opacity(0.14) : .black.opacity(0.08), radius: isSelected ? 12 : 5, y: isSelected ? 7 : 3)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : (isSelected ? 1.04 : 1)))
            .animation(AppMotion.quickSpring(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AppMotion.quickSpring(reduceMotion: reduceMotion), value: isSelected)
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
    @Environment(\.appTheme) private var appTheme
    @Bindable var exerciseLog: ExerciseLog
    let templateNote: String?
    let previousPerformance: PreviousExercisePerformance?
    let completedSessions: [WorkoutSession]
    var startRestTimer: (String, Int) -> Void = { _, _ in }

    @State private var showingNotes = false
    @State private var showingSubstitutionSheet = false

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    private let substitutionService = ExerciseSubstitutionService()

    private var orderedSets: [SetLog] {
        exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                        size: 50,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseLog.exerciseNameSnapshot)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)

                        Text(targetText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()

                    if !substitutionOptions.isEmpty {
                        Button {
                            showingSubstitutionSheet = true
                        } label: {
                            Label("Substitute", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderless)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Last time: \(previousPerformance?.summary ?? "No previous data")")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Text(coachCue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .lineLimit(2)
                }

                if let templateNote, !templateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(templateNote, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup(isExpanded: $showingNotes) {
                    ExerciseNotesEditor(
                        text: Binding($exerciseLog.notes, replacingNilWith: ""),
                        title: "Session exercise note",
                        placeholder: "Add setup changes, discomfort, or what to adjust next time."
                    )
                    .padding(.top, 8)
                } label: {
                    Label(noteLabel, systemImage: "note.text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.actionColor)
                }

                HStack(spacing: 10) {
                    Text("Target sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Spacer()

                    CompactTargetSetStepper(
                        value: exerciseLog.targetSets,
                        decrement: { exerciseLog.targetSets = max(1, exerciseLog.targetSets - 1) },
                        increment: { exerciseLog.targetSets = min(10, exerciseLog.targetSets + 1) }
                    )
                }
            }
            .padding(.vertical, 6)
            .swipeActions(edge: .trailing) {
                Button("Remove", role: .destructive) {
                    removeExerciseFromSession()
                }
                .tint(.red)
            }

            ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, setLog in
                SetRowView(
                    setLog: setLog,
                    previousSet: index > 0 ? orderedSets[index - 1] : nil,
                    lastSessionSet: previousPerformance?.workingSets[safe: index] ?? previousPerformance?.workingSets.last,
                    deleteAction: { delete(setLog) }
                ) {
                    startRestTimer(exerciseLog.exerciseNameSnapshot, nextSetNumber(after: setLog))
                }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            delete(setLog)
                        }
                        .tint(.red)
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
        .sheet(isPresented: $showingSubstitutionSheet) {
            SubstitutionPickerSheet(
                title: "Substitute \(exerciseLog.exerciseNameSnapshot)",
                candidatesProvider: { reason in
                    substitutionService.candidates(
                        for: exerciseLog.exerciseId,
                        in: exercises,
                        completedSessions: completedSessions,
                        reason: reason
                    )
                },
                select: substitute
            )
        }
    }

    private var targetText: String {
        guard exerciseLog.targetSets > 0 else { return "No target set" }
        return "Target: \(exerciseLog.targetSets) sets x \(exerciseLog.minReps)-\(exerciseLog.maxReps) reps"
    }

    private var noteLabel: String {
        guard let notes = exerciseLog.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Add exercise note"
        }

        return "Edit exercise note"
    }

    private var coachCue: String {
        guard let previousPerformance, let first = previousPerformance.workingSets.first else {
            return "Establish a controlled baseline today."
        }

        if orderedSets.isEmpty {
            return "Start near last session: \(first.formattedWeight)kg x \(first.reps)."
        }

        if orderedSets.contains(where: { $0.rpe ?? 0 >= 9 }) {
            return "High effort logged. Hold load steady and protect form."
        }

        return "If reps stay clean, aim for the top of the range before adding load."
    }

    private var substitutionOptions: [Exercise] {
        substitutionService.alternatives(for: exerciseLog.exerciseId, in: exercises)
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

    private func substitute(with exercise: Exercise) {
        exerciseLog.exerciseId = exercise.id
        exerciseLog.exerciseNameSnapshot = exercise.name
        try? modelContext.save()
    }

    private func substitute(candidate: ExerciseSubstitutionCandidate, reason: ExerciseSubstitutionReason) {
        guard let exercise = exercises.first(where: { $0.id == candidate.exerciseId }) else { return }
        let originalName = exerciseLog.exerciseNameSnapshot
        let note = substitutionService.substitutionNote(
            originalName: originalName,
            replacementName: exercise.name,
            reason: reason
        )

        if hasLoggedSets {
            guard let session = exerciseLog.workoutSession else { return }
            append(note, to: exerciseLog)
            let replacement = ExerciseLog(
                workoutSessionId: session.id,
                exerciseId: exercise.id,
                exerciseNameSnapshot: exercise.name,
                orderIndex: exerciseLog.orderIndex + 1,
                targetSets: exerciseLog.targetSets,
                minReps: exerciseLog.minReps,
                maxReps: exerciseLog.maxReps,
                notes: note
            )
            replacement.workoutSession = session
            session.exerciseLogs.append(replacement)

            for (index, log) in session.exerciseLogs.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
                log.orderIndex = index
            }
        } else {
            exerciseLog.exerciseId = exercise.id
            exerciseLog.exerciseNameSnapshot = exercise.name
            append(note, to: exerciseLog)
        }

        try? modelContext.save()
    }

    private var hasLoggedSets: Bool {
        exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
    }

    private func append(_ text: String, to exerciseLog: ExerciseLog) {
        let existing = exerciseLog.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !existing.localizedCaseInsensitiveContains(text) else { return }
        exerciseLog.notes = existing.isEmpty ? text : "\(existing)\n\(text)"
    }

    private func nextSetNumber(after setLog: SetLog) -> Int {
        let next = setLog.setNumber + 1
        return min(next, max(exerciseLog.targetSets, next))
    }
}

private struct SetRowView: View {
    @Environment(\.appTheme) private var appTheme
    @Bindable var setLog: SetLog
    let previousSet: SetLog?
    let lastSessionSet: PreviousSetSnapshot?
    let deleteAction: () -> Void
    let completedAction: () -> Void

    @State private var activeSheet: SetRowSheet?

    private var hasLoggedData: Bool {
        setLog.weight > 0 || setLog.reps > 0
    }

    private var effort: EffortLevel? {
        EffortLevel(rpe: setLog.rpe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Set \(setLog.setNumber)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)

                Spacer()

                if setLog.isWarmup {
                    SetStatusChip(title: "Warm-up", systemImage: "flame", color: appTheme.warningColor)
                }

                if hasLoggedData {
                    SetStatusChip(title: "Logged", systemImage: "checkmark.circle.fill", color: appTheme.successColor)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                StepperValueControl(
                    label: "Weight",
                    valueText: format(setLog.weight),
                    unitSuffix: "kg",
                    canDecrement: setLog.weight > 0,
                    decrement: { updateWeight(max(0, setLog.weight - 2.5)) },
                    increment: { updateWeight(setLog.weight + 2.5) },
                    edit: { activeSheet = .weight }
                )

                StepperValueControl(
                    label: "Reps",
                    valueText: "\(setLog.reps)",
                    unitSuffix: "reps",
                    canDecrement: setLog.reps > 0,
                    decrement: { updateReps(max(0, setLog.reps - 1)) },
                    increment: { updateReps(setLog.reps + 1) },
                    edit: { activeSheet = .reps }
                )
            }

            QuickSetControlsView(
                canCopyPrevious: previousSet != nil,
                canCopyLastSession: lastSessionSet != nil,
                suggestion: nextSetSuggestion,
                copyPrevious: copyPreviousSet,
                copyLastSession: copyLastSessionSet,
                markComplete: markComplete
            )

            HStack(spacing: 8) {
                Button {
                    activeSheet = .effort
                } label: {
                    Text(effort.map { "Effort: \($0.title)" } ?? "Effort Optional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(effort == nil ? appTheme.colors.textSecondary : appTheme.colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(effort == nil ? appTheme.colors.cardBackgroundElevated : appTheme.colors.accentSurface, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(effort == nil ? appTheme.colors.cardBorder : appTheme.colors.accent.opacity(0.36), lineWidth: 1)
                        )
                }
                .buttonStyle(.borderless)

                Spacer()

                Menu {
                    Button {
                        setLog.isWarmup.toggle()
                    } label: {
                        Label(setLog.isWarmup ? "Remove Warm-up" : "Mark Warm-up", systemImage: "flame")
                    }

                    Button {
                        activeSheet = .effort
                    } label: {
                        Label("Edit Effort", systemImage: "gauge.with.dots.needle.33percent")
                    }

                    Button {
                        activeSheet = .plates
                    } label: {
                        Label("Plate Calculator", systemImage: "scalemass")
                    }

                    Button(role: .destructive) {
                        deleteAction()
                    } label: {
                        Label("Delete Set", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            syncCompletedState()
        }
        .onChange(of: setLog.isWarmup) { _, _ in
            syncCompletedState()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .weight:
                NumericEntrySheet(
                    title: "Edit Weight",
                    value: format(setLog.weight),
                    keyboardType: .decimalPad,
                    save: { updateWeight(Double($0) ?? setLog.weight) }
                )
            case .reps:
                NumericEntrySheet(
                    title: "Edit Reps",
                    value: "\(setLog.reps)",
                    keyboardType: .numberPad,
                    save: { updateReps(Int($0) ?? setLog.reps) }
                )
            case .effort:
                EffortPickerSheet(selectedRPE: setLog.rpe) { rpe in
                    setLog.rpe = rpe
                    syncCompletedState()
                    activeSheet = nil
                }
            case .plates:
                NavigationStack {
                    PlateCalculatorView(targetWeight: setLog.weight)
                }
            }
        }
    }

    private func format(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }

    private func updateWeight(_ weight: Double) {
        setLog.weight = max(0, weight)
        syncCompletedState(triggerAction: true)
    }

    private func updateReps(_ reps: Int) {
        setLog.reps = max(0, reps)
        syncCompletedState(triggerAction: true)
    }

    private func copyPreviousSet() {
        guard let previousSet else { return }
        setLog.weight = previousSet.weight
        setLog.reps = previousSet.reps
        setLog.rpe = previousSet.rpe
        syncCompletedState()
    }

    private func copyLastSessionSet() {
        guard let lastSessionSet else { return }
        setLog.weight = lastSessionSet.weight
        setLog.reps = lastSessionSet.reps
        setLog.rpe = lastSessionSet.rpe
        syncCompletedState()
    }

    private func markComplete() {
        if !hasLoggedData {
            if let previousSet {
                setLog.weight = previousSet.weight
                setLog.reps = previousSet.reps
                setLog.rpe = previousSet.rpe
            } else if let lastSessionSet {
                setLog.weight = lastSessionSet.weight
                setLog.reps = lastSessionSet.reps
                setLog.rpe = lastSessionSet.rpe
            }
        }

        let wasCompleted = setLog.completed
        setLog.completed = hasLoggedData
        if setLog.completed, !wasCompleted, !setLog.isWarmup {
            completedAction()
        }
    }

    private var nextSetSuggestion: String {
        if let effort, effort.rawValue >= 9 {
            return "Drop 2.5kg or repeat if that felt too heavy."
        }

        if setLog.completed || hasLoggedData {
            return "Repeat \(format(setLog.weight))kg x \(setLog.reps), or add 1 rep if it moved well."
        }

        if let previousSet {
            return "Repeat \(format(previousSet.weight))kg x \(previousSet.reps)."
        }

        if let lastSessionSet {
            return "Start near last session: \(lastSessionSet.formattedWeight)kg x \(lastSessionSet.reps)."
        }

        return "Set a clean baseline, then adjust with the main controls."
    }

    private func syncCompletedState(triggerAction: Bool = false) {
        let shouldBeCompleted = hasLoggedData
        let wasCompleted = setLog.completed
        setLog.completed = shouldBeCompleted

        if triggerAction, shouldBeCompleted, !wasCompleted, !setLog.isWarmup {
            completedAction()
        }
    }
}

private enum SetRowSheet: Identifiable {
    case weight
    case reps
    case effort
    case plates

    var id: String {
        switch self {
        case .weight:
            return "weight"
        case .reps:
            return "reps"
        case .effort:
            return "effort"
        case .plates:
            return "plates"
        }
    }
}

private enum EffortLevel: Double, CaseIterable, Identifiable {
    case easy = 6
    case moderate = 7
    case hard = 8
    case veryHard = 9
    case max = 10

    var id: Double { rawValue }

    init?(rpe: Double?) {
        guard let rpe else { return nil }
        self.init(rawValue: rpe.rounded())
    }

    var title: String {
        switch self {
        case .easy:
            return "Easy"
        case .moderate:
            return "Moderate"
        case .hard:
            return "Hard"
        case .veryHard:
            return "Very Hard"
        case .max:
            return "Max"
        }
    }

    var detail: String {
        switch self {
        case .easy:
            return "RPE 6"
        case .moderate:
            return "RPE 7"
        case .hard:
            return "RPE 8"
        case .veryHard:
            return "RPE 9"
        case .max:
            return "RPE 10"
        }
    }
}

private struct EffortPickerSheet: View {
    @Environment(\.appTheme) private var appTheme
    let selectedRPE: Double?
    let select: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Effort")
                    .font(.title2.weight(.bold))
                Text("Optional intensity for coaching and progression.")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(EffortLevel.allCases) { effort in
                    Button {
                        select(effort.rawValue)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effort.title)
                                    .font(.headline)
                                Text(effort.detail)
                                    .font(.caption)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }

                            Spacer()

                            if EffortLevel(rpe: selectedRPE) == effort {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(appTheme.actionColor)
                            }
                        }
                        .padding(12)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(role: .destructive) {
                select(nil)
            } label: {
                Label("Clear Effort", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(selectedRPE == nil)
        }
        .padding(22)
        .presentationDetents([.medium])
    }
}

private struct NumericEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var value: String
    let keyboardType: UIKeyboardType
    let save: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(title, text: $value)
                        .keyboardType(keyboardType)
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

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(value)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}

private struct SetStatusChip: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct CompactTargetSetStepper: View {
    @Environment(\.appTheme) private var appTheme
    let value: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: decrement) {
                Image(systemName: "minus")
                    .frame(width: 34, height: 32)
            }
            .disabled(value <= 1)

            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.bold))
                .frame(minWidth: 30)

            Button(action: increment) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 32)
            }
            .disabled(value >= 10)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(appTheme.colors.textPrimary)
        .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
        .overlay(
            Capsule()
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        )
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

private struct TargetSetStepper: View {
    @Environment(\.appTheme) private var appTheme

    let value: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: decrement) {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .disabled(value <= 1)

            Text("\(value)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 24)
                .foregroundStyle(appTheme.colors.textPrimary)

            Button(action: increment) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .disabled(value >= 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(appTheme.colors.accent)
        .background(appTheme.colors.accentSurface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(appTheme.cardBorder, lineWidth: 1)
        }
        .buttonStyle(.plain)
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
