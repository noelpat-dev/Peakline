import Foundation

struct HistoryFilters: Equatable {
    var splitName: String?
    var exerciseNameQuery = ""
    var minimumRating: Int?
    var startDate: Date?
    var endDate: Date?

    var isActive: Bool {
        splitName != nil ||
        !exerciseNameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        minimumRating != nil ||
        startDate != nil ||
        endDate != nil
    }
}

struct HistoryFilterService {
    func filter(_ sessions: [WorkoutSession], using filters: HistoryFilters, calendar: Calendar = .current) -> [WorkoutSession] {
        sessions.filter { session in
            matchesSplit(session, splitName: filters.splitName) &&
            matchesExercise(session, query: filters.exerciseNameQuery) &&
            matchesRating(session, minimumRating: filters.minimumRating) &&
            matchesDateRange(session, startDate: filters.startDate, endDate: filters.endDate, calendar: calendar)
        }
    }

    private func matchesSplit(_ session: WorkoutSession, splitName: String?) -> Bool {
        guard let splitName else { return true }
        return session.splitNameSnapshot.components(separatedBy: " - ").first == splitName
    }

    private func matchesExercise(_ session: WorkoutSession, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        return session.exerciseLogs.contains {
            $0.exerciseNameSnapshot.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func matchesRating(_ session: WorkoutSession, minimumRating: Int?) -> Bool {
        guard let minimumRating else { return true }
        return (session.perceivedDifficulty ?? 0) >= minimumRating
    }

    private func matchesDateRange(_ session: WorkoutSession, startDate: Date?, endDate: Date?, calendar: Calendar) -> Bool {
        if let startDate, session.date < calendar.startOfDay(for: startDate) {
            return false
        }

        if let endDate, session.date > (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate) {
            return false
        }

        return true
    }
}
