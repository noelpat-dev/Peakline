import Foundation
import SwiftData

#if canImport(HealthKit)
import HealthKit
#endif

enum HealthKitSleepAccessState: String, Codable, Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case restricted
    case enabledUnverified
    case authorized

    var displayName: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Permission denied"
        case .restricted:
            return "Restricted"
        case .enabledUnverified:
            return "Enabled · read access unverified"
        case .authorized:
            return "Authorized"
        }
    }
}

enum HealthKitSleepWriteAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

struct HealthKitSleepAccessInput: Equatable, Sendable {
    let isAvailable: Bool
    let readEnabled: Bool
    let writeEnabled: Bool
    let authorizationWasRequested: Bool
    let writeAuthorization: HealthKitSleepWriteAuthorization

    init(
        isAvailable: Bool,
        readEnabled: Bool,
        writeEnabled: Bool,
        authorizationWasRequested: Bool,
        writeAuthorization: HealthKitSleepWriteAuthorization = .notDetermined
    ) {
        self.isAvailable = isAvailable
        self.readEnabled = readEnabled
        self.writeEnabled = writeEnabled
        self.authorizationWasRequested = authorizationWasRequested
        self.writeAuthorization = writeAuthorization
    }
}

struct HealthKitSleepAccessSnapshot: Equatable, Sendable {
    let overall: HealthKitSleepAccessState
    let read: HealthKitSleepAccessState
    let write: HealthKitSleepAccessState
    let readEnabled: Bool
    let writeEnabled: Bool
    let authorizationWasRequested: Bool

    var displayName: String {
        overall.displayName
    }
}

enum HealthKitSleepAccessResolver {
    /// Resolves the status that can be known without claiming HealthKit read
    /// authorization. HealthKit intentionally does not expose the user's read
    /// decision, so an enabled read request becomes `enabledUnverified` after
    /// the authorization sheet completes.
    static func resolve(_ input: HealthKitSleepAccessInput) -> HealthKitSleepAccessSnapshot {
        guard input.isAvailable else {
            return HealthKitSleepAccessSnapshot(
                overall: .unavailable,
                read: .unavailable,
                write: .unavailable,
                readEnabled: input.readEnabled,
                writeEnabled: input.writeEnabled,
                authorizationWasRequested: input.authorizationWasRequested
            )
        }

        let read: HealthKitSleepAccessState
        if !input.readEnabled {
            read = .notDetermined
        } else if !input.authorizationWasRequested {
            read = .notDetermined
        } else {
            read = .enabledUnverified
        }

        let write: HealthKitSleepAccessState
        if !input.writeEnabled {
            write = .notDetermined
        } else if !input.authorizationWasRequested {
            write = .notDetermined
        } else {
            switch input.writeAuthorization {
            case .notDetermined:
                write = .notDetermined
            case .denied:
                write = .denied
            case .restricted:
                write = .restricted
            case .authorized:
                write = .authorized
            }
        }

        let overall: HealthKitSleepAccessState
        if write == .restricted {
            overall = .restricted
        } else if write == .denied {
            overall = .denied
        } else if input.readEnabled && input.authorizationWasRequested {
            overall = .enabledUnverified
        } else if input.writeEnabled && write == .authorized {
            overall = .authorized
        } else {
            overall = .notDetermined
        }

        return HealthKitSleepAccessSnapshot(
            overall: overall,
            read: read,
            write: write,
            readEnabled: input.readEnabled,
            writeEnabled: input.writeEnabled,
            authorizationWasRequested: input.authorizationWasRequested
        )
    }
}

enum HealthKitSleepImportError: Error, LocalizedError, Equatable, Sendable {
    case unavailable
    case authorizationDenied
    case restricted
    case readFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .authorizationDenied:
            return "Apple Health sleep read access was denied."
        case .restricted:
            return "Apple Health sleep access is restricted on this device."
        case .readFailed(let message):
            return "Apple Health sleep read failed. \(message)"
        case .unknown(let message):
            return message
        }
    }
}

enum HealthKitSleepImportResult: Equatable, Sendable {
    case unavailable
    case notRequested
    case denied
    case restricted
    case importing
    case noNewData(lastSyncedAt: Date?)
    case imported(candidates: [HealthKitSleepImportCandidate], lastSyncedAt: Date?)
    case error(HealthKitSleepImportError)

    var importedCount: Int {
        guard case .imported(let candidates, _) = self else { return 0 }
        return candidates.count
    }

    var error: HealthKitSleepImportError? {
        guard case .error(let error) = self else { return nil }
        return error
    }
}

enum HealthKitSleepImportPresentation: Equatable, Sendable {
    case idle
    case importing
    case unavailable
    case notRequested
    case denied
    case restricted
    case lastSynced(Date)
    case noNewData(lastSyncedAt: Date?)
    case imported(count: Int, lastSyncedAt: Date?)
    case error(String)

    static func make(
        result: HealthKitSleepImportResult,
        lastSyncedAt: Date? = nil
    ) -> HealthKitSleepImportPresentation {
        switch result {
        case .unavailable:
            return .unavailable
        case .notRequested:
            return .notRequested
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .importing:
            return .importing
        case .noNewData(let resultLastSyncedAt):
            return .noNewData(lastSyncedAt: resultLastSyncedAt ?? lastSyncedAt)
        case .imported(let candidates, let resultLastSyncedAt):
            return .imported(count: candidates.count, lastSyncedAt: resultLastSyncedAt ?? lastSyncedAt)
        case .error(let error):
            return .error(error.localizedDescription)
        }
    }
}

struct HealthKitSleepService {
    /// Sleep-stage records are normally sparse (roughly one record every few
    /// minutes), but HealthKit can contain overlapping sources. Keep the
    /// optional import bounded even when a caller supplies a wide date range;
    /// a partial result still groups into the best available sleep candidates.
    static let sleepSampleQueryLimit = 10_000

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

    @discardableResult
    func requestReadAuthorization() async throws -> HealthKitSleepAccessSnapshot {
        try await requestAuthorization(read: true, write: false)
    }

    @discardableResult
    func requestWriteAuthorization() async throws -> HealthKitSleepAccessSnapshot {
        try await requestAuthorization(read: false, write: true)
    }

    @discardableResult
    func requestAuthorization(read: Bool, write: Bool) async throws -> HealthKitSleepAccessSnapshot {
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

        return accessSnapshot(
            readEnabled: read,
            writeEnabled: write,
            authorizationWasRequested: true
        )
        #else
        throw HealthKitSyncError.unavailable
        #endif
    }

    func accessSnapshot(
        readEnabled: Bool,
        writeEnabled: Bool,
        authorizationWasRequested: Bool = false
    ) -> HealthKitSleepAccessSnapshot {
        let writeAuthorization: HealthKitSleepWriteAuthorization
        #if canImport(HealthKit)
        if writeEnabled && authorizationWasRequested,
           let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            switch healthStore.authorizationStatus(for: sleepType) {
            case .sharingAuthorized:
                writeAuthorization = .authorized
            case .sharingDenied:
                writeAuthorization = .denied
            case .notDetermined:
                writeAuthorization = .notDetermined
            @unknown default:
                writeAuthorization = .restricted
            }
        } else {
            writeAuthorization = .notDetermined
        }
        #else
        writeAuthorization = .notDetermined
        #endif

        return HealthKitSleepAccessResolver.resolve(
            HealthKitSleepAccessInput(
                isAvailable: isAvailable,
                readEnabled: readEnabled,
                writeEnabled: writeEnabled,
                authorizationWasRequested: authorizationWasRequested,
                writeAuthorization: writeAuthorization
            )
        )
    }

    /// Structured import API. The result distinguishes no data from read failure
    /// and permission states; callers should publish `.importing` before awaiting
    /// this operation and only record a sync timestamp for a successful result.
    func importRecentSleepCandidatesResult(
        days: Int,
        existing: HealthKitSleepImportExistingSnapshot,
        access: HealthKitSleepAccessSnapshot? = nil
    ) async -> HealthKitSleepImportResult {
        PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates begin days=\(days)")
        guard isAvailable else { return .unavailable }

        if let access {
            switch access.read {
            case .unavailable:
                return .unavailable
            case .notDetermined:
                return .notRequested
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .enabledUnverified, .authorized:
                break
            }
        }

        #if canImport(HealthKit)
        do {
            // Capture one reference instant for the whole query. HealthKit's
            // default sample predicate includes intervals that overlap the
            // query window, so a clock anomaly or an in-progress sample can
            // otherwise produce a group whose end is still in the future.
            let referenceNow = Date.now
            let start = Calendar.current.date(byAdding: .day, value: -days, to: referenceNow) ?? referenceNow.addingTimeInterval(-Double(days) * 86_400)
            let samples = try await rawSleepSamples(from: start, to: referenceNow)
            PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates samples=\(samples.count)")
            let grouped = groupedAsleepSamples(samples)
            var candidates: [HealthKitSleepImportCandidate] = []

            for group in grouped {
                guard HealthKitSleepImportCandidate.isValidImportInterval(
                    startDate: group.start,
                    endDate: group.end,
                    referenceNow: referenceNow
                ) else {
                    PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates skipped future interval")
                    continue
                }

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
            if candidates.isEmpty {
                return .noNewData(lastSyncedAt: nil)
            }
            return .imported(candidates: candidates, lastSyncedAt: nil)
        } catch {
            PerformanceTracer.mark(.healthKitSleepBridge, "importRecentSleepCandidates error=\(error.localizedDescription)")
            return Self.importResult(for: error)
        }
        #else
        return .unavailable
        #endif
    }

    /// Compatibility wrapper for the pre-result API. New callers should use
    /// `importRecentSleepCandidatesResult` so failures cannot be mistaken for an
    /// empty HealthKit result.
    @available(*, deprecated, message: "Use importRecentSleepCandidatesResult(days:existing:access:)")
    func importRecentSleepCandidates(days: Int, existing: HealthKitSleepImportExistingSnapshot) async -> [HealthKitSleepImportCandidate] {
        let result = await importRecentSleepCandidatesResult(days: days, existing: existing)
        guard case .imported(let candidates, _) = result else { return [] }
        return candidates
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

    private static func importResult(for error: Error) -> HealthKitSleepImportResult {
        if let syncError = error as? HealthKitSyncError {
            switch syncError {
            case .unavailable:
                return .unavailable
            case .authorizationDenied:
                return .denied
            case .readFailed(let message):
                return .error(.readFailed(message))
            case .unknown(let message):
                return .error(.unknown(message))
            case .missingQuantityType(let name), .invalidNutritionValue(let name):
                return .error(.unknown("Apple Health does not support \(name)."))
            case .noSupportedValues:
                return .error(.unknown("Apple Health returned no supported sleep values."))
            case .saveFailed(let message), .deleteFailed(let message):
                return .error(.unknown(message))
            }
        }

        return .error(.unknown(error.localizedDescription))
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
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: Self.sleepSampleQueryLimit, sortDescriptors: [sort]) { _, samples, error in
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
            sessions.flatMap(\.healthKitSampleIds)
            + naps.flatMap(\.healthKitSampleIds)
        )
        self.appleHealthSessions = sessions
            .map { Session(startDate: $0.confirmedSleepStartAt, endDate: $0.wakeAt) }
        self.appleHealthNaps = naps
            .map { Session(startDate: $0.startDate, endDate: $0.endDate) }
    }

    func hasOverlappingAppleHealthSession(start: Date, end: Date) -> Bool {
        appleHealthSessions.contains { $0.endDate > start && $0.startDate < end }
    }

    func hasOverlappingAppleHealthNap(start: Date, end: Date) -> Bool {
        appleHealthNaps.contains { $0.endDate > start && $0.startDate < end }
    }
}

enum HealthKitSleepImportCandidate: Sendable, Equatable {
    case session(startDate: Date, endDate: Date, confidence: SleepConfidence, healthKitSampleIds: [String])
    case nap(startDate: Date, endDate: Date, healthKitSampleIds: [String])

    static func isValidImportInterval(
        startDate: Date,
        endDate: Date,
        referenceNow: Date
    ) -> Bool {
        startDate <= referenceNow
            && endDate > startDate
            && endDate <= referenceNow
    }

    func isValidForImport(at referenceNow: Date) -> Bool {
        switch self {
        case let .session(startDate, endDate, _, _), let .nap(startDate, endDate, _):
            return Self.isValidImportInterval(
                startDate: startDate,
                endDate: endDate,
                referenceNow: referenceNow
            )
        }
    }
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
