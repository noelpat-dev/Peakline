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
    var onSummaryDone: (() -> Void)?

    @State private var selectedExerciseId: UUID?
    @State private var currentExerciseIndex = 0
    @State private var overlayPhase: WorkoutOverlayPhase = .idle
    @State private var overlayVisible = false
    @State private var celebrationPresentation = WorkoutCelebrationPresentation.initial
    @State private var motivationRotation: WorkoutMotivationRotation
    @State private var pendingExerciseIndex: Int?
    @State private var summaryRoute: WorkoutSummaryRoute?
    @State private var summaryRenderSnapshot: SessionSummaryRenderSnapshot?
    @State private var restTimerState = RestTimerState()
    @State private var showingSkippedExerciseConfirmation = false
    @State private var showingSkippedReasonSheet = false
    @State private var shouldPresentSkippedReasonsAfterAlert = false
    @State private var pendingFinishAfterModal = false
    @State private var showingWorkoutOrder = false
    @State private var overlayActionInFlight = false
    @State private var completionErrorMessage: String?
    @State private var previousPerformanceByExerciseId: [UUID: PreviousExercisePerformance] = [:]
    @State private var previousPerformanceSignature: String?
    @State private var orderedExerciseLogsCache: [ExerciseLog] = []
    @State private var orderedExerciseLogsSignature: String?
    @State private var templateNotesByExerciseId: [UUID: String] = [:]
    @State private var templateNotesSignature: String?
    @State private var substitutionRequest: WorkoutSubstitutionRequest?
    @State private var pendingSkippedReasonSelections: [UUID: SkippedExerciseReason] = [:]
    @State private var isCompletionCommitted = false
    @State private var didSuspendWarmRefreshForCompletion = false
    @State private var completedSessions: [WorkoutSession] = []
    @State private var exercises: [Exercise] = []
    @State private var activeSplits: [TrainingSplit] = []
    @State private var didLoadReferenceData = false
    @State private var editDurationHours: Int
    @State private var editDurationMinutes: Int
    @State private var pendingOutlierDurationSeconds: Int?
    @State private var acceptedOutlierDurationSeconds: Int?
    @State private var completionDurationOverrideSeconds: Int?
    @State private var showingDurationOutlierConfirmation = false
    @State private var showingDurationCorrectionSheet = false

    private let skippedReasonService = SkippedExerciseReasonService()
    private let substitutionService = ExerciseSubstitutionService()
    private let durationService = WorkoutSessionDurationService()

    init(
        session: WorkoutSession,
        isEditingCompletedWorkout: Bool = false,
        onSummaryDone: (() -> Void)? = nil
    ) {
        self.session = session
        self.isEditingCompletedWorkout = isEditingCompletedWorkout
        self.onSummaryDone = onSummaryDone
        _motivationRotation = State(initialValue: WorkoutMotivationRotation(sessionID: session.id))
        let durationSeconds = WorkoutSessionDurationService().recordedDurationSeconds(for: session) ?? 0
        _editDurationHours = State(initialValue: durationSeconds / 3_600)
        _editDurationMinutes = State(initialValue: (durationSeconds % 3_600) / 60)
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var orderedExerciseLogs: [ExerciseLog] {
        if orderedExerciseLogsSignature == exerciseLogOrderSignature {
            return orderedExerciseLogsCache
        }

        return session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var currentExerciseLog: ExerciseLog? {
        guard orderedExerciseLogs.indices.contains(currentExerciseIndex) else {
            return orderedExerciseLogs.first
        }

        return orderedExerciseLogs[currentExerciseIndex]
    }

    var body: some View {
        ZStack {
            if isCompletionCommitted {
                appTheme.colors.backgroundPrimary
                    .ignoresSafeArea()
            } else {
                workoutList
                    .allowsHitTesting(!isPopupMounted)
            }

            if overlayPhase.showsCelebration {
                motivationOverlay
                    .zIndex(10)
            }

            if overlayPhase.showsRating {
                WorkoutRatingOverlay(isVisible: overlayVisible) { rating in
                    handleRatingSelection(rating)
                }
                .zIndex(20)
            }
        }
        .peaklineKeyboardDismissal()
        .navigationTitle(session.splitNameSnapshot)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $summaryRoute) { route in
            if route.sessionID == session.id, let summaryRenderSnapshot {
                SessionSummaryView(session: session, snapshot: summaryRenderSnapshot) {
                    summaryRoute = nil
                    DispatchQueue.main.async {
                        if let onSummaryDone {
                            onSummaryDone()
                        } else {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    let navigationKey = summaryNavigationKey
                    NavigationInteraction.destinationDidAppear(key: navigationKey)
                    AppMotion.withoutAnimation {
                        overlayVisible = false
                        overlayPhase = .idle
                        overlayActionInFlight = false
                    }
                    PerformanceTracer.mark(.workoutLoggerFinish, "summary_stable_frame")
                }
                .onDisappear {
                    finishCompletionPresentation()
                }
            } else {
                ContentUnavailableView(
                    "Summary unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This workout could not be resolved.")
                )
            }
        }
        .sheet(isPresented: $showingSkippedReasonSheet, onDismiss: {
            if !pendingFinishAfterModal {
                pendingSkippedReasonSelections = [:]
            }
            consumePendingFinishAfterModal()
        }) {
            SkippedExerciseReasonSheet(
                skippedLogs: skippedReasonService.skippedLogs(in: session),
                save: applySkippedReasonsAndFinish,
                finishWithoutReasons: {
                    pendingSkippedReasonSelections = [:]
                    pendingFinishAfterModal = true
                }
            )
            .sheetContentEntrance()
        }
        .sheet(item: $substitutionRequest) { request in
            SubstitutionPickerSheet(
                title: request.title,
                candidates: request.candidates
            ) { candidate in
                applySubstitution(request: request, candidate: candidate)
            }
            .sheetContentEntrance()
        }
        .confirmationDialog(
            "Check workout duration",
            isPresented: $showingDurationOutlierConfirmation,
            titleVisibility: .visible
        ) {
            Button("Edit Duration") {
                let duration = pendingOutlierDurationSeconds ?? 0
                editDurationHours = duration / 3_600
                editDurationMinutes = (duration % 3_600) / 60
                DispatchQueue.main.async {
                    showingDurationCorrectionSheet = true
                }
            }
            Button("Use Recorded Time") {
                acceptedOutlierDurationSeconds = pendingOutlierDurationSeconds
                finishWorkout()
            }
            Button("Cancel", role: .cancel) {
                cancelDurationCheck()
            }
        } message: {
            Text("Peakline recorded \(durationText(seconds: pendingOutlierDurationSeconds ?? 0)). Confirm it or correct the duration before rating this workout.")
        }
        .sheet(isPresented: $showingDurationCorrectionSheet, onDismiss: {
            if pendingOutlierDurationSeconds != nil,
               completionDurationOverrideSeconds == nil {
                cancelDurationCheck()
            }
        }) {
            WorkoutDurationEditorSheet(
                initialHours: editDurationHours,
                initialMinutes: editDurationMinutes
            ) { hours, minutes in
                let correctedSeconds = (hours * 60 + minutes) * 60
                editDurationHours = hours
                editDurationMinutes = minutes
                completionDurationOverrideSeconds = correctedSeconds
                acceptedOutlierDurationSeconds = correctedSeconds
                pendingOutlierDurationSeconds = nil
                finishWorkout()
            }
            .sheetContentEntrance()
            .presentationDetents([.medium])
        }
        .alert("Finish with skipped exercises?", isPresented: $showingSkippedExerciseConfirmation) {
            Button("Keep Logging", role: .cancel) {}
            Button("Finish Anyway") {
                confirmSkippedAndFinish()
            }
            Button("Add Reasons") {
                shouldPresentSkippedReasonsAfterAlert = true
            }
        } message: {
            Text("Some planned exercises have no completed sets yet. You can finish anyway, or tag why they were skipped.")
        }
        .alert("Couldn’t finish workout", isPresented: completionErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(completionErrorMessage ?? "Peakline could not save this workout. Please try again.")
        }
        .onChange(of: showingSkippedExerciseConfirmation) { _, isPresented in
            guard !isPresented else { return }
            if shouldPresentSkippedReasonsAfterAlert {
                shouldPresentSkippedReasonsAfterAlert = false
                showingSkippedReasonSheet = true
            } else {
                consumePendingFinishAfterModal()
            }
        }
        .onChange(of: orderedExerciseLogs.count) { _, _ in
            guard !isCompletionCommitted else { return }
            withExerciseChangeAnimation {
                currentExerciseIndex = min(currentExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
            }
            refreshOrderedExerciseLogsCache()
            refreshTemplateNotesCache()
            refreshPreviousPerformanceCache()
        }
        .onAppear {
            refreshOrderedExerciseLogsCache(force: true)
        }
        .task(id: session.id) { @MainActor in
            // Let the logger paint from the already-loaded live session before
            // fetching optional history, exercise-library, and template data.
            await Task.yield()
            guard !Task.isCancelled else { return }
            loadReferenceDataIfNeeded()
            guard !Task.isCancelled else { return }
            refreshTemplateNotesCache(force: true)
            refreshPreviousPerformanceCache(force: true)
        }
        .onChange(of: previousPerformanceInputSignature) { _, _ in
            guard !isCompletionCommitted else { return }
            refreshPreviousPerformanceCache()
        }
        .onChange(of: exerciseLogOrderSignature) { _, _ in
            guard !isCompletionCommitted else { return }
            refreshOrderedExerciseLogsCache()
        }
        .onChange(of: templateNotesInputSignature) { _, _ in
            guard !isCompletionCommitted else { return }
            refreshTemplateNotesCache()
        }
    }

    private var isPopupMounted: Bool {
        overlayPhase != .idle
    }

    private var completionErrorBinding: Binding<Bool> {
        Binding {
            completionErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                completionErrorMessage = nil
            }
        }
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
                .buttonStyle(.borderless)
            }

            if isEditingCompletedWorkout {
                Section {
                    Button {
                        requestFinishWorkout()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.sectionTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .disabled(editableDurationSeconds < 60)
                    .accessibilityIdentifier("workout-logger-save-changes")
                }
            }
        }
        .peaklineGroupedContent()
        .listSectionSpacing(12)
        .accessibilityIdentifier("workout-logger-screen")
    }

    private var motivationOverlay: some View {
        WorkoutCelebrationOverlay(
            title: celebrationPresentation.title,
            message: celebrationPresentation.message,
            icon: celebrationPresentation.systemImage,
            primaryActionTitle: celebrationPresentation.primaryActionTitle,
            primaryActionIcon: celebrationPresentation.systemImage,
            style: celebrationPresentation.style,
            isVisible: overlayVisible,
            isPrimaryActionDisabled: overlayActionInFlight
        ) {
            dismissMotivationOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(celebrationAccessibilityLabel)
        .accessibilityValue("\(celebrationPresentation.title)|\(celebrationPresentation.message)")
        .accessibilityIdentifier(overlayPhase == .nextExercise ? "workout-transition-copy" : "workout-completion-copy")
    }

    private var celebrationAccessibilityLabel: String {
        switch celebrationPresentation.style {
        case .pr:
            return "Personal record workout completion"
        case .completedWorkout:
            return "Workout completion"
        case .nextExercise:
            return "Workout transition"
        case .recovery:
            return "Recovery workout completion"
        }
    }

    @ViewBuilder
    private var liveSessionContent: some View {
        Section {
            LiveWorkoutHeader(
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

        if restTimerState.endDate != nil {
            Section {
                RestTimerView(state: $restTimerState)
            }
            .transition(AppMotion.sheetInnerContentTransition(reduceMotion: reduceMotion))
        }

        Section {
            RestTimerView(state: $restTimerState, showsActiveTimer: false)
        } header: {
            Text("Rest Timer")
        } footer: {
            Text("Start a rest timer manually when you need one.")
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
                    .font(AppTypography.sectionTitle)
            }
            .tint(appTheme.actionColor)
        } footer: {
            Text("Reorder exercises if a station is busy, or jump straight to the machine that is free.")
        }

        if let currentExerciseLog {
            ExerciseLoggerSection(
                session: session,
                exerciseLog: currentExerciseLog,
                contextLabel: "Current exercise - \(currentExerciseIndex + 1) of \(orderedExerciseLogs.count)",
                templateNote: templateNote(for: currentExerciseLog),
                previousPerformance: previousPerformanceByExerciseId[currentExerciseLog.exerciseId],
                isCompletedWorkout: isEditingCompletedWorkout || session.completed,
                canSubstitute: hasSubstitutionCandidates(for: currentExerciseLog),
                requestSubstitution: { requestSubstitution(for: currentExerciseLog) },
                reportPersistenceError: { message in
                    refreshOrderedExerciseLogsCache(force: true)
                    completionErrorMessage = message
                }
            )
            .id(currentExerciseLog.id)

            Section {
                Button {
                    continueToNextExercise()
                } label: {
                    Label(isLastExercise ? "Finish Workout" : "Continue", systemImage: isLastExercise ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(AppTypography.sectionTitle)
                }
                .accessibilityIdentifier(isLastExercise ? "workout-logger-current-finish" : "workout-logger-continue")
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
            Stepper("Hours: \(editDurationHours)", value: $editDurationHours, in: 0...23)
                .accessibilityIdentifier("workout-edit-duration-hours")
            Stepper("Minutes: \(editDurationMinutes)", value: $editDurationMinutes, in: 0...59)
                .accessibilityIdentifier("workout-edit-duration-minutes")
            LabeledContent("Duration", value: editableDurationText)
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
                    session: session,
                    exerciseLog: exerciseLog,
                    templateNote: templateNote(for: exerciseLog),
                    previousPerformance: previousPerformanceByExerciseId[exerciseLog.exerciseId],
                    isCompletedWorkout: isEditingCompletedWorkout || session.completed,
                    canSubstitute: hasSubstitutionCandidates(for: exerciseLog),
                    requestSubstitution: { requestSubstitution(for: exerciseLog) },
                    reportPersistenceError: { message in
                        refreshOrderedExerciseLogsCache(force: true)
                        completionErrorMessage = message
                    }
                )
            }
        }
    }

    private var isLastExercise: Bool {
        currentExerciseIndex >= orderedExerciseLogs.count - 1
    }

    private var editableDurationSeconds: Int {
        (editDurationHours * 60 + editDurationMinutes) * 60
    }

    private var editableDurationText: String {
        guard editableDurationSeconds >= 60 else { return "Enter at least 1 minute" }
        return durationText(seconds: editableDurationSeconds)
    }

    private var previousPerformanceInputSignature: String {
        if isCompletionCommitted {
            return previousPerformanceSignature ?? "completion-committed"
        }

        return [
            session.id.uuidString,
            orderedExerciseLogs.map { "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.orderIndex)" }.joined(separator: ","),
            completedSessions.prefix(40).map { completedSession in
                // Keep view invalidation bounded to session metadata. Traversing
                // every historical relationship here makes SwiftUI evaluate
                // lazy SwiftData relationships repeatedly during a push.
                "\(completedSession.id.uuidString):\(completedSession.endedAt?.timeIntervalSince1970 ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "|")
    }

    private var exerciseLogOrderSignature: String {
        if isCompletionCommitted {
            return orderedExerciseLogsSignature ?? "completion-committed"
        }

        return session.exerciseLogs
            .map { "\($0.id.uuidString):\($0.orderIndex)" }
            .sorted()
            .joined(separator: ",")
    }

    private var templateNotesInputSignature: String {
        if isCompletionCommitted {
            return templateNotesSignature ?? "completion-committed"
        }

        return [
            session.splitId?.uuidString ?? "none",
            activeSplits.map { split in
                // `updatedAt` already invalidates edits to the template. Avoid
                // walking the template relationship from `body`.
                "\(split.id.uuidString):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|")
        ].joined(separator: "|")
    }

    private func refreshOrderedExerciseLogsCache(force: Bool = false) {
        let signature = exerciseLogOrderSignature
        guard force || signature != orderedExerciseLogsSignature else { return }
        orderedExerciseLogsCache = session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
        orderedExerciseLogsSignature = signature
    }

    private func refreshTemplateNotesCache(force: Bool = false) {
        let signature = templateNotesInputSignature
        guard force || signature != templateNotesSignature else { return }

        guard
            let splitId = session.splitId,
            let split = activeSplits.first(where: { $0.id == splitId })
        else {
            templateNotesByExerciseId = [:]
            templateNotesSignature = signature
            return
        }

        var notesByExerciseId: [UUID: String] = [:]
        for splitExercise in split.exercises {
            if let notes = splitExercise.notes {
                notesByExerciseId[splitExercise.exerciseId] = notes
            }
        }
        templateNotesByExerciseId = notesByExerciseId
        templateNotesSignature = signature
    }

    private func refreshPreviousPerformanceCache(force: Bool = false) {
        let signature = previousPerformanceInputSignature
        guard force || signature != previousPerformanceSignature else { return }

        previousPerformanceByExerciseId = PerformanceTracer.trace(.workoutLoggerPreviousPerformance) {
            WorkoutLoggerPerformanceCache.previousPerformanceByExerciseId(
                for: orderedExerciseLogs,
                currentSessionId: session.id,
                completedSessions: Array(completedSessions.prefix(40))
            )
        }
        previousPerformanceSignature = signature
    }

    @MainActor
    private func loadReferenceDataIfNeeded() {
        guard !didLoadReferenceData else { return }
        didLoadReferenceData = true

        do {
            completedSessions = try modelContext.fetch(Self.completedSessionsDescriptor)

            var exerciseDescriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate<Exercise> { !$0.isArchived },
                sortBy: [SortDescriptor(\.name)]
            )
            exerciseDescriptor.fetchLimit = 500
            exercises = try modelContext.fetch(exerciseDescriptor)

            var splitDescriptor = FetchDescriptor<TrainingSplit>(
                predicate: #Predicate<TrainingSplit> { $0.isActive },
                sortBy: [SortDescriptor(\.name)]
            )
            splitDescriptor.fetchLimit = 32
            activeSplits = try modelContext.fetch(splitDescriptor)
        } catch {
            completedSessions = []
            exercises = []
            activeSplits = []
        }
    }

    private func addSelectedExercise() {
        PerformanceTracer.trace(.workoutLoggerAddExercise) {
            guard
                let selectedExerciseId,
                let exercise = exercises.first(where: { $0.id == selectedExerciseId })
            else { return }

            let transaction = WorkoutLoggerPersistenceTransaction(session: session)
            do {
                try transaction.perform(in: modelContext) {
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
                }
                self.selectedExerciseId = nil
                refreshOrderedExerciseLogsCache(force: true)
                if orderedExerciseLogs.count == 1 {
                    currentExerciseIndex = 0
                }
            } catch {
                refreshOrderedExerciseLogsCache(force: true)
                completionErrorMessage = "Peakline could not add this exercise. Please try again."
            }
        }
    }

    private func templateNote(for exerciseLog: ExerciseLog) -> String? {
        templateNotesByExerciseId[exerciseLog.exerciseId]
    }

    private func moveExerciseLog(_ exerciseLog: ExerciseLog, offset: Int) {
        var logs = orderedExerciseLogs
        guard let index = logs.firstIndex(where: { $0.id == exerciseLog.id }) else { return }

        let newIndex = logs.index(index, offsetBy: offset)
        guard logs.indices.contains(newIndex) else { return }

        let currentId = currentExerciseLog?.id
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        do {
            try transaction.perform(in: modelContext) {
                logs.swapAt(index, newIndex)

                for (orderIndex, log) in logs.enumerated() {
                    log.orderIndex = orderIndex
                }
            }

            refreshOrderedExerciseLogsCache(force: true)
            if let currentId, let updatedCurrentIndex = logs.firstIndex(where: { $0.id == currentId }) {
                withExerciseChangeAnimation {
                    currentExerciseIndex = updatedCurrentIndex
                }
            }
        } catch {
            refreshOrderedExerciseLogsCache(force: true)
            completionErrorMessage = "Peakline could not save this exercise order. Please try again."
        }
    }

    private func continueToNextExercise() {
        guard !orderedExerciseLogs.isEmpty, !overlayActionInFlight, overlayPhase == .idle else { return }

        if isLastExercise {
            requestFinishWorkout()
            return
        }

        pendingExerciseIndex = currentExerciseIndex + 1
        AppHaptics.lightImpact()
        let transitionMessage = motivationRotation.next()
        configureCelebration(
            .nextExercise(
                title: transitionMessage.title,
                message: transitionMessage.detail
            )
        )
        presentOverlay(.nextExercise)
    }

    private func advanceAfterExerciseCelebration() {
        if let pendingExerciseIndex {
            withExerciseChangeAnimation {
                currentExerciseIndex = min(pendingExerciseIndex, max(orderedExerciseLogs.count - 1, 0))
            }
            self.pendingExerciseIndex = nil
        }
    }

    private func dismissMotivationOverlay() {
        guard overlayPhase.showsCelebration, overlayVisible, !overlayActionInFlight else { return }
        let dismissedPhase = overlayPhase
        overlayActionInFlight = true

        if dismissedPhase == .completion {
            if summaryRenderSnapshot != nil {
                // Keep the source hierarchy stable while NavigationStack begins
                // its native push. The destination's first frame retires this
                // overlay, avoiding a removal-and-push structural race.
                let route = WorkoutSummaryRoute(sessionID: session.id)
                let didRequestNavigation = NavigationInteraction.perform(
                    key: summaryNavigationKey,
                    destinationClass: .warm,
                    haptic: .none
                ) {
                    summaryRoute = route
                }
                if !didRequestNavigation {
                    overlayActionInFlight = false
                }
            } else {
                AppMotion.withoutAnimation {
                    overlayVisible = false
                    overlayPhase = .idle
                    overlayActionInFlight = false
                }
                isCompletionCommitted = false
                finishCompletionPresentation()
                completionErrorMessage = "Peakline could not prepare the workout summary. Please try again."
            }
        } else {
            withAnimation(
                AppMotion.popupExit(reduceMotion: reduceMotion),
                completionCriteria: .logicallyComplete
            ) {
                overlayVisible = false
            } completion: {
                AppMotion.withoutAnimation {
                    overlayPhase = .idle
                    overlayActionInFlight = false
                }
                advanceAfterExerciseCelebration()
            }
        }
    }

    private var summaryNavigationKey: String {
        "workout.summary.\(session.id.uuidString)"
    }

    private func presentOverlay(_ phase: WorkoutOverlayPhase) {
        guard overlayPhase == .idle else { return }
        withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
            overlayPhase = phase
            overlayVisible = true
        }
    }

    private func presentRatingOverlay() {
        presentOverlay(.rating)
    }

    private func requestFinishWorkout() {
        if !isEditingCompletedWorkout && hasSkippedPlannedExercises {
            showingSkippedExerciseConfirmation = true
            return
        }

        finishWorkout()
    }

    private func cancelDurationCheck() {
        session.endedAt = nil
        pendingOutlierDurationSeconds = nil
        acceptedOutlierDurationSeconds = nil
        completionDurationOverrideSeconds = nil
    }

    private func finishWorkout() {
        PerformanceTracer.trace(.workoutLoggerFinish) {
            guard !isEditingCompletedWorkout else {
                let transaction = WorkoutLoggerPersistenceTransaction(session: session)
                guard durationService.apply(
                    activeDurationSeconds: editableDurationSeconds,
                    to: session
                ) else { return }
                markEnteredSetsComplete()
                do {
                    try transaction.perform(in: modelContext) {}
                    WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutEdited)
                    dismiss()
                } catch {
                    completionErrorMessage = "Peakline could not save these workout changes. Please try again."
                }
                return
            }

            if session.endedAt == nil {
                session.endedAt = Date()
            }

            finalizePausedTime(at: session.endedAt ?? Date())
            restTimerState = RestTimerState()

            let measuredSeconds = completionDurationOverrideSeconds
                ?? activeDurationSeconds(at: session.endedAt ?? Date())
            if measuredSeconds >= WorkoutSessionDurationService.outlierThresholdSeconds,
               acceptedOutlierDurationSeconds != measuredSeconds {
                pendingOutlierDurationSeconds = measuredSeconds
                showingDurationOutlierConfirmation = true
                return
            }
            presentRatingOverlay()
        }
    }

    private func confirmSkippedAndFinish() {
        pendingFinishAfterModal = true
    }

    private func handleRatingSelection(_ rating: WorkoutRating) {
        guard overlayPhase == .rating, !overlayActionInFlight else { return }
        overlayPhase = .saving
        overlayActionInFlight = true

        withAnimation(AppMotion.popupExit(reduceMotion: reduceMotion)) {
            overlayVisible = false
        }
        saveCompletedWorkout(rating: rating)
    }

    private func applySkippedReasonsAndFinish(_ selections: [UUID: SkippedExerciseReason]) {
        pendingSkippedReasonSelections = selections
        pendingFinishAfterModal = true
    }

    private func consumePendingFinishAfterModal() {
        guard
            pendingFinishAfterModal,
            !showingSkippedExerciseConfirmation,
            !showingSkippedReasonSheet
        else {
            return
        }
        pendingFinishAfterModal = false
        finishWorkout()
    }

    private func saveCompletedWorkout(rating: WorkoutRating) {
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        let end = Date()
        if !didSuspendWarmRefreshForCompletion {
            didSuspendWarmRefreshForCompletion = true
            NotificationCenter.default.post(name: .workoutCompletionPresentationBegan, object: nil)
        }
        isCompletionCommitted = true
        session.endedAt = session.endedAt ?? end
        finalizePausedTime(at: session.endedAt ?? end)
        session.completed = true
        session.perceivedDifficulty = rating.score
        WorkoutSessionDateService.alignLoggedDateToStartDate(session)

        let activeSeconds = completionDurationOverrideSeconds
            ?? activeDurationSeconds(at: session.endedAt ?? end)
        guard durationService.apply(activeDurationSeconds: activeSeconds, to: session) else {
            transaction.restore(in: modelContext)
            finishCompletionPresentation()
            isCompletionCommitted = false
            overlayPhase = .rating
            overlayActionInFlight = false
            completionErrorMessage = "Enter a workout duration of at least one minute."
            return
        }

        // Finish-time completion is a finalisation fallback for entered sets.
        // It happens only after any duration guard has been accepted, so
        // cancelling the outlier dialog cannot leave rows marked as logged.
        markEnteredSetsComplete()

        do {
            try transaction.perform(in: modelContext) {
                for log in skippedReasonService.skippedLogs(in: session) {
                    if let reason = pendingSkippedReasonSelections[log.id] {
                        skippedReasonService.append(reason: reason, to: log)
                    }
                }
            }
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .workoutCompleted)
            PerformanceTracer.mark(.workoutLoggerFinish, "local_save_complete")
            let summarySessions = [session] + completedSessions.filter { $0.id != session.id }
            summaryRenderSnapshot = SessionSummaryRenderSnapshot.build(
                session: session,
                completedSessions: summarySessions,
                activeSplits: activeSplits
            )
            configureCelebration(
                .completion(
                    rating: rating,
                    durationText: durationText(seconds: activeSeconds),
                    prs: summaryRenderSnapshot?.sessionPRs ?? []
                )
            )
            AppMotion.withoutAnimation {
                overlayPhase = .completion
                overlayVisible = true
                overlayActionInFlight = false
            }
            AppHaptics.success()
            PerformanceTracer.mark(.workoutLoggerFinish, "completion_overlay_requested")
            pendingSkippedReasonSelections = [:]
        } catch {
            finishCompletionPresentation()
            isCompletionCommitted = false
            summaryRenderSnapshot = nil
            overlayPhase = .rating
            overlayActionInFlight = false
            completionErrorMessage = error.localizedDescription
            withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                overlayVisible = true
            }
        }
    }

    private func finishCompletionPresentation() {
        guard didSuspendWarmRefreshForCompletion else { return }
        didSuspendWarmRefreshForCompletion = false
        overlayActionInFlight = false
        NotificationCenter.default.post(name: .workoutCompletionPresentationEnded, object: nil)
    }

    private func markEnteredSetsComplete() {
        for set in session.exerciseLogs.flatMap(\.setLogs) where set.weight > 0 || set.reps > 0 || set.rpe != nil {
            set.completed = true
        }
    }

    private func hasSubstitutionCandidates(for exerciseLog: ExerciseLog) -> Bool {
        exercises.contains { exercise in
            exercise.id != exerciseLog.exerciseId && !exercise.isArchived
        }
    }

    private func requestSubstitution(for exerciseLog: ExerciseLog) {
        guard substitutionRequest == nil else {
            PerformanceTracer.mark(.navigationInteraction, "substitution request_deduplicated")
            return
        }

        let candidates = substitutionService.candidates(
            for: exerciseLog.exerciseId,
            in: exercises,
            completedSessions: completedSessions,
            reason: nil
        )
        guard !candidates.isEmpty else { return }

        substitutionRequest = WorkoutSubstitutionRequest(
            exerciseLogID: exerciseLog.id,
            title: "Substitute \(exerciseLog.exerciseNameSnapshot)",
            candidates: candidates
        )
    }

    private func applySubstitution(
        request: WorkoutSubstitutionRequest,
        candidate: ExerciseSubstitutionCandidate
    ) {
        guard
            let exerciseLog = session.exerciseLogs.first(where: { $0.id == request.exerciseLogID }),
            let exercise = exercises.first(where: { $0.id == candidate.exerciseId })
        else {
            return
        }

        let originalName = exerciseLog.exerciseNameSnapshot
        let note = substitutionService.substitutionNote(
            originalName: originalName,
            replacementName: exercise.name,
            reason: .preferAlternative
        )

        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        do {
            try transaction.perform(in: modelContext) {
                if exerciseLog.setLogs.contains(where: { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }) {
                    appendSubstitutionNote(note, to: exerciseLog)
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
                    appendSubstitutionNote(note, to: exerciseLog)
                }
            }

            refreshOrderedExerciseLogsCache(force: true)
            refreshPreviousPerformanceCache(force: true)
            refreshTemplateNotesCache(force: true)
        } catch {
            refreshOrderedExerciseLogsCache(force: true)
            refreshPreviousPerformanceCache(force: true)
            refreshTemplateNotesCache(force: true)
            completionErrorMessage = "Peakline could not save this substitution. Please try again."
        }
    }

    private func appendSubstitutionNote(_ text: String, to exerciseLog: ExerciseLog) {
        let existing = exerciseLog.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !existing.localizedCaseInsensitiveContains(text) else { return }
        exerciseLog.notes = existing.isEmpty ? text : "\(existing)\n\(text)"
    }

    private func configureCelebration(_ presentation: WorkoutCelebrationPresentation) {
        celebrationPresentation = presentation
    }

    private func withExerciseChangeAnimation(_ update: @escaping () -> Void) {
        update()
    }

    private func togglePause() {
        let now = Date()
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        do {
            try transaction.perform(in: modelContext) {
                if let pausedAt = session.pausedAt {
                    session.accumulatedPausedSeconds += max(0, Int(now.timeIntervalSince(pausedAt)))
                    session.pausedAt = nil
                } else {
                    session.pausedAt = now
                }
            }
        } catch {
            completionErrorMessage = "Peakline could not save the pause change. Please try again."
        }
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

private struct PreviousExercisePerformance {
    let summary: String
    let workingSets: [PreviousSetSnapshot]
}

private enum WorkoutLoggerPerformanceCache {
    static func previousPerformanceByExerciseId(
        for exerciseLogs: [ExerciseLog],
        currentSessionId: UUID,
        completedSessions: [WorkoutSession]
    ) -> [UUID: PreviousExercisePerformance] {
        let neededExerciseIds = Set(exerciseLogs.map(\.exerciseId))
        guard !neededExerciseIds.isEmpty else { return [:] }

        var results: [UUID: PreviousExercisePerformance] = [:]

        for previousSession in completedSessions where previousSession.id != currentSessionId {
            for previousLog in previousSession.exerciseLogs where neededExerciseIds.contains(previousLog.exerciseId) && results[previousLog.exerciseId] == nil {
                guard let performance = previousPerformance(from: previousLog) else { continue }
                results[previousLog.exerciseId] = performance

                if results.count == neededExerciseIds.count {
                    return results
                }
            }
        }

        return results
    }

    private static func previousPerformance(from exerciseLog: ExerciseLog) -> PreviousExercisePerformance? {
        let workingSets = exerciseLog.setLogs
            .filter { !$0.isWarmup && ($0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil) }
            .sorted { $0.setNumber < $1.setNumber }

        guard !workingSets.isEmpty else { return nil }

        let snapshots = workingSets.map { set in
            PreviousSetSnapshot(weight: set.weight, reps: set.reps, rpe: set.rpe)
        }
        let summary = snapshots
            .map { PeaklineText.loadReps(weight: $0.formattedWeight, reps: $0.reps) }
            .joined(separator: ", ")

        return PreviousExercisePerformance(summary: summary, workingSets: snapshots)
    }
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
                    .font(AppTypography.badge)
                    .foregroundStyle(isCurrent ? appTheme.colors.accentForeground : appTheme.colors.textAccent)
                    .frame(width: 16, height: 16)
                    .background(isCurrent ? appTheme.actionColor : appTheme.actionColor.opacity(0.14), in: Circle())
                    .offset(x: 4, y: -4)
            }

            Button {
                AppHaptics.selection()
                jump()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("workout-logger-order-name-\(exerciseName)")
                    Text(isCurrent ? "Current exercise" : "Tap to jump here")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    AppHaptics.selection()
                    moveUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move \(exerciseName) up")
                .accessibilityIdentifier("workout-logger-order-move-up-\(exerciseName)")

                Button {
                    AppHaptics.selection()
                    moveDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move \(exerciseName) down")
                .accessibilityIdentifier("workout-logger-order-move-down-\(exerciseName)")
            }
            .buttonStyle(.borderless)
            .tint(appTheme.actionColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-logger-order-row-\(exerciseName)")
    }
}

struct WorkoutRating: Identifiable {
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

struct WorkoutCelebrationPresentation: Equatable {
    let title: String
    let message: String
    let primaryActionTitle: String
    let systemImage: String
    let style: CelebrationStyle

    static let initial = WorkoutCelebrationPresentation(
        title: "Keep going.",
        message: "One exercise banked. Keep the reps clean and own the next set.",
        primaryActionTitle: "Next Exercise",
        systemImage: "arrow.right.circle.fill",
        style: .nextExercise
    )

    static func nextExercise(title: String, message: String) -> WorkoutCelebrationPresentation {
        WorkoutCelebrationPresentation(
            title: title,
            message: message,
            primaryActionTitle: "Next Exercise",
            systemImage: "arrow.right.circle.fill",
            style: .nextExercise
        )
    }

    static func completion(
        rating: WorkoutRating,
        durationText: String,
        prs: [PRRecord]
    ) -> WorkoutCelebrationPresentation {
        guard !prs.isEmpty else {
            return WorkoutCelebrationPresentation(
                title: rating.completionTitle,
                message: "\(rating.completionMessage) You spent \(durationText) in the gym.",
                primaryActionTitle: "Done",
                systemImage: rating.systemImage,
                style: .completedWorkout
            )
        }

        let exerciseCount = Set(prs.map(\.exerciseLogId)).count
        let prSummary: String
        if exerciseCount == 1, let exerciseName = prs.first?.exerciseName {
            prSummary = "\(PeaklineText.count(prs.count, singular: "PR")) on \(exerciseName)."
        } else {
            prSummary = "\(PeaklineText.count(prs.count, singular: "PR")) across \(PeaklineText.count(exerciseCount, singular: "exercise"))."
        }

        return WorkoutCelebrationPresentation(
            title: prs.count == 1 ? "New best unlocked." : "New bests unlocked.",
            message: "\(prSummary) \(rating.completionMessage) You spent \(durationText) in the gym.",
            primaryActionTitle: "Done",
            systemImage: "trophy.fill",
            style: .pr
        )
    }
}

private struct WorkoutRatingOverlay: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isVisible: Bool
    let selectRating: (WorkoutRating) -> Void

    @State private var selectedRating: WorkoutRating?
    @State private var isTransitioning = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PeaklinePopupBackdrop(isVisible: isVisible)
                .ignoresSafeArea()

            PeaklinePopupCard(cornerRadius: 32, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("How did it go?")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .minimumScaleFactor(0.82)

                        Text("Rate the workout so Peakline remembers how the session felt, not just what you lifted.")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ratingOptions

                    Text("Saved with this workout and used for the completion message.")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    .font(.system(.largeTitle))

                Text(rating.title)
                    .font(AppTypography.metadataEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(RoundedRectangle(cornerRadius: appTheme.metrics.radius20, style: .continuous))
            .foregroundStyle(appTheme.colors.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius20, style: .continuous)
                    .fill(appTheme.colors.cardBackgroundElevated)
            }
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius20, style: .continuous)
                    .stroke(
                        isSelected ? appTheme.colors.accent.opacity(0.58) : appTheme.colors.cardBorder.opacity(0.72),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            }
            .shadow(
                color: isSelected ? appTheme.colors.accent.opacity(0.10) : .clear,
                radius: isSelected ? 8 : 0,
                y: isSelected ? 5 : 0
            )
            .scaleEffect(reduceMotion ? 1 : (isSelected ? AppMotion.selectedControlScale : 1))
            .animation(AppMotion.ratingSelect(reduceMotion: reduceMotion), value: isSelected)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout-rating-\(rating.id)")
        .accessibilityLabel("\(rating.title) workout rating")
        .buttonStyle(.plain)
        .disabled(selectedRating != nil || isTransitioning)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ rating: WorkoutRating) {
        guard selectedRating == nil, !isTransitioning else { return }

        isTransitioning = true
        AppHaptics.selection()
        PerformanceTracer.trace(.motionRatingSelect) {
            withAnimation(AppMotion.ratingSelect(reduceMotion: reduceMotion)) {
                selectedRating = rating
            }
        }
        selectRating(rating)
    }

}

struct WorkoutTransitionMessage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
}

enum WorkoutMotivationCatalog {
    static let messages: [WorkoutTransitionMessage] = [
        WorkoutTransitionMessage(id: "work-banked", title: "Work banked.", detail: "Reset your setup and bring the same control to the next exercise."),
        WorkoutTransitionMessage(id: "keep-standard", title: "Keep the standard.", detail: "Carry the clean reps forward and make the next movement just as deliberate."),
        WorkoutTransitionMessage(id: "next-station", title: "Next station.", detail: "Take a breath, set the equipment, and start the next exercise with intent."),
        WorkoutTransitionMessage(id: "clean-work", title: "Clean work.", detail: "That exercise is done. Keep the tempo honest when the next set begins."),
        WorkoutTransitionMessage(id: "rhythm-set", title: "Rhythm set.", detail: "The session is moving. Stay patient and let good positions lead the next lift."),
        WorkoutTransitionMessage(id: "one-block-down", title: "One block down.", detail: "Recover just enough, then give the next exercise your full attention."),
        WorkoutTransitionMessage(id: "stay-composed", title: "Stay composed.", detail: "Leave that effort behind and approach the next movement with a clear setup."),
        WorkoutTransitionMessage(id: "reset-and-go", title: "Reset and go.", detail: "Check your stance, brace well, and make the first rep of the next exercise count."),
        WorkoutTransitionMessage(id: "strong-foundation", title: "Strong foundation.", detail: "You have useful work in the bank. Build the next exercise on the same control."),
        WorkoutTransitionMessage(id: "pace-set", title: "Pace is set.", detail: "Keep the session efficient without rushing the setup or the range of motion."),
        WorkoutTransitionMessage(id: "quality-carries", title: "Quality carries.", detail: "Use the same steady execution as you move into the next part of the plan."),
        WorkoutTransitionMessage(id: "focus-forward", title: "Focus forward.", detail: "The previous exercise is complete. Put your attention on the next target now."),
        WorkoutTransitionMessage(id: "session-building", title: "Session building.", detail: "Each finished exercise adds up. Keep the next one controlled from rep one."),
        WorkoutTransitionMessage(id: "tidy-reps", title: "Tidy reps.", detail: "Hold onto that technique and make the next exercise equally repeatable."),
        WorkoutTransitionMessage(id: "intent-high", title: "Intent stays high.", detail: "Change stations, settle your breathing, and attack the next set without rushing."),
        WorkoutTransitionMessage(id: "form-first", title: "Form first.", detail: "Start the next exercise with the load you can own through the full range."),
        WorkoutTransitionMessage(id: "progress-stacked", title: "Progress stacked.", detail: "Another movement is complete. Keep adding useful reps, one set at a time."),
        WorkoutTransitionMessage(id: "smooth-handoff", title: "Smooth handoff.", detail: "Use the transition to reset, then make the next exercise sharp and controlled."),
        WorkoutTransitionMessage(id: "next-lift-ready", title: "Next lift ready.", detail: "Set your position before the load moves and keep the opening reps measured."),
        WorkoutTransitionMessage(id: "effort-placed", title: "Effort placed.", detail: "That work is recorded. Save enough focus to execute the next exercise well."),
        WorkoutTransitionMessage(id: "momentum-earned", title: "Momentum earned.", detail: "Keep it useful: stable setup, clean range, and no wasted reps on the next lift."),
        WorkoutTransitionMessage(id: "control-held", title: "Control held.", detail: "Take that composure with you and make the next movement look just as solid."),
        WorkoutTransitionMessage(id: "work-accumulates", title: "Work accumulates.", detail: "The session is taking shape. Stay consistent through the next exercise."),
        WorkoutTransitionMessage(id: "target-next", title: "Target the next.", detail: "Leave the completed sets in the log and focus on the next planned range."),
        WorkoutTransitionMessage(id: "stay-deliberate", title: "Stay deliberate.", detail: "A calm setup now will make the next working sets more productive."),
        WorkoutTransitionMessage(id: "setup-reset", title: "Setup reset.", detail: "Adjust the station, find your position, and begin the next exercise cleanly."),
        WorkoutTransitionMessage(id: "reps-in-book", title: "Reps in the book.", detail: "Keep your rest sensible and bring the same discipline to the next movement."),
        WorkoutTransitionMessage(id: "keep-moving", title: "Keep it moving.", detail: "You are through that exercise. Stay precise as the session moves on.")
    ]

    static let fallback = WorkoutTransitionMessage(
        id: "fallback",
        title: "Keep going.",
        detail: "Reset your setup and move into the next exercise with control."
    )
}

struct WorkoutMotivationRotation: Equatable, Sendable {
    private let messages: [WorkoutTransitionMessage]
    private var cursor: Int
    private(set) var lastMessageID: WorkoutTransitionMessage.ID?

    init(
        sessionID: UUID,
        messages: [WorkoutTransitionMessage] = WorkoutMotivationCatalog.messages
    ) {
        self.messages = messages
        cursor = messages.isEmpty
            ? 0
            : Int(Self.stableDigest(sessionID.uuidString) % UInt64(messages.count))
        lastMessageID = nil
    }

    mutating func next() -> WorkoutTransitionMessage {
        guard !messages.isEmpty else {
            lastMessageID = WorkoutMotivationCatalog.fallback.id
            return WorkoutMotivationCatalog.fallback
        }

        var message = messages[cursor]
        cursor = (cursor + 1) % messages.count

        if messages.count > 1, message.id == lastMessageID {
            message = messages[cursor]
            cursor = (cursor + 1) % messages.count
        }

        lastMessageID = message.id
        return message
    }

    private static func stableDigest(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { digest, byte in
            (digest ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private enum WorkoutOverlayPhase: Equatable {
    case idle
    case nextExercise
    case rating
    case saving
    case completion

    var showsCelebration: Bool {
        self == .nextExercise || self == .completion
    }

    var showsRating: Bool {
        self == .rating || self == .saving
    }
}

private struct WorkoutDurationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var hours: Int
    @State private var minutes: Int
    let save: (Int, Int) -> Void

    init(initialHours: Int, initialMinutes: Int, save: @escaping (Int, Int) -> Void) {
        _hours = State(initialValue: min(23, max(0, initialHours)))
        _minutes = State(initialValue: min(59, max(0, initialMinutes)))
        self.save = save
    }

    var body: some View {
        NavigationStack {
            FitnessScreen {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How long did you train?")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Enter the active time you actually spent training. Paused time remains separate.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Stepper("Hours: \(hours)", value: $hours, in: 0...23)
                            .accessibilityIdentifier("workout-duration-correction-hours")
                        Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                            .accessibilityIdentifier("workout-duration-correction-minutes")
                    }
                }
            }
            .navigationTitle("Edit Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(hours, minutes)
                        dismiss()
                    }
                    .disabled(hours == 0 && minutes == 0)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("workout-duration-correction-save")
                }
            }
        }
    }
}

private struct WorkoutSummaryRoute: Identifiable, Hashable {
    let sessionID: UUID

    var id: UUID { sessionID }
}

extension Notification.Name {
    static let workoutCompletionPresentationBegan = Notification.Name("workoutCompletionPresentationBegan")
    static let workoutCompletionPresentationEnded = Notification.Name("workoutCompletionPresentationEnded")
}

private struct WorkoutSubstitutionRequest: Identifiable {
    let exerciseLogID: UUID
    let title: String
    let candidates: [ExerciseSubstitutionCandidate]

    var id: UUID { exerciseLogID }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: WorkoutSession
    @Bindable var exerciseLog: ExerciseLog
    var contextLabel: String? = nil
    let templateNote: String?
    let previousPerformance: PreviousExercisePerformance?
    let isCompletedWorkout: Bool
    let canSubstitute: Bool
    let requestSubstitution: () -> Void
    let reportPersistenceError: (String) -> Void

    @State private var showingNotes = false
    @State private var guideEntry: ExerciseGuideEntry?

    private var orderedSets: [SetLog] {
        exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if let contextLabel {
                    Label {
                        Text(contextLabel)
                            .accessibilityIdentifier("workout-logger-current-position")
                    } icon: {
                        Image(systemName: "location.viewfinder")
                    }
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(appTheme.colors.accentSurface, in: Capsule())
                }

                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                        size: 60,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseLog.exerciseNameSnapshot)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                            .accessibilityIdentifier("workout-logger-current-exercise-name")

                        Text(targetText)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()

                    if canSubstitute {
                        Button {
                            requestSubstitution()
                        } label: {
                            Label("Substitute", systemImage: "arrow.triangle.2.circlepath")
                                .font(AppTypography.chip)
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("workout-logger-substitute")
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(setProgressText)
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Last time: \(previousPerformance?.summary ?? "No previous data")")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Text(coachCue)
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textAccent)
                        .lineLimit(2)
                }

                if let templateNote, !templateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(templateNote, systemImage: "lightbulb")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let entry = ExerciseIconMapper.guideEntry(forName: exerciseLog.exerciseNameSnapshot) {
                    Button {
                        guideEntry = entry
                    } label: {
                        Label("Exercise Guide", systemImage: "info.circle")
                            .font(AppTypography.bodyEmphasis)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("workout-logger-exercise-guide")
                    .sheet(item: $guideEntry) { entry in
                        ExerciseGuideSheet(entry: entry)
                    }
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
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.actionColor)
                }

                HStack(spacing: 10) {
                    Text("Target sets")
                        .font(AppTypography.chip)
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
            .destructiveSwipeAction("Remove") {
                removeExerciseFromSession()
            }

            ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, setLog in
                SetRowView(
                    session: session,
                    isCompletedWorkout: isCompletedWorkout,
                    setLog: setLog,
                    didMutate: { transaction in
                        persistValueMutation(transaction: transaction)
                    },
                    deleteAction: { delete(setLog) }
                )
                    .transition(AppMotion.rowInsertRemoveTransition(reduceMotion: reduceMotion))
                    .destructiveSwipeAction {
                        delete(setLog)
                    }
            }

            HStack {
                Button {
                    addSet(copyPrevious: !orderedSets.isEmpty)
                } label: {
                    Label("Add Set", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("workout-logger-add-set")
            }
        }
    }

    private var targetText: String {
        guard exerciseLog.targetSets > 0 else { return "No target set" }
        return "Target: \(PeaklineText.count(exerciseLog.targetSets, singular: "set")) x \(exerciseLog.minReps)-\(exerciseLog.maxReps) reps"
    }

    private var setProgressText: String {
        let workingSets = orderedSets.filter { !$0.isWarmup }
        let isHistorical = isCompletedWorkout || session.completed
        let enteredWorkingSets = workingSets.filter {
            isHistorical ? $0.completed : ($0.weight > 0 || $0.reps > 0 || $0.rpe != nil)
        }.count
        let target = max(exerciseLog.targetSets, workingSets.count)
        let status = isHistorical ? "logged" : "entered"
        return "\(enteredWorkingSets) of \(PeaklineText.count(target, singular: "working set")) \(status)"
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
            return "Start near last session: \(PeaklineText.loadReps(weight: first.formattedWeight, reps: first.reps))."
        }

        if orderedSets.contains(where: { $0.rpe ?? 0 >= 9 }) {
            return "High effort logged. Hold load steady and protect form."
        }

        return "If reps stay clean, aim for the top of the range before adding load."
    }

    private func addSet(copyPrevious: Bool) {
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
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
        persistMutation(transaction: transaction)
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
        let originalSets = orderedSets
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        withAnimation(AppMotion.rowCollapse(reduceMotion: reduceMotion)) {
            exerciseLog.setLogs.removeAll { $0.id == setLog.id }

            for (index, set) in orderedSets.filter({ $0.id != setLog.id }).enumerated() {
                set.setNumber = index + 1
            }
            modelContext.delete(setLog)
        }

        do {
            try transaction.perform(in: modelContext) {}
            if isCompletedWorkout {
                WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutSetEdited)
            }
        } catch {
            AppMotion.withoutAnimation {
                exerciseLog.setLogs = originalSets
                for (index, set) in originalSets.enumerated() {
                    set.setNumber = index + 1
                    set.exerciseLog = exerciseLog
                }
            }
            reportPersistenceError("Peakline could not save this set change. Please try again.")
        }
    }

    private func removeExerciseFromSession() {
        let transaction = WorkoutLoggerPersistenceTransaction(session: session)
        session.exerciseLogs.removeAll { $0.id == exerciseLog.id }
        modelContext.delete(exerciseLog)

        for (index, log) in session.exerciseLogs.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            log.orderIndex = index
        }

        persistMutation(transaction: transaction)
    }

    private func persistMutation(transaction: WorkoutLoggerPersistenceTransaction) {
        do {
            try transaction.perform(in: modelContext) {}
            if isCompletedWorkout {
                WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutSetEdited)
            }
        } catch {
            reportPersistenceError("Peakline could not save this set change. Please try again.")
        }
    }

    private func persistValueMutation(transaction: WorkoutSetPersistenceTransaction?) {
        guard isCompletedWorkout else { return }
        do {
            if let transaction {
                try transaction.perform(in: modelContext) {}
            } else {
                try modelContext.save()
            }
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutSetEdited)
        } catch {
            reportPersistenceError("Peakline could not save this set change. Please try again.")
        }
    }

}

private struct SetRowView: View {
    @Environment(\.appTheme) private var appTheme
    let session: WorkoutSession
    let isCompletedWorkout: Bool
    @Bindable var setLog: SetLog
    let didMutate: (WorkoutSetPersistenceTransaction?) -> Void
    let deleteAction: () -> Void

    @State private var activeSheet: SetRowSheet?

    private var effort: EffortLevel? {
        EffortLevel(rpe: setLog.rpe)
    }

    private var hasLoggedData: Bool {
        setLog.weight > 0 || setLog.reps > 0 || setLog.rpe != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Set \(setLog.setNumber)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .accessibilityIdentifier("set-row-\(setLog.setNumber)")

                Spacer()

                if setLog.isWarmup {
                    SetStatusChip(title: "Warm-up", systemImage: "flame", color: appTheme.warningColor)
                }

                if setLog.completed {
                    SetStatusChip(
                        title: "Logged",
                        systemImage: "checkmark.circle.fill",
                        color: appTheme.successColor
                    )
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

            HStack(spacing: 8) {
                Button {
                    activeSheet = .effort
                } label: {
                    Text(effort.map { "Effort: \($0.title)" } ?? "Effort Optional")
                        .font(AppTypography.chip)
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
                        toggleWarmup()
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
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Actions for set \(setLog.setNumber)")
                .accessibilityIdentifier("workout-logger-set-actions-\(setLog.id.uuidString)")
            }
        }
        .padding(.vertical, 8)
        .onAppear {
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
                .sheetContentEntrance()
            case .reps:
                NumericEntrySheet(
                    title: "Edit Reps",
                    value: "\(setLog.reps)",
                    keyboardType: .numberPad,
                    save: { updateReps(Int($0) ?? setLog.reps) }
                )
                .sheetContentEntrance()
            case .effort:
                EffortPickerSheet(selectedRPE: setLog.rpe) { rpe in
                    let transaction = persistenceTransaction()
                    setLog.rpe = rpe
                    syncCompletedState()
                    didMutate(transaction)
                    activeSheet = nil
                }
                .sheetContentEntrance()
            case .plates:
                NavigationStack {
                    PlateCalculatorView(targetWeight: setLog.weight)
                }
                .sheetContentEntrance()
            }
        }
    }

    private func format(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }

    private func updateWeight(_ weight: Double) {
        let transaction = persistenceTransaction()
        setLog.weight = max(0, weight)
        syncCompletedState()
        didMutate(transaction)
    }

    private func updateReps(_ reps: Int) {
        let transaction = persistenceTransaction()
        setLog.reps = max(0, reps)
        syncCompletedState()
        didMutate(transaction)
    }

    private func toggleWarmup() {
        let transaction = persistenceTransaction()
        setLog.isWarmup.toggle()
        syncCompletedState()
        didMutate(transaction)
    }

    private func persistenceTransaction() -> WorkoutSetPersistenceTransaction? {
        guard session.completed || isCompletedWorkout else { return nil }
        return WorkoutSetPersistenceTransaction(set: setLog)
    }

    private func syncCompletedState() {
        guard hasLoggedData else {
            setLog.completed = false
            return
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
                    .font(AppTypography.largeMetric)
                Text("Optional intensity for coaching and progression.")
                    .font(AppTypography.body)
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
                                    .font(AppTypography.sectionTitle)
                                Text(effort.detail)
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }

                            Spacer()

                            if EffortLevel(rpe: selectedRPE) == effort {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(appTheme.actionColor)
                            }
                        }
                        .padding(12)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
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
            .peaklineGroupedContent()
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
        .peaklineKeyboardDismissal()
        .presentationDetents([.height(220)])
    }
}

private struct SetStatusChip: View {
    let title: String
    let systemImage: String
    let color: Color
    var checkmarkProgress: CGFloat? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let checkmarkProgress {
                ZStack {
                    Image(systemName: systemImage)
                        .opacity(0.22)

                    CheckmarkStroke(progress: checkmarkProgress)
                        .trim(from: 0, to: checkmarkProgress)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(title)
        }
            .font(AppTypography.badge)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct CheckmarkStroke: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.16))
        return path
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
                    .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
            }
            .disabled(value <= 1)
            .accessibilityLabel("Decrease target sets")

            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.bold))
                .frame(minWidth: 30)

            Button(action: increment) {
                Image(systemName: "plus")
                    .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
            }
            .disabled(value >= 10)
            .accessibilityLabel("Increase target sets")
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
