import SwiftData
import SwiftUI

struct SplitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @Query
    private var splits: [TrainingSplit]

    @Query
    private var completedSessions: [WorkoutSession]

    @State private var showingAddSplit = false
    @State private var showingEditRotation = false
    @State private var showingOtherSplits = false
    @State private var pendingDeleteSplitID: UUID?
    @State private var deleteErrorText: String?
    @State private var dashboardSnapshot = SplitsDashboardSnapshot.empty
    @State private var lastDashboardSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?
    @State private var isDashboardVisible = false
    @State private var isPreparingInitialSnapshot = true

    private let coachEngine = CoachRecommendationEngine()
    private let targetService = TargetSuggestionService()
    private let rotationService = TrainingRotationService()

    init() {
        _splits = Query(Self.splitsDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
    }

    private static var splitsDescriptor: FetchDescriptor<TrainingSplit> {
        FetchDescriptor<TrainingSplit>(
            sortBy: [SortDescriptor(\.name)]
        )
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var activeProgrammeSplits: [TrainingSplit] {
        currentDashboardSnapshot.activeProgrammeSplits
    }

    private var otherSplits: [TrainingSplit] {
        currentDashboardSnapshot.otherSplits
    }

    private var recommendedSplitName: String? {
        currentDashboardSnapshot.recommendedSplitName
    }

    var body: some View {
        let snapshot = currentDashboardSnapshot

        NavigationStack {
            FitnessScreen {
                if isPreparingInitialSnapshot {
                    SwiftUI.ProgressView("Loading splits…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityIdentifier("splits-loading")
                } else if !snapshot.activeProgrammeSplits.isEmpty {
                    SplitProgrammeCard(
                        splits: snapshot.activeProgrammeSplits,
                        trainingCall: snapshot.trainingCall,
                        onEditRotation: {
                            presentEditRotation()
                        }
                    )

                    DashboardSection(title: "Training Days") {
                        ForEach(snapshot.activeProgrammeSplits) { split in
                            NavigationLink(value: split.id) {
                                SplitTrainingDayCard(
                                    split: split,
                                    status: snapshot.statusesBySplitName[split.name] ?? .ready,
                                    lastTrainedText: snapshot.lastTrainedTextBySplitName[split.name] ?? "No history yet",
                                    focusDescription: snapshot.focusTextBySplitName[split.name] ?? focusDescription(for: split)
                                )
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityIdentifier("split-card-\(split.name.peaklineAccessibilityIdentifierFragment)")
                        }
                    }
                } else {
                    DashboardEmptyStateCard(
                        title: "No active programme",
                        message: "Create training days or edit the rotation to build your programme dashboard.",
                        systemImage: "list.bullet.rectangle"
                    )

                    Button {
                        presentEditRotation()
                    } label: {
                        Label("Edit Rotation", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .accessibilityIdentifier("edit-empty-rotation-button")
                }

                if !snapshot.otherSplits.isEmpty {
                    FitnessCard(style: .compact, padding: 0) {
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(AppMotion.reorderSpring(reduceMotion: reduceMotion)) {
                                    showingOtherSplits.toggle()
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Other Splits")
                                            .font(AppTypography.sectionTitle)
                                            .foregroundStyle(appTheme.colors.textPrimary)
                                        Text("\(snapshot.otherSplits.count) inactive or custom templates")
                                            .font(AppTypography.body)
                                            .foregroundStyle(appTheme.colors.textSecondary)
                                    }

                                    Spacer(minLength: 12)

                                    Text(showingOtherSplits ? "Hide" : "Show")
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(showingOtherSplits ? appTheme.colors.accent : appTheme.colors.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(
                                            showingOtherSplits ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground,
                                            in: Capsule()
                                        )

                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.eyebrow)
                                        .foregroundStyle(appTheme.colors.textTertiary)
                                        .rotationEffect(.degrees(showingOtherSplits ? 90 : 0))
                                }
                                .padding(18)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PeaklineButtonPressStyle())
                            .accessibilityLabel(showingOtherSplits ? "Hide other splits" : "Show other splits")
                            .accessibilityValue(showingOtherSplits ? "expanded" : "collapsed")
                            .accessibilityIdentifier("other-splits-toggle")

                            if showingOtherSplits {
                                VStack(spacing: 0) {
                                    Text("Inactive templates are not used by today's recommendations.")
                                        .font(.footnote)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .padding(.bottom, 8)

                                    ForEach(snapshot.otherSplits) { split in
                                        Divider()
                                            .padding(.leading, 66)

                                        HStack(spacing: 0) {
                                            NavigationLink(value: split.id) {
                                                inactiveSplitRow(split)
                                            }
                                            .buttonStyle(PeaklineButtonPressStyle())
                                            .accessibilityIdentifier("other-split-card-\(split.name.peaklineAccessibilityIdentifierFragment)")

                                            Menu {
                                                Button(role: .destructive) {
                                                    pendingDeleteSplitID = split.id
                                                } label: {
                                                    Label("Delete Split", systemImage: "trash")
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis")
                                                    .font(AppTypography.compactCardTitle)
                                                    .foregroundStyle(appTheme.colors.textSecondary)
                                                    .frame(
                                                        width: appTheme.metrics.minimumHitTarget,
                                                        height: appTheme.metrics.minimumHitTarget
                                                    )
                                                    .background(appTheme.elevatedCardBackground, in: Circle())
                                            }
                                            .accessibilityLabel("Actions for \(split.name)")
                                            .padding(.trailing, appTheme.metrics.spacing12)
                                        }
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("splits-screen")
            .navigationTitle("Splits")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { splitID in
                SplitDetailRouteView(splitID: splitID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add split", systemImage: "plus.circle.fill") {
                        PerformanceTracer.mark(.toolbarBreadcrumb, "splits.add_split tapped")
                        NavigationInteraction.perform(
                            key: "splits.add",
                            destinationClass: .deep,
                            haptic: .selection
                        ) {
                            showingAddSplit = true
                        }
                    }
                    .accessibilityLabel("Add split")
                    .accessibilityIdentifier("add-split-button")
                }
            }
            .sheet(isPresented: $showingAddSplit) {
                AddSplitView()
                    .onAppear {
                        NavigationInteraction.destinationDidAppear(key: "splits.add")
                    }
            }
            .sheet(isPresented: $showingEditRotation) {
                EditActiveRotationView(splits: splits)
                    .onAppear {
                        NavigationInteraction.destinationDidAppear(key: "splits.rotation")
                    }
            }
            .alert("Delete split?", isPresented: deleteAlertBinding) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteSplitID = nil
                }
                Button("Delete", role: .destructive) {
                    deletePendingSplit()
                }
            } message: {
                Text("This removes the split template and its exercise setup. Workout history stays intact.")
            }
            .alert(
                "Split deletion failed",
                isPresented: Binding(
                    get: { deleteErrorText != nil },
                    set: { if !$0 { deleteErrorText = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorText ?? "")
            }
        }
        .onAppear {
            isDashboardVisible = true
            scheduleDashboardSnapshotRefresh(force: lastDashboardSignature == nil)
        }
        .onChange(of: dashboardSignatureForObservation) { oldSignature, newSignature in
            guard oldSignature != nil, newSignature != nil else { return }
            scheduleDashboardSnapshotRefresh()
        }
        .onDisappear {
            isDashboardVisible = false
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = nil
        }
    }

    private func presentEditRotation() {
        NavigationInteraction.perform(
            key: "splits.rotation",
            destinationClass: .deep,
            haptic: .selection
        ) {
            showingEditRotation = true
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteSplitID != nil
        } set: { showing in
            if !showing {
                pendingDeleteSplitID = nil
            }
        }
    }

    private var pendingDeleteSplit: TrainingSplit? {
        guard let pendingDeleteSplitID else { return nil }
        return splits.first { $0.id == pendingDeleteSplitID }
    }

    private var currentDashboardSnapshot: SplitsDashboardSnapshot {
        dashboardSnapshot
    }

    private var dashboardSignature: String {
        [
            splits.map { split in
                // Keep observation scalar-only. Exercise details are consumed
                // by the deferred dashboard build, while split edits advance
                // `updatedAt` and the workout generation covers history edits.
                return "\(split.id.uuidString):\(split.name):\(split.isActive):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|"),
            "revision:\(workoutWarmStartInvalidation.revision)",
            completedSessions.prefix(40).map { session in
                "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.perceivedDifficulty ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }

    private var dashboardSignatureForObservation: String? {
        isDashboardVisible ? dashboardSignature : nil
    }

    private func scheduleDashboardSnapshotRefresh(force: Bool = false) {
        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = Task { @MainActor in
            // The root tab's stable-frame marker uses one insertion-turn yield.
            // Keep relationship-heavy target/recommendation projection behind
            // that marker so selecting Splits cannot contend with its timing.
            await Task.yield()
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled, isDashboardVisible else { return }
            PerformanceTracer.mark(.unsafeBreadcrumb, "splits.dashboard deferred_refresh")
            refreshDashboardSnapshot(force: force)
        }
    }

    private func refreshDashboardSnapshot(force: Bool = false) {
        let signature = dashboardSignature
        guard force || signature != lastDashboardSignature else {
            isPreparingInitialSnapshot = false
            return
        }
        dashboardSnapshot = PerformanceTracer.trace(.splitsDashboard) {
            makeDashboardSnapshot()
        }
        lastDashboardSignature = signature
        isPreparingInitialSnapshot = false
    }

    private func makeDashboardSnapshot() -> SplitsDashboardSnapshot {
        let activeProgrammeSplits = rotationService.orderedActiveSplits(splits)
        let otherSplits = splits.filter { !$0.isActive }
        let analyticsSessions = completedSessions.map(WorkoutAnalyticsSession.init)
        let splitSnapshots = activeProgrammeSplits.map(TrainingSplitSnapshot.init)
        let targetSuggestionsByExerciseID = makeTargetSuggestions(
            for: activeProgrammeSplits.flatMap(\.exercises),
            completedSessions: analyticsSessions,
            targetService: targetService
        )
        let summary = coachEngine.makeSummary(
            activeSplits: splitSnapshots,
            completedSessions: analyticsSessions
        )
        let recommendedSplitName = summary.recommendedSplitName
        let trainingCall = TrainingCallSnapshotBuilder().make(
            decision: summary.trainingDecision,
            activeSplits: splitSnapshots,
            completedSessions: analyticsSessions
        )
        var statusesBySplitName: [String: SplitStatus] = [:]
        var lastTrainedTextBySplitName: [String: String] = [:]
        var focusTextBySplitName: [String: String] = [:]

        for split in activeProgrammeSplits {
            statusesBySplitName[split.name] = status(
                for: split,
                recommendedSplitName: recommendedSplitName,
                targetSuggestionsByExerciseID: targetSuggestionsByExerciseID
            )
            lastTrainedTextBySplitName[split.name] = lastTrainedDescription(for: split)
            focusTextBySplitName[split.name] = focusDescription(for: split)
        }

        return SplitsDashboardSnapshot(
            activeProgrammeSplits: activeProgrammeSplits,
            otherSplits: otherSplits,
            recommendedSplitName: recommendedSplitName,
            trainingCall: trainingCall,
            statusesBySplitName: statusesBySplitName,
            lastTrainedTextBySplitName: lastTrainedTextBySplitName,
            focusTextBySplitName: focusTextBySplitName
        )
    }

    private func inactiveSplitRow(_ split: TrainingSplit) -> some View {
        HStack(spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                size: 36,
                tint: appTheme.colors.textSecondary,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(split.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PeaklineText.count(split.exercises.count, singular: "exercise"))
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .layoutPriority(1)

            Spacer()

            SplitStatusBadge(status: split.isActive ? .custom : .inactive)

            Image(systemName: "chevron.right")
                .font(AppTypography.eyebrow)
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func delete(_ split: TrainingSplit) {
        do {
            modelContext.delete(split)
            try modelContext.save()
            try rotationService.normalizePersistedRotation(in: modelContext)
            try modelContext.save()
        } catch {
            deleteErrorText = "Peakline could not delete this split. Check the split still exists and try again."
        }
    }

    private func deletePendingSplit() {
        guard let pendingDeleteSplit else {
            pendingDeleteSplitID = nil
            return
        }
        delete(pendingDeleteSplit)
        pendingDeleteSplitID = nil
    }

    private func status(
        for split: TrainingSplit,
        recommendedSplitName: String?,
        targetSuggestionsByExerciseID: [UUID: TargetSuggestion]
    ) -> SplitStatus {
        guard split.isActive else { return .inactive }

        if wasTrainedRecently(split) {
            return .recentlyTrained
        }

        if isPrioritised(split) {
            return .prioritise
        }

        if hasProgressOpportunity(split, targetSuggestionsByExerciseID: targetSuggestionsByExerciseID) {
            return .progressOpportunity
        }

        if recommendedSplitName == split.name {
            return .ready
        }

        return .ready
    }

    private func wasTrainedRecently(_ split: TrainingSplit) -> Bool {
        guard let last = lastSession(for: split) else { return false }
        return Calendar.current.isDateInToday(last.date) || Calendar.current.isDateInYesterday(last.date)
    }

    private func isPrioritised(_ split: TrainingSplit) -> Bool {
        guard let last = lastSession(for: split) else { return false }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        return days >= 7
    }

    private func hasProgressOpportunity(
        _ split: TrainingSplit,
        targetSuggestionsByExerciseID: [UUID: TargetSuggestion]
    ) -> Bool {
        split.exercises.contains { splitExercise in
            let suggestion = targetSuggestionsByExerciseID[splitExercise.id]
                ?? targetService.suggestion(for: splitExercise, completedSessions: completedSessions)
            return suggestion.recommendationType == .increaseLoad || suggestion.recommendationType == .addReps
        }
    }

    private func lastSession(for split: TrainingSplit) -> WorkoutSession? {
        completedSessions.first { baseSplitName($0.splitNameSnapshot) == split.name }
    }

    private func lastTrainedDescription(for split: TrainingSplit) -> String {
        guard let last = lastSession(for: split) else { return "No history yet" }

        if Calendar.current.isDateInToday(last.date) {
            return "Last trained today"
        }

        if Calendar.current.isDateInYesterday(last.date) {
            return "Last trained yesterday"
        }

        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day
        if let days, days > 1, days < 14 {
            return "Last trained \(days) days ago"
        }

        return "Last trained \(last.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func focusDescription(for split: TrainingSplit) -> String {
        switch split.name {
        case "Push":
            return PeaklineText.joinedMetadata(["Chest", "Shoulders", "Triceps"])
        case "Pull":
            return PeaklineText.joinedMetadata(["Back", "Biceps", "Rear delts"])
        case "Legs":
            return PeaklineText.joinedMetadata(["Quads", "Hamstrings", "Calves"])
        default:
            return split.splitType.displayName
        }
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

extension String {
    var peaklineAccessibilityIdentifierFragment: String {
        let scalars = unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }

        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

private func makeTargetSuggestions(
    for exercises: [SplitExercise],
    completedSessions: [WorkoutAnalyticsSession],
    targetService: TargetSuggestionService
) -> [UUID: TargetSuggestion] {
    Dictionary(
        uniqueKeysWithValues: exercises.map { exercise in
            (
                exercise.id,
                targetService.suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
            )
        }
    )
}

private struct SplitsDashboardSnapshot {
    let activeProgrammeSplits: [TrainingSplit]
    let otherSplits: [TrainingSplit]
    let recommendedSplitName: String?
    let trainingCall: TrainingCallSnapshot
    let statusesBySplitName: [String: SplitStatus]
    let lastTrainedTextBySplitName: [String: String]
    let focusTextBySplitName: [String: String]

    static let empty = SplitsDashboardSnapshot(
        activeProgrammeSplits: [],
        otherSplits: [],
        recommendedSplitName: nil,
        trainingCall: .placeholder,
        statusesBySplitName: [:],
        lastTrainedTextBySplitName: [:],
        focusTextBySplitName: [:]
    )
}

private struct SplitDetailRouteView: View {
    let splitID: UUID

    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    var body: some View {
        if let split = splits.first(where: { $0.id == splitID }) {
            SplitDetailView(split: split)
        } else {
            FitnessScreen(
                title: "Split unavailable",
                subtitle: "This split may have been deleted or changed.",
                systemImage: "exclamationmark.triangle"
            ) {
                DashboardEmptyStateCard(
                    title: "Split no longer exists",
                    message: "Return to Splits and choose an available training day.",
                    systemImage: "list.bullet.rectangle"
                )
            }
            .accessibilityIdentifier("split-detail-missing-screen")
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SplitDetailView: View {
    @Environment(\.appTheme) private var appTheme
    @Bindable var split: TrainingSplit

    @Query
    private var completedSessions: [WorkoutSession]

    @State private var targetSuggestionsByExerciseID: [UUID: TargetSuggestion] = [:]
    @State private var lastTargetSuggestionSignature: String?

    private let targetService = TargetSuggestionService()

    init(split: TrainingSplit) {
        self.split = split
        _completedSessions = Query(Self.completedSessionsDescriptor)
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        let suggestionsByExerciseID = currentTargetSuggestionsByExerciseID

        FitnessScreen {
            splitHeroCard

            DashboardSection(title: "Exercises") {
                if orderedExercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises yet",
                        message: "Add exercises to make this split useful in previews and coaching.",
                        systemImage: "dumbbell"
                    )
                } else {
                    FitnessCard(style: .compact, padding: 14) {
                        VStack(spacing: 0) {
                            ForEach(Array(orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 50)
                                }

                                SplitExerciseRow(
                                    exercise: exercise,
                                    suggestion: targetSuggestion(
                                        for: exercise,
                                        suggestionsByExerciseID: suggestionsByExerciseID
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("split-detail-screen")
        .navigationTitle(split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink {
                SplitEditorView(split: split)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("split-edit-button")
        }
        .onAppear {
            refreshTargetSuggestions(force: true)
        }
        .onChange(of: targetSuggestionSignature) { _, _ in
            refreshTargetSuggestions()
        }
    }

    private var targetSuggestionSignature: String {
        [
            orderedExercises.map {
                "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.orderIndex):\($0.exerciseNameSnapshot):\($0.minReps):\($0.maxReps)"
            }
            .joined(separator: "|"),
            completedSessions.prefix(60).map { session in
                let logSignature = session.exerciseLogs
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .map { log in
                        let setSignature = log.setLogs
                            .sorted { $0.setNumber < $1.setNumber }
                            .map { "\($0.id.uuidString):\($0.setNumber):\($0.weight):\($0.reps):\($0.completed):\($0.isWarmup)" }
                            .joined(separator: ",")
                        return "\(log.id.uuidString):\(log.exerciseId.uuidString):\(log.orderIndex):\(setSignature)"
                    }
                    .joined(separator: ";")
                return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(logSignature)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }

    private var currentTargetSuggestionsByExerciseID: [UUID: TargetSuggestion] {
        let signature = targetSuggestionSignature
        guard signature == lastTargetSuggestionSignature else {
            let analyticsSessions = completedSessions.map(WorkoutAnalyticsSession.init)
            return makeTargetSuggestions(
                for: orderedExercises,
                completedSessions: analyticsSessions,
                targetService: targetService
            )
        }

        return targetSuggestionsByExerciseID
    }

    private func refreshTargetSuggestions(force: Bool = false) {
        let signature = targetSuggestionSignature
        guard force || signature != lastTargetSuggestionSignature else { return }

        let analyticsSessions = completedSessions.map(WorkoutAnalyticsSession.init)
        targetSuggestionsByExerciseID = makeTargetSuggestions(
            for: orderedExercises,
            completedSessions: analyticsSessions,
            targetService: targetService
        )
        lastTargetSuggestionSignature = signature
    }

    private func targetSuggestion(
        for exercise: SplitExercise,
        suggestionsByExerciseID: [UUID: TargetSuggestion]
    ) -> TargetSuggestion {
        suggestionsByExerciseID[exercise.id] ?? targetService.suggestion(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.exerciseNameSnapshot,
            minReps: exercise.minReps,
            maxReps: exercise.maxReps,
            completedSessions: [WorkoutAnalyticsSession]()
        )
    }

    private var splitHeroCard: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ExerciseIconTile(
                        iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                        title: nil,
                        size: 54,
                        style: .compact,
                        tint: split.isActive ? appTheme.colors.accent : appTheme.colors.textSecondary
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(split.isActive ? "Active Training Day" : "Inactive Template")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text(split.name)
                            .font(AppTypography.heroTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                            .accessibilityIdentifier("split-detail-title-\(split.name.peaklineAccessibilityIdentifierFragment)")
                        Text(
                            PeaklineText.joinedMetadata([
                                PeaklineText.count(orderedExercises.count, singular: "exercise"),
                                "\(split.daysPerWeek) days/week"
                            ])
                        )
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    SplitStatusBadge(status: detailStatus)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        MetricTile(label: "Last trained", value: compactLastTrainedText, caption: nil, systemImage: "clock.arrow.circlepath")
                        MetricTile(label: "Focus", value: focusDescription, caption: split.splitType.displayName, systemImage: "scope")
                    }

                    VStack(spacing: 10) {
                        MetricTile(label: "Last trained", value: compactLastTrainedText, caption: nil, systemImage: "clock.arrow.circlepath")
                        MetricTile(label: "Focus", value: focusDescription, caption: split.splitType.displayName, systemImage: "scope")
                    }
                }
            }
        }
    }

    private var detailStatus: SplitStatus {
        guard split.isActive else { return .inactive }
        guard let last = lastSession else { return .ready }
        if Calendar.current.isDateInToday(last.date) || Calendar.current.isDateInYesterday(last.date) {
            return .recentlyTrained
        }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        return days >= 7 ? .prioritise : .ready
    }

    private var lastSession: WorkoutSession? {
        completedSessions.first { baseSplitName($0.splitNameSnapshot) == split.name }
    }

    private var compactLastTrainedText: String {
        guard let lastSession else { return "Never" }
        if Calendar.current.isDateInToday(lastSession.date) { return "Today" }
        if Calendar.current.isDateInYesterday(lastSession.date) { return "Yesterday" }
        return lastSession.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var focusDescription: String {
        switch split.name {
        case "Push":
            return "Chest"
        case "Pull":
            return "Back"
        case "Legs":
            return "Legs"
        default:
            return "Custom"
        }
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

private struct AddSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var splitType = SplitType.custom
    @State private var daysPerWeek = 3
    @State private var addToActiveRotation = true

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
                    Toggle("Add to active rotation", isOn: $addToActiveRotation)
                }
            }
            .peaklineGroupedContent()
            .peaklineKeyboardDismissal()
            .accessibilityIdentifier("add-split-screen")
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
        let existingSplits = (try? modelContext.fetch(FetchDescriptor<TrainingSplit>())) ?? []
        let nextRotationIndex = existingSplits
            .filter(\.isActive)
            .compactMap(\.activeRotationIndex)
            .max()
            .map { $0 + 1 } ?? existingSplits.filter(\.isActive).count
        let split = TrainingSplit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            splitType: splitType,
            isActive: addToActiveRotation,
            activeRotationIndex: addToActiveRotation ? nextRotationIndex : nil,
            daysPerWeek: daysPerWeek
        )
        modelContext.insert(split)
        try? modelContext.save()
        dismiss()
    }
}

private struct EditActiveRotationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let splits: [TrainingSplit]

    @State private var orderedSplitIDs: [UUID]

    private let rotationService = TrainingRotationService()

    init(splits: [TrainingSplit]) {
        self.splits = splits
        _orderedSplitIDs = State(
            initialValue: TrainingRotationService()
                .orderedActiveSplits(splits)
                .map(\.id)
        )
    }

    private var orderedSplits: [TrainingSplit] {
        orderedSplitIDs.compactMap { id in
            splits.first { $0.id == id }
        }
    }

    private var availableSplits: [TrainingSplit] {
        let activeIDs = Set(orderedSplitIDs)
        return splits
            .filter { !activeIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if orderedSplits.isEmpty {
                        Text("No training days are active. You can save an empty rotation or add a template below.")
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        ForEach(orderedSplits) { split in
                            HStack(spacing: 12) {
                                ExerciseIconView(
                                    iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                                    size: 34,
                                    tint: appTheme.colors.accent,
                                    showBackground: false,
                                    isDecorative: true
                                )

                                Text(split.name)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .onMove { source, destination in
                            orderedSplitIDs.move(fromOffsets: source, toOffset: destination)
                        }
                        .onDelete { offsets in
                            orderedSplitIDs.remove(atOffsets: offsets)
                        }
                    }
                } header: {
                    Text("Active Rotation")
                } footer: {
                    Text("Drag training days into the order Peakline should recommend them.")
                }

                if !availableSplits.isEmpty {
                    Section("Available Training Days") {
                        ForEach(availableSplits) { split in
                            Button {
                                orderedSplitIDs.append(split.id)
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseIconView(
                                        iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                                        size: 34,
                                        tint: appTheme.colors.textSecondary,
                                        showBackground: false,
                                        isDecorative: true
                                    )
                                    Text(split.name)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(appTheme.colors.textAccent)
                                }
                            }
                            .accessibilityLabel("Add \(split.name) to active rotation")
                        }
                    }
                }
            }
            .peaklineGroupedContent()
            .environment(\.editMode, .constant(.active))
            .accessibilityIdentifier("edit-active-rotation-screen")
            .navigationTitle("Edit Rotation")
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
                    .accessibilityIdentifier("save-active-rotation-button")
                }
            }
        }
    }

    private func save() {
        try? rotationService.applyRotation(
            orderedSplitIDs: orderedSplitIDs,
            to: splits,
            in: modelContext
        )
        dismiss()
    }
}

private struct SplitEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
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
                Toggle("In Active Rotation", isOn: activeRotationBinding)
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
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(orderedExercises) { splitExercise in
                        SplitExerciseEditorRow(splitExercise: splitExercise)
                    }
                    .onDelete(perform: deleteExercises)
                    .onMove(perform: moveExercises)
                }
            }
        }
        .peaklineGroupedContent()
        .peaklineKeyboardDismissal()
        .navigationTitle("Edit Split")
        .toolbar {
            EditButton()
        }
        .onDisappear {
            split.updatedAt = .now
            try? modelContext.save()
        }
    }

    private var activeRotationBinding: Binding<Bool> {
        Binding {
            split.isActive
        } set: { isActive in
            split.isActive = isActive
            if isActive {
                let allSplits = (try? modelContext.fetch(FetchDescriptor<TrainingSplit>())) ?? []
                split.activeRotationIndex = allSplits
                    .filter { $0.isActive && $0.id != split.id }
                    .compactMap(\.activeRotationIndex)
                    .max()
                    .map { $0 + 1 } ?? allSplits.filter { $0.isActive && $0.id != split.id }.count
            } else {
                split.activeRotationIndex = nil
            }
            split.updatedAt = .now
            try? TrainingRotationService().normalizePersistedRotation(in: modelContext)
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
            notes: nil
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
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: splitExercise),
                size: 36,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(splitExercise.exerciseNameSnapshot)
                    .font(AppTypography.sectionTitle)

                Stepper("Sets: \(splitExercise.targetSets)", value: $splitExercise.targetSets, in: 1...10)
                Stepper("Min reps: \(splitExercise.minReps)", value: $splitExercise.minReps, in: 1...50)
                Stepper("Max reps: \(splitExercise.maxReps)", value: $splitExercise.maxReps, in: max(splitExercise.minReps, 1)...50)
                Stepper("Rest: \(restText)", value: Binding($splitExercise.restSeconds, replacingNilWith: 120), in: 30...300, step: 15)
            }
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
