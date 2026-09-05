import SwiftData
import SwiftUI

struct SessionSummaryExerciseSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let exerciseName: String
    let iconKey: ExerciseIconKey
    let bestSetDescription: String
    let notes: String?
}

struct SessionSummaryRenderSnapshot: Equatable, Sendable {
    let summary: SessionSummary
    let sessionPRs: [PRRecord]
    let nextTrainingCall: TrainingCallSnapshot
    let completedExercises: [SessionSummaryExerciseSnapshot]
    let matchingSplitID: UUID?

    @MainActor
    static func build(
        session: WorkoutSession,
        completedSessions: [WorkoutSession],
        activeSplits: [TrainingSplit]
    ) -> SessionSummaryRenderSnapshot {
        let summary = SessionSummaryBuilder().build(
            from: session,
            completedSessions: completedSessions,
            activeSplits: activeSplits
        )
        let sessionPRs = TrainingAnalyticsService().prs(for: session, in: completedSessions)
        let weeklyReview = WeeklyReviewBuilder().build(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let nextTrainingCall = TrainingCallSnapshotBuilder().make(
            decision: weeklyReview.nextDecision,
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let completedExercises = session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { exerciseLog in
                exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
            }
            .map { exerciseLog in
                let bestSet = exerciseLog.setLogs
                    .filter { $0.completed && !$0.isWarmup }
                    .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
                let bestSetDescription: String
                if let bestSet {
                    let weight = bestSet.weight.formatted(
                        .number.precision(
                            .fractionLength(bestSet.weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
                        )
                    )
                    bestSetDescription = PeaklineText.loadReps(weight: weight, reps: bestSet.reps)
                } else {
                    bestSetDescription = "Logged"
                }
                return SessionSummaryExerciseSnapshot(
                    id: exerciseLog.id,
                    exerciseName: exerciseLog.exerciseNameSnapshot,
                    iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                    bestSetDescription: bestSetDescription,
                    notes: exerciseLog.notes
                )
            }
        let matchingSplitID = activeSplits.first { split in
            let base = session.splitNameSnapshot.components(separatedBy: " - ").first ?? session.splitNameSnapshot
            return split.id == session.splitId || split.name == base
        }?.id

        return SessionSummaryRenderSnapshot(
            summary: summary,
            sessionPRs: sessionPRs,
            nextTrainingCall: nextTrainingCall,
            completedExercises: completedExercises,
            matchingSplitID: matchingSplitID
        )
    }
}

struct SessionSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @State private var showingTemplateSave = false
    @State private var showingReopenConfirmation = false
    @State private var reopenedSession: WorkoutSession?
    @State private var showingUpdateSplitConfirmation = false
    @State private var persistenceErrorMessage: String?

    let session: WorkoutSession
    let snapshot: SessionSummaryRenderSnapshot
    let onDone: (() -> Void)?
    private let reopenService = WorkoutSessionReopenService()
    private let splitUpdateService = SplitTemplateUpdateService()

    init(
        session: WorkoutSession,
        snapshot: SessionSummaryRenderSnapshot,
        onDone: (() -> Void)? = nil
    ) {
        self.session = session
        self.snapshot = snapshot
        self.onDone = onDone
    }

    private var summary: SessionSummary {
        snapshot.summary
    }

    private var sessionPRs: [PRRecord] {
        snapshot.sessionPRs
    }

    private var nextTrainingCall: TrainingCallSnapshot {
        snapshot.nextTrainingCall
    }

    var body: some View {
        FitnessScreen {
            FitnessCard(style: .hero) {
                VStack(alignment: .leading, spacing: 14) {
                    let headerLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                    headerLayout {
                        ExerciseIconView(
                            iconKey: ExerciseIconMapper.splitIconKey(for: summary.splitName),
                            size: 58,
                            showBackground: true,
                            isDecorative: true
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Completed")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .accessibilityLabel("Completed")
                                .accessibilityIdentifier("session-summary-status")
                            Text(summary.splitName)
                                .font(AppTypography.heroTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                        CoachBadgeView(state: sessionPRs.isEmpty ? .ready : .pr)
                    }

                    Text(summary.takeaway)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ViewThatFits(in: .horizontal) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            HStack(alignment: .bottom, spacing: 14) {
                                SessionSummaryPrimaryMetric(value: "\(summary.workingSetCount)")

                                Divider()
                                    .overlay(appTheme.colors.cardBorder)
                                    .frame(height: 62)

                                HStack(alignment: .bottom, spacing: 14) {
                                    SessionSummarySupportingMetric(label: "Duration", value: summary.durationText)
                                    SessionSummarySupportingMetric(label: "Exercises", value: "\(summary.completedExerciseCount)")
                                    SessionSummarySupportingMetric(label: "Rating", value: summary.ratingText ?? "–")
                                }
                            }

                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SessionSummaryPrimaryMetric(value: "\(summary.workingSetCount)")
                            let metricsLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 16))
                            metricsLayout {
                                SessionSummarySupportingMetric(label: "Duration", value: summary.durationText)
                                SessionSummarySupportingMetric(label: "Exercises", value: "\(summary.completedExerciseCount)")
                                SessionSummarySupportingMetric(label: "Rating", value: summary.ratingText ?? "–")
                            }
                        }
                    }

                    if let notes = session.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(notes, systemImage: "note.text")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DashboardSection(title: "Today's Improvements") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(sessionPRs.isEmpty ? "Completed Work" : "New Bests")
                                .font(AppTypography.sectionTitle)
                            Spacer()
                            CoachBadgeView(state: sessionPRs.isEmpty ? .ready : .pr)
                        }

                        if sessionPRs.isEmpty {
                            Text("No PRs today, but you completed \(PeaklineText.count(summary.workingSetCount, singular: "working set")).")
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        } else {
                            ForEach(sessionPRs.prefix(5)) { pr in
                                Label("\(pr.exerciseName) · \(pr.improvementDescription)", systemImage: "arrow.up.circle.fill")
                                    .font(AppTypography.body)
                            }
                        }
                    }
                }
            }

            if let suggestedNextSplit = summary.suggestedNextSplit {
                DashboardSection(title: "Next Up") {
                    FitnessCard {
                        HStack {
                            ExerciseIconView(
                                iconKey: ExerciseIconMapper.splitIconKey(for: suggestedNextSplit),
                                size: 44,
                                showBackground: true,
                                isDecorative: true
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Suggested split")
                                    .font(AppTypography.metadataEmphasis)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .textCase(.uppercase)
                                Text(suggestedNextSplit)
                                    .font(AppTypography.largeMetric)
                            }

                            Spacer()
                            CoachBadgeView(state: .ready)
                        }
                    }
                }
            }

            DashboardSection(title: "Next Decision") {
                TrainingCallAuditCard(snapshot: nextTrainingCall, title: "Next call")
            }

            if !snapshot.completedExercises.isEmpty {
                DashboardSection(title: "Completed Exercises") {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(snapshot.completedExercises.enumerated()), id: \.element.id) { index, exercise in
                                if index > 0 {
                                    Divider()
                                }

                                SessionSummaryExerciseRow(exercise: exercise)
                            }
                        }
                    }
                }
            }

            DashboardSection(title: "Actions") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        historyButton
                        doneButton
                    }

                    VStack(spacing: 10) {
                        doneButton
                        historyButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        saveTemplateButton
                        reopenButton
                    }

                    VStack(spacing: 10) {
                        saveTemplateButton
                        reopenButton
                    }
                }

                if snapshot.matchingSplitID != nil {
                    Button {
                        showingUpdateSplitConfirmation = true
                    } label: {
                        Label("Update Split Template", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .navigationDestination(item: $reopenedSession) { session in
            WorkoutLoggerView(session: session)
        }
        .sheet(isPresented: $showingTemplateSave) {
            WorkoutTemplateSaveSheet(session: session)
        }
        .alert("Reopen this workout?", isPresented: $showingReopenConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reopen") {
                reopenWorkout()
            }
        } message: {
            Text("This moves it back into the live workout logger so you can add or edit sets before finishing again.")
        }
        .alert("Update split template?", isPresented: $showingUpdateSplitConfirmation) {
            Button("Keep Split Unchanged", role: .cancel) {}
            Button("Replace Exercise Order") {
                updateMatchingSplit()
            }
        } message: {
            Text("This applies the completed workout's exercise order and substitutions to the matching split. Your workout history stays unchanged.")
        }
        .alert("Could not save changes", isPresented: Binding(
            get: { persistenceErrorMessage != nil },
            set: { if !$0 { persistenceErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage ?? "Try again.")
        }
    }

    private var historyButton: some View {
        NavigationLink {
            HistoryView()
        } label: {
            Label("History", systemImage: "calendar")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    private var doneButton: some View {
        Button {
            if let onDone {
                onDone()
            } else {
                dismiss()
            }
        } label: {
            Label("Done", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
    }

    private var saveTemplateButton: some View {
        Button {
            showingTemplateSave = true
        } label: {
            Label("Save Template", systemImage: "rectangle.stack.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    private var reopenButton: some View {
        Button {
            showingReopenConfirmation = true
        } label: {
            Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    private func reopenWorkout() {
        let originalState = WorkoutSessionCompletionState(session)
        reopenService.reopen(session)
        do {
            try modelContext.save()
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .workoutReopened)
            reopenedSession = session
        } catch {
            originalState.restore(session)
            persistenceErrorMessage = "Could not reopen this workout locally. Try again."
        }
    }

    private func updateMatchingSplit() {
        guard let matchingSplitID = snapshot.matchingSplitID else { return }
        let descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate { $0.id == matchingSplitID }
        )
        guard let matchingSplit = try? modelContext.fetch(descriptor).first else { return }
        splitUpdateService.replaceOrder(of: matchingSplit, with: session)
        try? modelContext.save()
    }
}

private struct SessionSummaryPrimaryMetric: View {
    @Environment(\.appTheme) private var appTheme

    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(AppTypography.heroMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
            Text("Working sets")
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SessionSummarySupportingMetric: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(AppTypography.workoutNumber)
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionSummaryExerciseRow: View {
    @Environment(\.appTheme) private var appTheme

    let exercise: SessionSummaryExerciseSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ExerciseIconView(
                    iconKey: exercise.iconKey,
                    size: 34,
                    showBackground: true,
                    isDecorative: true
                )

                Text(exercise.exerciseName)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(exercise.bestSetDescription)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
            }

            if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

}
