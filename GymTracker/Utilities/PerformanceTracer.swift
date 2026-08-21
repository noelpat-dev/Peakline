import Foundation
import os

enum PerformanceMetric: String {
    case appLaunchPreparation = "app.launch.preparation"
    case startupAccountCheck = "startup.account_check"
    case startupBackupMetadata = "startup.backup_metadata"
    case startupLocalPreparation = "startup.local_preparation"
    case startupSnapshotPreparation = "startup.snapshot_preparation"
    case startupCriticalReady = "startup.critical_ready"
    case startupPresentationStart = "startup.presentation.start"
    case startupPresentationSlow = "startup.presentation.slow"
    case startupRevealStart = "startup.reveal.start"
    case startupRevealEnd = "startup.reveal.end"
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
    case warmStartLoad = "warm_start.load"
    case warmStartCacheHit = "warm_start.cache_hit"
    case warmStartCacheMiss = "warm_start.cache_miss"
    case warmStartDecodeFailed = "warm_start.decode_failed"
    case warmStartPersist = "warm_start.persist"
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
    case workoutPreviewWarmCache = "workout_preview.warm_cache"
    case previewRouteTap = "preview.route.tap"
    case previewRouteStartButtonVisible = "preview.route.start_button_visible"
    case previewHydrationBegin = "preview.hydration.begin"
    case previewHydrationExerciseRowsReady = "preview.hydration.exercise_rows_ready"
    case previewHydrationTargetSuggestionsReady = "preview.hydration.target_suggestions_ready"
    case previewHydrationCoachGuidanceReady = "preview.hydration.coach_guidance_ready"
    case previewHydrationFullContentReady = "preview.hydration.full_content_ready"
    case previewOnAppearRefresh = "preview.onAppear.refresh"
    case motionTapFeedback = "motion.tap.feedback"
    case motionChipSelect = "motion.chip.select"
    case motionRatingSelect = "motion.rating.select"
    case motionCheckInSelect = "motion.checkin.select"
    case checkInSheetPresentation = "checkin.sheet.presentation"
    case motionPreviewModeChange = "motion.preview.mode_change"
    case motionHistoryRowOpen = "motion.history.row_open"
    case motionRoutePush = "motion.route.push"
    case motionTabSelect = "motion.tab.select"
    case motionLoadingReveal = "motion.loading.reveal"
    case motionSetCompletion = "motion.set_completion"
    case navigationInteraction = "navigation.interaction"
    case navigationPersistence = "navigation.persistence"
    case sleepAnalyticsCache = "sleep.analytics.cache"
    case sleepReadinessCache = "sleep_readiness.cache"
    case coachSleepAnalytics = "coach.sleep_analytics"
    case coachSnapshot = "coach.snapshot"
    case coachDerivedMetrics = "coach.derived_metrics"
    case coachWeeklyReview = "coach.weekly_review"
    case nutritionDashboardSnapshot = "nutrition.dashboard_snapshot"
    case savedFoodsSnapshot = "saved_foods.snapshot"
    case swipeRevealInteraction = "swipe_reveal.interaction"
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
    case historyScroll = "history.scroll"
    case sleepSessionQuality = "sleep.session_quality"
}

enum PerformanceTracer {
    static func mark(_ metric: PerformanceMetric, _ message: String = "") {
        #if DEBUG
        PerformanceAcceptanceState.record(metric: metric, message: message)
        if isConsoleLoggingEnabled {
            logger.debug("\(metric.rawValue, privacy: .public) \(message, privacy: .public)")
        }
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
            if isConsoleLoggingEnabled {
                logger.debug("\(metric.rawValue, privacy: .public) completed in \(milliseconds)ms")
            }
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
            if isConsoleLoggingEnabled {
                logger.debug("\(metric.rawValue, privacy: .public) completed in \(milliseconds)ms")
            }
        }
        #endif

        return try await work()
    }

    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Peakline"
    private static let logger = Logger(subsystem: subsystem, category: "Performance")
    private static let signpostLog = OSLog(subsystem: subsystem, category: "Performance")
    private static let signpostName: StaticString = "PeaklinePerformance"

    private static var isConsoleLoggingEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PeaklinePerformanceConsoleLogging")
    }
    #endif
}

#if DEBUG
enum PerformanceAcceptanceState {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PerformanceAcceptanceMode") ||
            ProcessInfo.processInfo.environment["PERFORMANCE_ACCEPTANCE_MODE"] == "1"
    }

    static var summary: String {
        lock.lock()
        defer { lock.unlock() }

        let status = failures.isEmpty ? "PASS" : "FAIL"
        let failureText = failures.isEmpty ? "none" : failures.joined(separator: "; ")
        let routeTimingText = navigationRouteMaxMilliseconds
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let rootTabTimingText = rootTabMaxMillisecondsByName
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        return [
            "performance_acceptance=\(status)",
            "startupLocalMax=\(startupLocalMaxMilliseconds)",
            "startupSnapshotMax=\(startupSnapshotMaxMilliseconds)",
            "todayCoachMax=\(todayCoachMaxMilliseconds)",
            "coachPreviewMax=\(coachPreviewMaxMilliseconds)",
            "rootTabMax=\(rootTabMaxMilliseconds)",
            "rootTabTimings=\(rootTabTimingText)",
            "rootNotificationMax=\(rootNotificationMaxMilliseconds)",
            "routeTimings=\(routeTimingText)",
            "previewWarmCacheHits=\(workoutPreviewWarmCacheHits)",
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
        case .workoutPreviewWarmCache where message.hasPrefix("hit"):
            workoutPreviewWarmCacheHits += 1
        case .workoutRouteNavigation where message.contains("appended route=coach"):
            if pendingWorkoutCoachAppend {
                addFailureLocked("workout.route.navigation duplicate appended route=coach without depth=0")
            }
            pendingWorkoutCoachAppend = true
        case .workoutRouteNavigation where message.contains("path_changed depth=0"):
            pendingWorkoutCoachAppend = false
        case .checkInSheetPresentation where message.contains("requested"):
            if pendingCheckInPresentation {
                addFailureLocked("checkin.sheet.presentation duplicate request")
            }
            pendingCheckInPresentation = true
        case .checkInSheetPresentation where message.contains("stable_frame elapsed_ms="):
            pendingCheckInPresentation = false
            if let milliseconds = firstInteger(after: "stable_frame elapsed_ms=", in: message),
               milliseconds > 500 {
                addFailureLocked("checkin.sheet.presentation stable frame in \(milliseconds)ms")
            }
        case .checkInSheetPresentation where message.contains("dismissed"):
            pendingCheckInPresentation = false
        case .motionCheckInSelect where message.contains("response_ms="):
            if let milliseconds = firstInteger(after: "response_ms=", in: message),
               milliseconds > 100 {
                addFailureLocked("motion.checkin.select response in \(milliseconds)ms")
            }
        case .motionTabSelect where message.contains("stable_frame"):
            if let milliseconds = firstInteger(after: "elapsed_ms=", in: message) {
                rootTabMaxMilliseconds = max(rootTabMaxMilliseconds, milliseconds)
                let tab = firstToken(after: "tab=", in: message) ?? "unknown"
                rootTabMaxMillisecondsByName[tab] = max(
                    rootTabMaxMillisecondsByName[tab] ?? 0,
                    milliseconds
                )
                if milliseconds > 300 {
                    addFailureLocked("motion.tab.select \(tab) stable frame in \(milliseconds)ms")
                }
            }
        case .navigationInteraction where message.contains("duplicate_mutation"):
            addFailureLocked("navigation.interaction duplicate mutation")
        case .navigationInteraction where message.contains("stable_frame"):
            if let milliseconds = firstInteger(after: "elapsed_ms=", in: message),
               let threshold = firstInteger(after: "threshold_ms=", in: message) {
                let key = firstToken(after: "key=", in: message) ?? "unknown"
                navigationRouteMaxMilliseconds[key] = max(
                    navigationRouteMaxMilliseconds[key] ?? 0,
                    milliseconds
                )
                if key.hasPrefix("coach.preview.") {
                    coachPreviewMaxMilliseconds = max(coachPreviewMaxMilliseconds, milliseconds)
                }
                if milliseconds > threshold {
                    addFailureLocked(
                        "navigation.interaction \(key) stable frame in \(milliseconds)ms above \(threshold)ms"
                    )
                }
            }
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

        switch metric {
        case .startupLocalPreparation:
            startupLocalMaxMilliseconds = max(startupLocalMaxMilliseconds, Int(milliseconds))
        case .startupSnapshotPreparation:
            startupSnapshotMaxMilliseconds = max(startupSnapshotMaxMilliseconds, Int(milliseconds))
        case .rootNotificationRefresh:
            let value = Int(milliseconds)
            rootNotificationMaxMilliseconds = max(rootNotificationMaxMilliseconds, value)
            if value > 50 {
                addFailureLocked("root.notification.refresh completed in \(value)ms")
            }
        default:
            break
        }
    }

    private static let lock = NSLock()
    private static var failures: [String] = []
    private static var failureSet = Set<String>()
    private static var startupLocalMaxMilliseconds = 0
    private static var startupSnapshotMaxMilliseconds = 0
    private static var todayCoachMaxMilliseconds = 0
    private static var coachPreviewMaxMilliseconds = 0
    private static var rootTabMaxMilliseconds = 0
    private static var rootTabMaxMillisecondsByName: [String: Int] = [:]
    private static var rootNotificationMaxMilliseconds = 0
    private static var workoutPreviewWarmCacheHits = 0
    private static var workoutPreviewOnAppearRefreshes = 0
    private static var navigationRouteMaxMilliseconds: [String: Int] = [:]
    private static var pendingWorkoutCoachAppend = false
    private static var pendingCheckInPresentation = false

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

    private static func firstToken(after needle: String, in text: String) -> String? {
        guard let range = text.range(of: needle) else { return nil }
        let suffix = text[range.upperBound...]
        let token = suffix.prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }
}
#endif
