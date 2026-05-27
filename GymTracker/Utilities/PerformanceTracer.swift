import Foundation
import os

enum PerformanceMetric: String {
    case appLaunchPreparation = "app.launch.preparation"
    case rootNotificationRefresh = "root.notification.refresh"
    case rootNotificationInputSignature = "root.notification.input_signature"
    case rootNotificationSettingsLoad = "root.notification.settings_load"
    case rootNotificationSnapshot = "root.notification.snapshot"
    case rootNotificationDeferredWork = "root.notification.deferred_work"
    case rootNotificationPermissionStatus = "root.notification.permission_status"
    case rootNotificationPendingFetch = "root.notification.pending_fetch"
    case rootNotificationCancellation = "root.notification.cancellation"
    case rootNotificationScheduling = "root.notification.scheduling"
    case rootNotificationMainState = "root.notification.main_state"
    case appLifecycle = "app.lifecycle"
    case toolbarBreadcrumb = "toolbar.breadcrumb"
    case splitsDashboard = "splits.dashboard"
    case todayRouteSelection = "today.route.selection"
    case todayRouteSelectionState = "today.route.selection_state"
    case todayRouteDestination = "today.route.destination"
    case todayRouteAppear = "today.route.appear"
    case todayCoachContentMount = "today.coach.content_mount"
    case todayCoachDestinationBody = "today.coach.destination_body"
    case todayCoachDestinationAppear = "today.coach.destination_appear"
    case todayCoachFirstFrame = "today.coach.first_frame"
    case todaySnapshot = "today.snapshot"
    case todayCoachSnapshot = "today.coach.snapshot"
    case todaySleepReadiness = "today.sleep_readiness"
    case unsafeBreadcrumb = "unsafe.breadcrumb"
    case healthKitSleepBridge = "healthkit.sleep.bridge"
    case healthKitNutritionBridge = "healthkit.nutrition.bridge"
    case sleepMorningConfirmation = "sleep.morning_confirmation"
    case workoutStartSleepReadiness = "workout_start.sleep_readiness"
    case workoutRouteNavigation = "workout.route.navigation"
    case workoutLoggerPreviousPerformance = "workout_logger.previous_performance"
    case workoutLoggerAddExercise = "workout_logger.add_exercise"
    case workoutLoggerFinish = "workout_logger.finish"
    case workoutPreviewRenderSnapshot = "workout_preview.render_snapshot"
    case sleepAnalyticsCache = "sleep.analytics.cache"
    case sleepReadinessCache = "sleep_readiness.cache"
    case coachSleepAnalytics = "coach.sleep_analytics"
    case coachSnapshot = "coach.snapshot"
    case coachDerivedMetrics = "coach.derived_metrics"
    case coachWeeklyReview = "coach.weekly_review"
    case nutritionDashboardSnapshot = "nutrition.dashboard_snapshot"
    case nutritionInsightsSnapshot = "nutrition.insights_snapshot"
    case nutritionHealthKitRowStatus = "nutrition.healthkit_row_status"
    case nutritionHealthKitSync = "nutrition.healthkit_sync"
    case barcodeLookup = "barcode.lookup"
    case openFoodFactsRequest = "open_food_facts.request"
    case nutritionOCR = "nutrition.ocr"
    case nutritionOCRParse = "nutrition.ocr_parse"
    case progressFetchExercises = "progress.fetch_exercises"
    case progressAnalytics = "progress.analytics"
    case exerciseProgressEntries = "progress.exercise_entries"
    case prTimelineAnalytics = "pr_timeline.analytics"
    case historyDisplaySnapshot = "history.display_snapshot"
    case sleepSessionQuality = "sleep.session_quality"
}

enum PerformanceTracer {
    static func mark(_ metric: PerformanceMetric, _ message: String = "") {
        #if DEBUG
        PerformanceAcceptanceState.record(metric: metric, message: message)
        logger.debug("\(metric.rawValue, privacy: .public) \(message, privacy: .public)")
        #endif
    }

    @discardableResult
    static func trace<T>(_ metric: PerformanceMetric, _ work: () throws -> T) rethrows -> T {
        #if DEBUG
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: signpostName, signpostID: signpostID, "%{public}s", metric.rawValue)
        let start = ContinuousClock.now
        defer {
            let elapsed = start.duration(to: ContinuousClock.now)
            let milliseconds = elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            os_signpost(.end, log: signpostLog, name: signpostName, signpostID: signpostID, "%{public}s", metric.rawValue)
            PerformanceAcceptanceState.recordCompletion(metric: metric, milliseconds: milliseconds)
            logger.debug("\(metric.rawValue, privacy: .public) completed in \(milliseconds)ms")
        }
        #endif

        return try work()
    }

    static func traceAsync<T>(_ metric: PerformanceMetric, _ work: () async throws -> T) async rethrows -> T {
        #if DEBUG
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: signpostName, signpostID: signpostID, "%{public}s", metric.rawValue)
        let start = ContinuousClock.now
        defer {
            let elapsed = start.duration(to: ContinuousClock.now)
            let milliseconds = elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            os_signpost(.end, log: signpostLog, name: signpostName, signpostID: signpostID, "%{public}s", metric.rawValue)
            PerformanceAcceptanceState.recordCompletion(metric: metric, milliseconds: milliseconds)
            logger.debug("\(metric.rawValue, privacy: .public) completed in \(milliseconds)ms")
        }
        #endif

        return try await work()
    }

    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Peakline"
    private static let logger = Logger(subsystem: subsystem, category: "Performance")
    private static let signpostLog = OSLog(subsystem: subsystem, category: "Performance")
    private static let signpostName: StaticString = "PeaklinePerformance"
    #endif
}

#if DEBUG
enum PerformanceAcceptanceState {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PerformanceAcceptanceMode")
    }

    static var summary: String {
        lock.lock()
        defer { lock.unlock() }

        let status = failures.isEmpty ? "PASS" : "FAIL"
        let failureText = failures.isEmpty ? "none" : failures.joined(separator: "; ")
        return [
            "performance_acceptance=\(status)",
            "todayCoachMax=\(todayCoachMaxMilliseconds)",
            "rootNotificationMax=\(rootNotificationMaxMilliseconds)",
            "previewOnAppearRefreshes=\(workoutPreviewOnAppearRefreshes)",
            "failures=\(failureText)"
        ].joined(separator: " | ")
    }

    static func record(metric: PerformanceMetric, message: String) {
        guard isEnabled else { return }

        let line = "\(metric.rawValue) \(message)"
        print("PERF_ACCEPTANCE \(line)")
        recordFailureStrings(in: line)

        lock.lock()
        defer { lock.unlock() }

        switch metric {
        case .todayRouteAppear where message.contains("coach appeared in"):
            if let milliseconds = firstInteger(after: "coach appeared in ", in: message) {
                todayCoachMaxMilliseconds = max(todayCoachMaxMilliseconds, milliseconds)
                if milliseconds > 500 {
                    addFailureLocked("today.route.appear coach appeared in \(milliseconds)ms")
                }
            }
        case .workoutPreviewRenderSnapshot where message.contains("refresh onAppear"):
            workoutPreviewOnAppearRefreshes += 1
            if workoutPreviewOnAppearRefreshes > 1 {
                addFailureLocked("workout_preview.render_snapshot refresh onAppear repeated \(workoutPreviewOnAppearRefreshes)x")
            }
        case .workoutRouteNavigation where message.contains("appended route=coach"):
            if pendingWorkoutCoachAppend {
                addFailureLocked("workout.route.navigation duplicate appended route=coach without depth=0")
            }
            pendingWorkoutCoachAppend = true
        case .workoutRouteNavigation where message.contains("path_changed depth=0"):
            pendingWorkoutCoachAppend = false
        default:
            break
        }
    }

    static func recordCompletion(metric: PerformanceMetric, milliseconds: Int64) {
        guard isEnabled else { return }

        let line = "\(metric.rawValue) completed in \(milliseconds)ms"
        print("PERF_ACCEPTANCE \(line)")
        recordFailureStrings(in: line)

        lock.lock()
        defer { lock.unlock() }

        if metric == .rootNotificationRefresh {
            let value = Int(milliseconds)
            rootNotificationMaxMilliseconds = max(rootNotificationMaxMilliseconds, value)
            if value > 50 {
                addFailureLocked("root.notification.refresh completed in \(value)ms")
            }
        }
    }

    private static let lock = NSLock()
    private static var failures: [String] = []
    private static var failureSet = Set<String>()
    private static var todayCoachMaxMilliseconds = 0
    private static var rootNotificationMaxMilliseconds = 0
    private static var workoutPreviewOnAppearRefreshes = 0
    private static var pendingWorkoutCoachAppend = false

    private static let failureStrings = [
        "Potential Structural Swift Concurrency Issue: unsafeForcedSync",
        "Gesture: System gesture gate timed out",
        "Unable to simultaneously satisfy constraints",
        "_UIButtonBarButton",
        "_UIModernBarButton",
        "ButtonWrapper.width",
        "UIView-Encapsulated-Layout-Width == 0"
    ]

    private static func recordFailureStrings(in line: String) {
        let matches = failureStrings.filter { line.contains($0) }
        guard !matches.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        for match in matches {
            addFailureLocked(match)
        }
    }

    private static func addFailureLocked(_ message: String) {
        guard !failureSet.contains(message) else { return }
        failureSet.insert(message)
        failures.append(message)
    }

    private static func firstInteger(after needle: String, in text: String) -> Int? {
        guard let range = text.range(of: needle) else { return nil }
        let suffix = text[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}
#endif
