import Foundation
import SwiftData

struct FullAppBackupCounts: Codable, Equatable, Sendable {
    var userProfileCount: Int
    var exerciseCount: Int
    var splitCount: Int
    var workoutCount: Int
    var recommendationCount: Int
    var bodyweightCount: Int
    var foodItemCount: Int
    var foodLogCount: Int
    var hydrationCount: Int
    var sleepCount: Int
    var napCount: Int
    var coachRecordCount: Int
    var userContentCount: Int
    var workoutTemplateCount: Int? = nil

    var totalRecordCount: Int {
        userProfileCount + exerciseCount + splitCount + workoutCount + recommendationCount
            + bodyweightCount + foodItemCount + foodLogCount + hydrationCount + sleepCount
            + napCount + coachRecordCount + (workoutTemplateCount ?? 0)
    }
}

struct FullAppBackupMetadata: Codable, Equatable, Sendable {
    let createdAt: Date
    let exportedAt: Date
    let counts: FullAppBackupCounts
    let compressedByteCount: Int
    let appVersion: String?
}

enum FullAppBackupLimits {
    static let maxRecordCount = 100_000
    static let maxCompressedPayloadBytes = 64 * 1024 * 1024
    static let maxDecompressedPayloadBytes = 128 * 1024 * 1024
    static let maxCloudChunkCount = 256
    static let maxCloudChunkBytes = 480 * 1_024
}

struct FullAppBackupImportSummary: Equatable {
    let counts: FullAppBackupCounts
    let importedAt: Date
}

struct FullAppBackupEnvelope: Codable, @unchecked Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let appName: String
    let appVersion: String?
    let preferences: FullAppPreferencesBackupDTO
    let data: FullAppBackupDataDTO

    var counts: FullAppBackupCounts {
        data.counts
    }
}

struct FullAppPreferencesBackupDTO: Codable, Equatable {
    var appTheme: String?
    var appAppearance: String?
    var sleepSettings: SleepSettings
    var healthKitSyncPreferences: HealthKitSyncPreferences
    var hydrationDailyTargetML: Int
    var nutritionGoal: NutritionGoal

    init(defaults: UserDefaults = .standard) {
        appTheme = defaults.string(forKey: "appTheme")
        appAppearance = defaults.string(forKey: "appAppearance")
        sleepSettings = SleepSettingsStore(defaults: defaults).load()
        healthKitSyncPreferences = HealthKitPreferenceStore(defaults: defaults).load()
        hydrationDailyTargetML = HydrationSettingsStore(defaults: defaults).dailyTargetML()
        nutritionGoal = NutritionGoalService(defaults: defaults).loadGoal()
    }

    func apply(to defaults: UserDefaults = .standard) {
        if let appTheme {
            defaults.set(appTheme, forKey: "appTheme")
        }
        if let appAppearance {
            defaults.set(appAppearance, forKey: "appAppearance")
        }
        SleepSettingsStore(defaults: defaults).save(sleepSettings)
        HealthKitPreferenceStore(defaults: defaults).save(healthKitSyncPreferences)
        HydrationSettingsStore(defaults: defaults).saveDailyTargetML(hydrationDailyTargetML)
        NutritionGoalService(defaults: defaults).saveGoal(nutritionGoal)
    }
}

struct FullAppBackupDataDTO: Codable, @unchecked Sendable {
    var userProfiles: [UserProfileBackupDTO]
    var exercises: [ExerciseBackupDTO]
    var splits: [TrainingSplitBackupDTO]
    var workouts: [WorkoutSessionBackupDTO]
    var recommendations: [RecommendationBackupDTO]
    var bodyweightLogs: [BodyweightLogBackupDTO]
    var foodItems: [FoodItemBackupDTO]
    var foodLogs: [FoodLogEntryBackupDTO]
    var hydrationEntries: [HydrationEntryBackupDTO]
    var sleepSessions: [SleepSessionBackupDTO]
    var napSessions: [NapSessionBackupDTO]
    var dailyCoachCheckIns: [DailyCoachCheckInBackupDTO]
    var coachPreferences: [CoachPreferencesBackupDTO]
    var coachSplitMetadata: [CoachSplitMetadataBackupDTO]
    var coachActionHistory: [CoachActionHistoryEntryBackupDTO]
    var savedCoachDeloadBlocks: [SavedCoachDeloadBlockBackupDTO]
    var coachExerciseMetadata: [CoachExerciseMetadataBackupDTO]
    var coachRecommendationFeedback: [CoachRecommendationFeedbackBackupDTO]
    var workoutTemplates: [CustomWorkoutTemplate]? = nil

    var counts: FullAppBackupCounts {
        let coreUserContentCount = workouts.count
            + recommendations.count
            + bodyweightLogs.count
            + foodItems.count
            + foodLogs.count
            + hydrationEntries.count
            + sleepSessions.count
            + napSessions.count
            + (workoutTemplates?.count ?? 0)
        let coachCount = dailyCoachCheckIns.count
            + coachPreferences.count
            + coachSplitMetadata.count
            + coachActionHistory.count
            + savedCoachDeloadBlocks.count
            + coachExerciseMetadata.count
            + coachRecommendationFeedback.count
        let userContentCount = coreUserContentCount + coachCount
        return FullAppBackupCounts(
            userProfileCount: userProfiles.count,
            exerciseCount: exercises.count,
            splitCount: splits.count,
            workoutCount: workouts.count,
            recommendationCount: recommendations.count,
            bodyweightCount: bodyweightLogs.count,
            foodItemCount: foodItems.count,
            foodLogCount: foodLogs.count,
            hydrationCount: hydrationEntries.count,
            sleepCount: sleepSessions.count,
            napCount: napSessions.count,
            coachRecordCount: coachCount,
            userContentCount: userContentCount,
            workoutTemplateCount: workoutTemplates?.count
        )
    }
}

@ModelActor
private actor FullAppBackupSnapshotActor {
    func makeData(templateStore: WorkoutTemplateStore) throws -> FullAppBackupDataDTO {
        try makeFullAppBackupData(
            in: modelContext,
            workoutTemplates: templateStore.loadTemplatesForBackup()
        )
    }
}

@MainActor
struct FullAppBackupService {
    private let appName = "Peakline"
    private let schemaVersion = 3
    private let defaults: UserDefaults
    private let templateStore: WorkoutTemplateStore
    private let beforeCommit: () throws -> Void

    init(
        defaults: UserDefaults = .standard,
        templateStore: WorkoutTemplateStore = WorkoutTemplateStore(),
        beforeCommit: @escaping () throws -> Void = {}
    ) {
        self.defaults = defaults
        self.templateStore = templateStore
        self.beforeCommit = beforeCommit
    }

    func makeEnvelope(in context: ModelContext) throws -> FullAppBackupEnvelope {
        FullAppBackupEnvelope(
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            appName: appName,
            appVersion: appVersion,
            preferences: FullAppPreferencesBackupDTO(defaults: defaults),
            data: try makeFullAppBackupData(
                in: context,
                workoutTemplates: templateStore.loadTemplatesForBackup()
            )
        )
    }

    /// Uses an actor-owned SwiftData context so a large snapshot does not block
    /// the app's main context while every relationship is converted to DTOs.
    func makeEnvelope(in modelContainer: ModelContainer) async throws -> FullAppBackupEnvelope {
        let exportedAt = Date()
        let version = appVersion
        let preferences = FullAppPreferencesBackupDTO(defaults: defaults)
        let snapshotActor = FullAppBackupSnapshotActor(modelContainer: modelContainer)
        let data = try await snapshotActor.makeData(templateStore: templateStore)
        return FullAppBackupEnvelope(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            appName: appName,
            appVersion: version,
            preferences: preferences,
            data: data
        )
    }

    func encode(_ envelope: FullAppBackupEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= FullAppBackupLimits.maxDecompressedPayloadBytes else {
            throw FullAppBackupError.payloadTooLarge
        }
        return data
    }

    func decodeEnvelope(from data: Data) throws -> FullAppBackupEnvelope {
        guard data.count <= FullAppBackupLimits.maxDecompressedPayloadBytes else {
            throw FullAppBackupError.payloadTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FullAppBackupEnvelope.self, from: data)
    }

    func importBackup(from data: Data, into context: ModelContext, replaceExisting: Bool) throws -> FullAppBackupImportSummary {
        let envelope = try decodeEnvelope(from: data)
        return try importBackup(envelope, into: context, replaceExisting: replaceExisting)
    }

    func importBackup(
        _ envelope: FullAppBackupEnvelope,
        into context: ModelContext,
        replaceExisting: Bool
    ) throws -> FullAppBackupImportSummary {
        try validate(envelope)
        try preflight(envelope)

        if !replaceExisting, try userContentCount(in: context) > 0 {
            throw FullAppBackupError.storeNotEmpty
        }

        // Establish a clean rollback boundary before applying the replacement.
        try context.save()
        let previousTemplates = try templateStore.loadTemplatesForBackup()
        var replacedTemplates = false

        do {
            if replaceExisting {
                try clearStore(in: context)
            }
            try restore(envelope.data, into: context)
            try TrainingRotationService().normalizePersistedRotation(in: context)

            if let workoutTemplates = envelope.data.workoutTemplates {
                try templateStore.replaceAll(with: workoutTemplates)
                replacedTemplates = true
            }

            try beforeCommit()
            try context.save()
            envelope.preferences.apply(to: defaults)
            return FullAppBackupImportSummary(counts: envelope.counts, importedAt: Date())
        } catch {
            context.rollback()
            if replacedTemplates {
                try? templateStore.replaceAll(with: previousTemplates)
            }
            throw error
        }
    }

    func userContentCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<WorkoutSession>())
            + context.fetchCount(FetchDescriptor<Recommendation>())
            + context.fetchCount(FetchDescriptor<BodyweightLog>())
            + context.fetchCount(FetchDescriptor<FoodItem>())
            + context.fetchCount(FetchDescriptor<FoodLogEntry>())
            + context.fetchCount(FetchDescriptor<HydrationEntry>())
            + context.fetchCount(FetchDescriptor<SleepSession>())
            + context.fetchCount(FetchDescriptor<NapSession>())
            + context.fetchCount(FetchDescriptor<DailyCoachCheckIn>())
            + context.fetchCount(FetchDescriptor<CoachPreferences>())
            + context.fetchCount(FetchDescriptor<CoachSplitMetadata>())
            + context.fetchCount(FetchDescriptor<CoachActionHistoryEntry>())
            + context.fetchCount(FetchDescriptor<SavedCoachDeloadBlock>())
            + context.fetchCount(FetchDescriptor<CoachExerciseMetadata>())
            + context.fetchCount(FetchDescriptor<CoachRecommendationFeedback>())
            + (templateStore.hasStoredTemplateData ? 1 : 0)
    }

    private var appVersion: String? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return nil
        }
    }

    private func clearStore(in context: ModelContext) throws {
        try deleteAll(SetLog.self, in: context)
        try deleteAll(ExerciseLog.self, in: context)
        try deleteAll(WorkoutSession.self, in: context)
        try deleteAll(SplitExercise.self, in: context)
        try deleteAll(TrainingSplit.self, in: context)
        try deleteAll(Exercise.self, in: context)
        try deleteAll(Recommendation.self, in: context)
        try deleteAll(BodyweightLog.self, in: context)
        try deleteAll(FoodLogEntry.self, in: context)
        try deleteAll(FoodItem.self, in: context)
        try deleteAll(HydrationEntry.self, in: context)
        try deleteAll(SleepSession.self, in: context)
        try deleteAll(NapSession.self, in: context)
        try deleteAll(DailyCoachCheckIn.self, in: context)
        try deleteAll(CoachActionHistoryEntry.self, in: context)
        try deleteAll(SavedCoachDeloadBlock.self, in: context)
        try deleteAll(CoachExerciseMetadata.self, in: context)
        try deleteAll(CoachRecommendationFeedback.self, in: context)
        try deleteAll(CoachPreferences.self, in: context)
        try deleteAll(CoachSplitMetadata.self, in: context)
        try deleteAll(UserProfile.self, in: context)
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }

    private func restore(_ data: FullAppBackupDataDTO, into context: ModelContext) throws {
        for dto in data.userProfiles { context.insert(dto.makeModel()) }
        for dto in data.exercises { context.insert(dto.makeModel()) }
        for dto in data.splits { context.insert(dto.makeModel()) }
        for dto in data.workouts { context.insert(dto.makeModel()) }
        for dto in data.recommendations { context.insert(dto.makeModel()) }
        for dto in data.bodyweightLogs { context.insert(dto.makeModel()) }
        for dto in data.foodItems { context.insert(dto.makeModel()) }
        for dto in data.foodLogs { context.insert(dto.makeModel()) }
        for dto in data.hydrationEntries { context.insert(dto.makeModel()) }
        for dto in data.sleepSessions { context.insert(dto.makeModel()) }
        for dto in data.napSessions { context.insert(dto.makeModel()) }
        for dto in data.dailyCoachCheckIns { context.insert(dto.makeModel()) }
        for dto in data.coachPreferences { context.insert(dto.makeModel()) }
        for dto in data.coachSplitMetadata { context.insert(dto.makeModel()) }
        for dto in data.coachActionHistory { context.insert(dto.makeModel()) }
        for dto in data.savedCoachDeloadBlocks { context.insert(dto.makeModel()) }
        for dto in data.coachExerciseMetadata { context.insert(dto.makeModel()) }
        for dto in data.coachRecommendationFeedback { context.insert(dto.makeModel()) }
    }

    func validate(_ envelope: FullAppBackupEnvelope) throws {
        guard envelope.appName == appName else {
            throw FullAppBackupError.wrongApplication(envelope.appName)
        }
        guard (2...schemaVersion).contains(envelope.schemaVersion) else {
            throw FullAppBackupError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        guard envelope.counts.totalRecordCount <= FullAppBackupLimits.maxRecordCount else {
            throw FullAppBackupError.recordLimitExceeded
        }

        let data = envelope.data
        try requireUnique(data.userProfiles.map(\.id), label: "user profile")
        try requireUnique(data.exercises.map(\.id), label: "exercise")
        try requireUnique(data.splits.map(\.id), label: "training split")
        try requireUnique(data.workouts.map(\.id), label: "workout")
        try requireUnique(data.recommendations.map(\.id), label: "recommendation")
        try requireUnique(data.bodyweightLogs.map(\.id), label: "bodyweight log")
        try requireUnique(data.foodItems.map(\.id), label: "food item")
        try requireUnique(data.foodLogs.map(\.id), label: "food log")
        try requireUnique(data.hydrationEntries.map(\.id), label: "hydration entry")
        try requireUnique(data.sleepSessions.map(\.id), label: "sleep session")
        try requireUnique(data.napSessions.map(\.id), label: "nap session")
        try requireUnique(data.dailyCoachCheckIns.map(\.id), label: "coach check-in")
        try requireUnique(data.coachPreferences.map(\.id), label: "coach preferences")
        try requireUnique(data.coachSplitMetadata.map(\.id), label: "coach split metadata")
        try requireUnique(data.coachActionHistory.map(\.id), label: "coach action history")
        try requireUnique(data.savedCoachDeloadBlocks.map(\.id), label: "coach deload block")
        try requireUnique(data.coachExerciseMetadata.map(\.id), label: "coach exercise metadata")
        try requireUnique(data.coachRecommendationFeedback.map(\.id), label: "coach feedback")

        let exerciseIDs = Set(data.exercises.map(\.id))
        let splitExerciseIDs = data.splits.flatMap(\.exercises).map(\.id)
        try requireUnique(splitExerciseIDs, label: "split exercise")
        for split in data.splits {
            for exercise in split.exercises {
                guard exercise.splitId == split.id else {
                    throw FullAppBackupError.invalidRelationship("Split exercise \(exercise.id) has the wrong parent split.")
                }
                guard exerciseIDs.contains(exercise.exerciseId) else {
                    throw FullAppBackupError.invalidRelationship("Split exercise \(exercise.id) references a missing exercise.")
                }
            }
        }

        let exerciseLogs = data.workouts.flatMap(\.exerciseLogs)
        try requireUnique(exerciseLogs.map(\.id), label: "exercise log")
        try requireUnique(exerciseLogs.flatMap(\.setLogs).map(\.id), label: "set log")
        for workout in data.workouts {
            for exerciseLog in workout.exerciseLogs {
                guard exerciseLog.workoutSessionId == workout.id else {
                    throw FullAppBackupError.invalidRelationship("Exercise log \(exerciseLog.id) has the wrong parent workout.")
                }
                guard exerciseIDs.contains(exerciseLog.exerciseId) else {
                    throw FullAppBackupError.invalidRelationship("Exercise log \(exerciseLog.id) references a missing exercise.")
                }
                for setLog in exerciseLog.setLogs where setLog.exerciseLogId != exerciseLog.id {
                    throw FullAppBackupError.invalidRelationship("Set log \(setLog.id) has the wrong parent exercise log.")
                }
            }
        }

        if let templates = data.workoutTemplates {
            try requireUnique(templates.map(\.id), label: "workout template")
            try requireUnique(templates.flatMap(\.exercises).map(\.id), label: "workout template exercise")
        }
    }

    private func preflight(_ envelope: FullAppBackupEnvelope) throws {
        let container = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try restore(envelope.data, into: context)
        try TrainingRotationService().normalizePersistedRotation(in: context)
        try context.save()

        let data = envelope.data
        guard try context.fetchCount(FetchDescriptor<UserProfile>()) == data.userProfiles.count,
              try context.fetchCount(FetchDescriptor<Exercise>()) == data.exercises.count,
              try context.fetchCount(FetchDescriptor<TrainingSplit>()) == data.splits.count,
              try context.fetchCount(FetchDescriptor<SplitExercise>()) == data.splits.flatMap(\.exercises).count,
              try context.fetchCount(FetchDescriptor<WorkoutSession>()) == data.workouts.count,
              try context.fetchCount(FetchDescriptor<ExerciseLog>()) == data.workouts.flatMap(\.exerciseLogs).count,
              try context.fetchCount(FetchDescriptor<SetLog>()) == data.workouts.flatMap(\.exerciseLogs).flatMap(\.setLogs).count,
              try context.fetchCount(FetchDescriptor<Recommendation>()) == data.recommendations.count,
              try context.fetchCount(FetchDescriptor<BodyweightLog>()) == data.bodyweightLogs.count,
              try context.fetchCount(FetchDescriptor<FoodItem>()) == data.foodItems.count,
              try context.fetchCount(FetchDescriptor<FoodLogEntry>()) == data.foodLogs.count,
              try context.fetchCount(FetchDescriptor<HydrationEntry>()) == data.hydrationEntries.count,
              try context.fetchCount(FetchDescriptor<SleepSession>()) == data.sleepSessions.count,
              try context.fetchCount(FetchDescriptor<NapSession>()) == data.napSessions.count,
              try context.fetchCount(FetchDescriptor<DailyCoachCheckIn>()) == data.dailyCoachCheckIns.count,
              try context.fetchCount(FetchDescriptor<CoachPreferences>()) == data.coachPreferences.count,
              try context.fetchCount(FetchDescriptor<CoachSplitMetadata>()) == data.coachSplitMetadata.count,
              try context.fetchCount(FetchDescriptor<CoachActionHistoryEntry>()) == data.coachActionHistory.count,
              try context.fetchCount(FetchDescriptor<SavedCoachDeloadBlock>()) == data.savedCoachDeloadBlocks.count,
              try context.fetchCount(FetchDescriptor<CoachExerciseMetadata>()) == data.coachExerciseMetadata.count,
              try context.fetchCount(FetchDescriptor<CoachRecommendationFeedback>()) == data.coachRecommendationFeedback.count else {
            throw FullAppBackupError.preflightCountMismatch
        }
    }

    private func requireUnique(_ identifiers: [UUID], label: String) throws {
        guard Set(identifiers).count == identifiers.count else {
            throw FullAppBackupError.duplicateIdentifier(label)
        }
    }
}

private func makeFullAppBackupData(
    in context: ModelContext,
    workoutTemplates: [CustomWorkoutTemplate]
) throws -> FullAppBackupDataDTO {
    FullAppBackupDataDTO(
        userProfiles: try context.fetch(FetchDescriptor<UserProfile>()).map(UserProfileBackupDTO.init),
        exercises: try context.fetch(FetchDescriptor<Exercise>()).map(ExerciseBackupDTO.init),
        splits: try context.fetch(FetchDescriptor<TrainingSplit>()).map(TrainingSplitBackupDTO.init),
        workouts: try context.fetch(FetchDescriptor<WorkoutSession>()).map(WorkoutSessionBackupDTO.init),
        recommendations: try context.fetch(FetchDescriptor<Recommendation>()).map(RecommendationBackupDTO.init),
        bodyweightLogs: try context.fetch(FetchDescriptor<BodyweightLog>()).map(BodyweightLogBackupDTO.init),
        foodItems: try context.fetch(FetchDescriptor<FoodItem>()).map(FoodItemBackupDTO.init),
        foodLogs: try context.fetch(FetchDescriptor<FoodLogEntry>()).map(FoodLogEntryBackupDTO.init),
        hydrationEntries: try context.fetch(FetchDescriptor<HydrationEntry>()).map(HydrationEntryBackupDTO.init),
        sleepSessions: try context.fetch(FetchDescriptor<SleepSession>()).map(SleepSessionBackupDTO.init),
        napSessions: try context.fetch(FetchDescriptor<NapSession>()).map(NapSessionBackupDTO.init),
        dailyCoachCheckIns: try context.fetch(FetchDescriptor<DailyCoachCheckIn>()).map(DailyCoachCheckInBackupDTO.init),
        coachPreferences: try context.fetch(FetchDescriptor<CoachPreferences>()).map(CoachPreferencesBackupDTO.init),
        coachSplitMetadata: try context.fetch(FetchDescriptor<CoachSplitMetadata>()).map(CoachSplitMetadataBackupDTO.init),
        coachActionHistory: try context.fetch(FetchDescriptor<CoachActionHistoryEntry>()).map(CoachActionHistoryEntryBackupDTO.init),
        savedCoachDeloadBlocks: try context.fetch(FetchDescriptor<SavedCoachDeloadBlock>()).map(SavedCoachDeloadBlockBackupDTO.init),
        coachExerciseMetadata: try context.fetch(FetchDescriptor<CoachExerciseMetadata>()).map(CoachExerciseMetadataBackupDTO.init),
        coachRecommendationFeedback: try context.fetch(FetchDescriptor<CoachRecommendationFeedback>()).map(CoachRecommendationFeedbackBackupDTO.init),
        workoutTemplates: workoutTemplates
    )
}

enum FullAppBackupError: LocalizedError, Equatable {
    case storeNotEmpty
    case wrongApplication(String)
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(String)
    case invalidRelationship(String)
    case preflightCountMismatch
    case payloadTooLarge
    case recordLimitExceeded

    var errorDescription: String? {
        switch self {
        case .storeNotEmpty:
            return "Current app data is not empty. Confirm a full restore before replacing it."
        case .wrongApplication(let name):
            return "This backup belongs to \(name), not Peakline."
        case .unsupportedSchemaVersion(let version):
            return "Backup schema version \(version) is not supported by this version of Peakline."
        case .duplicateIdentifier(let label):
            return "The backup contains a duplicate \(label) identifier."
        case .invalidRelationship(let message):
            return message
        case .preflightCountMismatch:
            return "The backup failed its restore preflight count check."
        case .payloadTooLarge:
            return "The backup payload is larger than Peakline's supported safety limit."
        case .recordLimitExceeded:
            return "The backup contains more records than Peakline will process in one operation."
        }
    }
}

private func backupValue<T: RawRepresentable>(_ rawValue: String, fallback: T) -> T where T.RawValue == String {
    T(rawValue: rawValue) ?? fallback
}

struct UserProfileBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var goal: TrainingGoal
    var experienceLevel: ExperienceLevel
    var liftingStartDate: Date?
    var trainingDaysPerWeek: Int
    var preferredSplitType: SplitType
    var bodyweight: Double?
    var unitSystem: UnitSystem
    var injuryNotes: String?
    var exercisesToAvoid: [String]
    var notificationsEnabled: Bool
    var dailyCheckInTime: Date?

    init(_ profile: UserProfile) {
        id = profile.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        goal = profile.goal
        experienceLevel = profile.experienceLevel
        liftingStartDate = profile.liftingStartDate
        trainingDaysPerWeek = profile.trainingDaysPerWeek
        preferredSplitType = profile.preferredSplitType
        bodyweight = profile.bodyweight
        unitSystem = profile.unitSystem
        injuryNotes = profile.injuryNotes
        exercisesToAvoid = profile.exercisesToAvoid
        notificationsEnabled = profile.notificationsEnabled
        dailyCheckInTime = profile.dailyCheckInTime
    }

    func makeModel() -> UserProfile {
        UserProfile(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            goal: goal,
            experienceLevel: experienceLevel,
            liftingStartDate: liftingStartDate,
            trainingDaysPerWeek: trainingDaysPerWeek,
            preferredSplitType: preferredSplitType,
            bodyweight: bodyweight,
            unitSystem: unitSystem,
            injuryNotes: injuryNotes,
            exercisesToAvoid: exercisesToAvoid,
            notificationsEnabled: notificationsEnabled,
            dailyCheckInTime: dailyCheckInTime
        )
    }
}

struct ExerciseBackupDTO: Codable {
    var id: UUID
    var name: String
    var primaryMuscleGroup: MuscleGroup
    var secondaryMuscleGroups: [MuscleGroup]
    var movementPattern: MovementPattern
    var equipment: EquipmentType
    var isCompound: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        primaryMuscleGroup = exercise.primaryMuscleGroup
        secondaryMuscleGroups = exercise.secondaryMuscleGroups
        movementPattern = exercise.movementPattern
        equipment = exercise.equipment
        isCompound = exercise.isCompound
        isArchived = exercise.isArchived
        createdAt = exercise.createdAt
        updatedAt = exercise.updatedAt
    }

    func makeModel() -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            movementPattern: movementPattern,
            equipment: equipment,
            isCompound: isCompound,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct TrainingSplitBackupDTO: Codable {
    var id: UUID
    var name: String
    var splitType: SplitType
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var activeRotationIndex: Int?
    var daysPerWeek: Int
    var exercises: [SplitExerciseBackupDTO]

    init(_ split: TrainingSplit) {
        id = split.id
        name = split.name
        splitType = split.splitType
        createdAt = split.createdAt
        updatedAt = split.updatedAt
        isActive = split.isActive
        activeRotationIndex = split.activeRotationIndex
        daysPerWeek = split.daysPerWeek
        exercises = split.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(SplitExerciseBackupDTO.init)
    }

    func makeModel() -> TrainingSplit {
        let split = TrainingSplit(
            id: id,
            name: name,
            splitType: splitType,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive,
            activeRotationIndex: activeRotationIndex,
            daysPerWeek: daysPerWeek
        )
        split.exercises = exercises.map { dto in
            let child = dto.makeModel(splitId: id)
            child.split = split
            return child
        }
        return split
    }
}

struct SplitExerciseBackupDTO: Codable {
    var id: UUID
    var splitId: UUID
    var exerciseId: UUID
    var exerciseNameSnapshot: String
    var orderIndex: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var restSeconds: Int?
    var notes: String?

    init(_ splitExercise: SplitExercise) {
        id = splitExercise.id
        splitId = splitExercise.splitId
        exerciseId = splitExercise.exerciseId
        exerciseNameSnapshot = splitExercise.exerciseNameSnapshot
        orderIndex = splitExercise.orderIndex
        targetSets = splitExercise.targetSets
        minReps = splitExercise.minReps
        maxReps = splitExercise.maxReps
        restSeconds = splitExercise.restSeconds
        notes = splitExercise.notes
    }

    func makeModel(splitId parentSplitId: UUID) -> SplitExercise {
        SplitExercise(
            id: id,
            splitId: parentSplitId,
            exerciseId: exerciseId,
            exerciseNameSnapshot: exerciseNameSnapshot,
            orderIndex: orderIndex,
            targetSets: targetSets,
            minReps: minReps,
            maxReps: maxReps,
            restSeconds: restSeconds,
            notes: notes
        )
    }
}

struct WorkoutSessionBackupDTO: Codable {
    var id: UUID
    var date: Date
    var splitId: UUID?
    var splitNameSnapshot: String
    var startedAt: Date?
    var endedAt: Date?
    var durationMinutes: Int?
    var durationSeconds: Int?
    var pausedAt: Date?
    var accumulatedPausedSeconds: Int
    var perceivedDifficulty: Int?
    var energyLevel: Int?
    var sorenessLevel: Int?
    var notes: String?
    var completed: Bool
    var exerciseLogs: [ExerciseLogBackupDTO]

    init(_ session: WorkoutSession) {
        id = session.id
        date = session.date
        splitId = session.splitId
        splitNameSnapshot = session.splitNameSnapshot
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationMinutes = session.durationMinutes
        durationSeconds = session.durationSeconds
        pausedAt = session.pausedAt
        accumulatedPausedSeconds = session.accumulatedPausedSeconds
        perceivedDifficulty = session.perceivedDifficulty
        energyLevel = session.energyLevel
        sorenessLevel = session.sorenessLevel
        notes = session.notes
        completed = session.completed
        exerciseLogs = session.exerciseLogs.sorted { $0.orderIndex < $1.orderIndex }.map(ExerciseLogBackupDTO.init)
    }

    func makeModel() -> WorkoutSession {
        let session = WorkoutSession(
            id: id,
            date: date,
            splitId: splitId,
            splitNameSnapshot: splitNameSnapshot,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMinutes: durationMinutes,
            durationSeconds: durationSeconds,
            pausedAt: pausedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            perceivedDifficulty: perceivedDifficulty,
            energyLevel: energyLevel,
            sorenessLevel: sorenessLevel,
            notes: notes,
            completed: completed
        )
        session.exerciseLogs = exerciseLogs.map { dto in
            let log = dto.makeModel(workoutSessionId: id)
            log.workoutSession = session
            return log
        }
        return session
    }
}

struct ExerciseLogBackupDTO: Codable {
    var id: UUID
    var workoutSessionId: UUID
    var exerciseId: UUID
    var exerciseNameSnapshot: String
    var orderIndex: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var notes: String?
    var setLogs: [SetLogBackupDTO]

    init(_ log: ExerciseLog) {
        id = log.id
        workoutSessionId = log.workoutSessionId
        exerciseId = log.exerciseId
        exerciseNameSnapshot = log.exerciseNameSnapshot
        orderIndex = log.orderIndex
        targetSets = log.targetSets
        minReps = log.minReps
        maxReps = log.maxReps
        notes = log.notes
        setLogs = log.setLogs.sorted { $0.setNumber < $1.setNumber }.map(SetLogBackupDTO.init)
    }

    func makeModel(workoutSessionId parentWorkoutSessionId: UUID) -> ExerciseLog {
        let log = ExerciseLog(
            id: id,
            workoutSessionId: parentWorkoutSessionId,
            exerciseId: exerciseId,
            exerciseNameSnapshot: exerciseNameSnapshot,
            orderIndex: orderIndex,
            targetSets: targetSets,
            minReps: minReps,
            maxReps: maxReps,
            notes: notes
        )
        log.setLogs = setLogs.map { dto in
            let set = dto.makeModel(exerciseLogId: id)
            set.exerciseLog = log
            return set
        }
        return log
    }
}

struct SetLogBackupDTO: Codable {
    var id: UUID
    var exerciseLogId: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
    var completed: Bool

    init(_ set: SetLog) {
        id = set.id
        exerciseLogId = set.exerciseLogId
        setNumber = set.setNumber
        weight = set.weight
        reps = set.reps
        rpe = set.rpe
        isWarmup = set.isWarmup
        completed = set.completed
    }

    func makeModel(exerciseLogId parentExerciseLogId: UUID) -> SetLog {
        SetLog(
            id: id,
            exerciseLogId: parentExerciseLogId,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            rpe: rpe,
            isWarmup: isWarmup,
            completed: completed
        )
    }
}

struct RecommendationBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var type: RecommendationType
    var splitId: UUID?
    var exerciseId: UUID?
    var title: String
    var message: String
    var reason: String
    var confidence: Double
    var dismissed: Bool

    init(_ recommendation: Recommendation) {
        id = recommendation.id
        createdAt = recommendation.createdAt
        type = recommendation.type
        splitId = recommendation.splitId
        exerciseId = recommendation.exerciseId
        title = recommendation.title
        message = recommendation.message
        reason = recommendation.reason
        confidence = recommendation.confidence
        dismissed = recommendation.dismissed
    }

    func makeModel() -> Recommendation {
        Recommendation(
            id: id,
            createdAt: createdAt,
            type: type,
            splitId: splitId,
            exerciseId: exerciseId,
            title: title,
            message: message,
            reason: reason,
            confidence: confidence,
            dismissed: dismissed
        )
    }
}

struct BodyweightLogBackupDTO: Codable {
    var id: UUID
    var date: Date
    var weight: Double
    var unit: UnitSystem
    var notes: String?

    init(_ log: BodyweightLog) {
        id = log.id
        date = log.date
        weight = log.weight
        unit = log.unit
        notes = log.notes
    }

    func makeModel() -> BodyweightLog {
        BodyweightLog(id: id, date: date, weight: weight, unit: unit, notes: notes)
    }
}

struct HydrationEntryBackupDTO: Codable {
    var id: UUID
    var amountML: Int
    var loggedAt: Date
    var source: HydrationEntrySource
    var context: HydrationEntryContext
    var linkedWorkoutID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ entry: HydrationEntry) {
        id = entry.id
        amountML = entry.amountML
        loggedAt = entry.loggedAt
        source = entry.source
        context = entry.context
        linkedWorkoutID = entry.linkedWorkoutID
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func makeModel() -> HydrationEntry {
        HydrationEntry(
            id: id,
            amountML: amountML,
            loggedAt: loggedAt,
            source: source,
            context: context,
            linkedWorkoutID: linkedWorkoutID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct FoodItemBackupDTO: Codable {
    var id: UUID
    var barcode: String?
    var name: String
    var brand: String?
    var servingSize: Double?
    var baseUnit: FoodAmountUnit
    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var sugarPer100g: Double?
    var fibrePer100g: Double?
    var saltPer100g: Double?
    var source: FoodDataSource
    var verificationStatus: FoodVerificationStatus
    var createdAt: Date
    var updatedAt: Date

    init(_ food: FoodItem) {
        id = food.id
        barcode = food.barcode
        name = food.name
        brand = food.brand
        servingSize = food.servingSize
        baseUnit = food.baseUnit
        caloriesPer100g = food.caloriesPer100g
        proteinPer100g = food.proteinPer100g
        carbsPer100g = food.carbsPer100g
        fatPer100g = food.fatPer100g
        sugarPer100g = food.sugarPer100g
        fibrePer100g = food.fibrePer100g
        saltPer100g = food.saltPer100g
        source = food.source
        verificationStatus = food.verificationStatus
        createdAt = food.createdAt
        updatedAt = food.updatedAt
    }

    func makeModel() -> FoodItem {
        FoodItem(
            id: id,
            barcode: barcode,
            name: name,
            brand: brand,
            servingSize: servingSize,
            baseUnit: baseUnit,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            sugarPer100g: sugarPer100g,
            fibrePer100g: fibrePer100g,
            saltPer100g: saltPer100g,
            source: source,
            verificationStatus: verificationStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct FoodLogEntryBackupDTO: Codable {
    var id: UUID
    var foodItemId: UUID
    var foodNameSnapshot: String
    var brandSnapshot: String?
    var consumedAmount: Double
    var amountUnit: FoodAmountUnit
    var mealType: MealType
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var sugarSnapshot: Double?
    var fibreSnapshot: Double?
    var saltSnapshot: Double?
    var loggedAt: Date
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(_ entry: FoodLogEntry) {
        id = entry.id
        foodItemId = entry.foodItemId
        foodNameSnapshot = entry.foodNameSnapshot
        brandSnapshot = entry.brandSnapshot
        consumedAmount = entry.consumedAmount
        amountUnit = entry.amountUnit
        mealType = entry.mealType
        caloriesSnapshot = entry.caloriesSnapshot
        proteinSnapshot = entry.proteinSnapshot
        carbsSnapshot = entry.carbsSnapshot
        fatSnapshot = entry.fatSnapshot
        sugarSnapshot = entry.sugarSnapshot
        fibreSnapshot = entry.fibreSnapshot
        saltSnapshot = entry.saltSnapshot
        loggedAt = entry.loggedAt
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func makeModel() -> FoodLogEntry {
        FoodLogEntry(
            id: id,
            foodItemId: foodItemId,
            foodNameSnapshot: foodNameSnapshot,
            brandSnapshot: brandSnapshot,
            consumedAmount: consumedAmount,
            amountUnit: amountUnit,
            mealType: mealType,
            caloriesSnapshot: caloriesSnapshot,
            proteinSnapshot: proteinSnapshot,
            carbsSnapshot: carbsSnapshot,
            fatSnapshot: fatSnapshot,
            sugarSnapshot: sugarSnapshot,
            fibreSnapshot: fibreSnapshot,
            saltSnapshot: saltSnapshot,
            loggedAt: loggedAt,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SleepSessionBackupDTO: Codable {
    var id: UUID
    var sleepModeStartedAt: Date?
    var windDownDurationMinutes: Int?
    var estimatedSleepStartAt: Date?
    var confirmedSleepStartAt: Date
    var wakeAt: Date
    var durationMinutes: Int
    var qualityRating: Int?
    var tagRawValues: [String]
    var notes: String?
    var source: SleepSource
    var confidence: SleepConfidence
    var status: SleepSessionStatus
    var healthKitSampleIds: [String]
    var morningReminderSentAt: Date?
    var unfinishedReminderSentAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(_ session: SleepSession) {
        id = session.id
        sleepModeStartedAt = session.sleepModeStartedAt
        windDownDurationMinutes = session.windDownDurationMinutes
        estimatedSleepStartAt = session.estimatedSleepStartAt
        confirmedSleepStartAt = session.confirmedSleepStartAt
        wakeAt = session.wakeAt
        durationMinutes = session.durationMinutes
        qualityRating = session.qualityRating
        tagRawValues = session.tagRawValues
        notes = session.notes
        source = session.source
        confidence = session.confidence
        status = session.status
        healthKitSampleIds = session.healthKitSampleIds
        morningReminderSentAt = session.morningReminderSentAt
        unfinishedReminderSentAt = session.unfinishedReminderSentAt
        createdAt = session.createdAt
        updatedAt = session.updatedAt
    }

    func makeModel() -> SleepSession {
        let session = SleepSession(
            id: id,
            sleepModeStartedAt: sleepModeStartedAt,
            windDownDurationMinutes: windDownDurationMinutes,
            estimatedSleepStartAt: estimatedSleepStartAt,
            confirmedSleepStartAt: confirmedSleepStartAt,
            wakeAt: wakeAt,
            durationMinutes: durationMinutes,
            qualityRating: qualityRating,
            tags: tagRawValues.compactMap(SleepTag.init(rawValue:)),
            notes: notes,
            source: source,
            confidence: confidence,
            status: status,
            healthKitSampleIds: healthKitSampleIds,
            morningReminderSentAt: morningReminderSentAt,
            unfinishedReminderSentAt: unfinishedReminderSentAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        session.tagRawValues = tagRawValues
        session.durationMinutes = durationMinutes
        return session
    }
}

struct NapSessionBackupDTO: Codable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var durationMinutes: Int
    var qualityRating: Int?
    var source: NapSource
    var timingCategory: NapTimingCategory
    var note: String?
    var healthKitSampleIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(_ nap: NapSession) {
        id = nap.id
        startDate = nap.startDate
        endDate = nap.endDate
        durationMinutes = nap.durationMinutes
        qualityRating = nap.qualityRating
        source = nap.source
        timingCategory = nap.timingCategory
        note = nap.note
        healthKitSampleIds = nap.healthKitSampleIds
        createdAt = nap.createdAt
        updatedAt = nap.updatedAt
    }

    func makeModel() -> NapSession {
        let nap = NapSession(
            id: id,
            startDate: startDate,
            endDate: endDate,
            qualityRating: qualityRating,
            source: source,
            timingCategory: timingCategory,
            note: note,
            healthKitSampleIds: healthKitSampleIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        nap.durationMinutes = durationMinutes
        return nap
    }
}

struct DailyCoachCheckInBackupDTO: Codable {
    var id: UUID
    var date: Date
    var energy: Int
    var soreness: Int
    var stress: Int
    var motivation: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(_ checkIn: DailyCoachCheckIn) {
        id = checkIn.id
        date = checkIn.date
        energy = checkIn.energy
        soreness = checkIn.soreness
        stress = checkIn.stress
        motivation = checkIn.motivation
        note = checkIn.note
        createdAt = checkIn.createdAt
        updatedAt = checkIn.updatedAt
    }

    func makeModel() -> DailyCoachCheckIn {
        let checkIn = DailyCoachCheckIn(
            id: id,
            date: date,
            energy: energy,
            soreness: soreness,
            stress: stress,
            motivation: motivation,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        checkIn.date = date
        checkIn.note = note
        return checkIn
    }
}

struct CoachPreferencesBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var aggressivenessRawValue: String
    var deloadWordingRawValue: String
    var detailLevelRawValue: String
    var trainingPriorityRawValue: String
    var reductionPreferenceRawValue: String
    var recommendationFrequencyRawValue: String
    var showDiagnostics: Bool

    init(_ preferences: CoachPreferences) {
        id = preferences.id
        createdAt = preferences.createdAt
        updatedAt = preferences.updatedAt
        aggressivenessRawValue = preferences.aggressivenessRawValue
        deloadWordingRawValue = preferences.deloadWordingRawValue
        detailLevelRawValue = preferences.detailLevelRawValue
        trainingPriorityRawValue = preferences.trainingPriorityRawValue
        reductionPreferenceRawValue = preferences.reductionPreferenceRawValue
        recommendationFrequencyRawValue = preferences.recommendationFrequencyRawValue
        showDiagnostics = preferences.showDiagnostics
    }

    func makeModel() -> CoachPreferences {
        let preferences = CoachPreferences(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            aggressiveness: backupValue(aggressivenessRawValue, fallback: CoachAggressiveness.balanced),
            deloadWording: backupValue(deloadWordingRawValue, fallback: CoachDeloadWording.gentle),
            detailLevel: backupValue(detailLevelRawValue, fallback: CoachDetailLevel.standard),
            trainingPriority: backupValue(trainingPriorityRawValue, fallback: CoachTrainingPriority.balanced),
            reductionPreference: backupValue(reductionPreferenceRawValue, fallback: CoachReductionPreference.protectPriorityLifts),
            recommendationFrequency: backupValue(recommendationFrequencyRawValue, fallback: CoachRecommendationFrequency.standard),
            showDiagnostics: showDiagnostics
        )
        preferences.aggressivenessRawValue = aggressivenessRawValue
        preferences.deloadWordingRawValue = deloadWordingRawValue
        preferences.detailLevelRawValue = detailLevelRawValue
        preferences.trainingPriorityRawValue = trainingPriorityRawValue
        preferences.reductionPreferenceRawValue = reductionPreferenceRawValue
        preferences.recommendationFrequencyRawValue = recommendationFrequencyRawValue
        preferences.updatedAt = updatedAt
        return preferences
    }
}

struct CoachSplitMetadataBackupDTO: Codable {
    var id: UUID
    var splitId: UUID
    var splitName: String
    var createdAt: Date
    var updatedAt: Date
    var priorityRawValue: String
    var plannedIntensityRawValue: String
    var primaryGoalRawValue: String
    var expectedFatigueRawValue: String
    var protectCompounds: Bool
    var accessoriesFlexible: Bool
    var preferredAdjustmentStyleRawValue: String
    var userNote: String?

    init(_ metadata: CoachSplitMetadata) {
        id = metadata.id
        splitId = metadata.splitId
        splitName = metadata.splitName
        createdAt = metadata.createdAt
        updatedAt = metadata.updatedAt
        priorityRawValue = metadata.priorityRawValue
        plannedIntensityRawValue = metadata.plannedIntensityRawValue
        primaryGoalRawValue = metadata.primaryGoalRawValue
        expectedFatigueRawValue = metadata.expectedFatigueRawValue
        protectCompounds = metadata.protectCompounds
        accessoriesFlexible = metadata.accessoriesFlexible
        preferredAdjustmentStyleRawValue = metadata.preferredAdjustmentStyleRawValue
        userNote = metadata.userNote
    }

    func makeModel() -> CoachSplitMetadata {
        let metadata = CoachSplitMetadata(
            id: id,
            splitId: splitId,
            splitName: splitName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            priority: backupValue(priorityRawValue, fallback: CoachSplitPriority.normal),
            plannedIntensity: backupValue(plannedIntensityRawValue, fallback: CoachPlannedIntensity.moderate),
            primaryGoal: backupValue(primaryGoalRawValue, fallback: CoachSplitGoal.hypertrophy),
            expectedFatigue: backupValue(expectedFatigueRawValue, fallback: CoachExpectedFatigue.moderate),
            protectCompounds: protectCompounds,
            accessoriesFlexible: accessoriesFlexible,
            preferredAdjustmentStyle: backupValue(preferredAdjustmentStyleRawValue, fallback: CoachPreferredAdjustmentStyle.protectMainLifts),
            userNote: userNote
        )
        metadata.priorityRawValue = priorityRawValue
        metadata.plannedIntensityRawValue = plannedIntensityRawValue
        metadata.primaryGoalRawValue = primaryGoalRawValue
        metadata.expectedFatigueRawValue = expectedFatigueRawValue
        metadata.preferredAdjustmentStyleRawValue = preferredAdjustmentStyleRawValue
        metadata.userNote = userNote
        metadata.updatedAt = updatedAt
        return metadata
    }
}

struct CoachActionHistoryEntryBackupDTO: Codable {
    var id: UUID
    var actionRawValue: String
    var outcomeRawValue: String
    var createdAt: Date
    var readinessCategoryRawValue: String
    var fatigueRiskRawValue: String
    var confidenceRawValue: String
    var shortReason: String
    var workoutName: String?
    var splitName: String?
    var beforeTotalSets: Int
    var afterTotalSets: Int
    var contributingSignals: [String]
    var diagnosticSummary: String?

    init(_ entry: CoachActionHistoryEntry) {
        id = entry.id
        actionRawValue = entry.actionRawValue
        outcomeRawValue = entry.outcomeRawValue
        createdAt = entry.createdAt
        readinessCategoryRawValue = entry.readinessCategoryRawValue
        fatigueRiskRawValue = entry.fatigueRiskRawValue
        confidenceRawValue = entry.confidenceRawValue
        shortReason = entry.shortReason
        workoutName = entry.workoutName
        splitName = entry.splitName
        beforeTotalSets = entry.beforeTotalSets
        afterTotalSets = entry.afterTotalSets
        contributingSignals = entry.contributingSignals
        diagnosticSummary = entry.diagnosticSummary
    }

    func makeModel() -> CoachActionHistoryEntry {
        let entry = CoachActionHistoryEntry(
            id: id,
            action: backupValue(actionRawValue, fallback: CoachWorkoutAdjustmentAction.keepPlan),
            outcome: backupValue(outcomeRawValue, fallback: CoachActionHistoryOutcome.cancelled),
            createdAt: createdAt,
            readinessCategory: backupValue(readinessCategoryRawValue, fallback: ReadinessCategory.ready),
            fatigueRiskLevel: backupValue(fatigueRiskRawValue, fallback: CoachFatigueRiskLevel.low),
            confidence: backupValue(confidenceRawValue, fallback: ReadinessConfidence.low),
            shortReason: shortReason,
            workoutName: workoutName,
            splitName: splitName,
            beforeTotalSets: beforeTotalSets,
            afterTotalSets: afterTotalSets,
            contributingSignals: contributingSignals,
            diagnosticSummary: diagnosticSummary
        )
        entry.actionRawValue = actionRawValue
        entry.outcomeRawValue = outcomeRawValue
        entry.readinessCategoryRawValue = readinessCategoryRawValue
        entry.fatigueRiskRawValue = fatigueRiskRawValue
        entry.confidenceRawValue = confidenceRawValue
        return entry
    }
}

struct SavedCoachDeloadBlockBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var startsAt: Date
    var endsAt: Date
    var durationRawValue: String
    var volumeReductionRawValue: String
    var focusRawValue: String
    var stateRawValue: String
    var reason: String
    var splitName: String?

    init(_ block: SavedCoachDeloadBlock) {
        id = block.id
        createdAt = block.createdAt
        updatedAt = block.updatedAt
        startsAt = block.startsAt
        endsAt = block.endsAt
        durationRawValue = block.durationRawValue
        volumeReductionRawValue = block.volumeReductionRawValue
        focusRawValue = block.focusRawValue
        stateRawValue = block.stateRawValue
        reason = block.reason
        splitName = block.splitName
    }

    func makeModel() -> SavedCoachDeloadBlock {
        let block = SavedCoachDeloadBlock(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startsAt: startsAt,
            endsAt: endsAt,
            duration: backupValue(durationRawValue, fallback: ManualDeloadDuration.fiveDays),
            volumeReduction: backupValue(volumeReductionRawValue, fallback: ManualDeloadVolumeReduction.twentyFivePercent),
            focus: backupValue(focusRawValue, fallback: ManualDeloadFocus.maintainFrequency),
            state: backupValue(stateRawValue, fallback: CoachDeloadBlockState.active),
            reason: reason,
            splitName: splitName
        )
        block.durationRawValue = durationRawValue
        block.volumeReductionRawValue = volumeReductionRawValue
        block.focusRawValue = focusRawValue
        block.stateRawValue = stateRawValue
        block.updatedAt = updatedAt
        return block
    }
}

struct CoachExerciseMetadataBackupDTO: Codable {
    var id: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date
    var roleRawValue: String
    var primaryMuscleGroupRawValue: String
    var secondaryMuscleGroupRawValues: [String]
    var movementPatternRawValue: String
    var splitClassificationRawValue: String
    var priorityRawValue: String
    var userNote: String?

    init(_ metadata: CoachExerciseMetadata) {
        id = metadata.id
        exerciseId = metadata.exerciseId
        createdAt = metadata.createdAt
        updatedAt = metadata.updatedAt
        roleRawValue = metadata.roleRawValue
        primaryMuscleGroupRawValue = metadata.primaryMuscleGroupRawValue
        secondaryMuscleGroupRawValues = metadata.secondaryMuscleGroupRawValues
        movementPatternRawValue = metadata.movementPatternRawValue
        splitClassificationRawValue = metadata.splitClassificationRawValue
        priorityRawValue = metadata.priorityRawValue
        userNote = metadata.userNote
    }

    func makeModel() -> CoachExerciseMetadata {
        let metadata = CoachExerciseMetadata(
            id: id,
            exerciseId: exerciseId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            role: backupValue(roleRawValue, fallback: CoachExerciseMetadataRole.compound),
            primaryMuscleGroup: backupValue(primaryMuscleGroupRawValue, fallback: MuscleGroup.other),
            secondaryMuscleGroups: secondaryMuscleGroupRawValues.map { backupValue($0, fallback: MuscleGroup.other) },
            movementPattern: backupValue(movementPatternRawValue, fallback: MovementPattern.other),
            splitClassification: backupValue(splitClassificationRawValue, fallback: CoachSplitClassification.unspecified),
            priority: backupValue(priorityRawValue, fallback: CoachExercisePriorityLevel.normal),
            userNote: userNote
        )
        metadata.roleRawValue = roleRawValue
        metadata.primaryMuscleGroupRawValue = primaryMuscleGroupRawValue
        metadata.secondaryMuscleGroupRawValues = secondaryMuscleGroupRawValues
        metadata.movementPatternRawValue = movementPatternRawValue
        metadata.splitClassificationRawValue = splitClassificationRawValue
        metadata.priorityRawValue = priorityRawValue
        metadata.userNote = userNote
        metadata.updatedAt = updatedAt
        return metadata
    }
}

struct CoachRecommendationFeedbackBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var historyEntryId: UUID?
    var actionRawValue: String?
    var feedbackRawValues: [String]
    var note: String?
    var splitName: String?
    var readinessCategoryRawValue: String?
    var fatigueRiskRawValue: String?
    var confidenceRawValue: String?

    init(_ feedback: CoachRecommendationFeedback) {
        id = feedback.id
        createdAt = feedback.createdAt
        historyEntryId = feedback.historyEntryId
        actionRawValue = feedback.actionRawValue
        feedbackRawValues = feedback.feedbackRawValues
        note = feedback.note
        splitName = feedback.splitName
        readinessCategoryRawValue = feedback.readinessCategoryRawValue
        fatigueRiskRawValue = feedback.fatigueRiskRawValue
        confidenceRawValue = feedback.confidenceRawValue
    }

    func makeModel() -> CoachRecommendationFeedback {
        let feedback = CoachRecommendationFeedback(
            id: id,
            createdAt: createdAt,
            historyEntryId: historyEntryId,
            action: actionRawValue.map { backupValue($0, fallback: CoachWorkoutAdjustmentAction.keepPlan) },
            tags: feedbackRawValues.compactMap(CoachRecommendationFeedbackTag.init(rawValue:)),
            note: note,
            splitName: splitName,
            readinessCategory: readinessCategoryRawValue.map { backupValue($0, fallback: ReadinessCategory.ready) },
            fatigueRiskLevel: fatigueRiskRawValue.map { backupValue($0, fallback: CoachFatigueRiskLevel.low) },
            confidence: confidenceRawValue.map { backupValue($0, fallback: ReadinessConfidence.low) }
        )
        feedback.actionRawValue = actionRawValue
        feedback.feedbackRawValues = feedbackRawValues
        feedback.note = note
        feedback.readinessCategoryRawValue = readinessCategoryRawValue
        feedback.fatigueRiskRawValue = fatigueRiskRawValue
        feedback.confidenceRawValue = confidenceRawValue
        return feedback
    }
}
