import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @Query(filter: #Predicate<WorkoutSession> { !$0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var unfinishedSessions: [WorkoutSession]

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sleepSessions: [SleepSession]

    @Query(sort: \NapSession.startDate, order: .reverse)
    private var napSessions: [NapSession]

    @Query(sort: \HydrationEntry.loggedAt, order: .reverse)
    private var hydrationEntries: [HydrationEntry]

    @State private var route: TodayRoute?
    @State private var showingRestDayConfirmation = false
    @State private var previewSplit: WorkoutPreviewSplit?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = SleepAnalyticsService.emptyReadinessSnapshot()
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?

    private let decisionService = TrainingDecisionService()
    private let modePlanner = WorkoutModePlanner()
    private let sleepCoaching = SleepCoachingService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let hydrationService = HydrationService()
    private let hydrationSettingsStore = HydrationSettingsStore()

    private let weekColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var trainingDecision: TrainingDecision {
        decisionService.decision(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sleepSessions, naps: napSessions, workouts: completedSessions, settings: sleepSettings, sessionLimit: 45, workoutLimit: 12)
    }

    private var hydrationSummary: DailyHydrationSummary {
        hydrationService.summary(
            entries: hydrationEntries,
            targetML: hydrationSettingsStore.dailyTargetML()
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
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
                        primaryAction: { route = .workout },
                        secondaryAction: previewSuggestedSplit
                    )

                    DashboardSection(title: "Recovery") {
                        NavigationLink {
                            SleepDashboardView()
                        } label: {
                            TodaySleepRecoveryCard(summary: sleepSummary, recommendation: todayRecoveryRecommendation)
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }

                    DashboardSection(title: "Quick Actions") {
                        QuickActionsGrid(actions: quickActions)
                    }

                    DashboardSection(title: "Nutrition") {
                        NavigationLink {
                            NutritionInsightsDashboardView()
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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { route in
                switch route {
                case .workout:
                    StartWorkoutContentView()
                case .coach:
                    CoachContentView()
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
            .navigationDestination(item: $previewSplit) { split in
                WorkoutPreviewView(split: split)
            }
            .alert("Rest day noted", isPresented: $showingRestDayConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Persistent rest-day logging is still on the roadmap. For now, your workout history remains unchanged.")
            }
            .onAppear {
                sleepSettings = sleepSettingsStore.load()
                refreshSleepReadiness(force: true)
            }
            .onChange(of: currentSleepReadinessSignature) { _, _ in
                refreshSleepReadiness()
            }
        }
    }

    private var quickActions: [QuickAction] {
        [
            QuickAction(
                title: unfinishedSessions.isEmpty ? "Start Workout" : "Resume Workout",
                subtitle: unfinishedSessions.isEmpty ? "Open your training flow" : "Continue the active log",
                systemImage: "figure.strengthtraining.traditional",
                style: .primary,
                action: { route = .workout }
            ),
            QuickAction(
                title: "Hydration",
                subtitle: hydrationSubtitle,
                systemImage: "drop.fill",
                style: .hydration,
                action: { route = .hydration }
            ),
            QuickAction(
                title: "Sleep",
                subtitle: "Start Sleep Mode or review recovery",
                systemImage: "moon.zzz.fill",
                style: .calm,
                action: { route = .sleep }
            ),
            QuickAction(
                title: "Coach Check-In",
                subtitle: "Read targets and warnings",
                systemImage: "sparkles",
                style: .neutral,
                action: { route = .coach }
            ),
            QuickAction(
                title: "Nutrition",
                subtitle: "Log food and check macros",
                systemImage: "fork.knife",
                style: .progress,
                action: { route = .nutrition }
            ),
            QuickAction(
                title: "Progress & Charts",
                subtitle: "Review lifts and PRs",
                systemImage: "chart.xyaxis.line",
                style: .progress,
                action: { route = .progress }
            )
        ]
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
                            .font(.title3.bold())
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Text("\(last.exerciseLogs.count) exercises - \(workingSetCount(in: last)) working sets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3.weight(.semibold))
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
        sleepReadinessSnapshot.latestSummary
    }

    private var todayRecoveryRecommendation: String {
        sleepReadinessSnapshot.adaptiveRecommendation?.message ?? sleepCoaching.recommendation(for: sleepSummary, settings: sleepSettings)
    }

    private func refreshSleepReadiness(force: Bool = false) {
        let signature = currentSleepReadinessSignature
        guard force || signature != lastSleepReadinessSignature else { return }

        sleepReadinessSnapshot = sleepReadinessStore.snapshot(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: completedSessions,
            settings: sleepSettings,
            force: force
        )
        lastSleepReadinessSignature = signature
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

    private var pplOrderedSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            activeSplits.first { $0.name == name }
        }
    }

    private var recentPPLCycleNames: [String] {
        var names: [String] = []

        for session in completedSessions {
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

    private func pplName(for splitNameSnapshot: String) -> String? {
        PPLRotation.names.first { name in
            splitNameSnapshot == name || splitNameSnapshot.hasPrefix("\(name) - ")
        }
    }

    private var weeklySessions: [WorkoutSession] {
        completedSessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    private var workoutsThisWeek: Int {
        weeklySessions.count
    }

    private var workingSetsThisWeek: Int {
        weeklySessions.reduce(0) { total, session in
            total + workingSetCount(in: session)
        }
    }

    private var volumeThisWeekText: String {
        let volume = weeklySessions.reduce(0) { total, session in
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
        let names = splitCoverageNames
        let trainedNames = Set(weeklySessions.map { baseSplitName($0.splitNameSnapshot) })

        return names.map { name in
            SplitCoverageItem(name: name, isComplete: trainedNames.contains(name))
        }
    }

    private var splitCoverageNames: [String] {
        let activePPLNames = PPLRotation.names.filter { name in
            activeSplits.contains { $0.name == name }
        }

        if !activePPLNames.isEmpty {
            return activePPLNames
        }

        return Array(activeSplits.map(\.name).prefix(3))
    }

    private var splitBalanceText: String {
        guard !splitCoverageItems.isEmpty else { return "0/0" }
        return "\(splitCoverageItems.filter(\.isComplete).count)/\(splitCoverageItems.count)"
    }

    private var splitCoverageSubtitle: String {
        guard !splitCoverageItems.isEmpty else {
            return "Create active splits to track weekly coverage."
        }

        if splitCoverageItems.allSatisfy(\.isComplete) {
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
        previewSplit = WorkoutPreviewSplit(suggestedSplit)
    }

    private func previewRecommendedSplit() {
        guard
            let splitName = trainingDecision.recommendedSplitName,
            let split = activeSplits.first(where: { $0.name == splitName })
        else { return }

        previewSplit = WorkoutPreviewSplit(split)
    }
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
}

private struct TodaySleepRecoveryCard: View {
    @Environment(\.appTheme) private var appTheme

    let summary: SleepSummary
    let recommendation: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 46, height: 46)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(recoveryTitle)
                            .font(.headline)
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

    @State private var customAmount = ""
    @State private var showingCustomAmount = false
    @State private var errorText: String?
    @State private var confirmation: HydrationEntry?

    private let service = HydrationService()
    private let settingsStore = HydrationSettingsStore()
    private let quickAmounts = [250, 500, 750]

    private var todayEntries: [HydrationEntry] {
        service.entries(for: .now, entries: entries)
    }

    private var summary: DailyHydrationSummary {
        service.summary(entries: entries, targetML: settingsStore.dailyTargetML())
    }

    var body: some View {
        FitnessScreen(
            title: "Hydration",
            subtitle: "Track your water intake for training and recovery.",
            systemImage: "drop.fill"
        ) {
            hydrationProgressCard

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
    }

    private var hydrationProgressCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text("\(HydrationService.formatAmount(summary.totalML)) / \(HydrationService.formatAmount(summary.targetML))")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "drop.fill")
                        .font(.title2.weight(.semibold))
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
            withAnimation(AppMotion.transientConfirmation(reduceMotion: reduceMotion)) {
                confirmation = entry
            }
        } catch {
            errorText = "Could not save that water entry."
        }
    }

    private func delete(_ entry: HydrationEntry) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
            if confirmation?.id == entry.id {
                withAnimation(AppMotion.gentleFade(reduceMotion: reduceMotion)) {
                    confirmation = nil
                }
            }
        } catch {
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
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(entry.context.displayName)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                Spacer()

                Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var deleteAction: some View {
        Button(role: .destructive, action: delete) {
            Image(systemName: "trash")
                .font(.title3.weight(.semibold))
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
