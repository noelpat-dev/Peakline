import Foundation
import SwiftData

struct HydrationSettingsStore {
    private let targetKey = "hydration.dailyTargetML.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func dailyTargetML() -> Int {
        let stored = defaults.integer(forKey: targetKey)
        return stored > 0 ? stored : 2_500
    }

    func saveDailyTargetML(_ target: Int) {
        defaults.set(max(500, min(target, 6_000)), forKey: targetKey)
    }
}

struct HydrationService {
    func entries(for date: Date, entries: [HydrationEntry], calendar: Calendar = .current) -> [HydrationEntry] {
        entries
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    func summary(for date: Date = .now, entries: [HydrationEntry], targetML: Int, calendar: Calendar = .current) -> DailyHydrationSummary {
        let todayEntries = self.entries(for: date, entries: entries, calendar: calendar)
        let total = todayEntries.reduce(0) { $0 + $1.amountML }
        let safeTarget = max(1, targetML)
        let progress = Double(total) / Double(safeTarget)
        let status: HydrationStatus

        switch progress {
        case 0..<0.4:
            status = .low
        case 0.4..<0.7:
            status = .behind
        case 0.7..<0.9:
            status = .onTrack
        case 0.9...1.1:
            status = .complete
        default:
            status = .aboveTarget
        }

        return DailyHydrationSummary(
            date: calendar.startOfDay(for: date),
            totalML: total,
            targetML: safeTarget,
            progress: progress,
            remainingML: max(0, safeTarget - total),
            status: status,
            lastLoggedAt: todayEntries.map { $0.loggedAt }.max()
        )
    }

    func recoverySignal(from summary: DailyHydrationSummary) -> HydrationRecoverySignal {
        HydrationRecoverySignal(
            status: summary.status,
            completionRatio: summary.progress,
            totalML: summary.totalML,
            targetML: summary.targetML,
            lastLoggedAt: summary.lastLoggedAt,
            confidence: summary.totalML == 0 ? .low : summary.progress >= 0.7 ? .high : .medium
        )
    }

    static func formatAmount(_ amountML: Int) -> String {
        if amountML < 1_000 {
            return "\(amountML) mL"
        }

        let litres = Double(amountML) / 1_000
        if amountML % 1_000 == 0 {
            return "\(Int(litres)) L"
        }
        return "\(litres.formatted(.number.precision(.fractionLength(1)))) L"
    }
}
