import SwiftData
import SwiftUI
import UIKit

struct AppStartupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var coordinator = AppStartupCoordinator()
    @StateObject private var presentation = StartupPresentationCoordinator()
    @State private var splashOpacity = 1.0
    @State private var splashScale = 1.0
    @State private var email = ""
    @State private var password = ""
    @State private var backupPassphrase = ""
    @State private var signInError: String?
    @State private var isWorking = false
    #if DEBUG
    @State private var performanceAcceptanceSummary = PerformanceAcceptanceState.summary
    private let performanceAcceptanceTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    #endif

    private let accountService = FirebaseAccountService()

    var body: some View {
        ZStack {
            phaseContent

            if presentation.isOverlayMounted {
                PeaklineSplashView(
                    stageText: coordinator.stageText,
                    showsProgress: presentation.showsSlowProgress,
                    animatesWordmark: presentation.animatesWordmark && !reduceMotion
                )
                .opacity(splashOpacity)
                .scaleEffect(splashScale)
                .zIndex(10)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            }
        }
        .task {
            presentation.start()
            await coordinator.start(in: modelContext)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch coordinator.phase {
        case .branding, .checkingAccount, .checkingBackup, .preparingLocalData, .warmingScreens:
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()
                .accessibilityHidden(true)
        case .accountRequired(let readiness):
            AccountGateView(
                readiness: readiness,
                email: $email,
                password: $password,
                backupPassphrase: $backupPassphrase,
                errorMessage: signInError,
                isWorking: isWorking,
                retry: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.retry(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                continueWithoutBackup: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.continueWithoutBackup(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                signIn: { Task { await authenticate(createAccount: false) } },
                createAccount: { Task { await authenticate(createAccount: true) } }
            )
            .onAppear {
                presentation.interrupt(reason: "account")
            }
        case .restorePrompt(let metadata):
            CloudBackupRestorePromptView(
                metadata: metadata,
                passphrase: $backupPassphrase,
                errorMessage: coordinator.restoreError,
                isWorking: isWorking,
                restore: { Task { await restoreBackup() } },
                skip: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.skipRestore(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                }
            )
            .onAppear {
                presentation.interrupt(reason: "restore")
            }
        case .ready(let snapshot):
            readyContent(snapshot)
        case .recoverableFailure(let message, let canContinueOffline):
            startupStatusView(
                title: "Peakline could not finish loading",
                message: message,
                actionTitle: "Try Again",
                action: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.retry(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                secondaryActionTitle: canContinueOffline ? "Continue Offline" : nil,
                secondaryAction: canContinueOffline
                    ? {
                        resumeAfterInteraction()
                        Task {
                            await coordinator.continueOfflineAfterFailure(in: modelContext)
                            interruptPresentationIfNeeded()
                        }
                    }
                    : nil
            )
            .onAppear {
                presentation.interrupt(reason: "error")
            }
        }
    }

    private func readyContent(_ snapshot: StartupSnapshotBundle) -> some View {
        RootTabView(
            startupSnapshot: snapshot,
            startupRevealComplete: presentation.isRevealComplete
        )
        .accessibilityIdentifier("startup-critical-ready")
        #if DEBUG
        .accessibilityValue(performanceAcceptanceSummary)
        .onReceive(performanceAcceptanceTimer) { _ in
            guard PerformanceAcceptanceState.isEnabled else { return }
            performanceAcceptanceSummary = PerformanceAcceptanceState.summary
        }
        #endif
        .allowsHitTesting(presentation.isRevealComplete)
        .accessibilityHidden(!presentation.isRevealComplete)
        .task(id: snapshot.preparedAt) {
            guard presentation.beginReveal() else { return }
            await Task.yield()

            let duration = StartupPresentationTiming.current.revealDuration
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: duration)
                    : .easeInOut(duration: duration)
            ) {
                splashOpacity = 0
                splashScale = reduceMotion ? 1 : 1.015
            }

            try? await Task.sleep(for: .seconds(duration))
            presentation.finishReveal()
        }
    }

    private func resumeAfterInteraction() {
        splashOpacity = 1
        splashScale = 1
        presentation.resumeAfterInteraction()
    }

    private func interruptPresentationIfNeeded() {
        switch coordinator.phase {
        case .accountRequired:
            presentation.interrupt(reason: "account")
        case .restorePrompt:
            presentation.interrupt(reason: "restore")
        case .recoverableFailure:
            presentation.interrupt(reason: "error")
        case .branding, .checkingAccount, .checkingBackup, .preparingLocalData, .warmingScreens, .ready:
            break
        }
    }

    @ViewBuilder
    private func startupStatusView(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .tint(appTheme.colors.accent)
                    .opacity(action == nil ? 1 : 0)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(PrimaryFitnessButtonStyle())
                }

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
            .padding()
        }
        .accessibilityIdentifier("startup-error")
    }

    private func authenticate(createAccount: Bool) async {
        isWorking = true
        defer { isWorking = false }
        signInError = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            signInError = "Enter your email and password."
            return
        }
        guard backupPassphrase.count >= 8 else {
            signInError = "Use a backup passphrase with at least 8 characters."
            return
        }

        do {
            if createAccount {
                _ = try await accountService.createAccount(email: trimmedEmail, password: password)
            } else {
                _ = try await accountService.signIn(email: trimmedEmail, password: password)
            }
            resumeAfterInteraction()
            await coordinator.retry(in: modelContext)
            interruptPresentationIfNeeded()
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func restoreBackup() async {
        isWorking = true
        defer { isWorking = false }

        guard backupPassphrase.count >= 8 else {
            coordinator.restoreError = "Enter the backup passphrase you used when saving this backup."
            return
        }

        resumeAfterInteraction()
        await coordinator.restoreBackup(in: modelContext, passphrase: backupPassphrase)
        if coordinator.restoreError != nil {
            presentation.interrupt(reason: "restore_failed")
        }
    }
}

enum StartupPresentationState: Equatable {
    case animating
    case holdingSlow
    case revealing
    case hidden
    case interrupted
}

enum StartupPresentationEvent {
    case start
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
            return state == .hidden ? .hidden : .animating
        case .slowThresholdReached:
            return state == .animating ? .holdingSlow : state
        case .criticalReady:
            return state == .animating || state == .holdingSlow ? .revealing : state
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
        state == .animating || state == .holdingSlow || state == .revealing
    }

    var animatesWordmark: Bool {
        state == .animating
    }

    var showsSlowProgress: Bool {
        state == .holdingSlow
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
        slowThresholdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(maximumDuration))
            guard !Task.isCancelled, let self, self.state == .animating else { return }
            self.transition(.slowThresholdReached)
            PerformanceTracer.mark(.startupPresentationSlow, "animation_settled")
        }
    }

    @discardableResult
    func beginReveal() -> Bool {
        guard state == .animating || state == .holdingSlow else { return false }
        let route = state == .animating ? "ready_before_5s" : "ready_after_5s"
        slowThresholdTask?.cancel()
        transition(.criticalReady)
        PerformanceTracer.mark(.startupRevealStart, route)
        return true
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
        state = StartupPresentationReducer.reduce(state, event: event)
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

    private init() {}

    func update(readiness: ReadinessScore, sourceSignature: String) {
        guard snapshot.sourceSignature != sourceSignature
                || snapshot.isProvisional != readiness.isProvisional else { return }

        snapshot = OverallReadinessPresentationSnapshot(
            isProvisional: readiness.isProvisional,
            sourceSignature: sourceSignature,
            revision: snapshot.revision &+ 1,
            generatedAt: readiness.generatedAt
        )
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
            workoutDashboardSignature: workoutDashboardSignature,
            previewWarmSnapshots: previewWarmSnapshots
        )
    }

    @MainActor
    static func make(
        in context: ModelContext,
        deferSleepSnapshots: Bool = false
    ) throws -> StartupModelProjections {
        let sourceRevision = WorkoutWarmStartInvalidation.shared.revision
        let splits = try context.fetch(
            FetchDescriptor<TrainingSplit>(sortBy: [SortDescriptor(\.name)])
        )
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
        napDescriptor.fetchLimit = 60
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

        let savedFoods = try context.fetch(
            FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        )
        let savedFoodCatalogSnapshot = PerformanceTracer.trace(.savedFoodsSnapshot) {
            SavedFoodCatalogSnapshot(foods: savedFoods.map(SavedFoodSnapshot.init))
        }

        var checkInDescriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        checkInDescriptor.fetchLimit = 30
        let checkIns = try context.fetch(checkInDescriptor)

        let sourceSignature = WorkoutWarmStartSourceSignature.make(
            revision: sourceRevision,
            splitSignatures: splitSnapshots.map { WorkoutWarmStartSourceSignature.split($0) },
            workoutSignatures: completedWorkouts.map { WorkoutWarmStartSourceSignature.workout($0) }
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
        let nutritionGoal = NutritionGoalService().loadGoal()
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
        let coachSnapshot = CoachIntelligenceService().snapshot(
            for: readinessEvaluatedAt,
            activeSplits: orderedActiveSplits,
            exercises: exercises,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal
        )
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
    let previewWarmSnapshots: [WorkoutPreviewWarmSnapshot]
}

struct StartupDerivedValues: Sendable {
    let trainingCall: TrainingCallSnapshot
    let coachDerivedMetrics: CoachDerivedMetrics
    let weeklyReview: WeeklyReview
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

        let trainingCallTask = Task.detached(priority: .userInitiated) {
            let summary = CoachRecommendationEngine().makeSummary(
                activeSplits: splitSnapshots,
                completedSessions: workoutSnapshots
            )
            return TrainingCallSnapshotBuilder().make(
                decision: summary.trainingDecision,
                activeSplits: splitSnapshots,
                completedSessions: workoutSnapshots
            )
        }

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
        let trainingCall = await trainingCallTask.value
        let coachRouteValues = await coachRouteValuesTask.value

        return StartupDerivedValues(
            trainingCall: trainingCall,
            coachDerivedMetrics: coachRouteValues.0,
            weeklyReview: coachRouteValues.1
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
        let trainingCall = derived.trainingCall.neutralizedForProvisionalReadiness(
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
                recommendedSplit: recommendedSplit
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
            settingsProfileSnapshot: projections.settingsProfileSnapshot,
            activeSplitCount: projections.activeSplitCount,
            completedWorkoutCount: projections.completedWorkoutCount,
            unfinishedWorkoutCount: projections.unfinishedWorkoutCount,
            historyRowWarmCount: projections.historyWorkouts.count
        )
    }
}

struct PeaklineSplashView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stageText: String
    let showsProgress: Bool
    let animatesWordmark: Bool

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 16) {
                PeaklineAnimatedWordmark(
                    color: appTheme.colors.textPrimary,
                    isAnimating: animatesWordmark
                )
                    .frame(height: 48)
                    .accessibilityIdentifier("startup-wordmark")

                if showsProgress {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(appTheme.colors.accent)
                        Text(stageText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                    .accessibilityIdentifier("startup-slow-status")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peakline")
        .accessibilityValue(showsProgress ? stageText : "Loading")
        .accessibilityIdentifier("startup-brand-screen")
    }
}

private struct PeaklineAnimatedWordmark: UIViewRepresentable {
    let color: Color
    let isAnimating: Bool

    func makeUIView(context: Context) -> PeaklineWordmarkView {
        PeaklineWordmarkView()
    }

    func updateUIView(_ uiView: PeaklineWordmarkView, context: Context) {
        uiView.update(color: UIColor(color), isAnimating: isAnimating)
    }
}

private final class PeaklineWordmarkView: UIView {
    private let word = "Peakline"
    private let stack = UIStackView()
    private var letterLabels: [UILabel] = []
    private var hasStartedAnimation = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        letterLabels = word.map { character in
            let label = UILabel()
            label.text = String(character)
            label.font = .systemFont(ofSize: 36, weight: .bold)
            label.textAlignment = .center
            label.isAccessibilityElement = false
            stack.addArrangedSubview(label)
            return label
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: UIColor, isAnimating: Bool) {
        letterLabels.forEach { $0.textColor = color }

        guard isAnimating else {
            stopAtRest()
            return
        }
        guard !hasStartedAnimation else { return }
        hasStartedAnimation = true

        // Core Animation owns the one-shot sequence so SwiftData preparation on
        // the main actor cannot produce per-frame SwiftUI invalidations.
        DispatchQueue.main.async { [weak self] in
            self?.startOneShotAnimation()
        }
    }

    private func startOneShotAnimation() {
        let start = CACurrentMediaTime() + 0.20

        for (index, label) in letterLabels.enumerated() {
            let primary = CAAnimationGroup()
            primary.animations = [
                keyframes("transform.translation.y", values: [0, -8, 0], keyTimes: [0, 0.48, 1]),
                keyframes("transform.scale", values: [1, 1.025, 1], keyTimes: [0, 0.48, 1]),
                keyframes("opacity", values: [1, 0.82, 1], keyTimes: [0, 0.48, 1])
            ]
            primary.duration = 0.72
            primary.beginTime = start + (Double(index) * 0.075)
            primary.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.layer.add(primary, forKey: "peakline-primary-rise")

            let microWave = CAAnimationGroup()
            microWave.animations = [
                keyframes("transform.translation.y", values: [0, -3, 0], keyTimes: [0, 0.5, 1]),
                keyframes("transform.scale", values: [1, 1.01, 1], keyTimes: [0, 0.5, 1]),
                keyframes("opacity", values: [1, 0.93, 1], keyTimes: [0, 0.5, 1])
            ]
            microWave.duration = 0.62
            microWave.beginTime = start + 2.0 + (Double(index) * 0.055)
            microWave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.layer.add(microWave, forKey: "peakline-micro-wave")
        }

        let breath = CAKeyframeAnimation(keyPath: "transform.scale")
        breath.values = [1, 1.012, 1]
        breath.keyTimes = [0, 0.45, 1]
        breath.duration = 1.55
        breath.beginTime = start + 3.25
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        stack.layer.add(breath, forKey: "peakline-breath")
    }

    private func stopAtRest() {
        guard hasStartedAnimation else { return }
        hasStartedAnimation = false
        letterLabels.forEach {
            $0.layer.removeAllAnimations()
            $0.layer.transform = CATransform3DIdentity
            $0.layer.opacity = 1
        }
        stack.layer.removeAllAnimations()
        stack.layer.transform = CATransform3DIdentity
    }

    private func keyframes(
        _ keyPath: String,
        values: [NSNumber],
        keyTimes: [NSNumber]
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        return animation
    }
}

struct AccountGateView: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: AccountReadiness
    @Binding var email: String
    @Binding var password: String
    @Binding var backupPassphrase: String
    let errorMessage: String?
    let isWorking: Bool
    let retry: () -> Void
    let continueWithoutBackup: () -> Void
    let signIn: () -> Void
    let createAccount: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 74, height: 74)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protect your Peakline data")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Create or sign in to a free Firebase-backed account. Your full backup is encrypted before it leaves this iPhone.")
                            .font(.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(readiness.title, systemImage: readinessIcon)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text(readiness.message)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isFirebaseMissing {
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Local-only mode", systemImage: "iphone")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("You can keep using Peakline on this iPhone now. Add Firebase setup later to save encrypted backups before deleting or reinstalling the app.")
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            SecureField("Backup passphrase", text: $backupPassphrase)
                                .textContentType(.newPassword)
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .disabled(isWorking)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(appTheme.dangerColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isFirebaseMissing {
                        Button(action: continueWithoutBackup) {
                            Label("Continue Local Only", systemImage: "iphone")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .disabled(isWorking)
                    } else {
                        HStack(spacing: 10) {
                            Button(action: signIn) {
                                Label(isWorking ? "Signing In" : "Sign In", systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryFitnessButtonStyle())
                            .disabled(isWorking)

                            Button(action: createAccount) {
                                Label("Create", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .disabled(isWorking)
                        }
                    }

                    Button(action: retry) {
                        Label(isWorking ? "Checking" : "Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking)
                }
                .padding(24)
            }
        }
        .accessibilityIdentifier("startup-account-gate")
        .peaklineKeyboardDismissal()
    }

    private var isFirebaseMissing: Bool {
        if case .firebaseNotConfigured = readiness { return true }
        return false
    }

    private var readinessIcon: String {
        switch readiness {
        case .ready:
            return "checkmark.shield.fill"
        case .firebaseNotConfigured:
            return "externaldrive.badge.exclamationmark"
        default:
            return "person.crop.circle.badge.exclamationmark"
        }
    }
}

struct CloudBackupRestorePromptView: View {
    @Environment(\.appTheme) private var appTheme

    let metadata: FullAppBackupMetadata
    @Binding var passphrase: String
    let errorMessage: String?
    let isWorking: Bool
    let restore: () -> Void
    let skip: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 74, height: 74)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore your Peakline backup?")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("An encrypted Firebase backup was found before local starter data loaded.")
                        .font(.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                FitnessCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Last saved \(metadata.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("\(metadata.counts.workoutCount) workouts, \(metadata.counts.foodLogCount) food logs, \(metadata.counts.sleepCount) sleep sessions, and \(metadata.counts.hydrationCount) hydration entries.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SecureField("Backup passphrase", text: $passphrase)
                    .textContentType(.password)
                    .padding(12)
                    .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(isWorking)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: restore) {
                    Label(isWorking ? "Restoring" : "Restore Backup", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
                .disabled(isWorking)

                Button(action: skip) {
                    Text("Start Fresh")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .disabled(isWorking)
            }
            .padding(24)
        }
        .accessibilityIdentifier("startup-restore-prompt")
        .peaklineKeyboardDismissal()
    }
}
