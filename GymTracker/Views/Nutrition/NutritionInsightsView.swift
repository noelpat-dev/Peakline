import SwiftData
import SwiftUI
import UIKit

struct NutritionInsightsDashboardView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var foodLogs: [FoodLogEntry]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @State private var goal = NutritionGoal.empty
    @State private var healthPreferences = HealthKitSyncPreferences.default
    @State private var appleHealthContext: HealthKitDailyContext?

    private let goalService = NutritionGoalService()
    private let summaryService = NutritionSummaryService()
    private let trendService = NutritionTrendService()
    private let contextService = TrainingNutritionContextService()
    private let insightService = NutritionInsightService()
    private let healthPreferenceStore = HealthKitPreferenceStore()
    private let healthBridge = NutritionHealthKitBridge()

    private var todaySummary: DailyNutritionSummary {
        summaryService.dailySummary(for: .now, foodLogs: foodLogs, workouts: completedSessions)
    }

    private var weeklySummary: WeeklyNutritionSummary {
        trendService.weeklySummary(
            dailySummaries: summaryService.dailySummaries(endingOn: .now, days: 7, foodLogs: foodLogs, workouts: completedSessions),
            goal: goal
        )
    }

    private var trainingContext: TrainingNutritionContext {
        contextService.context(for: .now, foodLogs: foodLogs, workouts: completedSessions)
    }

    private var insights: [NutritionInsight] {
        insightService.insights(today: todaySummary, weekly: weeklySummary, goal: goal, context: trainingContext)
    }

    var body: some View {
        FitnessScreen(
            title: "Nutrition Insights",
            subtitle: "Training-aware nutrition from your local food and workout logs.",
            systemImage: "sparkles"
        ) {
            contextHeader

            DashboardSection(title: "Targets") {
                if goal.hasTargets {
                    MacroTargetGrid(summary: todaySummary, goal: goal)
                } else {
                    NavigationLink {
                        NutritionTargetsView()
                    } label: {
                        NutritionInsightsEmptyCard(
                            title: "Set nutrition targets",
                            message: "Add calories and macro targets to unlock progress cards and training-aware insight rules.",
                            systemImage: "target",
                            actionTitle: "Set Targets"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }

            trainingContextCard
            appleHealthContextCard

            DashboardSection(title: "Insights") {
                LazyVStack(spacing: 12) {
                    ForEach(insights) { insight in
                        InsightCard(insight: insight)
                    }
                }
            }

            DashboardSection(title: "7-Day Trends") {
                WeeklyTrendPreview(summary: weeklySummary, goal: goal)
            }

            DashboardSection(title: "Actions") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink {
                        AddFoodHubView()
                    } label: {
                        NutritionInsightActionTile(title: "Log Food", subtitle: "Add or reuse foods", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    NavigationLink {
                        NutritionTargetsView()
                    } label: {
                        NutritionInsightActionTile(title: "Targets", subtitle: goal.hasTargets ? "Edit daily goals" : "Set goals", systemImage: "target")
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    NavigationLink {
                        WeeklyNutritionTrendsView()
                    } label: {
                        NutritionInsightActionTile(title: "Weekly", subtitle: "Review 7 days", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    NavigationLink {
                        NutritionDashboardView()
                    } label: {
                        NutritionInsightActionTile(title: "Food Log", subtitle: "Today by meal", systemImage: "fork.knife")
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            goal = goalService.loadGoal()
            healthPreferences = healthPreferenceStore.load()
            Task {
                appleHealthContext = await healthBridge.dailyContext(for: .now, preferences: healthPreferences)
            }
        }
    }

    private var contextHeader: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: todaySummary.isTrainingDay ? "figure.strengthtraining.traditional" : "moon.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 48, height: 48)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(todaySummary.isTrainingDay ? "Training day" : "Rest day")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(todaySummary.isTrainingDay ? "\(todaySummary.workoutCount) workout\(todaySummary.workoutCount == 1 ? "" : "s")" : "No workout logged")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(appTheme.colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(appTheme.colors.accentSurface, in: Capsule())
                    }

                    Text(headerMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trainingContextCard: some View {
        DashboardSection(title: "Training Context") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 42, height: 42)
                            .background(appTheme.colors.accentSurface, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(trainingContext.latestWorkoutName ?? (todaySummary.isTrainingDay ? "Workout logged today" : "No workout today"))
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .lineLimit(2)

                            Text(trainingContextMessage)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        NutritionContextMetric(title: "Food logs", value: "\(todaySummary.loggedFoodCount)", caption: "today")
                        NutritionContextMetric(title: "Protein", value: "\(phase7Grams(todaySummary.protein))g", caption: "logged")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appleHealthContextCard: some View {
        if healthPreferences.isHealthKitEnabled, healthPreferences.requestsAnyReadData, let appleHealthContext {
            DashboardSection(title: "Apple Health Context") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(appTheme.colors.accent)
                                .frame(width: 42, height: 42)
                                .background(appTheme.colors.accentSurface, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supporting context")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("Apple Health values are labeled context only. Local GymTracker workouts and nutrition stay primary.")
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            if let bodyMass = appleHealthContext.bodyMassKg {
                                NutritionContextMetric(title: "Weight", value: "\(bodyMass.formatted(.number.precision(.fractionLength(1)))) kg", caption: "Apple Health")
                            }

                            if let activeEnergy = appleHealthContext.activeEnergyKcal {
                                NutritionContextMetric(title: "Active", value: "\(activeEnergy.formatted(.number.precision(.fractionLength(0)))) kcal", caption: "Apple Health")
                            }

                            if let stepCount = appleHealthContext.stepCount {
                                NutritionContextMetric(title: "Steps", value: stepCount.formatted(.number.precision(.fractionLength(0))), caption: "Apple Health")
                            }

                            if let workoutCount = appleHealthContext.workoutCount {
                                NutritionContextMetric(title: "Workouts", value: "\(workoutCount)", caption: "Apple Health")
                            }
                        }
                    }
                }
            }
        }
    }

    private var headerMessage: String {
        if todaySummary.loggedFoodCount == 0 {
            return todaySummary.isTrainingDay
                ? "You trained today. Log food to connect nutrition with this session."
                : "Log food to build today's macro summary."
        }

        return "You have \(todaySummary.loggedFoodCount) food log\(todaySummary.loggedFoodCount == 1 ? "" : "s") today with \(phase7Grams(todaySummary.protein))g protein logged."
    }

    private var trainingContextMessage: String {
        guard todaySummary.isTrainingDay else {
            return "Workout-specific observations stay hidden on days without completed training."
        }

        if let post = trainingContext.postWorkoutProtein {
            return "Within 4 hours after training, \(phase7Grams(post))g protein is logged."
        }

        if trainingContext.hasFoodLoggedAfterWorkout == false {
            return "No food log appears in the 4 hours after today's workout."
        }

        return "Timing details depend on workout start/end times and food log timestamps."
    }
}

struct NutritionTargetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var mode: NutritionTargetMode = .daily
    @State private var isEnabled = true
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var trainingCalories = ""
    @State private var restCalories = ""
    @State private var errorText: String?

    private let goalService = NutritionGoalService()

    var body: some View {
        FitnessScreen(
            title: "Nutrition Targets",
            subtitle: "Set manual targets. GymTracker uses them only for local progress and insight cards.",
            systemImage: "target"
        ) {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable targets", isOn: $isEnabled)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Picker("Target mode", selection: $mode) {
                        ForEach(NutritionTargetMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            DashboardSection(title: "Daily Targets") {
                FitnessCard {
                    VStack(spacing: 14) {
                        TargetTextField(title: "Calories", text: $calories, placeholder: "Optional", suffix: "kcal")
                        TargetTextField(title: "Protein", text: $protein, placeholder: "Optional", suffix: "g")
                        TargetTextField(title: "Carbs", text: $carbs, placeholder: "Optional", suffix: "g")
                        TargetTextField(title: "Fat", text: $fat, placeholder: "Optional", suffix: "g")
                    }
                }
            }

            if mode == .trainingAndRestDay {
                DashboardSection(title: "Optional Calorie Split") {
                    FitnessCard {
                        VStack(spacing: 14) {
                            TargetTextField(title: "Training day calories", text: $trainingCalories, placeholder: "Optional", suffix: "kcal")
                            TargetTextField(title: "Rest day calories", text: $restCalories, placeholder: "Optional", suffix: "kcal")
                        }
                    }
                }
            }

            FitnessCard(padding: 16) {
                Label("Targets are not dietary advice. They are manual numbers used to explain your logged data.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText {
                FitnessCard(padding: 16) {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.danger)
                }
            }

            Button {
                save()
            } label: {
                Label("Save Targets", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
        }
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        let goal = goalService.loadGoal()
        isEnabled = goal.isEnabled
        calories = fieldText(goal.dailyCaloriesTarget)
        protein = fieldText(goal.dailyProteinTarget)
        carbs = fieldText(goal.dailyCarbsTarget)
        fat = fieldText(goal.dailyFatTarget)
        trainingCalories = fieldText(goal.trainingDayCaloriesTarget)
        restCalories = fieldText(goal.restDayCaloriesTarget)
        mode = (goal.trainingDayCaloriesTarget != nil || goal.restDayCaloriesTarget != nil) ? .trainingAndRestDay : .daily
    }

    private func save() {
        guard
            let caloriesValue = parseOptionalPositive(calories),
            let proteinValue = parseOptionalPositive(protein),
            let carbsValue = parseOptionalPositive(carbs),
            let fatValue = parseOptionalPositive(fat),
            let trainingValue = parseOptionalPositive(trainingCalories),
            let restValue = parseOptionalPositive(restCalories)
        else {
            errorText = "Targets must be positive numbers or left blank."
            return
        }

        let goal = NutritionGoal(
            dailyCaloriesTarget: caloriesValue,
            dailyProteinTarget: proteinValue,
            dailyCarbsTarget: carbsValue,
            dailyFatTarget: fatValue,
            trainingDayCaloriesTarget: mode == .trainingAndRestDay ? trainingValue : nil,
            restDayCaloriesTarget: mode == .trainingAndRestDay ? restValue : nil,
            isEnabled: isEnabled,
            updatedAt: .now
        )

        goalService.saveGoal(goal)
        dismiss()
    }

    private func parseOptionalPositive(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return .some(value)
    }

    private func fieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct WeeklyNutritionTrendsView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var foodLogs: [FoodLogEntry]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @State private var goal = NutritionGoal.empty

    private let goalService = NutritionGoalService()
    private let summaryService = NutritionSummaryService()
    private let trendService = NutritionTrendService()

    private var weeklySummary: WeeklyNutritionSummary {
        trendService.weeklySummary(
            dailySummaries: summaryService.dailySummaries(endingOn: .now, days: 7, foodLogs: foodLogs, workouts: completedSessions),
            goal: goal
        )
    }

    var body: some View {
        FitnessScreen(
            title: "Weekly Nutrition",
            subtitle: "Seven local days of food logs, target progress, and training context.",
            systemImage: "chart.bar.fill"
        ) {
            WeeklyTrendPreview(summary: weeklySummary, goal: goal)

            DashboardSection(title: "Weekly Summary") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    NutritionContextMetric(title: "Logged days", value: "\(weeklySummary.loggedDays)/\(weeklySummary.dailySummaries.count)", caption: "food present")
                    NutritionContextMetric(title: "Training days", value: "\(weeklySummary.trainingDays)", caption: "completed")
                    NutritionContextMetric(title: "Protein hit", value: "\(weeklySummary.proteinTargetHitDays)", caption: "target days")
                    NutritionContextMetric(title: "Avg kcal", value: phase7Kcal(weeklySummary.averageCalories), caption: "per day")
                }
            }

            if let trainingAverage = weeklySummary.trainingDayAverageCalories, let restAverage = weeklySummary.restDayAverageCalories {
                FitnessCard {
                    Label("Training days average \(phase7Kcal(trainingAverage)) kcal vs \(phase7Kcal(restAverage)) kcal on rest days.", systemImage: "chart.xyaxis.line")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Weekly")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            goal = goalService.loadGoal()
        }
    }
}

struct NutritionHomeSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var foodLogs: [FoodLogEntry]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @State private var goal = NutritionGoal.empty

    private let goalService = NutritionGoalService()
    private let summaryService = NutritionSummaryService()
    private let trendService = NutritionTrendService()
    private let contextService = TrainingNutritionContextService()
    private let insightService = NutritionInsightService()

    private var today: DailyNutritionSummary {
        summaryService.dailySummary(for: .now, foodLogs: foodLogs, workouts: completedSessions)
    }

    private var weekly: WeeklyNutritionSummary {
        trendService.weeklySummary(
            dailySummaries: summaryService.dailySummaries(endingOn: .now, days: 7, foodLogs: foodLogs, workouts: completedSessions),
            goal: goal
        )
    }

    private var topInsight: NutritionInsight? {
        let context = contextService.context(for: .now, foodLogs: foodLogs, workouts: completedSessions)
        return insightService.insights(today: today, weekly: weekly, goal: goal, context: context, limit: 1).first
    }

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 44, height: 44)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Nutrition Today")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(today.isTrainingDay ? "Training" : "Rest")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(appTheme.colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.accentSurface, in: Capsule())
                        }

                        Text(topInsight?.title ?? "Log food to unlock training-aware insights")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                HStack(spacing: 8) {
                    compactMetric(title: "kcal", value: phase7Kcal(today.calories), target: goal.calorieTarget(isTrainingDay: today.isTrainingDay).map(phase7Kcal))
                    compactMetric(title: "Protein", value: "\(phase7Grams(today.protein))g", target: goal.dailyProteinTarget.map { "\(phase7Grams($0))g" })
                }
            }
        }
        .onAppear {
            goal = goalService.loadGoal()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nutrition today, \(phase7Kcal(today.calories)) calories, \(phase7Grams(today.protein)) grams protein")
    }

    private func compactMetric(title: String, value: String, target: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value + (target.map { " / \($0)" } ?? ""))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MacroTargetGrid: View {
    let summary: DailyNutritionSummary
    let goal: NutritionGoal

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            MacroTargetProgressCard(title: "Calories", current: summary.calories, target: goal.calorieTarget(isTrainingDay: summary.isTrainingDay), unit: "kcal", systemImage: "flame.fill")
            MacroTargetProgressCard(title: "Protein", current: summary.protein, target: goal.dailyProteinTarget, unit: "g", systemImage: "bolt.heart.fill")
            MacroTargetProgressCard(title: "Carbs", current: summary.carbs, target: goal.dailyCarbsTarget, unit: "g", systemImage: "leaf.fill")
            MacroTargetProgressCard(title: "Fat", current: summary.fat, target: goal.dailyFatTarget, unit: "g", systemImage: "drop.fill")
        }
    }
}

private struct MacroTargetProgressCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let current: Double
    let target: Double?
    let unit: String
    let systemImage: String

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(current / target, 1.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(appTheme.colors.accent)
                Spacer()
                Text(statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusTint)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            Text(valueText)
                .font(.title3.bold())
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            SwiftUI.ProgressView(value: progress, total: 1)
                .tint(statusTint)
                .accessibilityLabel("\(title) progress \(Int(progress * 100)) percent")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }

    private var valueText: String {
        let currentText = unit == "kcal" ? phase7Kcal(current) : phase7Grams(current)
        guard let target else { return "\(currentText)\(unit == "kcal" ? "" : unit)" }
        let targetText = unit == "kcal" ? phase7Kcal(target) : phase7Grams(target)
        return unit == "kcal" ? "\(currentText) / \(targetText)" : "\(currentText) / \(targetText)g"
    }

    private var statusText: String {
        guard let target, target > 0 else { return "No target" }
        let remaining = max(target - current, 0)
        if remaining == 0 { return "Hit" }
        return unit == "kcal" ? "\(phase7Kcal(remaining)) left" : "\(phase7Grams(remaining))g left"
    }

    private var statusTint: Color {
        guard let target, target > 0 else { return appTheme.colors.textTertiary }
        return current >= target ? appTheme.colors.success : appTheme.colors.accent
    }
}

private struct InsightCard: View {
    @Environment(\.appTheme) private var appTheme

    let insight: NutritionInsight

    var body: some View {
        FitnessCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: insight.category.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(insight.category.displayName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(tint.opacity(0.14), in: Capsule())
                        }

                        Text(insight.message)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let supportingValue = insight.supportingValue {
                    Text(supportingValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                }

                if let action = insight.action {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return appTheme.colors.success
        case .attention:
            return appTheme.colors.warning
        case .warning:
            return appTheme.colors.warning
        case .info:
            return appTheme.colors.accent
        }
    }
}

private struct WeeklyTrendPreview: View {
    @Environment(\.appTheme) private var appTheme

    let summary: WeeklyNutritionSummary
    let goal: NutritionGoal

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Food logs are present for \(summary.loggedDays) of the last \(summary.dailySummaries.count) days.")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("Protein target hit on \(summary.proteinTargetHitDays) days. \(summary.trainingDays) training day\(summary.trainingDays == 1 ? "" : "s") logged.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(summary.dailySummaries) { day in
                        dayColumn(day)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayColumn(_ day: DailyNutritionSummary) -> some View {
        let proteinProgress = min((goal.dailyProteinTarget.map { day.protein / max($0, 1) } ?? (day.loggedFoodCount > 0 ? 0.35 : 0)), 1)
        let height = max(12, 54 * proteinProgress)

        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(day.loggedFoodCount == 0 ? appTheme.colors.cardBackgroundElevated : (day.isTrainingDay ? appTheme.colors.accent : appTheme.colors.success))
                .frame(height: height)
                .frame(maxHeight: 58, alignment: .bottom)

            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.isTrainingDay ? appTheme.colors.accent : appTheme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .bottom)
        .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)), \(day.loggedFoodCount) food logs, \(day.isTrainingDay ? "training day" : "rest day")")
    }
}

private struct NutritionContextMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NutritionInsightActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        DashboardActionTile(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            showsChevron: false,
            minHeight: 132
        )
    }
}

private struct NutritionInsightsEmptyCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 48, height: 48)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle {
                    Label(actionTitle, systemImage: "arrow.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                }
            }
        }
    }
}

private struct TargetTextField: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    @Binding var text: String
    let placeholder: String
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(suffix)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(appTheme.colors.cardBorder, lineWidth: 1)
            }
        }
    }
}

private func phase7Kcal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}

private func phase7Grams(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(value < 10 && value != 0 ? 1 : 0)))
}
