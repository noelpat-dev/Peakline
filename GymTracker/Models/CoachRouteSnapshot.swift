import Foundation

struct CoachRouteRenderSnapshot: @unchecked Sendable {
    /// Monotonic source generation for the complete route payload. Readiness,
    /// the training call, and the recommended split must be published as one
    /// generation so a newer intelligence score cannot be paired with an
    /// older actionable decision.
    let sourceGeneration: Int
    /// Exact startup/live refresh guards; partial intelligence updates invalidate only their guard.
    let intelligenceInputSignature: String?
    let trainingInputSignature: String?
    let intelligence: CoachIntelligenceSnapshot
    let weeklyReview: WeeklyReview?
    let derivedMetrics: CoachDerivedMetrics
    let sleepAnalytics: SleepAnalyticsSnapshot
    let dailyDecision: CoachDailyDecision
    let practicalWeeklyReview: CoachWeeklyReviewSnapshot
    let recommendedSplit: WorkoutPreviewSplit?

    init(
        intelligence: CoachIntelligenceSnapshot,
        weeklyReview: WeeklyReview?,
        derivedMetrics: CoachDerivedMetrics,
        sleepAnalytics: SleepAnalyticsSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit? = nil,
        sourceGeneration: Int = 0,
        intelligenceInputSignature: String? = nil,
        trainingInputSignature: String? = nil
    ) {
        self.intelligenceInputSignature = intelligenceInputSignature
        self.trainingInputSignature = trainingInputSignature
        self.sourceGeneration = sourceGeneration
        self.intelligence = intelligence.routeCacheValueSnapshot
        self.weeklyReview = weeklyReview
        self.derivedMetrics = derivedMetrics
        self.sleepAnalytics = sleepAnalytics
        self.recommendedSplit = recommendedSplit

        let primaryTarget = derivedMetrics.targetSuggestions.first
        let badgeState: CoachBadgeState
        if trainingCall.recommendedMode == .recovery {
            badgeState = .recovery
        } else if let primaryTarget {
            badgeState = CoachBadgeState(recommendationType: primaryTarget.recommendationType)
        } else {
            badgeState = .baseline
        }

        let splitName = trainingCall.recommendedSplitName
        self.dailyDecision = CoachDailyDecision(
            recommendedSplitName: splitName,
            recommendedMode: trainingCall.recommendedMode,
            headline: splitName ?? trainingCall.title,
            targetLine: trainingCall.targetSummary,
            shortReason: trainingCall.reason,
            confidenceLabel: trainingCall.confidence.displayName,
            badgeState: badgeState,
            canOpenPreview: splitName != nil,
            primaryActionTitle: "Open \(trainingCall.recommendedMode.displayName) Preview",
            nextStep: splitName.map { "Next: preview \($0), adjust if needed, then start the session." }
                ?? "Create or activate a split to prepare a workout preview.",
            whySignals: Array(trainingCall.auditSignals.prefix(3)).enumerated().map { index, signal in
                CoachDecisionSignal(
                    title: index == 0 ? "Programme" : "Signal \(index + 1)",
                    message: signal,
                    systemImage: index == 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                )
            },
            primaryTarget: primaryTarget,
            additionalTargetCount: max(0, derivedMetrics.targetSuggestions.count - (primaryTarget == nil ? 0 : 1)),
            targetFallback: "Complete clean working sets to sharpen the next target.",
            modeReason: trainingCall.guardrailNotes.first ?? trainingCall.reason,
            trainingCall: trainingCall
        )

        self.practicalWeeklyReview = CoachWeeklyReviewSnapshot(
            bestWin: weeklyReview?.highlights.first?.message ?? "Finish a few sessions to build a weekly win.",
            mainRisk: weeklyReview?.watchlist.first?.message ?? "No major risk is standing out right now.",
            nextAdjustment: weeklyReview?.nextDecision.reason ?? trainingCall.reason,
            splitBalance: weeklyReview.map {
                "\($0.splitConsistency.countDescription(separator: " / ")). \($0.splitConsistency.balanceDescription)"
            } ?? "Active programme coverage will appear once this week has completed sessions.",
            recoveryNote: intelligence.weeklySummary.recommendedFocus
        )
    }

    func replacing(
        intelligence: CoachIntelligenceSnapshot,
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: WorkoutPreviewSplit?,
        sourceGeneration: Int
    ) -> CoachRouteRenderSnapshot {
        CoachRouteRenderSnapshot(
            intelligence: intelligence,
            weeklyReview: weeklyReview,
            derivedMetrics: derivedMetrics,
            sleepAnalytics: sleepAnalytics,
            trainingCall: trainingCall,
            recommendedSplit: recommendedSplit,
            sourceGeneration: sourceGeneration,
            trainingInputSignature: trainingInputSignature
        )
    }

    func withSourceGeneration(_ sourceGeneration: Int) -> CoachRouteRenderSnapshot {
        CoachRouteRenderSnapshot(
            intelligence: intelligence,
            weeklyReview: weeklyReview,
            derivedMetrics: derivedMetrics,
            sleepAnalytics: sleepAnalytics,
            trainingCall: dailyDecision.trainingCall,
            recommendedSplit: recommendedSplit,
            sourceGeneration: sourceGeneration,
            intelligenceInputSignature: intelligenceInputSignature,
            trainingInputSignature: trainingInputSignature
        )
    }
}

private extension CoachIntelligenceSnapshot {
    var routeCacheValueSnapshot: CoachIntelligenceSnapshot {
        CoachIntelligenceSnapshot(
            readiness: readiness.routeCacheValueScore,
            weeklySummary: weeklySummary,
            trends: trends,
            insights: insights,
            fatigueRisk: fatigueRisk,
            muscleFatigue: muscleFatigue,
            liftInsights: liftInsights,
            adaptiveGuidance: adaptiveGuidance,
            diagnostics: diagnostics
        )
    }
}

private extension ReadinessScore {
    var routeCacheValueScore: ReadinessScore {
        ReadinessScore(
            value: value,
            category: category,
            confidence: confidence,
            recommendation: recommendation,
            factors: factors,
            generatedAt: generatedAt,
            checkIn: nil,
            workoutAdjustment: workoutAdjustment,
            recoveryNote: recoveryNote
        )
    }
}

struct CoachDerivedMetrics: Sendable {
    let summary: CoachRecommendationSummary
    let recentPRs: [PRRecord]
    let targetSuggestions: [TargetSuggestion]
    let weeklyWorkoutCount: Int
    let weeklyWorkingSetCount: Int
    let progressOpportunityInsights: [CoachInsight]

    static let placeholder = CoachDerivedMetrics(
        summary: .placeholder,
        recentPRs: [],
        targetSuggestions: [],
        weeklyWorkoutCount: 0,
        weeklyWorkingSetCount: 0,
        progressOpportunityInsights: []
    )

    static func make(
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> CoachDerivedMetrics {
        let canonicalDecision = TrainingDecisionService().decision(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let summary = CoachRecommendationEngine().makeSummary(
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let prRecords = TrainingAnalyticsService().prTimeline(from: completedSessions)
        let targetSuggestions = makeTargetSuggestions(
            splitName: canonicalDecision.recommendedSplitName,
            activeSplits: activeSplits,
            completedSessions: completedSessions
        )
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 7 * 24 * 60 * 60)
        let weekSessions = completedSessions.filter {
            $0.completed && $0.date >= week.start && $0.date < week.end
        }
        let workingSets = weekSessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap { log in
                log.setLogs.filter { $0.completed && !$0.isWarmup }
            }.count
        }
        let progressInsights = targetSuggestions
            .filter { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }
            .prefix(4)
            .map { suggestion in
                CoachInsight(
                    title: suggestion.exerciseName,
                    message: suggestion.reason,
                    severity: .positive,
                    relatedExerciseName: suggestion.exerciseName,
                    relatedSplitName: canonicalDecision.recommendedSplitName
                )
            }

        return CoachDerivedMetrics(
            summary: summary,
            recentPRs: Array(prRecords.prefix(3)),
            targetSuggestions: targetSuggestions,
            weeklyWorkoutCount: weekSessions.count,
            weeklyWorkingSetCount: workingSets,
            progressOpportunityInsights: progressInsights
        )
    }

    private static func makeTargetSuggestions(
        splitName: String?,
        activeSplits: [TrainingSplitSnapshot],
        completedSessions: [WorkoutAnalyticsSession]
    ) -> [TargetSuggestion] {
        guard let recommendedSplit = activeSplits.first(where: { $0.name == splitName }) else {
            return []
        }

        return recommendedSplit.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(4)
            .map { exercise in
                TargetSuggestionService().suggestion(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseNameSnapshot,
                    minReps: exercise.minReps,
                    maxReps: exercise.maxReps,
                    completedSessions: completedSessions
                )
            }
    }
}

private extension CoachRecommendationSummary {
    static var placeholder: CoachRecommendationSummary {
        CoachRecommendationSummary(
            recommendedSplitName: nil,
            reason: "Preparing recommendation.",
            exerciseRecommendations: [],
            recoveryWarnings: [],
            weeklyInsights: [],
            trainingDecision: TrainingDecision(
                recommendedSplitName: nil,
                recommendedMode: .full,
                action: .buildBaseline,
                title: "Preparing recommendation",
                reason: "Preparing recommendation."
            )
        )
    }
}

struct CoachDailyDecision: Equatable {
    let recommendedSplitName: String?
    let recommendedMode: WorkoutMode
    let headline: String
    let targetLine: String?
    let shortReason: String
    let confidenceLabel: String
    let badgeState: CoachBadgeState
    let canOpenPreview: Bool
    let primaryActionTitle: String
    let nextStep: String
    let whySignals: [CoachDecisionSignal]
    let primaryTarget: TargetSuggestion?
    let additionalTargetCount: Int
    let targetFallback: String
    let modeReason: String
    let trainingCall: TrainingCallSnapshot

    static let placeholder = CoachDailyDecision(
        recommendedSplitName: nil,
        recommendedMode: .full,
        headline: "Preparing Today's Call",
        targetLine: nil,
        shortReason: "Peakline is preparing your next training decision.",
        confidenceLabel: "Building confidence",
        badgeState: .baseline,
        canOpenPreview: false,
        primaryActionTitle: "Open Preview",
        nextStep: "Next: wait a moment while Peakline refreshes your current coaching snapshot.",
        whySignals: [
            CoachDecisionSignal(
                title: "Rotation",
                message: "Coach is checking your recent split rotation.",
                systemImage: "calendar.badge.clock"
            ),
            CoachDecisionSignal(
                title: "Recovery",
                message: "Coach is refreshing readiness and recovery signals.",
                systemImage: "gauge.with.dots.needle.bottom.50percent"
            )
        ],
        primaryTarget: nil,
        additionalTargetCount: 0,
        targetFallback: "Complete a workout to unlock a clearer next target.",
        modeReason: "Peakline is confirming which mode fits today best.",
        trainingCall: .placeholder
    )
}

struct CoachWeeklyReviewSnapshot: Equatable {
    let bestWin: String
    let mainRisk: String
    let nextAdjustment: String
    let splitBalance: String
    let recoveryNote: String

    static let placeholder = CoachWeeklyReviewSnapshot(
        bestWin: "Finish workouts to build a weekly win.",
        mainRisk: "The weekly watchlist is still building.",
        nextAdjustment: "Keep logging sessions so the next adjustment gets sharper.",
        splitBalance: "Weekly split balance is still building.",
        recoveryNote: "Recovery guidance will appear once enough recent signals are available."
    )
}

struct CoachDecisionSignal: Identifiable, Equatable {
    let title: String
    let message: String
    let systemImage: String

    var id: String {
        "\(title)|\(message)|\(systemImage)"
    }
}
