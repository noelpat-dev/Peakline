import Foundation
import SwiftData

struct PRRecord: Identifiable, Equatable, Sendable {
    let id: String
    let sessionId: UUID
    let exerciseLogId: UUID
    let setLogId: UUID?
    let exerciseName: String
    let date: Date
    let workoutSplitName: String?
    let prType: PRType
    let value: Double
    let displayValue: String
    let previousDisplayValue: String?
    let improvementDescription: String
}

enum PRType: String, CaseIterable, Codable, Identifiable, Sendable {
    case heaviestWeight
    case bestRepsAtWeight
    case estimatedOneRepMax
    case bestSetVolume
    case totalExerciseVolume

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heaviestWeight:
            return "Heaviest weight"
        case .bestRepsAtWeight:
            return "Best reps"
        case .estimatedOneRepMax:
            return "Estimated 1RM"
        case .bestSetVolume:
            return "Best-set volume"
        case .totalExerciseVolume:
            return "Total volume"
        }
    }
}

struct WeeklyTrainingSummary: Equatable, Sendable {
    let weekStart: Date
    let weekEnd: Date
    let completedWorkouts: Int
    let workingSets: Int
    let splitCounts: [String: Int]
    let totalTonnage: Double
    let bestSetVolumeTotal: Double
    let prCount: Int
    let consistencyMessage: String
}

struct SplitConsistencySummary: Equatable, Sendable {
    let pushCount: Int
    let pullCount: Int
    let legsCount: Int
    let missedSplitName: String?
    let balanceDescription: String
}

struct WorkoutAnalyticsSession: Sendable {
    let id: UUID
    let date: Date
    let splitNameSnapshot: String
    let completed: Bool
    let exerciseLogs: [ExerciseAnalyticsLog]

    init(id: UUID, date: Date, splitNameSnapshot: String, completed: Bool, exerciseLogs: [ExerciseAnalyticsLog]) {
        self.id = id
        self.date = date
        self.splitNameSnapshot = splitNameSnapshot
        self.completed = completed
        self.exerciseLogs = exerciseLogs
    }

    init(session: WorkoutSession) {
        self.id = session.id
        self.date = session.date
        self.splitNameSnapshot = session.splitNameSnapshot
        self.completed = session.completed
        self.exerciseLogs = session.exerciseLogs.map(ExerciseAnalyticsLog.init)
    }
}

struct ExerciseAnalyticsLog: Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseNameSnapshot: String
    let orderIndex: Int
    let notes: String?
    let setLogs: [SetAnalyticsLog]

    init(id: UUID, exerciseId: UUID, exerciseNameSnapshot: String, orderIndex: Int, notes: String?, setLogs: [SetAnalyticsLog]) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.orderIndex = orderIndex
        self.notes = notes
        self.setLogs = setLogs
    }

    init(log: ExerciseLog) {
        self.id = log.id
        self.exerciseId = log.exerciseId
        self.exerciseNameSnapshot = log.exerciseNameSnapshot
        self.orderIndex = log.orderIndex
        self.notes = log.notes
        self.setLogs = log.setLogs.map(SetAnalyticsLog.init)
    }
}

struct SetAnalyticsLog: Sendable {
    let id: UUID
    let setNumber: Int
    let weight: Double
    let reps: Int
    let isWarmup: Bool
    let completed: Bool

    init(id: UUID, setNumber: Int, weight: Double, reps: Int, isWarmup: Bool, completed: Bool) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.isWarmup = isWarmup
        self.completed = completed
    }

    init(set: SetLog) {
        self.id = set.id
        self.setNumber = set.setNumber
        self.weight = set.weight
        self.reps = set.reps
        self.isWarmup = set.isWarmup
        self.completed = set.completed
    }
}

enum WorkoutAnalyticsSnapshotBuilder {
    @MainActor
    static func snapshots(from sessions: [WorkoutSession], in modelContext: ModelContext) throws -> [WorkoutAnalyticsSession] {
        guard !sessions.isEmpty else { return [] }

        let sessionIds = sessions.map(\.id)
        var logDescriptor = FetchDescriptor<ExerciseLog>(
            predicate: #Predicate<ExerciseLog> { sessionIds.contains($0.workoutSessionId) },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        logDescriptor.includePendingChanges = true

        let exerciseLogs = try modelContext.fetch(logDescriptor)
        let logIds = exerciseLogs.map(\.id)

        let setLogs: [SetLog]
        if logIds.isEmpty {
            setLogs = []
        } else {
            var setDescriptor = FetchDescriptor<SetLog>(
                predicate: #Predicate<SetLog> { logIds.contains($0.exerciseLogId) },
                sortBy: [SortDescriptor(\.setNumber)]
            )
            setDescriptor.includePendingChanges = true
            setLogs = try modelContext.fetch(setDescriptor)
        }

        let setsByLogId = Dictionary(grouping: setLogs, by: \.exerciseLogId)
        let logsBySessionId = Dictionary(grouping: exerciseLogs, by: \.workoutSessionId)

        return sessions.map { session in
            let logSnapshots = (logsBySessionId[session.id] ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { log in
                    let setSnapshots = (setsByLogId[log.id] ?? [])
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { set in
                            SetAnalyticsLog(
                                id: set.id,
                                setNumber: set.setNumber,
                                weight: set.weight,
                                reps: set.reps,
                                isWarmup: set.isWarmup,
                                completed: set.completed
                            )
                        }

                    return ExerciseAnalyticsLog(
                        id: log.id,
                        exerciseId: log.exerciseId,
                        exerciseNameSnapshot: log.exerciseNameSnapshot,
                        orderIndex: log.orderIndex,
                        notes: log.notes,
                        setLogs: setSnapshots
                    )
                }

            return WorkoutAnalyticsSession(
                id: session.id,
                date: session.date,
                splitNameSnapshot: session.splitNameSnapshot,
                completed: session.completed,
                exerciseLogs: logSnapshots
            )
        }
    }
}

struct TrainingAnalyticsService {
    func prTimeline(from sessions: [WorkoutSession]) -> [PRRecord] {
        prTimeline(from: sessions.map(WorkoutAnalyticsSession.init))
    }

    func prTimeline(from sessions: [WorkoutAnalyticsSession]) -> [PRRecord] {
        var records: [PRRecord] = []
        var bestWeightByExercise: [UUID: Double] = [:]
        var bestRepsByExerciseAndWeight: [String: Int] = [:]
        var bestOneRMByExercise: [UUID: Double] = [:]
        var bestSetVolumeByExercise: [UUID: Double] = [:]
        var bestTotalVolumeByExercise: [UUID: Double] = [:]

        for session in sessions.sorted(by: { $0.date < $1.date }) where session.completed {
            for log in session.exerciseLogs.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let sets = workingSets(in: log)
                guard !sets.isEmpty else { continue }

                let totalVolume = sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
                if let previous = bestTotalVolumeByExercise[log.exerciseId], totalVolume > previous {
                    records.append(record(session: session, log: log, set: nil, type: .totalExerciseVolume, value: totalVolume, previous: previous))
                }
                bestTotalVolumeByExercise[log.exerciseId] = max(bestTotalVolumeByExercise[log.exerciseId] ?? 0, totalVolume)

                for set in sets {
                    let weight = set.weight
                    let reps = set.reps
                    let oneRM = estimatedOneRepMax(set)
                    let setVolume = weight * Double(reps)
                    let weightKey = "\(log.exerciseId.uuidString)-\(format(weight))"

                    if let previous = bestWeightByExercise[log.exerciseId], weight > previous {
                        records.append(record(session: session, log: log, set: set, type: .heaviestWeight, value: weight, previous: previous))
                    }
                    bestWeightByExercise[log.exerciseId] = max(bestWeightByExercise[log.exerciseId] ?? 0, weight)

                    if let previous = bestRepsByExerciseAndWeight[weightKey], reps > previous {
                        records.append(record(session: session, log: log, set: set, type: .bestRepsAtWeight, value: Double(reps), previous: Double(previous)))
                    }
                    bestRepsByExerciseAndWeight[weightKey] = max(bestRepsByExerciseAndWeight[weightKey] ?? 0, reps)

                    if let previous = bestOneRMByExercise[log.exerciseId], oneRM > previous {
                        records.append(record(session: session, log: log, set: set, type: .estimatedOneRepMax, value: oneRM, previous: previous))
                    }
                    bestOneRMByExercise[log.exerciseId] = max(bestOneRMByExercise[log.exerciseId] ?? 0, oneRM)

                    if let previous = bestSetVolumeByExercise[log.exerciseId], setVolume > previous {
                        records.append(record(session: session, log: log, set: set, type: .bestSetVolume, value: setVolume, previous: previous))
                    }
                    bestSetVolumeByExercise[log.exerciseId] = max(bestSetVolumeByExercise[log.exerciseId] ?? 0, setVolume)
                }
            }
        }

        return records.sorted { $0.date > $1.date }
    }

    func prs(for session: WorkoutSession, in sessions: [WorkoutSession]) -> [PRRecord] {
        let sessionId = session.id
        return prTimeline(from: sessions).filter { $0.sessionId == sessionId }
    }

    func weeklySummary(from sessions: [WorkoutSession], now: Date = Date()) -> WeeklyTrainingSummary {
        weeklySummary(from: sessions.map(WorkoutAnalyticsSession.init), now: now)
    }

    func weeklySummary(from sessions: [WorkoutAnalyticsSession], now: Date = Date(), prRecords: [PRRecord]? = nil) -> WeeklyTrainingSummary {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
        let weekSessions = sessions.filter { $0.completed && $0.date >= week.start && $0.date < week.end }
        let sets = weekSessions.flatMap { session in session.exerciseLogs.flatMap(workingSets) }
        let splitCounts = Dictionary(grouping: weekSessions, by: { baseSplitName($0.splitNameSnapshot) }).mapValues(\.count)
        let prs = (prRecords ?? prTimeline(from: sessions)).filter { $0.date >= week.start && $0.date < week.end }
        let consistency = splitConsistency(from: sessions, now: now)

        return WeeklyTrainingSummary(
            weekStart: week.start,
            weekEnd: week.end,
            completedWorkouts: weekSessions.count,
            workingSets: sets.count,
            splitCounts: splitCounts,
            totalTonnage: sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) },
            bestSetVolumeTotal: weekSessions.reduce(0) { total, session in
                total + session.exerciseLogs.compactMap { log in
                    workingSets(in: log).map { $0.weight * Double($0.reps) }.max()
                }.reduce(0, +)
            },
            prCount: prs.count,
            consistencyMessage: consistency.balanceDescription
        )
    }

    func splitConsistency(from sessions: [WorkoutSession], now: Date = Date()) -> SplitConsistencySummary {
        splitConsistency(from: sessions.map(WorkoutAnalyticsSession.init), now: now)
    }

    func splitConsistency(from sessions: [WorkoutAnalyticsSession], now: Date = Date()) -> SplitConsistencySummary {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
        let weekSessions = sessions.filter { $0.completed && $0.date >= week.start && $0.date < week.end }
        let counts = Dictionary(grouping: weekSessions, by: { baseSplitName($0.splitNameSnapshot) }).mapValues(\.count)
        let push = counts["Push"] ?? 0
        let pull = counts["Pull"] ?? 0
        let legs = counts["Legs"] ?? 0
        let missed = [("Push", push), ("Pull", pull), ("Legs", legs)].min { $0.1 < $1.1 }?.0
        let missedName = [push, pull, legs].contains(0) ? missed : nil
        let description = missedName.map { "\($0) is due next." } ?? "Push/Pull/Legs is balanced this week."

        return SplitConsistencySummary(
            pushCount: push,
            pullCount: pull,
            legsCount: legs,
            missedSplitName: missedName,
            balanceDescription: description
        )
    }

    func workingSets(in log: ExerciseLog) -> [SetLog] {
        log.setLogs.filter { $0.completed && !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
    }

    func workingSets(in log: ExerciseAnalyticsLog) -> [SetAnalyticsLog] {
        log.setLogs.filter { $0.completed && !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
    }

    private func record(session: WorkoutAnalyticsSession, log: ExerciseAnalyticsLog, set: SetAnalyticsLog?, type: PRType, value: Double, previous: Double) -> PRRecord {
        PRRecord(
            id: [
                session.id.uuidString,
                log.id.uuidString,
                set?.id.uuidString ?? "exercise-total",
                type.rawValue
            ].joined(separator: "-"),
            sessionId: session.id,
            exerciseLogId: log.id,
            setLogId: set?.id,
            exerciseName: log.exerciseNameSnapshot,
            date: session.date,
            workoutSplitName: baseSplitName(session.splitNameSnapshot),
            prType: type,
            value: value,
            displayValue: display(value, type: type, set: set),
            previousDisplayValue: display(previous, type: type, weight: nil),
            improvementDescription: improvement(type: type, value: value, previous: previous, weight: set?.weight)
        )
    }

    private func improvement(type: PRType, value: Double, previous: Double, set: SetLog?) -> String {
        improvement(type: type, value: value, previous: previous, weight: set?.weight)
    }

    private func improvement(type: PRType, value: Double, previous: Double, weight: Double?) -> String {
        switch type {
        case .heaviestWeight:
            return "New heaviest set: \(format(value))kg"
        case .bestRepsAtWeight:
            return "+\(Int(value - previous)) reps at \(format(weight ?? 0))kg"
        case .estimatedOneRepMax:
            return "Estimated 1RM up \(format(value - previous))kg"
        case .bestSetVolume:
            return "New best-set volume: \(format(value))kg"
        case .totalExerciseVolume:
            return "Total exercise volume up \(format(value - previous))kg"
        }
    }

    private func display(_ value: Double, type: PRType, set: SetLog?) -> String {
        display(value, type: type, weight: set?.weight)
    }

    private func display(_ value: Double, type: PRType, set: SetAnalyticsLog?) -> String {
        display(value, type: type, weight: set?.weight)
    }

    private func display(_ value: Double, type: PRType, weight: Double?) -> String {
        switch type {
        case .bestRepsAtWeight:
            return "\(Int(value)) reps"
        default:
            return "\(format(value))kg"
        }
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func estimatedOneRepMax(_ set: SetAnalyticsLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
