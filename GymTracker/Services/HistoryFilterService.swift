import Foundation
import SwiftData

struct HistoryMonthIntervals {
    let current: DateInterval
    let previous: DateInterval

    var comparison: DateInterval {
        DateInterval(start: previous.start, end: current.end)
    }
}

enum HistoryFilterService {
    static func monthIntervals(
        for selectedMonth: Date,
        calendar: Calendar = .current
    ) -> HistoryMonthIntervals? {
        guard let current = calendar.dateInterval(of: .month, for: selectedMonth),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: current.start),
              let previous = calendar.dateInterval(of: .month, for: previousStart)
        else {
            return nil
        }

        return HistoryMonthIntervals(current: current, previous: previous)
    }

    static func completedSessionsDescriptor(
        for selectedMonth: Date,
        calendar: Calendar = .current
    ) -> FetchDescriptor<WorkoutSession>? {
        guard let intervals = monthIntervals(for: selectedMonth, calendar: calendar) else {
            return nil
        }

        let start = intervals.comparison.start
        let end = intervals.comparison.end
        return FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.completed && session.date >= start && session.date < end
            },
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
    }
}

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
