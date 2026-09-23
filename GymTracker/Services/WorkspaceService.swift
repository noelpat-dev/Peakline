import CryptoKit
import Foundation
import SwiftData

/// All operations use the caller's context on its owning actor. No model is
/// cached globally or carried across suspension points.
enum WorkspaceService {
    static func metadata(in context: ModelContext) throws -> LocalWorkspaceMetadata {
        let records = try context.fetch(FetchDescriptor<LocalWorkspaceMetadata>())
        guard records.count <= 1 else { throw WorkspaceError.duplicateWorkspace }
        if let existing = records.first { return existing }
        let metadata = LocalWorkspaceMetadata()
        // Unknown legacy provenance is personal, even for an exercise-only or
        // programme-only store. Never infer ownership from display names.
        metadata.initialized = try hasLegacyRecords(in: context)
        if metadata.initialized {
            metadata.bootstrapVersion = 1
            metadata.catalogueVersion = 1
        }
        context.insert(metadata)
        return metadata
    }

    static func provenance(_ metadata: LocalWorkspaceMetadata) throws -> CatalogueProvenance {
        guard let data = metadata.provenanceData else { return CatalogueProvenance() }
        return try JSONDecoder().decode(CatalogueProvenance.self, from: data)
    }

    static func setProvenance(_ value: CatalogueProvenance, on metadata: LocalWorkspaceMetadata) throws {
        metadata.provenanceData = try JSONEncoder().encode(value)
    }

    static func exerciseFingerprint(_ exercise: Exercise) -> String {
        let fields = [exercise.name, exercise.primaryMuscleGroup.rawValue,
                      exercise.secondaryMuscleGroups.map(\.rawValue).joined(separator: ","),
                      exercise.movementPattern.rawValue, exercise.equipment.rawValue,
                      String(exercise.isCompound), String(exercise.isArchived)]
        return SHA256.hash(data: Data(fields.joined(separator: "\u{1f}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func portableState(in context: ModelContext) throws -> WorkspacePortableState {
        let workspace = try metadata(in: context)
        return WorkspacePortableState(initialized: workspace.initialized,
                                      bootstrapVersion: workspace.bootstrapVersion,
                                      catalogueVersion: workspace.catalogueVersion,
                                      provenance: try provenance(workspace))
    }

    static func applyPortableState(_ state: WorkspacePortableState?, in context: ModelContext) throws {
        let workspace = try metadata(in: context)
        // Restored legacy archives are initialized too. Missing provenance must
        // never trigger a new catalogue or template over the imported records.
        workspace.initialized = true
        workspace.bootstrapVersion = max(1, state?.bootstrapVersion ?? 1)
        workspace.catalogueVersion = max(1, state?.catalogueVersion ?? 1)
        try setProvenance(state?.provenance ?? CatalogueProvenance(), on: workspace)
        workspace.backupProjectID = nil
        workspace.backupUID = nil
        workspace.lastBoundProjectID = nil
        workspace.lastBoundUID = nil
        workspace.lastRemoteGenerationID = nil
        workspace.lastBackupFingerprint = nil
        workspace.backupState = "localOnly"
        workspace.backupError = nil
        workspace.operationGeneration &+= 1
        workspace.revision &+= 1
    }

    static func operationContext(in context: ModelContext, projectID: String, uid: String) throws -> WorkspaceOperationContext {
        let workspace = try metadata(in: context)
        guard workspace.backupProjectID == projectID, workspace.backupUID == uid else {
            throw WorkspaceError.backupNotConnected
        }
        return WorkspaceOperationContext(workspaceID: workspace.id, projectID: projectID,
                                         uid: uid, generation: workspace.operationGeneration)
    }

    static func isCurrent(_ operation: WorkspaceOperationContext, in context: ModelContext) throws -> Bool {
        let workspace = try metadata(in: context)
        return workspace.id == operation.workspaceID
            && workspace.operationGeneration == operation.generation
            && workspace.backupProjectID == operation.projectID && workspace.backupUID == operation.uid
    }

    static func invalidateOperations(in context: ModelContext) throws {
        let workspace = try metadata(in: context)
        workspace.operationGeneration &+= 1
        try context.save()
    }

    static func bindBackup(projectID: String, uid: String, in context: ModelContext) throws {
        let workspace = try metadata(in: context)
        guard !projectID.isEmpty, !uid.isEmpty else { throw WorkspaceError.backupNotConnected }
        if let previous = workspace.lastBoundUID,
           previous != uid || workspace.lastBoundProjectID != projectID {
            throw WorkspaceError.differentAccount
        }
        workspace.backupProjectID = projectID
        workspace.backupUID = uid
        workspace.lastBoundProjectID = projectID
        workspace.lastBoundUID = uid
        workspace.operationGeneration &+= 1
        workspace.backupState = "connected"
        try context.save()
    }

    static func disconnectBackup(in context: ModelContext) throws {
        let workspace = try metadata(in: context)
        workspace.operationGeneration &+= 1
        workspace.backupProjectID = nil
        workspace.backupUID = nil
        workspace.backupState = "localOnly"
        workspace.backupError = nil
        try context.save()
    }

    static func meaningfulContent(
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        templateStore: WorkoutTemplateStore = WorkoutTemplateStore()
    ) throws -> WorkspaceContentSummary {
        let workspace = try metadata(in: context)
        let reference = try provenance(workspace)
        let fingerprints = Dictionary(reference.exercises.values.map { ($0.recordID, $0.initialFingerprint) }, uniquingKeysWith: { first, _ in first })
        let personalExercises = try context.fetch(FetchDescriptor<Exercise>()).filter {
            fingerprints[$0.id] != exerciseFingerprint($0)
        }.count
        var categories: [String: Int] = [
            "programmes": try context.fetchCount(FetchDescriptor<TrainingSplit>()),
            "personal exercises": personalExercises,
            "profiles": try context.fetchCount(FetchDescriptor<UserProfile>()),
            "workouts": try context.fetchCount(FetchDescriptor<WorkoutSession>()),
            "recommendations": try context.fetchCount(FetchDescriptor<Recommendation>()),
            "bodyweight entries": try context.fetchCount(FetchDescriptor<BodyweightLog>()),
            "saved foods": try context.fetchCount(FetchDescriptor<FoodItem>()),
            "food logs": try context.fetchCount(FetchDescriptor<FoodLogEntry>()),
            "hydration entries": try context.fetchCount(FetchDescriptor<HydrationEntry>()),
            "sleep records": try context.fetchCount(FetchDescriptor<SleepSession>()),
            "naps": try context.fetchCount(FetchDescriptor<NapSession>()),
            "check-ins": try context.fetchCount(FetchDescriptor<DailyCoachCheckIn>()),
            "coach preferences": try context.fetchCount(FetchDescriptor<CoachPreferences>()),
            "coach split settings": try context.fetchCount(FetchDescriptor<CoachSplitMetadata>()),
            "coach actions": try context.fetchCount(FetchDescriptor<CoachActionHistoryEntry>()),
            "deload plans": try context.fetchCount(FetchDescriptor<SavedCoachDeloadBlock>()),
            "coach exercise settings": try context.fetchCount(FetchDescriptor<CoachExerciseMetadata>()),
            "coach feedback": try context.fetchCount(FetchDescriptor<CoachRecommendationFeedback>())
        ]
        // File presence is deliberately conservative: decoding failure is never
        // evidence that the workspace is empty.
        categories["template files"] = templateStore.hasStoredTemplateData ? 1 : 0
        let keys = ["appTheme", "appAppearance", "sleep.settings.v1", "nutrition.goal.v1", "hydration.dailyTargetML.v1"]
        categories["preferences"] = keys.filter { defaults.object(forKey: $0) != nil }.count
        return WorkspaceContentSummary(categories: categories)
    }

    private static func hasLegacyRecords(in context: ModelContext) throws -> Bool {
        // All V1 entities are retained, including stores that contain no workouts.
        try context.fetchCount(FetchDescriptor<UserProfile>()) > 0
            || context.fetchCount(FetchDescriptor<Exercise>()) > 0
            || context.fetchCount(FetchDescriptor<TrainingSplit>()) > 0
            || context.fetchCount(FetchDescriptor<WorkoutSession>()) > 0
            || context.fetchCount(FetchDescriptor<FoodItem>()) > 0
            || context.fetchCount(FetchDescriptor<FoodLogEntry>()) > 0
            || context.fetchCount(FetchDescriptor<HydrationEntry>()) > 0
            || context.fetchCount(FetchDescriptor<SleepSession>()) > 0
            || context.fetchCount(FetchDescriptor<NapSession>()) > 0
            || context.fetchCount(FetchDescriptor<BodyweightLog>()) > 0
            || context.fetchCount(FetchDescriptor<DailyCoachCheckIn>()) > 0
    }
}
