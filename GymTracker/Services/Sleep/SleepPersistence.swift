import Foundation
import SwiftData
import UserNotifications

struct SleepSettingsStore {
    private let key = "sleep.settings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SleepSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SleepSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func save(_ settings: SleepSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

enum SleepSessionValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case wakeBeforeStart
    case startInFuture
    case wakeInFuture

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "This looks too short to count as a sleep session."
        case .tooLong:
            return "This looks unusually long. Please confirm the times."
        case .wakeBeforeStart:
            return "Wake time must be after sleep start."
        case .startInFuture:
            return "Sleep start cannot be in the future."
        case .wakeInFuture:
            return "Wake time cannot be in the future."
        }
    }
}

/// Restores only the SleepSession fields changed by a repository operation when
/// the ModelContext already contains unrelated pending edits. A clean context
/// can use `rollback()` safely because the operation owns all of its changes.
private struct SleepSessionPersistenceSnapshot {
    let confirmedSleepStartAt: Date
    let wakeAt: Date
    let durationMinutes: Int
    let qualityRating: Int?
    let tagRawValues: [String]
    let notes: String?
    let confidence: SleepConfidence
    let status: SleepSessionStatus
    let updatedAt: Date

    init(_ session: SleepSession) {
        confirmedSleepStartAt = session.confirmedSleepStartAt
        wakeAt = session.wakeAt
        durationMinutes = session.durationMinutes
        qualityRating = session.qualityRating
        tagRawValues = session.tagRawValues
        notes = session.notes
        confidence = session.confidence
        status = session.status
        updatedAt = session.updatedAt
    }

    func restore(on session: SleepSession) {
        session.confirmedSleepStartAt = confirmedSleepStartAt
        session.wakeAt = wakeAt
        session.durationMinutes = durationMinutes
        session.qualityRating = qualityRating
        session.tagRawValues = tagRawValues
        session.notes = notes
        session.confidence = confidence
        session.status = status
        session.updatedAt = updatedAt
    }
}

private func saveSleepContextChanges(
    in context: ModelContext,
    hadChangesBeforeOperation: Bool,
    save: (ModelContext) throws -> Void,
    restore: () -> Void
) throws {
    do {
        try save(context)
    } catch {
        if hadChangesBeforeOperation {
            // Do not roll back unrelated pending edits. The caller restores only
            // the model fields or insertion/deletion touched by this operation.
            restore()
        } else {
            // The context was clean before this operation, so rollback is scoped
            // to the failed Sleep/Nap mutation and restores the persisted state.
            context.rollback()
        }
        throw error
    }
}

struct SleepSessionRepository {
    private let saveContext: (ModelContext) throws -> Void

    init(saveContext: @escaping (ModelContext) throws -> Void = { context in
        try context.save()
    }) {
        self.saveContext = saveContext
    }

    func activeSession(in context: ModelContext) -> SleepSession? {
        let activeStatus = SleepSessionStatus.active
        var descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate<SleepSession> { $0.status == activeStatus },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func startSleepMode(windDownMinutes: Int, in context: ModelContext) throws -> SleepSession {
        if let existing = activeSession(in: context) {
            return existing
        }

        let now = Date()
        let estimatedStart = now.addingTimeInterval(TimeInterval(windDownMinutes * 60))
        let session = SleepSession(
            sleepModeStartedAt: now,
            windDownDurationMinutes: windDownMinutes,
            estimatedSleepStartAt: estimatedStart,
            confirmedSleepStartAt: estimatedStart,
            wakeAt: estimatedStart,
            durationMinutes: 0,
            source: .inAppTimer,
            confidence: .low,
            status: .active
        )
        let hadChangesBeforeOperation = context.hasChanges
        context.insert(session)
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            context.delete(session)
        }
        return session
    }

    func startManualSession(start: Date, wake: Date, quality: Int?, tags: [SleepTag], notes: String?, in context: ModelContext) throws {
        try validate(start: start, wake: wake)
        let session = SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: wake,
            durationMinutes: durationMinutes(start: start, wake: wake),
            qualityRating: quality,
            tags: tags,
            notes: notes,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        let hadChangesBeforeOperation = context.hasChanges
        context.insert(session)
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            context.delete(session)
        }
    }

    func confirmActiveSession(
        _ session: SleepSession,
        sleepStart: Date,
        wake: Date,
        quality: Int?,
        tags: [SleepTag],
        in context: ModelContext
    ) throws {
        try validate(start: sleepStart, wake: wake)
        let snapshot = SleepSessionPersistenceSnapshot(session)
        let hadChangesBeforeOperation = context.hasChanges
        session.confirmedSleepStartAt = sleepStart
        session.wakeAt = wake
        session.durationMinutes = durationMinutes(start: sleepStart, wake: wake)
        session.qualityRating = quality
        session.tags = tags
        session.confidence = .estimatedConfirmed
        session.status = .completed
        session.updatedAt = .now
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            snapshot.restore(on: session)
        }
    }

    func updateCompletedSession(
        _ session: SleepSession,
        sleepStart: Date,
        wake: Date,
        quality: Int?,
        tags: [SleepTag],
        notes: String?,
        in context: ModelContext
    ) throws {
        try validate(start: sleepStart, wake: wake)
        let snapshot = SleepSessionPersistenceSnapshot(session)
        let hadChangesBeforeOperation = context.hasChanges
        session.confirmedSleepStartAt = sleepStart
        session.wakeAt = wake
        session.durationMinutes = durationMinutes(start: sleepStart, wake: wake)
        session.qualityRating = quality
        session.tags = tags
        session.notes = notes
        session.updatedAt = .now
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            snapshot.restore(on: session)
        }
    }

    func discard(_ session: SleepSession, in context: ModelContext) throws {
        let snapshot = SleepSessionPersistenceSnapshot(session)
        let hadChangesBeforeOperation = context.hasChanges
        session.status = .discarded
        session.updatedAt = .now
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            snapshot.restore(on: session)
        }
    }

    func delete(_ session: SleepSession, in context: ModelContext) throws {
        let hadChangesBeforeOperation = context.hasChanges
        context.delete(session)
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            // A pending delete can be re-registered without touching unrelated
            // dirty models when rollback is intentionally not allowed.
            context.insert(session)
        }
    }

    func durationMinutes(start: Date, wake: Date) -> Int {
        max(0, Int(wake.timeIntervalSince(start) / 60))
    }

    func validate(start: Date, wake: Date, allowTooLongWarning: Bool = false) throws {
        guard start <= Date.now.addingTimeInterval(60) else { throw SleepSessionValidationError.startInFuture }
        guard wake > start else { throw SleepSessionValidationError.wakeBeforeStart }
        guard wake <= Date.now else { throw SleepSessionValidationError.wakeInFuture }

        let minutes = durationMinutes(start: start, wake: wake)
        guard minutes >= 60 else { throw SleepSessionValidationError.tooShort }
        if !allowTooLongWarning {
            guard minutes <= 14 * 60 else { throw SleepSessionValidationError.tooLong }
        }
    }
}

enum NapSessionValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case endBeforeStart
    case startInFuture
    case endInFuture

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Naps need to be at least 10 minutes to count."
        case .tooLong:
            return "That looks longer than a normal nap. Add it as sleep if it was your main rest."
        case .endBeforeStart:
            return "Nap end time must be after the start time."
        case .startInFuture:
            return "Nap start time cannot be in the future."
        case .endInFuture:
            return "Nap end time cannot be in the future."
        }
    }
}

struct NapSessionRepository {
    private let saveContext: (ModelContext) throws -> Void

    init(saveContext: @escaping (ModelContext) throws -> Void = { context in
        try context.save()
    }) {
        self.saveContext = saveContext
    }

    func addNap(start: Date, end: Date, quality: Int?, note: String?, source: NapSource = .manual, healthKitSampleIds: [String] = [], in context: ModelContext) throws {
        try validate(start: start, end: end)
        let nap = NapSession(
            startDate: start,
            endDate: end,
            qualityRating: quality,
            source: source,
            timingCategory: NapSession.timingCategory(for: start),
            note: note?.isEmpty == true ? nil : note,
            healthKitSampleIds: healthKitSampleIds
        )
        let hadChangesBeforeOperation = context.hasChanges
        context.insert(nap)
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            context.delete(nap)
        }
    }

    func delete(_ nap: NapSession, in context: ModelContext) throws {
        let hadChangesBeforeOperation = context.hasChanges
        context.delete(nap)
        try saveSleepContextChanges(
            in: context,
            hadChangesBeforeOperation: hadChangesBeforeOperation,
            save: saveContext
        ) {
            context.insert(nap)
        }
    }

    func validate(start: Date, end: Date) throws {
        guard start <= Date.now.addingTimeInterval(60) else { throw NapSessionValidationError.startInFuture }
        guard end > start else { throw NapSessionValidationError.endBeforeStart }
        guard end <= Date.now else { throw NapSessionValidationError.endInFuture }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes >= 10 else { throw NapSessionValidationError.tooShort }
        guard minutes <= 180 else { throw NapSessionValidationError.tooLong }
    }
}
