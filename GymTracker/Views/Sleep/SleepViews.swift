import SwiftData
import SwiftUI

struct SleepDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sessions: [SleepSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    @Query(sort: \NapSession.startDate, order: .reverse)
    private var naps: [NapSession]

    @State private var settings = SleepSettingsStore().load()
    @State private var showingSleepMode = false
    @State private var showingManualEntry = false
    @State private var showingNapEntry = false
    @State private var showingNapTimer = false
    @State private var showingSettings = false
    @State private var confirmationSession: SleepSession?
    @State private var importedCount: Int?
    @State private var summaries: [SleepSummary] = []
    @State private var latestSummary = SleepScoringService.emptySummary()
    @State private var dashboardSummary = SleepAnalyticsService.emptyDashboardSummary()
    @State private var lastAnalyticsSignature: SleepAnalyticsInputSignature?

    private let repository = SleepSessionRepository()
    private let scoring = SleepScoringService()
    private let coaching = SleepCoachingService()
    private let settingsStore = SleepSettingsStore()
    private let analyticsStore = SleepAnalyticsSnapshotStore.shared

    private var completedSessions: [SleepSession] {
        sessions.filter { $0.status == .completed }
    }

    private var activeSession: SleepSession? {
        sessions.first { $0.status == .active }
    }

    private var currentAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sessions, naps: naps, workouts: workouts, settings: settings)
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Sleep",
                subtitle: "Recovery & readiness.",
                systemImage: "moon.zzz.fill"
            ) {
                if let activeSession {
                    activeSleepCard(activeSession)
                } else {
                    recoveryCard
                    appleHealthConnectionCard
                    startCard
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
            .navigationDestination(for: SleepSession.self) { session in
                SleepSessionDetailView(session: session)
            }
            .onAppear {
                settings = settingsStore.load()
                refreshSleepAnalytics(force: true)
                maybePromptForWakeTime()
                Task { await importSleepIfEnabled() }
            }
            .onChange(of: currentAnalyticsSignature) { _, _ in
                refreshSleepAnalytics()
            }
            .onChange(of: settings) { _, newValue in
                settingsStore.save(newValue)
                refreshSleepAnalytics(force: true)
                Task {
                    await SleepNotificationScheduler().refreshAllSleepNotifications(settings: newValue, sessions: sessions, workouts: workouts)
                }
            }
        }
    }

    private var recoveryCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 54, height: 54)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Sleep Recovery")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(latestSummary.recoveryState.shortLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.accentSurface, in: Capsule())
                        }

                        Text(latestSummary.primarySession == nil ? "No sleep data yet" : SleepScoringService.durationText(minutes: latestSummary.totalSleepMinutes))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(summaryMetadataText)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    if let score = latestSummary.sleepScore {
                        Text("\(score)")
                            .font(.title2.bold())
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 58, height: 58)
                            .background(appTheme.colors.accentSurface, in: Circle())
                            .accessibilityLabel("Sleep recovery score, \(score) out of 100")
                    }
                }

                Text(dashboardSummary.recommendation)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
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
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 44, height: 44)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appleHealthTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(appleHealthSubtitle)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

            }
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
                return "Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened)). Sleep data can improve recovery scoring."
            }
            return "Sleep data from Apple Health can be used in your recovery score."
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
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "bed.double.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 46, height: 46)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sleep Mode")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Sleep start is estimated from your wind-down timer. You can edit it in the morning.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        showingSleepMode = true
                    } label: {
                        Label("Start Sleep Mode", systemImage: "moon.zzz.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button {
                        showingManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .accessibilityLabel("Add sleep manually")
                }

                HStack(spacing: 10) {
                    Button {
                        showingNapEntry = true
                    } label: {
                        Label("Log Nap", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())

                    Button {
                        showingNapTimer = true
                    } label: {
                        Label("Nap Timer", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())
                }
            }
        }
    }

    private func activeSleepCard(_ session: SleepSession) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sleep Mode Active")
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(activeSleepDescription(for: session))
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        confirmationSession = session
                    } label: {
                        Label("Confirm Wake Time", systemImage: "sun.max.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button(role: .destructive) {
                        try? repository.discard(session, in: modelContext)
                        Task {
                            SleepNotificationScheduler().cancelNotifications(for: session.id)
                            await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessions, workouts: workouts)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())
                    .accessibilityLabel("Discard sleep session")
                }
            }
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

    private var weeklyChartCard: some View {
        SleepDashboardSection(title: "Last 7 Days") {
            FitnessCard {
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
        SleepDashboardSection(title: "Naps") {
            VStack(spacing: 12) {
                if dashboardSummary.recentNaps.isEmpty {
                    FitnessCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "moonphase.first.quarter")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(appTheme.colors.accent)
                                .frame(width: 44, height: 44)
                                .background(appTheme.colors.accentSurface, in: Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                Text("No naps logged recently")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("Log a nap after short sleep to see whether it helped today's recovery.")
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
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
        SleepDashboardSection(title: "Recovery Trends") {
            VStack(spacing: 12) {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sleep Debt")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(sleepDebtHeadline)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(sleepDebtCopy)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                FitnessCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Consistency")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(dashboardSummary.consistencySummary.displayName)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        if let bed = dashboardSummary.consistencySummary.averageSleepStart, let wake = dashboardSummary.consistencySummary.averageWakeTime {
                            HStack(spacing: 10) {
                                SleepMiniMetric(title: "Bedtime", value: bed.formatted(date: .omitted, time: .shortened))
                                SleepMiniMetric(title: "Wake", value: wake.formatted(date: .omitted, time: .shortened))
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
    }

    private var trainingInsightCard: some View {
        SleepDashboardSection(title: "Sleep And Training") {
            FitnessCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 44, height: 44)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    Text(coaching.trainingInsight(summaries: summaries, workouts: workouts))
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var coachingInsightsSection: some View {
        SleepDashboardSection(title: "Coaching Insights") {
            VStack(spacing: 10) {
                if let recommendation = dashboardSummary.adaptiveRecommendation {
                    SleepAdaptiveRecommendationCard(recommendation: recommendation)
                }

                if dashboardSummary.coachingInsights.isEmpty {
                    FitnessCard {
                        Text("Keep tracking sleep and workouts. Once there is enough history, Peakline can show how your sleep affects performance.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
        SleepDashboardSection(title: "History") {
            if completedSessions.isEmpty {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No sleep data yet")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("Start Sleep Mode tonight to help the app understand your recovery.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(completedSessions.prefix(14)) { session in
                        NavigationLink(value: session) {
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
        await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessions, workouts: workouts)
    }
}

private struct NapSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let nap: NapSession
    let creditMinutes: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moonphase.first.quarter")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 44, height: 44)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(nap.startDate.formatted(date: .omitted, time: .shortened))-\(nap.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Spacer()
                        Text(nap.source.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                    }

                    Text("\(SleepScoringService.durationText(minutes: nap.durationMinutes)) - \(nap.timingCategory.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    if let quality = nap.qualityRating {
                        Text("\(SleepQualityPicker.label(for: quality)) quality")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }

                    Text(creditMinutes)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                }
            }
        }
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
            Form {
                Section("Nap Time") {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Quality") {
                    SleepQualityPicker(selection: $quality)
                }

                Section("Note") {
                    TextField("Felt refreshed, still tired, post-workout nap", text: $note, axis: .vertical)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(appTheme.colors.danger)
                    }
                }
            }
            .navigationTitle("Log Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNap() }
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
            VStack(spacing: 22) {
                Text("Nap Mode")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(timerText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(appTheme.colors.accent)
                    .monospacedDigit()

                Picker("Timer", selection: $selectedMinutes) {
                    ForEach(options, id: \.self) { minutes in
                        Text("\(minutes)m").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(startedAt != nil)

                SleepQualityPicker(selection: $quality)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.danger)
                }

                Button {
                    if startedAt == nil {
                        startedAt = .now
                    } else {
                        finishNap()
                    }
                } label: {
                    Label(startedAt == nil ? "Start Nap Timer" : "Finish Nap", systemImage: startedAt == nil ? "timer" : "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())

                Spacer()
            }
            .padding()
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
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

                    FitnessCard {
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
                        Button {
                            start(minutes: selectedMinutes)
                        } label: {
                            Label("Start Sleep Mode", systemImage: "moon.zzz.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())

                        Button {
                            start(minutes: 0)
                        } label: {
                            Label("Start Now", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())

                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeutralFitnessButtonStyle())
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
                .stroke(appTheme.colors.cardBorder, lineWidth: 14)

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
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessions, workouts: workouts)
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
                FitnessCard {
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

                FitnessCard {
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

                Button {
                    confirm()
                } label: {
                    Label("Confirm Wake Time", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())

                Button(role: .destructive) {
                    try? repository.discard(session, in: modelContext)
                    dismiss()
                } label: {
                    Text("Discard Session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeutralFitnessButtonStyle())
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
                Task {
                    if let ids = try? await HealthKitSleepService().writeConfirmedSession(session) {
                        session.healthKitSampleIds = ids
                        try? modelContext.save()
                    }
                }
            }

            Task {
                SleepNotificationScheduler().cancelNotifications(for: session.id)
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: settings, sessions: sessions, workouts: workouts)
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
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Sleep start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Wake time", selection: $wakeAt, displayedComponents: [.date, .hourAndMinute])

                        SleepMiniMetric(
                            title: "Duration",
                            value: SleepScoringService.durationText(minutes: repository.durationMinutes(start: sleepStart, wake: wakeAt))
                        )
                    }
                }

                FitnessCard {
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

                Button {
                    save()
                } label: {
                    Label("Save Sleep Session", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
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
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: SleepSettingsStore().load(), sessions: sessions, workouts: workouts)
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
            FitnessCard {
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
                FitnessCard {
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

            FitnessCard {
                Text("Recovery impact: \(SleepCoachingService().historyImpact(for: scoring.score(for: session, recentSessions: [session], settings: SleepSettingsStore().load())))")
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
            }

            FitnessCard {
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

            Button {
                showingEditor = true
            } label: {
                Label("Edit Sleep Session", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
            .disabled(session.source == .appleHealth)

            if session.source == .appleHealth {
                Text("Apple Health imported sleep is read-only in Peakline for now.")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Session", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeutralFitnessButtonStyle())
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
                FitnessCard {
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

                FitnessCard {
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

                FitnessCard(padding: 12) {
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

                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(healthTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(healthDescription)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await requestHealthAccess() }
                        } label: {
                            if isRequestingHealth {
                                SwiftUI.ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(settings.enableAppleHealthImport || settings.enableAppleHealthExport ? "Request Sleep Access" : "Connect Apple Health", systemImage: "lock.open")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Notifications")
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)

            FitnessCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 44, height: 44)
                            .background(appTheme.colors.accentSurface, in: Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            Text(settings.notificationPreferences.isEnabled ? "Sleep Notifications On" : "Enable sleep reminders?")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("We'll remind you to start Sleep Mode and confirm your wake time so recovery guidance stays accurate.")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await toggleSleepNotifications() }
                        } label: {
                            if isRequestingNotifications {
                                SwiftUI.ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(settings.notificationPreferences.isEnabled ? "Turn Off" : "Enable Reminders", systemImage: settings.notificationPreferences.isEnabled ? "bell.slash" : "bell")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Coaching")
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)

            FitnessCard(padding: 12) {
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

private struct SleepDashboardSection<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)
            content
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
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: hasAppeared)
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
        FitnessCard(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: session.source == .appleHealth ? "heart.text.square.fill" : "moon.zzz.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 42, height: 42)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(SleepCalendar.displayTitle(for: session.nightDate))
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("\(SleepScoringService.durationText(minutes: session.durationMinutes)) - \(session.qualityRating.map { SleepQualityPicker.label(for: $0) } ?? "No quality") - \(session.source.displayName)")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(2)

                    Text("Recovery impact: \(SleepCoachingService().historyImpact(for: score))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                Spacer()

                Text("\(score)")
                    .font(.headline.bold())
                    .foregroundStyle(appTheme.colors.accent)
            }
        }
    }
}

private struct SleepMiniMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SleepAdaptiveRecommendationCard: View {
    @Environment(\.appTheme) private var appTheme

    let recommendation: AdaptiveTrainingRecommendation

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.title)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(recommendation.message)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

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
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(insight.confidence.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.12), in: Capsule())
                    }

                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !insight.basedOn.isEmpty {
                        Text("Based on: \(insight.basedOn.map(\.displayName).joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
        }
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

    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
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
                    .foregroundStyle(selection == value ? .black : appTheme.colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selection == value ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
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
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 36, height: 36)
                    .background(appTheme.colors.accentSurface, in: Circle())

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
