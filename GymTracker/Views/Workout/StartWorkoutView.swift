import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    var body: some View {
        NavigationStack {
            StartWorkoutContentView()
        }
    }
}

struct StartWorkoutContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { !$0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var unfinishedSessions: [WorkoutSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?
    @State private var pendingDiscardSession: WorkoutSession?
    @State private var previewSplit: WorkoutPreviewSplit?
    @State private var route: StartWorkoutRoute?
    @State private var templateCount = 0

    private let coachEngine = CoachRecommendationEngine()
    private let modePlanner = WorkoutModePlanner()
    private let summaryBuilder = SessionSummaryBuilder()
    private let reuseBuilder = WorkoutReuseBuilder()
    private let templateStore = WorkoutTemplateStore()

    private var coachSummary: CoachRecommendationSummary {
        coachEngine.makeSummary(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    private var recommendedSplit: TrainingSplit? {
        guard let name = coachSummary.recommendedSplitName else { return nil }
        return activeSplits.first { $0.name == name }
    }

    private var displayedSplits: [TrainingSplit] {
        let pplNames = ["Push", "Pull", "Legs"]
        let pplSplits = pplNames.compactMap { name in activeSplits.first { $0.name == name } }
        return pplSplits.isEmpty ? activeSplits : pplSplits
    }

    var body: some View {
        FitnessScreen(
            title: "Workout",
            subtitle: "Prepare the right session, then log fast.",
            systemImage: "figure.strengthtraining.traditional"
        ) {
            if let unfinishedSession = unfinishedSessions.first {
                activeWorkoutCard(unfinishedSession)
            }

            if let recommendedSplit {
                recommendedWorkoutCard(recommendedSplit)
            }

            reuseCard

            DashboardSection(title: "Start") {
                ForEach(displayedSplits) { split in
                    splitStartCard(split)
                }

                emptyWorkoutCard
            }

            if let lastSession = completedSessions.first {
                recentSessionCard(lastSession)
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
        .navigationDestination(item: $previewSplit) { split in
            WorkoutPreviewView(split: split)
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .coach:
                CoachContentView()
            case .templates:
                WorkoutTemplateLibraryView()
            }
        }
        .alert("Discard active workout?", isPresented: discardAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDiscardSession = nil
            }
            Button("Discard", role: .destructive) {
                discardPendingWorkout()
            }
        } message: {
            Text("This removes the unfinished workout and its logged sets.")
        }
        .onAppear {
            templateCount = templateStore.loadTemplates().count
        }
    }

    private func activeWorkoutCard(_ session: WorkoutSession) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: session.splitNameSnapshot),
                        size: 46,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Workout")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(session.splitNameSnapshot)
                            .font(.title2.bold())
                    }

                    Spacer()

                    MetricTile(label: "Elapsed", value: activeElapsedText(for: session), caption: nil, systemImage: "timer")
                        .frame(maxWidth: 150)
                }

                Text(resumeSummary(for: session))
                    .font(.subheadline)
                    .foregroundStyle(appTheme.mutedText)

                HStack {
                    Button {
                        activeSession = session
                    } label: {
                        Label("Resume", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button(role: .destructive) {
                        pendingDiscardSession = session
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())
                    .foregroundStyle(appTheme.colors.danger)
                }
            }
        }
    }

    private func recommendedWorkoutCard(_ split: TrainingSplit) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ExerciseIconTile(
                        iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                        title: nil,
                        size: 58,
                        style: .compact
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(split.name)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    }

                    Spacer()
                    CoachBadgeView(state: .ready)
                }

                Text(coachSummary.reason)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.mutedText)

                HStack {
                    Button {
                        preview(split)
                    } label: {
                        Label("Preview", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button {
                        route = .coach
                    } label: {
                        Label("Coach", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
    }

    private func splitStartCard(_ split: TrainingSplit) -> some View {
        Button {
            preview(split)
        } label: {
            SplitCardView(
                splitName: split.name,
                lastTrainedText: lastTrainedText(for: split),
                estimatedDurationText: estimatedDurationText(for: split),
                exerciseCount: split.exercises.count,
                badgeState: badgeState(for: split),
                actionTitle: nil,
                action: nil
            )
        }
        .buttonStyle(.plain)
    }

    private func preview(_ split: TrainingSplit) {
        previewSplit = WorkoutPreviewSplit(split)
    }

    private var emptyWorkoutCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ExerciseIconView(
                        iconKey: .genericExercise,
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Empty Workout")
                            .font(.title3.bold())
                        Text("Build a one-off session from scratch.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }

                    Spacer()
                    CoachBadgeView(state: .baseline)
                }

                Button {
                    activeSession = createEmptyWorkout()
                } label: {
                    Label("Start Empty", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeutralFitnessButtonStyle())
            }
        }
    }

    private var reuseCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: .genericExercise,
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reuse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text("Repeat or start from a template")
                            .font(.title3.bold())
                        Text(templateCount == 0 ? "No saved templates yet" : "\(templateCount) saved templates")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }

                    Spacer()
                }

                HStack {
                    Button {
                        if let lastSession = completedSessions.first {
                            previewSplit = reuseBuilder.previewSplit(from: lastSession)
                        }
                    } label: {
                        Label("Repeat Last", systemImage: "repeat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(completedSessions.isEmpty)

                    Button {
                        route = .templates
                    } label: {
                        Label("Templates", systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
    }

    private func recentSessionCard(_ session: WorkoutSession) -> some View {
        let summary = summaryBuilder.build(from: session, completedSessions: completedSessions, activeSplits: activeSplits)

        return FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: session.splitNameSnapshot),
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(session.splitNameSnapshot)
                            .font(.title3.bold())
                    }

                    Spacer()
                    CoachBadgeView(state: summary.bestSetImprovements.isEmpty ? .ready : .pr)
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Duration", value: summary.durationText, caption: nil, systemImage: "timer")
                    MetricTile(label: "Rating", value: summary.ratingText ?? "-", caption: nil, systemImage: "face.smiling")
                }

                Text(summary.bestSetImprovements.first ?? summary.takeaway)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.mutedText)

                Button {
                    previewSplit = reuseBuilder.previewSplit(from: session)
                } label: {
                    Label("Repeat Last Workout", systemImage: "repeat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
            }
        }
    }

    private func lastTrainedText(for split: TrainingSplit) -> String {
        guard let session = completedSessions.first(where: { baseSplitName($0.splitNameSnapshot) == split.name }) else {
            return "No history yet"
        }

        return "Last trained \(session.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func estimatedDurationText(for split: TrainingSplit) -> String {
        let selectable = split.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(WorkoutSelectableExercise.init)
        let planned = modePlanner.plannedExercises(from: selectable, mode: .full)
        let duration = modePlanner.estimatedDurationMinutes(for: planned, mode: .full)
        return "\(duration.lowerBound)-\(duration.upperBound)m"
    }

    private func badgeState(for split: TrainingSplit) -> CoachBadgeState {
        guard let recommendedName = coachSummary.recommendedSplitName else { return .baseline }
        return recommendedName == split.name ? .ready : .repeatTarget
    }

    private func activeElapsedText(for session: WorkoutSession) -> String {
        guard let startedAt = session.startedAt else { return "0:00" }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds)
        return "\(elapsed / 60):\(String(format: "%02d", elapsed % 60))"
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding {
            pendingDiscardSession != nil
        } set: { showing in
            if !showing {
                pendingDiscardSession = nil
            }
        }
    }

    private func discardPendingWorkout() {
        guard let pendingDiscardSession else { return }
        modelContext.delete(pendingDiscardSession)
        try? modelContext.save()
        self.pendingDiscardSession = nil
    }

    private func resumeSummary(for session: WorkoutSession) -> String {
        let started = (session.startedAt ?? session.date).formatted(date: .abbreviated, time: .shortened)
        let completedSets = session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        return "Started \(started) - \(completedSets) completed sets"
    }

    private func createEmptyWorkout() -> WorkoutSession {
        let startDate = Date()
        let session = WorkoutSession(date: startDate, startedAt: startDate)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

private enum StartWorkoutRoute: Hashable, Identifiable {
    case coach
    case templates

    var id: Self { self }
}
