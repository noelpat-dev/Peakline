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

    static func repairCompletedSessionDates(in context: ModelContext) {
        do {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            var repairedAnySession = false

            for session in sessions where session.completed {
                guard let startedAt = session.startedAt else { continue }
                guard abs(session.date.timeIntervalSince(startedAt)) > 1 else { continue }

                session.date = startedAt
                repairedAnySession = true
            }

            if repairedAnySession {
                try context.save()
            }
        } catch {
            assertionFailure("Workout date repair failed: \(error)")
        }
    }
}
