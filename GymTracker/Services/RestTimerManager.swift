import Foundation

struct RestTimerState: Equatable {
    var endDate: Date?
    var exerciseName: String?
    var nextSetNumber: Int?

    var isRunning: Bool {
        guard let endDate else { return false }
        return endDate > Date()
    }
}
