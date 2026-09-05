import SwiftData
import SwiftUI

struct TodayView: View {
    @ScaledMetric(relativeTo: .title) private var headerSize: CGFloat = 28
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @Query
    private var activeSplits: [TrainingSplit]

    @Query
    private var exercises: [Exercise]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var unfinishedSessions: [WorkoutSession]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @Query
    private var hydrationEntries: [HydrationEntry]

    @Query
    private var foodLogEntries: [FoodLogEntry]

    @Query
    private var coachCheckIns: [DailyCoachCheckIn]

    @State private var selectedRoute: TodayRoute?
    @State private var showingRestDayConfirmation = false
    @State private var previewRoute: WorkoutPreviewPreparedRoute?
    @State private var previewNavigationKey: String?
    @State private var startWorkoutRoute: StartWorkoutRoute?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = SleepAnalyticsService.emptyReadinessSnapshot()
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var coachSnapshot = CoachIntelligenceService.emptySnapshot()
    @State private var lastCoachSnapshotSignature: String?
    @State private var todaySnapshot = TodayDashboardSnapshot.empty
    @State private var trainingCallSnapshot = TrainingCallSnapshot.placeholder
    @State private var lastTodaySnapshotSignature: String?
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var didRequestInitialRefresh = false
    @State private var pendingRouteNavigation: TodayRouteNavigationStart?
    @State private var backupWarning: String?
    @State private var checkInDraft: DailyCheckInDraft?
    @State private var isWorkoutCompletionPresentationActive = false
    @State private var isDashboardVisible = false
    @StateObject private var dashboardArrival = DashboardArrivalCoordinator()
    @State private var reentryWashCards: Set<TodayReentryCard> = []
    @State private var reentryWashTask: Task<Void, Never>?
    @State private var wasAwayForReentry = false
    @State private var reentryComparisonPending = false
    @State private var lastReadinessCardOutputSignature: String?
    @State private var lastRecoveryCardOutputSignature: String?
    @State private var lastNutritionCardOutputSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?

    private let initialStartupSnapshot: StartupSnapshotBundle?
    private let openHistory: () -> Void
    private let openSettings: () -> Void
    private let coachIntelligence = CoachIntelligenceService()
    private let decisionService = TrainingDecisionService()
    private let rotationService = TrainingRotationService()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let modePlanner = WorkoutModePlanner()
    private let sleepCoaching = SleepCoachingService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let workoutDashboardWarmStartStore = WorkoutDashboardWarmStartStore.shared
    private let hydrationService = HydrationService()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let targetSuggestionService = TargetSuggestionService()
    private let accountService = FirebaseAccountService()
    private let backupCoordinator = BackupCoordinator()

    init(startupSnapshot: StartupSnapshotBundle? = nil, openHistory: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openHistory = openHistory
        self.openSettings = openSettings
        initialStartupSnapshot = startupSnapshot
        _activeSplits = Query(Self.activeSplitsDescriptor)
        _exercises = Query(Self.exercisesDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _unfinishedSessions = Query(Self.unfinishedSessionsDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
        _sleepReadinessSnapshot = State(
            initialValue: startupSnapshot?.sleepReadinessSnapshot
                ?? SleepAnalyticsService.emptyReadinessSnapshot()
        )
        _coachSnapshot = State(
            initialValue: startupSnapshot?.coachSnapshot
                ?? CoachIntelligenceService.emptySnapshot()
        )
        _trainingCallSnapshot = State(
            initialValue: startupSnapshot?.trainingCall
                ?? WorkoutDashboardWarmStartStore.shared.trainingCall
                ?? .placeholder
        )
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var exercisesDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 180
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

    private static var unfinishedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { !$0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var hydrationEntriesDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var foodLogEntriesDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 160
        return descriptor
    }

    private static var coachCheckInsDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private var currentTodaySnapshot: TodayDashboardSnapshot {
        todaySnapshot
    }

    private var todaySnapshotSignature: String {
        let splitSignature = signature(activeSplits, limit: 12) {
            "\($0.id.uuidString):\($0.activeRotationIndex ?? -1):\($0.updatedAt.timeIntervalSince1970):\($0.exercises.count)"
        }
        let sessionSignature = signature(completedSessions, limit: 40) { session in
            let setSignature = session.exerciseLogs
                .flatMap(\.setLogs)
                .map { "\($0.id.uuidString):\($0.completed):\($0.isWarmup):\($0.weight):\($0.reps)" }
                .joined(separator: ",")
            return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(setSignature)"
        }
        let unfinishedSignature = signature(unfinishedSessions, limit: 5) { session in
            let sets = session.exerciseLogs
                .flatMap(\.setLogs)
                .map { "\($0.id.uuidString):\($0.completed):\($0.weight):\($0.reps)" }
                .joined(separator: ",")
            return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(sets)"
        }
        let hydrationSignature = signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
        return [
            splitSignature,
            sessionSignature,
            unfinishedSignature,
            hydrationSignature,
            String(hydrationTargetML),
            "workoutRevision:\(workoutWarmStartInvalidation.revision)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    private var todaySnapshotSignatureForObservation: String? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : todaySnapshotSignature
    }

    private var trainingDecision: TrainingDecision {
        currentTodaySnapshot.trainingDecision
    }

    private var trainingCall: TrainingCallSnapshot {
        trainingCallSnapshot
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: Array(completedSessions.prefix(12)),
            settings: sleepSettings,
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var currentSleepAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: completedSessions,
            settings: sleepSettings,
            sessionLimit: 90,
            workoutLimit: 28,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var currentOverallReadinessSourceSignature: String {
        let inputSignature = OverallReadinessInputSignature.make(
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            completedWorkouts: completedSessions,
            hydrationEntries: hydrationEntries,
            foodLogs: foodLogEntries,
            checkIns: coachCheckIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            workoutRevision: workoutWarmStartInvalidation.revision,
            dayStart: readinessRefreshClock.token.dayStart,
            hydrationPhase: readinessRefreshClock.token.hydrationPhase
        )
        return "\(inputSignature)|readinessGeneration:\(readinessRefreshClock.token.generation)"
    }

    private var sleepReadinessSignatureForObservation: SleepAnalyticsInputSignature? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentSleepReadinessSignature
    }

    private var hydrationSummary: DailyHydrationSummary {
        currentTodaySnapshot.hydrationSummary
    }

    private var readinessScore: ReadinessScore {
        currentCoachSnapshot.readiness
    }

    private var currentSleepReadinessSnapshot: SleepWorkoutReadinessSnapshot {
        sleepReadinessSnapshot
    }

    private var currentCoachSnapshot: CoachIntelligenceSnapshot {
        coachSnapshot
    }

    private var currentCoachSnapshotSignature: String {
        [
            signature(activeSplits, limit: 12) {
                "\($0.id.uuidString):\($0.activeRotationIndex ?? -1):\($0.updatedAt.timeIntervalSince1970)"
            },
            signature(exercises, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(completedSessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(sleepSessions, limit: 45) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(hydrationEntries, limit: 60) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 80) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 14) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "workoutRevision:\(workoutWarmStartInvalidation.revision)",
            sleepSettingsSignature,
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    private var coachSnapshotSignatureForObservation: String? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentCoachSnapshotSignature
    }

    private var sleepSettingsSignature: String {
        [
            "\(sleepSettings.targetSleepMinutes)",
            "\(sleepSettings.recoveryCoachingEnabled)",
            sleepSettings.preferredSource.rawValue,
            "\(sleepSettings.coachingPreferences.sleepCoachingInsightsEnabled)",
            "\(sleepSettings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled)",
            "\(sleepSettings.coachingPreferences.deloadSuggestionsEnabled)",
            "\(sleepSettings.coachingPreferences.sleepPerformanceInsightsEnabled)"
        ].joined(separator: ":")
    }

    private func makeCoachSnapshot() -> CoachIntelligenceSnapshot {
        PerformanceTracer.trace(.todayCoachSnapshot) {
            coachIntelligence.snapshot(
                activeSplits: activeSplits,
                exercises: exercises,
                sleepSessions: sleepSessions,
                napSessions: napSessions,
                hydrationEntries: hydrationEntries,
                completedWorkouts: Array(completedSessions.prefix(40)),
                foodLogs: foodLogEntries,
                checkIns: coachCheckIns,
                sleepSettings: sleepSettings,
                hydrationTargetML: hydrationTargetML,
                nutritionGoal: nutritionGoal
            )
        }
    }

    private func refreshTodaySnapshot(force: Bool = false) {
        let signature = todaySnapshotSignature
        guard force || signature != lastTodaySnapshotSignature else { return }
        let nextSnapshot = PerformanceTracer.trace(.todaySnapshot) {
            makeTodaySnapshot()
        }
        let nextTrainingCall = makeTrainingCall(
            decision: nextSnapshot.trainingDecision,
            coachSnapshot: currentCoachSnapshot
        )
        AppMotion.withoutAnimation {
            todaySnapshot = nextSnapshot
            trainingCallSnapshot = nextTrainingCall
            lastTodaySnapshotSignature = signature
        }
        workoutDashboardWarmStartStore.update(
            trainingCall: nextTrainingCall,
            sourceSignature: signature
        )
        scheduleReentryWashEvaluation()
    }

    private func makeTodaySnapshot() -> TodayDashboardSnapshot {
        let sessionSnapshots = completedSessions.prefix(40).map(makeWorkoutSessionSnapshot)
        let orderedActiveSplits = rotationService.orderedActiveSplits(activeSplits)
        let decision = decisionService.decision(
            activeSplits: orderedActiveSplits,
            completedSessions: Array(completedSessions.prefix(40))
        )
        let recentCycleNames = makeRecentProgrammeCycleNames(from: sessionSnapshots)
        let suggested = orderedActiveSplits.first { $0.name == decision.recommendedSplitName }
            ?? orderedActiveSplits.first
        let weekSessionSnapshots = makeWeeklySessionSnapshots(from: sessionSnapshots)
        let workingSets = weekSessionSnapshots.reduce(0) { $0 + $1.workingSetCount }
        let volume = weekSessionSnapshots.reduce(0) { $0 + $1.workingSetVolume }
        let mode = makeTrainingCall(
            decision: decision,
            coachSnapshot: currentCoachSnapshot
        ).recommendedMode
        let nextLift = makeNextLiftSnapshot(
            suggestedSplit: suggested,
            completedSessions: Array(completedSessions.prefix(40)),
            mode: mode
        )
        let completedDays = makeCompletedDaysThisWeek(from: weekSessionSnapshots)
        let coverageNames = makeSplitCoverageNames(from: activeSplits)
        let trainedNames = Set(weekSessionSnapshots.map(\.baseSplitName))
        let coverageItems = coverageNames.map { name in
            SplitCoverageItem(name: name, isComplete: trainedNames.contains(name))
        }

        return TodayDashboardSnapshot(
            trainingDecision: decision,
            hydrationSummary: hydrationService.summary(
                entries: hydrationEntries,
                targetML: hydrationTargetML
            ),
            suggestedSplit: suggested,
            recentProgrammeCycleNames: recentCycleNames,
            weeklySessions: weekSessionSnapshots.map(\.session),
            workoutsThisWeek: weekSessionSnapshots.count,
            workingSetsThisWeek: workingSets,
            volumeThisWeekText: makeVolumeText(volume),
            splitCoverageItems: coverageItems,
            splitCoverageNames: coverageNames,
            splitBalanceText: makeSplitBalanceText(from: coverageItems),
            splitCoverageSubtitle: makeSplitCoverageSubtitle(from: coverageItems),
            nextLift: nextLift,
            completedDaysThisWeek: completedDays
        )
    }

    private func makeNextLiftSnapshot(
        suggestedSplit: TrainingSplit?,
        completedSessions: [WorkoutSession],
        mode: WorkoutMode
    ) -> TodayNextLiftSnapshot {
        guard let suggestedSplit else { return .empty }
        let orderedExercises = suggestedSplit.exercises.sorted { $0.orderIndex < $1.orderIndex }
        let planned = modePlanner.plannedExercises(
            from: orderedExercises.map(WorkoutSelectableExercise.init),
            mode: mode
        )
        guard let first = planned.first,
              let exercise = orderedExercises.first(where: { $0.id == first.id }) else {
            return .empty
        }

        let baseSuggestion = targetSuggestionService.suggestion(
            for: exercise,
            completedSessions: completedSessions
        )
        let suggestion = modePlanner.modeAdjustedSuggestion(baseSuggestion, mode: mode)
        let targetText: String
        if let weight = suggestion.suggestedWeight, let reps = suggestion.suggestedReps {
            targetText = PeaklineText.loadReps(weight: formattedWeight(weight), reps: reps)
        } else if let weight = suggestion.suggestedWeight {
            targetText = "\(formattedWeight(weight)) kg"
        } else if let reps = suggestion.suggestedReps {
            targetText = PeaklineText.count(reps, singular: "rep")
        } else {
            targetText = PeaklineText.repRange(minimum: exercise.minReps, maximum: exercise.maxReps)
        }

        return TodayNextLiftSnapshot(
            value: exercise.exerciseNameSnapshot,
            detail: targetText,
            footer: suggestion.reason.components(separatedBy: ". ").first
        )
    }

    private func makeCompletedDaysThisWeek(from snapshots: [TodayWorkoutSessionSnapshot]) -> [Bool] {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else {
            return Array(repeating: false, count: 7)
        }

        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return false
            }
            return snapshots.contains { calendar.isDate($0.session.date, inSameDayAs: day) }
        }
    }

    private func formattedWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return "\(Int(weight))"
        }
        return weight.formatted(.number.precision(.fractionLength(1)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
                    todayHeader

                    if let backupWarning {
                        BackupHealthWarningCard(message: backupWarning)
                    }

                    TodayReadinessHero(
                        scoreText: readinessScoreText,
                        status: readinessStatusText,
                        summary: readinessSummaryText,
                        coverage: readinessCoverageText,
                        isProvisional: readinessIsProvisional,
                        action: openCoachRoute
                    )
                    .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 0), index: 0)
                    .todayReentryWash(isActive: reentryWashCards.contains(.readiness))

                    LazyVGrid(columns: todayGridColumns, spacing: appTheme.metrics.spacing10) {
                        TodayMetricCard(
                            title: unfinishedSessions.isEmpty ? "Next Lift" : "Active Workout",
                            systemImage: "figure.strengthtraining.traditional",
                            value: nextLiftValueText,
                            detail: nextLiftDetailText,
                            footer: nextLiftFooterText,
                            isMetric: false,
                            highlightValue: false,
                            action: nextLiftAction
                        )
                        .accessibilityIdentifier("quick-action-workout")

                        TodayMetricCard(
                            title: "Sleep",
                            systemImage: "moon.zzz",
                            value: sleepValueText,
                            detail: sleepDetailText,
                            footer: sleepFooterText,
                            isMetric: true,
                            action: { openRoute(.sleep) }
                        )
                        .accessibilityIdentifier("quick-action-sleep")
                        .todayReentryWash(isActive: reentryWashCards.contains(.recovery))

                        TodayMetricCard(
                            title: "Hydration",
                            systemImage: "drop",
                            value: hydrationValueText,
                            detail: hydrationDetailText,
                            footer: hydrationFooterText,
                            isMetric: true,
                            highlightValue: hydrationSummary.totalML > 0,
                            action: { openRoute(.hydration) }
                        )
                        .accessibilityIdentifier("quick-action-hydration")

                        TodayMetricCard(
                            title: "Coach Brief",
                            systemImage: "doc.text",
                            value: coachBriefValueText,
                            detail: coachBriefDetailText,
                            footer: nil,
                            action: openCoachRoute
                        )
                        .accessibilityIdentifier("today-coach-brief-open")
                    }
                    .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 1), index: 1)

                    TodayWeeklyActivityCard(completedDays: completedDaysThisWeek) {
                        openHistory()
                    }
                    .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 2), index: 2)

                    TodayPlanButton(
                        isEnabled: suggestedSplit != nil,
                        action: previewSuggestedSplit
                    )
                    .dashboardArrival(isVisible: dashboardArrival.isVisible(index: 3), index: 3)
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .accessibilityIdentifier("today-screen")
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedRoute) { route in
                destination(for: route)
            }
            .navigationDestination(item: $previewRoute) { route in
                WorkoutPreviewRouteView(preparedRoute: route) {
                    previewRoute = nil
                }
                .toolbar(.visible, for: .navigationBar)
                .onAppear {
                    if let previewNavigationKey {
                        NavigationInteraction.destinationDidAppear(
                            key: previewNavigationKey
                        )
                        self.previewNavigationKey = nil
                    }
                }
            }
            .sheet(item: $checkInDraft) { draft in
                DailyCheckInSheet(draft: draft)
                    .sheetContentEntrance()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Rest day noted", isPresented: $showingRestDayConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Persistent rest-day logging is still on the roadmap. For now, your workout history remains unchanged.")
            }
            .onAppear {
                let isReentry = wasAwayForReentry && didRequestInitialRefresh
                wasAwayForReentry = false
                reentryComparisonPending = isReentry
                isDashboardVisible = true
                dashboardArrival.start(itemCount: 4, reduceMotion: reduceMotion)
                readinessRefreshClock.start()
                sleepSettings = sleepSettingsStore.load()
                hydrationTargetML = hydrationSettingsStore.dailyTargetML()
                nutritionGoal = nutritionGoalStore.loadGoal()
                let shouldForceRefresh = !didRequestInitialRefresh
                didRequestInitialRefresh = true
                dashboardRefreshTask?.cancel()
                dashboardRefreshTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    refreshTodaySnapshot(force: shouldForceRefresh)
                    if initialStartupSnapshot == nil {
                        refreshSleepReadiness(force: shouldForceRefresh)
                        refreshCoachSnapshot(force: shouldForceRefresh)
                    } else {
                        lastSleepReadinessSignature = currentSleepReadinessSignature
                        lastCoachSnapshotSignature = currentCoachSnapshotSignature
                    }
                    scheduleReentryWashEvaluation()
                    dashboardRefreshTask = nil
                }
                Task { await refreshBackupWarning() }
            }
            .onChange(of: todaySnapshotSignatureForObservation) { _, signature in
                guard signature != nil else { return }
                refreshTodaySnapshot()
            }
            .onChange(of: sleepReadinessSignatureForObservation) { _, signature in
                guard signature != nil else { return }
                refreshSleepReadiness()
            }
            .onChange(of: coachSnapshotSignatureForObservation) { _, signature in
                guard signature != nil else { return }
                refreshCoachSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
                isWorkoutCompletionPresentationActive = true
                PerformanceTracer.mark(.workoutLoggerFinish, "today_refresh_suspended")
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
                isWorkoutCompletionPresentationActive = false
                PerformanceTracer.mark(.workoutLoggerFinish, "today_refresh_resumed")
            }
            .onDisappear {
                isDashboardVisible = false
                wasAwayForReentry = true
                dashboardRefreshTask?.cancel()
                dashboardRefreshTask = nil
                reentryWashTask?.cancel()
                reentryWashTask = nil
                dashboardArrival.cancel()
            }
        }
    }

    private func refreshBackupWarning() async {
#if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
                && !ProcessInfo.processInfo.arguments.contains("-SkipAccountGate") else {
            backupWarning = nil
            return
        }
#endif

        let readiness = await accountService.readiness()
        guard readiness.isReady else {
            backupWarning = readiness.message
            return
        }

        switch await backupCoordinator.latestMetadata() {
        case .available:
            backupWarning = nil
        case .noBackup:
            backupWarning = "No encrypted Firebase backup has been saved yet. Open Settings -> Account & Backup and save one before deleting the app."
        case .unavailable(let message), .failed(let message):
            backupWarning = message
        }
    }

    private func openRoute(_ route: TodayRoute) {
        let activeRoute = selectedRoute?.analyticsName ?? "none"
        let pendingRoute = pendingRouteNavigation?.route.analyticsName ?? "none"
        PerformanceTracer.mark(.todayRouteSelectionState, "request route=\(route.analyticsName) active=\(activeRoute) pending=\(pendingRoute)")
        guard selectedRoute != route else {
            PerformanceTracer.mark(.todayRouteSelectionState, "skip selectedRoute=\(route.analyticsName) already_active")
            return
        }
        guard pendingRouteNavigation?.route != route else {
            PerformanceTracer.mark(.todayRouteSelectionState, "skip selectedRoute=\(route.analyticsName) transition_in_flight")
            return
        }

        PerformanceTracer.mark(.todayRouteSelection, "\(route.analyticsName) requested")
        PerformanceTracer.mark(.todayRouteSelectionState, "before selectedRoute=\(route.analyticsName)")
        let navigationKey = "today.\(route.analyticsName)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: route.destinationClass,
            haptic: route == .workout ? .medium : .selection,
            action: {
            PerformanceTracer.trace(.todayRouteSelection) {
                selectedRoute = route
            }
        }) else {
            return
        }
        PerformanceTracer.mark(.todayRouteSelectionState, "after selectedRoute=\(route.analyticsName)")
        pendingRouteNavigation = TodayRouteNavigationStart(route: route, startedAt: ContinuousClock.now)
    }

    private func openCoachRoute() {
        PerformanceTracer.mark(.todayRouteSelectionState, "open_coach_route signature_ready=\(lastCoachSnapshotSignature != nil)")
        openRoute(.coach)
    }

    @ViewBuilder
    private func destination(for route: TodayRoute) -> some View {
        let _ = PerformanceTracer.mark(.todayRouteDestination, "build_start route=\(route.analyticsName) scenePhase=\(String(describing: scenePhase))")
        Group {
            switch route {
            case .workout:
                StartWorkoutContentView(
                    initialReadinessSnapshot: initialStartupSnapshot?.workoutSleepReadinessSnapshot,
                    initialReadinessSignature: initialStartupSnapshot?.sleepReadinessInputSignature,
                    initialFirstFrameSnapshot: initialStartupSnapshot?.workoutFirstFrameSnapshot,
                    initialOverallReadinessIsProvisional: currentCoachSnapshot.readiness.isProvisional
                ) { route in
                    guard startWorkoutRoute != route else { return }
                    NavigationInteraction.perform(
                        key: "today.workout.\(route.analyticsName)",
                        destinationClass: route.destinationClass,
                        haptic: .selection
                    ) {
                        startWorkoutRoute = route
                    }
                }
                .navigationDestination(item: $startWorkoutRoute) { route in
                    startWorkoutDestination(for: route)
                        .onAppear {
                            NavigationInteraction.destinationDidAppear(
                                key: "today.workout.\(route.analyticsName)"
                            )
                        }
                }
            case .coach:
                CoachRouteDestinationView(
                    initialSnapshot: coachNavigationSnapshot,
                    backButtonTitle: "Today",
                    onBack: {
                        selectedRoute = nil
                    }
                )
            case .progress:
                ProgressContentView()
            case .nutrition:
                DeferredNutritionDashboardHost(
                    initialPayload: NutritionWarmStartStore.shared.dashboard
                )
            case .sleep:
                DeferredSleepDashboardHost(
                    initialSnapshot: WarmRouteSnapshots.sleepAnalytics(
                        matching: currentSleepAnalyticsSignature,
                        fallback: initialStartupSnapshot?.sleepAnalyticsSnapshot
                    ),
                    initialReadinessScore: WarmRouteSnapshots.overallReadiness(
                        matching: currentOverallReadinessSourceSignature,
                        fallback: initialStartupSnapshot?.coachSnapshot.readiness
                    )
                )
            case .hydration:
                HydrationView()
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .background {
            if route == .coach, scenePhase == .active {
                CoachRouteFrameProbe(label: "navigationDestination.background")
            }
        }
        .onAppear {
            PerformanceTracer.mark(.todayRouteDestination, "onAppear route=\(route.analyticsName)")
            NavigationInteraction.destinationDidAppear(
                key: "today.\(route.analyticsName)"
            )
            markRouteAppeared(route)
        }
    }

    @ViewBuilder
    private func startWorkoutDestination(for route: StartWorkoutRoute) -> some View {
        switch route {
        case .coach:
            CoachRouteDestinationView()
        case .templates:
            WorkoutTemplateLibraryView()
        case .library:
            ExerciseLibraryView()
        case let .preview(route):
            WorkoutPreviewRouteView(preparedRoute: route.preparedRoute) {
                startWorkoutRoute = nil
            }
        }
    }

    private func markRouteAppeared(_ route: TodayRoute) {
        guard let pendingRouteNavigation, pendingRouteNavigation.route == route else {
            return
        }

        let elapsed = pendingRouteNavigation.startedAt.duration(to: ContinuousClock.now)
        let milliseconds = elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        PerformanceTracer.mark(.todayRouteAppear, "\(route.analyticsName) appeared in \(milliseconds)ms")
        self.pendingRouteNavigation = nil
    }

    private var todayDateText: String {
        let weekday = Date.now.formatted(.dateTime.weekday(.abbreviated))
        let date = Date.now.formatted(.dateTime.day().month(.abbreviated))
        return "\(weekday), \(date)"
    }

    private var todayHeader: some View {
        HStack(alignment: .top, spacing: appTheme.metrics.spacing12) {
            VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                Text("Peakline")
                    .font(AppTypography.rounded(size: headerSize, weight: .bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)

                Text("Today · \(todayDateText)")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: appTheme.metrics.spacing8)

            Menu {
                Button {
                    openRoute(.workout)
                } label: {
                    Label(
                        unfinishedSessions.isEmpty ? "Start Workout" : "Resume Workout",
                        systemImage: unfinishedSessions.isEmpty ? "play.fill" : "arrow.clockwise.circle"
                    )
                }

                Button {
                    previewSuggestedSplit()
                } label: {
                    Label("Review Today’s Plan", systemImage: "list.bullet")
                }
                .disabled(suggestedSplit == nil)

                Button {
                    openRoute(.nutrition)
                } label: {
                    Label("Nutrition", systemImage: "fork.knife")
                }

                Button {
                    openRoute(.progress)
                } label: {
                    Label("Progress & Charts", systemImage: "chart.xyaxis.line")
                }

                Button {
                    openCoachRoute()
                } label: {
                    Label("Coach Brief", systemImage: "doc.text")
                }

                Button {
                    presentCheckIn()
                } label: {
                    Label("Check In", systemImage: "checkmark.circle")
                }

                Divider()

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(AppTypography.rounded(size: 28, weight: .semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                    .background(appTheme.colors.cardBackgroundElevated, in: Circle())
            }
            .accessibilityLabel("Profile and more options")
            .accessibilityIdentifier("today-profile-menu")
        }
        .padding(.top, appTheme.metrics.spacing4)
    }

    private var hasLoadedReadiness: Bool {
        lastCoachSnapshotSignature != nil || initialStartupSnapshot != nil
    }

    private var hasReadinessEvidence: Bool {
        hasLoadedReadiness && readinessScore.availableSignalCount > 0
    }

    private var todayGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: appTheme.metrics.spacing12, alignment: .top),
            GridItem(.flexible(), spacing: appTheme.metrics.spacing12, alignment: .top)
        ]
    }

    private var readinessScoreText: String {
        hasReadinessEvidence ? "\(readinessScore.value)" : "—"
    }

    private var readinessStatusText: String {
        guard hasReadinessEvidence else { return "Readiness not available" }
        return readinessScore.isProvisional ? "Build your daily picture" : readinessScore.recommendation.title
    }

    private var readinessSummaryText: String {
        guard hasReadinessEvidence else {
            return "Add local recovery signals to see today’s readiness score."
        }
        return readinessScore.recommendation.summary
    }

    private var readinessCoverageText: String {
        guard hasLoadedReadiness else { return "Local signals are still loading." }
        return readinessScore.coverageSummary
    }

    private var readinessIsProvisional: Bool {
        hasReadinessEvidence && readinessScore.isProvisional
    }

    private var nextLiftValueText: String {
        unfinishedSessions.isEmpty ? currentTodaySnapshot.nextLift.value : "Resume Workout"
    }

    private var nextLiftDetailText: String {
        unfinishedSessions.first?.splitNameSnapshot ?? currentTodaySnapshot.nextLift.detail
    }

    private var nextLiftFooterText: String? {
        unfinishedSessions.isEmpty ? currentTodaySnapshot.nextLift.footer : "Continue your active session"
    }

    private var nextLiftAction: () -> Void {
        unfinishedSessions.isEmpty ? previewSuggestedSplit : { openRoute(.workout) }
    }

    private var sleepValueText: String {
        guard sleepSummary.primarySession != nil else { return "—" }
        return SleepScoringService.durationText(minutes: sleepSummary.totalSleepMinutes)
    }

    private var sleepDetailText: String {
        guard sleepSummary.primarySession != nil else { return "No sleep recorded last night" }
        return sleepSummary.recoveryState.displayName
    }

    private var sleepFooterText: String? {
        guard let quality = sleepSummary.qualityRating else { return "Open Sleep" }
        return "Quality \(SleepQualityPicker.label(for: quality))"
    }

    private var hydrationValueText: String {
        hydrationSummary.totalML > 0 ? HydrationService.formatAmount(hydrationSummary.totalML) : "—"
    }

    private var hydrationDetailText: String {
        hydrationSummary.totalML > 0 ? hydrationSummary.status.displayName : "No water logged yet"
    }

    private var hydrationFooterText: String? {
        let percentage = Int((hydrationSummary.progress * 100).rounded())
        return "\(HydrationService.formatAmount(hydrationSummary.targetML)) goal · \(percentage)%"
    }

    private var coachBriefValueText: String {
        guard hasLoadedReadiness else { return "—" }
        let title = currentCoachSnapshot.adaptiveGuidance.title.components(separatedBy: ": ").last ?? ""
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private var coachBriefDetailText: String {
        guard hasLoadedReadiness else { return "Preparing your local coaching brief" }
        return currentCoachSnapshot.adaptiveGuidance.primarySuggestion
    }

    private var completedDaysThisWeek: [Bool] {
        currentTodaySnapshot.completedDaysThisWeek
    }

    private func presentCheckIn() {
        guard checkInDraft == nil else {
            PerformanceTracer.mark(.checkInSheetPresentation, "duplicate_request_ignored source=today")
            return
        }
        PerformanceTracer.mark(.checkInSheetPresentation, "requested source=today")
        checkInDraft = DailyCheckInDraft(existingCheckIn: currentCoachSnapshot.readiness.checkIn)
    }

    private var sleepSummary: SleepSummary {
        currentSleepReadinessSnapshot.latestSummary
    }

    private var todayRecoveryRecommendation: String {
        if readinessScore.isProvisional {
            return sleepSummary.primarySession == nil
                ? "Add sleep to improve this signal. Training guidance waits for enough daily readiness evidence."
                : "Sleep is one supportive signal. Training guidance waits for enough daily readiness evidence."
        }
        return currentSleepReadinessSnapshot.adaptiveRecommendation?.message ?? sleepCoaching.recommendation(for: sleepSummary, settings: sleepSettings)
    }

    private var coachNavigationSnapshot: CoachRouteRenderSnapshot? {
        CoachRouteSnapshotStore.shared.snapshot ?? initialStartupSnapshot?.coachRouteSnapshot
    }

    private var readinessCardOutputSignature: String {
        let readiness = currentCoachSnapshot.readiness
        let factors = readiness.topFactors.map {
            "\($0.kind.rawValue):\($0.title):\($0.detail):\($0.impact.rawValue):\($0.contribution)"
        }.joined(separator: ",")
        return [
            "value:\(readiness.value)",
            "category:\(readiness.category.rawValue)",
            "confidence:\(readiness.confidence.rawValue)",
            "provisional:\(readiness.isProvisional)",
            "coverage:\(readiness.coverageSummary)",
            "checkIn:\(readiness.hasCompletedTodayCheckIn)",
            "title:\(readiness.recommendation.title)",
            "summary:\(readiness.recommendation.summary)",
            "factors:\(factors)"
        ].joined(separator: "|")
    }

    private var recoveryCardOutputSignature: String {
        let summary = sleepSummary
        return [
            "state:\(summary.recoveryState.rawValue)",
            "minutes:\(summary.totalSleepMinutes)",
            "quality:\(summary.qualityRating ?? -1)",
            "source:\(summary.source?.rawValue ?? "none")",
            "score:\(summary.sleepScore ?? -1)",
            "recommendation:\(todayRecoveryRecommendation)"
        ].joined(separator: "|")
    }

    private var nutritionCardOutputSignature: String {
        let summary = NutritionHomeSummarySnapshot.make(
            foodLogs: foodLogEntries,
            completedSessions: completedSessions,
            goal: nutritionGoal
        )
        return [
            "calories:\(summary.today.calories)",
            "protein:\(summary.today.protein)",
            "training:\(summary.today.isTrainingDay)",
            "calorieTarget:\(summary.goal.calorieTarget(isTrainingDay: summary.today.isTrainingDay) ?? -1)",
            "proteinTarget:\(summary.goal.dailyProteinTarget ?? -1)",
            "insight:\(summary.topInsight?.title ?? "none")"
        ].joined(separator: "|")
    }

    private func captureTodayCardOutputSignatures() {
        lastReadinessCardOutputSignature = readinessCardOutputSignature
        lastRecoveryCardOutputSignature = recoveryCardOutputSignature
        lastNutritionCardOutputSignature = nutritionCardOutputSignature
    }

    private func scheduleReentryWashEvaluation() {
        guard isDashboardVisible else { return }
        guard reentryComparisonPending else {
            captureTodayCardOutputSignatures()
            return
        }

        reentryWashTask?.cancel()
        reentryWashTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isDashboardVisible, reentryComparisonPending else { return }

            var changed: Set<TodayReentryCard> = []
            if lastReadinessCardOutputSignature != readinessCardOutputSignature {
                changed.insert(.readiness)
            }
            if lastRecoveryCardOutputSignature != recoveryCardOutputSignature {
                changed.insert(.recovery)
            }
            if lastNutritionCardOutputSignature != nutritionCardOutputSignature {
                changed.insert(.nutrition)
            }

            reentryWashCards = changed
            reentryComparisonPending = false
            captureTodayCardOutputSignatures()
            reentryWashTask = nil

            guard !changed.isEmpty else { return }
            try? await Task.sleep(nanoseconds: UInt64(AppMotion.todayReentryWashDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            reentryWashCards = []
        }
    }

    private func refreshSleepReadiness(force: Bool = false) {
        let signature = currentSleepReadinessSignature
        guard force || signature != lastSleepReadinessSignature else { return }

        let nextSnapshot = PerformanceTracer.trace(.todaySleepReadiness) {
            sleepReadinessStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedSessions.prefix(12)),
                settings: sleepSettings,
                workoutRevision: workoutWarmStartInvalidation.revision,
                force: force
            )
        }
        AppMotion.withoutAnimation {
            sleepReadinessSnapshot = nextSnapshot
            lastSleepReadinessSignature = signature
        }
        scheduleReentryWashEvaluation()
    }

    private func refreshCoachSnapshot(force: Bool = false) {
        let signature = currentCoachSnapshotSignature
        guard force || signature != lastCoachSnapshotSignature else { return }

        let nextSnapshot = makeCoachSnapshot()
        AppMotion.withoutAnimation {
            coachSnapshot = nextSnapshot
            lastCoachSnapshotSignature = signature
        }
        let nextTrainingCall = makeTrainingCall(
            decision: trainingDecision,
            coachSnapshot: nextSnapshot
        ).neutralizedForProvisionalReadiness(if: nextSnapshot.readiness.isProvisional)
        let nextLift = makeNextLiftSnapshot(
            suggestedSplit: suggestedSplit,
            completedSessions: Array(completedSessions.prefix(40)),
            mode: nextTrainingCall.recommendedMode
        )
        AppMotion.withoutAnimation {
            trainingCallSnapshot = nextTrainingCall
            todaySnapshot.nextLift = nextLift
        }
        workoutDashboardWarmStartStore.update(
            trainingCall: nextTrainingCall,
            sourceSignature: "\(lastTodaySnapshotSignature ?? "today-pending")|\(signature)"
        )
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store before_update source=today scenePhase=\(String(describing: scenePhase)) main=\(Thread.isMainThread)"
        )
        guard scenePhase == .active else {
            PerformanceTracer.mark(
                .coachSnapshot,
                "route_snapshot_store skip source=today scenePhase=\(String(describing: scenePhase))"
            )
            return
        }
        // A root modifier change can invalidate the route store between
        // refreshes. Rebuilding from this fresh intelligence (with startup
        // pieces as structural fallback) keeps the Readiness quick action's
        // first frame populated instead of reverting to a launch-time value.
        let nextRecommendedSplit = activeSplits.first {
            $0.name == nextTrainingCall.recommendedSplitName
        }.map(WorkoutPreviewSplit.init)
        CoachRouteSnapshotStore.shared.update(
            intelligence: nextSnapshot,
            trainingCall: nextTrainingCall,
            recommendedSplit: nextRecommendedSplit,
            fallback: initialStartupSnapshot?.coachRouteSnapshot,
            signature: signature,
            sourceGeneration: CoachRouteSnapshotStore.shared.nextSourceGeneration(),
            source: "today"
        )
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store after_update source=today scenePhase=\(String(describing: scenePhase)) main=\(Thread.isMainThread)"
        )
        scheduleReentryWashEvaluation()
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }

    private func makeTrainingCall(
        decision: TrainingDecision,
        coachSnapshot: CoachIntelligenceSnapshot
    ) -> TrainingCallSnapshot {
        trainingCallBuilder.make(
            decision: decision,
            activeSplits: activeSplits,
            completedSessions: Array(completedSessions.prefix(40)),
            readiness: coachSnapshot.readiness,
            fatigueRisk: coachSnapshot.fatigueRisk
        )
    }

    private var hydrationSubtitle: String {
        let summary = hydrationSummary
        if summary.totalML >= summary.targetML {
            return "Target reached today"
        }
        if summary.totalML > 0 {
            return "\(HydrationService.formatAmount(summary.totalML)) / \(HydrationService.formatAmount(summary.targetML)) today"
        }
        return "Log water intake"
    }

    private var suggestedSplit: TrainingSplit? {
        currentTodaySnapshot.suggestedSplit
            ?? trainingCall.recommendedSplitName.flatMap { recommendedName in
                activeSplits.first {
                    $0.name.compare(
                        recommendedName,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }
            }
    }

    private var programmeOrderedSplits: [TrainingSplit] {
        rotationService.orderedActiveSplits(activeSplits)
    }

    private var recentProgrammeCycleNames: [String] {
        currentTodaySnapshot.recentProgrammeCycleNames
    }

    private func makeWorkoutSessionSnapshot(_ session: WorkoutSession) -> TodayWorkoutSessionSnapshot {
        var workingSetCount = 0
        var workingSetVolume = 0.0
        let exerciseLogs = session.exerciseLogs

        for log in exerciseLogs {
            for set in log.setLogs where set.completed && !set.isWarmup {
                workingSetCount += 1
                workingSetVolume += set.weight * Double(set.reps)
            }
        }

        return TodayWorkoutSessionSnapshot(
            session: session,
            baseSplitName: baseSplitName(session.splitNameSnapshot),
            programmeSplitName: programmeSplitName(for: session),
            exerciseCount: exerciseLogs.count,
            workingSetCount: workingSetCount,
            workingSetVolume: workingSetVolume
        )
    }

    private func makeRecentProgrammeCycleNames(from sessionSnapshots: [TodayWorkoutSessionSnapshot]) -> [String] {
        var names: [String] = []

        for sessionSnapshot in sessionSnapshots {
            guard let name = sessionSnapshot.programmeSplitName else { continue }

            if names.contains(name) {
                break
            }

            names.append(name)

            if names.count == programmeOrderedSplits.count {
                break
            }
        }

        return names
    }

    private func programmeSplitName(for session: WorkoutSession) -> String? {
        if let splitId = session.splitId {
            return programmeOrderedSplits.first { $0.id == splitId }?.name
        }

        let matches = programmeOrderedSplits.filter { split in
            session.splitNameSnapshot == split.name
                || session.splitNameSnapshot.hasPrefix("\(split.name) - ")
        }
        return matches.count == 1 ? matches.first?.name : nil
    }

    private var weeklySessions: [WorkoutSession] {
        currentTodaySnapshot.weeklySessions
    }

    private func makeWeeklySessionSnapshots(from sessionSnapshots: [TodayWorkoutSessionSnapshot]) -> [TodayWorkoutSessionSnapshot] {
        sessionSnapshots.filter { $0.session.date <= .now && Calendar.current.isDate($0.session.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    private var workoutsThisWeek: Int {
        currentTodaySnapshot.workoutsThisWeek
    }

    private var workingSetsThisWeek: Int {
        currentTodaySnapshot.workingSetsThisWeek
    }

    private var volumeThisWeekText: String {
        currentTodaySnapshot.volumeThisWeekText
    }

    private func makeVolumeText(_ volume: Double) -> String {
        guard volume > 0 else { return "0" }
        if volume >= 100_000 {
            return "\(Int(volume / 1_000))k"
        }
        if volume >= 1_000 {
            return String(format: "%.1fk", volume / 1_000)
        }
        return "\(Int(volume))"
    }

    private var splitCoverageItems: [SplitCoverageItem] {
        currentTodaySnapshot.splitCoverageItems
    }

    private var splitCoverageNames: [String] {
        currentTodaySnapshot.splitCoverageNames
    }

    private func makeSplitCoverageNames(from splits: [TrainingSplit]) -> [String] {
        rotationService.orderedActiveSplits(splits).map(\.name)
    }

    private var splitBalanceText: String {
        currentTodaySnapshot.splitBalanceText
    }

    private func makeSplitBalanceText(from items: [SplitCoverageItem]) -> String {
        guard !items.isEmpty else { return "0/0" }
        return "\(items.filter(\.isComplete).count)/\(items.count)"
    }

    private var splitCoverageSubtitle: String {
        currentTodaySnapshot.splitCoverageSubtitle
    }

    private func makeSplitCoverageSubtitle(from items: [SplitCoverageItem]) -> String {
        guard !items.isEmpty else {
            return "Create active splits to track weekly coverage."
        }

        if items.allSatisfy(\.isComplete) {
            return "Balanced week complete."
        }

        return "Complete each active split once this week."
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }

    private func previewSuggestedSplit() {
        guard let suggestedSplit else { return }
        openPreview(WorkoutPreviewSplit(suggestedSplit), mode: trainingCall.recommendedMode)
    }

    private func openPreview(_ split: WorkoutPreviewSplit, mode: WorkoutMode = .full) {
        PerformanceTracer.mark(.previewRouteTap, "source=today split=\(split.name) mode=\(mode.rawValue)")
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation request source=today split=\(split.id.uuidString) active=\(previewRoute?.split.id.uuidString ?? "none")")
        guard previewRoute?.split.id != split.id else {
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation skip source=today already_active split=\(split.id.uuidString)")
            return
        }

        let preparedRoute = WorkoutPreviewWarmStartStore.shared.prepareRoute(
            for: split,
            initialMode: mode
        )
        let navigationKey = "today.preview.\(split.id.uuidString)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: .warm,
            haptic: .selection,
            action: {
            previewRoute = preparedRoute
            previewNavigationKey = navigationKey
        }) else {
            return
        }
    }
}

private struct DeferredSleepDashboardHost: View {
    let initialSnapshot: SleepAnalyticsSnapshot?
    let initialReadinessScore: ReadinessScore

    @State private var isLiveMounted = false
    @State private var isVisible = false

    var body: some View {
        content
            .onAppear {
                isVisible = true
                guard !isLiveMounted else { return }
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        guard isVisible else { return }
                        isLiveMounted = true
                    }
                }
            }
            .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private var content: some View {
        if isLiveMounted {
            SleepDashboardView(
                initialSnapshot: initialSnapshot,
                initialReadinessScore: initialReadinessScore
            )
        } else {
            FitnessScreen {
                FitnessCard(style: .hero) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sleep")
                            .font(AppTypography.cardTitle)
                        if let latest = initialSnapshot?.summaries.first {
                            Text(SleepScoringService.durationText(minutes: latest.totalSleepMinutes))
                                .font(AppTypography.heroMetric)
                                .accessibilityIdentifier("sleep-last-night-duration")
                        } else {
                            Text("Start Sleep Mode or add a sleep entry to build your recovery view.")
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("sleep-no-data-hero")
                        }
                    }
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("sleep-screen")
        }
    }
}

private struct TodayDashboardSnapshot {
    let trainingDecision: TrainingDecision
    let hydrationSummary: DailyHydrationSummary
    let suggestedSplit: TrainingSplit?
    let recentProgrammeCycleNames: [String]
    let weeklySessions: [WorkoutSession]
    let workoutsThisWeek: Int
    let workingSetsThisWeek: Int
    let volumeThisWeekText: String
    let splitCoverageItems: [SplitCoverageItem]
    let splitCoverageNames: [String]
    let splitBalanceText: String
    let splitCoverageSubtitle: String
    var nextLift: TodayNextLiftSnapshot
    let completedDaysThisWeek: [Bool]

    static let empty = TodayDashboardSnapshot(
        trainingDecision: TrainingDecision(
            recommendedSplitName: nil,
            recommendedMode: .full,
            action: .buildBaseline,
            title: "",
            reason: ""
        ),
        hydrationSummary: DailyHydrationSummary(
            date: .now,
            totalML: 0,
            targetML: 0,
            progress: 0,
            remainingML: 0,
            status: .low,
            lastLoggedAt: nil
        ),
        suggestedSplit: nil,
        recentProgrammeCycleNames: [],
        weeklySessions: [],
        workoutsThisWeek: 0,
        workingSetsThisWeek: 0,
        volumeThisWeekText: "0",
        splitCoverageItems: [],
        splitCoverageNames: [],
        splitBalanceText: "0/0",
        splitCoverageSubtitle: "Create active splits to track weekly coverage.",
        nextLift: .empty,
        completedDaysThisWeek: Array(repeating: false, count: 7)
    )
}

private struct TodayNextLiftSnapshot {
    let value: String
    let detail: String
    let footer: String?

    static let empty = TodayNextLiftSnapshot(
        value: "—",
        detail: "Choose a training split to prepare your next lift.",
        footer: nil
    )
}

private struct TodayWorkoutSessionSnapshot {
    let session: WorkoutSession
    let baseSplitName: String
    let programmeSplitName: String?
    let exerciseCount: Int
    let workingSetCount: Int
    let workingSetVolume: Double
}

private enum TodayRoute: Hashable, Identifiable {
    case workout
    case coach
    case progress
    case nutrition
    case sleep
    case hydration

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .workout:
            return "workout"
        case .coach:
            return "coach"
        case .progress:
            return "progress"
        case .nutrition:
            return "nutrition"
        case .sleep:
            return "sleep"
        case .hydration:
            return "hydration"
        }
    }

    var destinationClass: NavigationDestinationClass {
        switch self {
        case .coach, .progress:
            return .deep
        case .workout, .nutrition, .sleep, .hydration:
            return .warm
        }
    }
}

private enum TodayReentryCard: Hashable {
    case readiness
    case recovery
    case nutrition
}

private struct TodayRouteNavigationStart {
    let route: TodayRoute
    let startedAt: ContinuousClock.Instant
}

private struct BackupHealthWarningCard: View {
    @Environment(\.appTheme) private var appTheme

    let message: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(AppTypography.compactCardTitle)
                    .foregroundStyle(appTheme.colors.textWarning)
                    .frame(width: 38, height: 38)
                    .background(appTheme.colors.warning.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup needs attention")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct TodaySleepRecoveryCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let summary: SleepSummary
    let recommendation: String
    @State private var displayedScore: Double?

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(appTheme.colors.textAccent)
                    .frame(width: 46, height: 46)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(recoveryTitle)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        if let source = summary.source {
                            Text(source.displayName)
                                .font(AppTypography.chip)
                                .foregroundStyle(appTheme.colors.textAccent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.accentSurface, in: Capsule())
                        }
                    }

                    Text(detailText)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Text(recommendation)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let score = summary.sleepScore {
                    ZStack {
                        AnimatedMetricNumber(
                            value: displayedScore ?? Double(score),
                            suffix: "%"
                        )
                        .font(.headline.bold())
                        .foregroundStyle(appTheme.colors.textAccent)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sleep recovery score")
                    .accessibilityValue("\(score) percent")
                    .onAppear {
                        if displayedScore == nil {
                            displayedScore = Double(score)
                        }
                    }
                    .onChange(of: score) { _, newScore in
                        if reduceMotion {
                            displayedScore = Double(newScore)
                        } else {
                            withAnimation(AppMotion.animation(for: .metricChange, reduceMotion: false)) {
                                displayedScore = Double(newScore)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recoveryTitle: String {
        switch summary.recoveryState {
        case .high, .good:
            return "Sleep recovery looks good"
        case .moderate:
            return "Sleep recovery is slightly reduced"
        case .low, .veryLow:
            return "Sleep recovery may affect today"
        case .unknown:
            return "No sleep recorded last night"
        }
    }

    private var detailText: String {
        guard summary.primarySession != nil else {
            return "Add the missing overnight record, or start Sleep Mode tonight."
        }

        let quality = summary.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality"
        return "\(SleepScoringService.durationText(minutes: summary.totalSleepMinutes)) sleep · \(quality) quality"
    }
}

struct HydrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared

    @Query
    private var entries: [HydrationEntry]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @Query
    private var foodLogEntries: [FoodLogEntry]

    @Query
    private var coachCheckIns: [DailyCoachCheckIn]

    @State private var customAmount = ""
    @State private var showingCustomAmount = false
    @State private var errorText: String?
    @State private var confirmation: HydrationEntry?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var readinessScore = WarmRouteSnapshots.overallReadiness(fallback: nil)
    @State private var lastReadinessSignature: String?
    @State private var activeHydrationSwipeID: UUID?

    private let coachIntelligence = CoachIntelligenceService()
    private let service = HydrationService()
    private let settingsStore = HydrationSettingsStore()
    private let sleepSettingsStore = SleepSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let quickAmounts = [250, 500, 750]

    init() {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast

        var hydrationDescriptor = FetchDescriptor<HydrationEntry>(
            predicate: #Predicate<HydrationEntry> { $0.loggedAt >= recentCutoff },
            sortBy: [SortDescriptor(\HydrationEntry.loggedAt, order: .reverse)]
        )
        hydrationDescriptor.fetchLimit = 500
        _entries = Query(hydrationDescriptor)

        var workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 40
        _completedSessions = Query(workoutDescriptor)

        var sleepDescriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\SleepSession.createdAt, order: .reverse)]
        )
        sleepDescriptor.fetchLimit = 90
        _sleepSessions = Query(sleepDescriptor)

        var napDescriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\NapSession.startDate, order: .reverse)]
        )
        napDescriptor.fetchLimit = 60
        _napSessions = Query(napDescriptor)

        var foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate<FoodLogEntry> { $0.loggedAt >= recentCutoff },
            sortBy: [SortDescriptor(\FoodLogEntry.loggedAt, order: .reverse)]
        )
        foodDescriptor.fetchLimit = 500
        _foodLogEntries = Query(foodDescriptor)

        var checkInDescriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\DailyCoachCheckIn.date, order: .reverse)]
        )
        checkInDescriptor.fetchLimit = 30
        _coachCheckIns = Query(checkInDescriptor)
    }

    private var todayEntries: [HydrationEntry] {
        service.entries(for: .now, entries: entries)
    }

    private var summary: DailyHydrationSummary {
        service.summary(entries: entries, targetML: hydrationTargetML)
    }

    private var currentReadinessSignature: String {
        [
            signature(sleepSessions, limit: 60) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(entries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(completedSessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(foodLogEntries, limit: 160) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "\(sleepSettings.targetSleepMinutes):\(sleepSettings.recoveryCoachingEnabled):\(sleepSettings.preferredSource.rawValue)",
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    var body: some View {
        FitnessScreen {
            hydrationProgressCard

            DashboardSection(title: "Coach Context") {
                ReadinessContextCard(
                    readiness: readinessScore,
                    focus: .hydration,
                    title: "Hydration in today's readiness"
                )
            }

            DashboardSection(title: "Quick Add") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(quickAmounts, id: \.self) { amount in
                        hydrationAddButton(title: "+\(HydrationService.formatAmount(amount))", amount: amount, source: .quickAdd)
                    }
                    Button {
                        showingCustomAmount = true
                    } label: {
                        Label("Custom", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .accessibilityLabel("Add custom water amount")
                }
            }

            if let confirmation {
                FitnessCard {
                    HStack {
                        Label("Added \(HydrationService.formatAmount(confirmation.amountML))", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSuccess)
                        Spacer()
                        Button("Undo") {
                            delete(confirmation)
                        }
                        .font(AppTypography.bodyEmphasis)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            DashboardSection(title: "Today's Logs") {
                if todayEntries.isEmpty {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No water logged yet")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("Use quick add to start tracking hydration.")
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }
                } else {
                    ForEach(todayEntries) { entry in
                        HydrationLogRow(entry: entry, activeSwipeID: $activeHydrationSwipeID) {
                            delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hydration")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("hydration-screen")
        .alert("Custom amount", isPresented: $showingCustomAmount) {
            TextField("350", text: $customAmount)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                customAmount = ""
            }
            Button("Add") {
                addCustomAmount()
            }
        } message: {
            Text("Enter an amount in millilitres.")
        }
        .onAppear {
            readinessRefreshClock.start()
            sleepSettings = sleepSettingsStore.load()
            hydrationTargetML = settingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            DispatchQueue.main.async {
                refreshReadinessScore()
            }
        }
        .onChange(of: currentReadinessSignature) { _, _ in
            refreshReadinessScore()
        }
    }

    private func refreshReadinessScore(force: Bool = false) {
        let signature = currentReadinessSignature
        guard force || signature != lastReadinessSignature else { return }

        let nextReadinessScore = coachIntelligence.readiness(
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: entries,
            completedWorkouts: completedSessions,
            foodLogs: foodLogEntries,
            checkIns: coachCheckIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal
        )
        AppMotion.withoutAnimation {
            readinessScore = nextReadinessScore
            lastReadinessSignature = signature
        }
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }

    private var hydrationProgressCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Today")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text("\(HydrationService.formatAmount(summary.totalML)) / \(HydrationService.formatAmount(summary.targetML))")
                            .font(AppTypography.screenTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "drop.fill")
                        .font(AppTypography.largeMetric)
                        .foregroundStyle(appTheme.colors.textHydration)
                        .frame(width: 52, height: 52)
                        .background(appTheme.colors.hydration.opacity(0.14), in: Circle())
                }

                SwiftUI.ProgressView(value: min(1, summary.progress))
                    .tint(appTheme.colors.hydration)
                    .scaleEffect(x: 1, y: 1.35, anchor: .center)
                    .animation(AppMotion.progressFill(reduceMotion: reduceMotion), value: summary.totalML)
                    .accessibilityLabel("Hydration progress")
                    .accessibilityValue("\(HydrationService.formatAmount(summary.totalML)) out of \(HydrationService.formatAmount(summary.targetML))")

                HStack {
                    Text(progressText)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Spacer()
                    Text(statusText)
                        .font(AppTypography.chip)
                        .foregroundStyle(statusColor)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.textDanger)
                }
            }
        }
    }

    private var progressText: String {
        "\(Int(min(1.5, summary.progress) * 100))% complete"
    }

    private var statusText: String {
        switch summary.status {
        case .low:
            return "Getting started"
        case .behind:
            return "\(HydrationService.formatAmount(summary.remainingML)) remaining"
        case .onTrack:
            return "On track"
        case .complete:
            return "Target reached"
        case .aboveTarget:
            return "Above target"
        }
    }

    private var statusColor: Color {
        switch summary.status {
        case .low, .behind:
            return appTheme.colors.warning
        case .onTrack, .complete, .aboveTarget:
            return appTheme.colors.success
        }
    }

    private func hydrationAddButton(title: String, amount: Int, source: HydrationEntrySource) -> some View {
        Button {
            add(amount: amount, source: source)
        } label: {
            Label(title, systemImage: "drop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
        .accessibilityLabel("Add \(amount) millilitres of water")
    }

    private func addCustomAmount() {
        guard let amount = Int(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorText = "Enter a valid amount in millilitres."
            return
        }
        add(amount: amount, source: .manual)
        customAmount = ""
    }

    private func add(amount: Int, source: HydrationEntrySource) {
        guard amount > 0 else {
            errorText = "Amount must be greater than 0 mL."
            return
        }
        guard amount <= 2_000 else {
            errorText = "That is a large single entry. Keep one entry at 2,000 mL or less."
            return
        }

        let entry = HydrationEntry(amountML: amount, source: source, context: .general)
        modelContext.insert(entry)
        do {
            try modelContext.save()
            errorText = nil
            AppHaptics.success()
            withAnimation(AppMotion.transientConfirmation(reduceMotion: reduceMotion)) {
                confirmation = entry
            }
        } catch {
            AppHaptics.error()
            errorText = "Could not save that water entry."
        }
    }

    private func delete(_ entry: HydrationEntry) {
        var saveError: Error?
        withAnimation(AppMotion.rowCollapse(reduceMotion: reduceMotion)) {
            modelContext.delete(entry)
            do {
                try modelContext.save()
            } catch {
                saveError = error
            }
        }

        if saveError == nil {
            AppHaptics.warning()
            errorText = nil
            activeHydrationSwipeID = nil
            if confirmation?.id == entry.id {
                withAnimation(AppMotion.rowCollapse(reduceMotion: reduceMotion)) {
                    confirmation = nil
                }
            }
        } else {
            modelContext.rollback()
            AppHaptics.error()
            errorText = "Could not delete that water entry."
        }
    }
}

private struct HydrationLogRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: HydrationEntry
    @Binding var activeSwipeID: UUID?
    let delete: () -> Void

    var body: some View {
        SwipeRevealRow(id: entry.id, activeID: $activeSwipeID) {
            rowContent
        } action: {
            deleteAction
        }
        .accessibilityAction(named: "Delete Entry", delete)
        .transition(AppMotion.rowInsertRemoveTransition(reduceMotion: reduceMotion))
    }

    private var rowContent: some View {
        FitnessCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(HydrationService.formatAmount(entry.amountML))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(entry.context.displayName)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                Spacer()

                Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            delete()
        } label: {
            Image(systemName: "trash")
                .font(AppTypography.cardTitle)
                .frame(width: appTheme.metrics.swipeRevealActionSize, height: appTheme.metrics.swipeRevealActionSize)
                .foregroundStyle(.white)
                .background(appTheme.colors.danger, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete \(HydrationService.formatAmount(entry.amountML)) hydration entry")
    }

}
