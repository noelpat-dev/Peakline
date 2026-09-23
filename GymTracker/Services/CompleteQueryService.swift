import SwiftData

/// Reads a descriptor in bounded pages so routes can keep a small warm query
/// while still hydrating the complete result when a user needs older data.
enum CompleteQueryService {
    static let defaultPageSize = 200

    static func fetchAll<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        in context: ModelContext,
        pageSize: Int = defaultPageSize
    ) throws -> [T] {
        try collect(pageSize: pageSize) { offset, limit in
            var page = descriptor
            page.fetchOffset = offset
            page.fetchLimit = limit
            return try context.fetch(page)
        }
    }

    static func fetchPage<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        in context: ModelContext,
        offset: Int,
        pageSize: Int = defaultPageSize
    ) throws -> [T] {
        var page = descriptor
        page.fetchOffset = offset
        page.fetchLimit = pageSize
        return try context.fetch(page)
    }

    static func collect<T>(
        pageSize: Int = defaultPageSize,
        fetchPage: (_ offset: Int, _ limit: Int) throws -> [T]
    ) throws -> [T] {
        precondition(pageSize > 0)
        var result: [T] = []
        var offset = 0
        while true {
            let page = try fetchPage(offset, pageSize)
            result.append(contentsOf: page)
            guard page.count == pageSize else { return result }
            offset += page.count
        }
    }

    /// Resolves only the sessions that contain the selected exercise. The
    /// exercise-log index is paged, then session IDs are fetched in chunks so
    /// a drill-down never scans unrelated session relationships.
    static func sessions(
        containingExerciseID exerciseID: UUID,
        in context: ModelContext,
        pageSize: Int = defaultPageSize
    ) throws -> [WorkoutSession] {
        let logDescriptor = FetchDescriptor<ExerciseLog>(
            predicate: #Predicate<ExerciseLog> { log in
                log.exerciseId == exerciseID && log.workoutSession?.completed == true
            }
        )
        let logs = try fetchAll(logDescriptor, in: context, pageSize: pageSize)
        let ids = Array(Set(logs.map(\.workoutSessionId)))
        guard !ids.isEmpty else { return [] }

        var sessions: [WorkoutSession] = []
        for chunk in ids.chunked(into: pageSize) {
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate<WorkoutSession> { session in
                    chunk.contains(session.id)
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            sessions.append(contentsOf: try context.fetch(descriptor))
        }
        return sessions.sorted { $0.date > $1.date }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
