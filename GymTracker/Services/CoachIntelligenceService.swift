import Foundation

struct CoachIntelligenceService {
    private let calendar: Calendar
    private let sleepScoring = SleepScoringService()
    private let hydrationService = HydrationService()
    private let nutritionSummaryService = NutritionSummaryService()
    private let trendService = NutritionTrendService()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    static func emptySnapshot() -> CoachIntelligenceSnapshot {
        CoachIntelligenceService().snapshot(
            activeSplits: [],
            exercises: [],
            sleepSessions: [],
            napSessions: [],
            hydrationEntries: [],
            completedWorkouts: [],
            foodLogs: [],
            checkIns: [],
            sleepSettings: .default,
            hydrationTargetML: 2500,
            nutritionGoal: .empty
        )
    }

    func readiness(
        for date: Date = .now,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal
    ) -> ReadinessScore {
        let sleepSummaries = sleepScoring.summaries(
            from: sleepSessions,
            naps: napSessions,
            workouts: completedWorkouts,
            settings: sleepSettings,
            days: 14,
            endingOn: date,
            calendar: calendar
        )

        return readiness(
            for: date,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            sleepSummaries: sleepSummaries
        )
    }

    private func readiness(
        for date: Date = .now,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        sleepSummaries: [SleepSummary]?
    ) -> ReadinessScore {
        let today = calendar.startOfDay(for: date)
        let checkIn = todayCheckIn(from: checkIns, date: today)
        let sleep = sleepSignal(
            date: today,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            workouts: completedWorkouts,
            settings: sleepSettings,
            sleepSummaries: sleepSummaries
        )
        let training = trainingSignal(date: today, workouts: completedWorkouts)
        let hydration = hydrationSignal(date: today, entries: hydrationEntries, targetML: hydrationTargetML)
        let checkInSignal = subjectiveSignal(from: checkIn)
        let nutrition = nutritionSignal(date: today, foodLogs: foodLogs, workouts: completedWorkouts, goal: nutritionGoal)

        let signals = [sleep, training, hydration, checkInSignal, nutrition]
        let weightedScore = signals.reduce(0.0) { $0 + Double($1.score) * $1.weight }
        let totalWeight = max(signals.reduce(0.0) { $0 + $1.weight }, 1)
        let value = min(100, max(0, Int((weightedScore / totalWeight).rounded())))
        let category = ReadinessCategory(score: value)
        let factors = signals.map(\.factor)
        let confidence = confidence(for: signals, checkIn: checkIn)
        let recommendation = recommendation(
            value: value,
            category: category,
            confidence: confidence,
            factors: factors
        )

        return ReadinessScore(
            value: value,
            category: category,
            confidence: confidence,
            recommendation: recommendation,
            factors: factors,
            generatedAt: date,
            checkIn: checkIn,
            workoutAdjustment: workoutAdjustment(for: category, factors: factors),
            recoveryNote: recoveryNote(for: confidence, factors: factors)
        )
    }

    func snapshot(
        for date: Date = .now,
        activeSplits: [TrainingSplit] = [],
        exercises: [Exercise] = [],
        plannedExerciseIDs: [UUID] = [],
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        exerciseMetadata: [CoachExerciseMetadata] = [],
        coachActionHistory: [CoachActionHistoryEntry] = [],
        recommendationFeedback: [CoachRecommendationFeedback] = [],
        savedDeloadBlocks: [SavedCoachDeloadBlock] = []
    ) -> CoachIntelligenceSnapshot {
        snapshot(
            for: date,
            activeSplits: activeSplits,
            exercises: exercises,
            plannedExerciseIDs: plannedExerciseIDs,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            exerciseMetadata: exerciseMetadata,
            coachActionHistory: coachActionHistory,
            recommendationFeedback: recommendationFeedback,
            savedDeloadBlocks: savedDeloadBlocks,
            coachPreferences: .default,
            splitMetadata: []
        )
    }

    func snapshot(
        for date: Date = .now,
        activeSplits: [TrainingSplit] = [],
        exercises: [Exercise] = [],
        plannedExerciseIDs: [UUID] = [],
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        exerciseMetadata: [CoachExerciseMetadata] = [],
        coachActionHistory: [CoachActionHistoryEntry] = [],
        recommendationFeedback: [CoachRecommendationFeedback] = [],
        savedDeloadBlocks: [SavedCoachDeloadBlock] = [],
        coachPreferences: CoachPreferencesSnapshot,
        splitMetadata: [CoachSplitMetadata] = []
    ) -> CoachIntelligenceSnapshot {
        let sleepSummaries = sleepScoring.summaries(
            from: sleepSessions,
            naps: napSessions,
            workouts: completedWorkouts,
            settings: sleepSettings,
            days: 14,
            endingOn: date,
            calendar: calendar
        )
        let readinessSeries = readinessProxySeries(
            endingOn: date,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            sleepSummaries: sleepSummaries
        )
        let readiness = readiness(
            for: date,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            sleepSummaries: sleepSummaries
        )
        let trends = trendSummary(
            date: date,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            readinessSeries: readinessSeries,
            sleepSummaries: sleepSummaries
        )
        let fatigueRisk = fatigueRisk(
            date: date,
            readiness: readiness,
            trends: trends,
            completedWorkouts: completedWorkouts,
            checkIns: checkIns
        )
        let muscleFatigue = muscleGroupFatigue(
            date: date,
            workouts: completedWorkouts,
            exercises: exercises,
            checkIns: checkIns
        )
        let liftInsights = liftProgressInsights(
            workouts: completedWorkouts,
            fatigueRisk: fatigueRisk
        )
        let weeklySummary = weeklySummary(
            date: date,
            readiness: readiness,
            trends: trends,
            fatigueRisk: fatigueRisk,
            completedWorkouts: completedWorkouts,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            readinessSeries: readinessSeries
        )
        let insights = weeklyInsights(
            date: date,
            readiness: readiness,
            trends: trends,
            fatigueRisk: fatigueRisk,
            muscleFatigue: muscleFatigue,
            liftInsights: liftInsights,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            hydrationEntries: hydrationEntries,
            activeSplits: activeSplits,
            hydrationTargetML: hydrationTargetML
        )
        let guidance = adaptiveGuidance(
            readiness: readiness,
            fatigueRisk: fatigueRisk,
            muscleFatigue: muscleFatigue,
            exercises: exercises,
            plannedExerciseIDs: plannedExerciseIDs
        )
        let diagnostics = coachDiagnostics(
            readiness: readiness,
            fatigueRisk: fatigueRisk,
            adaptiveGuidance: guidance,
            plannedExerciseIDs: plannedExerciseIDs,
            exerciseMetadata: exerciseMetadata,
            coachActionHistory: coachActionHistory,
            recommendationFeedback: recommendationFeedback,
            savedDeloadBlocks: savedDeloadBlocks,
            coachPreferences: coachPreferences,
            splitMetadata: splitMetadata
        )

        return CoachIntelligenceSnapshot(
            readiness: readiness,
            weeklySummary: weeklySummary,
            trends: trends,
            insights: insights,
            fatigueRisk: fatigueRisk,
            muscleFatigue: muscleFatigue,
            liftInsights: liftInsights,
            adaptiveGuidance: guidance,
            diagnostics: diagnostics
        )
    }

    private func todayCheckIn(from checkIns: [DailyCoachCheckIn], date: Date) -> DailyCoachCheckIn? {
        checkIns
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private func trendSummary(
        date: Date,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        readinessSeries: [(date: Date, value: Double)],
        sleepSummaries: [SleepSummary]
    ) -> CoachTrendSummary {
        let currentDates = dateRange(endingOn: date, days: 7)
        let previousDates = previousDateRange(endingOn: date, days: 7)
        let sleepByDate = Dictionary(uniqueKeysWithValues: sleepSummaries.map { (calendar.startOfDay(for: $0.date), $0) })
        let currentWorkouts = workouts(in: currentDates, from: completedWorkouts)
        let previousWorkouts = workouts(in: previousDates, from: completedWorkouts)
        let currentHardSessions = currentWorkouts.filter(isHardSession).count
        let previousHardSessions = previousWorkouts.filter(isHardSession).count
        let currentSets = workingSetCount(in: currentWorkouts)
        let previousSets = workingSetCount(in: previousWorkouts)

        return CoachTrendSummary(
            readiness: trend(
                title: "Readiness",
                current: values(readinessSeries, in: currentDates),
                previous: values(readinessSeries, in: previousDates),
                threshold: 4,
                higherIsBetter: true,
                unit: "score"
            ),
            sleepDuration: trend(
                title: "Sleep duration",
                current: currentDates.compactMap { sleepByDate[$0]?.primarySession == nil ? nil : Double(sleepByDate[$0]?.totalSleepMinutes ?? 0) },
                previous: previousDates.compactMap { sleepByDate[$0]?.primarySession == nil ? nil : Double(sleepByDate[$0]?.totalSleepMinutes ?? 0) },
                threshold: 30,
                higherIsBetter: true,
                unit: "minutes"
            ),
            sleepQuality: trend(
                title: "Sleep quality",
                current: currentDates.compactMap { sleepByDate[$0]?.qualityRating.map(Double.init) },
                previous: previousDates.compactMap { sleepByDate[$0]?.qualityRating.map(Double.init) },
                threshold: 0.4,
                higherIsBetter: true,
                unit: "rating"
            ),
            hydrationConsistency: consistencyTrend(
                title: "Hydration consistency",
                currentDates: currentDates,
                previousDates: previousDates,
                target: 4,
                currentCount: hydrationHitDays(in: currentDates, entries: hydrationEntries, targetML: hydrationTargetML),
                previousCount: hydrationHitDays(in: previousDates, entries: hydrationEntries, targetML: hydrationTargetML)
            ),
            nutritionConsistency: consistencyTrend(
                title: "Nutrition consistency",
                currentDates: currentDates,
                previousDates: previousDates,
                target: 4,
                currentCount: nutritionLoggedDays(in: currentDates, foodLogs: foodLogs),
                previousCount: nutritionLoggedDays(in: previousDates, foodLogs: foodLogs)
            ),
            workoutFrequency: countTrend(
                title: "Workout frequency",
                current: currentWorkouts.count,
                previous: previousWorkouts.count,
                threshold: 1,
                higherIsBetter: true
            ),
            setVolume: countTrend(
                title: "Weekly set volume",
                current: currentSets,
                previous: previousSets,
                threshold: 8,
                higherIsBetter: true
            ),
            hardSessionFrequency: countTrend(
                title: "Hard sessions",
                current: currentHardSessions,
                previous: previousHardSessions,
                threshold: 1,
                higherIsBetter: false
            ),
            energy: checkInTrend(title: "Energy", dates: currentDates, previousDates: previousDates, checkIns: checkIns, keyPath: \.energy, higherIsBetter: true),
            soreness: checkInTrend(title: "Soreness", dates: currentDates, previousDates: previousDates, checkIns: checkIns, keyPath: \.soreness, higherIsBetter: false),
            stress: checkInTrend(title: "Stress", dates: currentDates, previousDates: previousDates, checkIns: checkIns, keyPath: \.stress, higherIsBetter: false),
            motivation: checkInTrend(title: "Motivation", dates: currentDates, previousDates: previousDates, checkIns: checkIns, keyPath: \.motivation, higherIsBetter: true)
        )
    }

    private func fatigueRisk(
        date: Date,
        readiness: ReadinessScore,
        trends: CoachTrendSummary,
        completedWorkouts: [WorkoutSession],
        checkIns: [DailyCoachCheckIn]
    ) -> CoachFatigueRisk {
        let recentWorkouts = workouts(in: dateRange(endingOn: date, days: 7), from: completedWorkouts)
        let previousWorkouts = workouts(in: previousDateRange(endingOn: date, days: 7), from: completedWorkouts)
        let recentSets = workingSetCount(in: recentWorkouts)
        let previousSets = workingSetCount(in: previousWorkouts)
        let hardSessions = recentWorkouts.filter(isHardSession).count
        let consecutiveDays = consecutiveTrainingDays(endingOn: date, workouts: completedWorkouts)
        let checkIn = todayCheckIn(from: checkIns, date: calendar.startOfDay(for: date))

        var factors: [String] = []

        if readiness.value < 55 || trends.readiness.direction == .declining {
            factors.append("Readiness is low or trending down.")
        }
        if hardSessions >= 3 {
            factors.append("\(hardSessions) hard sessions are logged in the last 7 days.")
        } else if hardSessions == 2 {
            factors.append("Two hard sessions are already in the last 7 days.")
        }
        if previousSets >= 10, Double(recentSets) > Double(previousSets) * 1.35 {
            factors.append("Weekly set volume is up sharply from the previous week.")
        } else if recentSets >= 50 {
            factors.append("\(recentSets) working sets are logged in the last 7 days.")
        }
        if consecutiveDays >= 3 {
            factors.append("\(consecutiveDays) consecutive training days are logged.")
        }
        if let checkIn, checkIn.soreness >= 4 {
            factors.append("Soreness check-in is elevated.")
        }
        if let checkIn, checkIn.energy <= 2 {
            factors.append("Energy check-in is low.")
        }
        if readiness.factors.contains(where: { $0.kind == .sleep && $0.impact == .negative }) {
            factors.append("Sleep is limiting today's readiness.")
        }
        if readiness.factors.contains(where: { ($0.kind == .hydration || $0.kind == .nutrition) && $0.impact == .negative }) {
            factors.append("Fuel or hydration consistency is limiting recovery confidence.")
        }

        let level: CoachFatigueRiskLevel
        switch factors.count {
        case 0...1:
            level = .low
        case 2:
            level = .moderate
        case 3:
            level = .high
        default:
            level = .deloadWatch
        }

        let title: String
        let summary: String
        let action: String

        switch level {
        case .low:
            title = "Fatigue looks manageable"
            summary = "Recent training and recovery signals do not show major accumulated fatigue."
            action = "Train as planned and keep logging recovery signals."
        case .moderate:
            title = "Fatigue is building"
            summary = "A few recent signals suggest keeping today's session controlled."
            action = "Maintain the plan, but avoid extra volume."
        case .high:
            title = "Fatigue is elevated"
            summary = "Several recent signals point to accumulated fatigue."
            action = "Reduce accessory volume by 10-20% and keep compounds technique-focused."
        case .deloadWatch:
            title = "Deload watch"
            summary = "Multiple warning signs are present. Keep this advisory and user-controlled."
            action = "Consider a recovery day or lighter week if readiness stays low."
        }

        return CoachFatigueRisk(
            level: level,
            title: title,
            summary: summary,
            factors: factors.isEmpty ? ["Recent logs look balanced."] : factors,
            recommendedAction: action,
            confidence: factors.count >= 3 ? .high : recentWorkouts.count >= 2 || checkIn != nil ? .medium : .low
        )
    }

    private func muscleGroupFatigue(
        date: Date,
        workouts: [WorkoutSession],
        exercises: [Exercise],
        checkIns: [DailyCoachCheckIn]
    ) -> [MuscleGroupFatigue] {
        let exerciseLookup = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let recentWorkouts = workouts.filter {
            let days = daysBetween($0.date, and: date)
            return days <= 7 && $0.date <= date.endOfDay(using: calendar)
        }
        let allHistoryGroups = Set(workouts.flatMap { session in
            session.exerciseLogs.flatMap { muscleGroups(for: $0, exercisesByID: exerciseLookup) }
        })
        let sorenessElevated = todayCheckIn(from: checkIns, date: calendar.startOfDay(for: date))?.soreness ?? 0 >= 4

        return majorMuscleGroups.map { group in
            var weightedLoad = 0.0
            var rawSets = 0
            var latestDate: Date?

            for session in recentWorkouts {
                let days = daysBetween(session.date, and: date)
                let recencyWeight: Double
                switch days {
                case 0...1:
                    recencyWeight = 1.0
                case 2...3:
                    recencyWeight = 0.7
                default:
                    recencyWeight = 0.45
                }

                for log in session.exerciseLogs {
                    let groups = muscleGroups(for: log, exercisesByID: exerciseLookup)
                    guard groups.contains(group) else { continue }
                    let sets = completedWorkingSets(from: log).count
                    rawSets += sets
                    weightedLoad += Double(sets) * recencyWeight
                    latestDate = latestDate.map { max($0, session.date) } ?? session.date
                }
            }

            let state: MuscleFatigueState
            if rawSets == 0 {
                state = allHistoryGroups.contains(group) ? .fresh : .unknown
            } else if weightedLoad >= 12 || (sorenessElevated && weightedLoad >= 7) {
                state = .fatigued
            } else if weightedLoad >= 7 {
                state = .loaded
            } else if weightedLoad >= 2 {
                state = .normal
            } else {
                state = .fresh
            }

            let daysSinceLast = latestDate.map { daysBetween($0, and: date) }
            let detail: String

            switch state {
            case .unknown:
                detail = "No recent group history yet."
            case .fresh:
                detail = daysSinceLast.map { "Last trained \($0) days ago." } ?? "No recent sets logged."
            case .normal:
                detail = "\(rawSets) recent working sets."
            case .loaded:
                detail = "\(rawSets) recent working sets. Keep warm-ups deliberate."
            case .fatigued:
                detail = "\(rawSets) recent working sets. Consider controlled volume."
            }

            return MuscleGroupFatigue(
                muscleGroup: group,
                state: state,
                recentSetCount: rawSets,
                daysSinceLastTrained: daysSinceLast,
                detail: detail
            )
        }
    }

    private func liftProgressInsights(
        workouts: [WorkoutSession],
        fatigueRisk: CoachFatigueRisk
    ) -> [LiftProgressInsight] {
        let logsByExercise = Dictionary(grouping: workouts.flatMap { session in
            session.exerciseLogs.map { log in
                (date: session.date, log: log)
            }
        }, by: { $0.log.exerciseId })

        let insights = logsByExercise.compactMap { exerciseId, entries -> LiftProgressInsight? in
            let history = entries
                .sorted { $0.date > $1.date }
                .compactMap { entry -> (date: Date, name: String, score: Double, volume: Double)? in
                    let sets = completedWorkingSets(from: entry.log)
                    guard let best = sets.max(by: { estimatedOneRepMax($0) < estimatedOneRepMax($1) }) else { return nil }
                    let volume = sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
                    return (entry.date, entry.log.exerciseNameSnapshot, estimatedOneRepMax(best), volume)
                }
                .prefix(4)

            guard history.count >= 3 else { return nil }

            let recent = Array(history.prefix(3))
            let scores = recent.map(\.score)
            let volumes = recent.map(\.volume)
            let newest = scores[0]
            let oldest = scores[2]
            let range = (scores.max() ?? newest) - (scores.min() ?? newest)
            let average = max(1, scores.reduce(0, +) / Double(scores.count))
            let volumeRange = (volumes.max() ?? 0) - (volumes.min() ?? 0)
            let exerciseName = recent[0].name
            let fatigueLanguage = fatigueRisk.level == .high || fatigueRisk.level == .deloadWatch
                ? " while fatigue is elevated"
                : ""

            if newest > oldest * 1.025 {
                return LiftProgressInsight(
                    id: "\(exerciseId.uuidString)-improving",
                    exerciseName: exerciseName,
                    state: .improving,
                    summary: "\(exerciseName) is trending up across recent sessions.",
                    recommendation: "Continue the current progression and keep reps clean.",
                    confidence: .medium
                )
            }

            if range / average <= 0.025 && volumeRange <= max(100, volumes[0] * 0.05) {
                return LiftProgressInsight(
                    id: "\(exerciseId.uuidString)-steady",
                    exerciseName: exerciseName,
                    state: .steady,
                    summary: "\(exerciseName) has been steady across recent sessions\(fatigueLanguage).",
                    recommendation: fatigueRisk.level == .high || fatigueRisk.level == .deloadWatch
                        ? "Maintain load and improve rep quality before pushing progression."
                        : "If this continues, maintain load and look for one cleaner rep.",
                    confidence: .medium
                )
            }

            if newest < oldest * 0.975 {
                return LiftProgressInsight(
                    id: "\(exerciseId.uuidString)-declining",
                    exerciseName: exerciseName,
                    state: .declining,
                    summary: "\(exerciseName) is down slightly across recent logged sessions\(fatigueLanguage).",
                    recommendation: "Repeat the load and keep the next exposure controlled.",
                    confidence: .medium
                )
            }

            return nil
        }

        let cautionFirst = insights.sorted { lhs, rhs in
            progressRank(lhs.state) > progressRank(rhs.state)
        }

        return Array(cautionFirst.prefix(4))
    }

    private func weeklySummary(
        date: Date,
        readiness: ReadinessScore,
        trends: CoachTrendSummary,
        fatigueRisk: CoachFatigueRisk,
        completedWorkouts: [WorkoutSession],
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        readinessSeries: [(date: Date, value: Double)]
    ) -> WeeklyCoachSummary {
        let currentDates = dateRange(endingOn: date, days: 7)
        let readinessValues = values(
            readinessSeries,
            in: currentDates
        )
        let averageReadiness = readinessValues.isEmpty ? nil : Int((readinessValues.reduce(0, +) / Double(readinessValues.count)).rounded())
        let topPositive = readiness.factors
            .filter { $0.impact == .positive }
            .sorted { $0.contribution > $1.contribution }
            .first?.title ?? "Baseline logging"
        let topLimiting = readiness.factors
            .filter { $0.impact == .negative }
            .sorted { $0.contribution < $1.contribution }
            .first?.title ?? "No major limiter"
        let focus: String

        if fatigueRisk.level == .high || fatigueRisk.level == .deloadWatch {
            focus = fatigueRisk.recommendedAction
        } else if trends.sleepDuration.direction == .declining {
            focus = "Stabilize sleep duration before adding training volume."
        } else if trends.hydrationConsistency.direction == .declining {
            focus = "Bring hydration back toward target on training days."
        } else {
            focus = "Keep training consistent and progress one key lift when readiness supports it."
        }

        return WeeklyCoachSummary(
            averageReadiness: averageReadiness,
            trainingSessionsCompleted: workouts(in: currentDates, from: completedWorkouts).count,
            recoveryTrend: trends.readiness.direction,
            topPositiveFactor: topPositive,
            topLimitingFactor: topLimiting,
            recommendedFocus: focus
        )
    }

    private func weeklyInsights(
        date: Date,
        readiness: ReadinessScore,
        trends: CoachTrendSummary,
        fatigueRisk: CoachFatigueRisk,
        muscleFatigue: [MuscleGroupFatigue],
        liftInsights: [LiftProgressInsight],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        hydrationEntries: [HydrationEntry],
        activeSplits: [TrainingSplit],
        hydrationTargetML: Int
    ) -> [CoachIntelligenceInsight] {
        let currentDates = dateRange(endingOn: date, days: 7)
        let previousDates = previousDateRange(endingOn: date, days: 7)
        let currentWorkouts = workouts(in: currentDates, from: completedWorkouts)
        let previousWorkouts = workouts(in: previousDates, from: completedWorkouts)
        let currentHardSessions = currentWorkouts.filter(isHardSession).count
        let currentSets = workingSetCount(in: currentWorkouts)
        let previousSets = workingSetCount(in: previousWorkouts)
        var insights: [CoachIntelligenceInsight] = []

        if trends.readiness.direction == .declining {
            insights.append(insight(
                "readiness-declining",
                title: "Readiness is trending down",
                summary: "Your recent readiness average is lower than the previous week.",
                category: .readiness,
                severity: .caution,
                confidence: trends.readiness.confidence,
                factors: [trends.readiness.summary],
                action: "Keep the next session controlled and avoid adding extra volume."
            ))
        } else if trends.readiness.direction == .improving {
            insights.append(insight(
                "readiness-improving",
                title: "Recovery trend is improving",
                summary: "Readiness is moving in a better direction compared with the previous week.",
                category: .recovery,
                severity: .positive,
                confidence: trends.readiness.confidence,
                factors: [trends.readiness.summary],
                action: "Progress one key lift when warm-ups feel normal."
            ))
        }

        if trends.sleepDuration.direction == .declining {
            insights.append(insight(
                "sleep-duration-declining",
                title: "Sleep duration has dipped",
                summary: "Recent sleep duration is below the previous week.",
                category: .sleep,
                severity: .caution,
                confidence: trends.sleepDuration.confidence,
                factors: [trends.sleepDuration.summary],
                action: "Keep intensity controlled until sleep returns toward baseline."
            ))
        } else if trends.sleepDuration.direction == .improving {
            insights.append(insight(
                "sleep-duration-improving",
                title: "Sleep is supporting recovery",
                summary: "Sleep duration is improving compared with the previous week.",
                category: .sleep,
                severity: .positive,
                confidence: trends.sleepDuration.confidence,
                factors: [trends.sleepDuration.summary],
                action: "Use the extra recovery to train as planned."
            ))
        }

        let hydrationHits = hydrationHitDays(in: currentDates, entries: hydrationEntries, targetML: hydrationTargetML)
        if hydrationHits >= 5 {
            insights.append(insight(
                "hydration-supporting",
                title: "Hydration consistency is strong",
                summary: "Hydration is on track on most recent days.",
                category: .hydration,
                severity: .positive,
                confidence: .medium,
                factors: ["\(hydrationHits) of 7 days reached at least 70% of target."],
                action: "Keep this steady around harder sessions."
            ))
        } else if hydrationHits <= 2, !hydrationEntries.isEmpty {
            insights.append(insight(
                "hydration-limited",
                title: "Hydration consistency is light",
                summary: "Water logs are below target on most recent days.",
                category: .hydration,
                severity: .caution,
                confidence: .medium,
                factors: ["\(hydrationHits) of 7 days reached at least 70% of target."],
                action: "Bring hydration closer to target before high-volume sessions."
            ))
        }

        let nutritionDays = nutritionLoggedDays(in: currentDates, foodLogs: foodLogs)
        if nutritionDays <= 2, !foodLogs.isEmpty {
            insights.append(insight(
                "nutrition-consistency",
                title: "Nutrition consistency is limited",
                summary: "Few recent days have food logs, so recovery confidence is lower.",
                category: .nutrition,
                severity: .neutral,
                confidence: .low,
                factors: ["\(nutritionDays) of 7 days include food logs."],
                action: "Log protein and calories on training days to sharpen recovery guidance."
            ))
        }

        if currentWorkouts.count >= previousWorkouts.count + 2, currentWorkouts.count >= 4 {
            insights.append(insight(
                "frequency-increase",
                title: "Training frequency increased",
                summary: "You trained more often this week than last week.",
                category: .training,
                severity: .caution,
                confidence: .medium,
                factors: ["\(currentWorkouts.count) sessions this week vs \(previousWorkouts.count) last week."],
                action: "Maintain, but avoid extra accessories if readiness drops."
            ))
        }

        if previousSets >= 10, Double(currentSets) > Double(previousSets) * 1.35 {
            insights.append(insight(
                "set-volume-jump",
                title: "Set volume jumped",
                summary: "Working set volume is meaningfully above the previous week.",
                category: .fatigue,
                severity: .caution,
                confidence: .medium,
                factors: ["\(currentSets) sets this week vs \(previousSets) last week."],
                action: "Keep compounds technique-focused and avoid unnecessary extra sets."
            ))
        }

        if currentHardSessions >= 2 {
            insights.append(insight(
                "hard-sessions",
                title: "Hard sessions are accumulating",
                summary: "Multiple recent sessions look high effort or high volume.",
                category: .fatigue,
                severity: currentHardSessions >= 3 ? .important : .caution,
                confidence: .medium,
                factors: ["\(currentHardSessions) hard sessions in the last 7 days."],
                action: "Use longer warm-ups and keep the next session controlled."
            ))
        }

        if fatigueRisk.level == .high || fatigueRisk.level == .deloadWatch {
            insights.append(insight(
                "fatigue-risk",
                title: fatigueRisk.title,
                summary: fatigueRisk.summary,
                category: .fatigue,
                severity: fatigueRisk.level == .deloadWatch ? .important : .caution,
                confidence: fatigueRisk.confidence,
                factors: Array(fatigueRisk.factors.prefix(3)),
                action: fatigueRisk.recommendedAction
            ))
        }

        if let fatiguedGroup = muscleFatigue.first(where: { $0.state == .fatigued }) {
            insights.append(insight(
                "muscle-\(fatiguedGroup.muscleGroup.rawValue)",
                title: "\(fatiguedGroup.muscleGroup.displayName) is heavily loaded",
                summary: "Recent logs show elevated work for this area.",
                category: .muscleGroup,
                severity: .caution,
                confidence: .medium,
                factors: [fatiguedGroup.detail],
                action: "Prioritize warm-ups and avoid chasing failure for this group.",
                relatedArea: fatiguedGroup.muscleGroup.displayName
            ))
        }

        for lift in liftInsights where lift.state != .improving {
            insights.append(insight(
                "lift-\(lift.id)",
                title: "\(lift.exerciseName) is \(lift.state.displayName.lowercased())",
                summary: lift.summary,
                category: .plateau,
                severity: lift.state == .declining ? .caution : .neutral,
                confidence: lift.confidence,
                factors: ["At least 3 logged exposures are available."],
                action: lift.recommendation,
                relatedArea: lift.exerciseName
            ))
        }

        if insights.isEmpty {
            let activeSplitText = activeSplits.isEmpty ? "Add active splits and keep logging sessions." : "Keep logging sessions and recovery basics."
            insights.append(insight(
                "baseline-building",
                title: "Coach baseline is building",
                summary: "There is not enough recent pattern change for a strong insight yet.",
                category: .habit,
                severity: .neutral,
                confidence: .low,
                factors: ["Peakline needs repeated workouts, sleep, hydration, and check-ins."],
                action: activeSplitText
            ))
        }

        return Array(insights.prefix(8))
    }

    private func adaptiveGuidance(
        readiness: ReadinessScore,
        fatigueRisk: CoachFatigueRisk,
        muscleFatigue: [MuscleGroupFatigue],
        exercises: [Exercise],
        plannedExerciseIDs: [UUID]
    ) -> AdaptiveWorkoutGuidance {
        let plannedGroups = plannedExerciseIDs.flatMap { exerciseId in
            exercises.first { $0.id == exerciseId }.map { exercise in
                [exercise.primaryMuscleGroup] + exercise.secondaryMuscleGroups
            } ?? []
        }
        let plannedFatiguedGroups = muscleFatigue.filter { fatigue in
            plannedGroups.contains(fatigue.muscleGroup) && fatigue.state == .fatigued
        }
        let plannedLoadedGroups = muscleFatigue.filter { fatigue in
            plannedGroups.contains(fatigue.muscleGroup) && (fatigue.state == .loaded || fatigue.state == .fatigued)
        }

        let mode: AdaptiveWorkoutMode
        if readiness.category == .recovery || readiness.category == .low || fatigueRisk.level == .deloadWatch {
            mode = .recoveryFocus
        } else if fatigueRisk.level == .high || !plannedFatiguedGroups.isEmpty || readiness.category == .cautious {
            mode = .reduce
        } else if readiness.category == .peak, fatigueRisk.level == .low, plannedLoadedGroups.isEmpty {
            mode = .push
        } else {
            mode = .maintain
        }

        let fatigueContext: String
        if let first = plannedFatiguedGroups.first {
            fatigueContext = "\(first.muscleGroup.displayName) fatigue is elevated from recent sessions."
        } else {
            fatigueContext = fatigueRisk.summary
        }

        switch mode {
        case .push:
            return AdaptiveWorkoutGuidance(
                mode: mode,
                readinessCategory: readiness.category,
                fatigueContext: fatigueContext,
                title: "Push: progression is reasonable",
                summary: "Readiness is high and fatigue is low. Progress one key lift if warm-ups feel normal.",
                primarySuggestion: "Progress one primary lift",
                adjustmentChips: ["Keep plan", "Add optional set", "Progress one lift"]
            )
        case .maintain:
            return AdaptiveWorkoutGuidance(
                mode: mode,
                readinessCategory: readiness.category,
                fatigueContext: fatigueContext,
                title: "Maintain: follow the plan",
                summary: "Readiness is workable. Keep the planned session and avoid unnecessary extra volume.",
                primarySuggestion: "Keep plan",
                adjustmentChips: ["Keep plan", "Technique focus", "Avoid extra sets"]
            )
        case .reduce:
            return AdaptiveWorkoutGuidance(
                mode: mode,
                readinessCategory: readiness.category,
                fatigueContext: fatigueContext,
                title: "Reduce: keep volume controlled",
                summary: "Recovery or local fatigue suggests a more controlled session.",
                primarySuggestion: "Reduce accessories by 10-20%",
                adjustmentChips: ["Reduce accessories", "Technique focus", "Avoid PR attempts"]
            )
        case .recoveryFocus:
            return AdaptiveWorkoutGuidance(
                mode: mode,
                readinessCategory: readiness.category,
                fatigueContext: fatigueContext,
                title: "Recovery Focus: keep it easy",
                summary: "Readiness is low enough that a lighter session, mobility, or rest may be useful.",
                primarySuggestion: "Consider a recovery session",
                adjustmentChips: ["Recovery session", "Mobility", "Rest option"]
            )
        }
    }

    private func coachDiagnostics(
        readiness: ReadinessScore,
        fatigueRisk: CoachFatigueRisk,
        adaptiveGuidance: AdaptiveWorkoutGuidance,
        plannedExerciseIDs: [UUID],
        exerciseMetadata: [CoachExerciseMetadata],
        coachActionHistory: [CoachActionHistoryEntry],
        recommendationFeedback: [CoachRecommendationFeedback],
        savedDeloadBlocks: [SavedCoachDeloadBlock],
        coachPreferences: CoachPreferencesSnapshot,
        splitMetadata: [CoachSplitMetadata]
    ) -> CoachDiagnostics {
        let readinessInputs = readiness.factors.map { factor in
            let scoreText = factor.score.map { "\($0)" } ?? "n/a"
            return "\(factor.kind.displayName): \(scoreText), \(factor.impact.rawValue)"
        }
        let missingReasons = readiness.factors
            .filter { !$0.isDataAvailable }
            .map { "\($0.kind.displayName): \(missingDataReason(for: $0.kind))" }
        let deloadReason = fatigueRisk.level == .high || fatigueRisk.level == .deloadWatch
            ? fatigueRisk.factors.prefix(3).joined(separator: " ")
            : nil
        let plannedText = plannedExerciseIDs.isEmpty
            ? "No planned workout metadata was available."
            : "\(plannedExerciseIDs.count) planned exercise IDs were available."
        let context = CoachCalibrationContext(
            actionHistory: coachActionHistory,
            feedback: recommendationFeedback,
            deloadBlocks: savedDeloadBlocks,
            exerciseMetadata: exerciseMetadata,
            preferences: coachPreferences,
            splitMetadata: nil
        )
        let feedbackDiagnostics = CoachRecommendationFeedbackService().calibrationDiagnostics(from: context)
        let metadataInputs = exerciseMetadata.isEmpty
            ? ["No user-edited exercise coach metadata."]
            : exerciseMetadata.prefix(6).map { metadata in
                "\(metadata.role.displayName): \(metadata.primaryMuscleGroup.displayName), \(metadata.priority.displayName.lowercased()) priority."
            }
        let activeDeloads = savedDeloadBlocks.filter { $0.state == .active }
        let historyInfluence = coachActionHistory.isEmpty
            ? "No coach action history yet."
            : "\(coachActionHistory.prefix(20).count) recent coach actions available for calibration."
        let confidenceReasons = recommendationFeedback
            .filter { feedback in
                feedback.tags.contains(.feltInaccurate)
                    || feedback.tags.contains(.notHelpful)
                    || feedback.tags.contains(.tooAggressive)
                    || feedback.tags.contains(.preferredRecovery)
            }
            .prefix(3)
            .map { feedback in
                let action = feedback.action?.displayName ?? "Coach guidance"
                return "\(action): \(feedback.tags.map(\.displayName).joined(separator: ", "))"
            }
        let preferenceInfluence = [
            "Aggressiveness: \(coachPreferences.aggressiveness.displayName)",
            "Deload wording: \(coachPreferences.deloadWording.displayName)",
            "Detail: \(coachPreferences.detailLevel.displayName)",
            "Training priority: \(coachPreferences.trainingPriority.displayName)",
            "Reduction: \(coachPreferences.reductionPreference.displayName)",
            "Frequency: \(coachPreferences.recommendationFrequency.displayName)"
        ]
        let splitInfluence = splitMetadata.isEmpty
            ? ["No split-level coach metadata saved."]
            : splitMetadata.prefix(5).map { metadata in
                "\(metadata.splitName): \(metadata.priority.displayName) priority, \(metadata.primaryGoal.displayName), \(metadata.expectedFatigue.displayName.lowercased()) fatigue."
            }
        let bulkInfluence = exerciseMetadata.filter { $0.userNote?.localizedCaseInsensitiveContains("bulk") == true }
        let urgencyReasons = [
            coachPreferences.aggressiveness == .conservative ? "Conservative preference reduces urgency." : nil,
            coachPreferences.aggressiveness == .assertive ? "Assertive preference keeps recommendations more direct." : nil,
            activeDeloads.isEmpty ? nil : "Active deload block softens urgency.",
            coachActionHistory.contains { $0.action == .deloadStyleSession && ($0.outcome == .cancelled || $0.outcome == .bypassed) } ? "Past deload cancellations lower urgency unless fatigue is high." : nil
        ].compactMap { $0 }

        return CoachDiagnostics(
            readinessInputs: readinessInputs,
            fatigueInputs: fatigueRisk.factors,
            confidence: minConfidence(readiness.confidence, fatigueRisk.confidence),
            missingDataReasons: missingReasons,
            adaptiveActionReason: "\(adaptiveGuidance.mode.displayName): \(adaptiveGuidance.summary) \(plannedText)",
            deloadTriggerReason: deloadReason,
            exerciseMetadataInputs: metadataInputs,
            feedbackInfluence: feedbackDiagnostics,
            confidenceAdjustmentReasons: confidenceReasons.isEmpty ? ["No feedback-driven confidence adjustment."] : Array(confidenceReasons),
            deloadBlockInfluence: activeDeloads.isEmpty ? "No active saved deload block." : "\(activeDeloads.count) active deload block(s) may soften training guidance.",
            actionHistoryInfluence: historyInfluence,
            coachPreferenceInfluence: preferenceInfluence,
            splitMetadataInfluence: splitInfluence,
            bulkMetadataInfluence: bulkInfluence.isEmpty ? ["No bulk metadata changes detected."] : ["\(bulkInfluence.count) exercise metadata entries include bulk-edit context."],
            urgencyAdjustmentReasons: urgencyReasons.isEmpty ? ["No preference or history urgency adjustment."] : urgencyReasons
        )
    }

    private func missingDataReason(for kind: ReadinessFactorKind) -> String {
        switch kind {
        case .sleep:
            return "No recent completed sleep log."
        case .training:
            return "No recent completed workout history."
        case .hydration:
            return "No water logged today."
        case .checkIn:
            return "Daily check-in is not completed."
        case .nutrition:
            return "No recent food logs."
        }
    }

    private func minConfidence(_ lhs: ReadinessConfidence, _ rhs: ReadinessConfidence) -> ReadinessConfidence {
        let rank: [ReadinessConfidence: Int] = [.low: 0, .medium: 1, .high: 2]
        return (rank[lhs, default: 0] <= rank[rhs, default: 0]) ? lhs : rhs
    }

    private func sleepSignal(
        date: Date,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        sleepSummaries: [SleepSummary]?
    ) -> ReadinessSignal {
        let recentSleepSessions = sleepSessions.filter { session in
            guard session.status == .completed else { return false }
            return daysBetween(session.nightDate, and: date) <= 14
        }
        let recentNaps = napSessions.filter { daysBetween($0.startDate, and: date) <= 7 }
        let recentWorkouts = workouts.filter { daysBetween($0.date, and: date) <= 14 }
        let latest = sleepSummaries?.first { $0.primarySession != nil } ?? sleepScoring.latestSummary(
            from: Array(recentSleepSessions.prefix(45)),
            naps: recentNaps,
            workouts: recentWorkouts,
            settings: settings
        )
        let hasRecentSleep = latest.primarySession != nil && daysBetween(latest.date, and: date) <= 2
        let todayNapMinutes = recentNaps
            .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .reduce(0) { $0 + $1.durationMinutes }

        guard hasRecentSleep else {
            let napSupport = min(todayNapMinutes, 45)
            let score = todayNapMinutes > 0 ? 68 + min(7, napSupport / 10) : 70
            let detail = todayNapMinutes > 0
                ? "Nap logged today, but overnight sleep is missing."
                : "No recent sleep log. Readiness uses a neutral baseline."

            return signal(
                kind: .sleep,
                title: "Sleep baseline building",
                detail: detail,
                score: score,
                weight: 0.30,
                isDataAvailable: todayNapMinutes > 0
            )
        }

        let baseScore = latest.sleepScore ?? sleepScoring.durationScore(
            minutes: latest.totalSleepMinutes,
            targetMinutes: settings.targetSleepMinutes
        )
        let napBonus = min(6, latest.napCreditMinutes / 10)
        let score = min(100, baseScore + napBonus)
        let duration = SleepScoringService.durationText(minutes: latest.totalSleepMinutes)
        let quality = latest.qualityRating.map { "Quality \($0)/5" } ?? "No quality rating"
        let napText = latest.napCreditMinutes > 0 ? " Nap recovery adds support." : ""
        let title: String

        switch score {
        case 85...100:
            title = "Sleep supports training"
        case 70..<85:
            title = "Sleep is steady"
        case 55..<70:
            title = "Sleep is slightly below target"
        default:
            title = "Sleep may limit recovery"
        }

        return signal(
            kind: .sleep,
            title: title,
            detail: "\(duration) sleep. \(quality).\(napText)",
            score: score,
            weight: 0.30,
            isDataAvailable: true
        )
    }

    private func trainingSignal(date: Date, workouts: [WorkoutSession]) -> ReadinessSignal {
        let recent = workouts
            .filter { daysBetween($0.date, and: date) <= 7 }
            .sorted { $0.date > $1.date }
        let previousWeek = workouts.filter {
            let days = daysBetween($0.date, and: date)
            return days > 7 && days <= 14
        }

        guard !recent.isEmpty else {
            return signal(
                kind: .training,
                title: "Training baseline building",
                detail: "No recent workouts logged. Fatigue is treated as neutral.",
                score: 74,
                weight: 0.25,
                isDataAvailable: false
            )
        }

        let recentSetCount = workingSetCount(in: recent)
        let previousSetCount = workingSetCount(in: previousWeek)
        let consecutiveDays = consecutiveTrainingDays(endingOn: date, workouts: workouts)
        let hardSessions = recent.filter { isHardSession($0) }.count
        let hardSessions48h = recent.filter {
            abs($0.date.timeIntervalSince(date)) <= 48 * 60 * 60 && isHardSession($0)
        }.count

        var score = 88
        score -= max(0, recent.count - 3) * 6
        if consecutiveDays >= 4 {
            score -= 20
        } else if consecutiveDays == 3 {
            score -= 12
        } else if consecutiveDays == 2 {
            score -= 6
        }
        score -= min(18, hardSessions48h * 9)
        if recentSetCount >= 60 {
            score -= 15
        } else if recentSetCount >= 42 {
            score -= 8
        }
        if previousSetCount >= 10 && Double(recentSetCount) > Double(previousSetCount) * 1.35 {
            score -= 8
        }
        score = min(100, max(30, score))

        let title: String
        if score >= 82 {
            title = "Training fatigue is low"
        } else if score >= 68 {
            title = "Training load is manageable"
        } else if score >= 52 {
            title = "Training fatigue is moderate"
        } else {
            title = "Training fatigue is elevated"
        }

        let detail = "\(recent.count) workouts and \(recentSetCount) working sets in 7 days. \(hardSessions) hard sessions."

        return signal(
            kind: .training,
            title: title,
            detail: detail,
            score: score,
            weight: 0.25,
            isDataAvailable: true
        )
    }

    private func hydrationSignal(date: Date, entries: [HydrationEntry], targetML: Int) -> ReadinessSignal {
        let summary = hydrationService.summary(for: date, entries: entries, targetML: targetML, calendar: calendar)
        let expected = expectedHydrationProgress(on: date)
        let progress = summary.progress
        let score: Int
        let title: String

        if summary.totalML == 0 {
            score = expected < 0.70 ? 70 : 64
            title = expected < 0.38 ? "Hydration not logged yet" : "Hydration data is missing today"
        } else if progress >= 0.95 {
            score = 94
            title = "Hydration is on track"
        } else if progress >= expected {
            score = 84
            title = "Hydration is pacing well"
        } else if progress >= expected * 0.70 {
            score = 70
            title = "Hydration is slightly behind"
        } else {
            score = 55
            title = "Hydration is behind target"
        }

        let detail = summary.totalML == 0
            ? "No water logged today."
            : "\(HydrationService.formatAmount(summary.totalML)) of \(HydrationService.formatAmount(summary.targetML)) logged today."

        return signal(
            kind: .hydration,
            title: title,
            detail: detail,
            score: score,
            weight: 0.20,
            isDataAvailable: summary.totalML > 0
        )
    }

    private func subjectiveSignal(from checkIn: DailyCoachCheckIn?) -> ReadinessSignal {
        guard let checkIn else {
            return signal(
                kind: .checkIn,
                title: "Check-in not completed",
                detail: "Energy, soreness, stress, and motivation are unknown.",
                score: 70,
                weight: 0.15,
                isDataAvailable: false
            )
        }

        let readinessTotal = checkIn.energy
            + checkIn.motivation
            + (6 - checkIn.soreness)
            + (6 - checkIn.stress)
        let score = min(100, max(20, Int((Double(readinessTotal) / 20.0 * 100).rounded())))
        let title: String

        if score >= 82 {
            title = "Check-in supports training"
        } else if score >= 68 {
            title = "Check-in is balanced"
        } else if score >= 52 {
            title = "Check-in suggests caution"
        } else {
            title = "Check-in points to recovery"
        }

        return signal(
            kind: .checkIn,
            title: title,
            detail: "Energy \(checkIn.energy)/5, soreness \(checkIn.soreness)/5, stress \(checkIn.stress)/5, motivation \(checkIn.motivation)/5.",
            score: score,
            weight: 0.15,
            isDataAvailable: true
        )
    }

    private func nutritionSignal(
        date: Date,
        foodLogs: [FoodLogEntry],
        workouts: [WorkoutSession],
        goal: NutritionGoal
    ) -> ReadinessSignal {
        let summaries = nutritionSummaryService.dailySummaries(
            endingOn: date,
            days: 7,
            foodLogs: foodLogs,
            workouts: workouts,
            calendar: calendar
        )
        let weekly = trendService.weeklySummary(dailySummaries: summaries, goal: goal, calendar: calendar)
        let todaySummary = summaries.last

        guard weekly.loggedDays > 0 else {
            return signal(
                kind: .nutrition,
                title: "Nutrition baseline building",
                detail: "No recent food logs. Nutrition is treated as unknown.",
                score: 70,
                weight: 0.10,
                isDataAvailable: false
            )
        }

        var score = 68 + min(12, weekly.loggedDays * 2)
        var detailParts = ["\(weekly.loggedDays) of 7 days logged"]

        if let proteinTarget = goal.dailyProteinTarget, proteinTarget > 0 {
            let hitDays = summaries.filter { $0.protein >= proteinTarget * 0.85 }.count
            score += min(10, hitDays * 2)
            detailParts.append("\(hitDays) protein-supportive days")
        } else if (todaySummary?.protein ?? 0) > 0 {
            score += 4
            detailParts.append("protein logged today")
        }

        if goal.hasTargets {
            score += min(8, weekly.calorieTargetHitDays * 2)
            if weekly.loggedDays >= 3, weekly.averageCalories > 0 {
                let target = goal.calorieTarget(isTrainingDay: todaySummary?.isTrainingDay ?? false) ?? goal.dailyCaloriesTarget
                if let target, target > 0, weekly.averageCalories < target * 0.75 {
                    score -= 12
                    detailParts.append("recent calories look low")
                }
            }
        }

        score = min(96, max(45, score))
        let title: String

        if score >= 82 {
            title = "Nutrition supports recovery"
        } else if score >= 68 {
            title = "Nutrition is steady"
        } else {
            title = "Nutrition may need attention"
        }

        return signal(
            kind: .nutrition,
            title: title,
            detail: detailParts.joined(separator: ", ") + ".",
            score: score,
            weight: 0.10,
            isDataAvailable: true
        )
    }

    private func signal(
        kind: ReadinessFactorKind,
        title: String,
        detail: String,
        score: Int,
        weight: Double,
        isDataAvailable: Bool
    ) -> ReadinessSignal {
        let contribution = (Double(score) - 70.0) * weight
        let impact: ReadinessImpact

        if contribution >= 3 {
            impact = .positive
        } else if contribution <= -3 {
            impact = .negative
        } else {
            impact = .neutral
        }

        return ReadinessSignal(
            score: min(100, max(0, score)),
            weight: weight,
            factor: ReadinessFactor(
                kind: kind,
                title: title,
                detail: detail,
                impact: impact,
                contribution: contribution,
                score: min(100, max(0, score)),
                isDataAvailable: isDataAvailable
            )
        )
    }

    private func confidence(for signals: [ReadinessSignal], checkIn: DailyCoachCheckIn?) -> ReadinessConfidence {
        let availableCount = signals.filter(\.factor.isDataAvailable).count

        if availableCount >= 4, checkIn != nil {
            return .high
        }

        if availableCount >= 2 {
            return .medium
        }

        return .low
    }

    private func recommendation(
        value: Int,
        category: ReadinessCategory,
        confidence: ReadinessConfidence,
        factors: [ReadinessFactor]
    ) -> ReadinessCoachRecommendation {
        let negativeFactors = factors.filter { $0.impact == .negative }
        let positiveFactors = factors.filter { $0.impact == .positive }
        let orderedReasons = factors
            .sorted { abs($0.contribution) > abs($1.contribution) }
            .prefix(3)
            .map { reasonText(for: $0) }
        let reasons = orderedReasons.isEmpty ? ["Peakline is building your baseline from local logs."] : Array(orderedReasons)
        let prefix = confidence == .low ? "Based on limited data, " : ""

        switch category {
        case .peak:
            return ReadinessCoachRecommendation(
                title: "Good day to push",
                summary: "\(prefix)recovery signals are strong. Train as planned and consider progressing one key lift.",
                reasonBullets: reasons,
                suggestedActions: ["Progress one primary lift", "Keep accessories clean and controlled"]
            )
        case .ready:
            return ReadinessCoachRecommendation(
                title: "Train as planned",
                summary: "\(prefix)your recovery looks balanced. Keep the session focused and avoid unnecessary extra volume.",
                reasonBullets: reasons,
                suggestedActions: ["Follow the planned session", "Add reps only where execution feels solid"]
            )
        case .cautious:
            return ReadinessCoachRecommendation(
                title: "Keep volume controlled",
                summary: "\(prefix)readiness is slightly reduced. Train, but keep intensity and extra sets in check.",
                reasonBullets: reasons,
                suggestedActions: ["Avoid adding extra top sets", "Leave 1-2 reps in reserve on compounds"]
            )
        case .low:
            let action = negativeFactors.contains { $0.kind == .training }
                ? "Reduce accessory volume by 1 set"
                : "Reduce intensity slightly"
            return ReadinessCoachRecommendation(
                title: "Keep it controlled",
                summary: "\(prefix)recovery is below baseline. Reduce intensity slightly and prioritize clean reps.",
                reasonBullets: reasons,
                suggestedActions: [action, "Extend warm-ups before heavy work"]
            )
        case .recovery:
            let positiveText = positiveFactors.isEmpty ? "Use today to rebuild recovery signals." : "Keep the helpful habits in place."
            return ReadinessCoachRecommendation(
                title: "Recovery-first day",
                summary: "\(prefix)several readiness signals are low. Consider rest, mobility, or an easy session. \(positiveText)",
                reasonBullets: reasons,
                suggestedActions: ["Consider rest or active recovery", "Avoid chasing failure today"]
            )
        }
    }

    private func reasonText(for factor: ReadinessFactor) -> String {
        switch factor.impact {
        case .positive:
            return factor.title
        case .neutral:
            return factor.isDataAvailable ? factor.title : "\(factor.kind.displayName) data is limited"
        case .negative:
            return factor.title
        }
    }

    private func workoutAdjustment(for category: ReadinessCategory, factors: [ReadinessFactor]) -> String {
        let trainingFatigue = factors.first { $0.kind == .training && $0.impact == .negative } != nil
        let poorSleep = factors.first { $0.kind == .sleep && $0.impact == .negative } != nil
        let lowHydration = factors.first { $0.kind == .hydration && $0.impact == .negative } != nil

        switch category {
        case .peak:
            return "Good day to progress one primary lift if warm-ups feel normal."
        case .ready:
            return "Train as planned. Add volume only if performance feels stable."
        case .cautious:
            if trainingFatigue {
                return "Keep compounds controlled and avoid adding extra top sets."
            }
            return "Use planned loads, but keep accessories efficient."
        case .low:
            if poorSleep || lowHydration {
                return "Reduce accessories by 1 set and keep the main lifts submaximal."
            }
            return "Reduce volume slightly and stop sets before form breaks down."
        case .recovery:
            return "Consider rest, mobility, or a short recovery session. Your plan stays unchanged unless you choose edits."
        }
    }

    private func recoveryNote(for confidence: ReadinessConfidence, factors: [ReadinessFactor]) -> String {
        if confidence == .low {
            return "Peakline is building your baseline. A sleep log, hydration entry, and quick check-in will make the next brief more specific."
        }

        if let negative = factors.first(where: { $0.impact == .negative }) {
            return "\(negative.kind.displayName) is the main signal to manage today."
        }

        return "Recovery inputs are balanced. Keep logging the basics so the coach can track trends."
    }

    private func expectedHydrationProgress(on date: Date) -> Double {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case ..<10:
            return 0.25
        case 10..<13:
            return 0.45
        case 13..<17:
            return 0.70
        case 17..<21:
            return 0.90
        default:
            return 1.0
        }
    }

    private func workingSetCount(in sessions: [WorkoutSession]) -> Int {
        sessions.reduce(0) { total, session in
            total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
        }
    }

    private func isHardSession(_ session: WorkoutSession) -> Bool {
        let workingSets = session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }
        let hardRPECount = workingSets.filter { ($0.rpe ?? 0) >= 8.5 }.count

        if let perceivedDifficulty = session.perceivedDifficulty, perceivedDifficulty >= 4 {
            return true
        }

        if workingSets.count >= 16 || hardRPECount >= 3 {
            return true
        }

        return (session.durationMinutes ?? 0) >= 90
    }

    private func consecutiveTrainingDays(endingOn date: Date, workouts: [WorkoutSession]) -> Int {
        let workoutDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        var count = 0
        var cursor = calendar.startOfDay(for: date)

        while workoutDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        if count == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)), workoutDays.contains(yesterday) {
            cursor = yesterday
            while workoutDays.contains(cursor) {
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            }
        }

        return count
    }

    private func daysBetween(_ earlier: Date, and later: Date) -> Int {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return abs(calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private var majorMuscleGroups: [MuscleGroup] {
        [.chest, .back, .shoulders, .biceps, .triceps, .quads, .hamstrings, .glutes, .calves, .core]
    }

    private func dateRange(endingOn date: Date, days: Int) -> [Date] {
        let end = calendar.startOfDay(for: date)
        return (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end)
        }
    }

    private func previousDateRange(endingOn date: Date, days: Int) -> [Date] {
        let end = calendar.startOfDay(for: date)
        return (days..<(days * 2)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end)
        }
    }

    private func workouts(in dates: [Date], from sessions: [WorkoutSession]) -> [WorkoutSession] {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        return sessions.filter { session in
            session.completed && days.contains(calendar.startOfDay(for: session.date))
        }
    }

    private func values(_ series: [(date: Date, value: Double)], in dates: [Date]) -> [Double] {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        return series.filter { days.contains(calendar.startOfDay(for: $0.date)) }.map(\.value)
    }

    private func readinessProxySeries(
        endingOn date: Date,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal
    ) -> [(date: Date, value: Double)] {
        let sleepSummaries = sleepScoring.summaries(
            from: sleepSessions,
            naps: napSessions,
            workouts: completedWorkouts,
            settings: sleepSettings,
            days: 14,
            calendar: calendar
        )

        return readinessProxySeries(
            endingOn: date,
            sleepSessions: sleepSessions,
            napSessions: napSessions,
            hydrationEntries: hydrationEntries,
            completedWorkouts: completedWorkouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            sleepSummaries: sleepSummaries
        )
    }

    private func readinessProxySeries(
        endingOn date: Date,
        sleepSessions: [SleepSession],
        napSessions: [NapSession],
        hydrationEntries: [HydrationEntry],
        completedWorkouts: [WorkoutSession],
        foodLogs: [FoodLogEntry],
        checkIns: [DailyCoachCheckIn],
        sleepSettings: SleepSettings,
        hydrationTargetML: Int,
        nutritionGoal: NutritionGoal,
        sleepSummaries: [SleepSummary]
    ) -> [(date: Date, value: Double)] {
        let dates = dateRange(endingOn: date, days: 14)
        let sleepByDate = Dictionary(uniqueKeysWithValues: sleepSummaries.map { (calendar.startOfDay(for: $0.date), $0) })

        return dates.map { day in
            let sleepScore = sleepByDate[day]?.sleepScore ?? 70
            let hydrationScore = hydrationScore(for: day, entries: hydrationEntries, targetML: hydrationTargetML)
            let trainingScore = trainingFatigueScore(on: day, workouts: completedWorkouts)
            let checkInScore = subjectiveScore(todayCheckIn(from: checkIns, date: day))
            let nutritionScore = nutritionScore(for: day, foodLogs: foodLogs, workouts: completedWorkouts, goal: nutritionGoal)
            let value = Double(sleepScore) * 0.30
                + Double(trainingScore) * 0.25
                + Double(hydrationScore) * 0.20
                + Double(checkInScore) * 0.15
                + Double(nutritionScore) * 0.10
            return (date: day, value: value.rounded())
        }
    }

    private func hydrationScore(for date: Date, entries: [HydrationEntry], targetML: Int) -> Int {
        let summary = hydrationService.summary(for: date, entries: entries, targetML: targetML, calendar: calendar)
        if summary.totalML == 0 {
            return 70
        }
        switch summary.progress {
        case 0.95...:
            return 94
        case 0.70..<0.95:
            return 82
        case 0.40..<0.70:
            return 66
        default:
            return 54
        }
    }

    private func trainingFatigueScore(on date: Date, workouts: [WorkoutSession]) -> Int {
        let recent = workouts.filter { session in
            guard session.completed, session.date <= date.endOfDay(using: calendar) else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.date), to: calendar.startOfDay(for: date)).day ?? 0
            return days >= 0 && days <= 7
        }
        guard !recent.isEmpty else { return 74 }

        let sets = workingSetCount(in: recent)
        let hard = recent.filter(isHardSession).count
        var score = 88 - max(0, recent.count - 3) * 6 - min(18, hard * 5)
        if sets >= 60 {
            score -= 15
        } else if sets >= 42 {
            score -= 8
        }
        return min(100, max(30, score))
    }

    private func subjectiveScore(_ checkIn: DailyCoachCheckIn?) -> Int {
        guard let checkIn else { return 70 }
        let total = checkIn.energy + checkIn.motivation + (6 - checkIn.soreness) + (6 - checkIn.stress)
        return min(100, max(20, Int((Double(total) / 20.0 * 100).rounded())))
    }

    private func nutritionScore(for date: Date, foodLogs: [FoodLogEntry], workouts: [WorkoutSession], goal: NutritionGoal) -> Int {
        let summary = nutritionSummaryService.dailySummary(for: date, foodLogs: foodLogs, workouts: workouts, calendar: calendar)
        guard summary.loggedFoodCount > 0 else { return 70 }

        var score = 78
        if let proteinTarget = goal.dailyProteinTarget, proteinTarget > 0, summary.protein >= proteinTarget * 0.85 {
            score += 10
        } else if summary.protein > 0 {
            score += 4
        }

        if let calorieTarget = goal.calorieTarget(isTrainingDay: summary.isTrainingDay), calorieTarget > 0 {
            let adherence = abs(summary.calories - calorieTarget) / calorieTarget
            if adherence <= 0.15 {
                score += 8
            } else if summary.calories < calorieTarget * 0.65 {
                score -= 10
            }
        }

        return min(96, max(45, score))
    }

    private func trend(
        title: String,
        current: [Double],
        previous: [Double],
        threshold: Double,
        higherIsBetter: Bool,
        unit: String
    ) -> CoachTrend {
        guard current.count >= 2, previous.count >= 2 else {
            return CoachTrend(title: title, direction: .insufficientData, summary: "More recent logs are needed.", currentValue: current.average, previousValue: previous.average, confidence: .low)
        }

        let currentAverage = current.average ?? 0
        let previousAverage = previous.average ?? 0
        let delta = currentAverage - previousAverage
        let rawDirection: CoachTrendDirection

        if abs(delta) < threshold {
            rawDirection = .stable
        } else if delta > 0 {
            rawDirection = higherIsBetter ? .improving : .declining
        } else {
            rawDirection = higherIsBetter ? .declining : .improving
        }

        return CoachTrend(
            title: title,
            direction: rawDirection,
            summary: "\(title) is \(rawDirection.displayName.lowercased()) versus the previous week.",
            currentValue: currentAverage,
            previousValue: previousAverage,
            confidence: current.count >= 5 && previous.count >= 5 ? .high : .medium
        )
    }

    private func countTrend(title: String, current: Int, previous: Int, threshold: Int, higherIsBetter: Bool) -> CoachTrend {
        guard current + previous > 0 else {
            return CoachTrend(title: title, direction: .insufficientData, summary: "More training logs are needed.", currentValue: nil, previousValue: nil, confidence: .low)
        }

        let delta = current - previous
        let direction: CoachTrendDirection
        if abs(delta) <= threshold {
            direction = .stable
        } else if delta > 0 {
            direction = higherIsBetter ? .improving : .declining
        } else {
            direction = higherIsBetter ? .declining : .improving
        }

        return CoachTrend(
            title: title,
            direction: direction,
            summary: "\(current) this week vs \(previous) last week.",
            currentValue: Double(current),
            previousValue: Double(previous),
            confidence: current + previous >= 3 ? .medium : .low
        )
    }

    private func consistencyTrend(
        title: String,
        currentDates: [Date],
        previousDates: [Date],
        target: Int,
        currentCount: Int,
        previousCount: Int
    ) -> CoachTrend {
        let direction: CoachTrendDirection
        if currentCount + previousCount == 0 {
            direction = .insufficientData
        } else if currentCount >= previousCount + 2 {
            direction = .improving
        } else if previousCount >= currentCount + 2 {
            direction = .declining
        } else {
            direction = .stable
        }

        return CoachTrend(
            title: title,
            direction: direction,
            summary: "\(currentCount) of \(currentDates.count) recent days vs \(previousCount) of \(previousDates.count) previous days.",
            currentValue: Double(currentCount),
            previousValue: Double(previousCount),
            confidence: currentCount + previousCount >= target ? .medium : .low
        )
    }

    private func checkInTrend(
        title: String,
        dates: [Date],
        previousDates: [Date],
        checkIns: [DailyCoachCheckIn],
        keyPath: KeyPath<DailyCoachCheckIn, Int>,
        higherIsBetter: Bool
    ) -> CoachTrend {
        trend(
            title: title,
            current: checkInValues(in: dates, checkIns: checkIns, keyPath: keyPath),
            previous: checkInValues(in: previousDates, checkIns: checkIns, keyPath: keyPath),
            threshold: 0.5,
            higherIsBetter: higherIsBetter,
            unit: "rating"
        )
    }

    private func checkInValues(in dates: [Date], checkIns: [DailyCoachCheckIn], keyPath: KeyPath<DailyCoachCheckIn, Int>) -> [Double] {
        dates.compactMap { day in
            todayCheckIn(from: checkIns, date: day).map { Double($0[keyPath: keyPath]) }
        }
    }

    private func hydrationHitDays(in dates: [Date], entries: [HydrationEntry], targetML: Int) -> Int {
        dates.filter { date in
            hydrationService.summary(for: date, entries: entries, targetML: targetML, calendar: calendar).progress >= 0.70
        }.count
    }

    private func nutritionLoggedDays(in dates: [Date], foodLogs: [FoodLogEntry]) -> Int {
        dates.filter { date in
            foodLogs.contains { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        }.count
    }

    private func completedWorkingSets(from exerciseLog: ExerciseLog) -> [SetLog] {
        exerciseLog.setLogs
            .filter { $0.completed && !$0.isWarmup }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func estimatedOneRepMax(_ set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func progressRank(_ state: LiftProgressState) -> Int {
        switch state {
        case .declining:
            return 3
        case .steady:
            return 2
        case .improving:
            return 1
        }
    }

    private func muscleGroups(for log: ExerciseLog, exercisesByID: [UUID: Exercise]) -> [MuscleGroup] {
        if let exercise = exercisesByID[log.exerciseId] {
            return ([exercise.primaryMuscleGroup] + exercise.secondaryMuscleGroups)
                .filter { majorMuscleGroups.contains($0) }
        }

        return inferredMuscleGroups(from: log.exerciseNameSnapshot)
    }

    private func inferredMuscleGroups(from name: String) -> [MuscleGroup] {
        let lower = name.lowercased()

        if lower.contains("leg press") || lower.contains("squat") || lower.contains("extension") {
            return [.quads, .glutes]
        }
        if lower.contains("curl") && lower.contains("leg") {
            return [.hamstrings]
        }
        if lower.contains("calf") {
            return [.calves]
        }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull-up") || lower.contains("pull up") {
            return [.back, .biceps]
        }
        if lower.contains("bench") || lower.contains("chest") || lower.contains("fly") {
            return [.chest, .triceps]
        }
        if lower.contains("shoulder") || lower.contains("lateral") || lower.contains("delt") {
            return [.shoulders]
        }
        if lower.contains("tricep") {
            return [.triceps]
        }
        if lower.contains("bicep") || lower.contains("preacher") {
            return [.biceps]
        }
        if lower.contains("crunch") || lower.contains("core") || lower.contains("abdominal") {
            return [.core]
        }

        return []
    }

    private func insight(
        _ id: String,
        title: String,
        summary: String,
        category: CoachInsightCategory,
        severity: CoachIntelligenceSeverity,
        confidence: ReadinessConfidence,
        factors: [String],
        action: String,
        relatedArea: String? = nil
    ) -> CoachIntelligenceInsight {
        CoachIntelligenceInsight(
            id: id,
            title: title,
            summary: summary,
            category: category,
            severity: severity,
            confidence: confidence,
            supportingFactors: factors,
            recommendedAction: action,
            relatedArea: relatedArea
        )
    }
}

private struct ReadinessSignal {
    let score: Int
    let weight: Double
    let factor: ReadinessFactor
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private extension Date {
    func endOfDay(using calendar: Calendar) -> Date {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: self)) else {
            return self
        }
        return nextDay.addingTimeInterval(-1)
    }
}
