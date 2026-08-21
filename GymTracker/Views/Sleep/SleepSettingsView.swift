import SwiftData
import SwiftUI

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

