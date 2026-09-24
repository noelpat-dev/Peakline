import Foundation

enum SummitSnapshotBuilder {
    private static let liftWeekCount = 12
    private static let minimumLiftSessions = 3
    private static let recentPRInterval: TimeInterval = 7 * 24 * 60 * 60

    static func inputs(
        from sessions: [WorkoutSession],
        exercises: [Exercise],
        unitSystem: UnitSystem
    ) -> [SummitSessionInput] {
        let exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return sessions.enumerated()
            .filter { $0.element.completed }
            .sorted {
                $0.element.date == $1.element.date
                    ? $0.offset < $1.offset
                    : $0.element.date < $1.element.date
            }
            .map { _, session in
                let sets = session.exerciseLogs
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .flatMap { exerciseLog -> [SummitSetInput] in
                        let exercise = exercisesByID[exerciseLog.exerciseId]
                        return exerciseLog.setLogs
                            .filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
                            .sorted { $0.setNumber < $1.setNumber }
                            .map { set in
                                SummitSetInput(
                                    id: set.id,
                                    exerciseID: exerciseLog.exerciseId,
                                    exerciseName: exerciseLog.exerciseNameSnapshot.isEmpty
                                        ? exercise?.name ?? "Exercise"
                                        : exerciseLog.exerciseNameSnapshot,
                                    pattern: exercise?.movementPattern ?? .other,
                                    isBodyweight: exercise.map { $0.equipment == .bodyweight } ?? false,
                                    isCompound: exercise?.isCompound ?? false,
                                    weightKg: SummitWeightFormatting.kilograms(set.weight, unitSystem: unitSystem),
                                    reps: set.reps
                                )
                            }
                    }

                return SummitSessionInput(
                    id: session.id,
                    date: session.date,
                    title: session.splitNameSnapshot,
                    durationMinutes: session.durationMinutes,
                    sets: sets
                )
            }
    }

    static func bodyweightInputs(from logs: [BodyweightLog]) -> [SummitBodyweightInput] {
        logs.map { log in
            SummitBodyweightInput(
                date: log.date,
                weightKg: SummitWeightFormatting.kilograms(log.weight, unitSystem: log.unit)
            )
        }
    }

    static func build(
        sessions: [SummitSessionInput],
        bodyweights: [SummitBodyweightInput],
        profileBodyweightKg: Double?,
        expeditionStart: Date?,
        now: Date,
        calendar: Calendar
    ) -> SummitSnapshot {
        let chronologicalSessions = sessions.enumerated()
            .filter { $0.element.date <= now }
            .sorted {
                $0.element.date == $1.element.date
                    ? $0.offset < $1.offset
                    : $0.element.date < $1.element.date
            }
            .map(\.element)
        let sortedBodyweights = bodyweights.sorted { $0.date < $1.date }
        let bodyweightBySession = bodyweightsBySession(
            sessions: chronologicalSessions,
            bodyweights: sortedBodyweights,
            profileBodyweightKg: profileBodyweightKg
        )
        var liftCalendar = calendar
        liftCalendar.firstWeekday = 2
        let currentLiftWeekStart = liftCalendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? liftCalendar.startOfDay(for: now)
        let liftWindowStart = liftCalendar.date(
            byAdding: .weekOfYear,
            value: 1 - liftWeekCount,
            to: currentLiftWeekStart
        ) ?? currentLiftWeekStart

        var previousBestByExercise: [UUID: Double] = [:]
        var sessionCountByExercise: [UUID: Int] = [:]
        var observationsByExercise: [UUID: [LiftObservation]] = [:]
        var bestSetsByExercise: [UUID: [LiftSetObservation]] = [:]
        var prSetIDs: Set<UUID> = []
        var metresBySession: [UUID: Int] = [:]
        var climbs: [SummitSessionClimb] = []
        var totalMetres = 0

        for session in chronologicalSessions {
            let bodyweightKg = bodyweightBySession[session.id] ?? profileBodyweightKg ?? 75
            var setVolumes: [Double] = []
            var climbWork = 0.0
            var volumeKg = 0.0
            var hasLoadedSets = false
            var setsByExercise: [UUID: [LiftSetObservation]] = [:]

            for set in session.sets {
                let setVolume = set.weightKg * Double(set.reps)
                setVolumes.append(setVolume)
                guard set.reps > 0 else { continue }

                climbWork += SummitProgressService.metreWork(for: set, bodyweightKg: bodyweightKg)
                volumeKg += setVolume
                hasLoadedSets = hasLoadedSets || set.weightKg > 0
                let estimatedLoad = SummitProgressService.effectiveLoad(for: set, bodyweightKg: bodyweightKg)
                let e1RM = TrainingAnalyticsService.estimatedOneRepMax(weight: estimatedLoad, reps: set.reps)
                let observation = LiftSetObservation(set: set, e1RM: e1RM, date: session.date)
                setsByExercise[set.exerciseID, default: []].append(observation)
                if session.date >= liftWindowStart {
                    var bestSets = bestSetsByExercise[set.exerciseID, default: []]
                    // Identical sets from the same day are one "best set", not three.
                    let isRepeat = bestSets.contains {
                        $0.set.weightKg == set.weightKg
                            && $0.set.reps == set.reps
                            && calendar.isDate($0.date, inSameDayAs: session.date)
                    }
                    if !isRepeat { bestSets.append(observation) }
                    bestSets.sort { $0.e1RM > $1.e1RM }
                    bestSetsByExercise[set.exerciseID] = Array(bestSets.prefix(3))
                }
            }

            let metres = bodyweightKg > 0 ? Int((climbWork / bodyweightKg).rounded()) : 0
            let largestSetVolume = setVolumes.max() ?? 0
            let setProfile = setVolumes.map { largestSetVolume > 0 ? $0 / largestSetVolume : 0 }

            var prs: [SummitPR] = []
            for (exerciseID, exerciseSets) in setsByExercise {
                guard let bestSet = exerciseSets.max(by: { $0.e1RM < $1.e1RM }) else { continue }
                let hasEarlierSession = sessionCountByExercise[exerciseID, default: 0] > 0
                let previousBest = previousBestByExercise[exerciseID] ?? -.infinity
                let isPR = hasEarlierSession && bestSet.e1RM > previousBest

                if isPR {
                    prSetIDs.insert(bestSet.set.id)
                    prs.append(SummitPR(
                        exerciseName: bestSet.set.exerciseName,
                        weightKg: bestSet.set.weightKg,
                        reps: bestSet.set.reps,
                        isBodyweight: bestSet.set.isBodyweight
                    ))
                }

                previousBestByExercise[exerciseID] = max(previousBest, bestSet.e1RM)
                sessionCountByExercise[exerciseID, default: 0] += 1
                observationsByExercise[exerciseID, default: []].append(
                    LiftObservation(
                        date: session.date,
                        name: bestSet.set.exerciseName,
                        e1RM: bestSet.e1RM,
                        isCompound: bestSet.set.isCompound,
                        isPR: isPR
                    )
                )
            }

            let passedPeak = SummitProgressService.didPassPeak(before: totalMetres, after: totalMetres + metres)
            climbs.append(SummitSessionClimb(
                id: session.id,
                date: session.date,
                title: session.title,
                metres: metres,
                durationMinutes: session.durationMinutes,
                setCount: session.sets.count,
                volumeKg: volumeKg,
                setProfile: setProfile,
                prs: prs.sorted { $0.exerciseName < $1.exerciseName },
                passedPeak: passedPeak,
                isLowerRoute: !hasLoadedSets
            ))
            metresBySession[session.id] = metres
            totalMetres += metres
        }

        let todayStart = calendar.startOfDay(for: now)
        let todayClimbs = climbs.filter { calendar.isDate($0.date, inSameDayAs: todayStart) }
        let gainedToday = todayClimbs.isEmpty ? nil : todayClimbs.reduce(0) { $0 + $1.metres }
        let altitude = SummitProgressService.altitude(totalMetres: totalMetres, gainedToday: gainedToday)
        let month = monthRidge(climbs: climbs, now: now, calendar: calendar)
        let lifts = liftPeaks(
            observationsByExercise: observationsByExercise,
            bestSetsByExercise: bestSetsByExercise,
            prSetIDs: prSetIDs,
            now: now,
            calendar: calendar
        )
        let cairn = SummitProgressService.cairn(
            sessionDates: chronologicalSessions.map(\.date),
            now: now,
            calendar: calendar
        )
        let expedition: ExpeditionProgress?
        if let expeditionStart {
            let expeditionSessions = chronologicalSessions.filter { $0.date >= expeditionStart }
            let climbed = expeditionSessions.reduce(0) { $0 + metresBySession[$1.id, default: 0] }
            let recentMetres = expeditionSessions.suffix(8).map { metresBySession[$0.id, default: 0] }
            expedition = SummitProgressService.expeditionProgress(
                route: SummitCatalog.machame,
                startDate: expeditionStart,
                climbedSinceStart: climbed,
                recentSessionMetres: recentMetres
            )
        } else {
            expedition = nil
        }

        return SummitSnapshot(
            altitude: altitude,
            month: month,
            log: Array(climbs.reversed()),
            lifts: lifts,
            cairn: cairn,
            expedition: expedition
        )
    }

    private static func bodyweightsBySession(
        sessions: [SummitSessionInput],
        bodyweights: [SummitBodyweightInput],
        profileBodyweightKg: Double?
    ) -> [UUID: Double] {
        var bodyweightIndex = 0
        var latestLoggedWeight: Double?
        var result: [UUID: Double] = [:]

        for session in sessions {
            while bodyweightIndex < bodyweights.count,
                  bodyweights[bodyweightIndex].date <= session.date {
                latestLoggedWeight = bodyweights[bodyweightIndex].weightKg
                bodyweightIndex += 1
            }
            result[session.id] = latestLoggedWeight ?? profileBodyweightKg ?? 75
        }

        return result
    }

    private static func monthRidge(climbs: [SummitSessionClimb], now: Date, calendar: Calendar) -> SummitMonthRidge {
        monthRidge(forMonthContaining: now, climbs: climbs, now: now, calendar: calendar)
    }

    /// Builds the ridge for any month. Past months show every day and no
    /// today tick; future months are all future days.
    static func monthRidge(
        forMonthContaining month: Date,
        climbs: [SummitSessionClimb],
        now: Date,
        calendar: Calendar
    ) -> SummitMonthRidge {
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? calendar.startOfDay(for: month)
        let nowMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let currentDayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let isCurrentMonth = monthStart == nowMonthStart
        let currentDay: Int
        if isCurrentMonth {
            currentDay = calendar.component(.day, from: now)
        } else {
            currentDay = monthStart < nowMonthStart ? currentDayCount : 0
        }
        var currentLoads: [Int: Int] = [:]
        var previousLoadsByDay: [Int: Int] = [:]

        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        for climb in climbs {
            let sessionMonthStart = calendar.dateInterval(of: .month, for: climb.date)?.start
            let day = calendar.component(.day, from: climb.date)
            if sessionMonthStart == monthStart, climb.date <= now {
                currentLoads[day, default: 0] += climb.metres
            } else if sessionMonthStart == previousMonthStart {
                previousLoadsByDay[day, default: 0] += climb.metres
            }
        }

        let currentMaximum = currentLoads.values.max() ?? 0
        let dayLoads = (1...currentDayCount).map { day -> Double? in
            guard day <= currentDay else { return nil }
            let load = currentLoads[day, default: 0]
            return currentMaximum > 0 ? Double(load) / Double(currentMaximum) : 0
        }
        let previousDayCount = calendar.range(of: .day, in: .month, for: previousMonthStart)?.count ?? 31
        let previousMaximum = previousLoadsByDay.values.max() ?? 0
        let previousMonthLoads = (1...previousDayCount).map { day in
            let load = previousLoadsByDay[day, default: 0]
            return previousMaximum > 0 ? Double(load) / Double(previousMaximum) : 0
        }

        let prDayIndices = Set(climbs.filter { !$0.prs.isEmpty }.compactMap { climb in
            calendar.dateInterval(of: .month, for: climb.date)?.start == monthStart
                ? calendar.component(.day, from: climb.date) - 1
                : nil
        }).sorted()
        let summitDayIndices = Set(climbs.filter { $0.passedPeak != nil }.compactMap { climb in
            calendar.dateInterval(of: .month, for: climb.date)?.start == monthStart
                ? calendar.component(.day, from: climb.date) - 1
                : nil
        }).sorted()

        return SummitMonthRidge(
            monthStart: monthStart,
            dayLoads: dayLoads,
            todayIndex: isCurrentMonth ? currentDay - 1 : nil,
            prDayIndices: prDayIndices,
            summitDayIndices: summitDayIndices,
            previousMonthLoads: previousMonthLoads
        )
    }

    private static func liftPeaks(
        observationsByExercise: [UUID: [LiftObservation]],
        bestSetsByExercise: [UUID: [LiftSetObservation]],
        prSetIDs: Set<UUID>,
        now: Date,
        calendar: Calendar
    ) -> [SummitLiftPeak] {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let currentWeekStart = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? weekCalendar.startOfDay(for: now)
        let weekStarts = (0..<liftWeekCount).compactMap { offset in
            weekCalendar.date(byAdding: .weekOfYear, value: offset - liftWeekCount + 1, to: currentWeekStart)
        }
        guard let windowStart = weekStarts.first else { return [] }

        let candidates = observationsByExercise.compactMap { exerciseID, allObservations -> LiftCandidate? in
            let ordered = allObservations.sorted { $0.date < $1.date }
            let recent = ordered.filter { $0.date >= windowStart && $0.date <= now }
            guard recent.count >= minimumLiftSessions else { return nil }

            let earliestRecentValue = recent.first?.e1RM ?? 0
            var carried = ordered.last(where: { $0.date < windowStart })?.e1RM ?? earliestRecentValue
            let weeklyBest = weekStarts.map { start -> Double in
                let end = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? .distantFuture
                let value = recent
                    .filter { $0.date >= start && $0.date < end }
                    .map(\.e1RM)
                    .max()
                if let value { carried = value }
                return carried
            }
            let current = weeklyBest.last ?? earliestRecentValue
            let latestName = recent.last?.name ?? ordered.last?.name ?? "Exercise"
            let isCompound = recent.last?.isCompound ?? false
            let bestSets = (bestSetsByExercise[exerciseID] ?? [])
                .map {
                    SummitBestSet(
                        id: $0.set.id,
                        weightKg: $0.set.weightKg,
                        reps: $0.set.reps,
                        date: $0.date,
                        isPR: prSetIDs.contains($0.set.id),
                        isBodyweight: $0.set.isBodyweight
                    )
                }
            let hasRecentPR = recent.contains {
                $0.isPR && now.timeIntervalSince($0.date) >= 0 && now.timeIntervalSince($0.date) <= recentPRInterval
            }

            return LiftCandidate(
                value: SummitLiftPeak(
                    id: exerciseID,
                    name: latestName,
                    shortName: shortName(for: latestName),
                    e1RMNow: current,
                    e1RMThen: weeklyBest.first ?? earliestRecentValue,
                    weeklyBest: weeklyBest,
                    bestSets: Array(bestSets),
                    hasRecentPR: hasRecentPR
                ),
                isCompound: isCompound
            )
        }

        return candidates.sorted {
            if $0.isCompound != $1.isCompound { return $0.isCompound && !$1.isCompound }
            if $0.value.e1RMNow != $1.value.e1RMNow { return $0.value.e1RMNow > $1.value.e1RMNow }
            return $0.value.name < $1.value.name
        }.prefix(6).map(\.value)
    }

    private static func shortName(for name: String) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "overhead press": return "OHP"
        case "bench press": return "BENCH"
        case "deadlift": return "DEAD"
        case "pull-up", "chin-up": return "PULL"
        default:
            return String(name.split(whereSeparator: \.isWhitespace).first ?? "Exercise").prefix(6).uppercased()
        }
    }

    private struct LiftSetObservation {
        let set: SummitSetInput
        let e1RM: Double
        let date: Date
    }

    private struct LiftObservation {
        let date: Date
        let name: String
        let e1RM: Double
        let isCompound: Bool
        let isPR: Bool
    }

    private struct LiftCandidate {
        let value: SummitLiftPeak
        let isCompound: Bool
    }
}
