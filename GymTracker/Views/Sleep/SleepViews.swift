import SwiftData
import SwiftUI

private let healthKitSleepAuthorizationRequestedKey = "sleep.healthkit.authorizationRequested.v1"

@MainActor
private final class SleepHealthKitExportStatusStore: ObservableObject {
    static let shared = SleepHealthKitExportStatusStore()

    @Published private(set) var message: String?

    private init() {}

    func begin() {
        message = "Saving confirmed sleep to Apple Health…"
    }

    func succeeded(sampleCount: Int) {
        message = sampleCount == 1
            ? "Saved confirmed sleep to Apple Health (1 sample)."
            : "Saved confirmed sleep to Apple Health (\(sampleCount) samples)."
    }

    func failed(_ message: String) {
        self.message = message
    }
}

@MainActor
private func applySleepHealthKitExport(
    _ ids: [String],
    to sessionID: UUID,
    in container: ModelContainer,
    statusStore: SleepHealthKitExportStatusStore
) {
    // Resolve the app's live context only after HealthKit has returned. The
    // container is stable across the suspension; a ModelContext or model must
    // not be retained by the task while the HealthKit write is in flight.
    let modelContext = container.mainContext
    let descriptor = FetchDescriptor<SleepSession>(
        predicate: #Predicate<SleepSession> { $0.id == sessionID }
    )

    do {
        guard let session = try modelContext.fetch(descriptor).first else {
            statusStore.failed("Apple Health accepted the sleep, but Peakline could not record the export. Local sleep was saved.")
            return
        }

        let previousSampleIDs = session.healthKitSampleIds
        let hadChangesBeforeExport = modelContext.hasChanges
        session.healthKitSampleIds = ids

        do {
            try modelContext.save()
            statusStore.succeeded(sampleCount: ids.count)
        } catch {
            // Keep unrelated pending edits in this context, but never leave a
            // failed export's sample IDs dirty for a later unrelated save.
            if hadChangesBeforeExport {
                session.healthKitSampleIds = previousSampleIDs
            } else {
                modelContext.rollback()
            }
            throw error
        }
    } catch {
        statusStore.failed("Apple Health accepted the sleep, but Peakline could not record the export. Local sleep was saved. \(error.localizedDescription)")
    }
}

@MainActor
private func scheduleSleepHealthKitExport(
    for session: SleepSession,
    in modelContext: ModelContext
) {
    scheduleSleepHealthKitExport(
        for: session,
        in: modelContext,
        statusStore: SleepHealthKitExportStatusStore.shared
    )
}

@MainActor
private func scheduleSleepHealthKitExport(
    for session: SleepSession,
    in modelContext: ModelContext,
    statusStore: SleepHealthKitExportStatusStore
) {
    let writeSnapshot = HealthKitSleepWriteSnapshot(session: session)
    let sessionID = writeSnapshot.id
    let container = modelContext.container
    statusStore.begin()
    PerformanceTracer.mark(.healthKitSleepBridge, "export scheduled session=\(sessionID.uuidString)")

    Task(priority: .utility) { @MainActor in
        do {
            let ids = try await HealthKitSleepService().writeConfirmedSession(writeSnapshot)
            applySleepHealthKitExport(ids, to: sessionID, in: container, statusStore: statusStore)
        } catch {
            statusStore.failed("Apple Health export failed. Local sleep was saved. \(error.localizedDescription)")
        }
    }
}

struct SleepDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared
    @ObservedObject private var healthKitExportStatus = SleepHealthKitExportStatusStore.shared

    @Query
    private var sessions: [SleepSession]

    @Query
    private var workouts: [WorkoutSession]

    @Query
    private var naps: [NapSession]

    @Query
    private var hydrationEntries: [HydrationEntry]

    @Query
    private var foodLogEntries: [FoodLogEntry]

    @Query
    private var coachCheckIns: [DailyCoachCheckIn]

    @State private var settings = SleepSettingsStore().load()
    @State private var showingSettings = false
    @State private var activeStartSheet: SleepStartSheet?
    @State private var confirmationSession: SleepSession?
    @State private var pendingDiscardSession: SleepSession?
    @State private var importedCount: Int?
    @State private var healthKitImportError: String?
    @State private var dashboardErrorMessage: String?
    @State private var summaries: [SleepSummary] = []
    @State private var latestSummary = SleepScoringService.emptySummary()
    @State private var dashboardSummary = SleepAnalyticsService.emptyDashboardSummary()
    @State private var lastAnalyticsSignature: SleepAnalyticsInputSignature?
    @State private var readinessScore = CoachIntelligenceService.emptySnapshot().readiness
    @State private var lastReadinessSignature: String?
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var healthKitSleepImportTask: Task<Void, Never>?
    @State private var didRequestInitialDashboardRefresh = false
    @State private var didPresentMorningConfirmation = false
    @State private var healthKitImportPresentation: HealthKitSleepImportPresentation = .idle
    @State private var locallyResolvedSessionIDs: Set<UUID> = []

    private let repository = SleepSessionRepository()
    private let scoring = SleepScoringService()
    private let coaching = SleepCoachingService()
    private let coachIntelligence = CoachIntelligenceService()
    private let settingsStore = SleepSettingsStore()
    private let analyticsStore = SleepAnalyticsSnapshotStore.shared
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    private let hasInitialSnapshot: Bool
    private let initialAnalyticsSignature: SleepAnalyticsInputSignature?

    init(
        initialSnapshot: SleepAnalyticsSnapshot? = nil,
        initialReadinessScore: ReadinessScore? = nil
    ) {
        hasInitialSnapshot = initialSnapshot != nil
        initialAnalyticsSignature = initialSnapshot?.inputSignature
        _sessions = Query(Self.sessionsDescriptor)
        _workouts = Query(Self.workoutsDescriptor)
        _naps = Query(Self.napsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
        _summaries = State(initialValue: initialSnapshot?.summaries ?? [])
        _latestSummary = State(
            initialValue: initialSnapshot?.latestSummary ?? SleepScoringService.emptySummary()
        )
        _dashboardSummary = State(
            initialValue: initialSnapshot?.dashboardSummary ?? SleepAnalyticsService.emptyDashboardSummary()
        )
        _readinessScore = State(
            initialValue: initialReadinessScore ?? CoachIntelligenceService.emptySnapshot().readiness
        )
    }

    private static var sessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var napsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var hydrationEntriesDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var foodLogEntriesDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return descriptor
    }

    private static var coachCheckInsDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private var completedSessions: [SleepSession] {
        sessions.filter { $0.status == .completed && $0.wakeAt <= Date.now }
    }

    private var activeSession: SleepSession? {
        sessions.first { $0.status == .active && !locallyResolvedSessionIDs.contains($0.id) }
    }

    private var currentAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var analyticsObservationSignature: String {
        [
            signature(sessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.status.rawValue)" },
            signature(naps, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(workouts, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            "\(workoutWarmStartInvalidation.revision)",
            "\(settings.targetSleepMinutes):\(settings.preferredSource.rawValue)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    private var currentReadinessSignature: String {
        [
            signature(sessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.status.rawValue)" },
            signature(naps, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(workouts, limit: 40) { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" },
            "\(workoutWarmStartInvalidation.revision)",
            signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 200) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "\(settings.targetSleepMinutes):\(settings.recoveryCoachingEnabled):\(settings.preferredSource.rawValue)",
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)",
            readinessRefreshClock.token.signature
        ].joined(separator: "|")
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding {
            pendingDiscardSession != nil
        } set: { showing in
            if !showing {
                pendingDiscardSession = nil
            }
        }
    }

    var body: some View {
        FitnessScreen {
            if let healthKitImportError {
                Text(healthKitImportError)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let dashboardErrorMessage {
                Text(dashboardErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sleep-dashboard-error")
            }

            if let exportStatus = healthKitExportStatus.message {
                Text(exportStatus)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Apple Health export status")
                    .accessibilityValue(exportStatus)
                    .accessibilityIdentifier("sleep-health-export-status")
            }

            if let activeSession {
                activeSleepCard(activeSession)
                activeStatusNote
            } else if latestSummary.primarySession == nil {
                if completedSessions.isEmpty {
                    noDataHero
                } else {
                    missingLastNightHero
                }
                appleHealthAccessCard
            } else {
                populatedHero
                readinessSupportSection
                appleHealthAccessCard
            }

            if activeSession == nil, !completedSessions.isEmpty {
                if trackedNightCount > 0 {
                    weeklyChartCard
                }
                if !dashboardSummary.recentNaps.isEmpty {
                    napsSection
                }
                if trackedNightCount >= 3 {
                    consistencyAndDebt
                }
                if !readinessScore.isProvisional, !dashboardSummary.coachingInsights.isEmpty {
                    coachingInsightsSection
                }
                if !completedSessions.isEmpty {
                    historySection
                }
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("sleep-screen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    PerformanceTracer.mark(.toolbarBreadcrumb, "sleep.settings tapped")
                    showingSettings = true
                } label: {
                    Label("Sleep settings", systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel("Sleep settings")
                .accessibilityIdentifier("sleep-settings-button")
            }
        }
        .sheet(item: $confirmationSession) { session in
            SleepMorningConfirmationView(session: session) { resolvedSessionID in
                locallyResolvedSessionIDs.insert(resolvedSessionID)
                refreshSleepAnalytics(force: true)
                refreshReadinessScore(force: true)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SleepSettingsView(settings: $settings)
        }
        .sheet(item: $activeStartSheet) { sheet in
            switch sheet {
            case .sleepMode:
                SleepModeView(settings: $settings)
            case .napEntry:
                NapSessionEditorView()
            case .napTimer:
                NapTimerView()
            case .manualEntry:
                SleepSessionEditorView(mode: .manual)
            }
        }
        .alert("Discard active sleep?", isPresented: discardAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDiscardSession = nil
            }
            Button("Discard", role: .destructive) {
                discardPendingSleepSession()
            }
        } message: {
            Text("This removes the unfinished Sleep Mode session.")
        }
        .onAppear {
            readinessRefreshClock.start()
            settings = settingsStore.load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            presentMorningConfirmationIfNeeded()
            let currentSignature = currentAnalyticsSignature
            let warmSnapshotMatchesLiveData = hasInitialSnapshot && initialAnalyticsSignature == currentSignature
            let shouldForceRefresh = !didRequestInitialDashboardRefresh
                && (!hasInitialSnapshot || !warmSnapshotMatchesLiveData)
            didRequestInitialDashboardRefresh = true
            if warmSnapshotMatchesLiveData {
                lastAnalyticsSignature = currentSignature
            } else {
                lastAnalyticsSignature = nil
            }
            lastReadinessSignature = nil
            DispatchQueue.main.async {
                refreshSleepAnalytics(force: shouldForceRefresh)
                refreshReadinessScore(force: shouldForceRefresh)
                scheduleSleepImportIfEnabled()
            }
        }
        .onDisappear {
            PerformanceTracer.mark(.healthKitSleepBridge, "dashboard onDisappear cancel_import begin")
            healthKitSleepImportTask?.cancel()
            PerformanceTracer.mark(.healthKitSleepBridge, "dashboard onDisappear cancel_import end")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.healthKitSleepBridge, "dashboard willResignActive cancel_import begin")
            healthKitSleepImportTask?.cancel()
            PerformanceTracer.mark(.healthKitSleepBridge, "dashboard willResignActive cancel_import end")
        }
        .onChange(of: analyticsObservationSignature) { _, _ in
            refreshSleepAnalytics()
            refreshReadinessScore()
        }
        .onChange(of: currentReadinessSignature) { _, _ in
            refreshReadinessScore()
        }
        .onChange(of: settings) { _, newValue in
            settingsStore.save(newValue)
            refreshSleepAnalytics()
            refreshReadinessScore()
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            let notificationSettings = newValue
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: notificationSettings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
        }
    }

    private var noDataHero: some View {
        SleepCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                SleepRow(title: "Sleep Recovery", subtitle: "Start with one night of tracking. Peakline will keep the estimate and its limits clear.", systemImage: "moon.stars.fill")

                Text("No sleep tracked yet")
                    .font(AppTypography.heroMetric)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep-empty-title")
                    .accessibilityIdentifier("sleep-no-data-hero")

                SleepActionButton(title: "Start Sleep Mode", systemImage: "moon.zzz.fill", style: .primary) {
                    activeStartSheet = .sleepMode
                }
                .accessibilityIdentifier("sleep-start-mode")

                sleepEntryActions
            }
        }
    }

    private var missingLastNightHero: some View {
        SleepCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                SleepRow(
                    title: "Sleep Recovery",
                    subtitle: "Older records stay in your history, but they do not fill today's missing overnight record.",
                    systemImage: "moon.stars.fill"
                )

                Text("No sleep recorded last night")
                    .font(AppTypography.heroMetric)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep-no-overnight-hero")

                Text("Today's sleep evidence remains unknown until you add the missing overnight record.")
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SleepActionButton(title: "Start Sleep Mode", systemImage: "moon.zzz.fill", style: .primary) {
                    activeStartSheet = .sleepMode
                }
                .accessibilityIdentifier("sleep-start-mode")

                sleepEntryActions
            }
        }
    }

    private var sleepEntryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                sleepEntryActionButtons
            }

            VStack(spacing: 10) {
                sleepEntryActionButtons
            }
        }
    }

    @ViewBuilder
    private var sleepEntryActionButtons: some View {
        SleepQuietAction(title: "Add Sleep", systemImage: "square.and.pencil") {
            activeStartSheet = .manualEntry
        }
        .accessibilityIdentifier("sleep-add-manual")

        SleepQuietAction(title: "Log Nap", systemImage: "moonphase.first.quarter") {
            activeStartSheet = .napEntry
        }
        .accessibilityIdentifier("sleep-log-nap")
    }

    private var populatedHero: some View {
        SleepCard(style: .hero) {
            VStack(alignment: .leading, spacing: 14) {
                SleepRow(
                    title: "Last night's sleep",
                    subtitle: summaryMetadataText,
                    systemImage: "moon.stars.fill",
                    tint: latestSummary.recoveryState == .unknown ? appTheme.colors.textSecondary : recoveryTint
                )

                Text(SleepScoringService.durationText(minutes: latestSummary.totalSleepMinutes))
                    .font(AppTypography.heroMetric)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep-last-night-duration")

                Text("Peakline sleep estimate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .accessibilityIdentifier("sleep-populated-hero")

                if let stageBreakdown = latestSummary.stageBreakdown, stageBreakdown.hasStages {
                    SleepStageBreakdownView(breakdown: stageBreakdown)
                        .accessibilityIdentifier("sleep-stage-breakdown")
                } else if latestSummary.source == .appleHealth {
                    Text("Apple Health stage detail is unavailable for this record. Peakline preserves the sleep interval without inventing stage values.")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sleep-stage-breakdown-unavailable")
                }

                Text(populatedHeroSupportText)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if latestSummary.napCreditMinutes > 0 {
                    Label("Nap added \(SleepScoringService.durationText(minutes: latestSummary.napCreditMinutes)) recovery credit", systemImage: "moonphase.first.quarter")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if latestSummary.source == .inAppTimer {
                    Text(SleepCoachingService.estimatedDataDisclaimer)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let conflict = dashboardSummary.sourceConflict {
                    Text(conflict.displayMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var readinessSupportSection: some View {
        DashboardSection(title: "Readiness & training support") {
            SleepCard(style: .compact) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(readinessScore.isProvisional ? "Provisional readiness" : supportTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Spacer(minLength: 8)
                        Text("\(readinessScore.value)/100")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Text(readinessScore.isProvisional ? "Training guidance waits for more evidence." : supportMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(readinessScore.confidenceNote)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readinessScore.isProvisional ? appTheme.colors.textSecondary : appTheme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sleep-readiness-confidence")
                }
            }
            .accessibilityIdentifier("sleep-readiness-support")
        }
    }

    private var activeStatusNote: some View {
        Text("Charts and coaching will update after you confirm this session.")
            .font(.caption)
            .foregroundStyle(appTheme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("sleep-active-status-note")
    }

    private var appleHealthAccessCard: some View {
        Button {
            showingSettings = true
        } label: {
            SleepCard(style: .compact) {
                SleepRow(
                    title: appleHealthTitle,
                    subtitle: appleHealthSubtitle,
                    systemImage: "heart.text.square.fill",
                    tint: HealthKitSleepService().isAvailable ? appTheme.colors.accent : appTheme.colors.textSecondary,
                    showsChevron: true
                ) {
                    Text(appleHealthActionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appleHealthTitle)
        .accessibilityValue(appleHealthSubtitle)
        .accessibilityHint(appleHealthAccessibilityHint)
        .accessibilityIdentifier("sleep-health-access")
    }

    private var appleHealthTitle: String {
        if !HealthKitSleepService().isAvailable {
            return "Apple Health unavailable"
        }

        switch (settings.enableAppleHealthImport, settings.enableAppleHealthExport) {
        case (true, true):
            return "Apple Health import and save"
        case (true, false):
            return "Apple Health import"
        case (false, true):
            return "Save to Apple Health"
        case (false, false):
            return "Apple Health off"
        }
    }

    private var appleHealthSubtitle: String {
        if !HealthKitSleepService().isAvailable {
            return "This device does not support HealthKit sleep access."
        }

        switch (settings.enableAppleHealthImport, settings.enableAppleHealthExport) {
        case (true, true):
            let exportStatus = healthKitExportStatus.message
                ?? "Saving confirmed sleep is enabled; review Apple Health save access in Settings."
            return "\(appleHealthImportSubtitle) \(exportStatus)"
        case (true, false):
            return appleHealthImportSubtitle
        case (false, true):
            return healthKitExportStatus.message
                ?? "Confirmed sleep will be saved when Apple Health save access is authorized. Import is off."
        case (false, false):
            return "Apple Health import and saving confirmed sleep are off. Open Settings to change these preferences."
        }
    }

    private var appleHealthImportSubtitle: String {
        if !healthKitAuthorizationWasRequested {
            return "Import is enabled, but access has not been requested on this install. Open Settings to continue."
        }

        switch healthKitImportPresentation {
        case .importing:
            return "Checking Apple Health for recent sleep…"
        case .denied:
            return "Sleep access was denied. Review access in the Health app."
        case .restricted:
            return "Sleep access is restricted on this device."
        case .error(let message):
            return message
        default:
            break
        }

        if let importedCount {
            return importedCount == 0
                ? "Apple Health checked. No new sleep samples were found."
                : "Imported \(importedCount) Apple Health sleep sample\(importedCount == 1 ? "" : "s")."
        }
        if let lastSync = settings.lastHealthKitSleepSyncAt {
            return "Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened)). Sleep data improves recovery scoring."
        }
        return "Import is enabled. Apple Health does not reveal read permission, so Peakline verifies access only when an import succeeds."
    }

    private var appleHealthAccessibilityHint: String {
        if !HealthKitSleepService().isAvailable {
            return "Opens Sleep Settings to review Apple Health availability."
        }

        switch (settings.enableAppleHealthImport, settings.enableAppleHealthExport) {
        case (true, true):
            return "Opens Sleep Settings to request or review Apple Health import and save access."
        case (true, false):
            return "Opens Sleep Settings to request or review Apple Health import access."
        case (false, true):
            return "Opens Sleep Settings to review Apple Health save access."
        case (false, false):
            return "Opens Sleep Settings to change Apple Health import and save preferences."
        }
    }

    private var appleHealthActionLabel: String {
        if !HealthKitSleepService().isAvailable {
            return "Review"
        }

        switch (settings.enableAppleHealthImport, settings.enableAppleHealthExport) {
        case (true, true):
            return "Review access"
        case (true, false):
            return "Review import"
        case (false, true):
            return "Review saving"
        case (false, false):
            return "Configure"
        }
    }

    private var summaryMetadataText: String {
        guard latestSummary.primarySession != nil else {
            return "Start Sleep Mode tonight to improve recovery coaching."
        }

        let quality = latestSummary.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality rating"
        let source = latestSummary.source?.displayName ?? "Sleep"
        return PeaklineText.joinedMetadata(["\(quality) quality", source])
    }

    private var populatedHeroSupportText: String {
        if latestSummary.qualityRating == nil {
            return "Add a quality rating when you have a useful read on how rested you feel."
        }
        return "Sleep is one input to readiness. Use the context below with how you feel and how warm-ups move."
    }

    private var supportTitle: String {
        guard let recommendation = dashboardSummary.adaptiveRecommendation else {
            return latestSummary.recoveryState == .unknown ? "Use today's context" : "Train as planned"
        }
        switch recommendation.level {
        case .rest, .recovery:
            return "Recovery-focused support"
        case .light, .moderate:
            return "Keep today's work controlled"
        case .push, .normal:
            return "Train as planned"
        }
    }

    private var supportMessage: String {
        guard let recommendation = dashboardSummary.adaptiveRecommendation else {
            return "Use sleep, recent training, and warm-ups together."
        }
        switch recommendation.level {
        case .push:
            return "Sleep and recent context support your planned session. Progress only if warm-ups feel good."
        default:
            return recommendation.message
        }
    }

    private var recoveryTint: Color {
        switch latestSummary.recoveryState {
        case .high, .good:
            return appTheme.colors.success
        case .moderate, .low:
            return appTheme.colors.warning
        case .veryLow:
            return appTheme.colors.danger
        case .unknown:
            return appTheme.colors.textSecondary
        }
    }

    private func activeSleepCard(_ session: SleepSession) -> some View {
        SleepCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    SleepIcon(systemImage: "moon.zzz.fill", size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sleep Mode Active")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .accessibilityIdentifier("sleep-active-hero")

                        TimelineView(.periodic(from: Date.now, by: 60)) { timeline in
                            Text(activeSleepDescription(for: session, at: timeline.date))
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("sleep-active-elapsed")
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        activeSleepActions(session)
                    }

                    VStack(spacing: 10) {
                        activeSleepActions(session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activeSleepActions(_ session: SleepSession) -> some View {
        SleepActionButton(
            title: "Confirm Wake Time",
            systemImage: "sun.max.fill",
            style: .primary
        ) {
            confirmationSession = session
        }
        .accessibilityIdentifier("sleep-active-confirm")

        SleepActionButton(
            title: "Discard",
            systemImage: "xmark.circle",
            style: .danger
        ) {
            pendingDiscardSession = session
        }
        .accessibilityLabel("Discard sleep session")
        .accessibilityIdentifier("sleep-active-discard")
    }

    private func activeSleepDescription(for session: SleepSession, at now: Date) -> String {
        let start = session.estimatedSleepStartAt ?? session.confirmedSleepStartAt
        if now < start {
            return "Wind-down is running. Estimated sleep starts at \(start.formatted(date: .omitted, time: .shortened))."
        }

        let minutes = SleepSessionRepository().durationMinutes(start: start, wake: now)
        return "Estimated sleep so far: \(SleepScoringService.durationText(minutes: minutes)). Confirm or edit wake time when you are up."
    }

    private func discardPendingSleepSession() {
        guard let session = pendingDiscardSession else { return }
        let discardedSessionID = session.id
        dashboardErrorMessage = nil

        do {
            try repository.discard(session, in: modelContext)
            locallyResolvedSessionIDs.insert(discardedSessionID)
            pendingDiscardSession = nil

            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            let notificationSettings = settings
            Task {
                SleepNotificationScheduler().cancelNotifications(for: discardedSessionID)
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: notificationSettings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
        } catch {
            dashboardErrorMessage = "Couldn’t discard this sleep session. \(error.localizedDescription)"
        }
    }

    private var weeklyChartCard: some View {
        DashboardSection(title: "Last 7 Days") {
            SleepCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Average \(SleepScoringService.durationText(minutes: averageSleepMinutes))")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Spacer()

                        Text("Target \(SleepScoringService.durationText(minutes: settings.targetSleepMinutes))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(summaries.reversed()) { summary in
                                SleepDurationBar(summary: summary, targetMinutes: settings.targetSleepMinutes)
                            }
                        }
                        .frame(height: 150)

                        GeometryReader { proxy in
                            let y = proxy.size.height * 0.13
                            Rectangle()
                                .fill(appTheme.colors.textTertiary.opacity(0.35))
                                .frame(height: 1)
                                .offset(y: y)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Weekly sleep chart. Average \(averageSleepMinutes == 0 ? "no tracked sleep" : SleepScoringService.durationText(minutes: averageSleepMinutes)). Target \(SleepScoringService.durationText(minutes: settings.targetSleepMinutes)).")
                    .accessibilityIdentifier("sleep-seven-day-trend")
                }
            }
        }
    }

    private var averageSleepMinutes: Int {
        let tracked = summaries.filter { $0.primarySession != nil }
        guard !tracked.isEmpty else { return 0 }
        return tracked.map(\.totalSleepMinutes).reduce(0, +) / tracked.count
    }

    private var napsSection: some View {
        DashboardSection(title: "Naps") {
            VStack(spacing: 12) {
                HStack {
                    Spacer(minLength: 0)
                    SleepQuietAction(title: "Nap Timer", systemImage: "timer") {
                        activeStartSheet = .napTimer
                    }
                    .frame(maxWidth: 170)
                    .accessibilityIdentifier("sleep-nap-timer")
                }

                if dashboardSummary.recentNaps.isEmpty {
                    SleepCard(style: .compact) {
                        SleepRow(
                            title: "No naps logged recently",
                            subtitle: "Log a nap after short sleep to see whether it helped today's recovery.",
                            systemImage: "moonphase.first.quarter"
                        )
                    }
                } else {
                    ForEach(dashboardSummary.recentNaps) { nap in
                        NapSummaryCard(nap: nap, creditMinutes: napCreditText(for: nap))
                    }
                }
            }
        }
    }

    private func napCreditText(for nap: NapSession) -> String {
        let sleep = latestSummary.primarySession.map {
            ResolvedSleepSession(
                id: $0.id,
                sleepDate: $0.nightDate,
                startDate: $0.confirmedSleepStartAt,
                endDate: $0.wakeAt,
                asleepDuration: TimeInterval($0.durationMinutes * 60),
                inBedDuration: nil,
                qualityRating: $0.qualityRating,
                dataSource: $0.source,
                confidence: $0.confidence,
                appleHealthSummary: nil,
                appSessionID: $0.id,
                notes: $0.notes,
                conflict: nil,
                stageBreakdown: nil
            )
        }
        let credit = NapRecoveryCalculator().calculateNapCredit(naps: [nap], overnightSleep: sleep, sleepTarget: TimeInterval(settings.targetSleepMinutes * 60)).cappedCreditMinutes
        return credit > 0 ? "+\(SleepScoringService.durationText(minutes: credit)) recovery credit" : "Logged for recovery context"
    }

    private var consistencyAndDebt: some View {
        DashboardSection(title: "Recovery Trends") {
            SleepCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SleepMetric(title: "Sleep Debt", value: sleepDebtHeadline, systemImage: "moon.zzz")
                        SleepMetric(title: "Consistency", value: dashboardSummary.consistencySummary.displayName, systemImage: "calendar")
                    }

                    Text(sleepDebtCopy)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let bed = dashboardSummary.consistencySummary.averageSleepStart, let wake = dashboardSummary.consistencySummary.averageWakeTime {
                        HStack(spacing: 10) {
                            SleepMetric(title: "Bedtime", value: bed.formatted(date: .omitted, time: .shortened), systemImage: "bed.double")
                            SleepMetric(title: "Wake", value: wake.formatted(date: .omitted, time: .shortened), systemImage: "sun.max")
                        }
                    }

                    Text(dashboardSummary.consistencySummary.message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trainingInsightCard: some View {
        DashboardSection(title: "Sleep And Training") {
            SleepCard(style: .compact) {
                SleepRow(
                    title: "Training context",
                    subtitle: coaching.trainingInsight(summaries: summaries, workouts: workouts),
                    systemImage: "figure.strengthtraining.traditional"
                )
            }
        }
    }

    private var coachingInsightsSection: some View {
        DashboardSection(title: "Coaching Insights") {
            VStack(spacing: 10) {
                if dashboardSummary.coachingInsights.isEmpty {
                    SleepCard(style: .compact) {
                        SleepRow(
                            title: "Insights warming up",
                            subtitle: "Keep tracking sleep and workouts. Once there is enough history, Peakline can show how your sleep affects performance.",
                            systemImage: "sparkles"
                        )
                    }
                } else {
                    ForEach(dashboardSummary.coachingInsights) { insight in
                        SleepCoachingInsightCard(insight: insight)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        DashboardSection(title: "History") {
            if completedSessions.isEmpty {
                SleepCard(style: .compact) {
                    SleepRow(
                        title: "No sleep data yet",
                        subtitle: "Start Sleep Mode tonight to help the app understand your recovery.",
                        systemImage: "moon.zzz"
                    )
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(completedSessions.prefix(14)) { session in
                        NavigationLink {
                            SleepSessionDetailView(
                                session: session,
                                recentSessions: completedSessions,
                                stageBreakdown: summaries.first { $0.primarySession?.id == session.id }?.stageBreakdown,
                                readinessIsProvisional: readinessScore.isProvisional
                            )
                        } label: {
                            SleepHistoryRow(
                                session: session,
                                qualityScore: scoring.score(for: session, recentSessions: completedSessions, settings: settings),
                                readinessIsProvisional: readinessScore.isProvisional
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sleep-history-\(session.id.uuidString)")
                    }
                }
            }
        }
    }

    private var trackedNightCount: Int {
        summaries.filter { $0.primarySession != nil }.count
    }

    private var sleepDebtHeadline: String {
        guard trackedNightCount > 0 else { return "-" }
        let debt = scoring.sleepDebtMinutes(summaries: summaries, targetMinutes: settings.targetSleepMinutes)
        return debt == 0 ? "On target" : "\(SleepScoringService.durationText(minutes: debt))"
    }

    private var sleepDebtCopy: String {
        guard trackedNightCount > 0 else {
            return "Track more nights to calculate weekly sleep debt."
        }

        let debt = scoring.sleepDebtMinutes(summaries: summaries, targetMinutes: settings.targetSleepMinutes)
        if debt == 0 {
            return "You are meeting your sleep target this week. Based on \(trackedNightCount) tracked night\(trackedNightCount == 1 ? "" : "s")."
        }

        return "\(SleepScoringService.durationText(minutes: debt)) below target. Based on \(trackedNightCount) tracked night\(trackedNightCount == 1 ? "" : "s")."
    }

    private func refreshSleepAnalytics(force: Bool = false) {
        let signature = currentAnalyticsSignature
        guard force || signature != lastAnalyticsSignature else { return }

        let snapshot = analyticsStore.snapshot(
            sessions: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            workoutRevision: workoutWarmStartInvalidation.revision,
            force: force
        )
        AppMotion.withoutAnimation {
            summaries = snapshot.summaries
            latestSummary = snapshot.latestSummary
            dashboardSummary = snapshot.dashboardSummary
            lastAnalyticsSignature = signature
        }
    }

    private func refreshReadinessScore(force: Bool = false) {
        let signature = currentReadinessSignature
        guard force || signature != lastReadinessSignature else { return }

        let nextReadinessScore = coachIntelligence.readiness(
            sleepSessions: sessions,
            napSessions: naps,
            hydrationEntries: hydrationEntries,
            completedWorkouts: workouts,
            foodLogs: foodLogEntries,
            checkIns: coachCheckIns,
            sleepSettings: settings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal
        )
        AppMotion.withoutAnimation {
            readinessScore = nextReadinessScore
            lastReadinessSignature = signature
        }
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }

    private func scheduleSleepImportIfEnabled() {
        guard settings.enableAppleHealthImport, healthKitAuthorizationWasRequested else { return }
        if let lastSync = settings.lastHealthKitSleepSyncAt, Date.now.timeIntervalSince(lastSync) < 30 * 60 {
            return
        }

        let existing = HealthKitSleepImportExistingSnapshot(sessions: sessions, naps: naps)
        healthKitSleepImportTask?.cancel()
        healthKitSleepImportTask = Task(priority: .utility) {
            PerformanceTracer.mark(.healthKitSleepBridge, "import task begin")
            await MainActor.run {
                healthKitImportPresentation = .importing
            }
            let service = HealthKitSleepService()
            let access = service.accessSnapshot(
                readEnabled: settings.enableAppleHealthImport,
                writeEnabled: settings.enableAppleHealthExport,
                authorizationWasRequested: healthKitAuthorizationWasRequested
            )
            let result = await service.importRecentSleepCandidatesResult(
                days: 14,
                existing: existing,
                access: access
            )
            guard !Task.isCancelled else { return }
            applyHealthKitSleepImport(result)
        }
    }

    @MainActor
    private func applyHealthKitSleepImport(_ result: HealthKitSleepImportResult) {
        PerformanceTracer.mark(.healthKitSleepBridge, "import main_apply begin")
        healthKitImportPresentation = .make(result: result, lastSyncedAt: settings.lastHealthKitSleepSyncAt)
        switch result {
        case .imported(let candidates, _):
            persistImportedHealthKitCandidates(candidates)
        case .noNewData:
            importedCount = 0
            healthKitImportError = nil
            markHealthKitSyncCompleted()
        case .unavailable:
            healthKitImportError = "Apple Health is unavailable on this device."
        case .notRequested:
            healthKitImportError = "Apple Health sleep access has not been requested."
        case .denied:
            healthKitImportError = "Apple Health sleep access was denied. Review access in the Health app."
        case .restricted:
            healthKitImportError = "Apple Health sleep access is restricted on this device."
        case .error(let error):
            healthKitImportError = error.localizedDescription
        case .importing:
            break
        }
        PerformanceTracer.mark(.healthKitSleepBridge, "import main_apply end")
    }

    @MainActor
    private func persistImportedHealthKitCandidates(_ candidates: [HealthKitSleepImportCandidate]) {
        do {
            let count = try persistHealthKitSleepImport(candidates)
            settings = settingsStore.load()
            healthKitImportError = nil
            refreshSleepAnalytics(force: true)
            importedCount = count

            let notificationSettings = settings
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            Task {
                PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.import notification_refresh begin")
                await SleepNotificationScheduler().refreshAllSleepNotifications(
                    settings: notificationSettings,
                    sessions: sessionSnapshots,
                    workouts: workoutSnapshots
                )
                PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.import notification_refresh end")
            }
        } catch {
            healthKitImportError = "Could not save Apple Health sleep data locally. Try again."
            PerformanceTracer.mark(.healthKitSleepBridge, "import save_failed error=\(error.localizedDescription)")
        }
    }

    private var healthKitAuthorizationWasRequested: Bool {
        UserDefaults.standard.bool(forKey: healthKitSleepAuthorizationRequestedKey)
    }

    private func markHealthKitSyncCompleted() {
        var refreshedSettings = settingsStore.load()
        refreshedSettings.lastHealthKitSleepSyncAt = .now
        settingsStore.save(refreshedSettings)
        settings = refreshedSettings
    }

    private func persistHealthKitSleepImport(_ candidates: [HealthKitSleepImportCandidate]) throws -> Int {
        var imported = 0
        var insertedSessions: [SleepSession] = []
        var insertedNaps: [NapSession] = []
        let referenceNow = Date.now

        for candidate in candidates {
            guard candidate.isValidForImport(at: referenceNow) else {
                PerformanceTracer.mark(.healthKitSleepBridge, "import persistence skipped future interval")
                continue
            }

            switch candidate {
            case let .session(startDate, endDate, confidence, healthKitSampleIds):
                let session = SleepSession(
                    confirmedSleepStartAt: startDate,
                    wakeAt: endDate,
                    durationMinutes: Int(endDate.timeIntervalSince(startDate) / 60),
                    source: .appleHealth,
                    confidence: confidence,
                    status: .completed,
                    healthKitSampleIds: healthKitSampleIds
                )
                modelContext.insert(session)
                insertedSessions.append(session)
                imported += 1
            case let .nap(startDate, endDate, healthKitSampleIds):
                let nap = NapSession(
                    startDate: startDate,
                    endDate: endDate,
                    source: .appleHealth,
                    timingCategory: NapSession.timingCategory(for: startDate),
                    healthKitSampleIds: healthKitSampleIds
                )
                modelContext.insert(nap)
                insertedNaps.append(nap)
                imported += 1
            }
        }

        if imported > 0 {
            do {
                try modelContext.save()
            } catch {
                insertedSessions.forEach(modelContext.delete)
                insertedNaps.forEach(modelContext.delete)
                throw error
            }
        }

        markHealthKitSyncCompleted()

        return imported
    }

    private func presentMorningConfirmationIfNeeded() {
        guard !didPresentMorningConfirmation, let activeSession else { return }
        let sleepStart = activeSession.estimatedSleepStartAt ?? activeSession.confirmedSleepStartAt
        guard Date.now.timeIntervalSince(sleepStart) >= 4 * 60 * 60 else { return }
        didPresentMorningConfirmation = true
        confirmationSession = activeSession
    }
}

private enum SleepStartSheet: String, Identifiable {
    case sleepMode
    case napEntry
    case napTimer
    case manualEntry

    var id: String { rawValue }
}

private struct NapSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let nap: NapSession
    let creditMinutes: String

    var body: some View {
        SleepCard(style: .compact) {
            SleepRow(
                title: "\(nap.startDate.formatted(date: .omitted, time: .shortened))-\(nap.endDate.formatted(date: .omitted, time: .shortened))",
                subtitle: napSubtitle,
                systemImage: "moonphase.first.quarter"
            ) {
                Text(nap.source.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
            }
        }
    }

    private var napSubtitle: String {
        let metadata = PeaklineText.joinedMetadata([
            SleepScoringService.durationText(minutes: nap.durationMinutes),
            nap.timingCategory.displayName,
            nap.qualityRating.map { "\(SleepQualityPicker.label(for: $0)) quality" } ?? ""
        ])
        return "\(metadata). \(creditMinutes)"
    }
}

struct NapSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var start = Date.now.addingTimeInterval(-30 * 60)
    @State private var end = Date.now
    @State private var quality: Int?
    @State private var note = ""
    @State private var errorText: String?
    @State private var showingTimer = false

    private let repository = NapSessionRepository()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Log Nap",
                subtitle: "Add short recovery sleep without changing overnight data.",
                systemImage: "moonphase.first.quarter"
            ) {
                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SleepRow(
                            title: "Nap Time",
                            subtitle: "Set when the nap started and ended.",
                            systemImage: "clock"
                        )

                        DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-nap-start")
                        DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-nap-end")
                    }
                }

                SleepQuietAction(title: "Use Nap Timer", systemImage: "timer") {
                    showingTimer = true
                }
                .accessibilityIdentifier("sleep-nap-timer")

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Quality")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                    SleepQualityPicker(selection: $quality)
                        .accessibilityIdentifier("sleep-nap-quality")
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                    TextField("Felt refreshed, still tired, post-workout nap", text: $note, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(12)
                            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("sleep-nap-error")
                }

                SleepActionButton(title: "Save Nap", systemImage: "checkmark", style: .primary) {
                    saveNap()
                }
                .accessibilityIdentifier("sleep-nap-save")
            }
            .navigationTitle("Log Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingTimer) {
                NapTimerView()
            }
        }
    }

    private func saveNap() {
        do {
            try repository.addNap(start: start, end: end, quality: quality, note: note, in: modelContext)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct NapTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var timerState = NapTimerMachineState.idle(selectedMinutes: 30)
    @State private var now = Date.now
    @State private var quality: Int?
    @State private var errorText: String?
    @State private var showingCloseConfirmation = false

    private let options = [20, 30, 45, 90]
    private let repository = NapSessionRepository()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Nap Timer",
                subtitle: "Set a short recovery window. The saved end time always comes from the clock.",
                systemImage: "timer"
            ) {
                SleepCard(style: .hero) {
                    VStack(alignment: .center, spacing: 14) {
                        SleepIcon(systemImage: timerState.phase == .idle ? "timer" : "moon.zzz.fill", size: 60)

                        Text(timerText)
                            .font(AppTypography.heroMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                            .accessibilityIdentifier("sleep-nap-timer-value")

                        Text(stateTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sleep-nap-timer-hero")

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Timer length")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Menu {
                            ForEach(options, id: \.self) { minutes in
                                Button("\(minutes) minutes") {
                                    transition(.selectDuration(minutes: minutes))
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(timerState.selectedMinutes) minutes")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
                        }
                        .disabled(timerState.phase != .idle)
                        .accessibilityLabel("Nap timer length")
                        .accessibilityValue("\(timerState.selectedMinutes) minutes")
                        .accessibilityIdentifier("sleep-nap-timer-length")

                        SleepQualityPicker(selection: $quality)
                            .disabled(timerState.phase != .idle)
                            .accessibilityIdentifier("sleep-nap-timer-quality")
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sleep-nap-timer-error")
                }

                SleepActionButton(
                    title: primaryActionTitle,
                    systemImage: primaryActionSystemImage,
                    style: .primary
                ) {
                    switch timerState.phase {
                    case .idle:
                        transition(.start(now: timerStartDate))
                    case .running, .elapsed:
                        finishNap()
                    case .completed:
                        dismiss()
                    case .finishing, .discardConfirmation:
                        break
                    }
                }
                .disabled(timerState.phase == .finishing || timerState.phase == .discardConfirmation)
                .accessibilityIdentifier("sleep-nap-timer-primary")
            }
            .navigationTitle("Nap Timer")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(timerState.isActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { requestClose() }
                        .disabled(timerState.phase == .finishing)
                        .accessibilityIdentifier("sleep-nap-timer-close")
                }
            }
            .onReceive(timer) { value in
                now = value
                transition(.tick(now: value))
            }
            .alert("Discard nap timer?", isPresented: $showingCloseConfirmation) {
                Button("Keep Timer", role: .cancel) {
                    transition(.cancelDiscard(now: .now))
                }
                Button("Discard", role: .destructive) {
                    transition(.confirmDiscard)
                    dismiss()
                }
            } message: {
                Text("The running timer has not been saved.")
            }
        }
    }

    private var elapsedSeconds: Int {
        Int(timerState.elapsed(at: now))
    }

    private var timerText: String {
        guard timerState.phase != .idle else { return "\(timerState.selectedMinutes):00" }
        return "\(elapsedSeconds / 60):\(String(format: "%02d", elapsedSeconds % 60))"
    }

    private var stateTitle: String {
        switch timerState.phase {
        case .idle:
            return "Ready when you are"
        case .running:
            return "Nap in progress"
        case .elapsed:
            return "Target reached · finish when ready"
        case .finishing:
            return "Saving nap"
        case .completed:
            return "Nap saved"
        case .discardConfirmation:
            return "Confirm discard"
        }
    }

    private var primaryActionTitle: String {
        switch timerState.phase {
        case .idle:
            return "Start Nap Timer"
        case .running, .elapsed:
            return "Finish Nap"
        case .finishing:
            return "Saving…"
        case .completed:
            return "Done"
        case .discardConfirmation:
            return "Finish Nap"
        }
    }

    private var primaryActionSystemImage: String {
        switch timerState.phase {
        case .idle:
            return "timer"
        case .finishing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .running, .elapsed, .discardConfirmation:
            return "checkmark.circle.fill"
        }
    }

    private var timerStartDate: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestNapElapsedFixture") {
            return Date.now.addingTimeInterval(-11 * 60)
        }
        #endif
        return .now
    }

    private func requestClose() {
        guard timerState.isActive else {
            dismiss()
            return
        }
        transition(.requestDiscard)
        showingCloseConfirmation = true
    }

    private func finishNap() {
        let transition = NapTimerStateMachine.reduce(timerState, .finish(now: .now))
        timerState = transition.state
        errorText = nil

        switch transition.effect {
        case let .persist(completion):
            do {
                try repository.addNap(
                    start: completion.startDate,
                    end: completion.endDate,
                    quality: quality,
                    note: "Nap timer",
                    source: .napTimer,
                    in: modelContext
                )
                timerState = NapTimerStateMachine.reduce(timerState, .finishSucceeded).state
            } catch {
                timerState = NapTimerStateMachine.reduce(timerState, .finishFailed).state
                errorText = error.localizedDescription
            }
        case let .error(error):
            errorText = error == .tooShort
                ? "Keep the timer running for at least 10 minutes before saving a nap."
                : error.localizedDescription
        case .none, .discard:
            break
        }
    }

    private func transition(_ action: NapTimerAction) {
        let result = NapTimerStateMachine.reduce(timerState, action)
        timerState = result.state
        if case let .error(error) = result.effect {
            errorText = error.localizedDescription
        } else {
            switch action {
            case .tick, .finishFailed:
                break
            default:
                errorText = nil
            }
        }
    }
}

struct SleepModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Query
    private var sessions: [SleepSession]

    @Query
    private var workouts: [WorkoutSession]

    @Binding var settings: SleepSettings
    @State private var selectedMinutes: Int
    @State private var now = Date()
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(settings: Binding<SleepSettings>) {
        self._settings = settings
        self._selectedMinutes = State(initialValue: settings.wrappedValue.defaultWindDownMinutes)
        self._sessions = Query(Self.sessionsDescriptor)
        self._workouts = Query(Self.workoutsDescriptor)
    }

    private static var sessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.colors.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        windDownSummary
                        windDownOptionsCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 150)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom) {
                sleepModeActions
            }
            .navigationTitle("Sleep Mode")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sleep-mode-close")
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { value in
                now = value
            }
        }
    }

    private var windDownSummary: some View {
        SleepCard(style: .hero, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind-down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(durationHeadline)
                            .font(AppTypography.heroMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 5) {
                        FitnessIconBadge(
                            systemImage: "bed.double.fill",
                            size: 44,
                            tint: appTheme.colors.textPrimary,
                            background: appTheme.colors.cardBackgroundElevated
                        )

                        Text(selectedMinutes == 0 ? "Tracking now" : "Tracking later")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(appTheme.colors.cardBackgroundElevated)

                            Capsule()
                                .fill(appTheme.colors.accent)
                                .frame(width: proxy.size.width * windDownFraction)
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Estimated start")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Spacer(minLength: 8)

                        Text(estimatedStart.formatted(date: .omitted, time: .shortened))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var windDownOptionsCard: some View {
        SleepCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wind-down length")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Spacer(minLength: 8)

                        Text("You can adjust the start in the morning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind-down length")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("You can adjust the start in the morning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(SleepSettings.windDownOptions, id: \.self) { minutes in
                        SleepWindDownOptionButton(
                            minutes: minutes,
                            isSelected: minutes == selectedMinutes
                        ) {
                            selectedMinutes = minutes
                        }
                        .accessibilityIdentifier("sleep-mode-winddown-\(minutes)")
                    }
                }
            }
        }
    }

    private var sleepModeActions: some View {
        VStack(spacing: 10) {
            SleepModeActionButton(title: "Start Sleep Mode", systemImage: "moon.zzz.fill", style: .primary) {
                start(minutes: selectedMinutes)
            }
            .accessibilityIdentifier("sleep-mode-start")

            Button("Start now") {
                start(minutes: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appTheme.colors.textSecondary)
            .frame(minHeight: appTheme.metrics.minimumHitTarget)
            .accessibilityIdentifier("sleep-mode-start-now")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            reduceTransparency
                ? AnyShapeStyle(appTheme.colors.cardBackground)
                : AnyShapeStyle(.thinMaterial)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appTheme.colors.cardBorder)
                .frame(height: 1)
        }
    }

    private var estimatedStart: Date {
        now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
    }

    private var durationHeadline: String {
        selectedMinutes == 0 ? "Now" : "\(selectedMinutes) min"
    }

    private var windDownFraction: CGFloat {
        CGFloat(max(0.12, Double(selectedMinutes) / Double(SleepSettings.windDownOptions.max() ?? 60)))
    }

    private func start(minutes: Int) {
        do {
            _ = try repository.startSleepMode(windDownMinutes: minutes, in: modelContext)
            settings.defaultWindDownMinutes = minutes == 0 ? settings.defaultWindDownMinutes : minutes
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            let notificationSettings = settings
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: notificationSettings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SleepWindDownOptionButton: View {
    @Environment(\.appTheme) private var appTheme

    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Text("\(minutes)m")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? appTheme.colors.accentForeground : appTheme.colors.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
        }
        .buttonStyle(PeaklineButtonPressStyle())
        .accessibilityLabel("\(minutes) minute wind-down")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        isSelected ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated
    }

    private var border: Color {
        isSelected ? appTheme.colors.accent.opacity(0.36) : appTheme.colors.cardBorder
    }
}

private struct SleepModeActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: style == .primary ? 58 : 52)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return appTheme.colors.accentForeground
        case .secondary:
            return appTheme.colors.textPrimary
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent
        case .secondary:
            return appTheme.colors.cardBackgroundElevated
        }
    }

    private var border: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent.opacity(0.4)
        case .secondary:
            return appTheme.colors.cardBorder
        }
    }
}

struct SleepMorningConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query
    private var sessions: [SleepSession]

    @Query
    private var workouts: [WorkoutSession]

    let session: SleepSession
    let onResolved: (UUID) -> Void

    @State private var sleepStart: Date
    @State private var wakeAt: Date
    @State private var qualityRating: Int?
    @State private var tags: Set<SleepTag> = []
    @State private var errorMessage: String?
    @State private var showingDiscardConfirmation = false

    private let repository = SleepSessionRepository()

    init(session: SleepSession, onResolved: @escaping (UUID) -> Void = { _ in }) {
        self.session = session
        self.onResolved = onResolved
        self._sessions = Query(Self.sessionsDescriptor)
        self._workouts = Query(Self.workoutsDescriptor)
        let start = session.estimatedSleepStartAt ?? session.confirmedSleepStartAt
        self._sleepStart = State(initialValue: min(start, Date.now))
        self._wakeAt = State(initialValue: Date.now)
        self._qualityRating = State(initialValue: session.qualityRating)
        self._tags = State(initialValue: Set(session.tags))
    }

    private static var sessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\SleepSession.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Good morning",
                subtitle: "Did you wake up at \(wakeAt.formatted(date: .omitted, time: .shortened))?",
                systemImage: "sun.max.fill"
            ) {
                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Estimated sleep")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(SleepScoringService.durationText(minutes: repository.durationMinutes(start: sleepStart, wake: wakeAt)))
                            .font(AppTypography.heroMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        DatePicker("Sleep start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-morning-start")
                        DatePicker("Wake time", selection: $wakeAt, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-morning-wake")
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How rested do you feel?")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        SleepQualityPicker(selection: $qualityRating)
                            .accessibilityIdentifier("sleep-morning-quality")

                        Text("Optional context")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        SleepTagPicker(selection: $tags)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("sleep-morning-error")
                }

                SleepActionButton(title: "Confirm Wake Time", systemImage: "checkmark.seal.fill", style: .primary) {
                    confirm()
                }
                .accessibilityIdentifier("sleep-morning-confirm")

                SleepActionButton(title: "Discard Session", systemImage: "trash", style: .danger) {
                    showingDiscardConfirmation = true
                }
                .accessibilityIdentifier("sleep-morning-discard")
            }
            .navigationTitle("Good morning")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .alert("Discard this sleep session?", isPresented: $showingDiscardConfirmation) {
                Button("Keep Session", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    do {
                        try repository.discard(session, in: modelContext)
                        onResolved(session.id)
                        dismiss()
                    } catch {
                        errorMessage = "Couldn’t discard this sleep session. \(error.localizedDescription)"
                    }
                }
            } message: {
                Text("This removes the unfinished session from today's recovery context.")
            }
        }
    }

    private func confirm() {
        do {
            PerformanceTracer.mark(.sleepMorningConfirmation, "confirm begin")
            try repository.confirmActiveSession(
                session,
                sleepStart: sleepStart,
                wake: wakeAt,
                quality: qualityRating,
                tags: Array(tags),
                in: modelContext
            )

            let settings = SleepSettingsStore().load()
            if settings.enableAppleHealthExport, session.source == .inAppTimer {
                scheduleSleepHealthKitExport(for: session, in: modelContext)
            }

            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            let sessionID = session.id
            Task {
                PerformanceTracer.mark(.sleepMorningConfirmation, "notification_refresh begin")
                SleepNotificationScheduler().cancelNotifications(for: sessionID)
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessionSnapshots, workouts: workoutSnapshots)
                PerformanceTracer.mark(.sleepMorningConfirmation, "notification_refresh end")
            }
            PerformanceTracer.mark(.sleepMorningConfirmation, "confirm end")
            onResolved(session.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

struct SleepSessionEditorView: View {
    enum Mode {
        case manual
        case edit(SleepSession)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sessions: [SleepSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    let mode: Mode

    @State private var sleepStart: Date
    @State private var wakeAt: Date
    @State private var qualityRating: Int?
    @State private var tags: Set<SleepTag> = []
    @State private var notes = ""
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(mode: Mode) {
        self.mode = mode
        self._sessions = Query(Self.sessionsDescriptor)
        self._workouts = Query(Self.workoutsDescriptor)

        switch mode {
        case .manual:
            let wake = Date.now
            #if DEBUG
            let start = ProcessInfo.processInfo.arguments.contains("-UITestSleepInvalidEditorFixture")
                ? wake
                : Calendar.current.date(byAdding: .hour, value: -8, to: wake) ?? wake.addingTimeInterval(-28_800)
            #else
            let start = Calendar.current.date(byAdding: .hour, value: -8, to: wake) ?? wake.addingTimeInterval(-28_800)
            #endif
            self._sleepStart = State(initialValue: start)
            self._wakeAt = State(initialValue: wake)
        case .edit(let session):
            self._sleepStart = State(initialValue: session.confirmedSleepStartAt)
            self._wakeAt = State(initialValue: session.wakeAt)
            self._qualityRating = State(initialValue: session.qualityRating)
            self._tags = State(initialValue: Set(session.tags))
            self._notes = State(initialValue: session.notes ?? "")
        }
    }

    private static var sessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: title,
                subtitle: "Keep sleep data honest and editable.",
                systemImage: "square.and.pencil"
            ) {
                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Sleep start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-editor-start")
                        DatePicker("Wake time", selection: $wakeAt, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-editor-wake")

                        SleepMiniMetric(
                            title: "Duration",
                            value: SleepScoringService.durationText(minutes: repository.durationMinutes(start: sleepStart, wake: wakeAt))
                        )
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SleepQualityPicker(selection: $qualityRating)
                            .accessibilityIdentifier("sleep-editor-quality")
                        SleepTagPicker(selection: $tags)
                            .accessibilityIdentifier("sleep-editor-tags")

                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(12)
                            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("sleep-editor-error")
                }

                SleepActionButton(title: "Save Sleep Session", systemImage: "checkmark", style: .primary) {
                    save()
                }
                .accessibilityIdentifier("sleep-editor-save")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .manual:
            return "Add Sleep"
        case .edit:
            return "Edit Sleep"
        }
    }

    private func save() {
        do {
            var manualSessionToExport: SleepSession?
            switch mode {
            case .manual:
                try repository.startManualSession(
                    start: sleepStart,
                    wake: wakeAt,
                    quality: qualityRating,
                    tags: Array(tags),
                    notes: notes.isEmpty ? nil : notes,
                    in: modelContext
                )
                if SleepSettingsStore().load().enableAppleHealthExport {
                    manualSessionToExport = try recentlySavedManualSession(start: sleepStart, wake: wakeAt)
                }
            case .edit(let session):
                try repository.updateCompletedSession(
                    session,
                    sleepStart: sleepStart,
                    wake: wakeAt,
                    quality: qualityRating,
                    tags: Array(tags),
                    notes: notes.isEmpty ? nil : notes,
                    in: modelContext
                )
            }
            if let manualSessionToExport {
                scheduleSleepHealthKitExport(for: manualSessionToExport, in: modelContext)
            }
            let refreshedSettings = SleepSettingsStore().load()
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: refreshedSettings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recentlySavedManualSession(start: Date, wake: Date) throws -> SleepSession? {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\SleepSession.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return try modelContext.fetch(descriptor).first {
            $0.source == .manual
                && $0.status == .completed
                && $0.confirmedSleepStartAt == start
                && $0.wakeAt == wake
        }
    }
}

struct SleepSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let session: SleepSession
    let recentSessions: [SleepSession]
    let stageBreakdown: SleepStageBreakdown?
    let readinessIsProvisional: Bool
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var qualityScore: Int

    private let repository = SleepSessionRepository()

    init(
        session: SleepSession,
        recentSessions: [SleepSession] = [],
        stageBreakdown: SleepStageBreakdown? = nil,
        readinessIsProvisional: Bool = true
    ) {
        self.session = session
        self.recentSessions = recentSessions.isEmpty ? [session] : recentSessions
        self.stageBreakdown = stageBreakdown
        self.readinessIsProvisional = readinessIsProvisional
        let score = PerformanceTracer.trace(.sleepSessionQuality) {
            SleepScoringService().score(
                for: session,
                recentSessions: recentSessions.isEmpty ? [session] : recentSessions,
                settings: SleepSettingsStore().load()
            )
        }
        _qualityScore = State(initialValue: score)
    }

    var body: some View {
        FitnessScreen(
            title: SleepCalendar.displayTitle(for: session.nightDate),
            subtitle: PeaklineText.joinedMetadata([session.source.displayName, session.confidence.displayName]),
            systemImage: "moon.stars.fill"
        ) {
            SleepCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(SleepScoringService.durationText(minutes: session.durationMinutes))
                        .font(AppTypography.heroMetric)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    HStack(spacing: 10) {
                        SleepMiniMetric(title: "Start", value: session.confirmedSleepStartAt.formatted(date: .omitted, time: .shortened))
                        SleepMiniMetric(title: "Wake", value: session.wakeAt.formatted(date: .omitted, time: .shortened))
                    }

                    SleepMiniMetric(title: "Quality", value: session.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "Not rated")

                    if let stageBreakdown, stageBreakdown.hasStages {
                        SleepStageBreakdownView(breakdown: stageBreakdown)
                            .accessibilityIdentifier("sleep-detail-stage-breakdown")
                    } else if session.source == .appleHealth {
                        Text("Apple Health stage detail is unavailable for this record. Peakline preserves the sleep interval without inventing stage values.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sleep-detail-stage-breakdown-unavailable")
                    }
                }
            }

            if !session.tags.isEmpty {
                SleepCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Context")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        FlowLayout(spacing: 8) {
                            ForEach(session.tags) { tag in
                                Text(tag.displayName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                            }
                        }
                    }
                }
            }

            SleepCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session quality: \(qualityScore)")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(readinessIsProvisional
                        ? "Sleep score is recorded; readiness guidance waits for more evidence."
                        : "Estimated training support: \(SleepCoachingService().historyImpact(for: qualityScore))")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SleepCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session Details")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    HStack(spacing: 10) {
                        SleepMiniMetric(title: "Source", value: session.source.displayName)
                        SleepMiniMetric(title: "Confidence", value: session.confidence.displayName)
                    }

                    SleepMiniMetric(title: "Created", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            SleepActionButton(title: "Edit Sleep Session", systemImage: "pencil", style: .primary) {
                showingEditor = true
            }
            .disabled(session.source == .appleHealth)
            .accessibilityIdentifier("sleep-detail-edit")

            if session.source == .appleHealth {
                Text("Apple Health imported sleep is read-only in Peakline for now.")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            Menu {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                .accessibilityIdentifier("sleep-detail-delete")
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.textSecondary)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.colors.cardBorder, lineWidth: 1)
            }
            .accessibilityLabel("Sleep session actions")
            .accessibilityIdentifier("sleep-detail-actions")

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep-detail-error")
            }
        }
        .navigationTitle("Sleep Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            SleepSessionEditorView(mode: .edit(session))
        }
        .onChange(of: session.updatedAt) { _, _ in
            refreshQualityScore()
        }
        .alert("Delete sleep session?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                do {
                    try repository.delete(session, in: modelContext)
                    dismiss()
                } catch {
                    errorMessage = "Couldn’t delete this sleep session. \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove it from your sleep trends and recovery score.")
        }
    }

    private func refreshQualityScore() {
        qualityScore = SleepScoringService().score(
            for: session,
            recentSessions: recentSessions,
            settings: SleepSettingsStore().load()
        )
    }
}

struct SleepSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @ObservedObject private var healthKitExportStatus = SleepHealthKitExportStatusStore.shared

    @Binding var settings: SleepSettings
    @State private var healthStatus: String?
    @State private var isRequestingHealth = false
    @State private var notificationStatus: String?
    @State private var isRequestingNotifications = false

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Sleep Settings",
                subtitle: "Keep recovery coaching transparent.",
                systemImage: "slider.horizontal.3"
            ) {
                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Default wind-down")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                            ForEach(SleepSettings.windDownOptions, id: \.self) { minutes in
                                FilterChip("\(minutes)m", systemImage: "timer", isSelected: settings.defaultWindDownMinutes == minutes) {
                                    settings.defaultWindDownMinutes = minutes
                                }
                            }
                        }

                        Text("Target sleep")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                            ForEach(SleepSettings.targetHourOptions, id: \.self) { hours in
                                FilterChip("\(hours)h", systemImage: "target", isSelected: settings.targetSleepMinutes == hours * 60) {
                                    settings.targetSleepMinutes = hours * 60
                                }
                            }
                        }
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Preferred Sleep Source")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Menu {
                            ForEach(PreferredSleepSource.allCases) { source in
                                Button {
                                    settings.preferredSource = source
                                } label: {
                                    if settings.preferredSource == source {
                                        Label(source.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(source.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(settings.preferredSource.displayName)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
                        }
                        .accessibilityLabel("Preferred sleep source")
                        .accessibilityValue(settings.preferredSource.displayName)
                        .accessibilityIdentifier("sleep-settings-preferred-source")

                        Text("Automatic uses Apple Health when it is reliable, keeps Sleep Mode ratings and notes, and falls back gracefully when data is missing.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SleepCard(padding: 12) {
                    VStack(spacing: 0) {
                        SleepToggleRow(title: "Recovery coaching", subtitle: "Use sleep score in training guidance.", systemImage: "sparkles", isOn: $settings.recoveryCoachingEnabled)
                            .accessibilityIdentifier("sleep-settings-recovery-coaching")
                        SleepSettingsDivider()
                        SleepToggleRow(title: "Apple Health import", subtitle: "Read sleep analysis when authorised.", systemImage: "heart.text.square", isOn: $settings.enableAppleHealthImport)
                            .disabled(!HealthKitSleepService().isAvailable)
                            .accessibilityIdentifier("sleep-settings-health-import")
                        SleepSettingsDivider()
                        SleepToggleRow(title: "Save Sleep to Apple Health", subtitle: "Save confirmed Sleep Mode sessions as simple estimated sleep.", systemImage: "square.and.arrow.up", isOn: $settings.enableAppleHealthExport)
                            .disabled(!HealthKitSleepService().isAvailable)
                            .accessibilityIdentifier("sleep-settings-health-export")
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(healthTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(healthDescription)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SleepActionButton(
                            title: HealthKitSleepService().isAvailable ? "Request Sleep Access" : "Apple Health Unavailable",
                            systemImage: "lock.open",
                            style: .primary
                        ) {
                            Task { await requestHealthAccess() }
                        }
                        .disabled(isRequestingHealth || !HealthKitSleepService().isAvailable)
                        .accessibilityIdentifier("sleep-settings-health-request")

                        if let healthStatus {
                            Text(healthStatus)
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("sleep-settings-health-status")
                        }

                        if let exportStatus = healthKitExportStatus.message {
                            Text(exportStatus)
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Apple Health export status")
                                .accessibilityValue(exportStatus)
                                .accessibilityIdentifier("sleep-settings-health-export-status")
                        }
                    }
                }

                sleepNotificationSettingsCard
                advancedCoachingSettingsCard
            }
            .navigationTitle("Sleep Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("sleep-settings-done")
                }
            }
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    private var sleepNotificationSettingsCard: some View {
        DashboardSection(title: "Sleep Notifications") {
            SleepCard {
                VStack(alignment: .leading, spacing: 16) {
                    SleepRow(
                        title: settings.notificationPreferences.isEnabled ? "Sleep Notifications On" : "Enable sleep reminders?",
                        subtitle: "We'll remind you to start Sleep Mode and confirm your wake time so recovery guidance stays accurate.",
                        systemImage: "bell.badge.fill"
                    )

                    HStack(spacing: 10) {
                        SleepActionButton(
                            title: settings.notificationPreferences.isEnabled ? "Turn Off" : "Enable Reminders",
                            systemImage: settings.notificationPreferences.isEnabled ? "bell.slash" : "bell",
                            style: .primary
                        ) {
                            Task { await toggleSleepNotifications() }
                        }
                        .disabled(isRequestingNotifications)
                        .accessibilityIdentifier("sleep-settings-notifications")
                    }

                    if let notificationStatus {
                        Text(notificationStatus)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SleepSettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Night Reminders")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        SleepToggleRow(title: "Bedtime Reminder", subtitle: "Get a reminder to start Sleep Mode before your usual bedtime.", systemImage: "moon.zzz", isOn: $settings.notificationPreferences.bedtimeReminderEnabled)
                        DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                            .disabled(!settings.notificationPreferences.isEnabled || !settings.notificationPreferences.bedtimeReminderEnabled)

                        SleepToggleRow(title: "Wind-Down Reminder", subtitle: "A quieter nudge before your bedtime reminder.", systemImage: "timer", isOn: $settings.notificationPreferences.windDownReminderEnabled)
                        windDownOffsetControl
                    }

                    SleepSettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Morning Reminders")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        SleepToggleRow(title: "Morning Confirmation", subtitle: "Review your wake time to update today's recovery score.", systemImage: "sun.max", isOn: $settings.notificationPreferences.morningConfirmationEnabled)
                        DatePicker("Morning time", selection: morningBinding, displayedComponents: .hourAndMinute)
                            .disabled(!settings.notificationPreferences.isEnabled || !settings.notificationPreferences.morningConfirmationEnabled)

                        SleepToggleRow(title: "Missed Sleep Reminder", subtitle: "Backfill last night when sleep is usually part of your routine.", systemImage: "square.and.pencil", isOn: $settings.notificationPreferences.missedSleepReminderEnabled)
                    }

                    SleepSettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Smart Coaching")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        SleepToggleRow(title: "Training-Aware Sleep Reminders", subtitle: "Nudge sleep before likely training days.", systemImage: "figure.strengthtraining.traditional", isOn: $settings.notificationPreferences.trainingAwareRemindersEnabled)
                        SleepToggleRow(title: "Recovery Coaching Notifications", subtitle: "Notify when a meaningful recovery update is ready.", systemImage: "sparkles", isOn: $settings.notificationPreferences.recoveryCoachingNotificationsEnabled)
                    }

                    SleepSettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quiet Days")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        FlowLayout(spacing: 8) {
                            ForEach(weekdayOptions, id: \.weekday) { option in
                                FilterChip(option.label, systemImage: "bell.slash", isSelected: settings.notificationPreferences.quietWeekdays.contains(option.weekday)) {
                                    toggleQuietWeekday(option.weekday)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var windDownOffsetControl: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Wind-down offset", selection: $settings.notificationPreferences.windDownOffsetMinutes) {
                ForEach(SleepNotificationPreferences.windDownOffsetOptions, id: \.self) { minutes in
                    Text("\(minutes)m before").tag(minutes)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                ForEach(SleepNotificationPreferences.windDownOffsetOptions, id: \.self) { minutes in
                    Button {
                        settings.notificationPreferences.windDownOffsetMinutes = minutes
                    } label: {
                        if settings.notificationPreferences.windDownOffsetMinutes == minutes {
                            Label("\(minutes)m before", systemImage: "checkmark")
                        } else {
                            Text("\(minutes)m before")
                        }
                    }
                }
            } label: {
                HStack {
                    Text("\(settings.notificationPreferences.windDownOffsetMinutes)m before")
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
            }
            .accessibilityLabel("Wind-down offset")
            .accessibilityValue("\(settings.notificationPreferences.windDownOffsetMinutes) minutes before")
        }
        .disabled(!settings.notificationPreferences.isEnabled || !settings.notificationPreferences.windDownReminderEnabled)
        .accessibilityIdentifier("sleep-settings-winddown-offset")
    }

    private var advancedCoachingSettingsCard: some View {
        DashboardSection(title: "Sleep Coaching") {
            SleepCard(padding: 12) {
                VStack(spacing: 0) {
                    SleepToggleRow(
                        title: "Sleep Coaching Insights",
                        subtitle: "Show personalised sleep and training patterns when there is enough history.",
                        systemImage: "sparkles",
                        isOn: $settings.coachingPreferences.sleepCoachingInsightsEnabled
                    )

                    SleepSettingsDivider()

                    SleepToggleRow(
                        title: "Adaptive Workout Recommendations",
                        subtitle: "Adjust today's training guidance using sleep, recovery, and recent performance.",
                        systemImage: "figure.strengthtraining.traditional",
                        isOn: $settings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled
                    )

                    SleepSettingsDivider()

                    SleepToggleRow(
                        title: "Deload Suggestions",
                        subtitle: "Suggest lighter training when poor recovery signals accumulate.",
                        systemImage: "arrow.down.forward.circle",
                        isOn: $settings.coachingPreferences.deloadSuggestionsEnabled
                    )

                    SleepSettingsDivider()

                    SleepToggleRow(
                        title: "Show Sleep-Performance Insights",
                        subtitle: "Compare sleep before workouts with volume, completion, and performance trends.",
                        systemImage: "chart.xyaxis.line",
                        isOn: $settings.coachingPreferences.sleepPerformanceInsightsEnabled
                    )
                }
            }
        }
    }

    private var healthTitle: String {
        if !HealthKitSleepService().isAvailable {
            return "Apple Health unavailable"
        }
        return "Apple Health sleep access"
    }

    private var healthDescription: String {
        if !HealthKitSleepService().isAvailable {
            return "This device does not support HealthKit sleep access."
        }

        let preferenceSummary: String
        switch (settings.enableAppleHealthImport, settings.enableAppleHealthExport) {
        case (true, true):
            preferenceSummary = "Apple Health import and saving confirmed sleep are enabled."
        case (true, false):
            preferenceSummary = "Apple Health import is enabled. Saving confirmed sleep is off."
        case (false, true):
            preferenceSummary = "Apple Health import is off. Saving confirmed sleep is enabled."
        case (false, false):
            preferenceSummary = "Apple Health import and saving confirmed sleep are off."
        }

        if let healthStatus {
            return "\(preferenceSummary) Current authorization result: \(healthStatus)"
        }
        return "\(preferenceSummary) Authorization is unverified until you request access below; a preference does not confirm permission."
    }

    private var bedtimeBinding: Binding<Date> {
        Binding {
            date(from: settings.notificationPreferences.bedtimeReminderTime)
        } set: { value in
            settings.notificationPreferences.bedtimeReminderTime = Calendar.current.dateComponents([.hour, .minute], from: value)
        }
    }

    private var morningBinding: Binding<Date> {
        Binding {
            date(from: settings.notificationPreferences.morningConfirmationTime)
        } set: { value in
            settings.notificationPreferences.morningConfirmationTime = Calendar.current.dateComponents([.hour, .minute], from: value)
        }
    }

    private var weekdayOptions: [(weekday: Int, label: String)] {
        [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
    }

    private func requestHealthAccess() async {
        isRequestingHealth = true
        defer { isRequestingHealth = false }
        UserDefaults.standard.set(true, forKey: healthKitSleepAuthorizationRequestedKey)

        do {
            if !settings.enableAppleHealthImport && !settings.enableAppleHealthExport {
                settings.enableAppleHealthImport = true
            }
            let access = try await HealthKitSleepService().requestAuthorization(
                read: settings.enableAppleHealthImport,
                write: settings.enableAppleHealthExport
            )
            healthStatus = healthAccessStatus(for: access)
        } catch {
            healthStatus = error.localizedDescription
        }
    }

    private func healthAccessStatus(for access: HealthKitSleepAccessSnapshot) -> String {
        var statuses: [String] = []

        if settings.enableAppleHealthImport {
            switch access.read {
            case .unavailable:
                statuses.append("Apple Health read access is unavailable.")
            case .notDetermined:
                statuses.append("Apple Health read access was not requested.")
            case .denied:
                statuses.append("Apple Health read access was denied. Review access in the Health app.")
            case .restricted:
                statuses.append("Apple Health read access is restricted on this device.")
            case .enabledUnverified, .authorized:
                statuses.append("Read access was requested. Apple Health keeps read permission private; Peakline will verify it when the next import succeeds.")
            }
        }

        if settings.enableAppleHealthExport {
            switch access.write {
            case .unavailable:
                statuses.append("Apple Health save access is unavailable.")
            case .notDetermined:
                statuses.append("Apple Health save access was not requested.")
            case .denied:
                statuses.append("Apple Health save access was denied. Confirm the permission in the Health app before exporting.")
            case .restricted:
                statuses.append("Apple Health save access is restricted on this device.")
            case .enabledUnverified:
                statuses.append("Apple Health save access was requested, but its state is not verified.")
            case .authorized:
                statuses.append("Apple Health save access is authorized.")
            }
        }

        return statuses.isEmpty ? access.displayName : statuses.joined(separator: " ")
    }

    private func toggleSleepNotifications() async {
        if settings.notificationPreferences.isEnabled {
            settings.notificationPreferences.isEnabled = false
            await SleepNotificationScheduler().cancelSleepNotificationsAsync()
            notificationStatus = "Sleep reminders are off."
            return
        }

        isRequestingNotifications = true
        defer { isRequestingNotifications = false }

        do {
            let status = try await SleepNotificationService().requestAuthorization()
            settings.notificationPreferences.isEnabled = true
            notificationStatus = status == .provisional ? "Sleep reminders are enabled provisionally." : "Sleep reminders are enabled."
        } catch {
            notificationStatus = "Notifications are off. Enable notifications in iOS Settings to receive sleep reminders."
        }
    }

    private func refreshNotificationStatus() async {
        let status = await SleepNotificationService().authorizationStatus()
        switch status {
        case .authorized:
            notificationStatus = "Notifications are allowed."
        case .provisional:
            notificationStatus = "Notifications are allowed quietly."
        case .denied:
            notificationStatus = "Notifications are off. Enable notifications in iOS Settings to receive sleep reminders."
        case .notDetermined:
            notificationStatus = "Permission will be requested when you enable reminders."
        case .ephemeral:
            notificationStatus = "Notifications are available for this session."
        @unknown default:
            notificationStatus = "Notification permission status is unavailable."
        }
    }

    private func date(from components: DateComponents) -> Date {
        Calendar.current.date(
            bySettingHour: components.hour ?? 22,
            minute: components.minute ?? 30,
            second: 0,
            of: .now
        ) ?? .now
    }

    private func toggleQuietWeekday(_ weekday: Int) {
        if settings.notificationPreferences.quietWeekdays.contains(weekday) {
            settings.notificationPreferences.quietWeekdays.removeAll { $0 == weekday }
        } else {
            settings.notificationPreferences.quietWeekdays.append(weekday)
            settings.notificationPreferences.quietWeekdays.sort()
        }
    }
}

struct SleepSettingsStandaloneView: View {
    @State private var settings = SleepSettingsStore().load()
    private let store = SleepSettingsStore()

    var body: some View {
        SleepSettingsView(settings: $settings)
            .onChange(of: settings) { _, newValue in
                store.save(newValue)
            }
    }
}

private struct SleepCard<Content: View>: View {
    var style: FitnessCardStyle = .standard
    var padding: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        FitnessCard(style: style, padding: padding) {
            content()
        }
    }
}

private struct SleepIcon: View {
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color?

    var body: some View {
        FitnessIconBadge(systemImage: systemImage, size: size, tint: tint)
    }
}

private struct SleepRow<Trailing: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color?
    var showsChevron = false
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color? = nil,
        showsChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.showsChevron = showsChevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SleepIcon(systemImage: systemImage, size: appTheme.metrics.rowIconSize, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailing()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct SleepQuietAction: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget)
                .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }
}

private struct SleepActionButton: View {
    enum Style {
        case primary
        case secondary
        case neutral
        case danger
    }

    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(labelFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: appTheme.metrics.buttonHeight)
                .frame(maxWidth: .infinity)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }

    private var labelFont: Font {
        switch style {
        case .primary:
            return .headline.weight(.semibold)
        case .secondary, .neutral, .danger:
            return .subheadline.weight(.semibold)
        }
    }

    private var horizontalPadding: CGFloat {
        style == .primary ? 16 : 10
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return appTheme.colors.accentForeground
        case .secondary:
            return appTheme.colors.textPrimary
        case .neutral:
            return appTheme.colors.textSecondary
        case .danger:
            return .white
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent
        case .secondary, .neutral:
            return appTheme.colors.cardBackgroundElevated
        case .danger:
            return appTheme.colors.danger
        }
    }

    private var border: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent.opacity(0.45)
        case .secondary, .neutral:
            return appTheme.colors.cardBorder
        case .danger:
            return appTheme.colors.danger.opacity(0.45)
        }
    }
}

private struct SleepMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(tint ?? appTheme.colors.textSecondary)

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct SleepDurationBar: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    let summary: SleepSummary
    let targetMinutes: Int

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                let maxHeight = proxy.size.height
                let ratio = min(1.15, Double(summary.totalSleepMinutes) / Double(max(1, targetMinutes)))
                let height = max(8, maxHeight * ratio / 1.15)

                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(barColor)
                        .frame(height: summary.totalSleepMinutes > 0 ? (hasAppeared || reduceMotion ? height : 8) : 8)
                        .animation(AppMotion.progressFill(reduceMotion: reduceMotion), value: hasAppeared)
                }
            }

            Text(summary.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            hasAppeared = true
        }
    }

    private var barColor: Color {
        if summary.totalSleepMinutes == 0 {
            return appTheme.colors.cardBackgroundElevated
        }

        if summary.totalSleepMinutes < 360 {
            return appTheme.colors.warning
        }

        return appTheme.colors.accent
    }

    private var accessibilityLabel: String {
        let day = summary.date.formatted(.dateTime.weekday(.wide))
        guard summary.primarySession != nil else {
            return "\(day), no sleep data."
        }

        let targetCopy = summary.totalSleepMinutes < targetMinutes ? "below target" : "on target"
        return "\(day), \(SleepScoringService.durationText(minutes: summary.totalSleepMinutes)) sleep, \(targetCopy)."
    }
}

private struct SleepHistoryRow: View {
    @Environment(\.appTheme) private var appTheme

    let session: SleepSession
    let qualityScore: Int
    let readinessIsProvisional: Bool

    var body: some View {
        SleepCard(style: .compact, padding: 16) {
            SleepRow(
                title: SleepCalendar.displayTitle(for: session.nightDate),
                subtitle: subtitle,
                systemImage: session.source == .appleHealth ? "heart.text.square.fill" : "moon.zzz.fill",
                showsChevron: true
            ) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session quality")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .multilineTextAlignment(.trailing)

                    Text("\(qualityScore)")
                        .font(.headline.bold())
                        .foregroundStyle(appTheme.colors.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Session quality \(qualityScore) out of 100")
            }
        }
    }

    private var subtitle: String {
        let metadata = PeaklineText.joinedMetadata([
            SleepScoringService.durationText(minutes: session.durationMinutes),
            session.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality",
            session.source.displayName
        ])
        if readinessIsProvisional {
            return "\(metadata). Sleep score is recorded; readiness guidance waits for more evidence."
        }
        return "\(metadata). Estimated training support: \(SleepCoachingService().historyImpact(for: qualityScore))"
    }
}

private struct SleepMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        SleepMetric(title: title, value: value)
    }
}

private struct SleepCoachingInsightCard: View {
    @Environment(\.appTheme) private var appTheme

    let insight: SleepCoachingInsight

    var body: some View {
        SleepCard(style: .compact) {
            SleepRow(
                title: insight.title,
                subtitle: insightSubtitle,
                systemImage: systemImage,
                tint: tint
                ) {
                    Text(insight.confidence.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
            }
        }
    }

    private var insightSubtitle: String {
        if insight.basedOn.isEmpty {
            return insight.message
        }

        return "\(insight.message) Based on: \(insight.basedOn.map(\.displayName).joined(separator: ", "))."
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return appTheme.colors.success
        case .neutral:
            return appTheme.colors.accent
        case .caution:
            return appTheme.colors.warning
        case .important:
            return appTheme.colors.danger
        }
    }

    private var systemImage: String {
        switch insight.type {
        case .sleepImprovesPerformance, .goodSleepBeforeStrongSession, .recoveryTrendImproving:
            return "chart.line.uptrend.xyaxis"
        case .poorSleepReducesPerformance, .sleepDebtAccumulating, .recoveryTrendDeclining:
            return "exclamationmark.triangle.fill"
        case .deloadSuggested:
            return "arrow.down.forward.circle.fill"
        case .lateWorkoutAffectsSleep, .bedtimeConsistencyOpportunity:
            return "clock.fill"
        case .consistentSleepImprovesRecovery:
            return "checkmark.seal.fill"
        case .poorSleepBeforeMissedSession:
            return "calendar.badge.exclamationmark"
        case .notEnoughData, .missingSleepData, .missingWorkoutData:
            return "sparkles"
        }
    }
}

private struct SleepStageBreakdownView: View {
    @Environment(\.appTheme) private var appTheme

    let breakdown: SleepStageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Health stages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                if let awakeMinutes = breakdown.awakeMinutes {
                    SleepMiniMetric(title: "Awake", value: SleepScoringService.durationText(minutes: awakeMinutes))
                }
                if let remMinutes = breakdown.remMinutes {
                    SleepMiniMetric(title: "REM", value: SleepScoringService.durationText(minutes: remMinutes))
                }
                if let coreMinutes = breakdown.coreMinutes {
                    SleepMiniMetric(title: "Core", value: SleepScoringService.durationText(minutes: coreMinutes))
                }
                if let deepMinutes = breakdown.deepMinutes {
                    SleepMiniMetric(title: "Deep", value: SleepScoringService.durationText(minutes: deepMinutes))
                }
            }
        }
    }
}

struct SleepQualityPicker: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: Int?

    var body: some View {
        Menu {
            Button {
                update(nil)
            } label: {
                if selection == nil {
                    Label("Not rated", systemImage: "checkmark")
                } else {
                    Text("Not rated")
                }
            }

            ForEach(1...5, id: \.self) { value in
                Button {
                    update(value)
                } label: {
                    if selection == value {
                        Label(Self.label(for: value), systemImage: "checkmark")
                    } else {
                        Text(Self.label(for: value))
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep quality")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Text(selection.map(Self.label) ?? "Not rated")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
        }
        .accessibilityLabel("Sleep quality")
        .accessibilityValue(selection.map(Self.label) ?? "Not rated")
        .accessibilityIdentifier("sleep-quality-picker")
    }

    private func update(_ value: Int?) {
        AppHaptics.selection()
        PerformanceTracer.trace(.motionRatingSelect) {
            withAnimation(AppMotion.ratingSelect(reduceMotion: reduceMotion)) {
                selection = value
            }
        }
    }

    static func label(for value: Int) -> String {
        switch value {
        case 1:
            return "Very poor"
        case 2:
            return "Poor"
        case 3:
            return "Okay"
        case 4:
            return "Good"
        default:
            return "Excellent"
        }
    }

}

private struct SleepTagPicker: View {
    @Binding var selection: Set<SleepTag>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(SleepTag.allCases) { tag in
                FilterChip(tag.displayName, isSelected: selection.contains(tag)) {
                    if selection.contains(tag) {
                        selection.remove(tag)
                    } else {
                        selection.insert(tag)
                    }
                }
            }
        }
    }
}

private struct SleepToggleRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SleepIcon(systemImage: systemImage, size: appTheme.metrics.rowIconSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

private struct SleepSettingsDivider: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Divider()
            .overlay(appTheme.colors.cardBorder)
            .padding(.leading, 56)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
