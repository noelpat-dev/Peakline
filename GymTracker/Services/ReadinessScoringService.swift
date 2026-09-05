import Combine
import Foundation
import UIKit

enum HydrationPacingPhase: String, CaseIterable, Hashable {
    case morning
    case midday
    case afternoon
    case evening
    case dayEnd

    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case ..<10:
            self = .morning
        case 10..<13:
            self = .midday
        case 13..<17:
            self = .afternoon
        case 17..<21:
            self = .evening
        default:
            self = .dayEnd
        }
    }

    var reliability: Double {
        switch self {
        case .morning:
            return 0.25
        case .midday:
            return 0.45
        case .afternoon:
            return 0.70
        case .evening:
            return 0.90
        case .dayEnd:
            return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .morning:
            return "morning"
        case .midday:
            return "midday"
        case .afternoon:
            return "afternoon"
        case .evening:
            return "evening"
        case .dayEnd:
            return "day-end"
        }
    }
}

struct ReadinessRefreshToken: Hashable {
    let dayStart: Date
    let hydrationPhase: HydrationPacingPhase
    let generation: Int

    init(date: Date, calendar: Calendar = .current, generation: Int) {
        dayStart = calendar.startOfDay(for: date)
        hydrationPhase = HydrationPacingPhase(date: date, calendar: calendar)
        self.generation = generation
    }

    var signature: String {
        "\(dayStart.timeIntervalSinceReferenceDate):\(hydrationPhase.rawValue):\(generation)"
    }
}

/// App-wide readiness clock. It schedules only the next calendar or hydration boundary,
/// replacing the task whenever activation or a significant time change occurs.
@MainActor
final class ReadinessRefreshClock: ObservableObject {
    static let shared = ReadinessRefreshClock()

    @Published private(set) var token: ReadinessRefreshToken

    private let calendar: Calendar
    private var generation = 0
    private var boundaryTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false

    private init(calendar: Calendar = .current) {
        self.calendar = calendar
        token = ReadinessRefreshToken(date: .now, calendar: calendar, generation: 0)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        installObservers()
        refresh()
    }

    func refresh(now: Date = .now) {
        generation += 1
        token = ReadinessRefreshToken(date: now, calendar: calendar, generation: generation)
        scheduleNextBoundary(after: now)
    }

    private func resume(now: Date = .now) {
        let current = ReadinessRefreshToken(date: now, calendar: calendar, generation: generation)
        if current != token {
            refresh(now: now)
        } else {
            // Activation alone does not change readiness inputs. Keep cached
            // dashboards valid, but restart the timer cancelled on resigning.
            scheduleNextBoundary(after: now)
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancelBoundaryTask() }
        })
        observers.append(center.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    private func scheduleNextBoundary(after date: Date) {
        cancelBoundaryTask()
        guard let boundary = nextBoundary(after: date) else { return }
        let delay = max(0.1, boundary.timeIntervalSince(date))
        boundaryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func cancelBoundaryTask() {
        boundaryTask?.cancel()
        boundaryTask = nil
    }

    private func nextBoundary(after date: Date) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        for hour in [10, 13, 17, 21] {
            guard let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) else {
                continue
            }
            if boundary > date {
                return boundary
            }
        }
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
    }
}

struct ReadinessSignalEvidence: Hashable {
    let kind: ReadinessFactorKind
    let title: String
    let detail: String
    let rawScore: Int?
    let reliability: Double
    let historicalScores: [Int]

    init(
        kind: ReadinessFactorKind,
        title: String? = nil,
        detail: String,
        rawScore: Int?,
        reliability: Double = 1,
        historicalScores: [Int] = []
    ) {
        self.kind = kind
        self.title = title ?? kind.displayName
        self.detail = detail
        self.rawScore = rawScore
        self.reliability = reliability
        self.historicalScores = historicalScores
    }
}

struct ReadinessScoringResult: Hashable {
    let value: Int
    let confidence: ReadinessConfidence
    let factors: [ReadinessFactor]
    let effectiveEvidenceWeight: Double
    let availableSignalCount: Int
    let diagnosticSummary: String

    var isProvisional: Bool {
        confidence == .low
    }
}

/// Pure, deterministic readiness aggregation. Domain services are responsible for deciding
/// whether a signal is eligible; this scorer never invents a value for missing evidence.
struct ReadinessScoringService {
    static let version = "readiness-v2"
    static let neutralPrior = 70

    private static let baseWeights: [ReadinessFactorKind: Double] = [
        .training: 0.30,
        .checkIn: 0.25,
        .sleep: 0.25,
        .hydration: 0.10,
        .nutrition: 0.10
    ]

    func score(_ evidence: [ReadinessSignalEvidence]) -> ReadinessScoringResult {
        let evidenceByKind = evidence.reduce(into: [ReadinessFactorKind: ReadinessSignalEvidence]()) {
            $0[$1.kind] = $1
        }
        let orderedEvidence = ReadinessFactorKind.allCases.map { kind in
            evidenceByKind[kind] ?? ReadinessSignalEvidence(
                kind: kind,
                detail: "No eligible data for this day.",
                rawScore: nil,
                reliability: 0
            )
        }
        let available = orderedEvidence.filter {
            $0.rawScore != nil && clampedReliability($0.reliability) > 0
        }
        let availableCount = available.count
        let evidenceCeiling: Double
        switch availableCount {
        case 0:
            evidenceCeiling = 0
        case 1:
            evidenceCeiling = 0.40
        case 2:
            evidenceCeiling = 0.80
        default:
            evidenceCeiling = 1.0
        }

        let availableBaseWeight = available.reduce(0.0) {
            $0 + Self.baseWeight(for: $1.kind)
        }
        var factors: [ReadinessFactor] = []
        var weightedDelta = 0.0
        var effectiveEvidenceWeight = 0.0

        for item in orderedEvidence {
            guard let rawScore = item.rawScore,
                  clampedReliability(item.reliability) > 0,
                  availableBaseWeight > 0 else {
                factors.append(ReadinessFactor(
                    kind: item.kind,
                    title: item.title,
                    detail: item.detail,
                    impact: .neutral,
                    contribution: 0,
                    score: nil,
                    isDataAvailable: false,
                    rawScore: nil,
                    reliability: 0,
                    effectiveWeight: 0,
                    calibrationAdjustment: 0
                ))
                continue
            }

            let boundedRawScore = min(100, max(0, rawScore))
            let adjustment = personalAdjustment(
                for: item.kind,
                rawScore: boundedRawScore,
                historicalScores: item.historicalScores
            )
            let calibratedScore = min(100, max(0, boundedRawScore + adjustment))
            let reliability = clampedReliability(item.reliability)
            let assignedWeight = evidenceCeiling
                * Self.baseWeight(for: item.kind)
                / availableBaseWeight
            let effectiveWeight = min(
                assignedWeight,
                Self.maximumAggregateWeight(for: item.kind)
            ) * reliability
            let contribution = Double(calibratedScore - Self.neutralPrior) * effectiveWeight

            factors.append(ReadinessFactor(
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                impact: impact(for: calibratedScore),
                contribution: contribution,
                score: calibratedScore,
                isDataAvailable: true,
                rawScore: boundedRawScore,
                reliability: reliability,
                effectiveWeight: effectiveWeight,
                calibrationAdjustment: adjustment
            ))
            effectiveEvidenceWeight += effectiveWeight
            weightedDelta += contribution
        }

        let value = min(100, max(0, Int((Double(Self.neutralPrior) + weightedDelta).rounded())))
        let confidence = confidence(
            factors: factors,
            effectiveEvidenceWeight: effectiveEvidenceWeight
        )
        let weights = factors
            .filter(\.isDataAvailable)
            .map { "\($0.kind.rawValue)=\(Self.percent($0.effectiveWeight))" }
            .joined(separator: ",")
        let adjustments = factors
            .filter { $0.calibrationAdjustment != 0 }
            .map { "\($0.kind.rawValue)=\($0.calibrationAdjustment > 0 ? "+" : "")\($0.calibrationAdjustment)" }
            .joined(separator: ",")
        let diagnosticSummary = "\(Self.version) coverage=\(availableCount)/\(ReadinessFactorKind.allCases.count) evidence=\(Self.percent(effectiveEvidenceWeight)) weights=[\(weights)] calibration=[\(adjustments)]"

        return ReadinessScoringResult(
            value: value,
            confidence: confidence,
            factors: factors,
            effectiveEvidenceWeight: effectiveEvidenceWeight,
            availableSignalCount: availableCount,
            diagnosticSummary: diagnosticSummary
        )
    }

    private func personalAdjustment(
        for kind: ReadinessFactorKind,
        rawScore: Int,
        historicalScores: [Int]
    ) -> Int {
        guard kind == .sleep || kind == .training || kind == .checkIn,
              historicalScores.count >= 5 else {
            return 0
        }

        let median = Self.median(historicalScores.map { min(100, max(0, $0)) })
        let adjustment = Int(((Double(rawScore) - median) * 0.35).rounded())
        return min(8, max(-8, adjustment))
    }

    private func confidence(
        factors: [ReadinessFactor],
        effectiveEvidenceWeight: Double
    ) -> ReadinessConfidence {
        let available = factors.filter(\.isDataAvailable)
        let adequateCount = available.filter { $0.reliability >= 0.50 }.count

        guard available.count >= 2,
              adequateCount >= 2,
              effectiveEvidenceWeight >= 0.60 else {
            return .low
        }

        let kinds = Set(available.map(\.kind))
        let hasCoreSignals = kinds.isSuperset(of: [.sleep, .training, .checkIn])
        let hasQualifiedModifier = kinds.contains(.hydration) || kinds.contains(.nutrition)
        if hasCoreSignals, hasQualifiedModifier, effectiveEvidenceWeight >= 0.90 {
            return .high
        }

        return .medium
    }

    private func impact(for calibratedScore: Int) -> ReadinessImpact {
        switch calibratedScore {
        case 76...:
            return .positive
        case ...64:
            return .negative
        default:
            return .neutral
        }
    }

    private func clampedReliability(_ reliability: Double) -> Double {
        min(1, max(0, reliability))
    }

    private static func baseWeight(for kind: ReadinessFactorKind) -> Double {
        baseWeights[kind, default: 0]
    }

    private static func maximumAggregateWeight(for kind: ReadinessFactorKind) -> Double {
        kind == .nutrition ? 0.10 : 1.0
    }

    private static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return Double(sorted[midpoint])
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
