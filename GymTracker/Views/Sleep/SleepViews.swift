import SwiftData
import SwiftUI

struct SleepDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

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
    @State private var showingSleepMode = false
    @State private var showingManualEntry = false
    @State private var showingNapEntry = false
    @State private var showingNapTimer = false
    @State private var showingSettings = false
    @State private var confirmationSession: SleepSession?
    @State private var pendingDiscardSession: SleepSession?
    @State private var importedCount: Int?
    @State private var summaries: [SleepSummary] = []
    @State private var latestSummary = SleepScoringService.emptySummary()
    @State private var dashboardSummary = SleepAnalyticsService.emptyDashboardSummary()
    @State private var lastAnalyticsSignature: SleepAnalyticsInputSignature?
    @State private var readinessScore = CoachIntelligenceService.emptySnapshot().readiness
    @State private var lastReadinessSignature: String?
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()

    private let repository = SleepSessionRepository()
    private let scoring = SleepScoringService()
    private let coaching = SleepCoachingService()
    private let coachIntelligence = CoachIntelligenceService()
    private let settingsStore = SleepSettingsStore()
    private let analyticsStore = SleepAnalyticsSnapshotStore.shared
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()

    init() {
        _sessions = Query(Self.sessionsDescriptor)
        _workouts = Query(Self.workoutsDescriptor)
        _naps = Query(Self.napsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _foodLogEntries = Query(Self.foodLogEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
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
        sessions.filter { $0.status == .completed }
    }

    private var activeSession: SleepSession? {
        sessions.first { $0.status == .active }
    }

    private var currentAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sessions, naps: naps, workouts: workouts, settings: settings)
    }

    private var currentReadinessSignature: String {
        [
            signature(sessions, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.status.rawValue)" },
            signature(naps, limit: 90) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(workouts, limit: 40) { session in
                let setSignature = session.exerciseLogs
                    .flatMap(\.setLogs)
                    .map { "\($0.id.uuidString):\($0.completed):\($0.isWarmup):\($0.weight):\($0.reps)" }
                    .joined(separator: ",")
                return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(setSignature)"
            },
            signature(hydrationEntries, limit: 120) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(foodLogEntries, limit: 200) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            signature(coachCheckIns, limit: 30) { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
            "\(settings.targetSleepMinutes):\(settings.recoveryCoachingEnabled):\(settings.preferredSource.rawValue)",
            "\(hydrationTargetML)",
            "\(nutritionGoal.updatedAt.timeIntervalSince1970)"
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
        FitnessScreen(
            title: "Sleep",
            subtitle: "Recovery & readiness.",
            systemImage: "moon.zzz.fill"
        ) {
            if let activeSession {
                activeSleepCard(activeSession)
            } else {
                recoveryCard
                DashboardSection(title: "Coach Context") {
                    ReadinessContextCard(
                        readiness: readinessScore,
                        focus: .sleep,
                        title: "Sleep in today's readiness"
                    )
                }
                startCard
                appleHealthConnectionCard
            }

            weeklyChartCard
            napsSection
            consistencyAndDebt
            trainingInsightCard
            coachingInsightsSection
            historySection
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Sleep settings")
            }
        }
        .sheet(isPresented: $showingSleepMode) {
            SleepModeView(settings: $settings)
        }
        .sheet(isPresented: $showingManualEntry) {
            SleepSessionEditorView(mode: .manual)
        }
        .sheet(isPresented: $showingNapEntry) {
            NapSessionEditorView()
        }
        .sheet(isPresented: $showingNapTimer) {
            NapTimerView()
        }
        .sheet(item: $confirmationSession) { session in
            SleepMorningConfirmationView(session: session)
        }
        .sheet(isPresented: $showingSettings) {
            SleepSettingsView(settings: $settings)
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
            settings = settingsStore.load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            maybePromptForWakeTime()
            DispatchQueue.main.async {
                refreshSleepAnalytics()
                refreshReadinessScore()
                Task { @MainActor in await importSleepIfEnabled() }
            }
        }
        .onChange(of: currentAnalyticsSignature) { _, _ in
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
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: newValue, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
        }
    }

    private var recoveryCard: some View {
        SleepGlassCard(style: .hero) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    SleepIconTile(systemImage: "moon.stars.fill", size: 50)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sleep Recovery")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(summaryMetadataText)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if let score = latestSummary.sleepScore {
                        SleepScoreBadge(score: score)
                    }
                }

                Text(latestSummary.primarySession == nil ? "No sleep data yet" : SleepScoringService.durationText(minutes: latestSummary.totalSleepMinutes))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                VStack(alignment: .leading, spacing: 8) {
                    SleepStatusChip(title: recoveryActionTitle, state: latestSummary.recoveryState)

                    Text(dashboardSummary.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(appTheme.metrics.compactCardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous)
                        .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                }

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

                if latestSummary.primarySession != nil, latestSummary.qualityRating == nil {
                    Text("Add a sleep quality rating to improve recovery coaching.")
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let conflict = dashboardSummary.sourceConflict {
                    Text(conflict.displayMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let stages = latestSummary.stageBreakdown, stages.hasStages {
                    SleepStageBreakdownView(breakdown: stages)
                }
            }
        }
    }

    private var appleHealthConnectionCard: some View {
        SleepGlassCard(style: .compact) {
            SleepGlassRow(
                title: appleHealthTitle,
                subtitle: appleHealthSubtitle,
                systemImage: "heart.text.square.fill"
            )
        }
    }

    private var appleHealthTitle: String {
        if !HealthKitSleepService().isAvailable {
            return "Apple Health unavailable"
        }
        return settings.enableAppleHealthImport ? "Apple Health Connected" : "Connect Apple Health"
    }

    private var appleHealthSubtitle: String {
        if !HealthKitSleepService().isAvailable {
            return "This device does not support HealthKit sleep access."
        }
        if settings.enableAppleHealthImport {
            if let lastSync = settings.lastHealthKitSleepSyncAt {
                return "Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened)). Sleep data improves recovery scoring."
            }
            return "Sleep data improves recovery scoring."
        }
        return "Import sleep data automatically to improve recovery scoring."
    }

    private var summaryMetadataText: String {
        guard latestSummary.primarySession != nil else {
            return "Start Sleep Mode tonight to improve recovery coaching."
        }

        let quality = latestSummary.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality rating"
        let source = latestSummary.source?.displayName ?? "Sleep"
        return "\(quality) quality - \(source)"
    }

    private var startCard: some View {
        SleepGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SleepGlassRow(
                    title: "Sleep Mode",
                    subtitle: "Sleep start is estimated from your wind-down timer. You can edit it in the morning.",
                    systemImage: "bed.double.fill"
                )

                SleepActionButton(
                    title: "Start Sleep Mode",
                    systemImage: "moon.zzz.fill",
                    style: .primary
                ) {
                    showingSleepMode = true
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sleepSecondaryActions
                    }

                    VStack(spacing: 10) {
                        sleepSecondaryActions
                    }
                }
            }
        }
    }

    private func activeSleepCard(_ session: SleepSession) -> some View {
        SleepGlassCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    SleepIconTile(systemImage: "moon.zzz.fill", size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sleep Mode Active")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(activeSleepDescription(for: session))
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
    private var sleepSecondaryActions: some View {
        SleepActionButton(
            title: "Log Nap",
            systemImage: "plus.circle.fill",
            style: .secondary
        ) {
            showingNapEntry = true
        }

        SleepActionButton(
            title: "Nap Timer",
            systemImage: "timer",
            style: .secondary
        ) {
            showingNapTimer = true
        }

        SleepActionButton(
            title: "Manual Entry",
            systemImage: "square.and.pencil",
            style: .secondary
        ) {
            showingManualEntry = true
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

        SleepActionButton(
            title: "Discard",
            systemImage: "xmark.circle",
            style: .neutral
        ) {
            pendingDiscardSession = session
        }
        .accessibilityLabel("Discard sleep session")
    }

    private var recoveryActionTitle: String {
        switch latestSummary.recoveryState {
        case .high:
            return "Push progression"
        case .good:
            return "Train normally"
        case .moderate:
            return "Train with caution"
        case .low:
            return "Reduce volume today"
        case .veryLow:
            return "Recovery focus"
        case .unknown:
            return "Track sleep tonight"
        }
    }

    private func activeSleepDescription(for session: SleepSession) -> String {
        let start = session.estimatedSleepStartAt ?? session.confirmedSleepStartAt
        if Date.now < start {
            return "Wind-down is running. Estimated sleep starts at \(start.formatted(date: .omitted, time: .shortened))."
        }

        let minutes = SleepSessionRepository().durationMinutes(start: start, wake: .now)
        return "Estimated sleep so far: \(SleepScoringService.durationText(minutes: minutes)). Confirm or edit wake time when you are up."
    }

    private func discardPendingSleepSession() {
        guard let session = pendingDiscardSession else { return }
        let discardedSessionID = session.id
        try? repository.discard(session, in: modelContext)
        pendingDiscardSession = nil

        let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
        let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
        Task {
            SleepNotificationScheduler().cancelNotifications(for: discardedSessionID)
            await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessionSnapshots, workouts: workoutSnapshots)
        }
    }

    private var weeklyChartCard: some View {
        DashboardSection(title: "Last 7 Days") {
            SleepGlassCard {
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
                if dashboardSummary.recentNaps.isEmpty {
                    SleepGlassCard(style: .compact) {
                        SleepGlassRow(
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
            SleepGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SleepGlassMetricTile(title: "Sleep Debt", value: sleepDebtHeadline, systemImage: "moon.zzz")
                        SleepGlassMetricTile(title: "Consistency", value: dashboardSummary.consistencySummary.displayName, systemImage: "calendar")
                    }

                    Text(sleepDebtCopy)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let bed = dashboardSummary.consistencySummary.averageSleepStart, let wake = dashboardSummary.consistencySummary.averageWakeTime {
                        HStack(spacing: 10) {
                            SleepGlassMetricTile(title: "Bedtime", value: bed.formatted(date: .omitted, time: .shortened), systemImage: "bed.double")
                            SleepGlassMetricTile(title: "Wake", value: wake.formatted(date: .omitted, time: .shortened), systemImage: "sun.max")
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
            SleepGlassCard(style: .compact) {
                SleepGlassRow(
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
                if let recommendation = dashboardSummary.adaptiveRecommendation {
                    SleepAdaptiveRecommendationCard(recommendation: recommendation)
                }

                if dashboardSummary.coachingInsights.isEmpty {
                    SleepGlassCard(style: .compact) {
                        SleepGlassRow(
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
                SleepGlassCard(style: .compact) {
                    SleepGlassRow(
                        title: "No sleep data yet",
                        subtitle: "Start Sleep Mode tonight to help the app understand your recovery.",
                        systemImage: "moon.zzz"
                    )
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(completedSessions.prefix(14)) { session in
                        NavigationLink {
                            SleepSessionDetailView(session: session)
                        } label: {
                            SleepHistoryRow(session: session, score: scoring.score(for: session, recentSessions: completedSessions, settings: settings))
                        }
                        .buttonStyle(.plain)
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

    private func maybePromptForWakeTime() {
        guard let activeSession else { return }
        let sleepStart = activeSession.estimatedSleepStartAt ?? activeSession.confirmedSleepStartAt
        if Date.now.timeIntervalSince(sleepStart) >= 60 * 60 {
            confirmationSession = activeSession
        }
    }

    private func refreshSleepAnalytics(force: Bool = false) {
        let signature = currentAnalyticsSignature
        guard force || signature != lastAnalyticsSignature else { return }

        let snapshot = analyticsStore.snapshot(sessions: sessions, naps: naps, workouts: workouts, settings: settings, force: force)
        summaries = snapshot.summaries
        latestSummary = snapshot.latestSummary
        dashboardSummary = snapshot.dashboardSummary
        lastAnalyticsSignature = signature
    }

    private func refreshReadinessScore(force: Bool = false) {
        let signature = currentReadinessSignature
        guard force || signature != lastReadinessSignature else { return }

        readinessScore = coachIntelligence.readiness(
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
        lastReadinessSignature = signature
    }

    private func signature<Value>(_ values: [Value], limit: Int, transform: (Value) -> String) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
    }

    @MainActor
    private func importSleepIfEnabled() async {
        guard settings.enableAppleHealthImport else { return }
        if let lastSync = settings.lastHealthKitSleepSyncAt, Date.now.timeIntervalSince(lastSync) < 30 * 60 {
            return
        }

        let count = await HealthKitSleepService().importRecentSleep(days: 14, into: modelContext)
        settings = settingsStore.load()
        refreshSleepAnalytics(force: true)
        if count > 0 {
            importedCount = count
        }
        await SleepNotificationScheduler().refreshAllSleepNotifications(
            settings: settings,
            sessions: SleepNotificationScheduler.sessionSnapshots(from: sessions),
            workouts: SleepNotificationScheduler.workoutSnapshots(from: workouts)
        )
    }
}

private struct NapSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let nap: NapSession
    let creditMinutes: String

    var body: some View {
        SleepGlassCard(style: .compact) {
            SleepGlassRow(
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
        let quality = nap.qualityRating.map { " - \(SleepQualityPicker.label(for: $0)) quality" } ?? ""
        return "\(SleepScoringService.durationText(minutes: nap.durationMinutes)) - \(nap.timingCategory.displayName)\(quality). \(creditMinutes)"
    }
}

struct NapSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var start = Date.now.addingTimeInterval(-30 * 60)
    @State private var end = Date.now
    @State private var quality = 3
    @State private var note = ""
    @State private var errorText: String?

    private let repository = NapSessionRepository()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Log Nap",
                subtitle: "Add short recovery sleep without changing overnight data.",
                systemImage: "moonphase.first.quarter"
            ) {
                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SleepGlassRow(
                            title: "Nap Time",
                            subtitle: "Set when the nap started and ended.",
                            systemImage: "clock"
                        )

                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Quality")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                    SleepQualityPicker(selection: $quality)
                    }
                }

                SleepGlassCard {
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
                        .foregroundStyle(appTheme.colors.danger)
                }

                SleepGlassActionButton(title: "Save Nap", systemImage: "checkmark", style: .primary) {
                    saveNap()
                }
            }
            .navigationTitle("Log Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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

    @State private var selectedMinutes = 30
    @State private var startedAt: Date?
    @State private var now = Date.now
    @State private var quality = 3
    @State private var errorText: String?

    private let options = [20, 30, 45, 90]
    private let repository = NapSessionRepository()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Nap Timer",
                subtitle: "Set a short recovery window.",
                systemImage: "timer"
            ) {
                SleepGlassCard(style: .hero) {
                    VStack(alignment: .center, spacing: 14) {
                        SleepGlassIcon(systemImage: startedAt == nil ? "timer" : "moon.zzz.fill", size: 66)

                        Text(timerText)
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()

                        Text(startedAt == nil ? "Ready when you are" : "Nap in progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Timer")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Picker("Timer", selection: $selectedMinutes) {
                            ForEach(options, id: \.self) { minutes in
                                Text("\(minutes)m").tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(startedAt != nil)

                        SleepQualityPicker(selection: $quality)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.danger)
                }

                SleepGlassActionButton(
                    title: startedAt == nil ? "Start Nap Timer" : "Finish Nap",
                    systemImage: startedAt == nil ? "timer" : "checkmark.circle.fill",
                    style: .primary
                ) {
                    if startedAt == nil {
                        startedAt = .now
                    } else {
                        finishNap()
                    }
                }
            }
            .navigationTitle("Nap Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onReceive(timer) { value in
                now = value
            }
        }
    }

    private var timerText: String {
        guard let startedAt else {
            return "\(selectedMinutes):00"
        }

        let elapsed = Int(now.timeIntervalSince(startedAt))
        let remaining = max(0, selectedMinutes * 60 - elapsed)
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
    }

    private func finishNap() {
        guard let startedAt else { return }
        let end = max(Date.now, startedAt.addingTimeInterval(10 * 60))
        do {
            try repository.addNap(start: startedAt, end: end, quality: quality, note: "Nap timer", source: .napTimer, in: modelContext)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct SleepModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sessions: [SleepSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    @Binding var settings: SleepSettings
    @State private var selectedMinutes: Int
    @State private var session: SleepSession?
    @State private var now = Date()
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(settings: Binding<SleepSettings>) {
        self._settings = settings
        self._selectedMinutes = State(initialValue: settings.wrappedValue.defaultWindDownMinutes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.colors.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 18)

                    SleepGlassCard(style: .hero) {
                        VStack(spacing: 18) {
                            SleepGlassIcon(systemImage: "moon.zzz.fill", size: 70)

                            VStack(spacing: 8) {
                                Text("Sleep Mode")
                                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                    .foregroundStyle(appTheme.colors.textPrimary)

                                Text("Wind down now. Sleep tracking will begin soon.")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            countdownRing

                            Text("Estimated sleep start: \(estimatedStart.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    SleepGlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Change Timer")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                                ForEach(SleepSettings.windDownOptions, id: \.self) { minutes in
                                    FilterChip("\(minutes)m", systemImage: "timer", isSelected: minutes == selectedMinutes) {
                                        selectedMinutes = minutes
                                    }
                                }
                            }

                            Text("Sleep start is estimated from your wind-down timer. You can edit it in the morning.")
                                .font(.footnote)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 10) {
                        SleepGlassActionButton(title: "Start Sleep Mode", systemImage: "moon.zzz.fill", style: .primary) {
                            start(minutes: selectedMinutes)
                        }

                        SleepGlassActionButton(title: "Start Now", systemImage: "play.fill", style: .secondary) {
                            start(minutes: 0)
                        }

                        SleepGlassActionButton(title: "Cancel", systemImage: "xmark", style: .neutral) {
                            dismiss()
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.danger)
                    }

                    Spacer(minLength: 18)
                }
                .padding()
            }
            .navigationTitle("Sleep Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { value in
                now = value
            }
        }
    }

    private var estimatedStart: Date {
        Date.now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
    }

    private var remainingSeconds: Int {
        max(0, Int(estimatedStart.timeIntervalSince(now)))
    }

    private var countdownText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(appTheme.colors.cardBackgroundElevated, lineWidth: 14)

            Circle()
                .trim(from: 0, to: selectedMinutes == 0 ? 1 : CGFloat(remainingSeconds) / CGFloat(max(1, selectedMinutes * 60)))
                .stroke(appTheme.colors.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(countdownText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .monospacedDigit()
                    .accessibilityLabel("Wind-down countdown \(countdownText)")
                Text(selectedMinutes == 0 ? "Start now" : "until estimate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 240, height: 240)
    }

    private func start(minutes: Int) {
        do {
            _ = try repository.startSleepMode(windDownMinutes: minutes, in: modelContext)
            settings.defaultWindDownMinutes = minutes == 0 ? settings.defaultWindDownMinutes : minutes
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SleepMorningConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sessions: [SleepSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    let session: SleepSession

    @State private var sleepStart: Date
    @State private var wakeAt: Date
    @State private var qualityRating: Int = 3
    @State private var tags: Set<SleepTag> = []
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(session: SleepSession) {
        self.session = session
        let start = session.estimatedSleepStartAt ?? session.confirmedSleepStartAt
        self._sleepStart = State(initialValue: min(start, Date.now))
        self._wakeAt = State(initialValue: Date.now)
        self._qualityRating = State(initialValue: session.qualityRating ?? 3)
        self._tags = State(initialValue: Set(session.tags))
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Good morning",
                subtitle: "Did you wake up at \(wakeAt.formatted(date: .omitted, time: .shortened))?",
                systemImage: "sun.max.fill"
            ) {
                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Estimated sleep")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(SleepScoringService.durationText(minutes: repository.durationMinutes(start: sleepStart, wake: wakeAt)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        DatePicker("Sleep start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Wake time", selection: $wakeAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How rested do you feel?")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        SleepQualityPicker(selection: $qualityRating)

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
                        .foregroundStyle(appTheme.colors.danger)
                }

                SleepGlassActionButton(title: "Confirm Wake Time", systemImage: "checkmark.seal.fill", style: .primary) {
                    confirm()
                }

                SleepGlassActionButton(title: "Discard Session", systemImage: "trash", style: .neutral) {
                    try? repository.discard(session, in: modelContext)
                    dismiss()
                }
            }
            .navigationTitle("Good morning")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func confirm() {
        do {
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
                Task { @MainActor in
                    if let ids = try? await HealthKitSleepService().writeConfirmedSession(session) {
                        session.healthKitSampleIds = ids
                        try? modelContext.save()
                    }
                }
            }

            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            Task {
                SleepNotificationScheduler().cancelNotifications(for: session.id)
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
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
    @State private var qualityRating: Int = 3
    @State private var tags: Set<SleepTag> = []
    @State private var notes = ""
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .manual:
            let wake = Date.now
            let start = Calendar.current.date(byAdding: .hour, value: -8, to: wake) ?? wake.addingTimeInterval(-28_800)
            self._sleepStart = State(initialValue: start)
            self._wakeAt = State(initialValue: wake)
        case .edit(let session):
            self._sleepStart = State(initialValue: session.confirmedSleepStartAt)
            self._wakeAt = State(initialValue: session.wakeAt)
            self._qualityRating = State(initialValue: session.qualityRating ?? 3)
            self._tags = State(initialValue: Set(session.tags))
            self._notes = State(initialValue: session.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: title,
                subtitle: "Keep sleep data honest and editable.",
                systemImage: "square.and.pencil"
            ) {
                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Sleep start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Wake time", selection: $wakeAt, displayedComponents: [.date, .hourAndMinute])

                        SleepMiniMetric(
                            title: "Duration",
                            value: SleepScoringService.durationText(minutes: repository.durationMinutes(start: sleepStart, wake: wakeAt))
                        )
                    }
                }

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SleepQualityPicker(selection: $qualityRating)
                        SleepTagPicker(selection: $tags)

                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(12)
                            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.danger)
                }

                SleepGlassActionButton(title: "Save Sleep Session", systemImage: "checkmark", style: .primary) {
                    save()
                }
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
}

struct SleepSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let session: SleepSession
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    private let repository = SleepSessionRepository()
    private let scoring = SleepScoringService()

    var body: some View {
        FitnessScreen(
            title: SleepCalendar.displayTitle(for: session.nightDate),
            subtitle: "\(session.source.displayName) - \(session.confidence.displayName)",
            systemImage: "moon.stars.fill"
        ) {
            SleepGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(SleepScoringService.durationText(minutes: session.durationMinutes))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(appTheme.colors.textPrimary)

                    HStack(spacing: 10) {
                        SleepMiniMetric(title: "Start", value: session.confirmedSleepStartAt.formatted(date: .omitted, time: .shortened))
                        SleepMiniMetric(title: "Wake", value: session.wakeAt.formatted(date: .omitted, time: .shortened))
                    }

                    SleepMiniMetric(title: "Quality", value: session.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "Not rated")
                }
            }

            if !session.tags.isEmpty {
                SleepGlassCard {
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

            SleepGlassCard {
                Text("Recovery impact: \(SleepCoachingService().historyImpact(for: scoring.score(for: session, recentSessions: [session], settings: SleepSettingsStore().load())))")
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
            }

            SleepGlassCard {
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

            SleepGlassActionButton(title: "Edit Sleep Session", systemImage: "pencil", style: .primary) {
                showingEditor = true
            }
            .disabled(session.source == .appleHealth)

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
        }
        .navigationTitle("Sleep Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            SleepSessionEditorView(mode: .edit(session))
        }
        .alert("Delete sleep session?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                try? repository.delete(session, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove it from your sleep trends and recovery score.")
        }
    }
}

struct SleepSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

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
                SleepGlassCard {
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

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Preferred Sleep Source")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Picker("Preferred Sleep Source", selection: $settings.preferredSource) {
                            ForEach(PreferredSleepSource.allCases) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Automatic uses Apple Health when it is reliable, keeps Sleep Mode ratings and notes, and falls back gracefully when data is missing.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SleepGlassCard(padding: 12) {
                    VStack(spacing: 0) {
                        SleepToggleRow(title: "Recovery coaching", subtitle: "Use sleep score in training guidance.", systemImage: "sparkles", isOn: $settings.recoveryCoachingEnabled)
                        SleepSettingsDivider()
                        SleepToggleRow(title: "Apple Health import", subtitle: "Read sleep analysis when authorised.", systemImage: "heart.text.square", isOn: $settings.enableAppleHealthImport)
                            .disabled(!HealthKitSleepService().isAvailable)
                        SleepSettingsDivider()
                        SleepToggleRow(title: "Save Sleep to Apple Health", subtitle: "Save confirmed Sleep Mode sessions as simple estimated sleep.", systemImage: "square.and.arrow.up", isOn: $settings.enableAppleHealthExport)
                            .disabled(!HealthKitSleepService().isAvailable)
                    }
                }

                SleepGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(healthTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(healthDescription)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SleepGlassActionButton(
                            title: settings.enableAppleHealthImport || settings.enableAppleHealthExport ? "Request Sleep Access" : "Connect Apple Health",
                            systemImage: "lock.open",
                            style: .primary
                        ) {
                            Task { await requestHealthAccess() }
                        }
                        .disabled(isRequestingHealth || !HealthKitSleepService().isAvailable)

                        if let healthStatus {
                            Text(healthStatus)
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
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
                }
            }
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    private var sleepNotificationSettingsCard: some View {
        DashboardSection(title: "Sleep Notifications") {
            SleepGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    SleepGlassRow(
                        title: settings.notificationPreferences.isEnabled ? "Sleep Notifications On" : "Enable sleep reminders?",
                        subtitle: "We'll remind you to start Sleep Mode and confirm your wake time so recovery guidance stays accurate.",
                        systemImage: "bell.badge.fill"
                    )

                    HStack(spacing: 10) {
                        SleepGlassActionButton(
                            title: settings.notificationPreferences.isEnabled ? "Turn Off" : "Enable Reminders",
                            systemImage: settings.notificationPreferences.isEnabled ? "bell.slash" : "bell",
                            style: .primary
                        ) {
                            Task { await toggleSleepNotifications() }
                        }
                        .disabled(isRequestingNotifications)
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
                        Picker("Wind-down offset", selection: $settings.notificationPreferences.windDownOffsetMinutes) {
                            ForEach(SleepNotificationPreferences.windDownOffsetOptions, id: \.self) { minutes in
                                Text("\(minutes)m before").tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!settings.notificationPreferences.isEnabled || !settings.notificationPreferences.windDownReminderEnabled)
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

    private var advancedCoachingSettingsCard: some View {
        DashboardSection(title: "Sleep Coaching") {
            SleepGlassCard(padding: 12) {
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
        return settings.enableAppleHealthImport ? "Apple Health connected" : "Connect Apple Health"
    }

    private var healthDescription: String {
        if !HealthKitSleepService().isAvailable {
            return "This device does not support HealthKit sleep access."
        }
        if settings.enableAppleHealthExport {
            return "Use sleep data from Apple Health to improve recovery scoring, and save confirmed Sleep Mode sessions only when you choose."
        }
        return "Use sleep data from Apple Health to improve your recovery score and training recommendations."
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

        do {
            if !settings.enableAppleHealthImport && !settings.enableAppleHealthExport {
                settings.enableAppleHealthImport = true
            }
            try await HealthKitSleepService().requestAuthorization(read: settings.enableAppleHealthImport, write: settings.enableAppleHealthExport)
            healthStatus = "Apple Health sleep access requested. If permission is granted, recent sleep can be imported."
        } catch {
            healthStatus = error.localizedDescription
        }
    }

    private func toggleSleepNotifications() async {
        if settings.notificationPreferences.isEnabled {
            settings.notificationPreferences.isEnabled = false
            SleepNotificationScheduler().cancelSleepNotifications()
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

private struct SleepGlassCard<Content: View>: View {
    var style: FitnessCardStyle = .standard
    var padding: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        FitnessCard(style: style, padding: padding) {
            content()
        }
    }
}

private struct SleepGlassIcon: View {
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color?

    var body: some View {
        FitnessIconBadge(systemImage: systemImage, size: size, tint: tint)
    }
}

private typealias SleepIconTile = SleepGlassIcon

private struct SleepScoreBadge: View {
    @Environment(\.appTheme) private var appTheme

    let score: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("\(score)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(appTheme.colors.accent)
                .monospacedDigit()

            Text("Score")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(appTheme.colors.accent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep recovery score, \(score) out of 100")
    }
}

private struct SleepStatusChip: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let state: RecoveryState

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, appTheme.metrics.chipHorizontalPadding)
            .padding(.vertical, appTheme.metrics.chipVerticalPadding)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
    }

    private var tint: Color {
        switch state {
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
}

private struct SleepGlassRow<Trailing: View>: View {
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
            SleepGlassIcon(systemImage: systemImage, size: appTheme.metrics.rowIconSize, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

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

private struct SleepGlassActionButton: View {
    enum Style {
        case primary
        case secondary
        case neutral
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)
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
        .buttonStyle(.plain)
    }

    private var labelFont: Font {
        switch style {
        case .primary:
            return .headline.weight(.semibold)
        case .secondary, .neutral:
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
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent
        case .secondary, .neutral:
            return appTheme.colors.cardBackgroundElevated
        }
    }

    private var border: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent.opacity(0.45)
        case .secondary, .neutral:
            return appTheme.colors.cardBorder
        }
    }
}

private typealias SleepActionButton = SleepGlassActionButton

private struct SleepGlassMetricTile: View {
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
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
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
    let score: Int

    var body: some View {
        SleepGlassCard(style: .compact, padding: 16) {
            SleepGlassRow(
                title: SleepCalendar.displayTitle(for: session.nightDate),
                subtitle: "\(SleepScoringService.durationText(minutes: session.durationMinutes)) - \(session.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality") - \(session.source.displayName). Recovery impact: \(SleepCoachingService().historyImpact(for: score))",
                systemImage: session.source == .appleHealth ? "heart.text.square.fill" : "moon.zzz.fill",
                showsChevron: true
            ) {
                Text("\(score)")
                    .font(.headline.bold())
                    .foregroundStyle(appTheme.colors.accent)
            }
        }
    }
}

private struct SleepMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        SleepGlassMetricTile(title: title, value: value)
    }
}

private struct SleepAdaptiveRecommendationCard: View {
    @Environment(\.appTheme) private var appTheme

    let recommendation: AdaptiveTrainingRecommendation

    var body: some View {
        SleepGlassCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                SleepGlassRow(
                    title: recommendation.title,
                    subtitle: recommendation.message,
                    systemImage: systemImage,
                    tint: tint
                ) {
                    Text(recommendation.level.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.14), in: Capsule())
                }

                FlowLayout(spacing: 8) {
                    ForEach(recommendation.suggestedActions) { action in
                        Text(action.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                    }
                }

                Text("Based on: \(recommendation.basedOn.map(\.displayName).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tint: Color {
        switch recommendation.level {
        case .push, .normal:
            return appTheme.colors.success
        case .moderate:
            return appTheme.colors.accent
        case .light, .recovery:
            return appTheme.colors.warning
        case .rest:
            return appTheme.colors.danger
        }
    }

    private var systemImage: String {
        switch recommendation.level {
        case .push:
            return "bolt.fill"
        case .normal:
            return "checkmark.seal.fill"
        case .moderate:
            return "dial.medium.fill"
        case .light:
            return "arrow.down.forward.circle.fill"
        case .recovery:
            return "figure.cooldown"
        case .rest:
            return "moon.fill"
        }
    }
}

private struct SleepCoachingInsightCard: View {
    @Environment(\.appTheme) private var appTheme

    let insight: SleepCoachingInsight

    var body: some View {
        SleepGlassCard(style: .compact) {
            SleepGlassRow(
                title: insight.title,
                subtitle: insightSubtitle,
                systemImage: systemImage,
                tint: tint
            ) {
                Text(insight.confidence.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
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

            HStack(spacing: 8) {
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

    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    withAnimation(AppMotion.selectionSpring(reduceMotion: reduceMotion)) {
                        selection = value
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text("\(value)")
                            .font(.headline.bold())
                        Text(Self.shortLabel(for: value))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == value ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selection == value ? appTheme.colors.accentSurfaceStrong : appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selection == value ? appTheme.colors.accent.opacity(0.32) : appTheme.colors.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("Sleep quality \(Self.label(for: value))")
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

    private static func shortLabel(for value: Int) -> String {
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
                SleepGlassIcon(systemImage: systemImage, size: appTheme.metrics.rowIconSize)

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
