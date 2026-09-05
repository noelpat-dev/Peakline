import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @State private var navigationPath: [StartWorkoutRoute] = []
    @State private var pendingNavigationRoute: StartWorkoutRoute?
    private let initialReadinessSnapshot: WorkoutSleepReadinessSnapshot?
    private let initialReadinessSignature: SleepAnalyticsInputSignature?
    private let initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot?
    private let initialOverallReadinessIsProvisional: Bool
    private let initialDashboardAction: WorkoutDashboardInitialAction?

    init(
        initialReadinessSnapshot: WorkoutSleepReadinessSnapshot? = nil,
        initialReadinessSignature: SleepAnalyticsInputSignature? = nil,
        initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot? = nil,
        initialOverallReadinessIsProvisional: Bool = true,
        initialDashboardAction: WorkoutDashboardInitialAction? = nil
    ) {
        self.initialReadinessSnapshot = initialReadinessSnapshot
        self.initialReadinessSignature = initialReadinessSignature
        self.initialFirstFrameSnapshot = initialFirstFrameSnapshot
        self.initialOverallReadinessIsProvisional = initialOverallReadinessIsProvisional
        self.initialDashboardAction = initialDashboardAction
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            StartWorkoutContentView(
                initialReadinessSnapshot: initialReadinessSnapshot,
                initialReadinessSignature: initialReadinessSignature,
                initialFirstFrameSnapshot: initialFirstFrameSnapshot,
                initialOverallReadinessIsProvisional: initialOverallReadinessIsProvisional,
                initialDashboardAction: initialDashboardAction
            ) { route in
                push(route)
            }
            .navigationDestination(for: StartWorkoutRoute.self) { route in
                destination(for: route)
                    .onAppear {
                        PerformanceTracer.mark(.workoutRouteNavigation, "destination_onAppear route=\(route.analyticsName) path_depth=\(navigationPath.count)")
                        NavigationInteraction.destinationDidAppear(
                            key: "workout.\(route.analyticsName)"
                        )
                        if pendingNavigationRoute == route {
                            pendingNavigationRoute = nil
                            PerformanceTracer.mark(.workoutRouteNavigation, "transition_cleared route=\(route.analyticsName)")
                        }
                    }
            }
        }
        .onChange(of: navigationPath) { _, newPath in
            let topRoute = newPath.last?.analyticsName ?? "none"
            PerformanceTracer.mark(.workoutRouteNavigation, "path_changed depth=\(newPath.count) top=\(topRoute)")
            if let pendingNavigationRoute, !newPath.contains(pendingNavigationRoute) {
                PerformanceTracer.mark(.workoutRouteNavigation, "transition_cleared_missing route=\(pendingNavigationRoute.analyticsName)")
                self.pendingNavigationRoute = nil
            }
        }
    }

    @ViewBuilder
    private func destination(for route: StartWorkoutRoute) -> some View {
        switch route {
        case .coach:
            CoachRouteDestinationView(
                backButtonTitle: "Workout",
                onBack: {
                    pop(route)
                }
            )
        case .templates:
            WorkoutTemplateLibraryView()
        case .library:
            ExerciseLibraryView()
        case let .preview(route):
            WorkoutPreviewRouteView(preparedRoute: route.preparedRoute) {
                navigationPath.removeAll()
                pendingNavigationRoute = nil
            }
        }
    }

    private func push(_ route: StartWorkoutRoute) {
        let topRoute = navigationPath.last?.analyticsName ?? "none"
        let pendingRoute = pendingNavigationRoute?.analyticsName ?? "none"
        PerformanceTracer.mark(.workoutRouteNavigation, "request route=\(route.analyticsName) path_depth=\(navigationPath.count) top=\(topRoute) pending=\(pendingRoute)")

        guard navigationPath.last != route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "skip route=\(route.analyticsName) already_active")
            return
        }

        guard pendingNavigationRoute != route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "skip route=\(route.analyticsName) transition_in_flight")
            return
        }

        let navigationKey = "workout.\(route.analyticsName)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: route.destinationClass,
            haptic: .selection,
            action: {
            pendingNavigationRoute = route
            navigationPath.append(route)
        }) else {
            return
        }
        PerformanceTracer.mark(.workoutRouteNavigation, "appended route=\(route.analyticsName) path_depth=\(navigationPath.count)")
    }

    private func pop(_ route: StartWorkoutRoute) {
        let topRoute = navigationPath.last?.analyticsName ?? "none"
        PerformanceTracer.mark(.workoutRouteNavigation, "pop_request route=\(route.analyticsName) path_depth=\(navigationPath.count) top=\(topRoute)")

        guard navigationPath.last == route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "pop_skip route=\(route.analyticsName) top=\(topRoute)")
            return
        }

        navigationPath.removeLast()
        pendingNavigationRoute = nil
        PerformanceTracer.mark(.workoutRouteNavigation, "pop_complete route=\(route.analyticsName) path_depth=\(navigationPath.count)")
    }
}

enum WorkoutDashboardInitialAction: Equatable {
    case startRecommended
    case previewRecommended
}

/// Keeps dashboard item construction behind the lazy stack's visibility
/// boundary. `FitnessScreen` accepts an already-built `Content` value, so its
/// lazy stack cannot prevent every dashboard card from being constructed while
/// the root tab is mounting.
private struct StartWorkoutLazyScreen<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: appTheme.metrics.screenContentSpacing
            ) {
                content()
            }
            .padding(appTheme.metrics.screenPadding)
            .padding(.bottom, appTheme.metrics.screenBottomPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .submitLabel(.done)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
    }
}

struct WorkoutDashboardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.backgroundPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.textPrimary, in: Capsule())
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: 0.88
            )
    }
}

struct WorkoutDashboardHero: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let splitName: String
    let iconKey: ExerciseIconKey
    let status: CoachBadgeState
    let exerciseCount: Int
    let durationText: String
    let modeText: String
    let onStart: () -> Void
    let onPreview: () -> Void

    var body: some View {
        FitnessCard(style: .hero, padding: appTheme.metrics.spacing18) {
            VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
                Text("TODAY")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.mutedText)
                    .tracking(0.7)

                HStack(alignment: .center, spacing: 14) {
                    ExerciseIconView(
                        iconKey: iconKey,
                        size: 58,
                        tint: appTheme.colors.textPrimary,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(splitName)
                            .font(AppTypography.heroTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                        CoachBadgeView(state: status)
                    }
                }

                if dynamicTypeSize.isAccessibilitySize {
                    CoachBadgeView(state: status)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ViewThatFits(in: .horizontal) {
                    metadataRow
                    metadataStack
                }

                VStack(spacing: appTheme.metrics.spacing10) {
                    Button {
                        onStart()
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutDashboardPrimaryButtonStyle())
                    .accessibilityIdentifier("workout-recommended-start")

                    Button {
                        onPreview()
                    } label: {
                        Label("Preview Workout", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())
                    .accessibilityIdentifier("workout-recommended-preview")
                }
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            metadataItem(
                systemImage: "list.bullet",
                text: exerciseCountText
            )
            metadataDivider
            metadataItem(systemImage: "clock", text: durationText)
            metadataDivider
            metadataItem(systemImage: "figure.strengthtraining.traditional", text: modeText)
        }
        .foregroundStyle(appTheme.colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataStack: some View {
        VStack(alignment: .leading, spacing: appTheme.metrics.spacing8) {
            metadataItem(
                systemImage: "list.bullet",
                text: exerciseCountText
            )
            metadataItem(systemImage: "clock", text: durationText)
            metadataItem(systemImage: "figure.strengthtraining.traditional", text: modeText)
        }
        .foregroundStyle(appTheme.colors.textSecondary)
    }

    private func metadataItem(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(AppTypography.metadataEmphasis)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
    }

    private var exerciseCountText: String {
        exerciseCount > 0
            ? PeaklineText.count(exerciseCount, singular: "exercise")
            : "Plan ready"
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(appTheme.colors.cardBorder)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

struct WorkoutToolsGrid: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onEmptyWorkout: () -> Void
    let onTemplates: () -> Void
    let onCoach: () -> Void
    let onExerciseLibrary: () -> Void

    var body: some View {
        LazyVGrid(columns: toolColumns, spacing: appTheme.metrics.cardSpacing) {
            ForEach(toolItems) { item in
                toolButton(item)
            }
        }
    }

    private var toolColumns: [GridItem] {
        let columnCount: Int
        if dynamicTypeSize.isAccessibilitySize {
            columnCount = 1
        } else if dynamicTypeSize >= .xxLarge {
            columnCount = 2
        } else {
            columnCount = 4
        }

        return Array(
            repeating: GridItem(.flexible(), spacing: appTheme.metrics.cardSpacing),
            count: columnCount
        )
    }

    private var toolItems: [WorkoutToolItem] {
        [
            WorkoutToolItem(title: "Empty Workout", systemImage: "plus", action: onEmptyWorkout),
            WorkoutToolItem(title: "Templates", systemImage: "doc.on.doc", action: onTemplates),
            WorkoutToolItem(title: "Coach", systemImage: "sparkles", action: onCoach),
            WorkoutToolItem(title: "Exercise Library", systemImage: "dumbbell", action: onExerciseLibrary)
        ]
    }

    private func toolButton(_ item: WorkoutToolItem) -> some View {
        Button {
            item.action()
        } label: {
            FitnessCard(style: .compact, padding: appTheme.metrics.spacing10) {
                VStack(spacing: appTheme.metrics.spacing6) {
                    Image(systemName: item.systemImage)
                        .font(AppTypography.rounded(size: 24, weight: .semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)

                    Text(item.title)
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.82)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier(item.id == "Empty Workout" ? "start-empty-workout" : "workout-tool-\(item.id.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

private struct WorkoutToolItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let action: () -> Void

    init(title: String, systemImage: String, action: @escaping () -> Void) {
        id = title
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

struct StartWorkoutContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @Query
    private var activeSplits: [TrainingSplit]

    @Query
    private var unfinishedSessions: [WorkoutSession]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @State private var activeSession: WorkoutSession?
    @State private var activeSessionNavigationKey: String?
    @State private var pendingNewSessionSaveID: UUID?
    @State private var pendingDiscardSession: WorkoutSession?
    @State private var fallbackRoute: StartWorkoutRoute?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = WorkoutSleepReadinessSnapshot.empty
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var dashboardSnapshot: StartWorkoutDashboardSnapshot?
    @State private var recentSessionSnapshot: StartWorkoutRecentSessionSnapshot?
    @State private var splitCardSnapshots: [StartWorkoutSplitCardSnapshot] = []
    @State private var lastDashboardSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?
    @State private var isWorkoutCompletionPresentationActive = false
    @State private var isDashboardVisible = false
    @State private var isSleepReadinessObservationEnabled = false
    @State private var hasSeededDashboardSnapshot = false
    @State private var isOverallReadinessProvisional = true
    @State private var showsSupportingDashboardItems = false
    @State private var supportingDashboardRevealTask: Task<Void, Never>?
    @State private var didConsumeInitialDashboardAction = false
    @ObservedObject private var overallReadinessSnapshotStore = OverallReadinessSnapshotStore.shared

    private let openRoute: ((StartWorkoutRoute) -> Void)?
    private let modePlanner = WorkoutModePlanner()
    private let summaryBuilder = SessionSummaryBuilder()
    private let reuseBuilder = WorkoutReuseBuilder()
    private let rotationService = TrainingRotationService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let dashboardWarmStartStore = WorkoutDashboardWarmStartStore.shared
    private let initialDashboardAction: WorkoutDashboardInitialAction?

    init(
        initialReadinessSnapshot: WorkoutSleepReadinessSnapshot? = nil,
        initialReadinessSignature: SleepAnalyticsInputSignature? = nil,
        initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot? = nil,
        initialOverallReadinessIsProvisional: Bool = true,
        initialDashboardAction: WorkoutDashboardInitialAction? = nil,
        openRoute: ((StartWorkoutRoute) -> Void)? = nil
    ) {
        self.openRoute = openRoute
        self.initialDashboardAction = initialDashboardAction
        let usableInitialSnapshot: WorkoutStartFirstFrameSnapshot?
        if let initialFirstFrameSnapshot,
           initialFirstFrameSnapshot.workoutRevision == WorkoutWarmStartInvalidation.shared.revision {
            usableInitialSnapshot = initialFirstFrameSnapshot
        } else {
            usableInitialSnapshot = nil
        }
        _sleepReadinessSnapshot = State(
            initialValue: initialReadinessSnapshot ?? .empty
        )
        _lastSleepReadinessSignature = State(
            initialValue: initialReadinessSignature
        )
        _dashboardSnapshot = State(
            initialValue: usableInitialSnapshot?.dashboard
        )
        _recentSessionSnapshot = State(
            initialValue: usableInitialSnapshot?.recentSession
        )
        _splitCardSnapshots = State(
            initialValue: usableInitialSnapshot?.splitCards ?? []
        )
        _lastDashboardSignature = State(
            initialValue: usableInitialSnapshot?.dashboardSignature
        )
        _hasSeededDashboardSnapshot = State(
            initialValue: usableInitialSnapshot != nil
        )
        _isOverallReadinessProvisional = State(
            initialValue: initialOverallReadinessIsProvisional
        )
        _activeSplits = Query(Self.activeSplitsDescriptor)
        _unfinishedSessions = Query(Self.unfinishedSessionsDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var unfinishedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { !$0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Readiness uses the newest 45 sessions; avoid fetching an extra cold
        // page into the root tab before the deferred sleep refresh runs.
        descriptor.fetchLimit = 45
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private var currentDashboardSnapshot: StartWorkoutDashboardSnapshot {
        if let dashboardSnapshot {
            return presentationSafeDashboardSnapshot(dashboardSnapshot)
        }

        if warmDashboardSourceIsCurrent,
           let warmTrainingCall = dashboardWarmStartStore.trainingCall,
           let splitName = warmTrainingCall.recommendedSplitName,
           let split = activeSplits.first(where: { $0.name == splitName }) {
            let presentationCall = warmTrainingCall.neutralizedForProvisionalReadiness(
                if: currentOverallReadinessIsProvisional
            )
            return StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: StartWorkoutRecommendedSplitSnapshot(
                    id: split.id,
                    name: split.name,
                    mode: presentationCall.recommendedMode,
                    exerciseCount: currentSplitCardSnapshots.first(where: { $0.splitId == split.id })?.exerciseCount ?? split.exercises.count,
                    estimatedDurationText: currentSplitCardSnapshots.first(where: { $0.splitId == split.id })?.estimatedDurationText ?? "Plan ready"
                )
            )
        }

        return .placeholder
    }

    private func presentationSafeDashboardSnapshot(
        _ snapshot: StartWorkoutDashboardSnapshot
    ) -> StartWorkoutDashboardSnapshot {
        let safeCall = snapshot.trainingCall.neutralizedForProvisionalReadiness(
            if: currentOverallReadinessIsProvisional
        )
        guard let recommendedSplit = snapshot.recommendedSplit,
              recommendedSplit.mode != safeCall.recommendedMode else {
            return StartWorkoutDashboardSnapshot(
                trainingCall: safeCall,
                recommendedSplit: snapshot.recommendedSplit
            )
        }

        return StartWorkoutDashboardSnapshot(
            trainingCall: safeCall,
            recommendedSplit: StartWorkoutRecommendedSplitSnapshot(
                id: recommendedSplit.id,
                name: recommendedSplit.name,
                mode: safeCall.recommendedMode
            )
        )
    }

    private var currentRecentSessionSnapshot: StartWorkoutRecentSessionSnapshot? {
        if hasSeededDashboardSnapshot {
            return recentSessionSnapshot
        }

        return recentSessionSnapshot ?? completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
    }

    private var currentSplitCardSnapshots: [StartWorkoutSplitCardSnapshot] {
        if hasSeededDashboardSnapshot || !splitCardSnapshots.isEmpty {
            return splitCardSnapshots
        }

        return displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
    }

    private var displayedSplits: [TrainingSplit] {
        rotationService.orderedActiveSplits(activeSplits)
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: completedSessions,
            settings: sleepSettings,
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var sleepReadinessSignatureForObservation: SleepAnalyticsInputSignature? {
        guard isSleepReadinessObservationEnabled,
              !isWorkoutCompletionPresentationActive,
              isDashboardVisible else {
            return nil
        }
        return currentSleepReadinessSignature
    }

    private var currentDashboardSignature: String {
        WorkoutDashboardInputSignature(
            splits: activeSplits.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    activeRotationIndex: $0.activeRotationIndex,
                    updatedAt: $0.updatedAt
                )
            },
            sessions: completedSessions.prefix(20).map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    endedAt: $0.endedAt,
                    durationSeconds: $0.durationSeconds,
                    perceivedDifficulty: $0.perceivedDifficulty
                )
            },
            workoutRevision: workoutWarmStartInvalidation.revision
        ).value
    }

    private var warmDashboardSourceIsCurrent: Bool {
        guard let sourceSignature = dashboardWarmStartStore.sourceSignature else { return false }
        return sourceSignature.hasPrefix("revision:\(workoutWarmStartInvalidation.revision)|")
    }

    private var dashboardSignatureForObservation: String? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentDashboardSignature
    }

    private var sleepSummary: WorkoutSleepReadinessSnapshot? {
        sleepReadinessSnapshot.hasPrimarySession ? sleepReadinessSnapshot : nil
    }

    private var adaptiveSleepRecommendation: AdaptiveTrainingRecommendation? {
        guard !currentOverallReadinessIsProvisional else { return nil }
        guard sleepSettings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled else { return nil }
        return sleepReadinessSnapshot.adaptiveRecommendation
    }

    private var provisionalSleepSupport: (title: String, suggestion: String)? {
        guard currentOverallReadinessIsProvisional, sleepSummary != nil else { return nil }
        return (
            "Sleep context",
            "Sleep is one supportive signal. Training guidance waits until daily readiness has enough evidence."
        )
    }

    private var currentOverallReadinessIsProvisional: Bool {
        let snapshot = overallReadinessSnapshotStore.snapshot
        return snapshot.revision > 0 ? snapshot.isProvisional : isOverallReadinessProvisional
    }

    private func preWorkoutSleepHint(
        for summary: WorkoutSleepReadinessSnapshot?
    ) -> (title: String, suggestion: String)? {
        guard let summary, let score = summary.sleepScore else { return nil }

        switch summary.recoveryState {
        case .high:
            return ("Sleep recovery: High", "Normal progression is suitable if warm-ups feel good.")
        case .good:
            return ("Sleep recovery: Good", "Continue with the planned session and adjust from your first working sets.")
        case .moderate:
            return ("Sleep recovery: Moderate", "Keep top sets controlled today.")
        case .low:
            return ("Sleep recovery: Low", "Avoid extra failure sets and reduce accessory volume if needed.")
        case .veryLow:
            return ("Sleep recovery: Very low", "A lighter session or rest may be more productive today.")
        case .unknown:
            return score > 0 ? ("Sleep recovery", "Use warm-ups to decide how hard to push today.") : nil
        }
    }

    var body: some View {
        workoutDashboard
    }

    private var workoutDashboard: some View {
        StartWorkoutLazyScreen {
            if let unfinishedSession = unfinishedSessions.first {
                activeWorkoutCard(unfinishedSession)
            } else if let recommendedSplit = currentDashboardSnapshot.recommendedSplit {
                recommendedWorkoutCard(recommendedSplit)
            }

            if showsSupportingDashboardItems {
                DashboardSection(title: "Tools") {
                    WorkoutToolsGrid(
                        onEmptyWorkout: {
                            openSession(createEmptyWorkout(), requiresSave: true)
                        },
                        onTemplates: {
                            navigate(to: .templates)
                        },
                        onCoach: {
                            navigate(to: .coach)
                        },
                        onExerciseLibrary: {
                            navigate(to: .library)
                        }
                    )
                }

                DashboardSection(title: "Your Workouts") {
                    ForEach(currentSplitCardSnapshots) { snapshot in
                        splitStartCard(snapshot)
                    }
                }

                if let recentSnapshot = currentRecentSessionSnapshot {
                    DashboardSection(title: "Recent Workout") {
                        recentSessionCard(recentSnapshot)
                    }
                }

                DashboardSection(title: "Readiness") {
                    workoutReadinessContextRow()
                }
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workout-screen")
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session) {
                activeSession = nil
            }
            .onAppear {
                if let activeSessionNavigationKey {
                    NavigationInteraction.destinationDidAppear(
                        key: activeSessionNavigationKey
                    )
                    self.activeSessionNavigationKey = nil
                }
                persistNewSessionIfNeeded(session)
            }
        }
        .navigationDestination(item: $fallbackRoute) { route in
            Group {
                switch route {
                case .coach:
                    CoachRouteDestinationView(
                        backButtonTitle: "Workout",
                        onBack: {
                            fallbackRoute = nil
                        }
                    )
                case .templates:
                    WorkoutTemplateLibraryView()
                case .library:
                    ExerciseLibraryView()
                case let .preview(route):
                    WorkoutPreviewRouteView(preparedRoute: route.preparedRoute) {
                        fallbackRoute = nil
                    }
                }
            }
            .onAppear {
                NavigationInteraction.destinationDidAppear(
                    key: "workout.fallback.\(route.analyticsName)"
                )
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
            isDashboardVisible = true
            if !showsSupportingDashboardItems {
                supportingDashboardRevealTask?.cancel()
                supportingDashboardRevealTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    showsSupportingDashboardItems = true
                    supportingDashboardRevealTask = nil
                }
            }
            let readinessSnapshot = overallReadinessSnapshotStore.snapshot
            if readinessSnapshot.revision > 0 {
                isOverallReadinessProvisional = readinessSnapshot.isProvisional
            }
            sleepSettings = sleepSettingsStore.load()
            restoreWarmedDashboardIfNeeded()
            let preparedMode = dashboardSnapshot?.recommendedSplit?.mode
            let presentationMode = dashboardSnapshot?.trainingCall.neutralizedForProvisionalReadiness(
                if: currentOverallReadinessIsProvisional
            ).recommendedMode
            scheduleDashboardSnapshotRefresh(
                force: dashboardSnapshot == nil || preparedMode != presentationMode
            )
            if lastSleepReadinessSignature == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    refreshSleepReadiness()
                    isSleepReadinessObservationEnabled = true
                }
            } else {
                Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    isSleepReadinessObservationEnabled = true
                }
            }
            consumeInitialDashboardActionIfNeeded()
        }
        .onChange(of: dashboardSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            scheduleDashboardSnapshotRefresh()
        }
        .onChange(of: sleepReadinessSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            refreshSleepReadiness()
        }
        .onChange(of: overallReadinessSnapshotStore.snapshot) { _, snapshot in
            guard snapshot.revision > 0 else { return }
            isOverallReadinessProvisional = snapshot.isProvisional
            scheduleDashboardSnapshotRefresh(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
            isWorkoutCompletionPresentationActive = true
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = nil
            PerformanceTracer.mark(.workoutLoggerFinish, "workout_dashboard_refresh_suspended")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
            isWorkoutCompletionPresentationActive = false
            PerformanceTracer.mark(.workoutLoggerFinish, "workout_dashboard_refresh_resumed")
        }
        .onDisappear {
            isDashboardVisible = false
            supportingDashboardRevealTask?.cancel()
            supportingDashboardRevealTask = nil
            isSleepReadinessObservationEnabled = false
            dashboardRefreshTask?.cancel()
        }
    }

    private func consumeInitialDashboardActionIfNeeded() {
        guard let initialDashboardAction,
              !didConsumeInitialDashboardAction else { return }

        Task { @MainActor in
            await Task.yield()
            guard isDashboardVisible,
                  unfinishedSessions.isEmpty,
                  let recommendedSplit = currentDashboardSnapshot.recommendedSplit else { return }
            didConsumeInitialDashboardAction = true

            switch initialDashboardAction {
            case .startRecommended:
                startRecommendedWorkout(recommendedSplit)
            case .previewRecommended:
                guard let liveSplit = activeSplits.first(where: { $0.id == recommendedSplit.id }) else { return }
                preview(liveSplit, mode: currentDashboardSnapshot.trainingCall.recommendedMode)
            }
        }
    }

    private func scheduleDashboardSnapshotRefresh(force: Bool = false) {
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
        let signature = currentDashboardSignature
        guard force || signature != lastDashboardSignature else { return }

        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, !isWorkoutCompletionPresentationActive else { return }
            await refreshDashboardSnapshot(signature: signature)
        }
    }

    private func recommendedSplitSnapshot(
        for split: TrainingSplit,
        mode: WorkoutMode
    ) -> StartWorkoutRecommendedSplitSnapshot {
        let prepared = WorkoutPreviewWarmStartStore.shared.snapshot(
            for: WorkoutPreviewSplit(split),
            mode: mode
        )
        return StartWorkoutRecommendedSplitSnapshot(
            id: split.id,
            name: split.name,
            mode: mode,
            exerciseCount: prepared?.plannedExercises.count ?? split.exercises.count,
            estimatedDurationText: prepared.map {
                "\($0.estimatedDuration.lowerBound)–\($0.estimatedDuration.upperBound) min"
            } ?? estimatedDurationText(for: split)
        )
    }

    private func refreshDashboardSnapshot(signature: String) async {
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
        let orderedActiveSplits = rotationService.orderedActiveSplits(activeSplits)
        let activeSnapshots = orderedActiveSplits.map(TrainingSplitSnapshot.init)
        let completedSnapshots = completedSessions.prefix(20).map(WorkoutAnalyticsSession.init)
        let call = await Task.detached(priority: .userInitiated) {
            let summary = CoachRecommendationEngine().makeSummary(
                activeSplits: activeSnapshots,
                completedSessions: completedSnapshots
            )
            return TrainingCallSnapshotBuilder().make(
                decision: summary.trainingDecision,
                activeSplits: activeSnapshots,
                completedSessions: completedSnapshots
            )
        }.value
        guard !Task.isCancelled,
              isDashboardVisible,
              !isWorkoutCompletionPresentationActive,
              signature == currentDashboardSignature else { return }

        let presentationCall = call.neutralizedForProvisionalReadiness(
            if: currentOverallReadinessIsProvisional
        )
        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: activeSplits.first {
                    $0.name == presentationCall.recommendedSplitName
                }.map { recommendedSplitSnapshot(for: $0, mode: presentationCall.recommendedMode) }
            )
            recentSessionSnapshot = makeRecentSessionSnapshot()
            splitCardSnapshots = displayedSplits.map(makeSplitCardSnapshot)
            lastDashboardSignature = signature
            hasSeededDashboardSnapshot = true
            consumeInitialDashboardActionIfNeeded()
        }
    }

    private func makeRecentSessionSnapshot() -> StartWorkoutRecentSessionSnapshot? {
        guard let session = completedSessions.first else { return nil }

        let summary = summaryBuilder.build(from: session, completedSessions: completedSessions, activeSplits: activeSplits)
        return StartWorkoutRecentSessionSnapshot(
            sessionId: session.id,
            splitName: session.splitNameSnapshot,
            dateText: session.date.formatted(date: .abbreviated, time: .omitted),
            durationText: summary.durationText,
            ratingText: summary.ratingText ?? "-",
            highlightText: summary.bestSetImprovements.first ?? summary.takeaway,
            badgeState: summary.bestSetImprovements.isEmpty ? .ready : .pr
        )
    }

    private func makeSplitCardSnapshot(_ split: TrainingSplit) -> StartWorkoutSplitCardSnapshot {
        let preparedFullSnapshot = WorkoutPreviewWarmStartStore.shared.snapshot(
            for: WorkoutPreviewSplit(split),
            mode: .full
        )
        return StartWorkoutSplitCardSnapshot(
            splitId: split.id,
            splitName: split.name,
            lastTrainedText: lastTrainedText(for: split),
            estimatedDurationText: preparedFullSnapshot.map {
                "\($0.estimatedDuration.lowerBound)–\($0.estimatedDuration.upperBound) min"
            } ?? estimatedDurationText(for: split),
            exerciseCount: split.exercises.count,
            plannedExerciseCount: preparedFullSnapshot?.plannedExercises.count,
            badgeState: badgeState(for: split)
        )
    }

    private func refreshSleepReadiness(force: Bool = false) {
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
        let signature = currentSleepReadinessSignature
        guard force || signature != lastSleepReadinessSignature else { return }

        let nextSnapshot = PerformanceTracer.trace(.workoutStartSleepReadiness) {
            sleepReadinessStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: completedSessions,
                settings: sleepSettings,
                workoutRevision: workoutWarmStartInvalidation.revision,
                force: force
            )
        }
        sleepReadinessSnapshot = WorkoutSleepReadinessSnapshot(nextSnapshot)
        lastSleepReadinessSignature = signature
    }

    private func restoreWarmedDashboardIfNeeded() {
        guard !hasSeededDashboardSnapshot,
              dashboardSnapshot == nil,
              warmDashboardSourceIsCurrent,
              let trainingCall = dashboardWarmStartStore.trainingCall else { return }

        let presentationCall = trainingCall.neutralizedForProvisionalReadiness(
            if: currentOverallReadinessIsProvisional
        )

        // Startup already prepared the recommendation. Keep the first Workout
        // frame value-only and do not compete with an immediately requested
        // Preview push by recomputing the same dashboard relationships.
        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: activeSplits.first {
                    $0.name == presentationCall.recommendedSplitName
                }.map { recommendedSplitSnapshot(for: $0, mode: presentationCall.recommendedMode) }
            )
            recentSessionSnapshot = completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
            splitCardSnapshots = displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
            lastDashboardSignature = currentDashboardSignature
            hasSeededDashboardSnapshot = true
            consumeInitialDashboardActionIfNeeded()
        }
    }

    private func activeWorkoutCard(_ session: WorkoutSession) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: session.splitNameSnapshot),
                        size: 46,
                        tint: appTheme.colors.textPrimary,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Workout")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(session.splitNameSnapshot)
                            .font(AppTypography.largeMetric)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Label("Elapsed", systemImage: "timer")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                        Text(activeElapsedText(for: session))
                            .font(AppTypography.largeMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                    }
                }

                Text(resumeSummary(for: session))
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.mutedText)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        resumeButton(session)
                        discardButton(session)
                    }

                    VStack(spacing: 10) {
                        resumeButton(session)
                        discardButton(session)
                    }
                }
            }
        }
    }

    private func resumeButton(_ session: WorkoutSession) -> some View {
        Button {
            openSession(session)
        } label: {
            Label("Resume", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorkoutDashboardPrimaryButtonStyle())
        .accessibilityIdentifier("workout-active-resume")
    }

    private func discardButton(_ session: WorkoutSession) -> some View {
        Button(role: .destructive) {
            pendingDiscardSession = session
        } label: {
            Label("Discard", systemImage: "xmark.circle")
                .foregroundStyle(appTheme.colors.textDanger)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeutralFitnessButtonStyle())
        .accessibilityIdentifier("workout-active-discard")
    }

    private func recommendedWorkoutCard(_ split: StartWorkoutRecommendedSplitSnapshot) -> some View {
        WorkoutDashboardHero(
            splitName: split.name,
            iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
            status: recommendedBadgeState,
            exerciseCount: split.exerciseCount,
            durationText: split.estimatedDurationText,
            modeText: currentDashboardSnapshot.trainingCall.recommendedMode.displayName,
            onStart: {
                startRecommendedWorkout(split)
            },
            onPreview: {
                guard let liveSplit = activeSplits.first(where: { $0.id == split.id }) else { return }
                preview(liveSplit, mode: currentDashboardSnapshot.trainingCall.recommendedMode)
            }
        )
    }

    private var recommendedBadgeState: CoachBadgeState {
        if currentOverallReadinessIsProvisional {
            return .provisional
        }

        if currentDashboardSnapshot.trainingCall.recommendedMode == .recovery {
            return .recovery
        }

        switch currentDashboardSnapshot.trainingCall.action {
        case .recover:
            return .recovery
        case .push:
            return .ready
        case .repeatTarget:
            return .repeatTarget
        case .rebalance, .buildBaseline:
            return .baseline
        }
    }

    private func workoutReadinessContextRow() -> some View {
        let recommendation = adaptiveSleepRecommendation
        let hint = !currentOverallReadinessIsProvisional ? preWorkoutSleepHint(for: sleepSummary) : nil
        let support = provisionalSleepSupport
        let title = recommendation?.title
            ?? hint?.title
            ?? (currentOverallReadinessIsProvisional ? "Provisional guidance" : "Coach context")
        let message = PeaklineText.joinedMetadata([
            currentDashboardSnapshot.trainingCall.reason,
            recommendation?.message ?? hint?.suggestion ?? support?.suggestion ?? ""
        ])
        let tint = recommendation.map { recoveryTint(for: $0) } ?? appTheme.colors.textSecondary
        let icon = recommendation.map { recoveryIcon(for: $0) }
            ?? ((hint != nil || support != nil) ? "moon.stars.fill" : "checkmark.seal.fill")

        return FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(
                    systemImage: icon,
                    size: 40,
                    tint: tint,
                    background: tint.opacity(0.14)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(PeaklineText.joinedMetadata([
                        title,
                        currentDashboardSnapshot.trainingCall.confidence.displayName
                    ]))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(message)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = recommendation?.suggestedActions.first {
                        Text(action.displayName)
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(tint)
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recoveryTint(for recommendation: AdaptiveTrainingRecommendation) -> Color {
        if requestsMissingSleep(recommendation) {
            return appTheme.colors.accent
        }

        switch recommendation.level {
        case .push, .normal:
            return appTheme.colors.success
        case .moderate:
            return appTheme.colors.accent
        case .light, .recovery:
            return appTheme.colors.warning
        case .rest:
            return appTheme.colors.danger
        }
    }

    private func recoveryIcon(for recommendation: AdaptiveTrainingRecommendation) -> String {
        if requestsMissingSleep(recommendation) {
            return "moon.stars.fill"
        }

        switch recommendation.level {
        case .push:
            return "bolt.fill"
        case .normal:
            return "checkmark.seal.fill"
        case .moderate:
            return "dial.medium.fill"
        case .light:
            return "arrow.down.forward.circle.fill"
        case .recovery:
            return "figure.cooldown"
        case .rest:
            return "moon.fill"
        }
    }

    private func requestsMissingSleep(_ recommendation: AdaptiveTrainingRecommendation) -> Bool {
        recommendation.title.localizedCaseInsensitiveContains("sleep")
            && recommendation.title.localizedCaseInsensitiveContains("add")
    }

    private func splitStartCard(_ snapshot: StartWorkoutSplitCardSnapshot) -> some View {
        Button {
            guard let split = activeSplits.first(where: { $0.id == snapshot.splitId }) else { return }
            preview(split)
        } label: {
            SplitCardView(
                splitName: snapshot.splitName,
                lastTrainedText: snapshot.lastTrainedText,
                estimatedDurationText: snapshot.estimatedDurationText,
                exerciseCount: snapshot.plannedExerciseCount ?? snapshot.exerciseCount,
                badgeState: snapshot.splitName == currentDashboardSnapshot.recommendedSplit?.name
                    ? recommendedBadgeState : snapshot.badgeState,
                actionTitle: nil,
                action: nil,
                iconTint: appTheme.colors.textPrimary
            )
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityIdentifier("start-split-\(snapshot.splitName)")
    }

    private func preview(_ split: TrainingSplit, mode: WorkoutMode = .full) {
        openPreview(WorkoutPreviewSplit(split), mode: mode)
    }

    private func startRecommendedWorkout(_ snapshot: StartWorkoutRecommendedSplitSnapshot) {
        guard let split = activeSplits.first(where: { $0.id == snapshot.id }) else { return }

        let mode = currentDashboardSnapshot.trainingCall.recommendedMode
        let previewSplit = WorkoutPreviewSplit(split)
        let warmStartStore = WorkoutPreviewWarmStartStore.shared
        let preparedSnapshot = warmStartStore.snapshot(for: previewSplit, mode: mode)
            ?? warmStartStore.snapshot(
                for: warmStartStore.prepareRoute(for: previewSplit, initialMode: mode),
                mode: mode
            )
        let plannedExercises = preparedSnapshot?.plannedExercises
            ?? modePlanner.plannedExercises(
                from: previewSplit.exercises,
                mode: mode
            )
        let draft = WorkoutLaunchDraft(
            splitId: split.id,
            splitName: split.name,
            modeLabel: mode.displayName,
            exercises: plannedExercises
        )
        let session = draft.makeSession()
        modelContext.insert(session)
        openSession(session, requiresSave: true)
    }

    private func recentSessionCard(_ snapshot: StartWorkoutRecentSessionSnapshot) -> some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .center, spacing: 12) {
                ExerciseIconView(
                    iconKey: snapshot.iconKey,
                    size: 44,
                    tint: appTheme.colors.textPrimary,
                    showBackground: true,
                    isDecorative: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.splitName)
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(PeaklineText.joinedMetadata([
                        snapshot.dateText,
                        snapshot.durationText
                    ]))
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    guard let session = completedSessions.first(where: { $0.id == snapshot.sessionId }) else { return }
                    openPreview(reuseBuilder.previewSplit(from: session))
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                }
                .buttonStyle(NeutralFitnessButtonStyle())
                .accessibilityLabel("Repeat Last Workout")
                .accessibilityHint(snapshot.highlightText)
                .disabled(completedSessions.first { $0.id == snapshot.sessionId } == nil)
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
        return "\(duration.lowerBound)–\(duration.upperBound) min"
    }

    private func badgeState(for split: TrainingSplit) -> CoachBadgeState {
        guard let recommendedName = currentDashboardSnapshot.trainingCall.recommendedSplitName else { return .baseline }
        return recommendedName == split.name ? recommendedBadgeState : .repeatTarget
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
        return PeaklineText.joinedMetadata([
            "Started \(started)",
            PeaklineText.count(completedSets, singular: "completed set")
        ])
    }

    private func createEmptyWorkout() -> WorkoutSession {
        let startDate = Date()
        let session = WorkoutSession(date: startDate, startedAt: startDate)
        modelContext.insert(session)
        return session
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func navigate(to route: StartWorkoutRoute) {
        if let openRoute {
            suspendDashboardRefreshForNavigation()
            PerformanceTracer.mark(.workoutRouteNavigation, "delegate_request route=\(route.analyticsName)")
            openRoute(route)
        } else {
            let activeRoute = fallbackRoute?.analyticsName ?? "none"
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_request route=\(route.analyticsName) active=\(activeRoute)")
            guard fallbackRoute != route else {
                PerformanceTracer.mark(.workoutRouteNavigation, "skip fallback route=\(route.analyticsName) already_active")
                return
            }

            let navigationKey = "workout.fallback.\(route.analyticsName)"
            guard NavigationInteraction.perform(
                key: navigationKey,
                destinationClass: route.destinationClass,
                haptic: .selection,
                action: {
                suspendDashboardRefreshForNavigation()
                fallbackRoute = route
            }) else {
                return
            }
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_set route=\(route.analyticsName)")
        }
    }

    private func openSession(
        _ session: WorkoutSession,
        requiresSave: Bool = false
    ) {
        let navigationKey = requiresSave
            ? "workout.session.new"
            : "workout.session.\(session.id.uuidString)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: .warm,
            haptic: .medium,
            action: {
                suspendDashboardRefreshForNavigation()
                if requiresSave {
                    pendingNewSessionSaveID = session.id
                }
                activeSessionNavigationKey = navigationKey
                activeSession = session
            }
        ) else {
            if requiresSave {
                modelContext.delete(session)
            }
            return
        }
    }

    private func persistNewSessionIfNeeded(_ session: WorkoutSession) {
        guard pendingNewSessionSaveID == session.id else { return }
        pendingNewSessionSaveID = nil

        Task { @MainActor in
            await Task.yield()
            PerformanceTracer.trace(.navigationPersistence) {
                try? modelContext.save()
            }
        }
    }

    private func openPreview(_ preview: WorkoutPreviewSplit, mode: WorkoutMode = .full) {
        PerformanceTracer.mark(.previewRouteTap, "source=workout split=\(preview.name) mode=\(mode.rawValue)")
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation request source=workout split=\(preview.id.uuidString)")
        navigate(to: .preview(StartWorkoutPreviewRoute(split: preview, mode: mode)))
    }

    private func suspendDashboardRefreshForNavigation() {
        isDashboardVisible = false
        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = nil
    }
}

struct StartWorkoutPreviewRoute: Hashable {
    let preparedRoute: WorkoutPreviewPreparedRoute

    var split: WorkoutPreviewSplit { preparedRoute.split }
    var mode: WorkoutMode { preparedRoute.initialMode }

    @MainActor
    init(split: WorkoutPreviewSplit, mode: WorkoutMode) {
        preparedRoute = WorkoutPreviewWarmStartStore.shared.prepareRoute(
            for: split,
            initialMode: mode
        )
    }

    static func == (lhs: StartWorkoutPreviewRoute, rhs: StartWorkoutPreviewRoute) -> Bool {
        lhs.preparedRoute == rhs.preparedRoute
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(preparedRoute)
    }
}

enum StartWorkoutRoute: Hashable, Identifiable {
    case coach
    case templates
    case library
    case preview(StartWorkoutPreviewRoute)

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .coach:
            return "coach"
        case .templates:
            return "templates"
        case .library:
            return "library"
        case let .preview(route):
            return "preview-\(route.split.id.uuidString)-\(route.mode.rawValue)"
        }
    }

    var destinationClass: NavigationDestinationClass {
        switch self {
        case .coach:
            return .warm
        case .templates, .library, .preview:
            return .deep
        }
    }
}

struct WorkoutDashboardInputSignature: Sendable, Equatable {
    struct Split: Sendable, Equatable {
        let id: UUID
        let name: String
        let activeRotationIndex: Int?
        let updatedAt: Date
    }

    struct Session: Sendable, Equatable {
        let id: UUID
        let date: Date
        let endedAt: Date?
        let durationSeconds: Int?
        let perceivedDifficulty: Int?
    }

    let splits: [Split]
    let sessions: [Session]
    let workoutRevision: Int

    init(
        splits: [Split],
        sessions: [Session],
        workoutRevision: Int
    ) {
        self.splits = splits
        self.sessions = sessions
        self.workoutRevision = workoutRevision
    }

    var value: String {
        [
            "revision:\(workoutRevision)",
            splits.map { split in
                "\(split.id.uuidString):\(split.name):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|"),
            sessions.map { session in
                "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.perceivedDifficulty ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }
}

struct WorkoutStartFirstFrameSnapshot: Sendable {
    let dashboard: StartWorkoutDashboardSnapshot
    let recentSession: StartWorkoutRecentSessionSnapshot?
    let splitCards: [StartWorkoutSplitCardSnapshot]
    let dashboardSignature: String
    let workoutRevision: Int

    static func make(
        trainingCall: TrainingCallSnapshot,
        activeSplits: [TrainingSplitSnapshot],
        historyWorkouts: [HistoryWorkoutSnapshot],
        previewWarmSnapshots: [WorkoutPreviewWarmSnapshot],
        dashboardSignature: String,
        workoutRevision: Int
    ) -> WorkoutStartFirstFrameSnapshot {
        let splitCards = activeSplits.map { split in
            let preparedFullWorkout = previewWarmSnapshots.first {
                $0.splitID == split.id && $0.mode == .full
            }
            let estimatedDurationText = preparedFullWorkout.map {
                "\($0.estimatedDuration.lowerBound)–\($0.estimatedDuration.upperBound) min"
            } ?? "Plan ready"
            let lastTrainedText = historyWorkouts.first {
                baseSplitName($0.splitName) == split.name
            }.map {
                "Last trained \($0.date.formatted(date: .abbreviated, time: .omitted))"
            } ?? "No history yet"
            let badgeState: CoachBadgeState
            if let recommendedSplitName = trainingCall.recommendedSplitName {
                badgeState = recommendedSplitName == split.name ? .ready : .repeatTarget
            } else {
                badgeState = .baseline
            }

            return StartWorkoutSplitCardSnapshot(
                splitId: split.id,
                splitName: split.name,
                lastTrainedText: lastTrainedText,
                estimatedDurationText: estimatedDurationText,
                exerciseCount: split.exercises.count,
                plannedExerciseCount: preparedFullWorkout?.plannedExercises.count,
                badgeState: badgeState
            )
        }

        return WorkoutStartFirstFrameSnapshot(
            dashboard: StartWorkoutDashboardSnapshot(
                trainingCall: trainingCall,
                recommendedSplit: activeSplits.first {
                    $0.name == trainingCall.recommendedSplitName
                }.map { split in
                    let prepared = previewWarmSnapshots.first {
                        $0.splitID == split.id && $0.mode == trainingCall.recommendedMode
                    }
                    return StartWorkoutRecommendedSplitSnapshot(
                        id: split.id,
                        name: split.name,
                        mode: trainingCall.recommendedMode,
                        exerciseCount: prepared?.plannedExercises.count ?? split.exercises.count,
                        estimatedDurationText: prepared.map {
                            "\($0.estimatedDuration.lowerBound)–\($0.estimatedDuration.upperBound) min"
                        } ?? "Plan ready"
                    )
                }
            ),
            recentSession: historyWorkouts.first.map(StartWorkoutRecentSessionSnapshot.placeholder),
            splitCards: splitCards,
            dashboardSignature: dashboardSignature,
            workoutRevision: workoutRevision
        )
    }

    private static func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

struct StartWorkoutRecommendedSplitSnapshot: Sendable {
    let id: UUID
    let name: String
    let mode: WorkoutMode
    let exerciseCount: Int
    let estimatedDurationText: String

    init(
        id: UUID,
        name: String,
        mode: WorkoutMode = .full,
        exerciseCount: Int = 0,
        estimatedDurationText: String = "Plan ready"
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.exerciseCount = exerciseCount
        self.estimatedDurationText = estimatedDurationText
    }
}

struct StartWorkoutDashboardSnapshot: Sendable {
    let trainingCall: TrainingCallSnapshot
    let recommendedSplit: StartWorkoutRecommendedSplitSnapshot?

    init(
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: StartWorkoutRecommendedSplitSnapshot? = nil
    ) {
        self.trainingCall = trainingCall
        self.recommendedSplit = recommendedSplit
    }

    static let placeholder = StartWorkoutDashboardSnapshot(
        trainingCall: .placeholder,
        recommendedSplit: nil
    )
}

struct StartWorkoutRecentSessionSnapshot: Sendable {
    let sessionId: UUID
    let splitName: String
    let dateText: String
    let durationText: String
    let ratingText: String
    let highlightText: String
    let badgeState: CoachBadgeState

    var iconKey: ExerciseIconKey {
        ExerciseIconMapper.splitIconKey(for: splitName)
    }

    static func placeholder(_ session: WorkoutSession) -> StartWorkoutRecentSessionSnapshot {
        StartWorkoutRecentSessionSnapshot(
            sessionId: session.id,
            splitName: session.splitNameSnapshot,
            dateText: session.date.formatted(date: .abbreviated, time: .omitted),
            durationText: durationText(for: session),
            ratingText: ratingText(for: session.perceivedDifficulty),
            highlightText: "Last session is ready to repeat while Peakline prepares the full summary.",
            badgeState: .ready
        )
    }

    static func placeholder(_ workout: HistoryWorkoutSnapshot) -> StartWorkoutRecentSessionSnapshot {
        StartWorkoutRecentSessionSnapshot(
            sessionId: workout.id,
            splitName: workout.splitName,
            dateText: workout.date.formatted(date: .abbreviated, time: .omitted),
            durationText: durationText(for: workout),
            ratingText: ratingText(for: workout.rating),
            highlightText: "Last session is ready to repeat while Peakline prepares the full summary.",
            badgeState: .ready
        )
    }

    private static func durationText(for session: WorkoutSession) -> String {
        if let durationSeconds = session.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return durationText(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let durationMinutes = session.durationMinutes {
            return "\(durationMinutes)m"
        }

        return "Recorded"
    }

    private static func durationText(for workout: HistoryWorkoutSnapshot) -> String {
        if let durationSeconds = workout.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

        if let startedAt = workout.startedAt, let endedAt = workout.endedAt {
            return durationText(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let durationMinutes = workout.durationMinutes {
            return "\(durationMinutes)m"
        }

        return "Recorded"
    }

    private static func durationText(seconds totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private static func ratingText(for score: Int?) -> String {
        guard let score else { return "-" }

        switch score {
        case 1:
            return "Rough"
        case 2:
            return "Okay"
        case 3:
            return "Good"
        case 4:
            return "Great"
        case 5:
            return "Excellent"
        default:
            return "\(score)/5"
        }
    }
}

struct StartWorkoutSplitCardSnapshot: Identifiable, Sendable {
    let splitId: UUID
    let splitName: String
    let lastTrainedText: String
    let estimatedDurationText: String
    let exerciseCount: Int
    let plannedExerciseCount: Int?
    let badgeState: CoachBadgeState

    var id: UUID { splitId }

    static func placeholder(_ split: TrainingSplit) -> StartWorkoutSplitCardSnapshot {
        StartWorkoutSplitCardSnapshot(
            splitId: split.id,
            splitName: split.name,
            lastTrainedText: "Ready to start",
            estimatedDurationText: "Plan ready",
            exerciseCount: 0,
            plannedExerciseCount: nil,
            badgeState: .baseline
        )
    }
}
