import Foundation
import SwiftData

enum HistoryDisplaySnapshotBuilder {
    static func build(
        workouts: [HistoryWorkoutSnapshot],
        filters: HistoryFilters = HistoryFilters(),
        trainingDaysPerWeek: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HistoryDisplaySnapshot {
        let filtered = workouts.filter { workout in
            matches(workout, filters: filters, calendar: calendar)
        }

        return HistoryDisplaySnapshot(
            sessionRows: filtered.map(rowSnapshot),
            calendarDaySummaries: calendarSummaries(filtered, calendar: calendar),
            splitOptions: Array(Set(workouts.map { baseSplitName($0.splitName) })).sorted(),
            overview: monthlyOverview(
                workouts,
                trainingDaysPerWeek: trainingDaysPerWeek,
                now: now,
                calendar: calendar
            )
        )
    }

    private static func matches(
        _ workout: HistoryWorkoutSnapshot,
        filters: HistoryFilters,
        calendar: Calendar
    ) -> Bool {
        if let splitName = filters.splitName, baseSplitName(workout.splitName) != splitName {
            return false
        }
        let query = filters.exerciseNameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, !workout.exercises.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
            return false
        }
        if let minimumRating = filters.minimumRating, (workout.rating ?? 0) < minimumRating {
            return false
        }
        if let startDate = filters.startDate, workout.date < calendar.startOfDay(for: startDate) {
            return false
        }
        if let endDate = filters.endDate,
           workout.date >= (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate) {
            return false
        }
        return true
    }

    private static func loggedExercises(_ workout: HistoryWorkoutSnapshot) -> [HistoryWorkoutSnapshot.Exercise] {
        workout.exercises
            .filter { exercise in
                exercise.sets.contains { $0.completed || $0.weight > 0 || $0.reps > 0 || $0.rpe != nil }
            }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private static func rowSnapshot(_ workout: HistoryWorkoutSnapshot) -> HistorySessionRowSnapshot {
        let exercises = loggedExercises(workout)
        let setCount = exercises.flatMap(\.sets).filter(\.completed).count
        let topExercises = exercises.prefix(3).map(\.name)
        return HistorySessionRowSnapshot(
            id: workout.id,
            splitName: workout.splitName,
            date: workout.date,
            dateText: workout.date.formatted(date: .abbreviated, time: .shortened),
            exerciseCountText: "\(exercises.count)",
            setCountText: "\(setCount)",
            durationText: durationText(workout) ?? "No duration",
            ratingText: ratingText(workout.rating),
            topExerciseSummary: topExercises.isEmpty ? "No exercises logged" : topExercises.joined(separator: ", "),
            notesPreview: workout.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func monthlyOverview(
        _ workouts: [HistoryWorkoutSnapshot],
        trainingDaysPerWeek: Int?,
        now: Date,
        calendar: Calendar
    ) -> HistoryOverviewSnapshot {
        guard let currentMonth = calendar.dateInterval(of: .month, for: now) else { return .empty }
        let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: currentMonth.start) ?? currentMonth.start
        let previousMonth = calendar.dateInterval(of: .month, for: previousMonthDate)
        let currentWorkouts = workouts.filter { currentMonth.contains($0.date) }
        let previousWorkouts = previousMonth.map { interval in
            workouts.filter { interval.contains($0.date) }
        } ?? []
        let currentVisits = Set(currentWorkouts.map { calendar.startOfDay(for: $0.date) }).count
        let previousVisits = Set(previousWorkouts.map { calendar.startOfDay(for: $0.date) }).count
        let currentDuration = currentWorkouts.reduce(0) { $0 + durationSeconds($1) }
        let previousDuration = previousWorkouts.reduce(0) { $0 + durationSeconds($1) }
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth.start)?.count ?? 30
        let monthlyTarget = trainingDaysPerWeek.map {
            max(1, Int((Double(daysInMonth * $0) / 7).rounded()))
        }

        return HistoryOverviewSnapshot(
            monthTitle: currentMonth.start.formatted(.dateTime.month(.wide).year()),
            currentVisitCount: currentVisits,
            monthlyTarget: monthlyTarget,
            progress: monthlyTarget.map { min(1, Double(currentVisits) / Double($0)) } ?? 0,
            currentDurationText: currentDuration > 0 ? formatDuration(currentDuration) : "No duration",
            previousVisitCount: previousVisits,
            previousDurationText: previousDuration > 0 ? formatDuration(previousDuration) : "No duration",
            goalSourceText: trainingDaysPerWeek.map { "Based on \($0) \($0 == 1 ? "day" : "days")/week" }
        )
    }

    private static func calendarSummaries(
        _ workouts: [HistoryWorkoutSnapshot],
        calendar: Calendar
    ) -> [HistoryCalendarDaySummary] {
        Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
            .map { date, workouts in
                let ordered = workouts.sorted { $0.date < $1.date }
                let exercises = ordered.flatMap(loggedExercises)
                let splitNames = ordered.map { baseSplitName($0.splitName) }
                let completedSets = exercises.flatMap(\.sets).filter(\.completed).count
                let duration = ordered.reduce(0) { $0 + durationSeconds($1) }
                let ratings = ordered.compactMap(\.rating)
                let ratingSummary: String? = {
                    guard !ratings.isEmpty else { return nil }
                    if ratings.count == 1 { return "\(ratings[0])/5 feel" }
                    let average = Double(ratings.reduce(0, +)) / Double(ratings.count)
                    return "avg \(average.formatted(.number.precision(.fractionLength(1))))/5 feel"
                }()
                let metrics = [
                    collapsedSplitSummary(splitNames),
                    duration > 0 ? formatDuration(duration) : nil,
                    "\(completedSets) sets",
                    "\(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises")",
                    ratingSummary
                ].compactMap { $0 }.joined(separator: " · ")
                let names = exercises.prefix(3).map(\.name)
                return HistoryCalendarDaySummary(
                    date: date,
                    title: ordered.count == 1 ? (splitNames.first ?? "Workout") : "\(ordered.count) workouts logged",
                    metricLine: metrics,
                    helperLine: ordered.count == 1
                        ? (names.isEmpty ? "No exercises logged" : names.joined(separator: ", "))
                        : "Sessions: \(splitNames.joined(separator: ", "))",
                    sessionCount: ordered.count
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func durationSeconds(_ workout: HistoryWorkoutSnapshot) -> Int {
        if let seconds = workout.durationSeconds { return seconds }
        if let minutes = workout.durationMinutes { return minutes * 60 }
        if let startedAt = workout.startedAt, let endedAt = workout.endedAt {
            return max(
                0,
                Int(endedAt.timeIntervalSince(startedAt)) - max(0, workout.accumulatedPausedSeconds)
            )
        }
        return 0
    }

    private static func durationText(_ workout: HistoryWorkoutSnapshot) -> String? {
        let seconds = durationSeconds(workout)
        return seconds > 0 ? formatDuration(seconds) : nil
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours) hr \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) sec"
    }

    private static func ratingText(_ rating: Int?) -> String? {
        switch rating {
        case 1: "Rough"
        case 2: "Okay"
        case 3: "Good"
        case 4: "Great"
        case 5: "Excellent"
        default: nil
        }
    }

    private static func baseSplitName(_ name: String) -> String {
        name.components(separatedBy: " - ").first ?? name
    }

    private static func collapsedSplitSummary(_ names: [String]) -> String {
        let nonEmptyNames = names.filter { !$0.isEmpty }
        let groupedNames: [String: [String]] = Dictionary(grouping: nonEmptyNames, by: { $0 })
        let unsortedCounts: [(name: String, count: Int)] = groupedNames.map { entry in
            (name: entry.key, count: entry.value.count)
        }
        let counts = unsortedCounts.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
        }
        return counts.prefix(2)
            .map { $0.count > 1 ? "\($0.name) x\($0.count)" : $0.name }
            .joined(separator: " + ")
    }
}
