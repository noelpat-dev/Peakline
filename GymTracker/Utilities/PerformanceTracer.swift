import Foundation
import os

enum PerformanceMetric: String {
    case appLaunchPreparation = "app.launch.preparation"
    case rootNotificationRefresh = "root.notification.refresh"
    case splitsDashboard = "splits.dashboard"
    case todayRouteSelection = "today.route.selection"
    case todayRouteAppear = "today.route.appear"
    case todayCoachContentMount = "today.coach.content_mount"
    case todaySnapshot = "today.snapshot"
    case todayCoachSnapshot = "today.coach.snapshot"
    case todaySleepReadiness = "today.sleep_readiness"
    case workoutStartSleepReadiness = "workout_start.sleep_readiness"
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
    case nutritionHealthKitRowStatus = "nutrition.healthkit_row_status"
    case nutritionHealthKitSync = "nutrition.healthkit_sync"
    case barcodeLookup = "barcode.lookup"
    case openFoodFactsRequest = "open_food_facts.request"
    case nutritionOCR = "nutrition.ocr"
    case nutritionOCRParse = "nutrition.ocr_parse"
    case progressFetchExercises = "progress.fetch_exercises"
    case progressAnalytics = "progress.analytics"
    case prTimelineAnalytics = "pr_timeline.analytics"
}

enum PerformanceTracer {
    static func mark(_ metric: PerformanceMetric, _ message: String = "") {
        #if DEBUG
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
