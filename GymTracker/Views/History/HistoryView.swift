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
            sessions.map { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0):\($0.perceivedDifficulty ?? 0)" }.joined(separator: ","),
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
            FitnessScreen(title: "History", subtitle: "Review training trends and recent sessions.", systemImage: "clock.arrow.circlepath") {
                FitnessCard(style: .compact) {
                    WorkoutCalendarView(displayedMonth: $displayedMonth, loggedDates: calendarLoggedDates)
                }

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
                            selectedWorkoutDetailRoute = HistoryWorkoutDetailRoute(sessionID: row.id)
                        } label: {
                            FitnessCard(style: .compact) {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(row.splitName)
                                            .font(.headline)
                                            .foregroundStyle(appTheme.colors.textPrimary)
                                        Text(row.summary)
                                            .font(.subheadline)
                                            .foregroundStyle(appTheme.mutedText)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(appTheme.colors.textTertiary)
                                        .frame(width: 18, height: 44, alignment: .center)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
        return HistoryDisplaySnapshot(
            sessionRows: filteredSessions.map { session in
                HistorySessionRowSnapshot(
                    id: session.id,
                    splitName: session.splitNameSnapshot,
                    date: session.date,
                    summary: summary(for: session)
                )
            },
            loggedDates: filteredSessions.map(\.date),
            splitOptions: Array(Set(sessions.map { baseSplitName($0.splitNameSnapshot) })).sorted()
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
            }
            .padding(.vertical, 2)
        }
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

    private func summary(for session: WorkoutSession) -> String {
        let date = session.date.formatted(date: .abbreviated, time: .omitted)
        let setCount = session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        let exerciseCount = session.exerciseLogs.filter { exerciseLog in
            exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
        }.count
        return "\(date) - \(exerciseCount) exercises - \(setCount) sets"
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

    static let empty = HistoryDisplaySnapshot(sessionRows: [], loggedDates: [], splitOptions: [])
}

private struct HistorySessionRowSnapshot: Identifiable, Hashable {
    let id: UUID
    let splitName: String
    let date: Date
    let summary: String
}

private struct HistoryWorkoutDetailRoute: Identifiable, Hashable {
    let sessionID: UUID

    var id: UUID {
        sessionID
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
        VStack(alignment: .leading, spacing: 12) {
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

            LazyVGrid(columns: columns, spacing: 8) {
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
                            .frame(height: 34)
                    }
                }
            }
        }
        .padding(.vertical, 6)
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
            .frame(height: 34)
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

    private var plannedExerciseLogs: [ExerciseLog] {
        orderedExerciseLogs.filter { !hasLoggedSets($0) }
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                if let duration = durationText {
                    LabeledContent("Duration", value: duration)
                }
                if let ratingText {
                    LabeledContent("Rating", value: ratingText)
                }
                if let notes = session.notes, !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
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
            WorkoutPreviewView(split: split)
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
                    previewSplit = reuseBuilder.previewSplit(from: session)
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
