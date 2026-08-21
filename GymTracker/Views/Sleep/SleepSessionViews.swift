import SwiftData
import SwiftUI

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

