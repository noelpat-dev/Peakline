import SwiftData
import SwiftUI

private struct WorkoutPreviewExerciseRowFrameCollector: ViewModifier {
    let isEnabled: Bool
    let updateFrames: ([UUID: CGRect]) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onPreferenceChange(WorkoutPreviewExerciseRowFramePreferenceKey.self) { frames in
                updateFrames(frames)
            }
        } else {
            content
        }
    }
}

struct WorkoutPreviewExerciseDropTarget: Equatable {
    let exerciseID: UUID
    let edge: WorkoutPreviewExerciseDropEdge

    static func resolve(
        location: CGPoint,
        sourceID: UUID,
        selectedExerciseIds: [UUID],
        rowFrames: [UUID: CGRect]
    ) -> Self? {
        guard
            let sourceIndex = selectedExerciseIds.firstIndex(of: sourceID),
            let destination = (
                rowFrames
                    .filter { id, frame in
                        id != sourceID && frame.contains(location)
                    }
                    .min { lhs, rhs in
                        abs(lhs.value.midY - location.y) < abs(rhs.value.midY - location.y)
                    }
            ),
            let destinationIndex = selectedExerciseIds.firstIndex(of: destination.key)
        else {
            return nil
        }

        return Self(
            exerciseID: destination.key,
            edge: sourceIndex < destinationIndex ? .after : .before
        )
    }
}

private struct WorkoutPreviewCoachActionsCard: View {
    @Environment(\.appTheme) private var appTheme

    let recommendations: [CoachWorkoutActionRecommendation]
    let appliedTitle: String?
    let resetAction: () -> Void
    let requestAction: (CoachWorkoutAdjustmentAction) -> Void

    var body: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Coach Actions", systemImage: "slider.horizontal.3")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .accessibilityIdentifier("workout-preview-guidance-chips")

                if let appliedTitle {
                    HStack(spacing: 8) {
                        Label("\(appliedTitle) applied", systemImage: "checkmark.seal.fill")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSuccess)

                        Spacer(minLength: 8)

                        Button("Reset", action: resetAction)
                            .font(AppTypography.bodyEmphasis)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-preview-reset-original")
                    }
                }

                ForEach(recommendations) { recommendation in
                    Button {
                        requestAction(recommendation.action)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: recommendation.action.systemImage)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(recommendation.title)
                                    .font(AppTypography.bodyEmphasis)
                                Text(recommendation.summary)
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(AppTypography.eyebrow)
                                .foregroundStyle(appTheme.colors.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-action-\(recommendation.action.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-actions-card")
    }
}

struct WorkoutPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeSession: WorkoutSession?
    @State private var pendingWorkoutSaveID: UUID?
    @State private var activeWorkoutNavigationKey: String?
    @State private var selectedExerciseIds: [UUID] = []
    @State private var selectedMode: WorkoutMode = .full
    @State private var optionalExerciseId: UUID?
    @State private var pendingSubstitutionExercise: PlannedWorkoutExercise?
    @State private var activeCoachSheet: CoachWorkoutSheet?
    @State private var appliedWorkoutAdjustment: AppliedCoachWorkoutAdjustment?
    @State private var substitutionNotesByExerciseId: [UUID: String] = [:]
    @State private var renderSnapshot: WorkoutPreviewPreparedSnapshot
    @State private var didMarkInitialPreviewContent = false
    @State private var didMarkStartButtonVisible = false
    @State private var didMarkExerciseRowsVisible = false
    @State private var didMarkFullContentVisible = false
    @State private var exerciseOrderMounted = false
    @State private var exerciseRowFrames: [UUID: CGRect] = [:]
    @State private var gestureDropTarget: WorkoutPreviewExerciseDropTarget?

    let split: WorkoutPreviewSplit
    let preparedRoute: WorkoutPreviewPreparedRoute
    let tracksReorderFrames: Bool
    let requestReorderFrameTracking: () -> Void
    let onWorkoutFinished: (() -> Void)?

    private let workoutAdjustmentService = CoachWorkoutAdjustmentService()
    private let coachHistoryService = CoachActionHistoryService()
    private let deloadBlockService = SavedCoachDeloadBlockService()
    private let deloadReviewService = CoachDeloadCalendarReviewService()
    private let modePlanner = WorkoutModePlanner()
    private let substitutionService = ExerciseSubstitutionService()

    init(
        preparedRoute: WorkoutPreviewPreparedRoute,
        initialSnapshot: WorkoutPreviewPreparedSnapshot,
        tracksReorderFrames: Bool,
        requestReorderFrameTracking: @escaping () -> Void,
        onWorkoutFinished: (() -> Void)? = nil
    ) {
        self.split = preparedRoute.split
        self.preparedRoute = preparedRoute
        self.tracksReorderFrames = tracksReorderFrames
        self.requestReorderFrameTracking = requestReorderFrameTracking
        self.onWorkoutFinished = onWorkoutFinished
        _selectedMode = State(initialValue: preparedRoute.initialMode)
        _selectedExerciseIds = State(initialValue: initialSnapshot.selectedExerciseIDs)
        _renderSnapshot = State(initialValue: initialSnapshot)
    }

    fileprivate static func resolveWarmSnapshot(
        for route: WorkoutPreviewPreparedRoute,
        mode: WorkoutMode
    ) -> WorkoutPreviewPreparedSnapshot {
        if let snapshot = WorkoutPreviewWarmStartStore.shared.snapshot(for: route, mode: mode) {
            return snapshot
        }

        let fallback = WorkoutPreviewPreparedSnapshot.fallback(split: route.split, mode: mode)
        WorkoutPreviewWarmStartStore.shared.insertFallback(fallback)
        return fallback
    }

    private var currentRenderSnapshot: WorkoutPreviewPreparedSnapshot { renderSnapshot }

    private func markInitialPreviewContentIfNeeded() {
        guard !didMarkInitialPreviewContent else { return }
        didMarkInitialPreviewContent = true
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "first_content visible")
    }

    private func markStartButtonVisibleIfNeeded(_ source: String) {
        guard !didMarkStartButtonVisible else { return }
        didMarkStartButtonVisible = true
        PerformanceTracer.mark(.previewRouteStartButtonVisible, "\(source) split=\(split.name)")
    }

    private func markExerciseRowsVisibleIfNeeded(count: Int, source: String) {
        guard !didMarkExerciseRowsVisible else { return }
        didMarkExerciseRowsVisible = true
        PerformanceTracer.mark(.previewHydrationExerciseRowsReady, "\(source) count=\(count)")
    }

    private func markFullContentVisibleIfNeeded(snapshot: WorkoutPreviewPreparedSnapshot) {
        guard !didMarkFullContentVisible else { return }
        didMarkFullContentVisible = true
        PerformanceTracer.mark(.previewHydrationFullContentReady, "visible exercises=\(snapshot.plannedExercises.count)")
    }

    private func previewExerciseCard(
        exercise: PlannedWorkoutExercise,
        position: Int,
        totalCount: Int,
        previousExerciseID: UUID?,
        nextExerciseID: UUID?,
        suggestions: [UUID: TargetSuggestion]
    ) -> some View {
        WorkoutPreviewExerciseCard(
            exercise: exercise,
            suggestion: suggestions[exercise.id] ?? baselineSuggestion(for: exercise),
            requestSubstitute: {
                pendingSubstitutionExercise = exercise
            },
            moveToTop: {
                moveToTop(exercise)
            },
            moveToBottom: {
                moveToBottom(exercise)
            },
            moveUp: {
                guard let previousExerciseID else { return }
                reorderExercise(exercise.id, relativeTo: previousExerciseID)
            },
            moveDown: {
                guard let nextExerciseID else { return }
                reorderExercise(exercise.id, relativeTo: nextExerciseID)
            },
            remove: {
                remove(exercise)
            },
            canMoveToTop: position > 0,
            canMoveToBottom: position < totalCount - 1,
            position: position + 1,
            totalCount: totalCount,
            tracksReorderFrame: tracksReorderFrames,
            gestureDropEdge: gestureDropTarget?.exerciseID == exercise.id
                ? gestureDropTarget?.edge
                : nil,
            updateGestureDropTarget: { location in
                updateGestureDropTarget(sourceID: exercise.id, location: location)
            },
            finishGestureDrop: { location in
                finishGestureDrop(sourceID: exercise.id, location: location)
            },
            cancelGestureDrop: {
                cancelGestureDrop()
            }
        )
    }

    var body: some View {
        previewContent(snapshot: currentRenderSnapshot)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session) {
                activeSession = nil
                onWorkoutFinished?()
            }
            .onAppear {
                if let activeWorkoutNavigationKey {
                    NavigationInteraction.destinationDidAppear(
                        key: activeWorkoutNavigationKey
                    )
                    self.activeWorkoutNavigationKey = nil
                }
                persistLaunchedWorkoutIfNeeded(session)
            }
        }
        .sheet(item: $pendingSubstitutionExercise) { exercise in
            SubstitutionPickerSheet(
                title: "Substitute \(exercise.exerciseNameSnapshot)",
                candidates: currentRenderSnapshot.substitutionCandidates[exercise.id] ?? [],
                select: { candidate in
                    if let replacement = currentRenderSnapshot.exerciseLookup.byID[candidate.exerciseId] {
                        substitute(exercise, with: replacement, reason: .preferAlternative)
                    }
                }
            )
        }
        .sheet(item: $activeCoachSheet) { sheet in
            switch sheet {
            case let .actionPreview(preview):
                WorkoutAdjustmentPreviewSheet(
                    preview: preview,
                    preferences: .default,
                    splitMetadata: nil
                ) { editedPreview in
                    applyCoachAdjustment(editedPreview, snapshot: currentRenderSnapshot.intelligence)
                } cancel: {
                    recordCoachAction(preview: preview, outcome: .cancelled, snapshot: currentRenderSnapshot.intelligence)
                }
            case .deloadPlanner:
                ManualDeloadPlannerSheet(
                    defaultPlan: workoutAdjustmentService.defaultDeloadPlan(for: currentRenderSnapshot.intelligence.fatigueRisk),
                    fatigueRisk: currentRenderSnapshot.intelligence.fatigueRisk,
                    calendarPreview: { plan in
                        deloadReviewService.preview(plan: plan)
                    }
                ) { plan in
                    if let preview = currentRenderSnapshot.actionPreviews[.deloadStyleSession] {
                        activeCoachSheet = .actionPreview(preview)
                    }
                } savePlan: { plan in
                    saveDeloadBlock(plan, snapshot: currentRenderSnapshot.intelligence)
                }
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            PerformanceTracer.trace(.motionPreviewModeChange) {
                PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "mode_change begin mode=\(newMode.rawValue)")
                resetCoachAdjustment()
                let warmSnapshot = Self.resolveWarmSnapshot(for: preparedRoute, mode: newMode)
                AppMotion.withoutAnimation {
                    selectedExerciseIds = warmSnapshot.selectedExerciseIDs
                    renderSnapshot = warmSnapshot
                }
            }
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "mode_change end mode=\(newMode.rawValue)")
        }
        .onChange(of: selectedExerciseIds) { _, _ in
            rebuildLocalSnapshot()
        }
        .onChange(of: substitutionNotesByExerciseId) { _, _ in
            rebuildLocalSnapshot()
        }
        .onChange(of: appliedWorkoutAdjustment?.id) { _, _ in
            rebuildLocalSnapshot()
        }
    }

    private func previewContent(snapshot: WorkoutPreviewPreparedSnapshot) -> some View {
        hydratedPreviewContent(snapshot: snapshot)
    }

    private func hydratedPreviewContent(snapshot: WorkoutPreviewPreparedSnapshot) -> some View {
        FitnessScreen(
            title: "\(split.name) Preview",
            subtitle: PeaklineText.joinedMetadata([
                "\(selectedMode.displayName) mode",
                "~\(snapshot.estimatedDuration.lowerBound)–\(snapshot.estimatedDuration.upperBound) min"
            ]),
            systemImage: "figure.strengthtraining.traditional",
            contentLayout: .eager,
            locksHorizontalScrolling: true
        ) {
            DashboardSection(title: "Mode") {
                FitnessCard {
                    WorkoutModePicker(selection: $selectedMode)
                }
            }

            DashboardSection(title: "Session Snapshot") {
                planReadinessCard(snapshot: snapshot)
            }

            DashboardSection(title: "Coach Brief") {
                FitnessCard(style: .compact) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(snapshot.coachSummaryText)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            CoachBadgeView(state: snapshot.coachSummaryBadge)
                        }

                        if selectedMode != snapshot.trainingCall.recommendedMode {
                            Text("\(selectedMode.displayName) mode is selected. Coach recommends \(snapshot.trainingCall.recommendedMode.displayName.lowercased()) based on current signals.")
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("workout-preview-training-call-audit")

                WorkoutPreviewCoachActionsCard(
                    recommendations: snapshot.actionRecommendations,
                    appliedTitle: appliedWorkoutAdjustment?.title,
                    resetAction: resetCoachAdjustment,
                    requestAction: { action in
                        requestCoachAction(action, preparedSnapshot: snapshot)
                    }
                )

                if appliedWorkoutAdjustment != nil {
                    originalPlanShortcut(snapshot: snapshot)
                }
            }

            if exerciseOrderMounted {
                DashboardSection(title: "Exercise Order") {
                HStack {
                    Spacer()
                    Button("Select All") {
                        AppMotion.withoutAnimation {
                            selectedExerciseIds = snapshot.orderedExercises.map(\.id)
                        }
                    }
                    .font(AppTypography.bodyEmphasis)
                    .tint(appTheme.actionColor)
                }

                if snapshot.plannedExercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises selected",
                        message: "Choose at least one exercise before starting.",
                        systemImage: "list.bullet"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.plannedExercises.enumerated()), id: \.element.id) { index, exercise in
                            previewExerciseCard(
                                exercise: exercise,
                                position: index,
                                totalCount: snapshot.plannedExercises.count,
                                previousExerciseID: index > 0 ? snapshot.plannedExercises[index - 1].id : nil,
                                nextExerciseID: index < snapshot.plannedExercises.count - 1 ? snapshot.plannedExercises[index + 1].id : nil,
                                suggestions: snapshot.suggestions
                            )

                            if index < snapshot.plannedExercises.count - 1 {
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .background(
                        appTheme.cardBackground,
                        in: RoundedRectangle(
                            cornerRadius: appTheme.metrics.standardCardRadius,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: appTheme.metrics.standardCardRadius,
                            style: .continuous
                        )
                        .stroke(appTheme.cardBorder.opacity(0.62), lineWidth: 1)
                    }
                    .accessibilityIdentifier("workout-preview-basic-exercise-rows")
                    .onAppear {
                        markExerciseRowsVisibleIfNeeded(count: snapshot.plannedExercises.count, source: "hydrated")
                    }
                }
                }
                .onAppear {
                    markFullContentVisibleIfNeeded(snapshot: snapshot)
                }

                LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                DashboardSection(title: "Add Exercise") {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            optionalExerciseMenu(snapshot: snapshot)

                            HStack {
                                Button {
                                    addOptionalExercise()
                                } label: {
                                    Label("Add Selected", systemImage: "plus.circle")
                                }
                                .disabled(optionalExerciseId == nil)
                                .accessibilityIdentifier("workout-preview-add-selected-exercise")

                                Spacer()

                                if let coreExercise = snapshot.coreExercise {
                                    Button {
                                        addExercise(coreExercise, targetSets: 2, minReps: 8, maxReps: 15, notes: "Optional core work.")
                                    } label: {
                                        Label("Add Core", systemImage: "figure.core.training")
                                    }
                                    .disabled(snapshot.selectedExerciseIDSet.contains(coreExercise.id))
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                DashboardSection(title: "Start") {
                    FitnessInformationalActionCard(style: .standard) {
                        Text(startHint)
                            .font(.footnote)
                            .foregroundStyle(appTheme.mutedText)
                    } action: {
                        VStack(spacing: 10) {
                            startWorkoutButton(snapshot: snapshot, identifier: "workout-preview-start-footer")

                            if appliedWorkoutAdjustment != nil {
                                startOriginalPlanButton(snapshot: snapshot, identifier: "workout-preview-start-original-footer")
                            }
                        }
                    }
                }
                }
            }
        }
        .onAppear {
            markInitialPreviewContentIfNeeded()
            scheduleExerciseOrderMountIfNeeded()
        }
        .coordinateSpace(name: WorkoutPreviewExerciseOrderCoordinateSpace.name)
        .modifier(
            WorkoutPreviewExerciseRowFrameCollector(isEnabled: tracksReorderFrames) { frames in
                if exerciseRowFrames != frames {
                    exerciseRowFrames = frames
                }
            }
        )
        .environment(\.fitnessCardShadowsEnabled, false)
        .accessibilityIdentifier("workout-preview-hydrated-content")
    }

    private func scheduleExerciseOrderMountIfNeeded() {
        guard !exerciseOrderMounted else { return }

        // The prepared session summary, Coach Brief, and primary Start action
        // form the first real frame. The one full-detail eager order follows on
        // the next rendered frame without introducing a duplicate or shell.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exerciseOrderMounted = true
        }
    }

    private func optionalExerciseMenu(snapshot: WorkoutPreviewPreparedSnapshot) -> some View {
        let selectionLabel = optionalExerciseId.flatMap { selectedID in
            snapshot.addableExercises.first { $0.id == selectedID }?.name
        } ?? "Choose"

        return Menu {
            Button("Choose") {
                optionalExerciseId = nil
            }

            Divider()

            ForEach(snapshot.addableExercises) { exercise in
                Button {
                    optionalExerciseId = exercise.id
                } label: {
                    if optionalExerciseId == exercise.id {
                        Label(exercise.name, systemImage: "checkmark")
                    } else {
                        Text(exercise.name)
                    }
                }
                .accessibilityIdentifier("workout-preview-optional-exercise-option-\(exercise.name)")
            }
        } label: {
            HStack(spacing: 10) {
                Text("Optional exercise")
                    .foregroundStyle(appTheme.colors.textPrimary)

                Spacer(minLength: 12)

                Text(selectionLabel)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.chip)
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Optional exercise")
        .accessibilityValue(selectionLabel)
        .accessibilityHint("Opens all exercises available to add")
        .accessibilityIdentifier("workout-preview-optional-exercise-menu")
    }

    private func planReadinessCard(snapshot: WorkoutPreviewPreparedSnapshot) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: planReadinessIcon(snapshot: snapshot),
                        size: 38,
                        tint: planReadinessAccent(snapshot: snapshot),
                        background: planReadinessAccent(snapshot: snapshot).opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(planReadinessTitle(snapshot: snapshot))
                            .font(AppTypography.compactCardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(planReadinessMessage(snapshot: snapshot))
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    CoachBadgeView(state: planReadinessBadge(snapshot: snapshot))
                }

                HStack(alignment: .top, spacing: 12) {
                    planReadinessStat(label: "Mode", value: selectedMode.displayName, systemImage: selectedMode.systemImage)
                    Divider().frame(height: 44)
                    planReadinessStat(label: "Exercises", value: "\(snapshot.plannedExercises.count)", systemImage: "list.bullet")
                    Divider().frame(height: 44)
                    planReadinessStat(label: "Time", value: "\(snapshot.estimatedDuration.lowerBound)–\(snapshot.estimatedDuration.upperBound) min", systemImage: "clock")
                }
                .accessibilityElement(children: .combine)

                if let appliedWorkoutAdjustment {
                    Label(
                        "\(appliedWorkoutAdjustment.title) is active for this workout only. The split template stays unchanged.",
                        systemImage: "wand.and.stars"
                    )
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                startWorkoutButton(snapshot: snapshot, identifier: "workout-preview-start")
            }
        }
    }

    private func planReadinessStat(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(AppTypography.badge)
                Text(label)
                    .font(AppTypography.metadataEmphasis)
                    .textCase(.uppercase)
            }
            .foregroundStyle(appTheme.mutedText)

            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planReadinessTitle(snapshot: WorkoutPreviewPreparedSnapshot) -> String {
        if appliedWorkoutAdjustment != nil {
            return "Coach-adjusted plan"
        }

        if snapshot.plannedExercises.isEmpty {
            return "Plan needs exercises"
        }

        return "\(selectedMode.displayName) plan ready"
    }

    private func planReadinessMessage(snapshot: WorkoutPreviewPreparedSnapshot) -> String {
        if snapshot.plannedExercises.isEmpty {
            return "Select at least one exercise before starting."
        }

        if let appliedWorkoutAdjustment {
            return "\(appliedWorkoutAdjustment.title) is the plan that will start when you press play."
        }

        switch selectedMode {
        case .full:
            return "The planned session is intact, with every selected exercise kept in order."
        case .quick:
            return "Main lifts stay first so the session can move quickly without losing focus."
        case .recovery:
            return "Volume is lower and targets stay controlled for a lighter training day."
        case .heavy:
            return "Main lifts lead, with a focus on controlled, heavier work."
        }
    }

    private func planReadinessBadge(snapshot: WorkoutPreviewPreparedSnapshot) -> CoachBadgeState {
        if snapshot.plannedExercises.isEmpty {
            return .missedSplit
        }

        return snapshot.coachSummaryBadge
    }

    private func planReadinessIcon(snapshot: WorkoutPreviewPreparedSnapshot) -> String {
        snapshot.plannedExercises.isEmpty ? "exclamationmark.triangle" : selectedMode.systemImage
    }

    private func planReadinessAccent(snapshot: WorkoutPreviewPreparedSnapshot) -> Color {
        snapshot.plannedExercises.isEmpty ? appTheme.warningColor : appTheme.colors.accent
    }

    private func originalPlanShortcut(snapshot: WorkoutPreviewPreparedSnapshot) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textAccent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Original plan")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(selectedMode.displayName) mode without the coach adjustment.")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                startOriginalPlanButton(snapshot: snapshot, identifier: "workout-preview-start-original")
            }
        }
    }

    private func startWorkoutButton(
        snapshot: WorkoutPreviewPreparedSnapshot,
        identifier: String
    ) -> some View {
        Button {
            startWorkout(
                using: makeLaunchDraft(
                    exercises: snapshot.plannedExercises,
                    modeLabel: appliedWorkoutAdjustment.map {
                        "\(selectedMode.displayName) - \($0.title)"
                    } ?? selectedMode.displayName
                )
            )
        } label: {
            Label(startButtonTitle, systemImage: "play.circle.fill")
                .font(AppTypography.sectionTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
        .accessibilityIdentifier(identifier)
        .disabled(snapshot.plannedExercises.isEmpty)
        .onAppear {
            markStartButtonVisibleIfNeeded(identifier)
        }
    }

    private func startOriginalPlanButton(
        snapshot: WorkoutPreviewPreparedSnapshot,
        identifier: String
    ) -> some View {
        Button {
            startOriginalPlan(snapshot: snapshot)
        } label: {
            Label("Start Original Plan", systemImage: "arrow.uturn.backward.circle")
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
        .accessibilityIdentifier(identifier)
        .disabled(snapshot.basePlannedExercises.isEmpty)
    }

    private func startOriginalPlan(snapshot: WorkoutPreviewPreparedSnapshot) {
        if let appliedWorkoutAdjustment {
            recordCoachAction(
                preview: appliedWorkoutAdjustment.preview,
                outcome: .bypassed,
                snapshot: snapshot.intelligence,
                saveImmediately: false
            )
        }

        startWorkout(
            using: makeLaunchDraft(
                exercises: snapshot.basePlannedExercises,
                modeLabel: "\(selectedMode.displayName) Original"
            )
        )
    }

    private var startButtonTitle: String {
        if let appliedWorkoutAdjustment {
            return "Start \(appliedWorkoutAdjustment.title)"
        }

        return "Start \(split.name)"
    }

    private var startHint: String {
        if let appliedWorkoutAdjustment {
            return "\(appliedWorkoutAdjustment.title) changes only this workout preview. The original split stays unchanged."
        }

        switch selectedMode {
        case .full:
            return "Full mode keeps the planned session intact."
        case .quick:
            return "Quick mode prioritises the main lifts and keeps the session tight."
        case .recovery:
            return "Recovery mode lowers volume and softens target pressure."
        case .heavy:
            return "Heavy mode prioritises the main lifts."
        }
    }

    private func coachSummaryText(
        suggestions: [UUID: TargetSuggestion],
        mode: WorkoutMode,
        trainingCall: TrainingCallSnapshot
    ) -> String {
        if trainingCall.recommendedMode != mode || trainingCall.isConservative {
            return trainingCall.reason
        }

        let suggestions = suggestions.values
        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) {
            return "Performance has dipped on at least one lift. Keep the session controlled and rest properly."
        }

        if let increase = suggestions.first(where: { $0.recommendationType == .increaseLoad }) {
            return "Progress opportunity: push \(increase.exerciseName), then keep the rest efficient."
        }

        if mode == .recovery {
            return "Lower stress session. Repeat targets, keep form clean, and avoid forcing PRs."
        }

        if mode == .quick {
            return "Short session. Hit the important lifts first and leave accessories optional."
        }

        return "Targets are ready. Repeat or add reps where the range allows."
    }

    private func coachSummaryBadge(suggestions: [UUID: TargetSuggestion], mode: WorkoutMode) -> CoachBadgeState {
        let suggestions = suggestions.values
        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) {
            return .fatigueRisk
        }
        if suggestions.contains(where: { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }) {
            return .ready
        }
        if mode == .recovery {
            return .recovery
        }
        return .repeatTarget
    }

    private func rebuildLocalSnapshot() {
        let source = renderSnapshot
        let orderedByID = Dictionary(
            source.orderedExercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let optionsByID = source.exerciseLookup.byID
        let selectedBase = selectedExerciseIds.compactMap { selectedID -> WorkoutSelectableExercise? in
            if let planned = orderedByID[selectedID] {
                return WorkoutSelectableExercise(
                    id: planned.id,
                    exerciseId: planned.exerciseId,
                    name: planned.name,
                    targetSets: planned.targetSets,
                    minReps: planned.minReps,
                    maxReps: planned.maxReps,
                    notes: substitutionNotesByExerciseId[planned.exerciseId] ?? planned.notes
                )
            }

            guard let option = optionsByID[selectedID] else { return nil }
            return WorkoutSelectableExercise(
                id: option.id,
                exerciseId: option.id,
                name: option.name,
                targetSets: option.primaryMuscleGroup == .core ? 2 : 2,
                minReps: 8,
                maxReps: option.primaryMuscleGroup == .core ? 15 : 12,
                notes: substitutionNotesByExerciseId[option.id]
            )
        }
        let basePlan = modePlanner.plannedExercises(from: selectedBase, mode: selectedMode)
        let plan = appliedWorkoutAdjustment?.adjustedExercises ?? basePlan
        let suggestions = plan.reduce(into: [UUID: TargetSuggestion]()) { result, exercise in
            result[exercise.id] = source.suggestions[exercise.id]
                ?? source.suggestions.values.first(where: { $0.exerciseName == exercise.exerciseNameSnapshot })
                ?? baselineSuggestion(for: exercise)
        }
        let selectedOptionIDs = Set(plan.map(\.exerciseId))

        renderSnapshot = WorkoutPreviewPreparedSnapshot(
            splitID: source.splitID,
            splitSignature: source.splitSignature,
            sourceSignature: source.sourceSignature,
            mode: selectedMode,
            selectedExerciseIDs: selectedExerciseIds,
            orderedExercises: source.orderedExercises,
            exerciseOptions: source.exerciseOptions,
            addableExercises: source.exerciseOptions.filter { !selectedOptionIDs.contains($0.id) },
            coreExercise: source.coreExercise,
            basePlannedExercises: basePlan,
            plannedExercises: plan,
            estimatedDuration: modePlanner.estimatedDurationMinutes(
                for: plan,
                mode: selectedMode,
                calibration: source.durationCalibration,
                splitName: split.name
            ),
            durationCalibration: source.durationCalibration,
            suggestions: suggestions,
            alternatives: source.alternatives,
            substitutionCandidates: source.substitutionCandidates,
            intelligence: source.intelligence,
            plannedFatigueItems: source.plannedFatigueItems,
            actionRecommendations: source.actionRecommendations,
            actionPreviews: source.actionPreviews,
            trainingCall: source.trainingCall,
            coachSummaryText: coachSummaryText(
                suggestions: suggestions,
                mode: selectedMode,
                trainingCall: source.trainingCall
            ),
            coachSummaryBadge: coachSummaryBadge(suggestions: suggestions, mode: selectedMode),
            preparedAt: source.preparedAt
        )
    }

    private func remove(_ exercise: PlannedWorkoutExercise) {
        resetCoachAdjustment()
        withAnimation(AppMotion.animation(for: .rowRemove, reduceMotion: reduceMotion)) {
            selectedExerciseIds.removeAll { $0 == exercise.id }
        }
    }

    private func moveToTop(_ exercise: PlannedWorkoutExercise) {
        guard let destinationID = selectedExerciseIds.first else { return }
        reorderExercise(exercise.id, relativeTo: destinationID)
    }

    private func moveToBottom(_ exercise: PlannedWorkoutExercise) {
        guard let destinationID = selectedExerciseIds.last else { return }
        reorderExercise(exercise.id, relativeTo: destinationID)
    }

    private func updateGestureDropTarget(sourceID: UUID, location: CGPoint) {
        guard tracksReorderFrames else {
            requestReorderFrameTracking()
            return
        }

        let destination = gestureDestination(at: location, sourceID: sourceID)
        guard gestureDropTarget != destination else { return }

        withAnimation(AppMotion.previewReorderTarget(reduceMotion: reduceMotion)) {
            gestureDropTarget = destination
        }
        if destination != nil {
            AppHaptics.selection()
        }
    }

    private func finishGestureDrop(sourceID: UUID, location: CGPoint) {
        let destination = gestureDestination(at: location, sourceID: sourceID)
        gestureDropTarget = nil
        guard let destination else { return }
        reorderExercise(
            sourceID,
            relativeTo: destination.exerciseID,
            animatesMutation: false
        )
    }

    private func cancelGestureDrop() {
        gestureDropTarget = nil
    }

    private func gestureDestination(
        at location: CGPoint,
        sourceID: UUID
    ) -> WorkoutPreviewExerciseDropTarget? {
        WorkoutPreviewExerciseDropTarget.resolve(
            location: location,
            sourceID: sourceID,
            selectedExerciseIds: selectedExerciseIds,
            rowFrames: exerciseRowFrames
        )
    }

    @discardableResult
    private func reorderExercise(
        _ sourceID: UUID,
        relativeTo destinationID: UUID,
        animatesMutation: Bool = true
    ) -> Bool {
        let reorderedIDs = WorkoutPreviewOrderReducer.move(
            selectedExerciseIds,
            sourceID: sourceID,
            destinationID: destinationID
        )
        guard reorderedIDs != selectedExerciseIds else { return false }

        if appliedWorkoutAdjustment != nil {
            resetCoachAdjustment()
        }

        if animatesMutation {
            withAnimation(AppMotion.previewReorderCommit(reduceMotion: reduceMotion)) {
                selectedExerciseIds = reorderedIDs
            }
        } else {
            selectedExerciseIds = reorderedIDs
        }
        return true
    }

    private func addOptionalExercise() {
        guard
            let optionalExerciseId,
            let exercise = currentRenderSnapshot.exerciseLookup.byID[optionalExerciseId]
        else { return }

        addExercise(exercise, targetSets: 2, minReps: 8, maxReps: 12, notes: "Added for today's workout.")
        self.optionalExerciseId = nil
    }

    private func addExercise(_ exercise: WorkoutPreviewExerciseOption, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        guard !selectedExerciseIds.contains(exercise.id) else { return }
        resetCoachAdjustment()
        withAnimation(AppMotion.animation(for: .rowInsert, reduceMotion: reduceMotion)) {
            selectedExerciseIds.append(exercise.id)
        }
    }

    private func baselineSuggestion(for exercise: PlannedWorkoutExercise) -> TargetSuggestion {
        TargetSuggestion(
            exerciseName: exercise.exerciseNameSnapshot,
            lastBestSetDescription: nil,
            lastBestWeight: nil,
            lastBestReps: nil,
            suggestedWeight: nil,
            suggestedReps: exercise.minReps,
            recommendationType: .baseline,
            reason: "Use the planned rep range and log clean working sets.",
            confidence: 0.45
        )
    }

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: WorkoutPreviewExerciseOption) {
        substitute(exercise, with: alternative, reason: .preferAlternative)
    }

    private func substitute(_ exercise: PlannedWorkoutExercise, with alternative: WorkoutPreviewExerciseOption, reason: ExerciseSubstitutionReason) {
        guard let index = selectedExerciseIds.firstIndex(of: exercise.id) else { return }
        resetCoachAdjustment()
        withAnimation(AppMotion.modeChange(reduceMotion: reduceMotion)) {
            selectedExerciseIds[index] = alternative.id
            substitutionNotesByExerciseId[alternative.id] = substitutionService.substitutionNote(
                originalName: exercise.exerciseNameSnapshot,
                replacementName: alternative.name,
                reason: reason
            )
        }
    }

    private func makeLaunchDraft(
        exercises: [PlannedWorkoutExercise],
        modeLabel: String
    ) -> WorkoutLaunchDraft {
        WorkoutLaunchDraft(
            splitId: split.id,
            splitName: split.name,
            modeLabel: modeLabel,
            exercises: exercises
        )
    }

    private func startWorkout(using draft: WorkoutLaunchDraft) {
        let session = draft.makeSession()
        modelContext.insert(session)
        let navigationKey = "preview.start.\(draft.splitId.uuidString)"

        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: .warm,
            haptic: .medium,
            action: {
                pendingWorkoutSaveID = session.id
                activeWorkoutNavigationKey = navigationKey
                activeSession = session
            }
        ) else {
            modelContext.delete(session)
            return
        }
    }

    private func persistLaunchedWorkoutIfNeeded(_ session: WorkoutSession) {
        guard pendingWorkoutSaveID == session.id else { return }
        pendingWorkoutSaveID = nil

        Task { @MainActor in
            await Task.yield()
            PerformanceTracer.trace(.navigationPersistence) {
                try? modelContext.save()
            }
        }
    }

    private func requestCoachAction(
        _ action: CoachWorkoutAdjustmentAction,
        preparedSnapshot: WorkoutPreviewPreparedSnapshot
    ) {
        if action == .deloadStyleSession {
            PerformanceTracer.mark(.motionTapFeedback, "preview coach deload sheet requested")
            activeCoachSheet = .deloadPlanner
            return
        }

        guard let preview = preparedSnapshot.actionPreviews[action] else { return }
        PerformanceTracer.mark(.motionTapFeedback, "preview coach action sheet requested")
        activeCoachSheet = .actionPreview(preview)
    }

    private func applyCoachAdjustment(_ preview: CoachWorkoutAdjustmentPreview, snapshot: CoachIntelligenceSnapshot) {
        if preview.action == .keepPlan || !preview.hasWorkoutChanges {
            recordCoachAction(preview: preview, outcome: .bypassed, snapshot: snapshot)
            resetCoachAdjustment()
            return
        }

        appliedWorkoutAdjustment = AppliedCoachWorkoutAdjustment(preview: preview)
        recordCoachAction(preview: preview, outcome: .applied, snapshot: snapshot)
    }

    private func resetCoachAdjustment() {
        if let appliedWorkoutAdjustment {
            recordCoachAction(preview: appliedWorkoutAdjustment.preview, outcome: .reset, snapshot: currentRenderSnapshot.intelligence)
        }
        appliedWorkoutAdjustment = nil
    }

    private func recordCoachAction(
        preview: CoachWorkoutAdjustmentPreview,
        outcome: CoachActionHistoryOutcome,
        snapshot: CoachIntelligenceSnapshot,
        saveImmediately: Bool = true
    ) {
        let entry = coachHistoryService.makeEntry(
            preview: preview,
            outcome: outcome,
            snapshot: snapshot,
            splitName: split.name
        )
        modelContext.insert(entry)
        if saveImmediately {
            try? modelContext.save()
        }
    }

    private func saveDeloadBlock(_ plan: ManualDeloadPlan, snapshot: CoachIntelligenceSnapshot) {
        let block = deloadBlockService.makeBlock(
            plan: plan,
            reason: snapshot.fatigueRisk.recommendedAction,
            splitName: split.name
        )
        modelContext.insert(block)
        try? modelContext.save()
    }
}

@MainActor
private final class WorkoutPreviewRoutePresentationState: ObservableObject {
    let initialSnapshot: WorkoutPreviewPreparedSnapshot

    init(preparedRoute: WorkoutPreviewPreparedRoute) {
        initialSnapshot = WorkoutPreviewView.resolveWarmSnapshot(
            for: preparedRoute,
            mode: preparedRoute.initialMode
        )
    }
}

struct WorkoutPreviewRouteView: View {
    @StateObject private var presentationState: WorkoutPreviewRoutePresentationState
    @State private var tracksReorderFrames = false

    let preparedRoute: WorkoutPreviewPreparedRoute
    let onWorkoutFinished: (() -> Void)?

    init(
        preparedRoute: WorkoutPreviewPreparedRoute,
        onWorkoutFinished: (() -> Void)? = nil
    ) {
        self.preparedRoute = preparedRoute
        self.onWorkoutFinished = onWorkoutFinished
        _presentationState = StateObject(
            wrappedValue: WorkoutPreviewRoutePresentationState(preparedRoute: preparedRoute)
        )
    }

    var body: some View {
        WorkoutPreviewView(
            preparedRoute: preparedRoute,
            initialSnapshot: presentationState.initialSnapshot,
            tracksReorderFrames: tracksReorderFrames,
            requestReorderFrameTracking: {
                guard !tracksReorderFrames else { return }
                tracksReorderFrames = true
            },
            onWorkoutFinished: onWorkoutFinished
        )
        .onAppear {
            WorkoutPreviewWarmStartStore.shared.routeDidMount(preparedRoute)
            PerformanceTracer.mark(
                .workoutPreviewRenderSnapshot,
                "route_mounted cache=\(preparedRoute.cacheToken)"
            )

            // Publish every eager row's frame before the first possible user drag.
            // Deferring this until the handle's first onChanged event leaves that
            // gesture without destinations and makes the visible lift a no-op.
            guard !tracksReorderFrames else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                tracksReorderFrames = true
            }
        }
        .onDisappear {
            PerformanceTracer.mark(
                .workoutPreviewRenderSnapshot,
                "route_dismissed cache=\(preparedRoute.cacheToken)"
            )
            WorkoutPreviewWarmStartStore.shared.routeDidDismiss(preparedRoute)
        }
    }

}

private enum CoachWorkoutSheet: Identifiable {
    case actionPreview(CoachWorkoutAdjustmentPreview)
    case deloadPlanner

    var id: String {
        switch self {
        case let .actionPreview(preview):
            return "action-\(preview.id)"
        case .deloadPlanner:
            return "deload-planner"
        }
    }
}

struct WorkoutPreviewSplit: Identifiable, Hashable {
    let id: UUID
    let name: String
    let exercises: [WorkoutSelectableExercise]

    init(id: UUID, name: String, exercises: [WorkoutSelectableExercise]) {
        self.id = id
        self.name = name
        self.exercises = exercises
    }

    init(_ split: TrainingSplit) {
        id = split.id
        name = split.name
        exercises = split.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(WorkoutSelectableExercise.init)
    }
}

struct WorkoutSelectableExercise: Identifiable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let notes: String?

    var exerciseNameSnapshot: String {
        name
    }

    init(_ splitExercise: SplitExercise) {
        id = splitExercise.id
        exerciseId = splitExercise.exerciseId
        name = splitExercise.exerciseNameSnapshot
        targetSets = splitExercise.targetSets
        minReps = splitExercise.minReps
        maxReps = splitExercise.maxReps
        notes = splitExercise.notes
    }

    init(id: UUID, exerciseId: UUID, name: String, targetSets: Int, minReps: Int, maxReps: Int, notes: String?) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.notes = notes
    }
}
