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
    @State private var pendingDeleteSession: WorkoutSession?

    private let filterService = HistoryFilterService()

    private var filteredSessions: [WorkoutSession] {
        filterService.filter(sessions, using: filters)
    }

    private var splitOptions: [String] {
        Array(Set(sessions.map { $0.splitNameSnapshot.components(separatedBy: " - ").first ?? $0.splitNameSnapshot })).sorted()
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(title: "History", subtitle: "Review training trends and recent sessions.", systemImage: "clock.arrow.circlepath") {
                FitnessCard(style: .compact) {
                    WorkoutCalendarView(displayedMonth: $displayedMonth, sessions: filteredSessions)
                }

                filterChips

                if filteredSessions.isEmpty {
                    DashboardEmptyStateCard(
                        title: sessions.isEmpty ? "No workouts logged yet" : "No matching workouts",
                        message: sessions.isEmpty ? "Start Push, Pull, or Legs to build your first training history." : "Adjust filters to see more sessions.",
                        systemImage: "clock"
                    )
                } else {
                    ForEach(filteredSessions) { session in
                        NavigationLink {
                            WorkoutHistoryDetailView(session: session)
                        } label: {
                            FitnessCard(style: .compact) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(session.splitNameSnapshot)
                                            .font(.headline)
                                            .foregroundStyle(appTheme.colors.textPrimary)
                                        Text(summary(for: session))
                                            .font(.subheadline)
                                            .foregroundStyle(appTheme.mutedText)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(appTheme.colors.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .destructiveSwipeAction {
                            pendingDeleteSession = session
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
                    pendingDeleteSession = nil
                }
                Button("Delete", role: .destructive) {
                    deletePendingSession()
                }
            } message: {
                Text("This removes the workout from history and progress trends.")
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteSession != nil
        } set: { showing in
            if !showing {
                pendingDeleteSession = nil
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

    private func delete(_ session: WorkoutSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func deletePendingSession() {
        guard let pendingDeleteSession else { return }
        delete(pendingDeleteSession)
        self.pendingDeleteSession = nil
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

private struct WorkoutCalendarView: View {
    @Environment(\.appTheme) private var appTheme

    @Binding var displayedMonth: Date
    let sessions: [WorkoutSession]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var loggedDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.date) })
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
                    Image(systemName: "ellipsis.circle")
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
