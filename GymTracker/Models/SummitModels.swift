import Foundation

// MARK: - Summit catalogue

struct SummitPeak: Hashable, Identifiable {
    let id: String
    let name: String
    let metres: Int
    let fact: String
    let coordinates: String
}

struct ExpeditionCamp: Hashable, Identifiable {
    let id: String
    let name: String
    let altitude: Int
}

struct ExpeditionRoute: Hashable, Identifiable {
    let id: String
    let name: String
    let mountain: String
    let camps: [ExpeditionCamp] // walking order; the last camp is the summit
}

enum SummitAppIcon: String, CaseIterable, Hashable {
    case topo, night, alpenglow, everest

    var alternateIconName: String? {
        switch self {
        case .topo: nil
        case .night: "AppIconNight"
        case .alpenglow: "AppIconAlpenglow"
        case .everest: "AppIconEverest"
        }
    }

    var unlockMetres: Int {
        switch self {
        case .topo: 0
        case .night: 1_345
        case .alpenglow: 4_808
        case .everest: 8_849
        }
    }
}

enum SummitCatalog {
    static let peaks: [SummitPeak] = [
        SummitPeak(id: "snowdon", name: "Snowdon", metres: 1_085, fact: "The highest point in Wales.", coordinates: "53.07° N · 4.08° W"),
        SummitPeak(id: "ben-nevis", name: "Ben Nevis", metres: 1_345, fact: "The highest point in the UK.", coordinates: "56.80° N · 5.00° W"),
        SummitPeak(id: "fuji", name: "Mount Fuji", metres: 3_776, fact: "Japan’s highest peak.", coordinates: "35.36° N · 138.73° E"),
        SummitPeak(id: "matterhorn", name: "Matterhorn", metres: 4_478, fact: "The most famous face in the Alps.", coordinates: "45.98° N · 7.66° E"),
        SummitPeak(id: "mont-blanc", name: "Mont Blanc", metres: 4_808, fact: "The highest point in the Alps.", coordinates: "45.83° N · 6.86° E"),
        SummitPeak(id: "kilimanjaro", name: "Kilimanjaro", metres: 5_895, fact: "The roof of Africa.", coordinates: "3.07° S · 37.35° E"),
        SummitPeak(id: "denali", name: "Denali", metres: 6_190, fact: "North America’s highest peak.", coordinates: "63.07° N · 151.01° W"),
        SummitPeak(id: "aconcagua", name: "Aconcagua", metres: 6_961, fact: "The highest point outside Asia.", coordinates: "32.65° S · 70.01° W"),
        SummitPeak(id: "everest", name: "Everest", metres: 8_849, fact: "The top of the world.", coordinates: "27.99° N · 86.93° E")
    ]

    static let machame = ExpeditionRoute(
        id: "kilimanjaro-machame", name: "Machame Route", mountain: "Kilimanjaro",
        camps: [
            ExpeditionCamp(id: "machame-gate", name: "Machame Gate", altitude: 1_800),
            ExpeditionCamp(id: "machame-camp", name: "Machame Camp", altitude: 3_010),
            ExpeditionCamp(id: "shira-camp", name: "Shira Camp", altitude: 3_845),
            ExpeditionCamp(id: "lava-tower", name: "Lava Tower", altitude: 4_630),
            ExpeditionCamp(id: "barranco-camp", name: "Barranco Camp", altitude: 3_960),
            ExpeditionCamp(id: "karanga-camp", name: "Karanga Camp", altitude: 3_995),
            ExpeditionCamp(id: "barafu-camp", name: "Barafu Camp", altitude: 4_673),
            ExpeditionCamp(id: "uhuru-peak", name: "Uhuru Peak", altitude: 5_895)
        ]
    )
}

// MARK: - Engine inputs

struct SummitSetInput: Hashable {
    var exerciseID: UUID
    var exerciseName: String
    var pattern: MovementPattern
    var isBodyweight: Bool
    var isCompound: Bool
    var weightKg: Double // added load for bodyweight exercises
    var reps: Int
}

struct SummitSessionInput: Hashable, Identifiable {
    var id: UUID
    var date: Date
    var title: String
    var durationMinutes: Int?
    var sets: [SummitSetInput] // completed, non-warm-up sets only
}

// MARK: - Engine outputs

struct SummitPR: Hashable {
    var exerciseName: String
    var weightKg: Double
    var reps: Int
}

struct SummitAltitude: Hashable {
    var totalMetres: Int
    var gainedToday: Int?
    var passed: [SummitPeak]
    var next: SummitPeak?
    var metresToNext: Int?
}

struct SummitSessionClimb: Hashable, Identifiable {
    var id: UUID
    var date: Date
    var title: String
    var metres: Int
    var durationMinutes: Int?
    var setCount: Int
    var volumeKg: Double
    var setProfile: [Double] // one value per set, 0...1 relative to the session's largest set volume
    var prs: [SummitPR]
    var passedPeak: SummitPeak?
    var isLowerRoute: Bool
}

struct SummitMonthRidge: Hashable {
    var monthStart: Date
    var dayLoads: [Double?] // one per day of the month, 0...1; nil = a future day
    var todayIndex: Int?
    var prDayIndices: [Int]
    var summitDayIndices: [Int]
    var previousMonthLoads: [Double]
}

struct SummitBestSet: Hashable, Identifiable {
    var id: UUID
    var weightKg: Double
    var reps: Int
    var date: Date
    var isPR: Bool
}

struct SummitLiftPeak: Hashable, Identifiable {
    var id: UUID // exercise id
    var name: String
    var shortName: String
    var e1RMNow: Double
    var e1RMThen: Double // 12 weeks ago, or the earliest value inside the window
    var weeklyBest: [Double] // 12 values, oldest first, gaps carried forward
    var bestSets: [SummitBestSet] // top 3
    var hasRecentPR: Bool // a PR within the last 7 days
}

struct CairnWeek: Hashable, Identifiable {
    var weekStart: Date
    var climbs: Int
    var qualified: Bool
    var isCurrent: Bool
    var id: Date { weekStart }
}

struct PastCairn: Hashable, Identifiable {
    var height: Int
    var endedWeek: Date
    var id: Date { endedWeek }
}

struct CairnState: Hashable {
    var stones: Int
    var newestIsFresh: Bool
    var climbsThisWeek: Int
    var climbsNeeded: Int
    var recentWeeks: [CairnWeek] // 12, oldest first; the last is the current week
    var pastCairns: [PastCairn] // newest first, at most 5
}

struct ExpeditionProgress: Hashable {
    var route: ExpeditionRoute
    var startDate: Date
    var climbedSinceStart: Int
    var currentAltitude: Int
    var reachedCampIDs: [String]
    var nextCamp: ExpeditionCamp?
    var metresToNextCamp: Int?
    var remainingAscent: Int
    var estimatedSessionsLeft: Int?
}

struct SummitLowerRoute: Hashable {
    var title: String
    var detail: String
    var minutes: Int
}

enum SummitRoutePlan: Hashable {
    case planned
    case steady(note: String)
    case lowerRoute(plannedTitle: String, alternative: SummitLowerRoute)
}

struct SummitMoment: Hashable {
    var peak: SummitPeak
    var previousPeakMetres: Int
    var totalMetres: Int
    var gainedMetres: Int
    var durationMinutes: Int?
    var setCount: Int
    var prs: [SummitPR]
    var next: SummitPeak?
    var metresToNext: Int?
    var firstSessionDate: Date
    var sessionCount: Int
    var date: Date
}

struct SummitSnapshot: Hashable {
    var altitude: SummitAltitude
    var month: SummitMonthRidge
    var log: [SummitSessionClimb] // newest first
    var lifts: [SummitLiftPeak]
    var cairn: CairnState
    var expedition: ExpeditionProgress?
}

#if DEBUG
// MARK: - Fixed Summit gallery fixtures

private enum SummitFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(_ day: Int, _ month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
    }

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
    }

    static func profile(_ values: [Double]) -> [Double] {
        let largest = values.max() ?? 1
        return values.map { $0 / largest }
    }

    static func bestSets(_ values: [(Double, Int, Int, Int, Bool)], offset: Int) -> [SummitBestSet] {
        values.enumerated().map { index, value in
            SummitBestSet(
                id: id(offset + index), weightKg: value.0, reps: value.1,
                date: date(value.2, value.3), isPR: value.4
            )
        }
    }

    static let recentWeeks: [CairnWeek] = (0..<12).map { index in
        let weekStart = calendar.date(byAdding: .weekOfYear, value: index - 11, to: date(21))!
        return CairnWeek(weekStart: weekStart, climbs: index == 11 ? 1 : 2,
                         qualified: index < 11, isCurrent: index == 11)
    }

    static let zeroWeeks: [CairnWeek] = recentWeeks.map {
        CairnWeek(weekStart: $0.weekStart, climbs: 0, qualified: false, isCurrent: $0.isCurrent)
    }
}

extension SummitSnapshot {
    static let preview: SummitSnapshot = {
        let peaks = SummitCatalog.peaks
        let currentLoads: [Int: Double] = [
            1: 0.5, 2: 0.66, 4: 0.92, 6: 0.48, 8: 0.58, 9: 0.7,
            11: 0.96, 13: 0.44, 15: 0.6, 16: 0.74, 18: 0.14,
            20: 1, 22: 0.68, 23: 0.6
        ]
        let previousLoads: [Int: Double] = [
            1: 0.4, 3: 0.6, 5: 0.8, 7: 0.45, 10: 0.62, 12: 0.9,
            14: 0.5, 17: 0.66, 19: 0.7, 21: 0.85, 24: 0.55,
            26: 0.62, 28: 0.8, 30: 0.5
        ]
        let month = SummitMonthRidge(
            monthStart: SummitFixture.date(1),
            dayLoads: (1...30).map { $0 <= 23 ? currentLoads[$0] ?? 0 : nil },
            todayIndex: 22, prDayIndices: [22], summitDayIndices: [19],
            previousMonthLoads: (1...31).map { previousLoads[$0] ?? 0 }
        )
        let log: [SummitSessionClimb] = [
            SummitSessionClimb(
                id: SummitFixture.id(1), date: SummitFixture.date(23), title: "Push · Upper",
                metres: 46, durationMinutes: 52, setCount: 18, volumeKg: 7_420,
                setProfile: SummitFixture.profile([4,5,6,6,7,7,6,5,5,6,5,4,4,4,3,3,3,2]),
                prs: [SummitPR(exerciseName: "Bench press", weightKg: 102.5, reps: 3)],
                passedPeak: nil, isLowerRoute: false
            ),
            SummitSessionClimb(
                id: SummitFixture.id(2), date: SummitFixture.date(22), title: "Pull · Back & biceps",
                metres: 52, durationMinutes: 48, setCount: 16, volumeKg: 8_310,
                setProfile: SummitFixture.profile([5,6,6,7,7,6,6,5,5,5,4,4,4,3,3,2]),
                prs: [], passedPeak: nil, isLowerRoute: false
            ),
            SummitSessionClimb(
                id: SummitFixture.id(3), date: SummitFixture.date(20), title: "Legs · Heavy",
                metres: 118, durationMinutes: 61, setCount: 20, volumeKg: 15_760,
                setProfile: SummitFixture.profile([6,8,9,10,10,11,10,9,8,8,7,7,6,6,5,5,4,4,3,3]),
                prs: [SummitPR(exerciseName: "Squat", weightKg: 150, reps: 5)],
                passedPeak: peaks[4], isLowerRoute: false
            ),
            SummitSessionClimb(
                id: SummitFixture.id(4), date: SummitFixture.date(18), title: "Mobility",
                metres: 4, durationMinutes: 25, setCount: 10, volumeKg: 0,
                setProfile: SummitFixture.profile(Array(repeating: 1, count: 10)),
                prs: [], passedPeak: nil, isLowerRoute: true
            )
        ]
        let lifts: [SummitLiftPeak] = [
            SummitLiftPeak(id: SummitFixture.id(101), name: "Overhead press", shortName: "OHP",
                e1RMNow: 72, e1RMThen: 69,
                weeklyBest: [66,66,67,68,68,69,69,70,70,71,71,72],
                bestSets: SummitFixture.bestSets([(50,6,18,9,false),(50,5,4,9,false),(47.5,6,18,8,false)], offset: 201),
                hasRecentPR: false),
            SummitLiftPeak(id: SummitFixture.id(102), name: "Bench press", shortName: "BENCH",
                e1RMNow: 115, e1RMThen: 106,
                weeklyBest: [104,105,106,106,108,109,110,110,111,113,113,115],
                bestSets: SummitFixture.bestSets([(102.5,3,23,9,true),(100,4,9,9,false),(97.5,5,26,8,false)], offset: 204),
                hasRecentPR: true),
            SummitLiftPeak(id: SummitFixture.id(103), name: "Deadlift", shortName: "DEAD",
                e1RMNow: 205, e1RMThen: 196,
                weeklyBest: [194,195,196,196,198,199,200,200,201,203,204,205],
                bestSets: SummitFixture.bestSets([(180,3,19,9,false),(175,4,5,9,false),(170,5,22,8,false)], offset: 207),
                hasRecentPR: false),
            SummitLiftPeak(id: SummitFixture.id(104), name: "Squat", shortName: "SQUAT",
                e1RMNow: 169, e1RMThen: 156,
                weeklyBest: [154,155,156,157,158,160,161,162,164,165,167,169],
                bestSets: SummitFixture.bestSets([(150,5,20,9,true),(145,5,6,9,false),(140,6,23,8,false)], offset: 210),
                hasRecentPR: true),
            SummitLiftPeak(id: SummitFixture.id(105), name: "Barbell row", shortName: "ROW",
                e1RMNow: 100, e1RMThen: 96,
                weeklyBest: [94,94,95,96,96,97,97,98,98,99,99,100],
                bestSets: SummitFixture.bestSets([(85,6,22,9,false),(82.5,6,8,9,false),(80,8,25,8,false)], offset: 213),
                hasRecentPR: false),
            SummitLiftPeak(id: SummitFixture.id(106), name: "Weighted pull-up", shortName: "PULL",
                e1RMNow: 112, e1RMThen: 105,
                weeklyBest: [103,104,105,105,106,107,108,108,109,110,111,112],
                bestSets: SummitFixture.bestSets([(25,5,22,9,false),(22.5,5,8,9,false),(20,6,25,8,false)], offset: 216),
                hasRecentPR: false)
        ]
        return SummitSnapshot(
            altitude: SummitAltitude(totalMetres: 4_851, gainedToday: 46,
                passed: Array(peaks.prefix(5)), next: peaks[5], metresToNext: 1_044),
            month: month, log: log, lifts: lifts,
            cairn: CairnState(stones: 11, newestIsFresh: true, climbsThisWeek: 1,
                climbsNeeded: 2, recentWeeks: SummitFixture.recentWeeks,
                pastCairns: [PastCairn(height: 7, endedWeek: SummitFixture.date(25, 5)),
                             PastCairn(height: 4, endedWeek: SummitFixture.date(16, 3))]),
            expedition: ExpeditionProgress(
                route: SummitCatalog.machame, startDate: SummitFixture.date(1, 8),
                climbedSinceStart: 2_212, currentAltitude: 4_012,
                reachedCampIDs: ["machame-gate", "machame-camp", "shira-camp"],
                nextCamp: SummitCatalog.machame.camps[3], metresToNextCamp: 618,
                remainingAscent: 2_553, estimatedSessionsLeft: 35)
        )
    }()

    static let empty = SummitSnapshot(
        altitude: SummitAltitude(totalMetres: 0, gainedToday: nil, passed: [],
            next: SummitCatalog.peaks[0], metresToNext: 1_085),
        month: SummitMonthRidge(monthStart: SummitFixture.date(1),
            dayLoads: Array(repeating: 0, count: 30), todayIndex: 22,
            prDayIndices: [], summitDayIndices: [],
            previousMonthLoads: Array(repeating: 0, count: 31)),
        log: [], lifts: [],
        cairn: CairnState(stones: 0, newestIsFresh: false, climbsThisWeek: 0,
            climbsNeeded: 2, recentWeeks: SummitFixture.zeroWeeks, pastCairns: []),
        expedition: nil
    )
}

extension SummitMoment {
    static let preview = SummitMoment(
        peak: SummitCatalog.peaks[4], previousPeakMetres: 4_478,
        totalMetres: 4_851, gainedMetres: 118, durationMinutes: 61, setCount: 20,
        prs: [SummitPR(exerciseName: "Squat", weightKg: 150, reps: 5)],
        next: SummitCatalog.peaks[5], metresToNext: 1_044,
        firstSessionDate: SummitFixture.date(2, 6), sessionCount: 63,
        date: SummitFixture.date(20)
    )
}
#endif
