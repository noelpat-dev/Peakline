import Foundation

enum SummitProgressService {
    private static let metresPerEverest = 8_849
    private static let currentCairnWeekCount = 12
    private static let sessionsPerCairnStone = 2
    private static let weekFreshnessInterval: TimeInterval = 7 * 24 * 60 * 60

    static func metres(for sets: [SummitSetInput], bodyweightKg: Double) -> Int {
        guard bodyweightKg > 0 else { return 0 }

        let work = sets.reduce(0.0) { $0 + metreWork(for: $1, bodyweightKg: bodyweightKg) }

        return Int((work / bodyweightKg).rounded())
    }

    static func metreWork(for set: SummitSetInput, bodyweightKg: Double) -> Double {
        guard set.reps > 0 else { return 0 }
        let load = effectiveLoad(for: set, bodyweightKg: bodyweightKg)
        return load * Double(set.reps) * rangeOfMotion(for: set.pattern)
    }

    static func effectiveLoad(for set: SummitSetInput, bodyweightKg: Double) -> Double {
        let bodyweightLoad = set.isBodyweight
            ? bodyweightKg * bodyweightFactor(for: set.pattern)
            : 0
        return set.weightKg + bodyweightLoad
    }

    static func altitude(totalMetres: Int, gainedToday: Int?) -> SummitAltitude {
        let passedPeaks = SummitCatalog.peaks.filter { $0.metres <= totalMetres }
        let lapsPassed = max(0, totalMetres / metresPerEverest)
        let everest = SummitCatalog.peaks.first { $0.id == "everest" }

        var passed = passedPeaks
        if lapsPassed >= 2, let everest {
            passed.append(contentsOf: (2...lapsPassed).map { lapPeak($0, basedOn: everest) })
        }

        let nextPeak: SummitPeak?
        if let everest, totalMetres >= everest.metres {
            nextPeak = lapPeak(totalMetres / metresPerEverest + 1, basedOn: everest)
        } else {
            nextPeak = SummitCatalog.peaks.first { $0.metres > totalMetres }
        }

        return SummitAltitude(
            totalMetres: totalMetres,
            gainedToday: gainedToday,
            passed: passed,
            next: nextPeak,
            metresToNext: nextPeak.map { $0.metres - totalMetres }
        )
    }

    static func didPassPeak(before: Int, after: Int) -> SummitPeak? {
        guard after > before else { return nil }

        let cataloguePeak = SummitCatalog.peaks
            .filter { before < $0.metres && $0.metres <= after }
            .max { $0.metres < $1.metres }

        guard let everest = SummitCatalog.peaks.first(where: { $0.id == "everest" }) else {
            return cataloguePeak
        }

        let highestLapNumber = after / metresPerEverest
        guard highestLapNumber >= 2 else { return cataloguePeak }
        let lap = lapPeak(highestLapNumber, basedOn: everest)
        guard before < lap.metres else { return cataloguePeak }
        if let cataloguePeak, cataloguePeak.metres > lap.metres { return cataloguePeak }
        return lap
    }

    static func expeditionProgress(
        route: ExpeditionRoute,
        startDate: Date,
        climbedSinceStart: Int,
        recentSessionMetres: [Int]
    ) -> ExpeditionProgress {
        let cumulativeAscents = cumulativeCampAscents(for: route.camps)
        let ascent = max(0, climbedSinceStart)
        let reachedCampIDs = zip(route.camps, cumulativeAscents)
            .filter { $0.1 <= ascent }
            .map { $0.0.id }
        let nextIndex = cumulativeAscents.firstIndex { $0 > ascent }
        let nextCamp = nextIndex.map { route.camps[$0] }
        let nextAscent = nextIndex.map { cumulativeAscents[$0] }
        let routeAscent = cumulativeAscents.last ?? 0
        let currentAltitude: Int
        if let reachedIndex = cumulativeAscents.lastIndex(where: { $0 <= ascent }) {
            let metresSinceCamp = nextAscent.map { min(ascent - cumulativeAscents[reachedIndex], $0 - cumulativeAscents[reachedIndex]) } ?? 0
            currentAltitude = route.camps[reachedIndex].altitude + metresSinceCamp
        } else {
            currentAltitude = route.camps.first?.altitude ?? 0
        }
        let recent = recentSessionMetres.suffix(8)
        let estimatedSessionsLeft: Int?
        if recentSessionMetres.count >= 3 {
            let mean = Double(recent.reduce(0, +)) / Double(recent.count)
            estimatedSessionsLeft = mean > 0
                ? Int((Double(max(0, routeAscent - ascent)) / mean).rounded(.up))
                : nil
        } else {
            estimatedSessionsLeft = nil
        }

        return ExpeditionProgress(
            route: route,
            startDate: startDate,
            climbedSinceStart: ascent,
            currentAltitude: currentAltitude,
            reachedCampIDs: reachedCampIDs,
            nextCamp: nextCamp,
            metresToNextCamp: nextAscent.map { $0 - ascent },
            remainingAscent: max(0, routeAscent - ascent),
            estimatedSessionsLeft: estimatedSessionsLeft
        )
    }

    static func cairn(sessionDates: [Date], now: Date, calendar: Calendar) -> CairnState {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2

        let currentWeekStart = weekStart(containing: now, calendar: weekCalendar)
        let lastCompleteWeekStart = weekCalendar.date(
            byAdding: .weekOfYear,
            value: -1,
            to: currentWeekStart
        ) ?? currentWeekStart
        let datesByWeek = Dictionary(grouping: sessionDates.filter { $0 <= now }) {
            weekStart(containing: $0, calendar: weekCalendar)
        }
        let climbsThisWeek = datesByWeek[currentWeekStart]?.count ?? 0
        let currentWeekQualifies = climbsThisWeek >= sessionsPerCairnStone

        let recentWeekStarts = (0..<currentCairnWeekCount).compactMap { offset in
            weekCalendar.date(byAdding: .weekOfYear, value: offset - currentCairnWeekCount + 1, to: currentWeekStart)
        }
        let recentWeeks = recentWeekStarts.map { start in
            let climbs = datesByWeek[start]?.count ?? 0
            return CairnWeek(
                weekStart: start,
                climbs: climbs,
                qualified: climbs >= sessionsPerCairnStone,
                isCurrent: start == currentWeekStart
            )
        }

        let lastCompleteClimbs = datesByWeek[lastCompleteWeekStart]?.count ?? 0
        var consecutiveCompleteWeeks = 0
        var cursor = lastCompleteWeekStart
        while (datesByWeek[cursor]?.count ?? 0) >= sessionsPerCairnStone {
            consecutiveCompleteWeeks += 1
            guard let previous = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let stones = consecutiveCompleteWeeks + (currentWeekQualifies ? 1 : 0)
        let qualifyingWeekStart = currentWeekQualifies
            ? currentWeekStart
            : (lastCompleteClimbs >= sessionsPerCairnStone ? lastCompleteWeekStart : nil)
        let qualifyingDate = qualifyingWeekStart.flatMap { start in
            datesByWeek[start]?.sorted().dropFirst(sessionsPerCairnStone - 1).first
        }
        let newestIsFresh = qualifyingDate.map {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age <= weekFreshnessInterval
        } ?? false

        var pastCairns: [PastCairn] = []
        if let firstWeek = datesByWeek.keys.min(), firstWeek <= lastCompleteWeekStart {
            var week = firstWeek
            var runHeight = 0
            var runEndedWeek: Date?

            while week <= lastCompleteWeekStart {
                if (datesByWeek[week]?.count ?? 0) >= sessionsPerCairnStone {
                    runHeight += 1
                    runEndedWeek = week
                } else if runHeight > 0 {
                    if let runEndedWeek {
                        pastCairns.append(PastCairn(height: runHeight, endedWeek: runEndedWeek))
                    }
                    runHeight = 0
                    runEndedWeek = nil
                }

                guard let next = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = next
            }
        }

        return CairnState(
            stones: stones,
            newestIsFresh: newestIsFresh,
            climbsThisWeek: climbsThisWeek,
            climbsNeeded: sessionsPerCairnStone,
            recentWeeks: recentWeeks,
            pastCairns: Array(pastCairns.reversed().prefix(5))
        )
    }

    static func routePlan(
        category: ReadinessCategory,
        plannedTitle: String?,
        plannedMinutes: Int? = nil
    ) -> SummitRoutePlan {
        switch category {
        case .peak, .ready:
            return .planned
        case .cautious:
            return .steady(note: "Train as planned, skip the max attempts.")
        case .low:
            return .steady(note: "Trim volume and keep effort moderate.")
        case .recovery:
            let title = plannedTitle ?? "Planned session"
            return .lowerRoute(
                plannedTitle: title,
                alternative: SummitLowerRoute(
                    title: "Recovery climb",
                    detail: "\(title) at lower volume",
                    minutes: plannedMinutes ?? 35
                )
            )
        }
    }

    static func unlockedAppIcons(totalMetres: Int) -> [SummitAppIcon] {
        SummitAppIcon.allCases.filter { $0.unlockMetres <= totalMetres }
    }

    private static func rangeOfMotion(for pattern: MovementPattern) -> Double {
        switch pattern {
        case .squat: return 0.60
        case .hinge: return 0.50
        case .push: return 0.45
        case .pull: return 0.55
        case .carry: return 0
        case .isolation: return 0.35
        case .core: return 0.25
        case .other: return 0.35
        }
    }

    private static func bodyweightFactor(for pattern: MovementPattern) -> Double {
        switch pattern {
        case .pull: return 1.0
        case .push: return 0.65
        case .squat: return 0.8
        case .hinge: return 0.6
        case .core: return 0.3
        case .isolation: return 0.3
        case .other: return 0.6
        case .carry: return 0
        }
    }

    private static func lapPeak(_ number: Int, basedOn everest: SummitPeak) -> SummitPeak {
        SummitPeak(
            id: "everest-lap-\(number)",
            name: "Everest × \(number)",
            metres: metresPerEverest * number,
            fact: everest.fact,
            coordinates: everest.coordinates
        )
    }

    private static func cumulativeCampAscents(for camps: [ExpeditionCamp]) -> [Int] {
        guard let first = camps.first else { return [] }
        var previousAltitude = first.altitude
        var cumulativeAscent = 0

        return camps.enumerated().map { index, camp in
            guard index > 0 else { return 0 }
            cumulativeAscent += max(0, camp.altitude - previousAltitude)
            previousAltitude = camp.altitude
            return cumulativeAscent
        }
    }

    private static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
