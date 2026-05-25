import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

protocol HealthKitProviding {
    var isAvailable: Bool { get }
    func requestAuthorization(preferences: HealthKitSyncPreferences) async throws -> HealthKitPermissionState
    func currentPermissionState(preferences: HealthKitSyncPreferences) -> HealthKitPermissionState
    func sync(entries: [FoodLogEntry], foodItemsById: [UUID: FoodItem], preferences: HealthKitSyncPreferences) async -> HealthKitSyncSummary
    func dailyContext(for date: Date, preferences: HealthKitSyncPreferences) async -> HealthKitDailyContext?
}

struct HealthKitPreferenceStore {
    private let key = "healthkit.sync.preferences.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HealthKitSyncPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(HealthKitSyncPreferences.self, from: data) else {
            return .default
        }

        return preferences
    }

    func save(_ preferences: HealthKitSyncPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

struct HealthKitSyncStateStore {
    private let key = "healthkit.foodlog.sync.records.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func records() -> [HealthKitFoodLogSyncRecord] {
        loadRecords().values.sorted {
            ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast)
        }
    }

    func record(for foodLogEntryId: UUID) -> HealthKitFoodLogSyncRecord? {
        loadRecords()[foodLogEntryId.uuidString]
    }

    func save(_ record: HealthKitFoodLogSyncRecord) {
        var records = loadRecords()
        records[record.foodLogEntryId.uuidString] = record
        saveRecords(records)
    }

    func removeRecord(for foodLogEntryId: UUID) {
        var records = loadRecords()
        records.removeValue(forKey: foodLogEntryId.uuidString)
        saveRecords(records)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func loadRecords() -> [String: HealthKitFoodLogSyncRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([String: HealthKitFoodLogSyncRecord].self, from: data) else {
            return [:]
        }

        return records
    }

    private func saveRecords(_ records: [String: HealthKitFoodLogSyncRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

struct HealthKitAvailabilityService {
    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    var unavailableReason: String? {
        isHealthDataAvailable ? nil : "Apple Health is not available on this device."
    }
}

struct HealthKitFoodLogSyncSnapshot {
    let id: UUID
    let foodItemId: UUID
    let foodNameSnapshot: String
    let mealType: MealType
    let caloriesSnapshot: Double
    let proteinSnapshot: Double
    let carbsSnapshot: Double
    let fatSnapshot: Double
    let sugarSnapshot: Double?
    let fibreSnapshot: Double?
    let saltSnapshot: Double?
    let loggedAt: Date
    let updatedAt: Date

    init(entry: FoodLogEntry) {
        self.id = entry.id
        self.foodItemId = entry.foodItemId
        self.foodNameSnapshot = entry.foodNameSnapshot
        self.mealType = entry.mealType
        self.caloriesSnapshot = entry.caloriesSnapshot
        self.proteinSnapshot = entry.proteinSnapshot
        self.carbsSnapshot = entry.carbsSnapshot
        self.fatSnapshot = entry.fatSnapshot
        self.sugarSnapshot = entry.sugarSnapshot
        self.fibreSnapshot = entry.fibreSnapshot
        self.saltSnapshot = entry.saltSnapshot
        self.loggedAt = entry.loggedAt
        self.updatedAt = entry.updatedAt
    }
}

struct HealthKitFoodItemSyncSnapshot {
    let id: UUID
    let verificationStatus: FoodVerificationStatus

    init(food: FoodItem) {
        self.id = food.id
        self.verificationStatus = food.verificationStatus
    }
}

#if canImport(HealthKit)
private enum HealthKitTypeRegistry {
    static func writeTypes(preferences: HealthKitSyncPreferences) -> Set<HKSampleType> {
        guard preferences.isHealthKitEnabled, preferences.writeNutritionToHealthKit else { return [] }

        var identifiers: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal
        ]

        if preferences.includeSugarAndFibreIfAvailable {
            identifiers.append(contentsOf: [.dietarySugar, .dietaryFiber])
        }

        if preferences.includeSodiumIfAvailable {
            identifiers.append(.dietarySodium)
        }

        return Set(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
    }

    static func readTypes(preferences: HealthKitSyncPreferences) -> Set<HKObjectType> {
        guard preferences.isHealthKitEnabled else { return [] }

        var types: [HKObjectType] = []

        if preferences.readBodyWeight, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.append(type)
        }

        if preferences.readActiveEnergy, let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.append(type)
        }

        if preferences.readStepCount, let type = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.append(type)
        }

        if preferences.readWorkouts {
            types.append(HKObjectType.workoutType())
        }

        return Set(types)
    }
}
#endif

final class NutritionHealthKitBridge: HealthKitProviding {
    private let availabilityService: HealthKitAvailabilityService
    private let syncStore: HealthKitSyncStateStore

    #if canImport(HealthKit)
    private let healthStore: HKHealthStore

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        availabilityService: HealthKitAvailabilityService = HealthKitAvailabilityService(),
        syncStore: HealthKitSyncStateStore = HealthKitSyncStateStore()
    ) {
        self.healthStore = healthStore
        self.availabilityService = availabilityService
        self.syncStore = syncStore
    }
    #else
    init(
        availabilityService: HealthKitAvailabilityService = HealthKitAvailabilityService(),
        syncStore: HealthKitSyncStateStore = HealthKitSyncStateStore()
    ) {
        self.availabilityService = availabilityService
        self.syncStore = syncStore
    }
    #endif

    var isAvailable: Bool {
        availabilityService.isHealthDataAvailable
    }

    func requestAuthorization(preferences: HealthKitSyncPreferences) async throws -> HealthKitPermissionState {
        guard isAvailable else { throw HealthKitSyncError.unavailable }
        guard preferences.isHealthKitEnabled, preferences.requestsAnyHealthData else { return .notRequested }

        #if canImport(HealthKit)
        let writeTypes = HealthKitTypeRegistry.writeTypes(preferences: preferences)
        let readTypes = HealthKitTypeRegistry.readTypes(preferences: preferences)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { _, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.unknown(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        return currentPermissionState(preferences: preferences)
        #else
        throw HealthKitSyncError.unavailable
        #endif
    }

    func currentPermissionState(preferences: HealthKitSyncPreferences) -> HealthKitPermissionState {
        guard isAvailable else { return .unavailable }
        guard preferences.isHealthKitEnabled, preferences.requestsAnyHealthData else { return .notRequested }

        #if canImport(HealthKit)
        let writeTypes = HealthKitTypeRegistry.writeTypes(preferences: preferences)
        guard !writeTypes.isEmpty else {
            return preferences.requestsAnyReadData ? .readOnlyRequested : .notRequested
        }

        let statuses = writeTypes.map { healthStore.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            return .sharingAuthorized
        }

        if statuses.contains(.sharingAuthorized) {
            return .partiallyAuthorized
        }

        if statuses.contains(.sharingDenied) {
            return .sharingDenied
        }

        return .notRequested
        #else
        return .unavailable
        #endif
    }

    func sync(
        entries: [FoodLogEntry],
        foodItemsById: [UUID: FoodItem] = [:],
        preferences: HealthKitSyncPreferences
    ) async -> HealthKitSyncSummary {
        let entrySnapshots = entries.map { HealthKitFoodLogSyncSnapshot(entry: $0) }
        let foodSnapshots = Dictionary(uniqueKeysWithValues: foodItemsById.map { key, value in
            (key, HealthKitFoodItemSyncSnapshot(food: value))
        })
        return await sync(entries: entrySnapshots, foodItemsById: foodSnapshots, preferences: preferences)
    }

    func sync(
        entries: [HealthKitFoodLogSyncSnapshot],
        foodItemsById: [UUID: HealthKitFoodItemSyncSnapshot] = [:],
        preferences: HealthKitSyncPreferences
    ) async -> HealthKitSyncSummary {
        await PerformanceTracer.traceAsync(.nutritionHealthKitSync) {
            await syncUntraced(entries: entries, foodItemsById: foodItemsById, preferences: preferences)
        }
    }

    private func syncUntraced(
        entries: [HealthKitFoodLogSyncSnapshot],
        foodItemsById: [UUID: HealthKitFoodItemSyncSnapshot] = [:],
        preferences: HealthKitSyncPreferences
    ) async -> HealthKitSyncSummary {
        var summary = HealthKitSyncSummary()

        guard preferences.isHealthKitEnabled, preferences.writeNutritionToHealthKit else {
            entries.forEach { entry in
                syncStore.save(record(for: entry, status: .notEnabled, errorMessage: nil))
            }
            summary.skipped = entries.count
            return summary
        }

        guard isAvailable else {
            entries.forEach { entry in
                syncStore.save(record(for: entry, status: .unavailable, errorMessage: HealthKitSyncError.unavailable.localizedDescription))
            }
            summary.failed = entries.count
            return summary
        }

        #if canImport(HealthKit)
        let permissionState = currentPermissionState(preferences: preferences)
        guard permissionState == .sharingAuthorized || permissionState == .partiallyAuthorized else {
            entries.forEach { entry in
                syncStore.save(record(for: entry, status: .failed, errorMessage: HealthKitSyncError.authorizationDenied.localizedDescription))
            }
            summary.failed = entries.count
            return summary
        }

        for entry in entries {
            summary.attempted += 1

            if let existing = syncStore.record(for: entry.id),
               existing.status == .synced,
               existing.syncVersion == HealthKitFoodLogSyncRecord.currentSyncVersion {
                if entry.updatedAt > (existing.sourceUpdatedAt ?? .distantPast) {
                    syncStore.save(record(for: entry, status: .needsResync, errorMessage: "This log changed after syncing. Manual Apple Health cleanup is deferred."))
                    summary.skipped += 1
                    summary.warnings.append("\(entry.foodNameSnapshot) changed after syncing and was not duplicated.")
                } else {
                    summary.skipped += 1
                }
                continue
            }

            if preferences.syncOnlyUserConfirmedEntries,
               let food = foodItemsById[entry.foodItemId],
               food.verificationStatus != .userVerified,
               food.verificationStatus != .edited {
                syncStore.save(record(for: entry, status: .skipped, errorMessage: "Food is not user-confirmed."))
                summary.skipped += 1
                continue
            }

            do {
                let build = try makeSamples(for: entry, preferences: preferences)
                let warnings = build.warnings.map { "\(entry.foodNameSnapshot): \($0)" }
                summary.warnings.append(contentsOf: warnings)

                try await save(samples: build.samples)

                let syncedAt = Date.now
                let identifiers = build.samples.map { $0.uuid.uuidString }
                syncStore.save(record(for: entry, status: .synced, sampleIdentifiers: identifiers, syncedAt: syncedAt, errorMessage: nil))
                summary.synced += 1
            } catch {
                syncStore.save(record(for: entry, status: .failed, errorMessage: userFacingMessage(from: error)))
                summary.failed += 1
            }
        }

        summary.finishedAt = .now
        return summary
        #else
        entries.forEach { entry in
            syncStore.save(record(for: entry, status: .unavailable, errorMessage: HealthKitSyncError.unavailable.localizedDescription))
        }
        summary.failed = entries.count
        return summary
        #endif
    }

    func dailyContext(for date: Date, preferences: HealthKitSyncPreferences) async -> HealthKitDailyContext? {
        guard preferences.isHealthKitEnabled, preferences.requestsAnyReadData, isAvailable else { return nil }

        #if canImport(HealthKit)
        var context = HealthKitDailyContext(date: date)

        if preferences.readBodyWeight {
            context.bodyMassKg = try? await latestBodyMassKilograms(before: date)
        }

        let interval = Calendar.current.dateInterval(of: .day, for: date)

        if preferences.readActiveEnergy, let interval {
            context.activeEnergyKcal = try? await sumQuantity(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                start: interval.start,
                end: interval.end
            )
        }

        if preferences.readStepCount, let interval {
            context.stepCount = try? await sumQuantity(
                identifier: .stepCount,
                unit: .count(),
                start: interval.start,
                end: interval.end
            )
        }

        if preferences.readWorkouts, let interval {
            context.workoutCount = try? await workoutCount(start: interval.start, end: interval.end)
        }

        return context.hasAnyValue ? context : nil
        #else
        return nil
        #endif
    }

    private func record(
        for entry: HealthKitFoodLogSyncSnapshot,
        status: HealthKitSyncStatus,
        sampleIdentifiers: [String] = [],
        syncedAt: Date? = nil,
        errorMessage: String?
    ) -> HealthKitFoodLogSyncRecord {
        HealthKitFoodLogSyncRecord(
            foodLogEntryId: entry.id,
            foodItemId: entry.foodItemId,
            foodName: entry.foodNameSnapshot,
            sampleIdentifiers: sampleIdentifiers,
            status: status,
            lastSyncedAt: syncedAt,
            sourceUpdatedAt: entry.updatedAt,
            errorMessage: errorMessage
        )
    }

    private func userFacingMessage(from error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

#if canImport(HealthKit)
private extension NutritionHealthKitBridge {
    struct SampleBuild {
        var samples: [HKQuantitySample]
        var warnings: [String]
    }

    func makeSamples(for entry: HealthKitFoodLogSyncSnapshot, preferences: HealthKitSyncPreferences) throws -> SampleBuild {
        let metadata: [String: Any] = [
            "GymTrackerFoodLogEntryID": entry.id.uuidString,
            "GymTrackerFoodItemID": entry.foodItemId.uuidString,
            "GymTrackerMealType": entry.mealType.rawValue,
            "GymTrackerSyncVersion": HealthKitFoodLogSyncRecord.currentSyncVersion,
            "GymTrackerSource": "GymTracker"
        ]
        let startDate = entry.loggedAt
        let endDate = startDate.addingTimeInterval(1)
        var samples: [HKQuantitySample] = []
        var warnings: [String] = []

        try appendSample(
            identifier: .dietaryEnergyConsumed,
            label: "Calories",
            value: entry.caloriesSnapshot,
            upperWarning: 3000,
            unit: .kilocalorie(),
            startDate: startDate,
            endDate: endDate,
            metadata: metadata,
            samples: &samples,
            warnings: &warnings
        )

        try appendSample(identifier: .dietaryProtein, label: "Protein", value: entry.proteinSnapshot, upperWarning: 250, unit: .gram(), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)
        try appendSample(identifier: .dietaryCarbohydrates, label: "Carbs", value: entry.carbsSnapshot, upperWarning: 500, unit: .gram(), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)
        try appendSample(identifier: .dietaryFatTotal, label: "Fat", value: entry.fatSnapshot, upperWarning: 250, unit: .gram(), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)

        if preferences.includeSugarAndFibreIfAvailable {
            try appendSample(identifier: .dietarySugar, label: "Sugar", value: entry.sugarSnapshot, upperWarning: 300, unit: .gram(), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)
            try appendSample(identifier: .dietaryFiber, label: "Fibre", value: entry.fibreSnapshot, upperWarning: 100, unit: .gram(), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)
        }

        if preferences.includeSodiumIfAvailable, let salt = entry.saltSnapshot {
            let sodiumMilligrams = salt / 2.5 * 1000
            try appendSample(identifier: .dietarySodium, label: "Sodium", value: sodiumMilligrams, upperWarning: 10000, unit: HKUnit.gramUnit(with: .milli), startDate: startDate, endDate: endDate, metadata: metadata, samples: &samples, warnings: &warnings)
        }

        guard !samples.isEmpty else { throw HealthKitSyncError.noSupportedValues }
        return SampleBuild(samples: samples, warnings: warnings)
    }

    func appendSample(
        identifier: HKQuantityTypeIdentifier,
        label: String,
        value: Double?,
        upperWarning: Double,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        metadata: [String: Any],
        samples: inout [HKQuantitySample],
        warnings: inout [String]
    ) throws {
        guard let value else { return }
        guard value.isFinite, value >= 0 else { throw HealthKitSyncError.invalidNutritionValue(label) }
        guard value > 0 else { return }

        if value > upperWarning {
            warnings.append("\(label) looks unusually high and was synced as logged.")
        }

        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitSyncError.missingQuantityType(label)
        }

        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: startDate, end: endDate, metadata: metadata)
        samples.append(sample)
    }

    func save(samples: [HKQuantitySample]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: HealthKitSyncError.saveFailed("Apple Health did not accept the samples."))
                }
            }
        }
    }

    func latestBodyMassKilograms(before date: Date) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitSyncError.missingQuantityType("Body mass")
        }

        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.readFailed(error.localizedDescription))
                    return
                }

                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    func sumQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitSyncError.missingQuantityType(identifier.rawValue)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.readFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    func workoutCount(start: Date, end: Date) async throws -> Int? {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitSyncError.readFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples?.count ?? 0)
            }

            healthStore.execute(query)
        }
    }
}
#endif
