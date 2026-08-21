import SwiftData
import SwiftUI

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
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let dashboardErrorMessage {
                Text(dashboardErrorMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sleep-dashboard-error")
            }

            if let exportStatus = healthKitExportStatus.message {
                Text(exportStatus)
                    .font(AppTypography.body)
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
                    .font(AppTypography.chip)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .accessibilityIdentifier("sleep-populated-hero")

                if let stageBreakdown = latestSummary.stageBreakdown, stageBreakdown.hasStages {
                    SleepStageBreakdownView(breakdown: stageBreakdown)
                        .accessibilityIdentifier("sleep-stage-breakdown")
                } else if latestSummary.source == .appleHealth {
                    Text("Apple Health stage detail is unavailable for this record. Peakline preserves the sleep interval without inventing stage values.")
                        .font(AppTypography.metadata)
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
                        .foregroundStyle(appTheme.colors.textAccent)
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
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Spacer(minLength: 8)
                        Text("\(readinessScore.value)/100")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Text(readinessScore.isProvisional ? "Training guidance waits for more evidence." : supportMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(readinessScore.confidenceNote)
                        .font(AppTypography.chip)
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
            .font(AppTypography.metadata)
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
                        .font(AppTypography.chip)
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
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .accessibilityIdentifier("sleep-active-hero")

                        TimelineView(.periodic(from: Date.now, by: 60)) { timeline in
                            Text(activeSleepDescription(for: session, at: timeline.date))
                                .font(AppTypography.body)
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
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Spacer()

                        Text("Target \(SleepScoringService.durationText(minutes: settings.targetSleepMinutes))")
                            .font(AppTypography.chip)
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
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let bed = dashboardSummary.consistencySummary.averageSleepStart, let wake = dashboardSummary.consistencySummary.averageWakeTime {
                        HStack(spacing: 10) {
                            SleepMetric(title: "Bedtime", value: bed.formatted(date: .omitted, time: .shortened), systemImage: "bed.double")
                            SleepMetric(title: "Wake", value: wake.formatted(date: .omitted, time: .shortened), systemImage: "sun.max")
                        }
                    }

                    Text(dashboardSummary.consistencySummary.message)
                        .font(AppTypography.body)
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
                    .font(AppTypography.chip)
                    .foregroundStyle(appTheme.colors.textAccent)
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
                    RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous)
                        .fill(barColor)
                        .frame(height: summary.totalSleepMinutes > 0 ? (hasAppeared || reduceMotion ? height : 8) : 8)
                        .animation(AppMotion.progressFill(reduceMotion: reduceMotion), value: hasAppeared)
                }
            }

            Text(summary.date.formatted(.dateTime.weekday(.narrow)))
                .font(AppTypography.badge)
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
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .multilineTextAlignment(.trailing)

                    Text("\(qualityScore)")
                        .font(.headline.bold())
                        .foregroundStyle(appTheme.colors.textAccent)
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
                        .font(AppTypography.badge)
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

