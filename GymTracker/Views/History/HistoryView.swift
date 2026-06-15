import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var displayedMonth = Date()
    @State private var filters = HistoryFilters()
    @State private var useDateRange = false
    @State private var showingFilters = false
    @State private var pendingDeleteSessionID: UUID?
    @State private var selectedWorkoutDetailRoute: HistoryWorkoutDetailRoute?
    @State private var displaySnapshot = HistoryDisplaySnapshot.empty
    @State private var lastDisplaySignature: String?
    @State private var didRequestInitialRefresh = false
    @State private var displaySnapshotReady = false

    private let filterService = HistoryFilterService()

    private var currentDisplaySnapshot: HistoryDisplaySnapshot {
        displaySnapshot
    }

    private var displaySignature: String {
        [
            sessions.prefix(120).map { session in
                let setSignature = session.exerciseLogs
                    .flatMap(\.setLogs)
                    .map { "\($0.id.uuidString):\($0.setNumber):\($0.weight):\($0.reps):\($0.completed)" }
                    .joined(separator: ",")
                return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.durationMinutes ?? 0):\(session.perceivedDifficulty ?? 0):\(session.notes ?? ""):\(setSignature)"
            }.joined(separator: "|"),
            filters.splitName ?? "all",
            filters.exerciseNameQuery,
            "\(filters.minimumRating ?? 0)",
            "\(filters.startDate?.timeIntervalSince1970 ?? 0)",
            "\(filters.endDate?.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")
    }

    private var sessionRows: [HistorySessionRowSnapshot] {
        currentDisplaySnapshot.sessionRows
    }

    private var calendarLoggedDates: [Date] {
        currentDisplaySnapshot.loggedDates
    }

    private var splitOptions: [String] {
        currentDisplaySnapshot.splitOptions
    }

    var body: some View {
        NavigationStack {
            FitnessScreen {
                HistoryOverviewCard(snapshot: currentDisplaySnapshot.overview, filtersActive: filters.isActive)

                FitnessCard(style: .compact) {
                    WorkoutCalendarView(displayedMonth: $displayedMonth, loggedDates: calendarLoggedDates)
                }
                .accessibilityIdentifier("history-calendar-card")

                filterChips

                if sessionRows.isEmpty {
                    DashboardEmptyStateCard(
                        title: displaySnapshotReady ? (sessions.isEmpty ? "No workouts logged yet" : "No matching workouts") : "Loading history",
                        message: displaySnapshotReady ? (sessions.isEmpty ? "Start Push, Pull, or Legs to build your first training history." : "Adjust filters to see more sessions.") : "Preparing recent sessions and filters.",
                        systemImage: displaySnapshotReady ? "clock" : "hourglass"
                    )
                } else {
                    ForEach(sessionRows) { row in
                        Button {
                            AppHaptics.selection()
                            PerformanceTracer.trace(.motionHistoryRowOpen) {
                                selectedWorkoutDetailRoute = HistoryWorkoutDetailRoute(sessionID: row.id)
                            }
                        } label: {
                            FitnessCard(style: .compact) {
                                HistorySessionRowCard(row: row)
                            }
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .accessibilityIdentifier("history-session-row")
                        .destructiveSwipeAction {
                            pendingDeleteSessionID = row.id
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingFilters) {
                filterSheet
                    .presentationDetents([.medium, .large])
            }
            .alert("Delete workout?", isPresented: deleteAlertBinding) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteSessionID = nil
                }
                Button("Delete", role: .destructive) {
                    deletePendingSession()
                }
            } message: {
                Text("This removes the workout from history and progress trends.")
            }
            .navigationDestination(item: $selectedWorkoutDetailRoute) { route in
                WorkoutHistoryDetailRouteView(sessionID: route.sessionID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("history-filter-button")
                }
            }
        }
        .accessibilityIdentifier("history-screen")
        .onAppear {
            let shouldForceRefresh = !didRequestInitialRefresh
            didRequestInitialRefresh = true
            DispatchQueue.main.async {
                refreshDisplaySnapshot(force: shouldForceRefresh)
            }
        }
        .onChange(of: displaySignature) { _, _ in
            refreshDisplaySnapshot()
        }
    }

    private func refreshDisplaySnapshot(force: Bool = false) {
        let signature = displaySignature
        guard force || signature != lastDisplaySignature else { return }
        let nextSnapshot = PerformanceTracer.trace(.historyDisplaySnapshot) {
            makeDisplaySnapshot()
        }
        AppMotion.withoutAnimation {
            displaySnapshot = nextSnapshot
            lastDisplaySignature = signature
            displaySnapshotReady = true
        }
    }

    private func makeDisplaySnapshot() -> HistoryDisplaySnapshot {
        let filteredSessions = filterService.filter(sessions, using: filters)
        let sessionRows = filteredSessions.map(rowSnapshot(for:))
        return HistoryDisplaySnapshot(
            sessionRows: sessionRows,
            loggedDates: filteredSessions.map(\.date),
            splitOptions: Array(Set(sessions.map { baseSplitName($0.splitNameSnapshot) })).sorted(),
            overview: overviewSnapshot(for: filteredSessions)
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteSessionID != nil
        } set: { showing in
            if !showing {
                pendingDeleteSessionID = nil
            }
        }
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
                                .font(.headline)

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
                                .font(.headline)

                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(appTheme.colors.textTertiary)
                                TextField("Exercise name", text: $filters.exerciseNameQuery)
                                    .textInputAutocapitalization(.words)
                            }
                            .padding(12)
                            .background(appTheme.elevatedCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Rating")
                                .font(.headline)

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
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        filters = HistoryFilters()
                        useDateRange = false
                    }
                    .disabled(!filters.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
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

    private func rowSnapshot(for session: WorkoutSession) -> HistorySessionRowSnapshot {
        let loggedExercises = loggedExerciseLogs(in: session)
        let completedSetCount = loggedExercises.flatMap(\.setLogs).filter(\.completed).count
        let topExerciseNames = loggedExercises.prefix(3).map(\.exerciseNameSnapshot)
        let topExerciseSummary = topExerciseNames.isEmpty ? "No exercises logged" : topExerciseNames.joined(separator: ", ")

        return HistorySessionRowSnapshot(
            id: session.id,
            splitName: session.splitNameSnapshot,
            date: session.date,
            dateText: session.date.formatted(date: .abbreviated, time: .shortened),
            exerciseCountText: "\(loggedExercises.count)",
            setCountText: "\(completedSetCount)",
            durationText: durationText(for: session) ?? "No duration",
            ratingText: ratingText(for: session.perceivedDifficulty),
            topExerciseSummary: topExerciseSummary,
            notesPreview: session.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func overviewSnapshot(for filteredSessions: [WorkoutSession]) -> HistoryOverviewSnapshot {
        let totalSets = filteredSessions.reduce(0) { partial, session in
            partial + session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        }
        let totalExercises = filteredSessions.reduce(0) { partial, session in
            partial + loggedExerciseLogs(in: session).count
        }
        let topSplit = mostFrequent(filteredSessions.map { baseSplitName($0.splitNameSnapshot) })
        let topExercise = mostFrequent(filteredSessions.flatMap { loggedExerciseLogs(in: $0).map(\.exerciseNameSnapshot) })
        let totalDurationSeconds = filteredSessions.reduce(0) { partial, session in
            partial + durationSeconds(for: session)
        }
        let averageRating = averageRatingText(for: filteredSessions)

        return HistoryOverviewSnapshot(
            sessionCountText: "\(filteredSessions.count)",
            setCountText: "\(totalSets)",
            exerciseCountText: "\(totalExercises)",
            durationText: totalDurationSeconds > 0 ? formatDuration(seconds: totalDurationSeconds) : "No duration",
            topSplitText: topSplit ?? "No split yet",
            topExerciseText: topExercise ?? "No exercise yet",
            averageRatingText: averageRating ?? "No rating"
        )
    }

    private func loggedExerciseLogs(in session: WorkoutSession) -> [ExerciseLog] {
        session.exerciseLogs
            .filter { exerciseLog in
                exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
            }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func durationSeconds(for session: WorkoutSession) -> Int {
        if let durationSeconds = session.durationSeconds {
            return durationSeconds
        }

        if let durationMinutes = session.durationMinutes {
            return durationMinutes * 60
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return max(0, Int(endedAt.timeIntervalSince(startedAt)))
        }

        return 0
    }

    private func durationText(for session: WorkoutSession) -> String? {
        let seconds = durationSeconds(for: session)
        guard seconds > 0 else { return nil }
        return formatDuration(seconds: seconds)
    }

    private func formatDuration(seconds totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }

        if minutes > 0 {
            return "\(minutes) min"
        }

        return "\(totalSeconds) sec"
    }

    private func ratingText(for rating: Int?) -> String? {
        guard let rating else { return nil }

        switch rating {
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
            return nil
        }
    }

    private func averageRatingText(for sessions: [WorkoutSession]) -> String? {
        let ratings = sessions.compactMap(\.perceivedDifficulty)
        guard !ratings.isEmpty else { return nil }
        let average = Double(ratings.reduce(0, +)) / Double(ratings.count)
        return average.formatted(.number.precision(.fractionLength(1)))
    }

    private func mostFrequent(_ values: [String]) -> String? {
        let trimmedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedValues.isEmpty else { return nil }

        return Dictionary(grouping: trimmedValues, by: { $0 })
            .map { (value: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.value.localizedStandardCompare($1.value) == .orderedAscending
                }
                return $0.count > $1.count
            }
            .first?
            .value
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }

    private func delete(_ session: WorkoutSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func deletePendingSession() {
        guard let pendingDeleteSessionID else { return }
        defer { self.pendingDeleteSessionID = nil }

        guard let pendingDeleteSession = sessions.first(where: { $0.id == pendingDeleteSessionID }) else { return }
        delete(pendingDeleteSession)
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

private struct HistoryDisplaySnapshot {
    var sessionRows: [HistorySessionRowSnapshot]
    var loggedDates: [Date]
    var splitOptions: [String]
    var overview: HistoryOverviewSnapshot

    static let empty = HistoryDisplaySnapshot(sessionRows: [], loggedDates: [], splitOptions: [], overview: .empty)
}

private struct HistoryOverviewSnapshot: Hashable {
    let sessionCountText: String
    let setCountText: String
    let exerciseCountText: String
    let durationText: String
    let topSplitText: String
    let topExerciseText: String
    let averageRatingText: String

    static let empty = HistoryOverviewSnapshot(
        sessionCountText: "0",
        setCountText: "0",
        exerciseCountText: "0",
        durationText: "No duration",
        topSplitText: "No split yet",
        topExerciseText: "No exercise yet",
        averageRatingText: "No rating"
    )
}

private struct HistorySessionRowSnapshot: Identifiable, Hashable {
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

private struct HistoryWorkoutDetailRoute: Identifiable, Hashable {
    let sessionID: UUID

    var id: UUID {
        sessionID
    }
}

private struct HistoryOverviewCard: View {
    @Environment(\.appTheme) private var appTheme

    let snapshot: HistoryOverviewSnapshot
    let filtersActive: Bool

    var body: some View {
        FitnessCard(style: .compact, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "chart.bar.xaxis", size: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(filtersActive ? "Filtered training log" : "Training log")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text(filtersActive ? "Calendar and totals reflect active filters." : "Calendar, volume, and recent sessions in one view.")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    HistoryOverviewMetric(label: "Workouts", value: snapshot.sessionCountText, caption: snapshot.topSplitText, systemImage: "calendar.badge.checkmark")
                    HistoryOverviewMetric(label: "Sets", value: snapshot.setCountText, caption: snapshot.durationText, systemImage: "number")
                    HistoryOverviewMetric(label: "Exercises", value: snapshot.exerciseCountText, caption: snapshot.topExerciseText, systemImage: "figure.strengthtraining.traditional")
                    HistoryOverviewMetric(label: "Avg rating", value: snapshot.averageRatingText, caption: "Session feel", systemImage: "star.fill")
                }
            }
        }
        .accessibilityIdentifier("history-overview-card")
    }
}

private struct HistoryOverviewMetric: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(caption)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
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
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                        Text(row.dateText)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    if let ratingText = row.ratingText {
                        Label(ratingText, systemImage: "star.fill")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(appTheme.colors.accentSurface, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    HistoryRowMetric(value: row.exerciseCountText, label: "exercises")
                    HistoryRowMetric(value: row.setCountText, label: "sets")
                    HistoryRowMetric(value: row.durationText, label: "duration")
                }

                Label(row.topExerciseSummary, systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let notesPreview = row.notesPreview, !notesPreview.isEmpty {
                    Label(notesPreview, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
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

    @Binding var displayedMonth: Date
    let loggedDates: [Date]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var loggedDays: Set<Date> {
        Set(loggedDates.map { calendar.startOfDay(for: $0) })
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyDays = (firstWeekday + 5) % 7
        let days = dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }

        return Array(repeating: nil, count: leadingEmptyDays) + days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayCell(
                            date: date,
                            isLogged: loggedDays.contains(calendar.startOfDay(for: date)),
                            isToday: calendar.isDateInToday(date)
                        )
                    } else {
                        Color.clear
                            .frame(height: 24)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func moveMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}

private struct CalendarDayCell: View {
    @Environment(\.appTheme) private var appTheme
    let date: Date
    let isLogged: Bool
    let isToday: Bool

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    var body: some View {
        Text(dayNumber)
            .font(.subheadline.weight(isLogged ? .semibold : .regular))
            .foregroundStyle(isLogged ? appTheme.colors.accentForeground : appTheme.colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background {
                if isLogged {
                    Circle().fill(appTheme.colors.accent)
                } else if isToday {
                    Circle().stroke(appTheme.colors.textTertiary, lineWidth: 1)
                }
            }
    }
}

private struct WorkoutHistoryDetailRouteView: View {
    let sessionID: UUID

    @Query private var sessions: [WorkoutSession]

    init(sessionID: UUID) {
        self.sessionID = sessionID

        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.id == sessionID
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _sessions = Query(descriptor)
    }

    var body: some View {
        if let session = sessions.first {
            WorkoutHistoryDetailView(session: session)
        } else {
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
        }
    }
}

private struct WorkoutHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Bindable var session: WorkoutSession
    @State private var previewSplit: WorkoutPreviewSplit?
    @State private var reopenedSession: WorkoutSession?
    @State private var showingTemplateSave = false
    @State private var showingReopenConfirmation = false
    @State private var showingDeleteConfirmation = false

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private let reuseBuilder = WorkoutReuseBuilder()
    private let reopenService = WorkoutSessionReopenService()
    private let analytics = TrainingAnalyticsService()

    private var sessionPRs: [PRRecord] {
        analytics.prs(for: session, in: completedSessions)
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

    var body: some View {
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.warning)
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
        .scrollContentBackground(.hidden)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .listSectionSpacing(12)
        .navigationTitle(session.splitNameSnapshot)
        .navigationDestination(item: $previewSplit) { split in
            WorkoutPreviewRouteView(split: split, initialMode: .full)
        }
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
        .alert("Delete workout?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
        } message: {
            Text("This removes the workout from history and progress trends.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    let split = reuseBuilder.previewSplit(from: session)
                    PerformanceTracer.mark(.previewRouteTap, "source=history split=\(split.name) mode=\(WorkoutMode.full.rawValue)")
                    previewSplit = split
                } label: {
                    Label("Repeat", systemImage: "repeat")
                }

                Button {
                    showingTemplateSave = true
                } label: {
                    Label("Save Template", systemImage: "rectangle.stack.badge.plus")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    WorkoutLoggerView(session: session, isEditingCompletedWorkout: true)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

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

    private func hasLoggedSets(_ exerciseLog: ExerciseLog) -> Bool {
        exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
    }

    private var durationText: String? {
        if let durationSeconds = session.durationSeconds {
            return formatDuration(seconds: durationSeconds)
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return formatDuration(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let duration = session.durationMinutes {
            return "\(duration) min"
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
        try? modelContext.save()
        dismiss()
    }

    private func reopenWorkout() {
        reopenService.reopen(session)
        try? modelContext.save()
        reopenedSession = session
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
            }

            if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(.subheadline)
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
                    .font(.headline)

                if let firstPR = prs.first {
                    Label(firstPR.improvementDescription, systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.warning)
                }

                if sets.isEmpty {
                    Text("No sets logged")
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(sets) { set in
                        HStack {
                            Text("Set \(set.setNumber)")
                            Spacer()
                            Text("\(formatWeight(set.weight))kg x \(set.reps)")
                                .font(.headline)
                            if let rpe = set.rpe {
                                Text("RPE \(formatWeight(rpe))")
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }
                        }
                    }
                }

                if let notes = exerciseLog.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption)
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
