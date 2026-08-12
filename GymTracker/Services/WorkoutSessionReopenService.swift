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

struct WorkoutSessionCompletionState {
    let date: Date
    let endedAt: Date?
    let durationMinutes: Int?
    let durationSeconds: Int?
    let pausedAt: Date?
    let accumulatedPausedSeconds: Int
    let perceivedDifficulty: Int?
    let completed: Bool

    init(_ session: WorkoutSession) {
        date = session.date
        endedAt = session.endedAt
        durationMinutes = session.durationMinutes
        durationSeconds = session.durationSeconds
        pausedAt = session.pausedAt
        accumulatedPausedSeconds = session.accumulatedPausedSeconds
        perceivedDifficulty = session.perceivedDifficulty
        completed = session.completed
    }

    func restore(_ session: WorkoutSession) {
        session.date = date
        session.endedAt = endedAt
        session.durationMinutes = durationMinutes
        session.durationSeconds = durationSeconds
        session.pausedAt = pausedAt
        session.accumulatedPausedSeconds = accumulatedPausedSeconds
        session.perceivedDifficulty = perceivedDifficulty
        session.completed = completed
    }
}

struct WorkoutSessionDurationService {
    static let outlierThresholdSeconds = 4 * 60 * 60

    func recordedDurationSeconds(for session: WorkoutSession, now: Date = .now) -> Int? {
        if let durationSeconds = session.durationSeconds {
            return max(0, durationSeconds)
        }
        if let durationMinutes = session.durationMinutes {
            return max(0, durationMinutes * 60)
        }
        guard let startedAt = session.startedAt else { return nil }
        let end = session.endedAt ?? now
        return max(
            0,
            Int(end.timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds
        )
    }

    @discardableResult
    func apply(activeDurationSeconds: Int, to session: WorkoutSession) -> Bool {
        guard activeDurationSeconds >= 60 else { return false }

        session.durationSeconds = activeDurationSeconds
        session.durationMinutes = max(1, Int(ceil(Double(activeDurationSeconds) / 60)))
        if let startedAt = session.startedAt {
            session.endedAt = startedAt.addingTimeInterval(
                TimeInterval(activeDurationSeconds + max(0, session.accumulatedPausedSeconds))
            )
        }
        return true
    }
}
