import SwiftData
import SwiftUI

struct HistoryWorkoutSnapshot: Hashable, Sendable {
    struct Exercise: Hashable, Sendable {
        struct SetEntry: Hashable, Sendable {
            let completed: Bool
            let weight: Double
            let reps: Int
            let rpe: Double?
        }

        let name: String
        let orderIndex: Int
        let sets: [SetEntry]
    }

    let id: UUID
    let date: Date
    let splitName: String
    let startedAt: Date?
    let endedAt: Date?
    let durationMinutes: Int?
    let durationSeconds: Int?
    let accumulatedPausedSeconds: Int
    let rating: Int?
    let notes: String?
    let exercises: [Exercise]

    @MainActor
    init(_ session: WorkoutSession) {
        id = session.id
        date = session.date
        splitName = session.splitNameSnapshot
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationMinutes = session.durationMinutes
        durationSeconds = session.durationSeconds
        accumulatedPausedSeconds = session.accumulatedPausedSeconds
        rating = session.perceivedDifficulty
        notes = session.notes
        exercises = session.exerciseLogs.map { log in
            Exercise(
                name: log.exerciseNameSnapshot,
                orderIndex: log.orderIndex,
                sets: log.setLogs.map {
                    Exercise.SetEntry(
                        completed: $0.completed,
                        weight: $0.weight,
                        reps: $0.reps,
                        rpe: $0.rpe
                    )
                }
            )
        }
    }
}

struct HistoryWarmSnapshot: Sendable {
    let workouts: [HistoryWorkoutSnapshot]
    let display: HistoryDisplaySnapshot

    static let empty = HistoryWarmSnapshot(workouts: [], display: .empty)
}


private struct HistoryLazyScreen<Content: View>: View {
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

struct HistoryView: View {
    @Environment(\.appTheme) private var appTheme
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @Query
    private var sessions: [WorkoutSession]

    @Query
    private var profiles: [UserProfile]

    @State private var displayedMonth = Date()
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: .now)
    @State private var filters = HistoryFilters()
    @State private var useDateRange = false
    @State private var showingFilters = false
    @State private var selectedWorkoutDetailRoute: HistoryWorkoutDetailRoute?
    @State private var displaySnapshot = HistoryDisplaySnapshot.empty
    @State private var workoutSnapshots: [HistoryWorkoutSnapshot] = []
    @State private var lastSessionGeneration = ""
    @State private var didRequestInitialRefresh = false
    @State private var displaySnapshotReady = false
    @State private var historyScrollActive = false
    @State private var historyRefreshPending = false
    @State private var isWorkoutCompletionPresentationActive = false
    @State private var isHistoryVisible = false
    @State private var isCalendarVisible = false
    @State private var showsHistoryRows = false
    @State private var calendarRevealTask: Task<Void, Never>?
    @State private var sourceSnapshotRefreshTask: Task<Void, Never>?
    @State private var showingGoalEditor = false
    @State private var hasWarmSnapshotToValidate = false

    private let initialWarmSnapshot: HistoryWarmSnapshot?

    init(startupSnapshot: HistoryWarmSnapshot? = nil) {
        _sessions = Query(Self.sessionsDescriptor)
        _profiles = Query(Self.profileDescriptor)
        initialWarmSnapshot = startupSnapshot
        _displaySnapshot = State(initialValue: startupSnapshot?.display ?? .empty)
        _workoutSnapshots = State(initialValue: startupSnapshot?.workouts ?? [])
        // Defer the 120-workout generation string until the post-frame refresh;
        // RootTabContainer recreates every tab value during selection.
        _lastSessionGeneration = State(initialValue: "")
        _displaySnapshotReady = State(initialValue: startupSnapshot != nil)
        _hasWarmSnapshotToValidate = State(initialValue: startupSnapshot != nil)
    }

    private static var sessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var profileDescriptor: FetchDescriptor<UserProfile> {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var currentDisplaySnapshot: HistoryDisplaySnapshot {
        displaySnapshot
    }

    private var sessionGeneration: String {
        Self.liveSourceGeneration(
            for: sessions,
            revision: workoutWarmStartInvalidation.revision
        )
    }

    private var profileGoalGeneration: String {
        guard let profile = profiles.first else { return "missing" }
        return "\(profile.id.uuidString):\(profile.trainingDaysPerWeek)"
    }

    private var sessionGenerationForObservation: String? {
        isWorkoutCompletionPresentationActive || !isHistoryVisible ? nil : sessionGeneration
    }

    private static func liveSourceGeneration(
        for sessions: [WorkoutSession],
        revision: Int
    ) -> String {
        [
            "revision:\(revision)",
            sessions.prefix(120).map { session in
                "\(session.id.uuidString):\(session.splitNameSnapshot):\(session.date.timeIntervalSince1970):\(session.perceivedDifficulty ?? 0):\(session.durationSeconds ?? 0):\(session.durationMinutes ?? 0):\(session.endedAt?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: "|")
        ].joined(separator: "|")
    }

    private static func warmSourceGeneration(
        for workouts: [HistoryWorkoutSnapshot],
        revision: Int
    ) -> String {
        [
            "revision:\(revision)",
            workouts.prefix(120).map { workout in
                "\(workout.id.uuidString):\(workout.splitName):\(workout.date.timeIntervalSince1970):\(workout.rating ?? 0):\(workout.durationSeconds ?? 0):\(workout.durationMinutes ?? 0):\(workout.endedAt?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: "|")
        ].joined(separator: "|")
    }

    private var sessionRows: [HistorySessionRowSnapshot] {
        currentDisplaySnapshot.sessionRows
    }

    private var calendarDaySummaries: [HistoryCalendarDaySummary] {
        currentDisplaySnapshot.calendarDaySummaries
    }

    private var splitOptions: [String] {
        currentDisplaySnapshot.splitOptions
    }

    var body: some View {
        NavigationStack {
            HistoryLazyScreen {
                HistoryOverviewCard(snapshot: currentDisplaySnapshot.overview) {
                    openGoalEditor()
                }

                if isCalendarVisible {
                    FitnessCard(style: .compact, padding: 12) {
                        WorkoutCalendarView(
                            displayedMonth: $displayedMonth,
                            selectedDate: $selectedCalendarDate,
                            daySummaries: calendarDaySummaries
                        )
                    }
                    .accessibilityIdentifier("history-calendar-card")
                }

                filterChips

                if sessionRows.isEmpty {
                    DashboardEmptyStateCard(
                        title: displaySnapshotReady ? (sessions.isEmpty ? "No workouts logged yet" : "No matching workouts") : "Loading history",
                        message: displaySnapshotReady ? (sessions.isEmpty ? "Start Push, Pull, or Legs to build your first training history." : "Adjust filters to see more sessions.") : "Preparing recent sessions and filters.",
                        systemImage: displaySnapshotReady ? "clock" : "hourglass"
                    )
                } else if showsHistoryRows {
                    ForEach(sessionRows) { row in
                        Button {
                            PerformanceTracer.mark(.motionHistoryRowOpen, "session=\(row.id.uuidString)")
                            NavigationInteraction.perform(
                                key: "history.session.\(row.id.uuidString)",
                                destinationClass: .deep,
                                haptic: .selection
                            ) {
                                selectedWorkoutDetailRoute = HistoryWorkoutDetailRoute(sessionID: row.id)
                            }
                        } label: {
                            HistoryScrollRowSurface {
                                HistorySessionRowCard(row: row)
                            }
                        }
                        .buttonStyle(HistoryScrollRowButtonStyle())
                        .accessibilityIdentifier("history-session-row")
                    }
                } else {
                    DashboardEmptyStateCard(
                        title: "Loading history",
                        message: "Preparing recent sessions and filters.",
                        systemImage: "hourglass"
                    )
                }
            }
            .accessibilityIdentifier("history-screen")
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        guard !historyScrollActive else { return }
                        historyScrollActive = true
                        PerformanceTracer.mark(.historyScroll, "begin")
                    }
                    .onEnded { _ in
                        guard historyScrollActive else { return }
                        historyScrollActive = false
                        PerformanceTracer.mark(.historyScroll, "end")
                        if historyRefreshPending {
                            historyRefreshPending = false
                            scheduleSourceSnapshotRefresh()
                        }
                    }
            )
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingFilters) {
                filterSheet
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingGoalEditor) {
                HistoryTrainingGoalSheet(profile: profiles.first)
                    .presentationDetents([.medium])
            }
            .navigationDestination(item: $selectedWorkoutDetailRoute) { route in
                WorkoutHistoryDetailRouteView(sessionID: route.sessionID)
                    .onAppear {
                        NavigationInteraction.destinationDidAppear(
                            key: "history.session.\(route.sessionID.uuidString)"
                        )
                    }
            }
        }
        .onAppear {
            isHistoryVisible = true
            calendarRevealTask?.cancel()
            calendarRevealTask = Task { @MainActor in
                // Let the root tab's insertion turn and stable-frame marker
                // finish before mounting the calendar's date grid.
                await Task.yield()
                await Task.yield()
                await Task.yield()
                guard !Task.isCancelled, isHistoryVisible else { return }
                isCalendarVisible = true
                showsHistoryRows = true
                calendarRevealTask = nil
            }
            showsHistoryRows = false
            let shouldForceRefresh = !didRequestInitialRefresh
            didRequestInitialRefresh = true
            scheduleSourceSnapshotRefresh(force: shouldForceRefresh && initialWarmSnapshot == nil)
        }
        .onChange(of: sessionGenerationForObservation) { _, generation in
            guard generation != nil else { return }
            scheduleSourceSnapshotRefresh()
        }
        .onChange(of: selectedWorkoutDetailRoute) { oldRoute, newRoute in
            guard oldRoute != nil, newRoute == nil else { return }
            scheduleSourceSnapshotRefresh(force: true)
        }
        .onChange(of: filters) { _, _ in
            refreshDisplaySnapshot()
        }
        .onChange(of: profileGoalGeneration) { _, _ in
            refreshDisplaySnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
            isWorkoutCompletionPresentationActive = true
            PerformanceTracer.mark(.workoutLoggerFinish, "history_refresh_suspended")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
            isWorkoutCompletionPresentationActive = false
            PerformanceTracer.mark(.workoutLoggerFinish, "history_refresh_resumed")
        }
        .onDisappear {
            isHistoryVisible = false
            calendarRevealTask?.cancel()
            calendarRevealTask = nil
            isCalendarVisible = false
            showsHistoryRows = false
            sourceSnapshotRefreshTask?.cancel()
            sourceSnapshotRefreshTask = nil
        }
    }

    private func scheduleSourceSnapshotRefresh(force: Bool = false) {
        guard !historyScrollActive else {
            historyRefreshPending = true
            return
        }
        sourceSnapshotRefreshTask?.cancel()
        sourceSnapshotRefreshTask = Task { @MainActor in
            // Let the root stable-frame marker complete before materialising up
            // to 120 history projections and rebuilding the display snapshot.
            await Task.yield()
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled, isHistoryVisible else { return }
            guard !historyScrollActive else {
                historyRefreshPending = true
                sourceSnapshotRefreshTask = nil
                return
            }
            refreshSourceSnapshots(force: force)
            sourceSnapshotRefreshTask = nil
        }
    }

    private func refreshSourceSnapshots(force: Bool = false) {
        let generation = sessionGeneration

        if hasWarmSnapshotToValidate {
            hasWarmSnapshotToValidate = false
            if !force,
               let initialWarmSnapshot,
               generation == Self.warmSourceGeneration(
                   for: initialWarmSnapshot.workouts,
                   revision: workoutWarmStartInvalidation.revision
               ) {
                lastSessionGeneration = generation
                return
            }
        }

        guard force || generation != lastSessionGeneration else { return }
        workoutSnapshots = sessions.prefix(120).map(HistoryWorkoutSnapshot.init)
        lastSessionGeneration = generation
        refreshDisplaySnapshot()
    }

    private func refreshDisplaySnapshot() {
        let nextSnapshot = PerformanceTracer.trace(.historyDisplaySnapshot) {
            HistoryDisplaySnapshotBuilder.build(
                workouts: workoutSnapshots,
                filters: filters,
                trainingDaysPerWeek: profiles.first?.trainingDaysPerWeek
            )
        }
        AppMotion.withoutAnimation {
            displaySnapshot = nextSnapshot
            displaySnapshotReady = true
        }
    }

    private func openGoalEditor() {
        showingGoalEditor = true
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip("All", systemImage: "line.3.horizontal.decrease.circle", isSelected: !filters.isActive) {
                    filters = HistoryFilters()
                    useDateRange = false
                }

                ForEach(splitOptions.prefix(4), id: \.self) { splitName in
                    FilterChip(splitName, isSelected: filters.splitName == splitName) {
                        filters.splitName = filters.splitName == splitName ? nil : splitName
                    }
                }

                FilterChip(ratingChipTitle, systemImage: "star", isSelected: filters.minimumRating != nil) {
                    showingFilters = true
                }

                FilterChip(exerciseChipTitle, systemImage: "magnifyingglass", isSelected: !filters.exerciseNameQuery.isEmpty) {
                    showingFilters = true
                }

                FilterChip("Date", systemImage: "calendar", isSelected: useDateRange) {
                    showingFilters = true
                }

                if filters.isActive {
                    FilterChip("Clear", systemImage: "xmark", isSelected: false) {
                        filters = HistoryFilters()
                        useDateRange = false
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("history-filter-chips")
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Split")
                                .font(AppTypography.sectionTitle)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
                                FilterChip("All", isSelected: filters.splitName == nil) {
                                    filters.splitName = nil
                                }
                                ForEach(splitOptions, id: \.self) { splitName in
                                    FilterChip(splitName, isSelected: filters.splitName == splitName) {
                                        filters.splitName = splitName
                                    }
                                }
                            }
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercise")
                                .font(AppTypography.sectionTitle)

                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(appTheme.colors.textTertiary)
                                TextField("Exercise name", text: $filters.exerciseNameQuery)
                                    .textInputAutocapitalization(.words)
                            }
                            .padding(12)
                            .background(appTheme.elevatedCardBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous))
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Rating")
                                .font(AppTypography.sectionTitle)

                            HStack(spacing: 8) {
                                FilterChip("Any", isSelected: filters.minimumRating == nil) {
                                    filters.minimumRating = nil
                                }
                                ForEach([3, 4, 5], id: \.self) { rating in
                                    FilterChip(rating == 5 ? "5" : "\(rating)+", systemImage: "star.fill", isSelected: filters.minimumRating == rating) {
                                        filters.minimumRating = rating
                                    }
                                }
                            }
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Date range", isOn: $useDateRange)
                                .tint(appTheme.colors.accent)
                                .onChange(of: useDateRange) { _, enabled in
                                    updateDateRange(enabled: enabled)
                                }

                            if useDateRange {
                                DatePicker("From", selection: startDateBinding, displayedComponents: .date)
                                DatePicker("To", selection: endDateBinding, displayedComponents: .date)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .peaklineKeyboardDismissal()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filters = HistoryFilters()
                        useDateRange = false
                    }
                    .disabled(!filters.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingFilters = false
                    }
                }
            }
        }
    }

    private var ratingChipTitle: String {
        guard let minimumRating = filters.minimumRating else { return "Rating" }
        return minimumRating == 5 ? "5" : "\(minimumRating)+"
    }

    private var exerciseChipTitle: String {
        filters.exerciseNameQuery.isEmpty ? "Exercise" : filters.exerciseNameQuery
    }

    private func updateDateRange(enabled: Bool) {
        if enabled {
            filters.startDate = filters.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)
            filters.endDate = filters.endDate ?? .now
        } else {
            filters.startDate = nil
            filters.endDate = nil
        }
    }

    private var splitFilterBinding: Binding<String?> {
        Binding {
            filters.splitName
        } set: { newValue in
            filters.splitName = newValue
        }
    }

    private var ratingFilterBinding: Binding<Int?> {
        Binding {
            filters.minimumRating
        } set: { newValue in
            filters.minimumRating = newValue
        }
    }

    private var startDateBinding: Binding<Date> {
        Binding {
            filters.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        } set: { newValue in
            filters.startDate = newValue
        }
    }

    private var endDateBinding: Binding<Date> {
        Binding {
            filters.endDate ?? .now
        } set: { newValue in
            filters.endDate = newValue
        }
    }
}

struct HistoryDisplaySnapshot: Sendable {
    var sessionRows: [HistorySessionRowSnapshot]
    var calendarDaySummaries: [HistoryCalendarDaySummary]
    var splitOptions: [String]
    var overview: HistoryOverviewSnapshot

    static let empty = HistoryDisplaySnapshot(sessionRows: [], calendarDaySummaries: [], splitOptions: [], overview: .empty)
}

struct HistoryOverviewSnapshot: Hashable, Sendable {
    let monthTitle: String
    let currentVisitCount: Int
    let monthlyTarget: Int?
    let progress: Double
    let currentDurationText: String
    let previousVisitCount: Int
    let previousDurationText: String
    let goalSourceText: String?

    static let empty = HistoryOverviewSnapshot(
        monthTitle: Date.now.formatted(.dateTime.month(.wide).year()),
        currentVisitCount: 0,
        monthlyTarget: nil,
        progress: 0,
        currentDurationText: "No duration",
        previousVisitCount: 0,
        previousDurationText: "No duration",
        goalSourceText: nil
    )
}

struct HistorySessionRowSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let splitName: String
    let date: Date
    let dateText: String
    let exerciseCountText: String
    let setCountText: String
    let durationText: String
    let ratingText: String?
    let topExerciseSummary: String
    let notesPreview: String?
}

struct HistoryCalendarDaySummary: Identifiable, Hashable, Sendable {
    let date: Date
    let title: String
    let metricLine: String
    let helperLine: String
    let sessionCount: Int

    var id: Date {
        date
    }
}

private struct HistoryWorkoutDetailRoute: Identifiable, Hashable {
    let sessionID: UUID

    var id: UUID {
        sessionID
    }
}

private struct HistoryScrollRowSurface<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: appTheme.metrics.compactCardRadius,
            style: .continuous
        )
        content
            .padding(appTheme.metrics.compactCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.cardBackground, in: shape)
            .overlay {
                shape.stroke(appTheme.cardBorder.opacity(0.54), lineWidth: 1)
            }
            .contentShape(shape)
    }
}

private struct HistoryScrollRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(AppMotion.buttonPress(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct HistoryOverviewCard: View {
    @Environment(\.appTheme) private var appTheme

    let snapshot: HistoryOverviewSnapshot
    let editGoal: () -> Void

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "calendar.badge.checkmark", size: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(snapshot.monthTitle) attendance")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Gym days are counted once, even when a day contains more than one workout.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(snapshot.monthlyTarget == nil ? "Set Goal" : "Edit Goal", action: editGoal)
                        .font(AppTypography.metadataEmphasis)
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("history-edit-training-goal")
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(snapshot.currentVisitCount)")
                        .font(AppTypography.heroMetric)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    if let monthlyTarget = snapshot.monthlyTarget {
                        Text("of \(monthlyTarget) gym visits")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        Text(snapshot.currentVisitCount == 1 ? "gym visit" : "gym visits")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if snapshot.monthlyTarget != nil {
                    SwiftUI.ProgressView(value: snapshot.progress)
                        .tint(appTheme.colors.accent)
                        .accessibilityLabel("Monthly gym visit progress")
                        .accessibilityValue("\(Int(snapshot.progress * 100)) percent")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 14) {
                        HistoryOverviewSupportingMetric(label: "This month", value: snapshot.currentDurationText)
                        HistoryOverviewSupportingMetric(label: "Previous visits", value: "\(snapshot.previousVisitCount)")
                        HistoryOverviewSupportingMetric(label: "Previous duration", value: snapshot.previousDurationText)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HistoryOverviewSupportingMetric(label: "This month", value: snapshot.currentDurationText)
                        HStack(alignment: .bottom, spacing: 14) {
                            HistoryOverviewSupportingMetric(label: "Previous visits", value: "\(snapshot.previousVisitCount)")
                            HistoryOverviewSupportingMetric(label: "Previous duration", value: snapshot.previousDurationText)
                        }
                    }
                }

                Text(snapshot.goalSourceText ?? "Set a weekly training goal to track monthly progress.")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history-overview-card")
    }
}

private struct HistoryOverviewSupportingMetric: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(label)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryTrainingGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let profile: UserProfile?
    @State private var trainingDaysPerWeek: Int
    @State private var saveErrorMessage: String?

    init(profile: UserProfile?) {
        self.profile = profile
        _trainingDaysPerWeek = State(initialValue: profile?.trainingDaysPerWeek ?? 4)
    }

    var body: some View {
        NavigationStack {
            FitnessScreen {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly training goal")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Peakline converts this into a monthly target using the number of days in the current month.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Stepper(
                            "\(trainingDaysPerWeek) \(trainingDaysPerWeek == 1 ? "day" : "days") per week",
                            value: $trainingDaysPerWeek,
                            in: 1...7
                        )
                        .font(AppTypography.bodyEmphasis)
                        .accessibilityIdentifier("history-training-goal-stepper")
                    }
                }
            }
            .navigationTitle("Gym Visit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let savedProfile: UserProfile
                        if let profile {
                            savedProfile = profile
                        } else {
                            let newProfile = UserProfile()
                            modelContext.insert(newProfile)
                            savedProfile = newProfile
                        }
                        savedProfile.trainingDaysPerWeek = trainingDaysPerWeek
                        savedProfile.updatedAt = .now
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            modelContext.rollback()
                            saveErrorMessage = "Could not save your training goal locally. Try again."
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("history-training-goal-save")
                }
            }
            .alert("Couldn’t save goal", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Could not save your training goal locally. Try again.")
            }
        }
    }
}

private struct HistorySessionRowCard: View {
    @Environment(\.appTheme) private var appTheme

    let row: HistorySessionRowSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.splitIconKey(for: row.splitName),
                size: 42,
                tint: appTheme.colors.accent,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.splitName)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                        Text(row.dateText)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    if let ratingText = row.ratingText {
                        Label(ratingText, systemImage: "star.fill")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textAccent)
                            .padding(.vertical, 5)
                            .frame(width: 108)
                            .background(appTheme.colors.accentSurface, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    HistoryRowMetric(value: row.exerciseCountText, label: "exercises")
                    HistoryRowMetric(value: row.setCountText, label: "sets")
                    HistoryRowMetric(value: row.durationText, label: "duration")
                }

                Label(row.topExerciseSummary, systemImage: "list.bullet.rectangle")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let notesPreview = row.notesPreview, !notesPreview.isEmpty {
                    Label(notesPreview, systemImage: "note.text")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Image(systemName: "chevron.right")
                .font(AppTypography.eyebrow)
                .foregroundStyle(appTheme.colors.textTertiary)
                .frame(width: 18, height: 44, alignment: .center)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRowMetric: View {
    @Environment(\.appTheme) private var appTheme

    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutCalendarView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let daySummaries: [HistoryCalendarDaySummary]

    @State private var isMonthExpanded = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(minimum: 30), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var daySummaryByDate: [Date: HistoryCalendarDaySummary] {
        daySummaries.reduce(into: [:]) { partial, summary in
            partial[calendar.startOfDay(for: summary.date)] = summary
        }
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthWorkoutCount: Int {
        daySummaries
            .filter { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }
            .reduce(0) { $0 + $1.sessionCount }
    }

    private var monthActivityText: String {
        switch monthWorkoutCount {
        case 0:
            return "No workouts this month"
        case 1:
            return "1 workout this month"
        default:
            return "\(monthWorkoutCount) workouts this month"
        }
    }

    private var selectedDaySummary: HistoryCalendarDaySummary? {
        daySummaryByDate[calendar.startOfDay(for: selectedDate)]
    }

    private var shouldShowTodayButton: Bool {
        let today = Date()
        return !calendar.isDate(selectedDate, inSameDayAs: today)
            || !calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
    }

    private var monthDays: [HistoryCalendarDayViewModel?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyDays = (firstWeekday + 5) % 7
        let summariesByDate = daySummaryByDate
        let days = dayRange.compactMap { day -> HistoryCalendarDayViewModel? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else {
                return nil
            }

            let day = calendar.startOfDay(for: date)
            return HistoryCalendarDayViewModel(date: day, summary: summariesByDate[day])
        }
        let trailingEmptyDays = (7 - ((leadingEmptyDays + days.count) % 7)) % 7

        return Array(repeating: nil, count: leadingEmptyDays) + days + Array(repeating: nil, count: trailingEmptyDays)
    }

    private var selectedWeekDays: [HistoryCalendarDayViewModel?] {
        let selectedStart = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: selectedStart)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedStart) else {
            return []
        }

        return (0..<7).compactMap { offset -> HistoryCalendarDayViewModel? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
            let day = calendar.startOfDay(for: date)
            return HistoryCalendarDayViewModel(date: day, summary: daySummaryByDate[day])
        }
    }

    var body: some View {
        let visibleDays = isMonthExpanded ? monthDays : selectedWeekDays

        VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
            calendarHeader

            LazyVGrid(columns: columns, spacing: appTheme.metrics.spacing6) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                    Text(weekday)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .accessibilityLabel(weekdayAccessibilityLabels[index])
                }

                ForEach(Array(visibleDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayCell(
                            date: date.date,
                            summary: date.summary,
                            isSelected: calendar.isDate(date.date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date.date)
                        ) {
                            select(date.date)
                        }
                    } else {
                        Color.clear
                            .frame(minHeight: appTheme.metrics.minimumHitTarget + appTheme.metrics.spacing4)
                            .accessibilityHidden(true)
                    }
                }
            }

            Divider()
                .overlay(appTheme.colors.cardBorder)

            HistorySelectedDaySummaryView(date: selectedDate, summary: selectedDaySummary)
        }
        .padding(.vertical, 2)
    }

    private var calendarHeader: some View {
        HStack(spacing: appTheme.metrics.spacing10) {
            monthButton(systemImage: "chevron.left") {
                moveMonth(by: -1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(monthTitle)
                    .font(AppTypography.compactCardTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(monthActivityText)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if shouldShowTodayButton {
                Button {
                    resetToToday()
                } label: {
                    Image(systemName: "location.fill")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textAccent)
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                        .background(
                            appTheme.colors.accentSurface,
                            in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                                .stroke(appTheme.colors.accent.opacity(0.26), lineWidth: 1)
                        }
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("Show today")
            }

            Button {
                withAnimation(AppMotion.modeChange(reduceMotion: reduceMotion)) {
                    isMonthExpanded.toggle()
                }
            } label: {
                Image(systemName: isMonthExpanded ? "rectangle.compress.vertical" : "calendar")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(isMonthExpanded ? appTheme.colors.accent : appTheme.colors.textPrimary)
                    .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                    .background(
                        isMonthExpanded ? appTheme.colors.accentSurface : appTheme.elevatedCardBackground,
                        in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                            .stroke(
                                isMonthExpanded ? appTheme.colors.accent.opacity(0.26) : appTheme.colors.cardBorder.opacity(0.56),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityLabel(isMonthExpanded ? "Show selected week" : "Show full month")
            .accessibilityIdentifier("history-calendar-view-toggle")

            monthButton(systemImage: "chevron.right") {
                moveMonth(by: 1)
            }
        }
    }

    private var weekdayAccessibilityLabels: [String] {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    }

    private func monthButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppTypography.eyebrow)
                .foregroundStyle(appTheme.colors.textPrimary)
                .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                .background(
                    appTheme.elevatedCardBackground,
                    in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                        .stroke(appTheme.colors.cardBorder.opacity(0.56), lineWidth: 1)
                }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous month" : "Next month")
    }

    private func select(_ date: Date) {
        AppHaptics.selection()
        withAnimation(AppMotion.chipSelect(reduceMotion: reduceMotion)) {
            selectedDate = calendar.startOfDay(for: date)
        }
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }

        AppHaptics.selection()
        withAnimation(AppMotion.modeChange(reduceMotion: reduceMotion)) {
            displayedMonth = nextMonth
            selectedDate = preferredSelectedDate(in: nextMonth)
        }
    }

    private func resetToToday() {
        let today = Date()
        AppHaptics.selection()
        withAnimation(AppMotion.chipSelect(reduceMotion: reduceMotion)) {
            displayedMonth = today
            selectedDate = calendar.startOfDay(for: today)
        }
    }

    private func preferredSelectedDate(in month: Date) -> Date {
        let today = Date()
        if calendar.isDate(month, equalTo: today, toGranularity: .month) {
            return calendar.startOfDay(for: today)
        }

        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let dayRange = calendar.range(of: .day, in: .month, for: month)
        else {
            return calendar.startOfDay(for: month)
        }

        let requestedDay = min(max(1, calendar.component(.day, from: selectedDate)), dayRange.count)
        let adjustedDate = calendar.date(byAdding: .day, value: requestedDay - 1, to: monthInterval.start) ?? monthInterval.start
        return calendar.startOfDay(for: adjustedDate)
    }
}

private struct HistoryCalendarDayViewModel: Identifiable, Hashable {
    let date: Date
    let summary: HistoryCalendarDaySummary?

    var id: Date {
        date
    }
}

private struct CalendarDayCell: View {
    @Environment(\.appTheme) private var appTheme

    let date: Date
    let summary: HistoryCalendarDaySummary?
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var isLogged: Bool {
        summary != nil
    }

    private var tokenSize: CGFloat {
        appTheme.metrics.minimumHitTarget
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                dayToken

                dayText
                    .padding(.horizontal, appTheme.metrics.spacing2)
            }
            .frame(width: tokenSize, height: tokenSize)
            .frame(
                maxWidth: .infinity,
                minHeight: tokenSize + appTheme.metrics.spacing4
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayText: some View {
        Text(dayNumber)
            .font(.system(.body, design: .rounded).weight(isSelected || isLogged ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(dayForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    private var dayToken: some View {
        RoundedRectangle(cornerRadius: appTheme.metrics.radius12, style: .continuous)
            .fill(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius12, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            }
            .frame(width: tokenSize, height: tokenSize)
    }

    private var dayForeground: Color {
        if isSelected { return appTheme.colors.accentForeground }
        if isToday { return appTheme.colors.accent }
        return appTheme.colors.textPrimary
    }

    private var backgroundColor: Color {
        if isSelected { return appTheme.colors.accent }
        if isLogged { return appTheme.colors.accentSurface }
        if isToday { return appTheme.elevatedCardBackground }
        return .clear
    }

    private var strokeColor: Color {
        if isSelected { return appTheme.colors.accentHighlight.opacity(0.86) }
        if isToday { return appTheme.colors.accent.opacity(0.55) }
        if isLogged { return appTheme.colors.accent.opacity(0.18) }
        return .clear
    }

    private var strokeWidth: CGFloat {
        isSelected || isToday || isLogged ? 1 : 0
    }

    private var accessibilityLabel: String {
        let dateText = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let stateText = [
            isSelected ? "selected" : nil,
            isToday ? "today" : nil,
            isLogged ? "Workout logged" : "No workout logged"
        ]
            .compactMap { $0 }
            .joined(separator: ", ")
        return "\(dateText), \(stateText)"
    }
}

private struct HistorySelectedDaySummaryView: View {
    @Environment(\.appTheme) private var appTheme

    let date: Date
    let summary: HistoryCalendarDaySummary?

    private var dateText: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        HStack(alignment: .top, spacing: appTheme.metrics.spacing10) {
            FitnessIconBadge(
                systemImage: summary == nil ? "calendar" : "figure.strengthtraining.traditional",
                size: 34,
                tint: summary == nil ? appTheme.colors.textSecondary : appTheme.colors.accent,
                background: summary == nil ? appTheme.elevatedCardBackground : appTheme.colors.accentSurface
            )

            VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                Text(dateText)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)

                Text(summary?.title ?? "No workout logged")
                    .font(AppTypography.compactCardTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary?.metricLine ?? "Rest, recovery, or an unlogged training day.")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(summary == nil ? appTheme.colors.textSecondary : appTheme.colors.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .fixedSize(horizontal: false, vertical: true)

                if let helperLine = summary?.helperLine, !helperLine.isEmpty {
                    Text(helperLine)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, appTheme.metrics.spacing4)
        .padding(.vertical, appTheme.metrics.spacing2)
    }
}

private struct WorkoutHistoryDetailRouteView: View {
    @Environment(\.modelContext) private var modelContext

    let sessionID: UUID

    @State private var session: WorkoutSession?
    @State private var didResolveSession = false

    var body: some View {
        Group {
            if let session {
                WorkoutHistoryDetailView(session: session)
            } else if didResolveSession {
                FitnessScreen(
                    title: "Workout",
                    subtitle: "This workout is no longer available.",
                    systemImage: "clock.badge.questionmark"
                ) {
                    DashboardEmptyStateCard(
                        title: "Workout unavailable",
                        message: "It may have been deleted from history.",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                Color.clear
                    .ignoresSafeArea()
            }
        }
        .task(id: sessionID) {
            resolveSession()
        }
    }

    @MainActor
    private func resolveSession() {
        guard !didResolveSession else { return }

        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.id == sessionID
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        session = try? modelContext.fetch(descriptor).first
        didResolveSession = true
    }
}

private struct WorkoutHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Bindable var session: WorkoutSession
    @State private var previewRoute: WorkoutPreviewPreparedRoute?
    @State private var reopenedSession: WorkoutSession?
    @State private var showingTemplateSave = false
    @State private var showingReopenConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var reopenErrorMessage: String?
    @State private var editRoute: HistoryWorkoutEditRoute?
    @State private var sessionPRs: [PRRecord] = []
    @State private var didPrepareSessionPRs = false

    private let reuseBuilder = WorkoutReuseBuilder()
    private let reopenService = WorkoutSessionReopenService()

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private var orderedExerciseLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var completedExerciseLogs: [ExerciseLog] {
        orderedExerciseLogs.filter { hasLoggedSets($0) }
    }

    private var completedSetCount: Int {
        completedExerciseLogs.flatMap(\.setLogs).filter(\.completed).count
    }

    private var plannedExerciseLogs: [ExerciseLog] {
        orderedExerciseLogs.filter { !hasLoggedSets($0) }
    }

    private var isChildRouteActive: Bool {
        previewRoute != nil || reopenedSession != nil || editRoute != nil
    }

    var body: some View {
        Group {
            if isChildRouteActive {
                appTheme.colors.backgroundPrimary
                    .ignoresSafeArea()
            } else {
                detailList
            }
        }
        .navigationTitle(session.splitNameSnapshot)
        .task(id: session.id) {
            await prepareSessionPRsIfNeeded()
        }
        .navigationDestination(item: $previewRoute) { route in
            WorkoutPreviewRouteView(preparedRoute: route)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(
                        key: "history.preview.\(route.split.id.uuidString)"
                    )
                }
        }
        .navigationDestination(item: $reopenedSession) { session in
            WorkoutLoggerView(session: session)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(
                        key: "history.reopen.\(session.id.uuidString)"
                    )
                }
        }
        .navigationDestination(item: $editRoute) { route in
            if route.sessionID == session.id {
                WorkoutLoggerView(session: session, isEditingCompletedWorkout: true)
                    .onAppear {
                        NavigationInteraction.destinationDidAppear(
                            key: "history.edit.\(route.sessionID.uuidString)"
                        )
                    }
            }
        }
        .sheet(isPresented: $showingTemplateSave) {
            WorkoutTemplateSaveSheet(session: session)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(
                        key: "history.template.\(session.id.uuidString)"
                    )
                }
        }
        .alert("Reopen this workout?", isPresented: $showingReopenConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reopen") {
                reopenWorkout()
            }
        } message: {
            Text("This moves it back into the live workout logger so you can add or edit sets before finishing again.")
        }
        .alert("Delete workout?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
        } message: {
            Text("This removes the workout from history and progress trends.")
        }
        .alert("Could not delete workout", isPresented: deleteErrorPresentation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Try again.")
        }
        .alert("Could not reopen workout", isPresented: Binding(
            get: { reopenErrorMessage != nil },
            set: { if !$0 { reopenErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reopenErrorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    let split = reuseBuilder.previewSplit(from: session)
                    let preparedRoute = WorkoutPreviewWarmStartStore.shared.prepareRoute(
                        for: split,
                        initialMode: .full
                    )
                    PerformanceTracer.mark(.previewRouteTap, "source=history split=\(split.name) mode=\(WorkoutMode.full.rawValue)")
                    NavigationInteraction.perform(
                        key: "history.preview.\(split.id.uuidString)",
                        destinationClass: .warm,
                        haptic: .selection
                    ) {
                        previewRoute = preparedRoute
                    }
                } label: {
                    Label("Repeat", systemImage: "repeat")
                }

                Button {
                    NavigationInteraction.perform(
                        key: "history.template.\(session.id.uuidString)",
                        destinationClass: .deep,
                        haptic: .selection
                    ) {
                        showingTemplateSave = true
                    }
                } label: {
                    Label("Save Template", systemImage: "rectangle.stack.badge.plus")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    NavigationInteraction.perform(
                        key: "history.edit.\(session.id.uuidString)",
                        destinationClass: .deep,
                        haptic: .selection
                    ) {
                        editRoute = HistoryWorkoutEditRoute(sessionID: session.id)
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityIdentifier("history-workout-edit")

                Menu {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("Workout actions", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel("Workout actions")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingReopenConfirmation = true
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
    }

    private var detailList: some View {
        List {
            Section {
                HistoryDetailHero(
                    splitName: session.splitNameSnapshot,
                    dateText: session.date.formatted(date: .abbreviated, time: .shortened),
                    durationText: durationText ?? "No duration",
                    ratingText: ratingText,
                    exerciseCount: completedExerciseLogs.count,
                    setCount: completedSetCount,
                    prCount: sessionPRs.count,
                    notes: session.notes
                )
            }

            if !sessionPRs.isEmpty {
                Section("Highlights") {
                    ForEach(sessionPRs.prefix(4)) { record in
                        Label(record.improvementDescription, systemImage: "trophy.fill")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textWarning)
                    }
                }
            }

            if !completedExerciseLogs.isEmpty {
                Section("Exercises Done") {
                    ForEach(completedExerciseLogs) { exerciseLog in
                        ExerciseHistorySummary(
                            exerciseLog: exerciseLog,
                            prs: sessionPRs.filter { $0.exerciseLogId == exerciseLog.id }
                        )
                    }
                }
            }

            if !plannedExerciseLogs.isEmpty {
                Section("Planned But Not Logged") {
                    ForEach(plannedExerciseLogs) { exerciseLog in
                        HStack(spacing: 10) {
                            ExerciseIconView(
                                iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                                size: 30,
                                showBackground: true,
                                isDisabled: true,
                                isDecorative: true
                            )
                            Text(exerciseLog.exerciseNameSnapshot)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }
                }
            }
        }
        .peaklineGroupedContent()
        .listSectionSpacing(12)
    }

    @MainActor
    private func prepareSessionPRsIfNeeded() async {
        guard !didPrepareSessionPRs else { return }
        didPrepareSessionPRs = true

        let sessionID = session.id
        let snapshots: [WorkoutAnalyticsSession]
        do {
            let completedSessions = try modelContext.fetch(Self.completedSessionsDescriptor)
            snapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(
                from: completedSessions,
                in: modelContext
            )
        } catch {
            sessionPRs = []
            return
        }

        let records = await Task.detached(priority: .userInitiated) {
            TrainingAnalyticsService()
                .prTimeline(from: snapshots)
                .filter { $0.sessionId == sessionID }
        }.value

        guard !Task.isCancelled else { return }
        sessionPRs = records
    }

    private func hasLoggedSets(_ exerciseLog: ExerciseLog) -> Bool {
        exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
    }

    private var durationText: String? {
        if let durationSeconds = session.durationSeconds {
            return durationSeconds > 0 ? formatDuration(seconds: durationSeconds) : nil
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            let activeSeconds = max(
                0,
                Int(endedAt.timeIntervalSince(startedAt)) - max(0, session.accumulatedPausedSeconds)
            )
            return activeSeconds > 0 ? formatDuration(seconds: activeSeconds) : nil
        }

        if let duration = session.durationMinutes {
            return duration > 0 ? "\(duration) min" : nil
        }

        return nil
    }

    private var ratingText: String? {
        guard let perceivedDifficulty = session.perceivedDifficulty else { return nil }

        switch perceivedDifficulty {
        case 1:
            return "☹ Rough"
        case 2:
            return "😐 Okay"
        case 3:
            return "🙂 Good"
        case 4:
            return "😄 Great"
        case 5:
            return "🤩 Excellent"
        default:
            return nil
        }
    }

    private func deleteWorkout() {
        modelContext.delete(session)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = "Could not delete this workout locally. Try again."
        }
    }

    private var deleteErrorPresentation: Binding<Bool> {
        Binding {
            deleteErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                deleteErrorMessage = nil
            }
        }
    }

    private func reopenWorkout() {
        let originalState = WorkoutSessionCompletionState(session)
        reopenService.reopen(session)
        do {
            try modelContext.save()
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .workoutReopened)
            NavigationInteraction.perform(
                key: "history.reopen.\(session.id.uuidString)",
                destinationClass: .warm,
                haptic: .medium
            ) {
                reopenedSession = session
            }
        } catch {
            originalState.restore(session)
            reopenErrorMessage = "Could not reopen this workout locally. Try again."
        }
    }

    private func formatDuration(seconds totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min \(seconds) sec"
        }

        if minutes > 0 {
            return "\(minutes) min \(seconds) sec"
        }

        return "\(seconds) sec"
    }
}

private struct HistoryWorkoutEditRoute: Identifiable, Hashable {
    let sessionID: UUID

    var id: UUID { sessionID }
}

private struct HistoryDetailHero: View {
    @Environment(\.appTheme) private var appTheme

    let splitName: String
    let dateText: String
    let durationText: String
    let ratingText: String?
    let exerciseCount: Int
    let setCount: Int
    let prCount: Int
    let notes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ExerciseIconView(
                    iconKey: ExerciseIconMapper.splitIconKey(for: splitName),
                    size: 48,
                    tint: appTheme.colors.accent,
                    showBackground: true,
                    isDecorative: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(splitName)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(2)
                    Text(dateText)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                detailMetric("Duration", value: durationText, systemImage: "timer")
                detailMetric("Exercises", value: "\(exerciseCount)", systemImage: "figure.strengthtraining.traditional")
                detailMetric("Sets", value: "\(setCount)", systemImage: "number")
                detailMetric("PRs", value: "\(prCount)", systemImage: "trophy.fill")
            }

            if let ratingText {
                Label(ratingText, systemImage: "star.fill")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textAccent)
            }

            if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("history-detail-hero")
        .accessibilityElement(children: .combine)
    }

    private func detailMetric(_ label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: systemImage)
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(AppTypography.workoutNumber)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExerciseHistorySummary: View {
    @Environment(\.appTheme) private var appTheme

    let exerciseLog: ExerciseLog
    let prs: [PRRecord]

    private var sets: [SetLog] {
        exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: exerciseLog),
                size: 36,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(exerciseLog.exerciseNameSnapshot)
                    .font(AppTypography.sectionTitle)

                if let firstPR = prs.first {
                    Label(firstPR.improvementDescription, systemImage: "trophy.fill")
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textWarning)
                }

                if sets.isEmpty {
                    Text("No sets logged")
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(sets) { set in
                        HStack {
                            Text("Set \(set.setNumber)")
                            Spacer()
                            Text(PeaklineText.loadReps(weight: formatWeight(set.weight), reps: set.reps))
                                .font(AppTypography.sectionTitle)
                            if let rpe = set.rpe {
                                Text("RPE \(formatWeight(rpe))")
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }
                        }
                    }
                }

                if let notes = exerciseLog.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func formatWeight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
