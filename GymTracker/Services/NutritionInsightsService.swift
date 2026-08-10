import Foundation

struct NutritionGoalService {
    private let defaults: UserDefaults
    private let key = "nutrition.goal.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadGoal() -> NutritionGoal {
        guard
            let data = defaults.data(forKey: key),
            let goal = try? JSONDecoder().decode(NutritionGoal.self, from: data)
        else {
            return .empty
        }

        return sanitized(goal)
    }

    func saveGoal(_ goal: NutritionGoal) {
        let sanitizedGoal = sanitized(goal)
        guard let data = try? JSONEncoder().encode(sanitizedGoal) else { return }
        defaults.set(data, forKey: key)
    }

    private func sanitized(_ goal: NutritionGoal) -> NutritionGoal {
        NutritionGoal(
            dailyCaloriesTarget: positive(goal.dailyCaloriesTarget),
            dailyProteinTarget: positive(goal.dailyProteinTarget),
            dailyCarbsTarget: positive(goal.dailyCarbsTarget),
            dailyFatTarget: positive(goal.dailyFatTarget),
            dailyFibreTarget: positive(goal.dailyFibreTarget),
            trainingDayCaloriesTarget: positive(goal.trainingDayCaloriesTarget),
            restDayCaloriesTarget: positive(goal.restDayCaloriesTarget),
            isEnabled: goal.isEnabled,
            updatedAt: goal.updatedAt
        )
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

struct NutritionSummaryService {
    private let calculator = NutritionCalculatorService()

    func dailySummary(
        for date: Date,
        foodLogs: [FoodLogEntry],
        workouts: [WorkoutSession],
        calendar: Calendar = .current
    ) -> DailyNutritionSummary {
        let dayLogs = foodLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        let totals = calculator.totals(from: dayLogs)
        let dayWorkouts = workouts.filter { $0.completed && calendar.isDate($0.date, inSameDayAs: date) }
        let meals = Dictionary(grouping: dayLogs, by: \.mealType).mapValues { entries in
            let mealTotals = calculator.totals(from: entries)
            return MealNutritionSummary(
                calories: mealTotals.calories,
                protein: mealTotals.protein,
                carbs: mealTotals.carbs,
                fat: mealTotals.fat,
                sugar: mealTotals.sugar,
                fibre: mealTotals.fibre,
                salt: mealTotals.salt,
                itemCount: entries.count
            )
        }

        return DailyNutritionSummary(
            id: dayIdentifier(for: date, calendar: calendar),
            date: calendar.startOfDay(for: date),
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            sugar: totals.sugar,
            fibre: totals.fibre,
            salt: totals.salt,
            loggedFoodCount: dayLogs.count,
            mealBreakdown: meals,
            isTrainingDay: !dayWorkouts.isEmpty,
            workoutCount: dayWorkouts.count
        )
    }

    func dailySummaries(
        endingOn endDate: Date,
        days: Int,
        foodLogs: [FoodLogEntry],
        workouts: [WorkoutSession],
        calendar: Calendar = .current
    ) -> [DailyNutritionSummary] {
        let end = calendar.startOfDay(for: endDate)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return dailySummary(for: date, foodLogs: foodLogs, workouts: workouts, calendar: calendar)
        }
    }

    private func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct TrainingNutritionContextService {
    private let windowSeconds: TimeInterval = 4 * 60 * 60
    private let calculator = NutritionCalculatorService()

    func context(
        for date: Date,
        foodLogs: [FoodLogEntry],
        workouts: [WorkoutSession],
        calendar: Calendar = .current
    ) -> TrainingNutritionContext {
        let dayWorkouts = workouts
            .filter { $0.completed && calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { ($0.startedAt ?? $0.date) < ($1.startedAt ?? $1.date) }
        let dayLogs = foodLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        let startTimes = dayWorkouts.compactMap(\.startedAt)
        let endTimes = dayWorkouts.compactMap(\.endedAt)

        let preWorkoutLogs = startTimes.flatMap { start in
            dayLogs.filter { $0.loggedAt >= start.addingTimeInterval(-windowSeconds) && $0.loggedAt <= start }
        }
        let postWorkoutLogs = endTimes.flatMap { end in
            dayLogs.filter { $0.loggedAt >= end && $0.loggedAt <= end.addingTimeInterval(windowSeconds) }
        }

        let uniquePreLogs = uniqueLogs(preWorkoutLogs)
        let uniquePostLogs = uniqueLogs(postWorkoutLogs)
        let preTotals = uniquePreLogs.isEmpty ? nil : calculator.totals(from: uniquePreLogs)
        let postTotals = uniquePostLogs.isEmpty ? nil : calculator.totals(from: uniquePostLogs)

        return TrainingNutritionContext(
            date: calendar.startOfDay(for: date),
            isTrainingDay: !dayWorkouts.isEmpty,
            workoutCount: dayWorkouts.count,
            workoutStartTimes: startTimes,
            workoutEndTimes: endTimes,
            preWorkoutCalories: preTotals?.calories,
            postWorkoutProtein: postTotals?.protein,
            hasFoodLoggedBeforeWorkout: startTimes.isEmpty ? nil : !uniquePreLogs.isEmpty,
            hasFoodLoggedAfterWorkout: endTimes.isEmpty ? nil : !uniquePostLogs.isEmpty,
            latestWorkoutName: dayWorkouts.last?.splitNameSnapshot
        )
    }

    private func uniqueLogs(_ logs: [FoodLogEntry]) -> [FoodLogEntry] {
        var seen = Set<UUID>()
        return logs.filter { log in
            guard !seen.contains(log.id) else { return false }
            seen.insert(log.id)
            return true
        }
    }
}

struct NutritionTrendService {
    func weeklySummary(
        dailySummaries: [DailyNutritionSummary],
        goal: NutritionGoal,
        calendar: Calendar = .current
    ) -> WeeklyNutritionSummary {
        let sorted = dailySummaries.sorted { $0.date < $1.date }
        let count = max(sorted.count, 1)
        let proteinTarget = goal.dailyProteinTarget
        let calorieHitDays = sorted.filter { day in
            guard let target = goal.calorieTarget(isTrainingDay: day.isTrainingDay), target > 0 else { return false }
            return abs(day.calories - target) / target <= 0.10
        }.count

        let trainingCalorieDays = sorted.filter { $0.isTrainingDay && $0.loggedFoodCount > 0 }.map(\.calories)
        let restCalorieDays = sorted.filter { !$0.isTrainingDay && $0.loggedFoodCount > 0 }.map(\.calories)

        return WeeklyNutritionSummary(
            startDate: sorted.first?.date ?? calendar.startOfDay(for: .now),
            endDate: sorted.last?.date ?? calendar.startOfDay(for: .now),
            dailySummaries: sorted,
            averageCalories: sorted.reduce(0) { $0 + $1.calories } / Double(count),
            averageProtein: sorted.reduce(0) { $0 + $1.protein } / Double(count),
            averageCarbs: sorted.reduce(0) { $0 + $1.carbs } / Double(count),
            averageFat: sorted.reduce(0) { $0 + $1.fat } / Double(count),
            proteinTargetHitDays: sorted.filter { day in
                guard let proteinTarget, proteinTarget > 0 else { return false }
                return day.protein >= proteinTarget
            }.count,
            calorieTargetHitDays: calorieHitDays,
            loggedDays: sorted.filter { $0.loggedFoodCount > 0 }.count,
            trainingDays: sorted.filter(\.isTrainingDay).count,
            trainingDayAverageCalories: average(trainingCalorieDays),
            restDayAverageCalories: average(restCalorieDays)
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct NutritionInsightService {
    func insights(
        today: DailyNutritionSummary,
        weekly: WeeklyNutritionSummary,
        goal: NutritionGoal,
        context: TrainingNutritionContext,
        limit: Int = 5
    ) -> [NutritionInsight] {
        var ranked: [(Int, NutritionInsight)] = []

        if !goal.hasTargets {
            ranked.append((0, NutritionInsight(
                category: .logging,
                severity: .info,
                title: "Set nutrition targets",
                message: "Add calorie and macro targets to unlock training-aware nutrition insights.",
                action: .setTargets
            )))
        }

        if let proteinTarget = goal.dailyProteinTarget, proteinTarget > 0 {
            let remaining = max(proteinTarget - today.protein, 0)
            if context.isTrainingDay {
                if today.protein >= proteinTarget {
                    ranked.append((3, NutritionInsight(
                        category: .trainingDay,
                        severity: .positive,
                        title: "Training day protein covered",
                        message: "You trained today and reached your protein target.",
                        supportingValue: "\(grams(today.protein))g / \(grams(proteinTarget))g"
                    )))
                } else {
                    ranked.append((1, NutritionInsight(
                        category: .trainingDay,
                        severity: .attention,
                        title: "Training day protein gap",
                        message: "You trained today and are \(grams(remaining))g below your protein target.",
                        supportingValue: "\(grams(today.protein))g / \(grams(proteinTarget))g",
                        action: .logFood
                    )))
                }
            } else if today.protein >= proteinTarget {
                ranked.append((4, NutritionInsight(
                    category: .protein,
                    severity: .positive,
                    title: "Protein target hit",
                    message: "You logged \(grams(today.protein))g protein today, reaching your \(grams(proteinTarget))g target.",
                    supportingValue: "\(grams(today.protein))g"
                )))
            } else {
                ranked.append((2, NutritionInsight(
                    category: .protein,
                    severity: .attention,
                    title: "Protein still to log",
                    message: "You are \(grams(remaining))g below your protein target for today.",
                    supportingValue: "\(grams(today.protein))g / \(grams(proteinTarget))g",
                    action: .logFood
                )))
            }

            if weekly.loggedDays >= 3 {
                ranked.append((5, NutritionInsight(
                    category: .consistency,
                    severity: weekly.proteinTargetHitDays >= 4 ? .positive : .info,
                    title: "Weekly protein consistency",
                    message: "You hit your protein target on \(weekly.proteinTargetHitDays) of the last \(weekly.dailySummaries.count) days.",
                    supportingValue: "\(weekly.proteinTargetHitDays)/\(weekly.dailySummaries.count) days",
                    action: .viewWeeklyTrends
                )))
            }
        }

        if let calorieTarget = goal.calorieTarget(isTrainingDay: today.isTrainingDay), calorieTarget > 0 {
            let ratio = today.calories / calorieTarget
            if ratio >= 0.9 && ratio <= 1.1 {
                ranked.append((4, NutritionInsight(
                    category: .calories,
                    severity: .positive,
                    title: "Calories near target",
                    message: "You have logged \(kcal(today.calories)) kcal against a \(kcal(calorieTarget)) kcal target today.",
                    supportingValue: "\(Int(ratio * 100))%"
                )))
            } else if ratio < 0.85 {
                ranked.append((2, NutritionInsight(
                    category: .calories,
                    severity: .attention,
                    title: "Calories are below target",
                    message: "You have logged \(kcal(today.calories)) kcal against a \(kcal(calorieTarget)) kcal target today.",
                    supportingValue: "\(kcal(calorieTarget - today.calories)) kcal remaining",
                    action: .logFood
                )))
            } else if ratio > 1.15 {
                ranked.append((4, NutritionInsight(
                    category: .calories,
                    severity: .info,
                    title: "Calories above target",
                    message: "You have logged \(kcal(today.calories)) kcal against a \(kcal(calorieTarget)) kcal target today.",
                    supportingValue: "\(Int(ratio * 100))%"
                )))
            }
        }

        if context.isTrainingDay {
            if context.hasFoodLoggedAfterWorkout == false {
                ranked.append((6, NutritionInsight(
                    category: .recovery,
                    severity: .info,
                    title: "No post-workout food logged",
                    message: "No food was logged in the 4 hours after today's workout.",
                    action: .logFood
                )))
            } else if let postWorkoutProtein = context.postWorkoutProtein, postWorkoutProtein < 20 {
                ranked.append((6, NutritionInsight(
                    category: .recovery,
                    severity: .info,
                    title: "Post-workout protein is light",
                    message: "You logged \(grams(postWorkoutProtein))g protein within 4 hours after today's workout.",
                    supportingValue: "\(grams(postWorkoutProtein))g",
                    action: .logFood
                )))
            }

            if context.hasFoodLoggedBeforeWorkout == false {
                ranked.append((7, NutritionInsight(
                    category: .trainingDay,
                    severity: .info,
                    title: "No pre-workout food logged",
                    message: "No food was logged in the 4 hours before today's workout.",
                    action: .logFood
                )))
            }
        }

        let missingLogDays = weekly.dailySummaries.count - weekly.loggedDays
        if missingLogDays >= 2 {
            ranked.append((6, NutritionInsight(
                category: .logging,
                severity: .info,
                title: "Food logging gaps",
                message: "Food logs are missing for \(missingLogDays) of the last \(weekly.dailySummaries.count) days.",
                supportingValue: "\(weekly.loggedDays)/\(weekly.dailySummaries.count) days logged",
                action: .viewWeeklyTrends
            )))
        }

        if
            let trainingAverage = weekly.trainingDayAverageCalories,
            let restAverage = weekly.restDayAverageCalories,
            weekly.dailySummaries.filter({ $0.isTrainingDay && $0.loggedFoodCount > 0 }).count >= 2,
            weekly.dailySummaries.filter({ !$0.isTrainingDay && $0.loggedFoodCount > 0 }).count >= 2
        {
            ranked.append((7, NutritionInsight(
                category: .trend,
                severity: .info,
                title: "Training day calorie trend",
                message: "Your training days average \(kcal(trainingAverage)) kcal vs \(kcal(restAverage)) kcal on rest days this week.",
                supportingValue: "\(kcal(trainingAverage)) / \(kcal(restAverage)) kcal",
                action: .viewWeeklyTrends
            )))
        }

        if let distributionInsight = mealDistributionInsight(today: today) {
            ranked.append((8, distributionInsight))
        }

        if ranked.isEmpty {
            ranked.append((9, NutritionInsight(
                category: .logging,
                severity: .info,
                title: "No insights yet",
                message: "Log a few meals and workouts to unlock training-aware nutrition insights.",
                action: .logFood
            )))
        }

        return ranked
            .sorted { $0.0 < $1.0 }
            .map(\.1)
            .prefix(limit)
            .map { $0 }
    }

    private func mealDistributionInsight(today: DailyNutritionSummary) -> NutritionInsight? {
        guard today.loggedFoodCount >= 3, today.protein >= 40 else { return nil }
        let mealProteins = today.mealBreakdown.mapValues(\.protein)
        guard let maxMeal = mealProteins.max(by: { $0.value < $1.value }) else { return nil }
        guard maxMeal.value / max(today.protein, 1) >= 0.65 else { return nil }

        return NutritionInsight(
            category: .protein,
            severity: .info,
            title: "Protein is concentrated in \(maxMeal.key.displayName.lowercased())",
            message: "Most of today's protein is logged in \(maxMeal.key.displayName.lowercased()). Spreading intake is optional, but this shows your current pattern.",
            supportingValue: "\(grams(maxMeal.value))g in one meal"
        )
    }

    private func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...0)))
    }

    private func kcal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...0)))
    }
}
