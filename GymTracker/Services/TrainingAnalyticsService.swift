import Foundation

struct PRRecord: Identifiable, Equatable {
    let id: UUID
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

enum PRType: String, CaseIterable, Codable, Identifiable {
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

struct WeeklyTrainingSummary: Equatable {
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

struct SplitConsistencySummary: Equatable {
    let pushCount: Int
    let pullCount: Int
    let legsCount: Int
    let missedSplitName: String?
    let balanceDescription: String
}

struct TrainingAnalyticsService {
    func prTimeline(from sessions: [WorkoutSession]) -> [PRRecord] {
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
        prTimeline(from: sessions).filter { $0.sessionId == session.id }
    }

    func weeklySummary(from sessions: [WorkoutSession], now: Date = Date()) -> WeeklyTrainingSummary {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
        let weekSessions = sessions.filter { $0.completed && $0.date >= week.start && $0.date < week.end }
        let sets = weekSessions.flatMap { session in session.exerciseLogs.flatMap(workingSets) }
        let splitCounts = Dictionary(grouping: weekSessions, by: { baseSplitName($0.splitNameSnapshot) }).mapValues(\.count)
        let prs = prTimeline(from: sessions).filter { $0.date >= week.start && $0.date < week.end }
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

    private func record(session: WorkoutSession, log: ExerciseLog, set: SetLog?, type: PRType, value: Double, previous: Double) -> PRRecord {
        PRRecord(
            id: UUID(),
            sessionId: session.id,
            exerciseLogId: log.id,
            setLogId: set?.id,
            exerciseName: log.exerciseNameSnapshot,
            date: session.date,
            workoutSplitName: baseSplitName(session.splitNameSnapshot),
            prType: type,
            value: value,
            displayValue: display(value, type: type, set: set),
            previousDisplayValue: display(previous, type: type, set: nil),
            improvementDescription: improvement(type: type, value: value, previous: previous, set: set)
        )
    }

    private func improvement(type: PRType, value: Double, previous: Double, set: SetLog?) -> String {
        switch type {
        case .heaviestWeight:
            return "New heaviest set: \(format(value))kg"
        case .bestRepsAtWeight:
            return "+\(Int(value - previous)) reps at \(format(set?.weight ?? 0))kg"
        case .estimatedOneRepMax:
            return "Estimated 1RM up \(format(value - previous))kg"
        case .bestSetVolume:
            return "New best-set volume: \(format(value))kg"
        case .totalExerciseVolume:
            return "Total exercise volume up \(format(value - previous))kg"
        }
    }

    private func display(_ value: Double, type: PRType, set: SetLog?) -> String {
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

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
