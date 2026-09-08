import Foundation
import SwiftData

@MainActor
enum WorkoutSessionDateService {
    static func loggedDate(for session: WorkoutSession) -> Date {
        session.startedAt ?? session.date
    }

    static func alignLoggedDateToStartDate(_ session: WorkoutSession) {
        session.date = loggedDate(for: session)
    }

    @discardableResult
    static func repairCompletedSessionDates(in context: ModelContext) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        var repairedCount = 0

        for session in sessions where session.completed {
            guard let startedAt = session.startedAt else { continue }
            guard abs(session.date.timeIntervalSince(startedAt)) > 1 else { continue }

            session.date = startedAt
            repairedCount += 1
        }

        if repairedCount > 0 {
            try context.save()
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .completedWorkoutEdited)
        }
        return repairedCount
    }
}
