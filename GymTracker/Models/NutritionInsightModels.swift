import Foundation

struct NutritionGoal: Codable, Equatable {
    var dailyCaloriesTarget: Double?
    var dailyProteinTarget: Double?
    var dailyCarbsTarget: Double?
    var dailyFatTarget: Double?
    var dailyFibreTarget: Double? = nil
    var trainingDayCaloriesTarget: Double?
    var restDayCaloriesTarget: Double?
    var isEnabled: Bool
    var updatedAt: Date

    static var empty: NutritionGoal {
        NutritionGoal(
            dailyCaloriesTarget: nil,
            dailyProteinTarget: nil,
            dailyCarbsTarget: nil,
            dailyFatTarget: nil,
            dailyFibreTarget: nil,
            trainingDayCaloriesTarget: nil,
            restDayCaloriesTarget: nil,
            isEnabled: false,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    var hasTargets: Bool {
        isEnabled && [dailyCaloriesTarget, dailyProteinTarget, dailyCarbsTarget, dailyFatTarget, dailyFibreTarget, trainingDayCaloriesTarget, restDayCaloriesTarget]
            .contains { ($0 ?? 0) > 0 }
    }

    func calorieTarget(isTrainingDay: Bool) -> Double? {
        if isTrainingDay, let trainingDayCaloriesTarget, trainingDayCaloriesTarget > 0 {
            return trainingDayCaloriesTarget
        }

        if !isTrainingDay, let restDayCaloriesTarget, restDayCaloriesTarget > 0 {
            return restDayCaloriesTarget
        }

        return dailyCaloriesTarget
    }
}

enum NutritionTargetMode: String, Codable, CaseIterable, Identifiable {
    case daily
    case trainingAndRestDay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .trainingAndRestDay:
            return "Training / Rest"
        }
    }
}

struct MealNutritionSummary: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sugar: Double?
    var fibre: Double?
    var salt: Double?
    var itemCount: Int
}

struct DailyNutritionSummary: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sugar: Double?
    var fibre: Double?
    var salt: Double?
    var loggedFoodCount: Int
    var mealBreakdown: [MealType: MealNutritionSummary]
    var isTrainingDay: Bool
    var workoutCount: Int
}

struct WeeklyNutritionSummary: Codable, Equatable {
    var startDate: Date
    var endDate: Date
    var dailySummaries: [DailyNutritionSummary]
    var averageCalories: Double
    var averageProtein: Double
    var averageCarbs: Double
    var averageFat: Double
    var proteinTargetHitDays: Int
    var calorieTargetHitDays: Int
    var loggedDays: Int
    var trainingDays: Int
    var trainingDayAverageCalories: Double?
    var restDayAverageCalories: Double?
}

struct TrainingNutritionContext: Codable, Equatable {
    var date: Date
    var isTrainingDay: Bool
    var workoutCount: Int
    var workoutStartTimes: [Date]
    var workoutEndTimes: [Date]
    var preWorkoutCalories: Double?
    var postWorkoutProtein: Double?
    var hasFoodLoggedBeforeWorkout: Bool?
    var hasFoodLoggedAfterWorkout: Bool?
    var latestWorkoutName: String?
}

enum NutritionInsightCategory: String, Codable, CaseIterable {
    case protein
    case calories
    case carbs
    case fats
    case consistency
    case trainingDay
    case recovery
    case logging
    case trend

    var displayName: String {
        switch self {
        case .protein:
            return "Protein"
        case .calories:
            return "Calories"
        case .carbs:
            return "Carbs"
        case .fats:
            return "Fats"
        case .consistency:
            return "Consistency"
        case .trainingDay:
            return "Training"
        case .recovery:
            return "Recovery"
        case .logging:
            return "Logging"
        case .trend:
            return "Trend"
        }
    }

    var systemImage: String {
        switch self {
        case .protein:
            return "bolt.heart.fill"
        case .calories:
            return "flame.fill"
        case .carbs:
            return "leaf.fill"
        case .fats:
            return "drop.fill"
        case .consistency:
            return "calendar.badge.checkmark"
        case .trainingDay:
            return "figure.strengthtraining.traditional"
        case .recovery:
            return "heart.text.square.fill"
        case .logging:
            return "fork.knife"
        case .trend:
            return "chart.xyaxis.line"
        }
    }
}

enum NutritionInsightSeverity: String, Codable, CaseIterable {
    case info
    case positive
    case warning
    case attention
}

enum NutritionInsightAction: Codable, Equatable {
    case logFood
    case viewFoodLog
    case setTargets
    case viewWorkout
    case viewWeeklyTrends

    var title: String {
        switch self {
        case .logFood:
            return "Log Food"
        case .viewFoodLog:
            return "View Food Log"
        case .setTargets:
            return "Set Targets"
        case .viewWorkout:
            return "View Workout"
        case .viewWeeklyTrends:
            return "Weekly Trends"
        }
    }

    var systemImage: String {
        switch self {
        case .logFood:
            return "plus"
        case .viewFoodLog:
            return "list.bullet.rectangle"
        case .setTargets:
            return "target"
        case .viewWorkout:
            return "figure.strengthtraining.traditional"
        case .viewWeeklyTrends:
            return "chart.bar"
        }
    }
}

struct NutritionInsight: Identifiable, Codable, Equatable {
    var id: UUID
    var category: NutritionInsightCategory
    var severity: NutritionInsightSeverity
    var title: String
    var message: String
    var supportingValue: String?
    var action: NutritionInsightAction?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        category: NutritionInsightCategory,
        severity: NutritionInsightSeverity,
        title: String,
        message: String,
        supportingValue: String? = nil,
        action: NutritionInsightAction? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.message = message
        self.supportingValue = supportingValue
        self.action = action
        self.createdAt = createdAt
    }
}
