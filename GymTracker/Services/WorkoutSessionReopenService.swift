import Foundation

struct WorkoutSessionReopenService {
    func reopen(_ session: WorkoutSession) {
        session.completed = false
        session.endedAt = nil
        session.durationSeconds = nil
        session.durationMinutes = nil
        session.pausedAt = nil
    }
}

