import SwiftData
import SwiftUI

struct HealthKitSettingsView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var foodLogs: [FoodLogEntry]

    @Query private var foodItems: [FoodItem]

    @State private var preferences = HealthKitPreferenceStore().load()
    @State private var permissionState: HealthKitPermissionState = .notRequested
    @State private var syncRecords: [HealthKitFoodLogSyncRecord] = HealthKitSyncStateStore().records()
    @State private var lastSummary: HealthKitSyncSummary?
    @State private var healthContext: HealthKitDailyContext?
    @State private var statusMessage: String?
    @State private var isRequestingAccess = false
    @State private var isSyncing = false
    @State private var isReadingContext = false

    private let preferenceStore = HealthKitPreferenceStore()
    private let syncStore = HealthKitSyncStateStore()
    private let healthBridge = NutritionHealthKitBridge()

    var body: some View {
        FitnessScreen(
            title: "Apple Health",
            subtitle: "Optional nutrition sync and activity context.",
            systemImage: "heart.text.square"
        ) {
            integrationCard
            permissionsCard
            sharingControls
            syncActions
            appleHealthContextCard
            syncHistoryCard
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("healthkit-settings-screen")
        .onAppear {
            refreshState()
            Task { await refreshHealthContext() }
        }
        .onChange(of: preferences) { _, newValue in
            preferenceStore.save(newValue)
            refreshState()
        }
    }

    private var integrationCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 48, height: 48)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Apple Health Sync")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            HealthKitPermissionBadge(state: permissionState)
                        }

                        Text("Share confirmed nutrition logs with Apple Health and optionally use health context like body weight, steps, workouts, and active energy for training-aware insights.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("GymTracker will not replace your local food database. You control what is shared, and the app still works with Apple Health off.")
                    .font(.footnote)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var permissionsCard: some View {
        DashboardSection(title: "Connection") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HealthKitSettingsMetricRow(
                        title: "Availability",
                        value: healthBridge.isAvailable ? "Available" : "Unavailable",
                        systemImage: healthBridge.isAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill",
                        tint: healthBridge.isAvailable ? appTheme.colors.success : appTheme.colors.danger
                    )

                    HealthKitSettingsMetricRow(
                        title: "Permission",
                        value: permissionState.displayName,
                        systemImage: "lock.shield",
                        tint: permissionTint
                    )

                    if !preferences.isHealthKitEnabled {
                        Button {
                            preferences.isHealthKitEnabled = true
                            statusMessage = "Apple Health is enabled in GymTracker. Choose what to share, then request access."
                        } label: {
                            Label("Enable Apple Health", systemImage: "heart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .disabled(!healthBridge.isAvailable)
                    } else {
                        Button {
                            Task { await requestAccess() }
                        } label: {
                            if isRequestingAccess {
                                SwiftUI.ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Request Apple Health Access", systemImage: "lock.open")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .disabled(!healthBridge.isAvailable || !preferences.requestsAnyHealthData || isRequestingAccess)
                    }

                    if preferences.isHealthKitEnabled && !preferences.requestsAnyHealthData {
                        Text("Turn on at least one data type below before requesting Apple Health access.")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.warning)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var sharingControls: some View {
        DashboardSection(title: "Data Controls") {
            FitnessCard(padding: 12) {
                VStack(spacing: 0) {
                    HealthKitToggleRow(
                        title: "Apple Health integration",
                        subtitle: "Keep the bridge opt-in.",
                        systemImage: "heart",
                        isOn: $preferences.isHealthKitEnabled
                    )
                    .disabled(!healthBridge.isAvailable && !preferences.isHealthKitEnabled)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Write nutrition logs",
                        subtitle: "Share calories and macros from confirmed food logs.",
                        systemImage: "square.and.arrow.up",
                        isOn: $preferences.writeNutritionToHealthKit
                    )
                    .disabled(!preferences.isHealthKitEnabled || !healthBridge.isAvailable)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Auto-sync new logs",
                        subtitle: "Attempt Apple Health sync after a local log is saved.",
                        systemImage: "arrow.triangle.2.circlepath",
                        isOn: $preferences.autoSyncNewFoodLogs
                    )
                    .disabled(!preferences.isHealthKitEnabled || !preferences.writeNutritionToHealthKit || !healthBridge.isAvailable)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Body weight insights",
                        subtitle: "Use Apple Health body weight as labeled context.",
                        systemImage: "scalemass",
                        isOn: $preferences.readBodyWeight
                    )
                    .disabled(!preferences.isHealthKitEnabled || !healthBridge.isAvailable)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Activity context",
                        subtitle: "Read active energy, steps, and workouts for insight context.",
                        systemImage: "figure.walk.motion",
                        isOn: activityContextBinding
                    )
                    .disabled(!preferences.isHealthKitEnabled || !healthBridge.isAvailable)
                }
            }

            FitnessCard(padding: 12) {
                VStack(spacing: 0) {
                    HealthKitToggleRow(
                        title: "Include sugar and fibre",
                        subtitle: "Only when a local food log has those values.",
                        systemImage: "leaf",
                        isOn: $preferences.includeSugarAndFibreIfAvailable
                    )
                    .disabled(!preferences.writeNutritionToHealthKit)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Include sodium from salt",
                        subtitle: "Convert salt to sodium only when intentionally enabled.",
                        systemImage: "drop",
                        isOn: $preferences.includeSodiumIfAvailable
                    )
                    .disabled(!preferences.writeNutritionToHealthKit)

                    HealthKitSettingsDivider()

                    HealthKitToggleRow(
                        title: "Confirmed foods only",
                        subtitle: "Skip local foods that are not user-confirmed.",
                        systemImage: "checkmark.seal",
                        isOn: $preferences.syncOnlyUserConfirmedEntries
                    )
                    .disabled(!preferences.writeNutritionToHealthKit)
                }
            }
        }
    }

    private var syncActions: some View {
        DashboardSection(title: "Manual Sync") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 42, height: 42)
                            .background(appTheme.colors.accentSurface, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync recent food logs")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("Only eligible local logs are shared. Already-synced logs are skipped to avoid duplicates.")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            syncLogs(days: 1)
                        } label: {
                            Label("Today", systemImage: "calendar")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())

                        Button {
                            syncLogs(days: 7)
                        } label: {
                            if isSyncing {
                                SwiftUI.ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("7 Days", systemImage: "calendar.badge.clock")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                    }
                    .disabled(!canSync || isSyncing)

                    if let lastSummary {
                        Text(lastSummary.displayMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(lastSummary.failed > 0 ? appTheme.colors.danger : appTheme.colors.success)

                        ForEach(lastSummary.warnings.prefix(2), id: \.self) { warning in
                            Text(warning)
                                .font(.caption2)
                                .foregroundStyle(appTheme.colors.warning)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appleHealthContextCard: some View {
        if preferences.isHealthKitEnabled && preferences.requestsAnyReadData {
            DashboardSection(title: "Apple Health Context") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(appTheme.colors.accent)
                                .frame(width: 42, height: 42)
                                .background(appTheme.colors.accentSurface, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Labeled context only")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("Apple Health data can support insights, but local workouts and food logs stay primary.")
                                    .font(.caption)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let healthContext {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                if let bodyMass = healthContext.bodyMassKg {
                                    HealthKitContextMetric(title: "Weight", value: "\(bodyMass.formatted(.number.precision(.fractionLength(1)))) kg")
                                }
                                if let activeEnergy = healthContext.activeEnergyKcal {
                                    HealthKitContextMetric(title: "Active", value: "\(activeEnergy.formatted(.number.precision(.fractionLength(0)))) kcal")
                                }
                                if let stepCount = healthContext.stepCount {
                                    HealthKitContextMetric(title: "Steps", value: stepCount.formatted(.number.precision(.fractionLength(0))))
                                }
                                if let workoutCount = healthContext.workoutCount {
                                    HealthKitContextMetric(title: "Workouts", value: "\(workoutCount)")
                                }
                            }
                        } else {
                            Text(isReadingContext ? "Reading Apple Health..." : "No Apple Health context is available for today yet.")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }

                        Button {
                            Task { await refreshHealthContext() }
                        } label: {
                            Label("Refresh Context", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .disabled(isReadingContext)
                    }
                }
            }
        }
    }

    private var syncHistoryCard: some View {
        DashboardSection(title: "Sync History") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    if syncRecords.isEmpty {
                        Text("No HealthKit sync attempts yet.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    } else {
                        ForEach(syncRecords.prefix(5)) { record in
                            HealthKitSyncHistoryRow(record: record)
                        }
                    }
                }
            }
        }
    }

    private var activityContextBinding: Binding<Bool> {
        Binding {
            preferences.readActiveEnergy || preferences.readStepCount || preferences.readWorkouts
        } set: { newValue in
            preferences.readActiveEnergy = newValue
            preferences.readStepCount = newValue
            preferences.readWorkouts = newValue
        }
    }

    private var permissionTint: Color {
        switch permissionState {
        case .sharingAuthorized, .readOnlyRequested:
            return appTheme.colors.success
        case .partiallyAuthorized:
            return appTheme.colors.warning
        case .sharingDenied, .unavailable:
            return appTheme.colors.danger
        case .notRequested:
            return appTheme.colors.textSecondary
        }
    }

    private var canSync: Bool {
        preferences.isHealthKitEnabled && preferences.writeNutritionToHealthKit && healthBridge.isAvailable
    }

    private func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }

        do {
            permissionState = try await healthBridge.requestAuthorization(preferences: preferences)
            statusMessage = permissionState == .sharingDenied
                ? "Apple Health permissions may have changed. Review access in iOS Settings."
                : "Apple Health access updated."
        } catch {
            permissionState = .sharingDenied
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func syncLogs(days: Int) {
        guard !isSyncing else { return }
        isSyncing = true

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now)) ?? .now
        let eligibleLogs = foodLogs
            .filter { $0.loggedAt >= start }
            .map { HealthKitFoodLogSyncSnapshot(entry: $0) }
        let foodsById = Dictionary(uniqueKeysWithValues: foodItems.map { ($0.id, HealthKitFoodItemSyncSnapshot(food: $0)) })
        PerformanceTracer.mark(.healthKitNutritionBridge, "settings_sync snapshots_ready entries=\(eligibleLogs.count) foods=\(foodsById.count)")

        Task {
            PerformanceTracer.mark(.healthKitNutritionBridge, "settings_sync task_begin")
            let summary = await healthBridge.sync(entries: eligibleLogs, foodItemsById: foodsById, preferences: preferences)
            PerformanceTracer.mark(.healthKitNutritionBridge, "settings_sync before_main_state")
            await MainActor.run {
                lastSummary = summary
                syncRecords = syncStore.records()
                permissionState = healthBridge.currentPermissionState(preferences: preferences)
                isSyncing = false
            }
            PerformanceTracer.mark(.healthKitNutritionBridge, "settings_sync task_end")
        }
    }

    private func refreshHealthContext() async {
        guard preferences.isHealthKitEnabled, preferences.requestsAnyReadData else {
            healthContext = nil
            return
        }

        PerformanceTracer.mark(.healthKitNutritionBridge, "daily_context begin")
        isReadingContext = true
        healthContext = await healthBridge.dailyContext(for: .now, preferences: preferences)
        isReadingContext = false
        PerformanceTracer.mark(.healthKitNutritionBridge, "daily_context end hasContext=\(healthContext != nil)")
    }

    private func refreshState() {
        permissionState = healthBridge.currentPermissionState(preferences: preferences)
        syncRecords = syncStore.records()
    }
}

struct HealthKitSyncStatusBadge: View {
    @Environment(\.appTheme) private var appTheme

    let status: HealthKitSyncStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .synced:
            return appTheme.colors.success
        case .failed, .unavailable, .needsResync:
            return appTheme.colors.danger
        case .skipped:
            return appTheme.colors.warning
        case .notEnabled, .pending:
            return appTheme.colors.textSecondary
        }
    }
}

private struct HealthKitPermissionBadge: View {
    @Environment(\.appTheme) private var appTheme

    let state: HealthKitPermissionState

    var body: some View {
        Text(state.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch state {
        case .sharingAuthorized, .readOnlyRequested:
            return appTheme.colors.success
        case .partiallyAuthorized:
            return appTheme.colors.warning
        case .sharingDenied, .unavailable:
            return appTheme.colors.danger
        case .notRequested:
            return appTheme.colors.textSecondary
        }
    }
}

private struct HealthKitSettingsMetricRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct HealthKitToggleRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

private struct HealthKitSettingsDivider: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Rectangle()
            .fill(appTheme.colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

private struct HealthKitContextMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("Apple Health")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HealthKitSyncHistoryRow: View {
    @Environment(\.appTheme) private var appTheme

    let record: HealthKitFoodLogSyncRecord

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.foodName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            HealthKitSyncStatusBadge(status: record.status)
        }
        .padding(12)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detailText: String {
        if let lastSyncedAt = record.lastSyncedAt {
            return "Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return record.errorMessage ?? "No sync timestamp"
    }
}
