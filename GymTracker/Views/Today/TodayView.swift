import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var showingCoachCheckIn = false
    @State private var previewSplit: WorkoutPreviewSplit?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = SleepAnalyticsService.emptyReadinessSnapshot()
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var coachSnapshot = CoachIntelligenceService.emptySnapshot()
    @State private var lastCoachSnapshotSignature: String?
    @State private var todaySnapshot = TodayDashboardSnapshot.empty
    @State private var lastTodaySnapshotSignature: String?
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var didRequestInitialRefresh = false
    @State private var pendingRouteNavigation: TodayRouteNavigationStart?

    private let coachIntelligence = CoachIntelligenceService()
    private let decisionService = TrainingDecisionService()
    private let modePlanner = WorkoutModePlanner()
    private let sleepCoaching = SleepCoachingService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let hydrationService = HydrationService()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()

    private let weekColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init() {
        _activeSplits = Query(Self.activeSplitsDescriptor)
        _exercises = Query(Self.exercisesDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _unfinishedSessions = Query(Self.unfinishedSessionsDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
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
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
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
        guard lastTodaySnapshotSignature != nil else {
            return todaySnapshot
        }

        let signature = todaySnapshotSignature
        if signature == lastTodaySnapshotSignature {
            return todaySnapshot
        }

        return todaySnapshot
    }

    private var todaySnapshotSignature: String {
        let splitSignature = signature(activeSplits, limit: 12) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.exercises.count)" }
        let sessionSignature = signature(completedSessions, limit: 40) { session in
            let setSignature = session.exerciseLogs
                .flatMap(\.setLogs)
                .map { "\($0.id.uuidString):\($0.completed):\($0.isWarmup):\($0.weight):\($0.reps)" }
                .joined(separator: ",")
            return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(setSignature)"
        }
        let unfinishedSignature = signature(unfinishedSessions, limit: 5) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970)" }
        let hydrationSignature = signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
        return [
            splitSignature,
            sessionSignature,
            unfinishedSignature,
            hydrationSignature,
            String(hydrationTargetML)
        ].joined(separator: "|")
    }

    private var trainingDecision: TrainingDecision {
        currentTodaySnapshot.trainingDecision
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sleepSessions, naps: napSessions, workouts: Array(completedSessions.prefix(12)), settings: sleepSettings, sessionLimit: 45, workoutLimit: 12)
    }

    private var hydrationSummary: DailyHydrationSummary {
        currentTodaySnapshot.hydrationSummary
    }

    private var readinessScore: ReadinessScore {
        currentCoachSnapshot.readiness
    }

    private var currentSleepReadinessSnapshot: SleepWorkoutReadinessSnapshot {
        guard lastSleepReadinessSignature != nil else {
            return sleepReadinessSnapshot
        }

        let signature = currentSleepReadinessSignature
        if signature == lastSleepReadinessSignature {
            return sleepReadinessSnapshot
        }

        return sleepReadinessSnapshot
    }

    private var currentCoachSnapshot: CoachIntelligenceSnapshot {
        guard lastCoachSnapshotSignature != nil else {
            return coachSnapshot
        }

        let signature = currentCoachSnapshotSignature
        if signature == lastCoachSnapshotSignature {
            return coachSnapshot
        }

        return coachSnapshot
    }

    private var currentCoachSnapshotSignature: String {
        [
            signature(activeSplits, limit: 12) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(exercises, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(completedSessions, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            signature(sleepSessions, limit: 45) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(napSessions, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(hydrationEntries, limit: 60) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 80) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 14) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            sleepSettingsSignature,
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)"
        ].joined(separator: "|")
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
        todaySnapshot = PerformanceTracer.trace(.todaySnapshot) {
            makeTodaySnapshot()
        }
        lastTodaySnapshotSignature = signature
    }

    private func makeTodaySnapshot() -> TodayDashboardSnapshot {
        let decision = decisionService.decision(
            activeSplits: activeSplits,
            completedSessions: Array(completedSessions.prefix(40))
        )
        let recentCycleNames = makeRecentPPLCycleNames(from: completedSessions)
        let suggested = activeSplits.first { $0.name == decision.recommendedSplitName } ?? makeSuggestedSplit(recentPPLCycleNames: recentCycleNames)
        let weekSessions = makeWeeklySessions(from: completedSessions)
        let workingSets = weekSessions.reduce(0) { total, session in
            total + workingSetCount(in: session)
        }
        let coverageNames = makeSplitCoverageNames(from: activeSplits)
        let trainedNames = Set(weekSessions.map { baseSplitName($0.splitNameSnapshot) })
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
            recentPPLCycleNames: recentCycleNames,
            weeklySessions: weekSessions,
            workoutsThisWeek: weekSessions.count,
            workingSetsThisWeek: workingSets,
            volumeThisWeekText: makeVolumeThisWeekText(from: weekSessions),
            splitCoverageItems: coverageItems,
            splitCoverageNames: coverageNames,
            splitBalanceText: makeSplitBalanceText(from: coverageItems),
            splitCoverageSubtitle: makeSplitCoverageSubtitle(from: coverageItems)
        )
    }

    var body: some View {
        let intelligence = currentCoachSnapshot

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                    DashboardHeaderView(
                        dateText: todayDateText,
                        title: "Today",
                        subtitle: "Your lifting dashboard"
                    )
                    .padding(.bottom, 2)

                    HeroRecommendationCard(
                        eyebrow: "Suggested today",
                        splitName: suggestedSplit?.name ?? "Create a split",
                        reason: recommendationReason,
                        context: recommendationContext,
                        iconKey: ExerciseIconMapper.splitIconKey(for: suggestedSplit?.name ?? ""),
                        chips: heroChips,
                        primaryTitle: unfinishedSessions.isEmpty ? "Start Workout" : "Resume Workout",
                        secondaryTitle: "Preview Split",
                        isPrimaryEnabled: true,
                        isSecondaryEnabled: suggestedSplit != nil,
                        primaryAction: { openRoute(.workout) },
                        secondaryAction: previewSuggestedSplit
                    )

                    DashboardSection(title: "Daily Coach Brief") {
                        CoachBriefCard(
                            readiness: intelligence.readiness,
                            viewBrief: openCoachRoute,
                            checkIn: { showingCoachCheckIn = true }
                        )
                    }

                    DashboardSection(title: "Weekly Insight") {
                        WeeklyInsightPreviewCard(snapshot: intelligence) {
                            openCoachRoute()
                        }
                    }

                    DashboardSection(title: "Recovery") {
                        Button {
                            openRoute(.sleep)
                        } label: {
                            TodaySleepRecoveryCard(summary: sleepSummary, recommendation: todayRecoveryRecommendation)
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }

                    DashboardSection(title: "Quick Actions") {
                        QuickActionsGrid(actions: quickActions)
                    }

                    DashboardSection(title: "Nutrition") {
                        Button {
                            openRoute(.nutrition)
                        } label: {
                            NutritionHomeSummaryCard()
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }

                    DashboardSection(title: "Coach Insight") {
                        CoachInsightCard(
                            title: "Coach Insight",
                            recommendation: coachRecommendationTitle,
                            reason: trainingDecision.reason,
                            badge: trainingDecision.action.displayName,
                            buttonTitle: coachButtonTitle,
                            isButtonEnabled: trainingDecision.recommendedSplitName != nil,
                            action: previewRecommendedSplit
                        )
                    }

                    DashboardSection(title: "This Week") {
                        LazyVGrid(columns: weekColumns, spacing: 12) {
                            WeekMetricTile(
                                label: "Sessions",
                                value: "\(workoutsThisWeek)",
                                caption: "Completed workouts",
                                systemImage: "figure.strengthtraining.traditional"
                            )
                            WeekMetricTile(
                                label: "Working Sets",
                                value: "\(workingSetsThisWeek)",
                                caption: "Logged this week",
                                systemImage: "checkmark.circle"
                            )
                            WeekMetricTile(
                                label: "Volume",
                                value: volumeThisWeekText,
                                caption: "Load x reps",
                                systemImage: "scalemass"
                            )
                            WeekMetricTile(
                                label: "Split Balance",
                                value: splitBalanceText,
                                caption: "Weekly coverage",
                                systemImage: "scale.3d"
                            )
                        }

                        SplitCoverageBarView(
                            title: "Split Coverage",
                            subtitle: splitCoverageSubtitle,
                            items: splitCoverageItems
                        )
                    }

                    DashboardSection(title: "Last Workout") {
                        lastWorkoutInsight
                    }
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedRoute) { route in
                destination(for: route)
            }
            .navigationDestination(item: $previewSplit) { split in
                WorkoutPreviewView(split: split)
            }
            .alert("Rest day noted", isPresented: $showingRestDayConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Persistent rest-day logging is still on the roadmap. For now, your workout history remains unchanged.")
            }
            .sheet(isPresented: $showingCoachCheckIn) {
                DailyCheckInSheet(existingCheckIn: readinessScore.checkIn)
            }
            .onAppear {
                sleepSettings = sleepSettingsStore.load()
                hydrationTargetML = hydrationSettingsStore.dailyTargetML()
                nutritionGoal = nutritionGoalStore.loadGoal()
                let shouldForceRefresh = !didRequestInitialRefresh
                didRequestInitialRefresh = true
                refreshTodaySnapshot(force: shouldForceRefresh)
                refreshSleepReadiness()
                refreshCoachSnapshot()
            }
            .onChange(of: todaySnapshotSignature) { _, _ in
                refreshTodaySnapshot()
            }
            .onChange(of: currentSleepReadinessSignature) { _, _ in
                refreshSleepReadiness()
            }
            .onChange(of: currentCoachSnapshotSignature) { _, _ in
                refreshCoachSnapshot()
            }
        }
    }

    private var quickActions: [QuickAction] {
        [
            QuickAction(
                identifier: "quick-action-workout",
                title: unfinishedSessions.isEmpty ? "Start Workout" : "Resume Workout",
                subtitle: unfinishedSessions.isEmpty ? "Open your training flow" : "Continue the active log",
                systemImage: "figure.strengthtraining.traditional",
                style: .primary,
                action: { openRoute(.workout) }
            ),
            QuickAction(
                identifier: "quick-action-hydration",
                title: "Hydration",
                subtitle: hydrationSubtitle,
                systemImage: "drop.fill",
                style: .hydration,
                action: { openRoute(.hydration) }
            ),
            QuickAction(
                identifier: "quick-action-sleep",
                title: "Sleep",
                subtitle: "Start Sleep Mode or review recovery",
                systemImage: "moon.zzz.fill",
                style: .calm,
                action: { openRoute(.sleep) }
            ),
            QuickAction(
                identifier: "quick-action-readiness",
                title: "Readiness",
                subtitle: readinessQuickActionSubtitle,
                systemImage: "sparkles",
                style: .neutral,
                action: openCoachRoute
            ),
            QuickAction(
                identifier: "quick-action-nutrition",
                title: "Nutrition",
                subtitle: "Log food and check macros",
                systemImage: "fork.knife",
                style: .progress,
                action: { openRoute(.nutrition) }
            ),
            QuickAction(
                identifier: "quick-action-progress",
                title: "Progress & Charts",
                subtitle: "Review lifts and PRs",
                systemImage: "chart.xyaxis.line",
                style: .progress,
                action: { openRoute(.progress) }
            )
        ]
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

        pendingRouteNavigation = TodayRouteNavigationStart(route: route, startedAt: ContinuousClock.now)
        PerformanceTracer.mark(.todayRouteSelection, "\(route.analyticsName) requested")
        PerformanceTracer.mark(.todayRouteSelectionState, "before selectedRoute=\(route.analyticsName)")
        PerformanceTracer.trace(.todayRouteSelection) {
            selectedRoute = route
        }
        PerformanceTracer.mark(.todayRouteSelectionState, "after selectedRoute=\(route.analyticsName)")
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
                StartWorkoutContentView()
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
                NutritionDashboardView()
            case .sleep:
                SleepDashboardView()
            case .hydration:
                HydrationView()
            }
        }
        .background {
            if route == .coach, scenePhase == .active {
                CoachRouteFrameProbe(label: "navigationDestination.background")
            }
        }
        .onAppear {
            PerformanceTracer.mark(.todayRouteDestination, "onAppear route=\(route.analyticsName)")
            markRouteAppeared(route)
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

    private var lastWorkoutInsight: some View {
        FitnessCard {
            if let last = completedSessions.first {
                HStack(alignment: .center, spacing: 14) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: last.splitNameSnapshot),
                        size: 46,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(last.splitNameSnapshot)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Text("\(last.exerciseLogs.count) exercises - \(workingSetCount(in: last)) working sets")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "checkmark.seal.fill")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.accent)
                }
            } else {
                HStack(spacing: 12) {
                    FitnessIconBadge(systemImage: "calendar.badge.plus", size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No workouts logged yet")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Start a split to build your first dashboard summary.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            }
        }
    }

    private var todayDateText: String {
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        let date = Date.now.formatted(.dateTime.day().month(.wide))
        return "\(weekday), \(date)"
    }

    private var recommendationReason: String {
        guard let split = suggestedSplit else {
            return "Starter Push/Pull/Legs templates will appear after seed data is created."
        }

        if recentPPLCycleNames.isEmpty {
            return "Start your Push/Pull/Legs rotation with \(split.name)."
        }

        if recentPPLCycleNames.contains(split.name) {
            return "You have completed this PPL round. \(split.name) starts the next rotation."
        }

        return "\(split.name) is next because it has not been completed in your current Push/Pull/Legs rotation."
    }

    private var recommendationContext: String? {
        guard suggestedSplit != nil else {
            return "Create active templates to unlock daily training guidance."
        }

        if recentPPLCycleNames.isEmpty {
            return "Baseline week: log each split once so Peakline can calibrate targets."
        }

        if recentPPLCycleNames.count == PPLRotation.names.count {
            return "Full PPL round logged. Begin the next pass with a clean target."
        }

        let completed = recentPPLCycleNames.reversed().joined(separator: " / ")
        return "Current round logged: \(completed)."
    }

    private var heroChips: [DashboardChip] {
        guard let split = suggestedSplit else {
            return [DashboardChip("Setup needed", systemImage: "plus.circle")]
        }

        return [
            DashboardChip("\(split.exercises.count) exercises", systemImage: "list.bullet"),
            DashboardChip(estimatedDurationText(for: split), systemImage: "clock"),
            DashboardChip("\(trainingDecision.recommendedMode.displayName) Mode", systemImage: trainingDecision.recommendedMode.systemImage),
            DashboardChip(rotationChipText, systemImage: "arrow.triangle.2.circlepath")
        ]
    }

    private var rotationChipText: String {
        guard !recentPPLCycleNames.isEmpty else { return "First Round" }
        return recentPPLCycleNames.count == PPLRotation.names.count ? "Next Rotation" : "In Rotation"
    }

    private var coachRecommendationTitle: String {
        "Next: \(trainingDecision.recommendedSplitName ?? "Any split") - \(trainingDecision.recommendedMode.displayName)"
    }

    private var coachButtonTitle: String {
        guard let splitName = trainingDecision.recommendedSplitName else { return "See Recommendation" }
        return "Preview \(splitName)"
    }

    private var sleepSummary: SleepSummary {
        currentSleepReadinessSnapshot.latestSummary
    }

    private var todayRecoveryRecommendation: String {
        currentSleepReadinessSnapshot.adaptiveRecommendation?.message ?? sleepCoaching.recommendation(for: sleepSummary, settings: sleepSettings)
    }

    private var readinessQuickActionSubtitle: String {
        guard lastCoachSnapshotSignature != nil else {
            return "Preparing coach brief"
        }

        return "\(readinessScore.value) - \(readinessScore.category.displayName)"
    }

    private var coachNavigationSnapshot: CoachIntelligenceSnapshot? {
        lastCoachSnapshotSignature == nil ? nil : coachSnapshot
    }

    private func refreshSleepReadiness(force: Bool = false) {
        let signature = currentSleepReadinessSignature
        guard force || signature != lastSleepReadinessSignature else { return }

        sleepReadinessSnapshot = PerformanceTracer.trace(.todaySleepReadiness) {
            sleepReadinessStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedSessions.prefix(12)),
                settings: sleepSettings,
                force: force
            )
        }
        lastSleepReadinessSignature = signature
    }

    private func refreshCoachSnapshot(force: Bool = false) {
        let signature = currentCoachSnapshotSignature
        guard force || signature != lastCoachSnapshotSignature else { return }

        coachSnapshot = makeCoachSnapshot()
        lastCoachSnapshotSignature = signature
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
        CoachRouteSnapshotStore.shared.update(snapshot: coachSnapshot, signature: signature, source: "today")
        PerformanceTracer.mark(
            .coachSnapshot,
            "route_snapshot_store after_update source=today scenePhase=\(String(describing: scenePhase)) main=\(Thread.isMainThread)"
        )
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
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
    }

    private var pplOrderedSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
    }

    private var recentPPLCycleNames: [String] {
        currentTodaySnapshot.recentPPLCycleNames
    }

    private func makeRecentPPLCycleNames(from sessions: [WorkoutSession]) -> [String] {
        var names: [String] = []

        for session in sessions {
            guard let name = pplName(for: session.splitNameSnapshot) else { continue }

            if names.contains(name) {
                break
            }

            names.append(name)

            if names.count == PPLRotation.names.count {
                break
            }
        }

        return names
    }

    private func makeSuggestedSplit(recentPPLCycleNames: [String]) -> TrainingSplit? {
        let orderedSplits = pplOrderedSplits
        guard !orderedSplits.isEmpty else { return activeSplits.first }

        let completedNames = Set(recentPPLCycleNames)
        if let missingSplit = orderedSplits.first(where: { !completedNames.contains($0.name) }) {
            return missingSplit
        }

        guard
            let mostRecentName = completedSessions.compactMap({ pplName(for: $0.splitNameSnapshot) }).first,
            let mostRecentIndex = PPLRotation.names.firstIndex(of: mostRecentName)
        else {
            return orderedSplits.first
        }

        let nextName = PPLRotation.names[(mostRecentIndex + 1) % PPLRotation.names.count]
        return orderedSplits.first { $0.name == nextName } ?? orderedSplits.first
    }

    private func pplName(for splitNameSnapshot: String) -> String? {
        PPLRotation.names.first { name in
            splitNameSnapshot == name || splitNameSnapshot.hasPrefix("\(name) - ")
        }
    }

    private var weeklySessions: [WorkoutSession] {
        currentTodaySnapshot.weeklySessions
    }

    private func makeWeeklySessions(from sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
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

    private func makeVolumeThisWeekText(from sessions: [WorkoutSession]) -> String {
        let volume = sessions.reduce(0) { total, session in
            total + session.exerciseLogs
                .flatMap(\.setLogs)
                .filter { $0.completed && !$0.isWarmup }
                .reduce(0) { setTotal, set in
                    setTotal + (set.weight * Double(set.reps))
                }
        }

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
        let activePPLNames = PPLRotation.names.filter { name in
            splits.contains { $0.name == name }
        }

        if !activePPLNames.isEmpty {
            return activePPLNames
        }

        return Array(splits.map(\.name).prefix(3))
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

    private func estimatedDurationText(for split: TrainingSplit) -> String {
        let selectable = split.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(WorkoutSelectableExercise.init)
        let planned = modePlanner.plannedExercises(from: selectable, mode: trainingDecision.recommendedMode)
        let duration = modePlanner.estimatedDurationMinutes(for: planned, mode: trainingDecision.recommendedMode)
        return "~\(duration.lowerBound)-\(duration.upperBound)m"
    }

    private func workingSetCount(in session: WorkoutSession) -> Int {
        session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }

    private func previewSuggestedSplit() {
        guard let suggestedSplit else { return }
        openPreview(WorkoutPreviewSplit(suggestedSplit))
    }

    private func previewRecommendedSplit() {
        guard
            let splitName = trainingDecision.recommendedSplitName,
            let split = activeSplits.first(where: { $0.name == splitName })
        else { return }

        openPreview(WorkoutPreviewSplit(split))
    }

    private func openPreview(_ split: WorkoutPreviewSplit) {
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation request source=today split=\(split.id.uuidString) active=\(previewSplit?.id.uuidString ?? "none")")
        guard previewSplit?.id != split.id else {
            PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation skip source=today already_active split=\(split.id.uuidString)")
            return
        }

        AppMotion.smoothNavigate(reduceMotion: reduceMotion) {
            previewSplit = split
        }
    }
}

private struct TodayDashboardSnapshot {
    let trainingDecision: TrainingDecision
    let hydrationSummary: DailyHydrationSummary
    let suggestedSplit: TrainingSplit?
    let recentPPLCycleNames: [String]
    let weeklySessions: [WorkoutSession]
    let workoutsThisWeek: Int
    let workingSetsThisWeek: Int
    let volumeThisWeekText: String
    let splitCoverageItems: [SplitCoverageItem]
    let splitCoverageNames: [String]
    let splitBalanceText: String
    let splitCoverageSubtitle: String

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
        recentPPLCycleNames: [],
        weeklySessions: [],
        workoutsThisWeek: 0,
        workingSetsThisWeek: 0,
        volumeThisWeekText: "0",
        splitCoverageItems: [],
        splitCoverageNames: [],
        splitBalanceText: "0/0",
        splitCoverageSubtitle: "Create active splits to track weekly coverage."
    )
}

private enum PPLRotation {
    static let names = ["Push", "Pull", "Legs"]
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
}

private struct TodayRouteNavigationStart {
    let route: TodayRoute
    let startedAt: ContinuousClock.Instant
}

private struct TodaySleepRecoveryCard: View {
    @Environment(\.appTheme) private var appTheme

    let summary: SleepSummary
    let recommendation: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 46, height: 46)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(recoveryTitle)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        if let source = summary.source {
                            Text(source.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.accentSurface, in: Capsule())
                        }
                    }

                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Text(recommendation)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let score = summary.sleepScore {
                    Text("\(score)%")
                        .font(.headline.bold())
                        .foregroundStyle(appTheme.colors.accent)
                }
            }
        }
    }

    private var recoveryTitle: String {
        switch summary.recoveryState {
        case .high, .good:
            return "Recovery looks good"
        case .moderate:
            return "Recovery is slightly reduced"
        case .low, .veryLow:
            return "Sleep may affect today"
        case .unknown:
            return "No sleep data yet"
        }
    }

    private var detailText: String {
        guard summary.primarySession != nil else {
            return "Start Sleep Mode tonight to improve recovery coaching."
        }

        let quality = summary.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality"
        return "\(SleepScoringService.durationText(minutes: summary.totalSleepMinutes)) sleep - \(quality) quality"
    }
}

struct HydrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \HydrationEntry.loggedAt, order: .reverse)
    private var entries: [HydrationEntry]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sleepSessions: [SleepSession]

    @Query(sort: \NapSession.startDate, order: .reverse)
    private var napSessions: [NapSession]

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var foodLogEntries: [FoodLogEntry]

    @Query(sort: \DailyCoachCheckIn.date, order: .reverse)
    private var coachCheckIns: [DailyCoachCheckIn]

    @State private var customAmount = ""
    @State private var showingCustomAmount = false
    @State private var errorText: String?
    @State private var confirmation: HydrationEntry?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var readinessScore = CoachIntelligenceService.emptySnapshot().readiness
    @State private var lastReadinessSignature: String?

    private let coachIntelligence = CoachIntelligenceService()
    private let service = HydrationService()
    private let settingsStore = HydrationSettingsStore()
    private let sleepSettingsStore = SleepSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let quickAmounts = [250, 500, 750]

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
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)"
        ].joined(separator: "|")
    }

    var body: some View {
        FitnessScreen(
            title: "Hydration",
            subtitle: "Track your water intake for training and recovery.",
            systemImage: "drop.fill"
        ) {
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
                    hydrationAddButton(title: "Bottle", amount: 750, source: .preset)
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.success)
                        Spacer()
                        Button("Undo") {
                            delete(confirmation)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            DashboardSection(title: "Today's Logs") {
                if todayEntries.isEmpty {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No water logged yet")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("Use quick add to start tracking hydration.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }
                } else {
                    ForEach(todayEntries) { entry in
                        HydrationLogRow(entry: entry) {
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

        readinessScore = coachIntelligence.readiness(
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
        lastReadinessSignature = signature
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
                        .foregroundStyle(appTheme.colors.hydration)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Spacer()
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.danger)
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
            errorText = "Amount must be greater than 0ml."
            return
        }
        guard amount <= 2_000 else {
            errorText = "That is a large single entry. Keep one entry at 2000ml or less."
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
        modelContext.delete(entry)
        do {
            try modelContext.save()
            AppHaptics.warning()
            if confirmation?.id == entry.id {
                withAnimation(AppMotion.gentleFade(reduceMotion: reduceMotion)) {
                    confirmation = nil
                }
            }
        } catch {
            AppHaptics.error()
            errorText = "Could not delete that water entry."
        }
    }
}

private struct HydrationLogRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: HydrationEntry
    let delete: () -> Void

    @State private var horizontalOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDraggingHorizontally = false

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .padding(.trailing, appTheme.metrics.swipeRevealActionTrailingPadding)
                .opacity(deleteRevealProgress)

            rowContent
                .offset(x: horizontalOffset)
                .simultaneousGesture(swipeGesture)
                .onTapGesture {
                    guard horizontalOffset != 0 else { return }
                    closeSwipe()
                }
        }
        .accessibilityAction(named: "Delete Entry", delete)
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

    private var deleteRevealWidth: CGFloat {
        appTheme.metrics.swipeRevealWidth
    }

    private var deleteRevealProgress: CGFloat {
        min(1, abs(horizontalOffset) / deleteRevealWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if !isDraggingHorizontally {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isDraggingHorizontally = true
                    dragStartOffset = horizontalOffset
                }

                guard isDraggingHorizontally else { return }
                horizontalOffset = clampedOffset(dragStartOffset + value.translation.width)
            }
            .onEnded { value in
                defer {
                    isDraggingHorizontally = false
                    dragStartOffset = horizontalOffset
                }

                guard abs(value.translation.width) > abs(value.translation.height) else {
                    closeSwipe()
                    return
                }

                let projectedOffset = dragStartOffset + value.predictedEndTranslation.width
                let shouldOpen = projectedOffset < -(deleteRevealWidth * 0.45) || value.translation.width < -36

                withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
                    horizontalOffset = shouldOpen ? -deleteRevealWidth : 0
                }
            }
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-deleteRevealWidth, offset))
    }

    private func closeSwipe() {
        withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
            horizontalOffset = 0
        }
    }
}
