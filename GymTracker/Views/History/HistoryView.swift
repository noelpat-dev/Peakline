import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var displayedMonth = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkoutCalendarView(displayedMonth: $displayedMonth, sessions: sessions)
                }

                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "clock",
                        description: Text("Finished workouts will appear here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            WorkoutHistoryDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.splitNameSnapshot)
                                    .font(.headline)
                                Text(summary(for: session))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                delete(session)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
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
}

private struct WorkoutCalendarView: View {
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
                        .foregroundStyle(.secondary)
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
            .foregroundStyle(isLogged ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if isLogged {
                    Circle().fill(appTheme.primaryColor)
                } else if isToday {
                    Circle().stroke(.secondary, lineWidth: 1)
                }
            }
    }
}

private struct WorkoutHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession

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
                    Text(notes)
                }
            }

            if !completedExerciseLogs.isEmpty {
                Section("Exercises Done") {
                    ForEach(completedExerciseLogs) { exerciseLog in
                        ExerciseHistorySummary(exerciseLog: exerciseLog)
                    }
                }
            }

            if !plannedExerciseLogs.isEmpty {
                Section("Planned But Not Logged") {
                    ForEach(plannedExerciseLogs) { exerciseLog in
                        Text(exerciseLog.exerciseNameSnapshot)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(session.splitNameSnapshot)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    WorkoutLoggerView(session: session, isEditingCompletedWorkout: true)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteWorkout()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func hasLoggedSets(_ exerciseLog: ExerciseLog) -> Bool {
        exerciseLog.setLogs.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
    }

    private var durationText: String? {
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
    let exerciseLog: ExerciseLog

    private var sets: [SetLog] {
        exerciseLog.setLogs.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exerciseLog.exerciseNameSnapshot)
                .font(.headline)

            if sets.isEmpty {
                Text("No sets logged")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sets) { set in
                    HStack {
                        Text("Set \(set.setNumber)")
                        Spacer()
                        Text("\(formatWeight(set.weight))kg x \(set.reps)")
                            .font(.headline)
                        if let rpe = set.rpe {
                            Text("RPE \(formatWeight(rpe))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
