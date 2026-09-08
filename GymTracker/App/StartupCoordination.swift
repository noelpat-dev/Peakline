import SwiftData
import SwiftUI
import UIKit

enum StartupPresentationState: Equatable {
    case animating
    case waitingForAnimation
    case waitingForCriticalReady
    case holdingSlow
    case holdingSlowForAnimation
    case holdingSlowForCriticalReady
    case revealing
    case hidden
    case interrupted
}

enum StartupPresentationEvent {
    case start
    case animationFinished
    case slowThresholdReached
    case criticalReady
    case interrupted
    case revealFinished
    case resumeAfterInteraction
}

enum StartupPresentationReducer {
    static func reduce(
        _ state: StartupPresentationState,
        event: StartupPresentationEvent
    ) -> StartupPresentationState {
        switch event {
        case .start:
            // Startup is one-shot. Interaction retries resume with a settled
            // presentation instead of replaying the cold launch animation.
            return state == .hidden ? .hidden : state
        case .animationFinished:
            switch state {
            case .animating:
                return .waitingForCriticalReady
            case .waitingForAnimation, .holdingSlowForAnimation:
                return .revealing
            case .holdingSlow:
                return .holdingSlowForCriticalReady
            case .holdingSlowForCriticalReady, .waitingForCriticalReady,
                 .revealing, .hidden, .interrupted:
                return state
            }
        case .slowThresholdReached:
            switch state {
            case .animating, .waitingForCriticalReady:
                return state == .animating ? .holdingSlow : .holdingSlowForCriticalReady
            case .waitingForAnimation:
                return .holdingSlowForAnimation
            case .holdingSlow, .holdingSlowForAnimation, .holdingSlowForCriticalReady,
                 .revealing, .hidden, .interrupted:
                return state
            }
        case .criticalReady:
            switch state {
            case .animating:
                return .waitingForAnimation
            case .waitingForCriticalReady, .holdingSlowForCriticalReady:
                return .revealing
            case .holdingSlow:
                return .holdingSlowForAnimation
            case .waitingForAnimation, .holdingSlowForAnimation,
                 .revealing, .hidden, .interrupted:
                return state
            }
        case .interrupted:
            return state == .hidden ? .hidden : .interrupted
        case .revealFinished:
            return state == .revealing ? .hidden : state
        case .resumeAfterInteraction:
            return state == .hidden ? .hidden : .holdingSlow
        }
    }
}

struct StartupPresentationTiming {
    let maximumAnimationDuration: TimeInterval
    let revealDuration: TimeInterval

    static var current: StartupPresentationTiming {
        #if DEBUG
        let maximumMilliseconds = ProcessInfo.processInfo.integerArgument(
            named: "-UITestStartupAnimationMaxMS"
        )
        let maximumDuration = maximumMilliseconds.map { TimeInterval($0) / 1_000 } ?? 5
        #else
        let maximumDuration: TimeInterval = 5
        #endif

        return StartupPresentationTiming(
            maximumAnimationDuration: max(0.05, maximumDuration),
            revealDuration: 0.28
        )
    }
}

private extension ProcessInfo {
    func integerArgument(named name: String) -> Int? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return Int(arguments[index + 1])
    }
}

@MainActor
final class StartupPresentationCoordinator: ObservableObject {
    @Published private(set) var state: StartupPresentationState = .animating

    private var slowThresholdTask: Task<Void, Never>?
    private var didStart = false

    var isOverlayMounted: Bool {
        switch state {
        case .animating, .waitingForAnimation, .waitingForCriticalReady,
             .holdingSlow, .holdingSlowForAnimation, .holdingSlowForCriticalReady,
             .revealing:
            return true
        case .hidden, .interrupted:
            return false
        }
    }

    var animatesWordmark: Bool {
        state == .animating || state == .waitingForAnimation
    }

    var showsSlowProgress: Bool {
        state == .holdingSlow
            || state == .holdingSlowForAnimation
            || state == .holdingSlowForCriticalReady
    }

    var isRevealing: Bool {
        state == .revealing
    }

    var isRevealComplete: Bool {
        state == .hidden
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        transition(.start)

        let maximumDuration = StartupPresentationTiming.current.maximumAnimationDuration
        PerformanceTracer.mark(
            .startupPresentationStart,
            "maximum=\(Int(maximumDuration * 1_000))ms"
        )
        // The ceiling only exposes truthful slow-progress state. The splash
        // completes through its animation callback or an explicit settle.
        slowThresholdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(maximumDuration))
            guard !Task.isCancelled, let self else { return }
            guard self.state == .animating
                    || self.state == .waitingForAnimation
                    || self.state == .waitingForCriticalReady else { return }
            self.transition(.slowThresholdReached)
            PerformanceTracer.mark(.startupPresentationSlow, "animation_settled")
        }
    }

    func markCriticalReady() {
        transition(.criticalReady)
    }

    func markAnimationFinished() {
        transition(.animationFinished)
    }

    func finishReveal() {
        guard state == .revealing else { return }
        transition(.revealFinished)
        PerformanceTracer.mark(.startupRevealEnd, "root_interactive")
    }

    func interrupt(reason: String) {
        guard state != .hidden && state != .interrupted else { return }
        slowThresholdTask?.cancel()
        transition(.interrupted)
        PerformanceTracer.mark(.startupRevealEnd, "interrupted=\(reason)")
    }

    func resumeAfterInteraction() {
        slowThresholdTask?.cancel()
        transition(.resumeAfterInteraction)
        PerformanceTracer.mark(.startupPresentationSlow, "resumed_static")
    }

    private func transition(_ event: StartupPresentationEvent) {
        let previousState = state
        let wasSlow = showsSlowProgress
        state = StartupPresentationReducer.reduce(state, event: event)

        guard previousState != .revealing, state == .revealing else { return }
        slowThresholdTask?.cancel()
        let route = wasSlow ? "ready_after_5s" : "ready_before_5s"
        PerformanceTracer.mark(.startupRevealStart, route)
    }
}

enum AppStartupPreferences {
    private static let localOnlyBackupBypassKey = "PeaklineStartup.localOnlyBackupBypassEnabled"

    static var localOnlyBackupBypassEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: localOnlyBackupBypassKey) }
        set { UserDefaults.standard.set(newValue, forKey: localOnlyBackupBypassKey) }
    }
}

enum AppStartupPhase {
    case branding
    case checkingAccount
    case accountRequired(AccountReadiness)
    case checkingBackup
    case restorePrompt(FullAppBackupMetadata)
    case preparingLocalData
    case warmingScreens
    case ready(StartupSnapshotBundle)
    case recoverableFailure(String, canContinueOffline: Bool)
}

struct OverallReadinessPresentationSnapshot: Equatable, Sendable {
    let isProvisional: Bool
    let sourceSignature: String
    let revision: Int
    let generatedAt: Date

    static let empty = OverallReadinessPresentationSnapshot(
        isProvisional: true,
        sourceSignature: "",
        revision: 0,
        generatedAt: .distantPast
    )
}

@MainActor
final class OverallReadinessSnapshotStore: ObservableObject {
    static let shared = OverallReadinessSnapshotStore()

    @Published private(set) var snapshot = OverallReadinessPresentationSnapshot.empty
    /// The newest readiness score this store published. Kept outside the
    /// Equatable presentation snapshot because route destinations need the
    /// full score to seed a first frame before their own refresh runs.
    private(set) var latestReadiness: ReadinessScore?

    private init() {}

    func update(readiness: ReadinessScore, sourceSignature: String) {
        latestReadiness = readiness
        guard snapshot.sourceSignature != sourceSignature
                || snapshot.isProvisional != readiness.isProvisional else { return }

        snapshot = OverallReadinessPresentationSnapshot(
            isProvisional: readiness.isProvisional,
            sourceSignature: sourceSignature,
            revision: snapshot.revision &+ 1,
            generatedAt: readiness.generatedAt
        )
    }

    func readiness(matching sourceSignature: String) -> ReadinessScore? {
        guard snapshot.sourceSignature == sourceSignature else { return nil }
        return latestReadiness
    }
}

/// Resolves the freshest pre-computed route seed for destinations that would
/// otherwise render a launch-time value. Warm stores are kept current by the
/// root while the app runs, so a navigation push starts from data that
/// already matches live inputs.
@MainActor
enum WarmRouteSnapshots {
    static func sleepAnalytics(
        matching signature: SleepAnalyticsInputSignature,
        fallback: SleepAnalyticsSnapshot?
    ) -> SleepAnalyticsSnapshot? {
        if let cached = SleepAnalyticsSnapshotStore.shared.cachedAnalytics(matching: signature) {
            return cached.snapshot
        }
        guard fallback?.inputSignature == signature else { return nil }
        return fallback
    }

    static func overallReadiness(
        matching sourceSignature: String? = nil,
        fallback: ReadinessScore?
    ) -> ReadinessScore {
        let cached = sourceSignature.flatMap {
            OverallReadinessSnapshotStore.shared.readiness(matching: $0)
        } ?? (sourceSignature == nil ? OverallReadinessSnapshotStore.shared.latestReadiness : nil)
        return cached
            ?? fallback
            ?? CoachIntelligenceService.emptySnapshot().readiness
    }
}

extension TrainingCallSnapshot {
    func neutralizedForProvisionalReadiness(if isProvisional: Bool) -> TrainingCallSnapshot {
        guard isProvisional else { return self }

        return TrainingCallSnapshot(
            recommendedSplitName: recommendedSplitName,
            recommendedMode: .full,
            action: .repeatTarget,
            title: "Readiness is still settling",
            reason: "Daily readiness is provisional. Use planned targets and warm-ups while Peakline gathers enough evidence; no push or recovery prescription is available yet.",
            confidence: .low,
            targetSummary: nil,
            sourceSignals: [
                "The active programme rotation is available.",
                "Daily readiness is still being verified."
            ],
            missingOrStaleInputs: Array(
                (missingOrStaleInputs + ["Overall readiness is provisional."]).prefix(4)
            ),
            guardrailNotes: [
                "Provisional readiness blocks Push, Recovery, deload, and lighter-training prescriptions."
            ],
            isConservative: true
        )
    }
}

struct WorkoutSleepReadinessSnapshot {
    let hasPrimarySession: Bool
    let sleepScore: Int?
    let recoveryState: RecoveryState
    let adaptiveRecommendation: AdaptiveTrainingRecommendation?

    init(
        hasPrimarySession: Bool,
        sleepScore: Int?,
        recoveryState: RecoveryState,
        adaptiveRecommendation: AdaptiveTrainingRecommendation?
    ) {
        self.hasPrimarySession = hasPrimarySession
        self.sleepScore = sleepScore
        self.recoveryState = recoveryState
        self.adaptiveRecommendation = adaptiveRecommendation
    }

    static let empty = WorkoutSleepReadinessSnapshot(
        hasPrimarySession: false,
        sleepScore: nil,
        recoveryState: .unknown,
        adaptiveRecommendation: nil
    )

    init(_ snapshot: SleepWorkoutReadinessSnapshot) {
        hasPrimarySession = snapshot.latestSummary.primarySession != nil
        sleepScore = snapshot.latestSummary.sleepScore
        recoveryState = snapshot.latestSummary.recoveryState
        adaptiveRecommendation = snapshot.adaptiveRecommendation
    }
}

/// Value-only identifiers and settings needed to rebuild the sleep warm
/// snapshots after startup's detached preparation has completed. Keeping this
/// seed instead of the model-backed analytics structs prevents SwiftData
/// objects from being retained across the await in `prepareLocalData`.
struct StartupSleepSnapshotSeed: Sendable {
    let sessionIDs: [UUID]
    let analyticsNapIDs: [UUID]
    let readinessNapIDs: [UUID]
    let analyticsWorkoutIDs: [UUID]
    let readinessWorkoutIDs: [UUID]
    let settings: SleepSettings
    let workoutRevision: Int
}

@MainActor
struct StartupSleepSnapshots {
    let analytics: SleepAnalyticsSnapshot
    let readiness: SleepWorkoutReadinessSnapshot
    let readinessInputSignature: SleepAnalyticsInputSignature
}

struct StartupSnapshotBundle {
    let preparedAt: Date
    let sourceSignature: String
    let trainingCall: TrainingCallSnapshot
    let coachSnapshot: CoachIntelligenceSnapshot
    /// Value-only inputs used to produce `coachSnapshot.readiness`. Root can
    /// reuse that startup value only when its live inputs still produce this
    /// exact signature after the splash has finished.
    let overallReadinessInputSignature: String
    let coachRouteSnapshot: CoachRouteRenderSnapshot
    let sleepAnalyticsSnapshot: SleepAnalyticsSnapshot
    let sleepReadinessSnapshot: SleepWorkoutReadinessSnapshot
    let workoutSleepReadinessSnapshot: WorkoutSleepReadinessSnapshot
    let sleepReadinessInputSignature: SleepAnalyticsInputSignature
    let workoutFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot
    let historySnapshot: HistoryWarmSnapshot
    let previewWarmSnapshots: [WorkoutPreviewWarmSnapshot]
    let savedFoodCatalogSnapshot: SavedFoodCatalogSnapshot
    let progressWarmStartPayload: ProgressWarmStartPayload
    let nutritionDashboardWarmStartPayload: NutritionDashboardWarmStartPayload
    let nutritionInsightsWarmStartPayload: NutritionInsightsWarmStartPayload
    let settingsProfileSnapshot: SettingsProfileSnapshot?
    let activeSplitCount: Int
    let completedWorkoutCount: Int
    let unfinishedWorkoutCount: Int
    let historyRowWarmCount: Int
}

enum OverallReadinessInputSignature {
    static func make(
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        completedWorkouts: [WorkoutSession],
        hydrationEntries: [HydrationEntry],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        workoutRevision: Int,
        dayStart: Date,
        hydrationPhase: HydrationPacingPhase
    ) -> String {
        [
            sleepSessions.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.sorted().joined(separator: ","),
            napSessions.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.sorted().joined(separator: ","),
            completedWorkouts.map {
                "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0):\($0.durationSeconds ?? 0)"
            }.sorted().joined(separator: ","),
            hydrationEntries.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.sorted().joined(separator: ","),
            foodLogs.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.sorted().joined(separator: ","),
            checkIns.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.sorted().joined(separator: ","),
            "sleep:\(sleepSettings.targetSleepMinutes):\(sleepSettings.recoveryCoachingEnabled):\(sleepSettings.preferredSource.rawValue)",
            "hydrationTarget:\(hydrationTargetML)",
            "nutrition:\(nutritionGoal.isEnabled):\(nutritionGoal.dailyCaloriesTarget ?? 0):\(nutritionGoal.dailyProteinTarget ?? 0):\(nutritionGoal.dailyCarbsTarget ?? 0):\(nutritionGoal.dailyFatTarget ?? 0):\(nutritionGoal.dailyFibreTarget ?? 0):\(nutritionGoal.trainingDayCaloriesTarget ?? 0):\(nutritionGoal.restDayCaloriesTarget ?? 0):\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            "workoutRevision:\(workoutRevision)",
            "dayStart:\(dayStart.timeIntervalSince1970)",
            "hydrationPhase:\(hydrationPhase.rawValue)"
        ].joined(separator: "|")
    }
}

@MainActor
final class AppStartupCoordinator: ObservableObject {
    @Published private(set) var phase: AppStartupPhase = .branding
    @Published private(set) var stageText = "Preparing your training"
    @Published var restoreError: String?

    private let accountService = FirebaseAccountService()
    private let backupCoordinator = BackupCoordinator()
    private var hasStarted = false

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    func start(in context: ModelContext) async {
        guard !hasStarted else {
            PerformanceTracer.mark(.startupCriticalReady, "skip duplicate_start")
            return
        }
        hasStarted = true

        #if DEBUG
        if let delay = ProcessInfo.processInfo.integerArgument(
            named: "-UITestStartupPreparationDelayMS"
        ) {
            try? await Task.sleep(for: .milliseconds(delay))
        }
        #endif

        await evaluateAccountAndRestore(in: context)
    }

    func retry(in context: ModelContext) async {
        restoreError = nil
        await evaluateAccountAndRestore(in: context)
    }

    func continueWithoutBackup(in context: ModelContext) async {
        AppStartupPreferences.localOnlyBackupBypassEnabled = true
        await prepareLocalData(in: context, forceDateRepair: false)
    }

    func continueOfflineAfterFailure(in context: ModelContext) async {
        await prepareLocalData(in: context, forceDateRepair: false)
    }

    func skipRestore(in context: ModelContext) async {
        restoreError = nil
        await prepareLocalData(in: context, forceDateRepair: false)
    }

    func restoreBackup(in context: ModelContext, passphrase: String) async {
        restoreError = nil

        switch await backupCoordinator.restoreLatestBackup(
            in: context,
            replaceExisting: true,
            passphrase: passphrase
        ) {
        case .restored:
            await prepareLocalData(in: context, forceDateRepair: true)
        case .skippedNoBackup:
            phase = .recoverableFailure("No cloud backup was found.", canContinueOffline: true)
        case .skippedStoreNotEmpty:
            phase = .recoverableFailure(
                "Current local data is not empty. Use Settings to restore manually.",
                canContinueOffline: true
            )
        case .passphraseRequired:
            restoreError = "Enter the backup passphrase you used when saving this backup."
        case .unavailable(let message), .failed(let message):
            restoreError = message
        }
    }

    private func evaluateAccountAndRestore(in context: ModelContext) async {
        stageText = "Checking your local data"
        phase = .checkingAccount

        let canPromptRestore: Bool
        do {
            canPromptRestore = try backupCoordinator.canPromptRestore(in: context)
        } catch {
            phase = .recoverableFailure(error.localizedDescription, canContinueOffline: false)
            return
        }

#if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
                && !ProcessInfo.processInfo.arguments.contains("-SkipAccountGate") else {
            await prepareLocalData(in: context, forceDateRepair: false)
            return
        }
#endif

        // A populated local store is always usable without a cloud account. Account
        // readiness only matters when an empty install can offer a cloud restore.
        guard canPromptRestore else {
            await prepareLocalData(in: context, forceDateRepair: false)
            return
        }

        let readiness = await PerformanceTracer.traceAsync(.startupAccountCheck) {
            await accountService.readiness()
        }

        if case .firebaseNotConfigured = readiness,
           AppStartupPreferences.localOnlyBackupBypassEnabled {
            await prepareLocalData(in: context, forceDateRepair: false)
            return
        }

        guard readiness.isReady else {
            phase = .accountRequired(readiness)
            return
        }

        stageText = "Checking for a saved backup"
        phase = .checkingBackup
        let metadataOutcome = await PerformanceTracer.traceAsync(.startupBackupMetadata) {
            await backupCoordinator.latestMetadata()
        }

        switch metadataOutcome {
        case .available(let metadata) where metadata.counts.userContentCount > 0:
            phase = .restorePrompt(metadata)
        case .available, .noBackup:
            await prepareLocalData(in: context, forceDateRepair: false)
        case .unavailable(let message), .failed(let message):
            phase = .recoverableFailure(message, canContinueOffline: true)
        }
    }

    private func prepareLocalData(in context: ModelContext, forceDateRepair: Bool) async {
        phase = .preparingLocalData
        stageText = "Preparing your programme"
        await Task.yield()

        do {
            let projections = try PerformanceTracer.trace(.startupLocalPreparation) {
                SeedDataService.seedIfNeeded(in: context)
                try AppStartupMigrationService.repairWorkoutDatesIfNeeded(
                    in: context,
                    force: forceDateRepair
                )

                phase = .warmingScreens
                stageText = "Preparing your dashboards"
                return try StartupSnapshotBuilder.materialize(
                    in: context,
                    deferSleepSnapshots: true
                )
            }
            let derived = await PerformanceTracer.traceAsync(.startupSnapshotPreparation) {
                await StartupSnapshotBuilder.makePure(from: projections.pureProjection)
            }
            let sleepSnapshots = try StartupSnapshotBuilder.makeSleepSnapshots(
                from: projections.sleepSnapshotSeed,
                in: context
            )
            let snapshot = StartupSnapshotBuilder.makeBundle(
                from: projections,
                sleepSnapshots: sleepSnapshots,
                derived: derived
            )

            WorkoutDashboardWarmStartStore.shared.update(
                trainingCall: snapshot.trainingCall,
                sourceSignature: snapshot.sourceSignature
            )
            CoachRouteSnapshotStore.shared.update(
                snapshot: snapshot.coachRouteSnapshot,
                signature: snapshot.sourceSignature,
                source: "startup"
            )
            WorkoutPreviewWarmStartStore.shared.replaceActiveSnapshots(
                snapshot.previewWarmSnapshots
            )
            SavedFoodWarmStartStore.shared.update(snapshot.savedFoodCatalogSnapshot)
            OverallReadinessSnapshotStore.shared.update(
                readiness: snapshot.coachSnapshot.readiness,
                sourceSignature: snapshot.sourceSignature
            )
            ProgressWarmStartStore.shared.update(snapshot.progressWarmStartPayload)
            NutritionWarmStartStore.shared.update(dashboard: snapshot.nutritionDashboardWarmStartPayload)
            NutritionWarmStartStore.shared.update(insights: snapshot.nutritionInsightsWarmStartPayload)

            phase = .ready(snapshot)
            PerformanceTracer.mark(
                .startupCriticalReady,
                "splits=\(snapshot.activeSplitCount) workouts=\(snapshot.completedWorkoutCount)"
            )
        } catch {
            phase = .recoverableFailure(error.localizedDescription, canContinueOffline: false)
        }
    }
}

@MainActor
enum AppStartupMigrationService {
    private static let workoutDateRepairKey = "PeaklineMigration.completedWorkoutDateRepair.v1"

    static func repairWorkoutDatesIfNeeded(in context: ModelContext, force: Bool) throws {
        guard force || !UserDefaults.standard.bool(forKey: workoutDateRepairKey) else { return }
        try WorkoutSessionDateService.repairCompletedSessionDates(in: context)
        UserDefaults.standard.set(true, forKey: workoutDateRepairKey)
    }
}

@MainActor
struct StartupModelProjections {
    let coachIntelligenceInputSignature: String
    let coachTrainingInputSignature: String
    let sourceRevision: Int
    let splitSnapshots: [TrainingSplitSnapshot]
    let workoutSnapshots: [WorkoutAnalyticsSession]
    let historyWorkouts: [HistoryWorkoutSnapshot]
    let trainingDaysPerWeek: Int?
    let sourceSignature: String
    let overallReadinessInputSignature: String
    let workoutDashboardSignature: String
    let sleepReadinessInputSignature: SleepAnalyticsInputSignature
    let sleepSnapshotSeed: StartupSleepSnapshotSeed
    let sleepReadiness: SleepWorkoutReadinessSnapshot
    let sleepAnalytics: SleepAnalyticsSnapshot
    let coachSnapshot: CoachIntelligenceSnapshot
    let previewWarmSnapshots: [WorkoutPreviewWarmSnapshot]
    let recommendedSplits: [WorkoutPreviewSplit]
    let savedFoodCatalogSnapshot: SavedFoodCatalogSnapshot
    let progressExerciseRows: [ProgressExerciseRowSnapshot]
    let nutritionDashboardWarmStartPayload: NutritionDashboardWarmStartPayload
    let nutritionInsightsWarmStartPayload: NutritionInsightsWarmStartPayload
    let settingsProfileSnapshot: SettingsProfileSnapshot?
    let activeSplitCount: Int
    let completedWorkoutCount: Int
    let unfinishedWorkoutCount: Int

    var pureProjection: StartupPureProjection {
        StartupPureProjection(
            sourceRevision: sourceRevision,
            splitSnapshots: splitSnapshots,
            workoutSnapshots: workoutSnapshots,
            historyWorkouts: historyWorkouts,
            sourceSignature: sourceSignature,
            workoutDashboardSignature: workoutDashboardSignature
        )
    }

    @MainActor
    static func make(
        in context: ModelContext,
        deferSleepSnapshots: Bool = false
    ) throws -> StartupModelProjections {
        ReadinessRefreshClock.shared.start()
        let sourceRevision = WorkoutWarmStartInvalidation.shared.revision
        var splitDescriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        splitDescriptor.fetchLimit = 12
        let splits = try context.fetch(splitDescriptor)
        let orderedActiveSplits = TrainingRotationService().orderedActiveSplits(splits)
        let splitSnapshots = try TrainingSplitSnapshotBuilder.snapshots(
            from: orderedActiveSplits,
            in: context
        )
        let recommendedSplits = orderedActiveSplits.map(WorkoutPreviewSplit.init)
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        let trainingDaysPerWeek = profile?.trainingDaysPerWeek

        var completedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        completedDescriptor.fetchLimit = 40
        let completedWorkouts = try context.fetch(completedDescriptor)
        let workoutSnapshots = completedWorkouts.map(WorkoutAnalyticsSession.init)

        var historyDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        historyDescriptor.fetchLimit = 120
        let historyWorkouts = try context.fetch(historyDescriptor).map(HistoryWorkoutSnapshot.init)

        var unfinishedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { !$0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        unfinishedDescriptor.fetchLimit = 5
        let unfinishedWorkoutCount = try context.fetch(unfinishedDescriptor).count

        var exerciseDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        exerciseDescriptor.fetchLimit = 180
        let exercises = try context.fetch(exerciseDescriptor)

        var sleepDescriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        sleepDescriptor.fetchLimit = 90
        let sleepSessions = try context.fetch(sleepDescriptor)

        var napDescriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        napDescriptor.fetchLimit = 90
        let napSessions = try context.fetch(napDescriptor)

        var hydrationDescriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        hydrationDescriptor.fetchLimit = 120
        let hydrationEntries = try context.fetch(hydrationDescriptor)

        var foodDescriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        foodDescriptor.fetchLimit = 160
        let foodLogs = try context.fetch(foodDescriptor)

        var savedFoodDescriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        savedFoodDescriptor.fetchLimit = 180
        let savedFoods = try context.fetch(savedFoodDescriptor)
        let savedFoodCatalogSnapshot = PerformanceTracer.trace(.savedFoodsSnapshot) {
            SavedFoodCatalogSnapshot(foods: savedFoods.map(SavedFoodSnapshot.init))
        }

        let nutritionGoal = NutritionGoalService().loadGoal()
        let nutritionWarmSourceSignature = [
            "revision:\(sourceRevision)",
            foodLogs.prefix(160).map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            nutritionGoal.updatedAt.timeIntervalSince1970.description
        ].joined(separator: "|")
        let nutritionCalendar = Calendar.current
        let nutritionToday = nutritionCalendar.startOfDay(for: .now)
        let nutritionRows = foodLogs
            .filter { nutritionCalendar.isDate($0.loggedAt, inSameDayAs: nutritionToday) }
            .map(NutritionFoodLogSnapshot.init)
        let nutritionMealEntries = Dictionary(
            grouping: nutritionRows.sorted { $0.loggedAt < $1.loggedAt },
            by: \.mealType
        )
        let recentFoodIDs = foodLogs.map(\.foodItemId)
        var seenFoodIDs = Set<UUID>()
        let recentFoods = recentFoodIDs.compactMap { id -> SavedFoodSnapshot? in
            guard seenFoodIDs.insert(id).inserted else { return nil }
            return savedFoodCatalogSnapshot.foods.first { $0.id == id }
        }
        let nutritionSummaryService = NutritionSummaryService()
        let nutritionTrendService = NutritionTrendService()
        let nutritionContextService = TrainingNutritionContextService()
        let nutritionInsightService = NutritionInsightService()
        let nutritionTodaySummary = nutritionSummaryService.dailySummary(
            for: .now,
            foodLogs: foodLogs,
            workouts: completedWorkouts
        )
        let nutritionWeeklySummary = nutritionTrendService.weeklySummary(
            dailySummaries: nutritionSummaryService.dailySummaries(
                endingOn: .now,
                days: 7,
                foodLogs: foodLogs,
                workouts: completedWorkouts
            ),
            goal: nutritionGoal
        )
        let nutritionContext = nutritionContextService.context(
            for: .now,
            foodLogs: foodLogs,
            workouts: completedWorkouts
        )
        let nutritionInsights = nutritionInsightService.insights(
            today: nutritionTodaySummary,
            weekly: nutritionWeeklySummary,
            goal: nutritionGoal,
            context: nutritionContext
        )

        var checkInDescriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        checkInDescriptor.fetchLimit = 30
        let checkIns = try context.fetch(checkInDescriptor)

        let sourceSignature = WorkoutWarmStartSourceSignature.make(
            revision: sourceRevision,
            splitSignatures: splitSnapshots.map { WorkoutWarmStartSourceSignature.split($0) },
            workoutSignatures: completedWorkouts.map { WorkoutWarmStartSourceSignature.workout($0) },
            exerciseSignatures: exercises.map { WorkoutWarmStartSourceSignature.exercise($0) }
        )
        let workoutDashboardSignature = WorkoutDashboardInputSignature(
            // StartWorkout's live query is name-sorted. Keep the pure seed's
            // signature in that same order so a warm first frame does not
            // schedule an unnecessary replacement pass on appearance.
            splits: splits.filter(\.isActive).map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    activeRotationIndex: $0.activeRotationIndex,
                    updatedAt: $0.updatedAt
                )
            },
            sessions: completedWorkouts.prefix(20).map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    endedAt: $0.endedAt,
                    durationSeconds: $0.durationSeconds,
                    perceivedDifficulty: $0.perceivedDifficulty
                )
            },
            workoutRevision: sourceRevision
        ).value

        let sleepSettings = SleepSettingsStore().load()
        let workoutReadinessNaps = Array(napSessions.prefix(30))
        let workoutReadinessWorkouts = Array(completedWorkouts.prefix(12))
        let sleepReadinessInputSignature = SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: workoutReadinessNaps,
            workouts: workoutReadinessWorkouts,
            settings: sleepSettings,
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: sourceRevision
        )
        let sleepSnapshotSeed = StartupSleepSnapshotSeed(
            sessionIDs: sleepSessions.map(\.id),
            analyticsNapIDs: napSessions.map(\.id),
            readinessNapIDs: workoutReadinessNaps.map(\.id),
            analyticsWorkoutIDs: Array(completedWorkouts.prefix(28)).map(\.id),
            readinessWorkoutIDs: workoutReadinessWorkouts.map(\.id),
            settings: sleepSettings,
            workoutRevision: sourceRevision
        )
        let sleepReadiness = deferSleepSnapshots
            ? SleepAnalyticsService.emptyReadinessSnapshot()
            : SleepWorkoutReadinessSnapshotStore.shared.snapshot(
                sessions: sleepSessions,
                naps: workoutReadinessNaps,
                workouts: workoutReadinessWorkouts,
                settings: sleepSettings,
                workoutRevision: sourceRevision,
                force: true
            )
        let sleepAnalytics = deferSleepSnapshots
            ? SleepAnalyticsService.emptySnapshot(settings: sleepSettings)
            : SleepAnalyticsSnapshotStore.shared.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedWorkouts.prefix(28)),
                settings: sleepSettings,
                workoutRevision: sourceRevision,
                force: true
            )
        let hydrationTargetML = HydrationSettingsStore().dailyTargetML()
        let readinessEvaluatedAt = Date.now
        let overallReadinessInputSignature = OverallReadinessInputSignature.make(
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            completedWorkouts: completedWorkouts,
            hydrationEntries: hydrationEntries,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            workoutRevision: sourceRevision,
            dayStart: Calendar.current.startOfDay(for: readinessEvaluatedAt),
            hydrationPhase: HydrationPacingPhase(date: readinessEvaluatedAt)
        )
        let coachInputs = try CoachRouteInputs.load(in: context)
        let coachSnapshot = coachInputs.makeCoachSnapshot()
        let previewWarmSnapshots = WorkoutPreviewSnapshotBuilder.build(
            activeSplits: orderedActiveSplits,
            splitSnapshots: splitSnapshots,
            completedSessions: workoutSnapshots,
            completedWorkoutModels: completedWorkouts,
            exercises: exercises,
            sourceSignature: sourceSignature,
            coachSnapshot: coachSnapshot
        )

        return StartupModelProjections(
            coachIntelligenceInputSignature: coachInputs.currentCoachSnapshotSignature,
            coachTrainingInputSignature: coachInputs.currentWeeklyReviewSignature,
            sourceRevision: sourceRevision,
            splitSnapshots: splitSnapshots,
            workoutSnapshots: workoutSnapshots,
            historyWorkouts: historyWorkouts,
            trainingDaysPerWeek: trainingDaysPerWeek,
            sourceSignature: sourceSignature,
            overallReadinessInputSignature: overallReadinessInputSignature,
            workoutDashboardSignature: workoutDashboardSignature,
            sleepReadinessInputSignature: sleepReadinessInputSignature,
            sleepSnapshotSeed: sleepSnapshotSeed,
            sleepReadiness: sleepReadiness,
            sleepAnalytics: sleepAnalytics,
            coachSnapshot: coachSnapshot,
            previewWarmSnapshots: previewWarmSnapshots,
            recommendedSplits: recommendedSplits,
            savedFoodCatalogSnapshot: savedFoodCatalogSnapshot,
            progressExerciseRows: Array(exercises.prefix(ProgressWarmStartLimits.exerciseRowLimit))
                .map(ProgressExerciseRowSnapshot.init),
            nutritionDashboardWarmStartPayload: NutritionDashboardWarmStartPayload(
                sourceSignature: nutritionWarmSourceSignature,
                selectedDate: nutritionToday,
                dayEntries: nutritionRows,
                totals: NutritionCalculatorService().totals(from: foodLogs.filter { nutritionCalendar.isDate($0.loggedAt, inSameDayAs: nutritionToday) }),
                readiness: coachSnapshot.readiness,
                recentlyLoggedFoods: Array((recentFoods.isEmpty ? Array(savedFoodCatalogSnapshot.foods.prefix(3)) : recentFoods).prefix(3)),
                mealEntries: nutritionMealEntries,
                isTrainingDay: completedWorkouts.contains { nutritionCalendar.isDate($0.date, inSameDayAs: nutritionToday) },
                shouldShowHealthKitStatus: HealthKitPreferenceStore().load().isHealthKitEnabled,
                healthKitSyncRecordsByEntryId: [:]
            ),
            nutritionInsightsWarmStartPayload: NutritionInsightsWarmStartPayload(
                sourceSignature: nutritionWarmSourceSignature,
                goal: nutritionGoal,
                todaySummary: nutritionTodaySummary,
                weeklySummary: nutritionWeeklySummary,
                trainingContext: nutritionContext,
                insights: nutritionInsights
            ),
            settingsProfileSnapshot: profile.map(SettingsProfileSnapshot.init),
            activeSplitCount: orderedActiveSplits.count,
            completedWorkoutCount: completedWorkouts.count,
            unfinishedWorkoutCount: unfinishedWorkoutCount
        )
    }
}

struct StartupPureProjection: Sendable {
    let sourceRevision: Int
    let splitSnapshots: [TrainingSplitSnapshot]
    let workoutSnapshots: [WorkoutAnalyticsSession]
    let historyWorkouts: [HistoryWorkoutSnapshot]
    let sourceSignature: String
    let workoutDashboardSignature: String
}

struct StartupDerivedValues: Sendable {
    let coachDerivedMetrics: CoachDerivedMetrics
    let weeklyReview: WeeklyReview
    let progressWeeklySummary: WeeklyTrainingSummary
    let progressSplitConsistency: SplitConsistencySummary
}

@MainActor
enum StartupSnapshotBuilder {
    /// Materializes every SwiftData relationship synchronously on the main actor.
    /// Callers must finish this boundary before awaiting the pure builder below.
    static func materialize(
        in context: ModelContext,
        deferSleepSnapshots: Bool = false
    ) throws -> StartupModelProjections {
        try PerformanceTracer.trace(.startupSnapshotPreparation) {
            try StartupModelProjections.make(
                in: context,
                deferSleepSnapshots: deferSleepSnapshots
            )
        }
    }

    /// Builds only from Sendable/value projections. No ModelContext or SwiftData
    /// model is accepted by this async portion.
    nonisolated static func makePure(from projection: StartupPureProjection) async -> StartupDerivedValues {
        let splitSnapshots = projection.splitSnapshots
        let workoutSnapshots = projection.workoutSnapshots

        let coachRouteValuesTask = Task.detached(priority: .userInitiated) {
            (
                CoachDerivedMetrics.make(
                    activeSplits: splitSnapshots,
                    completedSessions: workoutSnapshots
                ),
                WeeklyReviewBuilder().build(
                    activeSplits: splitSnapshots,
                    completedSessions: workoutSnapshots
                )
            )
        }
        let progressValuesTask = Task.detached(priority: .userInitiated) {
            let analytics = TrainingAnalyticsService()
            let records = analytics.prTimeline(from: workoutSnapshots)
            return (
                analytics.weeklySummary(from: workoutSnapshots, prRecords: records),
                analytics.splitConsistency(
                    from: workoutSnapshots,
                    activeSplitNames: splitSnapshots.map(\.name)
                )
            )
        }
        let coachRouteValues = await coachRouteValuesTask.value
        let progressValues = await progressValuesTask.value

        return StartupDerivedValues(
            coachDerivedMetrics: coachRouteValues.0,
            weeklyReview: coachRouteValues.1,
            progressWeeklySummary: progressValues.0,
            progressSplitConsistency: progressValues.1
        )
    }

    /// Re-fetches only the bounded model sets represented by the value-only
    /// seed. This happens after the detached preparation has returned, so the
    /// model-backed sleep snapshots never live across that await.
    static func makeSleepSnapshots(
        from seed: StartupSleepSnapshotSeed,
        in context: ModelContext
    ) throws -> StartupSleepSnapshots {
        let sessions = try fetchSleepSessions(ids: seed.sessionIDs, in: context)
        let naps = try fetchNapSessions(ids: seed.analyticsNapIDs, in: context)
        let workouts = try fetchCompletedWorkouts(ids: seed.analyticsWorkoutIDs, in: context)

        let readinessNaps = ordered(seed.readinessNapIDs, from: naps) { $0.id }
        let readinessWorkouts = ordered(seed.readinessWorkoutIDs, from: workouts) { $0.id }
        let analyticsWorkouts = ordered(seed.analyticsWorkoutIDs, from: workouts) { $0.id }

        let readinessInputSignature = SleepAnalyticsInputSignature(
            sessions: sessions,
            naps: readinessNaps,
            workouts: readinessWorkouts,
            settings: seed.settings,
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: seed.workoutRevision
        )
        let readiness = SleepWorkoutReadinessSnapshotStore.shared.snapshot(
            sessions: sessions,
            naps: readinessNaps,
            workouts: readinessWorkouts,
            settings: seed.settings,
            workoutRevision: seed.workoutRevision,
            force: true
        )
        let analytics = SleepAnalyticsSnapshotStore.shared.snapshot(
            sessions: sessions,
            naps: naps,
            workouts: analyticsWorkouts,
            settings: seed.settings,
            workoutRevision: seed.workoutRevision,
            force: true
        )

        return StartupSleepSnapshots(
            analytics: analytics,
            readiness: readiness,
            readinessInputSignature: readinessInputSignature
        )
    }

    private static func fetchSleepSessions(ids: [UUID], in context: ModelContext) throws -> [SleepSession] {
        guard !ids.isEmpty else { return [] }
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\SleepSession.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = ids.count
        let byID = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
        return ordered(ids, from: byID.values) { $0.id }
    }

    private static func fetchNapSessions(ids: [UUID], in context: ModelContext) throws -> [NapSession] {
        guard !ids.isEmpty else { return [] }
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\NapSession.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = ids.count
        let byID = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
        return ordered(ids, from: byID.values) { $0.id }
    }

    private static func fetchCompletedWorkouts(ids: [UUID], in context: ModelContext) throws -> [WorkoutSession] {
        guard !ids.isEmpty else { return [] }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        descriptor.fetchLimit = ids.count
        let byID = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
        return ordered(ids, from: byID.values) { $0.id }
    }

    private static func ordered<Model, CollectionType: Collection>(
        _ ids: [UUID],
        from models: CollectionType,
        id: (Model) -> UUID
    ) -> [Model] where CollectionType.Element == Model {
        let byID = Dictionary(uniqueKeysWithValues: models.map { (id($0), $0) })
        return ids.compactMap { byID[$0] }
    }

    @MainActor
    static func makeBundle(
        from projections: StartupModelProjections,
        derived: StartupDerivedValues
    ) -> StartupSnapshotBundle {
        makeBundle(
            from: projections,
            sleepSnapshots: StartupSleepSnapshots(
                analytics: projections.sleepAnalytics,
                readiness: projections.sleepReadiness,
                readinessInputSignature: projections.sleepReadinessInputSignature
            ),
            derived: derived
        )
    }

    @MainActor
    static func makeBundle(
        from projections: StartupModelProjections,
        sleepSnapshots: StartupSleepSnapshots,
        derived: StartupDerivedValues
    ) -> StartupSnapshotBundle {
        let trainingCall = TrainingCallSnapshotBuilder().make(
            decision: derived.coachDerivedMetrics.summary.trainingDecision,
            activeSplits: projections.splitSnapshots,
            completedSessions: projections.workoutSnapshots,
            readiness: projections.coachSnapshot.readiness,
            fatigueRisk: projections.coachSnapshot.fatigueRisk,
            targetSuggestions: derived.coachDerivedMetrics.targetSuggestions
        ).neutralizedForProvisionalReadiness(
            if: projections.coachSnapshot.readiness.isProvisional
        )
        let recommendedSplit = projections.recommendedSplits
            .first { $0.name == trainingCall.recommendedSplitName }

        let workoutFirstFrameSnapshot = WorkoutStartFirstFrameSnapshot.make(
            trainingCall: trainingCall,
            activeSplits: projections.splitSnapshots,
            historyWorkouts: projections.historyWorkouts,
            previewWarmSnapshots: projections.previewWarmSnapshots,
            dashboardSignature: projections.workoutDashboardSignature,
            workoutRevision: projections.sourceRevision
        )

        return StartupSnapshotBundle(
            preparedAt: .now,
            sourceSignature: projections.sourceSignature,
            trainingCall: trainingCall,
            coachSnapshot: projections.coachSnapshot,
            overallReadinessInputSignature: projections.overallReadinessInputSignature,
            coachRouteSnapshot: CoachRouteRenderSnapshot(
                intelligence: projections.coachSnapshot,
                weeklyReview: derived.weeklyReview,
                derivedMetrics: derived.coachDerivedMetrics,
                sleepAnalytics: sleepSnapshots.analytics,
                trainingCall: trainingCall,
                recommendedSplit: recommendedSplit,
                intelligenceInputSignature: projections.coachIntelligenceInputSignature,
                trainingInputSignature: projections.coachTrainingInputSignature
            ),
            sleepAnalyticsSnapshot: sleepSnapshots.analytics,
            sleepReadinessSnapshot: sleepSnapshots.readiness,
            workoutSleepReadinessSnapshot: WorkoutSleepReadinessSnapshot(sleepSnapshots.readiness),
            sleepReadinessInputSignature: sleepSnapshots.readinessInputSignature,
            workoutFirstFrameSnapshot: workoutFirstFrameSnapshot,
            historySnapshot: HistoryWarmSnapshot(
                workouts: projections.historyWorkouts,
                display: HistoryDisplaySnapshotBuilder.build(
                    workouts: projections.historyWorkouts,
                    trainingDaysPerWeek: projections.trainingDaysPerWeek
                )
            ),
            previewWarmSnapshots: projections.previewWarmSnapshots,
            savedFoodCatalogSnapshot: projections.savedFoodCatalogSnapshot,
            progressWarmStartPayload: ProgressWarmStartPayload(
                sourceSignature: projections.sourceSignature,
                workoutRevision: projections.sourceRevision,
                weeklySummary: derived.progressWeeklySummary,
                splitConsistency: derived.progressSplitConsistency,
                exerciseRows: projections.progressExerciseRows
            ),
            nutritionDashboardWarmStartPayload: projections.nutritionDashboardWarmStartPayload,
            nutritionInsightsWarmStartPayload: projections.nutritionInsightsWarmStartPayload,
            settingsProfileSnapshot: projections.settingsProfileSnapshot,
            activeSplitCount: projections.activeSplitCount,
            completedWorkoutCount: projections.completedWorkoutCount,
            unfinishedWorkoutCount: projections.unfinishedWorkoutCount,
            historyRowWarmCount: projections.historyWorkouts.count
        )
    }
}
