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

struct StartupSnapshotBundle {
    let preparedAt: Date
    let sourceSignature: String
    let trainingCall: TrainingCallSnapshot
    let coachSnapshot: CoachIntelligenceSnapshot
    let coachRouteSnapshot: CoachRouteRenderSnapshot
    let sleepAnalyticsSnapshot: SleepAnalyticsSnapshot
    let sleepReadinessSnapshot: SleepWorkoutReadinessSnapshot
    let historySnapshot: HistoryWarmSnapshot
    let previewWarmSnapshots: [WorkoutPreviewWarmSnapshot]
    let savedFoodCatalogSnapshot: SavedFoodCatalogSnapshot
    let activeSplitCount: Int
    let completedWorkoutCount: Int
    let unfinishedWorkoutCount: Int
    let historyRowWarmCount: Int
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

        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
                && !ProcessInfo.processInfo.arguments.contains("-SkipAccountGate") else {
            await prepareLocalData(in: context, forceDateRepair: false)
            return
        }

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
            let snapshot = try await PerformanceTracer.traceAsync(.startupLocalPreparation) {
                SeedDataService.seedIfNeeded(in: context)
                try AppStartupMigrationService.repairWorkoutDatesIfNeeded(
                    in: context,
                    force: forceDateRepair
                )

                phase = .warmingScreens
                stageText = "Preparing your dashboards"
                return try await StartupSnapshotBuilder.make(in: context)
            }

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
enum StartupSnapshotBuilder {
    static func make(in context: ModelContext) async throws -> StartupSnapshotBundle {
        try await PerformanceTracer.traceAsync(.startupSnapshotPreparation) {
            let splits = try context.fetch(
                FetchDescriptor<TrainingSplit>(sortBy: [SortDescriptor(\.name)])
            )
            let orderedActiveSplits = TrainingRotationService().orderedActiveSplits(splits)
            let splitSnapshots = try TrainingSplitSnapshotBuilder.snapshots(
                from: orderedActiveSplits,
                in: context
            )

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
            let unfinishedWorkouts = try context.fetch(unfinishedDescriptor)

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

            let sourceSignature = [
                splitSnapshots.map {
                    "\($0.id.uuidString):\($0.activeRotationIndex ?? -1):\($0.updatedAt.timeIntervalSince1970)"
                }.joined(separator: ","),
                workoutSnapshots.map {
                    "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.splitId?.uuidString ?? "legacy")"
                }.joined(separator: ",")
            ].joined(separator: "|")

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

            let sleepSettings = SleepSettingsStore().load()
            let sleepReadiness = SleepWorkoutReadinessSnapshotStore.shared.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedWorkouts.prefix(12)),
                settings: sleepSettings,
                force: true
            )
            let sleepAnalytics = SleepAnalyticsSnapshotStore.shared.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: Array(completedWorkouts.prefix(28)),
                settings: sleepSettings,
                force: true
            )
            let coachSnapshot = CoachIntelligenceService().snapshot(
                activeSplits: orderedActiveSplits,
                exercises: exercises,
                sleepSessions: sleepSessions,
                napSessions: napSessions,
                hydrationEntries: hydrationEntries,
                completedWorkouts: completedWorkouts,
                foodLogs: foodLogs,
                checkIns: checkIns,
                sleepSettings: sleepSettings,
                hydrationTargetML: HydrationSettingsStore().dailyTargetML(),
                nutritionGoal: NutritionGoalService().loadGoal()
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

            return StartupSnapshotBundle(
                preparedAt: .now,
                sourceSignature: sourceSignature,
                trainingCall: trainingCall,
                coachSnapshot: coachSnapshot,
                coachRouteSnapshot: CoachRouteRenderSnapshot(
                    intelligence: coachSnapshot,
                    weeklyReview: coachRouteValues.1,
                    derivedMetrics: coachRouteValues.0,
                    sleepAnalytics: sleepAnalytics,
                    trainingCall: trainingCall,
                    recommendedSplit: orderedActiveSplits
                        .first { $0.name == trainingCall.recommendedSplitName }
                        .map(WorkoutPreviewSplit.init)
                ),
                sleepAnalyticsSnapshot: sleepAnalytics,
                sleepReadinessSnapshot: sleepReadiness,
                historySnapshot: HistoryWarmSnapshot(
                    workouts: historyWorkouts,
                    display: HistoryDisplaySnapshotBuilder.build(workouts: historyWorkouts)
                ),
                previewWarmSnapshots: previewWarmSnapshots,
                savedFoodCatalogSnapshot: savedFoodCatalogSnapshot,
                activeSplitCount: orderedActiveSplits.count,
                completedWorkoutCount: completedWorkouts.count,
                unfinishedWorkoutCount: unfinishedWorkouts.count,
                historyRowWarmCount: historyWorkouts.count
            )
        }
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
