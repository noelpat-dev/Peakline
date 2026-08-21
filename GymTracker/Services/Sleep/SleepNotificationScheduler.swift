import Foundation
import SwiftData
import UserNotifications

struct SleepNotificationID {
    static let bedtimeReminder = "sleep.bedtimeReminder"
    static let windDownReminder = "sleep.windDownReminder"
    static let missedSleepReminder = "sleep.missedSleepReminder"

    static func morningConfirmation(sessionID: UUID) -> String {
        "sleep.morningConfirmation.\(sessionID.uuidString)"
    }

    static func unfinishedSession(sessionID: UUID) -> String {
        "sleep.unfinishedSession.\(sessionID.uuidString)"
    }

    static func trainingAware(date: Date) -> String {
        let value = date.formatted(.iso8601.year().month().day())
        return "sleep.trainingAware.\(value)"
    }

    static let allStable = [bedtimeReminder, windDownReminder, missedSleepReminder]
}

struct SleepNotificationService {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        PerformanceTracer.mark(.unsafeBreadcrumb, "notification.authorizationStatus before_continuation")
        return await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                PerformanceTracer.mark(.unsafeBreadcrumb, "notification.authorizationStatus callback")
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let status = await authorizationStatus()
        guard granted || status == .authorized || status == .provisional else {
            throw HealthKitSyncError.authorizationDenied
        }
        return status
    }
}

struct SleepNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func refreshAllSleepNotifications(
        settings: SleepSettings,
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar = .current
    ) async {
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler begin enabled=\(settings.notificationPreferences.isEnabled)")
        guard settings.notificationPreferences.isEnabled else {
            await cancelSleepNotificationsAsync(sessions: sessions, workouts: workouts, calendar: calendar)
            PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end disabled")
            return
        }

        let status = await PerformanceTracer.traceAsync(.rootNotificationPermissionStatus) {
            await SleepNotificationService().authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await cancelSleepNotificationsAsync(sessions: sessions, workouts: workouts, calendar: calendar)
            PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end unauthorized status=\(status.rawValue)")
            return
        }

        await cancelSleepNotificationsAsync(sessions: sessions, workouts: workouts, calendar: calendar)

        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler before_schedule")
        PerformanceTracer.trace(.rootNotificationScheduling) {
            scheduleBedtimeReminder(settings: settings, sessions: sessions, calendar: calendar)
            scheduleWindDownReminder(settings: settings, sessions: sessions, calendar: calendar)

            if let session = sessions.first(where: { $0.status == .active }) {
                scheduleMorningConfirmationReminder(for: session, settings: settings, calendar: calendar)
                scheduleUnfinishedSessionReminder(for: session)
            }

            scheduleMissedSleepReminder(settings: settings, sessions: sessions, calendar: calendar)
            scheduleTrainingAwareReminder(settings: settings, sessions: sessions, workouts: workouts, calendar: calendar)
        }
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end")
    }

    func scheduleBedtimeReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.bedtimeReminderEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        guard !hasSessionForUpcomingNight(sessions: sessions, calendar: calendar) else { return }

        scheduleCalendarNotification(
            id: SleepNotificationID.bedtimeReminder,
            title: "Recovery starts tonight",
            body: "Start Sleep Mode so tomorrow's workout guidance is more accurate.",
            components: preferences.bedtimeReminderTime,
            repeats: true,
            destination: .sleepMode
        )
    }

    func scheduleWindDownReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.windDownReminderEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        let bedtime = date(from: preferences.bedtimeReminderTime, on: .now, calendar: calendar)
        let reminderDate = bedtime.addingTimeInterval(TimeInterval(-preferences.windDownOffsetMinutes * 60))
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)

        scheduleCalendarNotification(
            id: SleepNotificationID.windDownReminder,
            title: "Start winding down",
            body: "A consistent bedtime can improve recovery and training performance.",
            components: components,
            repeats: true,
            destination: .sleepMode
        )
    }

    func scheduleMorningConfirmationReminder(for session: SleepNotificationSessionSnapshot, settings: SleepSettings, calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.morningConfirmationEnabled else { return }
        guard session.morningReminderSentAt == nil else { return }

        scheduleCalendarNotification(
            id: SleepNotificationID.morningConfirmation(sessionID: session.id),
            title: "Confirm your sleep",
            body: "Review your wake time to update today's recovery score.",
            components: preferences.morningConfirmationTime,
            repeats: false,
            destination: .wakeConfirmation(sessionID: session.id)
        )
    }

    func scheduleUnfinishedSessionReminder(for session: SleepNotificationSessionSnapshot) {
        guard session.unfinishedReminderSentAt == nil else { return }
        let start = session.sleepModeStartedAt ?? session.confirmedSleepStartAt
        let fireDate = start.addingTimeInterval(12 * 3_600)
        let interval = max(60, fireDate.timeIntervalSinceNow)

        scheduleTimeIntervalNotification(
            id: SleepNotificationID.unfinishedSession(sessionID: session.id),
            title: "Still tracking sleep?",
            body: "Confirm your wake time so your recovery score does not overestimate sleep.",
            interval: interval,
            destination: .wakeConfirmation(sessionID: session.id)
        )
    }

    func scheduleMissedSleepReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.missedSleepReminderEnabled else { return }
        guard recentTrackedCount(sessions: sessions, now: .now, calendar: calendar) >= 3 else { return }
        guard !hasSessionForLastNight(sessions: sessions, calendar: calendar) else { return }

        var components = DateComponents()
        components.hour = 11
        components.minute = 30
        scheduleCalendarNotification(
            id: SleepNotificationID.missedSleepReminder,
            title: "Forgot to track sleep?",
            body: "Add an estimate so today's recovery score stays useful.",
            components: components,
            repeats: false,
            destination: .manualBackfill
        )
    }

    func scheduleTrainingAwareReminder(
        settings: SleepSettings,
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar = .current
    ) {
        let preferences = settings.notificationPreferences
        guard preferences.trainingAwareRemindersEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        guard likelyWorkoutTomorrow(workouts: workouts, calendar: calendar) else { return }

        let bedtime = date(from: preferences.bedtimeReminderTime, on: .now, calendar: calendar)
        let reminderDate = bedtime.addingTimeInterval(-20 * 60)
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now

        scheduleCalendarNotification(
            id: SleepNotificationID.trainingAware(date: tomorrow),
            title: "Big session tomorrow",
            body: "Start Sleep Mode tonight so your recovery guidance is more accurate.",
            components: components,
            repeats: false,
            destination: .sleepMode
        )
    }

    func cancelSleepNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: SleepNotificationID.allStable)
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("sleep.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelSleepNotificationsAsync(
        sessions: [SleepNotificationSessionSnapshot] = [],
        workouts: [SleepNotificationWorkoutSnapshot] = [],
        calendar: Calendar = .current
    ) async {
        await PerformanceTracer.traceAsync(.rootNotificationCancellation) {
            var ids = Set(SleepNotificationID.allStable)
            ids.formUnion(dynamicNotificationIDs(sessions: sessions, workouts: workouts, calendar: calendar))
            let pendingSleepIds = await pendingSleepNotificationIDs()
            ids.formUnion(pendingSleepIds)
            center.removePendingNotificationRequests(withIdentifiers: Array(ids))
        }
    }

    func cancelNotifications(for sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            SleepNotificationID.morningConfirmation(sessionID: sessionID),
            SleepNotificationID.unfinishedSession(sessionID: sessionID)
        ])
    }

    static func sessionSnapshots(from sessions: [SleepSession]) -> [SleepNotificationSessionSnapshot] {
        sessions.map { SleepNotificationSessionSnapshot(session: $0) }
    }

    static func workoutSnapshots(from workouts: [WorkoutSession]) -> [SleepNotificationWorkoutSnapshot] {
        workouts.map { SleepNotificationWorkoutSnapshot(workout: $0) }
    }

    private func scheduleCalendarNotification(id: String, title: String, body: String, components: DateComponents, repeats: Bool, destination: SleepNotificationDestination) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = destination.userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func scheduleTimeIntervalNotification(id: String, title: String, body: String, interval: TimeInterval, destination: SleepNotificationDestination) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = destination.userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func pendingSleepNotificationIDs() async -> [String] {
        await PerformanceTracer.traceAsync(.rootNotificationPendingFetch) {
            PerformanceTracer.mark(.unsafeBreadcrumb, "notification.pending_fetch before_continuation")
            return await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    PerformanceTracer.mark(.unsafeBreadcrumb, "notification.pending_fetch callback count=\(requests.count)")
                    continuation.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix("sleep.") })
                }
            }
        }
    }

    private func dynamicNotificationIDs(
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar
    ) -> [String] {
        var ids = sessions.flatMap { session in
            [
                SleepNotificationID.morningConfirmation(sessionID: session.id),
                SleepNotificationID.unfinishedSession(sessionID: session.id)
            ]
        }

        if likelyWorkoutTomorrow(workouts: workouts, calendar: calendar) {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
            ids.append(SleepNotificationID.trainingAware(date: tomorrow))
        }

        return ids
    }

    func hasSessionForUpcomingNight(
        sessions: [SleepNotificationSessionSnapshot],
        now: Date = .now,
        calendar: Calendar
    ) -> Bool {
        let upcomingNight = calendar.startOfDay(for: now)
        return sessions.contains {
            $0.status == .completed && $0.wakeAt <= now
                && calendar.isDate(
                    SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar),
                    inSameDayAs: upcomingNight
                )
        }
    }

    func hasSessionForLastNight(
        sessions: [SleepNotificationSessionSnapshot],
        now: Date = .now,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let lastNight = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return sessions.contains {
            $0.status == .completed && $0.wakeAt <= now
                && calendar.isDate(
                    SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar),
                    inSameDayAs: lastNight
                )
        }
    }

    private func recentTrackedCount(sessions: [SleepNotificationSessionSnapshot], now: Date = .now, calendar: Calendar) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        return Set(
            sessions
                .filter { $0.status == .completed && $0.wakeAt <= now && $0.confirmedSleepStartAt >= cutoff }
                .map { SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar) }
        ).count
    }

    private func likelyWorkoutTomorrow(workouts: [SleepNotificationWorkoutSnapshot], calendar: Calendar) -> Bool {
        let tomorrowWeekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let cutoff = calendar.date(byAdding: .day, value: -56, to: .now) ?? .now.addingTimeInterval(-56 * 86_400)
        return workouts.contains { workout in
            workout.date >= cutoff && calendar.component(.weekday, from: workout.date) == tomorrowWeekday
        }
    }

    private func date(from components: DateComponents, on date: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: components.hour ?? 22,
            minute: components.minute ?? 30,
            second: 0,
            of: date
        ) ?? date
    }
}

struct SleepNotificationSessionSnapshot: Sendable {
    let id: UUID
    let status: SleepSessionStatus
    let nightDate: Date
    let confirmedSleepStartAt: Date
    let wakeAt: Date
    let sleepModeStartedAt: Date?
    let morningReminderSentAt: Date?
    let unfinishedReminderSentAt: Date?

    init(session: SleepSession) {
        self.id = session.id
        self.status = session.status
        self.nightDate = session.nightDate
        self.confirmedSleepStartAt = session.confirmedSleepStartAt
        self.wakeAt = session.wakeAt
        self.sleepModeStartedAt = session.sleepModeStartedAt
        self.morningReminderSentAt = session.morningReminderSentAt
        self.unfinishedReminderSentAt = session.unfinishedReminderSentAt
    }
}

struct SleepNotificationWorkoutSnapshot: Sendable {
    let date: Date

    init(workout: WorkoutSession) {
        self.date = workout.date
    }
}
