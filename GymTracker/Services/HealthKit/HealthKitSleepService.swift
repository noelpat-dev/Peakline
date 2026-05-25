import Foundation
import SwiftData

#if canImport(HealthKit)
import HealthKit
#endif

struct HealthKitSleepService {
    var isAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    func requestReadAuthorization() async throws {
        try await requestAuthorization(read: true, write: false)
    }

    func requestWriteAuthorization() async throws {
        try await requestAuthorization(read: false, write: true)
    }

    func requestAuthorization(read: Bool, write: Bool) async throws {
        guard isAvailable else { throw HealthKitSyncError.unavailable }

        #if canImport(HealthKit)
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitSyncError.missingQuantityType("Sleep Analysis")
        }

        let readTypes: Set<HKObjectType> = read ? [sleepType] : []
        let writeTypes: Set<HKSampleType> = write ? [sleepType] : []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.unknown(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitSyncError.authorizationDenied)
                }
            }
        }
        #else
        throw HealthKitSyncError.unavailable
        #endif
    }

    func importRecentSleepCandidates(days: Int, existing: HealthKitSleepImportExistingSnapshot) async -> [HealthKitSleepImportCandidate] {
        PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates begin days=\(days)")
        guard isAvailable else { return [] }

        #if canImport(HealthKit)
        do {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now.addingTimeInterval(-Double(days) * 86_400)
            let samples = try await rawSleepSamples(from: start, to: .now)
            PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates samples=\(samples.count)")
            let grouped = groupedAsleepSamples(samples)
            var candidates: [HealthKitSleepImportCandidate] = []

            for group in grouped {
                let identifiers = group.samples.map { $0.uuid.uuidString }
                if identifiers.contains(where: { existing.healthSampleIds.contains($0) }) {
                    continue
                }

                if isLikelyNap(start: group.start, end: group.end, calendar: .current) {
                    if existing.hasOverlappingAppleHealthNap(start: group.start, end: group.end) {
                        continue
                    }

                    candidates.append(.nap(
                        startDate: group.start,
                        endDate: group.end,
                        healthKitSampleIds: identifiers
                    ))
                    continue
                }

                guard group.end.timeIntervalSince(group.start) >= 60 * 60 else {
                    continue
                }

                if existing.hasOverlappingAppleHealthSession(start: group.start, end: group.end) {
                    continue
                }

                candidates.append(.session(
                    startDate: group.start,
                    endDate: group.end,
                    confidence: group.hasStages ? .high : .medium,
                    healthKitSampleIds: identifiers
                ))
            }

            PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates end candidates=\(candidates.count)")
            return candidates
        } catch {
            PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates error=\(error.localizedDescription)")
            return []
        }
        #else
        return []
        #endif
    }

    func writeConfirmedSession(_ session: HealthKitSleepWriteSnapshot) async throws -> [String] {
        PerformanceTracer.mark(.healthKitSleepBridge, "writeConfirmedSession begin session=\(session.id.uuidString)")
        guard isAvailable else { throw HealthKitSyncError.unavailable }
        guard session.status == .completed else { throw HealthKitSyncError.noSupportedValues }
        guard session.source == .inAppTimer || session.source == .manual else { throw HealthKitSyncError.noSupportedValues }
        guard session.healthKitSampleIds.isEmpty else { return session.healthKitSampleIds }

        #if canImport(HealthKit)
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitSyncError.missingQuantityType("Sleep Analysis")
        }

        var samples: [HKCategorySample] = []
        let metadata: [String: Any] = [
            "GymTrackerSleepSessionID": session.id.uuidString,
            "GymTrackerSource": "Sleep Mode estimate",
            "GymTrackerSyncVersion": 1
        ]

        if let started = session.sleepModeStartedAt, started < session.wakeAt {
            samples.append(
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                    start: started,
                    end: session.wakeAt,
                    metadata: metadata
                )
            )
        }

        samples.append(
            HKCategorySample(
                type: sleepType,
                value: asleepWriteValue,
                start: session.confirmedSleepStartAt,
                end: session.wakeAt,
                metadata: metadata
            )
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PerformanceTracer.mark(.healthKitSleepBridge, "writeConfirmedSession before_save samples=\(samples.count)")
            healthStore.save(samples) { success, error in
                PerformanceTracer.mark(.healthKitSleepBridge, "writeConfirmedSession save_callback success=\(success)")
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed("Apple Health did not accept the sleep samples."))
                }
            }
        }

        let identifiers = samples.map { $0.uuid.uuidString }
        PerformanceTracer.mark(.healthKitSleepBridge, "writeConfirmedSession end samples=\(identifiers.count)")
        return identifiers
        #else
        throw HealthKitSyncError.unavailable
        #endif
    }

    func fetchSleepSamples(from startDate: Date, to endDate: Date) async throws -> [HealthSleepSample] {
        guard isAvailable else { throw HealthKitSyncError.unavailable }

        #if canImport(HealthKit)
        let samples = try await rawSleepSamples(from: startDate, to: endDate)
        return samples.map { sample in
            HealthSleepSample(
                id: sample.uuid,
                startDate: sample.startDate,
                endDate: sample.endDate,
                value: Self.healthSleepStage(for: sample.value),
                sourceName: sample.sourceRevision.source.name,
                sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier
            )
        }
        #else
        throw HealthKitSyncError.unavailable
        #endif
    }

    func fetchSleepSummary(for sleepDate: Date) async throws -> HealthSleepSummary? {
        let window = SleepCalendar.queryWindow(for: sleepDate)
        let samples = try await fetchSleepSamples(from: window.start, to: window.end)
        return Self.summary(for: sleepDate, samples: samples, intervalStart: window.start, intervalEnd: window.end)
    }

    static func summary(for sleepDate: Date, samples: [HealthSleepSample], intervalStart: Date, intervalEnd: Date) -> HealthSleepSummary? {
        let relevant = samples.filter { sample in
            sample.endDate > intervalStart && sample.startDate < intervalEnd
        }
        guard !relevant.isEmpty else { return nil }

        let inBed = relevant
            .filter { $0.value == .inBed }
            .reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let asleep = relevant
            .filter { $0.value.countsAsAsleep }
            .reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let awakeSamples = relevant.filter { $0.value == .awake }
        let awake = awakeSamples.isEmpty ? nil : awakeSamples.reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let coreSamples = relevant.filter { $0.value == .asleepCore }
        let deepSamples = relevant.filter { $0.value == .asleepDeep }
        let remSamples = relevant.filter { $0.value == .asleepREM }
        let core = coreSamples.isEmpty ? nil : coreSamples.reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let deep = deepSamples.isEmpty ? nil : deepSamples.reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let rem = remSamples.isEmpty ? nil : remSamples.reduce(0) { $0 + clippedDuration($1, intervalStart: intervalStart, intervalEnd: intervalEnd) }
        let sourceNames = Array(Set(relevant.compactMap(\.sourceName))).sorted()

        guard asleep > 0 || inBed > 0 else { return nil }

        return HealthSleepSummary(
            sleepDate: SleepCalendar.nightDate(for: sleepDate),
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            totalInBedDuration: inBed,
            totalAsleepDuration: asleep,
            totalAwakeDuration: awake,
            coreDuration: core,
            deepDuration: deep,
            remDuration: rem,
            sampleCount: relevant.count,
            sourceNames: sourceNames,
            confidence: confidence(asleepDuration: asleep, inBedDuration: inBed, samples: relevant)
        )
    }

    #if canImport(HealthKit)
    private var asleepWriteValue: Int {
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
    }

    private func rawSleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitSyncError.missingQuantityType("Sleep Analysis")
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.readFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }

            healthStore.execute(query)
        }
    }

    private struct SleepSampleGroup {
        var start: Date
        var end: Date
        var samples: [HKCategorySample]
        var hasStages: Bool
    }

    private func groupedAsleepSamples(_ samples: [HKCategorySample]) -> [SleepSampleGroup] {
        let asleep = samples
            .filter { isAsleepValue($0.value) }
            .sorted { $0.startDate < $1.startDate }

        var groups: [SleepSampleGroup] = []

        for sample in asleep {
            if var last = groups.popLast(), sample.startDate.timeIntervalSince(last.end) <= 3 * 60 * 60 {
                last.end = max(last.end, sample.endDate)
                last.samples.append(sample)
                last.hasStages = last.hasStages || isStagedValue(sample.value)
                groups.append(last)
            } else {
                groups.append(SleepSampleGroup(start: sample.startDate, end: sample.endDate, samples: [sample], hasStages: isStagedValue(sample.value)))
            }
        }

        return groups.filter { $0.end.timeIntervalSince($0.start) >= 10 * 60 }
    }

    private func isAsleepValue(_ value: Int) -> Bool {
        if value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
            return true
        }

        if #available(iOS 16.0, *) {
            return value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }

        return false
    }

    private func isStagedValue(_ value: Int) -> Bool {
        if #available(iOS 16.0, *) {
            return value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }

        return false
    }

    static func healthSleepStage(for value: Int) -> HealthSleepStage {
        if value == HKCategoryValueSleepAnalysis.inBed.rawValue {
            return .inBed
        }
        if value == HKCategoryValueSleepAnalysis.awake.rawValue {
            return .awake
        }
        if value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
            return .asleepUnspecified
        }

        if #available(iOS 16.0, *) {
            if value == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                return .asleepCore
            }
            if value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                return .asleepDeep
            }
            if value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                return .asleepREM
            }
        }

        return .unknown
    }
    #endif

    private static func clippedDuration(_ sample: HealthSleepSample, intervalStart: Date, intervalEnd: Date) -> TimeInterval {
        max(0, min(sample.endDate, intervalEnd).timeIntervalSince(max(sample.startDate, intervalStart)))
    }

    private static func confidence(asleepDuration: TimeInterval, inBedDuration: TimeInterval, samples: [HealthSleepSample]) -> SleepConfidence {
        let asleepMinutes = asleepDuration / 60
        if asleepMinutes >= 300, asleepMinutes <= 720, samples.contains(where: { $0.value == .asleepCore || $0.value == .asleepDeep || $0.value == .asleepREM }) {
            return .high
        }
        if asleepMinutes >= 180, asleepMinutes <= 840 {
            return .medium
        }
        if asleepDuration == 0, inBedDuration > 0 {
            return .low
        }
        return .low
    }

    private func isLikelyNap(start: Date, end: Date, calendar: Calendar) -> Bool {
        let duration = end.timeIntervalSince(start)
        guard duration >= 10 * 60, duration <= 3 * 60 * 60 else { return false }
        let startHour = calendar.component(.hour, from: start)
        let endHour = calendar.component(.hour, from: end)
        return startHour >= 8 && endHour < 20
    }
}

struct HealthKitSleepImportExistingSnapshot: Sendable {
    struct Session: Sendable {
        let startDate: Date
        let endDate: Date
    }

    let healthSampleIds: Set<String>
    private let appleHealthSessions: [Session]
    private let appleHealthNaps: [Session]

    init(sessions: [SleepSession], naps: [NapSession]) {
        self.healthSampleIds = Set(
            sessions.filter { $0.source == .appleHealth }.flatMap(\.healthKitSampleIds)
            + naps.filter { $0.source == .appleHealth }.flatMap(\.healthKitSampleIds)
        )
        self.appleHealthSessions = sessions
            .filter { $0.source == .appleHealth }
            .map { Session(startDate: $0.confirmedSleepStartAt, endDate: $0.wakeAt) }
        self.appleHealthNaps = naps
            .filter { $0.source == .appleHealth }
            .map { Session(startDate: $0.startDate, endDate: $0.endDate) }
    }

    func hasOverlappingAppleHealthSession(start: Date, end: Date) -> Bool {
        appleHealthSessions.contains { $0.endDate > start && $0.startDate < end }
    }

    func hasOverlappingAppleHealthNap(start: Date, end: Date) -> Bool {
        appleHealthNaps.contains { $0.endDate > start && $0.startDate < end }
    }
}

enum HealthKitSleepImportCandidate: Sendable {
    case session(startDate: Date, endDate: Date, confidence: SleepConfidence, healthKitSampleIds: [String])
    case nap(startDate: Date, endDate: Date, healthKitSampleIds: [String])
}

struct HealthKitSleepWriteSnapshot: Sendable {
    let id: UUID
    let sleepModeStartedAt: Date?
    let confirmedSleepStartAt: Date
    let wakeAt: Date
    let source: SleepSource
    let status: SleepSessionStatus
    let healthKitSampleIds: [String]

    init(session: SleepSession) {
        self.id = session.id
        self.sleepModeStartedAt = session.sleepModeStartedAt
        self.confirmedSleepStartAt = session.confirmedSleepStartAt
        self.wakeAt = session.wakeAt
        self.source = session.source
        self.status = session.status
        self.healthKitSampleIds = session.healthKitSampleIds
    }
}
