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

    @MainActor
    func importRecentSleep(days: Int, into context: ModelContext) async -> Int {
        guard isAvailable else { return 0 }

        #if canImport(HealthKit)
        do {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now.addingTimeInterval(-Double(days) * 86_400)
            let samples = try await rawSleepSamples(from: start, to: .now)
            let existingIdentifiers = existingHealthSampleIdentifiers(in: context)
            let grouped = groupedAsleepSamples(samples)
            var imported = 0

            for group in grouped {
                let identifiers = group.samples.map { $0.uuid.uuidString }
                if identifiers.contains(where: { existingIdentifiers.contains($0) }) {
                    continue
                }

                if isLikelyNap(start: group.start, end: group.end, calendar: .current) {
                    if hasOverlappingAppleHealthNap(start: group.start, end: group.end, in: context) {
                        continue
                    }

                    let nap = NapSession(
                        startDate: group.start,
                        endDate: group.end,
                        source: .appleHealth,
                        timingCategory: NapSession.timingCategory(for: group.start),
                        healthKitSampleIds: identifiers
                    )
                    context.insert(nap)
                    imported += 1
                    continue
                }

                guard group.end.timeIntervalSince(group.start) >= 60 * 60 else {
                    continue
                }

                if hasOverlappingAppleHealthSession(start: group.start, end: group.end, in: context) {
                    continue
                }

                let session = SleepSession(
                    confirmedSleepStartAt: group.start,
                    wakeAt: group.end,
                    durationMinutes: Int(group.end.timeIntervalSince(group.start) / 60),
                    source: .appleHealth,
                    confidence: group.hasStages ? .high : .medium,
                    status: .completed,
                    healthKitSampleIds: identifiers
                )
                context.insert(session)
                imported += 1
            }

            if imported > 0 {
                try? context.save()
            }

            var settings = SleepSettingsStore().load()
            settings.lastHealthKitSleepSyncAt = .now
            SleepSettingsStore().save(settings)

            return imported
        } catch {
            return 0
        }
        #else
        return 0
        #endif
    }

    @MainActor
    func writeConfirmedSession(_ session: SleepSession) async throws -> [String] {
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
            healthStore.save(samples) { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed("Apple Health did not accept the sleep samples."))
                }
            }
        }

        return samples.map { $0.uuid.uuidString }
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

    private func existingHealthSampleIdentifiers(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<SleepSession>()
        let sessions = (try? context.fetch(descriptor)) ?? []
        let napDescriptor = FetchDescriptor<NapSession>()
        let naps = (try? context.fetch(napDescriptor)) ?? []
        return Set(sessions.filter { $0.source == .appleHealth }.flatMap(\.healthKitSampleIds) + naps.filter { $0.source == .appleHealth }.flatMap(\.healthKitSampleIds))
    }

    private func hasOverlappingAppleHealthSession(start: Date, end: Date, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SleepSession>()
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.contains { session in
            session.source == .appleHealth
                && session.wakeAt > start
                && session.confirmedSleepStartAt < end
        }
    }

    private func hasOverlappingAppleHealthNap(start: Date, end: Date, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<NapSession>()
        let naps = (try? context.fetch(descriptor)) ?? []
        return naps.contains { nap in
            nap.source == .appleHealth
                && nap.endDate > start
                && nap.startDate < end
        }
    }

    private func isLikelyNap(start: Date, end: Date, calendar: Calendar) -> Bool {
        let duration = end.timeIntervalSince(start)
        guard duration >= 10 * 60, duration <= 3 * 60 * 60 else { return false }
        let startHour = calendar.component(.hour, from: start)
        let endHour = calendar.component(.hour, from: end)
        return startHour >= 8 && endHour < 20
    }
}
