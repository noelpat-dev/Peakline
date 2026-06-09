import SwiftData
import SwiftUI

struct SessionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @State private var showingTemplateSave = false
    @State private var showingReopenConfirmation = false
    @State private var reopenedSession: WorkoutSession?
    @State private var showingUpdateSplitConfirmation = false

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    let session: WorkoutSession
    private let builder = SessionSummaryBuilder()
    private let analytics = TrainingAnalyticsService()
    private let reviewBuilder = WeeklyReviewBuilder()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let reopenService = WorkoutSessionReopenService()
    private let splitUpdateService = SplitTemplateUpdateService()

    private var summary: SessionSummary {
        builder.build(from: session, completedSessions: completedSessions, activeSplits: activeSplits)
    }

    private var sessionPRs: [PRRecord] {
        analytics.prs(for: session, in: completedSessions)
    }

    private var weeklyReview: WeeklyReview {
        reviewBuilder.build(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    private var nextTrainingCall: TrainingCallSnapshot {
        trainingCallBuilder.make(
            decision: weeklyReview.nextDecision,
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
    }

    var body: some View {
        FitnessScreen(
            title: "Summary",
            subtitle: session.date.formatted(date: .abbreviated, time: .omitted),
            systemImage: "checkmark.circle.fill"
        ) {
            FitnessCard(style: .hero) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
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
                                .textCase(.uppercase)
                            Text(summary.splitName)
                                .font(AppTypography.screenTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        }

                        Spacer()

                        CoachBadgeView(state: sessionPRs.isEmpty ? .ready : .pr)
                    }

                    Text(summary.takeaway)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        MetricTile(label: "Duration", value: summary.durationText, caption: nil, systemImage: "timer")
                        MetricTile(label: "Sets", value: "\(summary.workingSetCount)", caption: "Working", systemImage: "checkmark.circle")
                    }

                    HStack(spacing: 10) {
                        MetricTile(label: "Exercises", value: "\(summary.completedExerciseCount)", caption: "Completed", systemImage: "list.bullet")
                        MetricTile(label: "Rating", value: summary.ratingText ?? "-", caption: "Session feel", systemImage: "face.smiling")
                    }

                    if let notes = session.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(notes, systemImage: "note.text")
                            .font(.subheadline)
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
                                .font(.headline)
                            Spacer()
                            CoachBadgeView(state: sessionPRs.isEmpty ? .ready : .pr)
                        }

                        if sessionPRs.isEmpty {
                            Text("No PRs today, but you completed \(summary.workingSetCount) working sets.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        } else {
                            ForEach(sessionPRs.prefix(5)) { pr in
                                Label("\(pr.exerciseName) - \(pr.improvementDescription)", systemImage: "arrow.up.circle.fill")
                                    .font(.subheadline)
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

            if !completedExerciseLogs.isEmpty {
                DashboardSection(title: "Completed Exercises") {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(completedExerciseLogs.enumerated()), id: \.element.id) { index, exerciseLog in
                                if index > 0 {
                                    Divider()
                                }

                                SessionSummaryExerciseRow(exerciseLog: exerciseLog)
                            }
                        }
                    }
                }
            }

            DashboardSection(title: "Actions") {
                HStack(spacing: 10) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("History", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())

                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "house")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                }
                .font(.headline)

                HStack(spacing: 10) {
                    Button {
                        showingTemplateSave = true
                    } label: {
                        Label("Save Template", systemImage: "rectangle.stack.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())

                    Button {
                        showingReopenConfirmation = true
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }

                if matchingSplit != nil {
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
    }

    private var completedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { exerciseLog in
                exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
            }
    }

    private var matchingSplit: TrainingSplit? {
        activeSplits.first { split in
            let base = session.splitNameSnapshot.components(separatedBy: " - ").first ?? session.splitNameSnapshot
            return split.id == session.splitId || split.name == base
        }
    }

    private func reopenWorkout() {
        reopenService.reopen(session)
        try? modelContext.save()
        reopenedSession = session
    }

    private func updateMatchingSplit() {
        guard let matchingSplit else { return }
        splitUpdateService.replaceOrder(of: matchingSplit, with: session)
        try? modelContext.save()
    }
}

private struct SessionSummaryExerciseRow: View {
    @Environment(\.appTheme) private var appTheme

    let exerciseLog: ExerciseLog

    private var bestSet: SetLog? {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ExerciseIconView(
                    iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                    size: 34,
                    showBackground: true,
                    isDecorative: true
                )

                Text(exerciseLog.exerciseNameSnapshot)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(bestSetDescription)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
            }

            if let notes = exerciseLog.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var bestSetDescription: String {
        guard let bestSet else { return "Logged" }
        return "\(format(bestSet.weight))kg x \(bestSet.reps)"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
