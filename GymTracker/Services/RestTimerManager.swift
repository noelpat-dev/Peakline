import Foundation

struct RestTimerState: Equatable {
    static let defaultDurationSeconds = 120

    var startDate: Date?
    var endDate: Date?
    var exerciseName: String?
    var nextSetNumber: Int?
    var completionDate: Date?

    init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        exerciseName: String? = nil,
        nextSetNumber: Int? = nil,
        completionDate: Date? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.exerciseName = exerciseName
        self.nextSetNumber = nextSetNumber
        self.completionDate = completionDate
    }

    var isRunning: Bool {
        guard let endDate, completionDate == nil else { return false }
        return endDate > Date()
    }

    var isComplete: Bool {
        completionDate != nil
    }

    var durationSeconds: TimeInterval {
        guard let startDate, let endDate else { return 0 }
        return max(1, endDate.timeIntervalSince(startDate))
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard let endDate, completionDate == nil else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(date)))
    }

    func progress(at date: Date = .now) -> Double {
        guard let startDate, let endDate else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        return min(1, max(0, elapsed / max(1, endDate.timeIntervalSince(startDate))))
    }

    mutating func start(
        durationSeconds: Int,
        exerciseName: String? = nil,
        nextSetNumber: Int? = nil,
        now: Date = .now
    ) {
        let duration = max(1, durationSeconds)
        startDate = now
        endDate = now.addingTimeInterval(TimeInterval(duration))
        self.exerciseName = exerciseName
        self.nextSetNumber = nextSetNumber
        completionDate = nil
    }

    mutating func extend(by seconds: Int, now: Date = .now) {
        guard let endDate, completionDate == nil else { return }
        self.endDate = max(endDate, now).addingTimeInterval(TimeInterval(seconds))
    }

    mutating func markComplete(at date: Date = .now) {
        guard endDate != nil, completionDate == nil else { return }
        completionDate = date
    }

    mutating func reset() {
        self = RestTimerState()
    }
}
