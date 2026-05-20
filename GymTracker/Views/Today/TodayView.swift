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

    @State private var route: TodayRoute?
    @State private var showingRestDayConfirmation = false
    @State private var previewSplit: WorkoutPreviewSplit?

    private let decisionService = TrainingDecisionService()
    private let modePlanner = WorkoutModePlanner()

    private let weekColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var trainingDecision: TrainingDecision {
        decisionService.decision(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                    TodayDashboardSection(title: "Quick Actions") {
                        QuickActionsGrid(actions: quickActions)
                    }

                    TodayDashboardSection(title: "Nutrition") {
                        NavigationLink {
                            NutritionInsightsDashboardView()
                        } label: {
                            NutritionHomeSummaryCard()
                        }
                        .buttonStyle(.plain)
                    }

                    TodayDashboardSection(title: "Coach Insight") {
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

                    TodayDashboardSection(title: "This Week") {
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

                    TodayDashboardSection(title: "Last Workout") {
                        lastWorkoutInsight
                    }
                }
                .padding()
                .padding(.bottom, 12)
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
                title: "Rest Day",
                subtitle: "Take recovery without noise",
                systemImage: "moon.fill",
                style: .calm,
                action: { showingRestDayConfirmation = true }
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
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 42, height: 42)
                        .background(appTheme.colors.accentSurface, in: Circle())

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

private struct TodayDashboardSection<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)

            content
        }
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

    var id: Self { self }
}
