import SwiftData
import SwiftUI

struct NutritionDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @Query
    private var logEntries: [FoodLogEntry]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @Query
    private var hydrationEntries: [HydrationEntry]

    @Query
    private var coachCheckIns: [DailyCoachCheckIn]

    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var healthPreferences = HealthKitPreferenceStore().load()
    @State private var hydrationTargetML = HydrationSettingsStore().dailyTargetML()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()

    private let coachIntelligence = CoachIntelligenceService()
    private let calculator = NutritionCalculatorService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalStore = NutritionGoalService()
    @State private var pendingDeleteLogEntry: FoodLogEntry?
    @State private var dashboardSnapshot = NutritionDashboardSnapshot.empty
    @State private var lastDashboardSignature: String?
    @State private var selectedRoute: NutritionRoute?
    @State private var didRequestInitialRefresh = false
    @State private var deferredDashboardRefreshWorkItem: DispatchWorkItem?

    init() {
        _logEntries = Query(Self.logEntriesDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
        _hydrationEntries = Query(Self.hydrationEntriesDescriptor)
        _coachCheckIns = Query(Self.coachCheckInsDescriptor)
    }

    private static var logEntriesDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private static var hydrationEntriesDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var coachCheckInsDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private var currentDashboardSnapshot: NutritionDashboardSnapshot {
        guard lastDashboardSignature != nil else {
            return dashboardSnapshot
        }

        let signature = dashboardSignature
        if signature == lastDashboardSignature {
            return dashboardSnapshot
        }

        return dashboardSnapshot
    }

    private var dashboardSignature: String {
        let foodItemsSignature = foodItems.map(foodItemSignature).joined(separator: ",")
        let logEntriesSignature = logEntries.prefix(160).map(foodLogEntrySignature).joined(separator: ",")
        let workoutsSignature = completedSessions.prefix(40).map(workoutSignature).joined(separator: ",")
        let sleepSignature = sleepSessions.prefix(60).map(sleepSessionSignature).joined(separator: ",")
        let napSignature = napSessions.prefix(30).map(napSessionSignature).joined(separator: ",")
        let hydrationSignature = hydrationEntries.prefix(120).map(hydrationEntrySignature).joined(separator: ",")
        let checkInSignature = coachCheckIns.prefix(30).map(coachCheckInSignature).joined(separator: ",")
        let sleepSettingsSignature = String(sleepSettings.lastHealthKitSleepSyncAt?.timeIntervalSince1970 ?? 0)
        let hydrationTargetSignature = String(hydrationTargetML)
        let nutritionGoalSignature = String(nutritionGoal.updatedAt.timeIntervalSince1970)
        let healthKitSignature = healthPreferences.isHealthKitEnabled ? "healthkit-on" : "healthkit-off"
        let parts: [String] = [
            foodItemsSignature,
            logEntriesSignature,
            workoutsSignature,
            sleepSignature,
            napSignature,
            hydrationSignature,
            checkInSignature,
            sleepSettingsSignature,
            hydrationTargetSignature,
            nutritionGoalSignature,
            healthKitSignature
        ]
        return parts.joined(separator: "|")
    }

    private func workoutSignature(_ session: WorkoutSession) -> String {
        let endedAt = session.endedAt?.timeIntervalSince1970 ?? 0
        return "\(session.id.uuidString):\(endedAt)"
    }

    private func foodItemSignature(_ food: FoodItem) -> String {
        "\(food.id.uuidString):\(food.updatedAt.timeIntervalSince1970)"
    }

    private func foodLogEntrySignature(_ entry: FoodLogEntry) -> String {
        "\(entry.id.uuidString):\(entry.updatedAt.timeIntervalSince1970):\(entry.loggedAt.timeIntervalSince1970)"
    }

    private func sleepSessionSignature(_ session: SleepSession) -> String {
        "\(session.id.uuidString):\(session.updatedAt.timeIntervalSince1970)"
    }

    private func napSessionSignature(_ session: NapSession) -> String {
        "\(session.id.uuidString):\(session.updatedAt.timeIntervalSince1970)"
    }

    private func hydrationEntrySignature(_ entry: HydrationEntry) -> String {
        "\(entry.id.uuidString):\(entry.updatedAt.timeIntervalSince1970)"
    }

    private func coachCheckInSignature(_ checkIn: DailyCoachCheckIn) -> String {
        "\(checkIn.id.uuidString):\(checkIn.updatedAt.timeIntervalSince1970)"
    }

    private var todaysEntries: [FoodLogEntry] {
        currentDashboardSnapshot.todaysEntries
    }

    private var totals: NutritionMacroSnapshot {
        currentDashboardSnapshot.totals
    }

    private var readinessScore: ReadinessScore {
        currentDashboardSnapshot.readiness
    }

    private var recentlyLoggedFoods: [FoodItem] {
        currentDashboardSnapshot.recentlyLoggedFoods
    }

    private func refreshDashboardSnapshot(force: Bool = false) {
        let signature = dashboardSignature
        guard force || signature != lastDashboardSignature else { return }
        dashboardSnapshot = PerformanceTracer.trace(.nutritionDashboardSnapshot) {
            makeDashboardSnapshot()
        }
        lastDashboardSignature = signature
    }

    private func makeDashboardSnapshot() -> NutritionDashboardSnapshot {
        let todaysEntries = logEntries.filter { Calendar.current.isDateInToday($0.loggedAt) }
        let recentFoods = recentlyLoggedFoods(from: logEntries, foodItems: foodItems)
        let mealEntries = Dictionary(grouping: todaysEntries.sorted { $0.loggedAt < $1.loggedAt }, by: \.mealType)
        let readiness = coachIntelligence.readiness(
            sleepSessions: Array(sleepSessions.prefix(60)),
            napSessions: Array(napSessions.prefix(30)),
            hydrationEntries: Array(hydrationEntries.prefix(120)),
            completedWorkouts: Array(completedSessions.prefix(40)),
            foodLogs: Array(logEntries.prefix(160)),
            checkIns: Array(coachCheckIns.prefix(30)),
            sleepSettings: sleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal
        )
        let healthKitSyncRecords = healthKitSyncRecordsByEntryId(for: todaysEntries)

        return NutritionDashboardSnapshot(
            todaysEntries: todaysEntries,
            totals: calculator.totals(from: todaysEntries),
            readiness: readiness,
            recentlyLoggedFoods: recentFoods,
            mealEntries: mealEntries,
            shouldShowHealthKitStatus: healthPreferences.isHealthKitEnabled,
            healthKitSyncRecordsByEntryId: healthKitSyncRecords
        )
    }

    private func healthKitSyncRecordsByEntryId(for entries: [FoodLogEntry]) -> [UUID: HealthKitFoodLogSyncRecord] {
        PerformanceTracer.trace(.nutritionHealthKitRowStatus) {
            guard healthPreferences.isHealthKitEnabled else { return [:] }
            let entryIds = Set(entries.map(\.id))
            return Dictionary(uniqueKeysWithValues: HealthKitSyncStateStore().records().compactMap { record in
                guard entryIds.contains(record.foodLogEntryId) else { return nil }
                return (record.foodLogEntryId, record)
            })
        }
    }

    private func recentlyLoggedFoods(from logEntries: [FoodLogEntry], foodItems: [FoodItem]) -> [FoodItem] {
        let recentIds = logEntries.prefix(160).map(\.foodItemId)
        var seenIds = Set<UUID>()
        let orderedUniqueIds = recentIds.filter { id in
            if seenIds.contains(id) { return false }
            seenIds.insert(id)
            return true
        }

        let recentFoods = orderedUniqueIds.compactMap { id in
            foodItems.first { $0.id == id }
        }

        if recentFoods.isEmpty {
            return Array(foodItems.prefix(3))
        }

        return Array(recentFoods.prefix(3))
    }

    var body: some View {
        let snapshot = currentDashboardSnapshot

        FitnessScreen(title: nil) {
            DashboardHeaderView(
                dateText: todayDateText,
                title: "Nutrition",
                subtitle: "Fuel today and keep macros visible"
            )

            NutritionHeroCard(totals: snapshot.totals, entryCount: snapshot.todaysEntries.count)

            DashboardSection(title: "Coach Context") {
                ReadinessContextCard(
                    readiness: snapshot.readiness,
                    focus: .nutrition,
                    title: "Nutrition in today's readiness"
                )
            }

            DashboardSection(title: "Macros") {
                MacroSummaryGrid(totals: snapshot.totals)
            }

            DashboardSection(title: "Quick Actions") {
                LazyVGrid(columns: actionColumns, spacing: 12) {
                    Button {
                        navigate(to: .addFood)
                    } label: {
                        NutritionActionCard(
                            title: "Add Food",
                            subtitle: "Create or log local foods",
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    Button {
                        navigate(to: .savedFoods)
                    } label: {
                        NutritionActionCard(
                            title: "Saved Foods",
                            subtitle: "\(foodItems.count) verified local items",
                            systemImage: "tray.full.fill"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    Button {
                        navigate(to: .insights)
                    } label: {
                        NutritionActionCard(
                            title: "Insights",
                            subtitle: "Targets, trends, and training context",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    Button {
                        navigate(to: .targets)
                    } label: {
                        NutritionActionCard(
                            title: "Targets",
                            subtitle: "Set calories and macro goals",
                            systemImage: "target"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }

            if !snapshot.recentlyLoggedFoods.isEmpty {
                DashboardSection(title: "Quick Log") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(snapshot.recentlyLoggedFoods) { food in
                                NavigationLink {
                                    LogFoodView(food: food)
                                } label: {
                                    QuickLogFoodCard(food: food)
                                }
                                .buttonStyle(PressableCardButtonStyle())
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollClipDisabled()
                }
            }

            DashboardSection(title: "Today") {
                if snapshot.todaysEntries.isEmpty {
                    Button {
                        navigate(to: .addFood)
                    } label: {
                        NutritionEmptyState(
                            title: "Nothing logged today",
                            message: foodItems.isEmpty
                                ? "Create your first verified food manually, then reuse it whenever it appears in your routine."
                                : "Log a saved food to start today's nutrition summary.",
                            systemImage: "fork.knife.circle",
                            actionTitle: foodItems.isEmpty ? "Create Food" : "Log Food"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(MealType.allCases) { mealType in
                            let entries = snapshot.mealEntries[mealType] ?? []

                            if !entries.isEmpty {
                                MealSectionCard(
                                    mealType: mealType,
                                    entries: entries,
                                    shouldShowHealthKitStatus: snapshot.shouldShowHealthKitStatus,
                                    syncRecordsByEntryId: snapshot.healthKitSyncRecordsByEntryId,
                                    requestDelete: { pendingDeleteLogEntry = $0 }
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            switch route {
            case .addFood:
                AddFoodHubView()
            case .savedFoods:
                FoodDatabaseView()
            case .insights:
                NutritionInsightsDashboardView()
            case .targets:
                NutritionTargetsView()
            case .barcode:
                BarcodeScannerView()
            case .labelScan:
                NutritionLabelScanView()
            }
        }
        .alert("Remove food log?", isPresented: deleteLogAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDeleteLogEntry = nil
            }
            Button("Remove Log", role: .destructive) {
                deletePendingLogEntry()
            }
        } message: {
            Text("This removes the logged entry from your daily totals. The saved food stays in your food database.")
        }
        .onAppear {
            sleepSettings = sleepSettingsStore.load()
            healthPreferences = HealthKitPreferenceStore().load()
            hydrationTargetML = hydrationSettingsStore.dailyTargetML()
            nutritionGoal = nutritionGoalStore.loadGoal()
            let shouldForceRefresh = !didRequestInitialRefresh
            didRequestInitialRefresh = true
            deferredDashboardRefreshWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                refreshDashboardSnapshot(force: shouldForceRefresh)
            }
            deferredDashboardRefreshWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
        .onDisappear {
            deferredDashboardRefreshWorkItem?.cancel()
        }
        .onChange(of: dashboardSignature) { _, _ in
            refreshDashboardSnapshot()
        }
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func navigate(to route: NutritionRoute) {
        AppMotion.smoothNavigate(reduceMotion: reduceMotion) {
            selectedRoute = route
        }
    }

    private var todayDateText: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var deleteLogAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteLogEntry != nil
        } set: { isShowing in
            if !isShowing {
                pendingDeleteLogEntry = nil
            }
        }
    }

    private func deletePendingLogEntry() {
        guard let pendingDeleteLogEntry else { return }
        HealthKitSyncStateStore().removeRecord(for: pendingDeleteLogEntry.id)
        modelContext.delete(pendingDeleteLogEntry)
        try? modelContext.save()
        AppHaptics.warning()
        self.pendingDeleteLogEntry = nil
    }
}

fileprivate enum NutritionRoute: Hashable, Identifiable {
    case addFood
    case savedFoods
    case insights
    case targets
    case barcode
    case labelScan

    var id: Self { self }
}

private struct NutritionDashboardSnapshot {
    var todaysEntries: [FoodLogEntry]
    var totals: NutritionMacroSnapshot
    var readiness: ReadinessScore
    var recentlyLoggedFoods: [FoodItem]
    var mealEntries: [MealType: [FoodLogEntry]]
    var shouldShowHealthKitStatus: Bool
    var healthKitSyncRecordsByEntryId: [UUID: HealthKitFoodLogSyncRecord]

    static let empty = NutritionDashboardSnapshot(
        todaysEntries: [],
        totals: NutritionMacroSnapshot(calories: 0, protein: 0, carbs: 0, fat: 0, sugar: nil, fibre: nil, salt: nil),
        readiness: CoachIntelligenceService.emptySnapshot().readiness,
        recentlyLoggedFoods: [],
        mealEntries: [:],
        shouldShowHealthKitStatus: false,
        healthKitSyncRecordsByEntryId: [:]
    )
}

struct AddFoodHubView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @State private var showingManualEntry = false
    @State private var selectedRoute: AddFoodHubRoute?

    var body: some View {
        FitnessScreen(
            title: "Add Food",
            subtitle: "Save verified foods locally, then log them fast.",
            systemImage: "plus.circle"
        ) {
            DashboardSection(title: "Available Now") {
                LazyVStack(spacing: 12) {
                    barcodeAction

                    labelScanAction

                    Button {
                        showingManualEntry = true
                    } label: {
                        NutritionHubActionCard(
                            title: "Manual Entry",
                            subtitle: "Create a verified food from its label.",
                            systemImage: "square.and.pencil",
                            status: "Manual",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())

                    savedFoodsAction
                }
            }
        }
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            switch route {
            case .barcode:
                BarcodeScannerView()
            case .labelScan:
                NutritionLabelScanView()
            case .savedFoods:
                FoodDatabaseView()
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodEntryView()
        }
    }

    @ViewBuilder
    private var barcodeAction: some View {
        Button {
            navigate(to: .barcode)
        } label: {
            barcodeActionCard
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    @ViewBuilder
    private var labelScanAction: some View {
        Button {
            navigate(to: .labelScan)
        } label: {
            labelScanActionCard
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    @ViewBuilder
    private var savedFoodsAction: some View {
        Button {
            navigate(to: .savedFoods)
        } label: {
            savedFoodsActionCard
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private func navigate(to route: AddFoodHubRoute) {
        AppMotion.smoothNavigate(reduceMotion: reduceMotion) {
            selectedRoute = route
        }
    }

    private var barcodeActionCard: some View {
        NutritionHubActionCard(
            title: "Scan Barcode",
            subtitle: "Check saved foods first, then import nutrition data.",
            systemImage: "barcode.viewfinder",
            status: "Fast lookup",
            isEnabled: true
        )
    }

    private var labelScanActionCard: some View {
        NutritionHubActionCard(
            title: "Scan Label",
            subtitle: "Read a nutrition label from a photo, then confirm values.",
            systemImage: "text.viewfinder",
            status: "OCR MVP",
            isEnabled: true
        )
    }

    private var savedFoodsActionCard: some View {
        NutritionHubActionCard(
            title: "Saved Foods",
            subtitle: foodItems.isEmpty ? "Create a food first, then reuse it here." : "Log one of \(foodItems.count) local foods.",
            systemImage: "tray.full",
            status: "Local",
            isEnabled: true
        )
    }
}

private enum AddFoodHubRoute: Hashable, Identifiable {
    case barcode
    case labelScan
    case savedFoods

    var id: Self { self }
}

struct FoodDatabaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @State private var searchText = ""
    @State private var showingManualEntry = false
    @State private var editingFood: FoodItem?
    @State private var pendingDelete: FoodItem?

    private var filteredFoods: [FoodItem] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return foodItems }

        return foodItems.filter { food in
            food.name.localizedCaseInsensitiveContains(trimmedSearch)
                || (food.brand?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
        }
    }

    var body: some View {
        FitnessScreen(
            title: "Saved Foods",
            subtitle: "Your user-confirmed local food database.",
            systemImage: "tray.full"
        ) {
            FoodDatabaseSummaryCard(foodCount: foodItems.count)

            Button {
                showingManualEntry = true
            } label: {
                Label("Create Manual Food", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())

            NutritionSearchField(searchText: $searchText)

            if filteredFoods.isEmpty {
                Button {
                    if foodItems.isEmpty {
                        showingManualEntry = true
                    }
                } label: {
                    NutritionEmptyState(
                        title: foodItems.isEmpty ? "No saved foods yet" : "No matching foods",
                        message: foodItems.isEmpty
                            ? "Create your first manual food so it can be logged again in seconds."
                            : "Try another food or brand name.",
                        systemImage: foodItems.isEmpty ? "tray" : "magnifyingglass",
                        actionTitle: foodItems.isEmpty ? "Create Food" : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(!foodItems.isEmpty)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredFoods) { food in
                        SavedFoodCard(
                            food: food,
                            edit: { editingFood = food },
                            delete: { pendingDelete = food }
                        )
                    }
                }
            }
        }
        .navigationTitle("Saved Foods")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodEntryView()
        }
        .sheet(item: $editingFood) { food in
            ManualFoodEntryView(food: food)
        }
        .alert("Delete food?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingFood()
            }
        } message: {
            Text("This removes the saved food. Existing log entries keep their snapshot macros.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDelete != nil
        } set: { isShowing in
            if !isShowing {
                pendingDelete = nil
            }
        }
    }

    private func deletePendingFood() {
        guard let pendingDelete else { return }
        modelContext.delete(pendingDelete)
        try? modelContext.save()
        AppHaptics.warning()
        self.pendingDelete = nil
    }
}

struct ManualFoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    private let food: FoodItem?

    @State private var name: String
    @State private var brand: String
    @State private var servingSize: String
    @State private var baseUnit: FoodAmountUnit
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var sugar: String
    @State private var fibre: String
    @State private var salt: String
    @State private var errorText: String?

    init(food: FoodItem? = nil) {
        self.food = food
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingSize = State(initialValue: Self.fieldText(food?.servingSize))
        _baseUnit = State(initialValue: food?.baseUnit ?? .grams)
        _calories = State(initialValue: Self.fieldText(food?.caloriesPer100g))
        _protein = State(initialValue: Self.fieldText(food?.proteinPer100g))
        _carbs = State(initialValue: Self.fieldText(food?.carbsPer100g))
        _fat = State(initialValue: Self.fieldText(food?.fatPer100g))
        _sugar = State(initialValue: Self.fieldText(food?.sugarPer100g))
        _fibre = State(initialValue: Self.fieldText(food?.fibrePer100g))
        _salt = State(initialValue: Self.fieldText(food?.saltPer100g))
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: food == nil ? "Manual Food" : "Edit Food",
                subtitle: "User-confirmed nutrition stays local and reusable.",
                systemImage: "square.and.pencil"
            ) {
                ManualFoodTrustCard(isEditing: food != nil)

                DashboardSection(title: "Food Identity") {
                    FitnessCard {
                        VStack(spacing: 14) {
                            NutritionTextField(title: "Food name", text: $name, placeholder: "Chicken Breast")
                            NutritionTextField(title: "Brand", text: $brand, placeholder: "Optional")
                        }
                    }
                }

                DashboardSection(title: "Nutrition Basis") {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Choose the base unit used for logging. Serving-based foods keep the values you enter for one serving.")
                                .font(.footnote)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Picker("Base unit", selection: $baseUnit) {
                                Text("g").tag(FoodAmountUnit.grams)
                                Text("ml").tag(FoodAmountUnit.millilitres)
                                Text("serving").tag(FoodAmountUnit.serving)
                            }
                            .pickerStyle(.segmented)

                            NutritionTextField(
                                title: "Serving size",
                                text: $servingSize,
                                placeholder: "Optional",
                                suffix: baseUnit == .millilitres ? "ml" : "g",
                                keyboardType: .decimalPad
                            )
                        }
                    }
                }

                DashboardSection(title: macroSectionTitle) {
                    FitnessCard {
                        VStack(spacing: 14) {
                            NutritionTextField(title: "Calories", text: $calories, placeholder: "106", suffix: "kcal", keyboardType: .decimalPad)
                            NutritionTextField(title: "Protein", text: $protein, placeholder: "24", suffix: "g", keyboardType: .decimalPad)
                            NutritionTextField(title: "Carbs", text: $carbs, placeholder: "0", suffix: "g", keyboardType: .decimalPad)
                            NutritionTextField(title: "Fat", text: $fat, placeholder: "1.2", suffix: "g", keyboardType: .decimalPad)
                        }
                    }
                }

                DashboardSection(title: "Optional Details") {
                    FitnessCard {
                        VStack(spacing: 14) {
                            NutritionTextField(title: "Sugar", text: $sugar, placeholder: "Optional", suffix: "g", keyboardType: .decimalPad)
                            NutritionTextField(title: "Fibre", text: $fibre, placeholder: "Optional", suffix: "g", keyboardType: .decimalPad)
                            NutritionTextField(title: "Salt", text: $salt, placeholder: "Optional", suffix: "g", keyboardType: .decimalPad)
                        }
                    }
                }

                if let validationWarning {
                    NutritionNoticeCard(message: validationWarning, systemImage: "exclamationmark.triangle", tone: .warning)
                }

                if let errorText {
                    NutritionNoticeCard(message: errorText, systemImage: "exclamationmark.triangle", tone: .danger)
                }

                Button {
                    save()
                } label: {
                    Label(food == nil ? "Save Food" : "Update Food", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
            .navigationTitle(food == nil ? "Manual Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var macroSectionTitle: String {
        switch baseUnit {
        case .grams:
            return "Macros per 100g"
        case .millilitres:
            return "Macros per 100ml"
        case .serving:
            return "Macros per serving"
        }
    }

    private var validationWarning: String? {
        guard let values = parsedValues else { return nil }
        return NutritionDataIntegrityService().per100NutritionWarning(
            calories: values.calories,
            protein: values.protein,
            carbs: values.carbs,
            fat: values.fat,
            sugar: values.sugar,
            fibre: values.fibre,
            salt: values.salt,
            baseUnit: baseUnit
        )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorText = "Enter a food name."
            return
        }

        guard let values = parsedValues else {
            errorText = "Nutrition values must be zero or positive numbers."
            return
        }

        guard values.hasNutrition else {
            errorText = "Add at least one calorie or macro value."
            return
        }

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now

        if let food {
            food.name = trimmedName
            food.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            food.servingSize = values.servingSize
            food.baseUnit = baseUnit
            food.caloriesPer100g = values.calories
            food.proteinPer100g = values.protein
            food.carbsPer100g = values.carbs
            food.fatPer100g = values.fat
            food.sugarPer100g = values.sugar
            food.fibrePer100g = values.fibre
            food.saltPer100g = values.salt
            food.source = .manual
            food.verificationStatus = .edited
            food.updatedAt = now
        } else {
            modelContext.insert(
                FoodItem(
                    name: trimmedName,
                    brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
                    servingSize: values.servingSize,
                    baseUnit: baseUnit,
                    caloriesPer100g: values.calories,
                    proteinPer100g: values.protein,
                    carbsPer100g: values.carbs,
                    fatPer100g: values.fat,
                    sugarPer100g: values.sugar,
                    fibrePer100g: values.fibre,
                    saltPer100g: values.salt,
                    source: .manual,
                    verificationStatus: .userVerified,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try? modelContext.save()
        AppHaptics.success()
        dismiss()
    }

    private var parsedValues: ParsedFoodValues? {
        guard
            let servingSize = parseOptionalNonNegative(servingSize),
            let calories = parseOptionalNonNegative(calories),
            let protein = parseOptionalNonNegative(protein),
            let carbs = parseOptionalNonNegative(carbs),
            let fat = parseOptionalNonNegative(fat),
            let sugar = parseOptionalNonNegative(sugar),
            let fibre = parseOptionalNonNegative(fibre),
            let salt = parseOptionalNonNegative(salt)
        else {
            return nil
        }

        return ParsedFoodValues(
            servingSize: servingSize,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            sugar: sugar,
            fibre: fibre,
            salt: salt
        )
    }

    private func parseOptionalNonNegative(_ text: String) -> Double?? {
        NutritionDataIntegrityService.parseOptionalNonNegative(text)
    }

    private static func fieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct LogFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let food: FoodItem

    @State private var consumedAmount: String
    @State private var amountUnit: FoodAmountUnit
    @State private var mealType: MealType = .lunch
    @State private var notes = ""
    @State private var errorText: String?

    private let calculator = NutritionCalculatorService()

    init(food: FoodItem) {
        self.food = food
        _consumedAmount = State(initialValue: Self.defaultAmountText(for: food))
        _amountUnit = State(initialValue: food.baseUnit)
    }

    private var parsedAmount: Double? {
        let normalized = consumedAmount
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var preview: NutritionMacroSnapshot {
        calculator.calculate(for: food, consumedAmount: max(parsedAmount ?? 0, 0), unit: amountUnit)
    }

    var body: some View {
        FitnessScreen(
            title: "Log Food",
            subtitle: "Choose amount, meal, and confirm the snapshot.",
            systemImage: "plus.forwardslash.minus"
        ) {
            SelectedFoodSummaryCard(food: food)

            DashboardSection(title: "Quantity") {
                FitnessCard {
                    VStack(spacing: 14) {
                        NutritionTextField(
                            title: "Consumed",
                            text: $consumedAmount,
                            placeholder: "150",
                            suffix: amountUnit.shortName,
                            keyboardType: .decimalPad
                        )

                        Picker("Unit", selection: $amountUnit) {
                            Text("g").tag(FoodAmountUnit.grams)
                            Text("ml").tag(FoodAmountUnit.millilitres)
                            Text("serving").tag(FoodAmountUnit.serving)
                        }
                        .pickerStyle(.segmented)

                        MealTypePicker(selectedMeal: $mealType)

                        NutritionTextField(title: "Notes", text: $notes, placeholder: "Optional")
                    }
                }
            }

            DashboardSection(title: "Calculated Snapshot") {
                MacroSummaryGrid(totals: preview)
            }

            if amountUnit == .serving && food.baseUnit != .serving && food.servingSize == nil {
                NutritionNoticeCard(
                    message: "Serving logs use 100g unless this food has a serving size.",
                    systemImage: "info.circle",
                    tone: .neutral
                )
            }

            if let errorText {
                NutritionNoticeCard(message: errorText, systemImage: "exclamationmark.triangle", tone: .danger)
            }

            Button {
                logFood()
            } label: {
                Label("Log Food", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
        }
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logFood() {
        guard let amount = parsedAmount, amount > 0 else {
            errorText = "Consumed amount must be greater than zero."
            return
        }

        let snapshot = calculator.calculate(for: food, consumedAmount: amount, unit: amountUnit)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now

        let entry = FoodLogEntry(
            foodItemId: food.id,
            foodNameSnapshot: food.name,
            brandSnapshot: food.brand,
            consumedAmount: amount,
            amountUnit: amountUnit,
            mealType: mealType,
            caloriesSnapshot: snapshot.calories,
            proteinSnapshot: snapshot.protein,
            carbsSnapshot: snapshot.carbs,
            fatSnapshot: snapshot.fat,
            sugarSnapshot: snapshot.sugar,
            fibreSnapshot: snapshot.fibre,
            saltSnapshot: snapshot.salt,
            loggedAt: now,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(entry)
        try? modelContext.save()
        AppHaptics.success()

        let healthPreferences = HealthKitPreferenceStore().load()
        if healthPreferences.isHealthKitEnabled,
           healthPreferences.writeNutritionToHealthKit,
           healthPreferences.autoSyncNewFoodLogs {
            let foodID = food.id
            let entrySnapshot = HealthKitFoodLogSyncSnapshot(entry: entry)
            let foodSnapshot = HealthKitFoodItemSyncSnapshot(food: food)
            let syncPreferences = healthPreferences
            PerformanceTracer.mark(.healthKitNutritionBridge, "auto_sync snapshots_ready entries=1")
            Task {
                PerformanceTracer.mark(.healthKitNutritionBridge, "auto_sync task_begin")
                _ = await NutritionHealthKitBridge().sync(entries: [entrySnapshot], foodItemsById: [foodID: foodSnapshot], preferences: syncPreferences)
                PerformanceTracer.mark(.healthKitNutritionBridge, "auto_sync task_end")
            }
        }

        dismiss()
    }

    private static func defaultAmountText(for food: FoodItem) -> String {
        if food.baseUnit == .serving {
            return "1"
        }

        return (food.servingSize ?? 100).formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct ParsedFoodValues {
    let servingSize: Double?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let sugar: Double?
    let fibre: Double?
    let salt: Double?

    var hasNutrition: Bool {
        [calories, protein, carbs, fat, sugar, fibre, salt].compactMap { $0 }.contains { $0 > 0 }
    }
}

private struct NutritionHeroCard: View {
    @Environment(\.appTheme) private var appTheme

    let totals: NutritionMacroSnapshot
    let entryCount: Int

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Today's Intake")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(kcalText(totals.calories))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            Text("kcal")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }

                    Spacer(minLength: 12)

                    FitnessIconBadge(systemImage: "flame.fill", size: 54)
                }

                Text(heroMessage)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    NutritionMiniMacroPill(label: "Protein", value: "\(gramsText(totals.protein))g", systemImage: "bolt.heart.fill")
                    NutritionMiniMacroPill(label: "Carbs", value: "\(gramsText(totals.carbs))g", systemImage: "leaf.fill")
                    NutritionMiniMacroPill(label: "Fat", value: "\(gramsText(totals.fat))g", systemImage: "drop.fill")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's intake, \(kcalText(totals.calories)) calories, \(gramsText(totals.protein)) grams protein")
    }

    private var heroMessage: String {
        if entryCount == 0 {
            return "Log a meal to connect today's food with your training."
        }

        if totals.protein >= 100 {
            return "Protein is building nicely today. Keep the rest of the day consistent."
        }

        return "Protein is the clearest lever for recovery. Keep it visible as you log meals."
    }
}

private struct MacroSummaryGrid: View {
    let totals: NutritionMacroSnapshot

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            NutritionMetricCard(label: "Calories", value: kcalText(totals.calories), caption: "kcal logged", systemImage: "flame.fill")
            NutritionMetricCard(label: "Protein", value: "\(gramsText(totals.protein))g", caption: "recovery focus", systemImage: "bolt.heart.fill")
            NutritionMetricCard(label: "Carbs", value: "\(gramsText(totals.carbs))g", caption: "training fuel", systemImage: "leaf.fill")
            NutritionMetricCard(label: "Fibre", value: "\(gramsText(totals.fibre ?? 0))g", caption: "daily target", systemImage: "chart.bar.fill")
        }
    }
}

private struct NutritionMetricCard: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        FitnessCard(style: .compact, padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)

                    Spacer()
                }

                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)

                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(caption)")
    }
}

private struct MealSectionCard: View {
    @Environment(\.appTheme) private var appTheme

    let mealType: MealType
    let entries: [FoodLogEntry]
    let shouldShowHealthKitStatus: Bool
    let syncRecordsByEntryId: [UUID: HealthKitFoodLogSyncRecord]
    let requestDelete: (FoodLogEntry) -> Void

    private let calculator = NutritionCalculatorService()

    private var totals: NutritionMacroSnapshot {
        calculator.totals(from: entries)
    }

    var body: some View {
        FitnessCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: mealType.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 36, height: 36)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mealType.displayName)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(entries.count) item\(entries.count == 1 ? "" : "s") - P \(gramsText(totals.protein))g C \(gramsText(totals.carbs))g F \(gramsText(totals.fat))g")
                            .font(.caption)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 8)

                    Text("\(kcalText(totals.calories)) kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appTheme.colors.accent)
                        .lineLimit(1)
                }

                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        FoodLogRow(
                            entry: entry,
                            shouldShowHealthKitStatus: shouldShowHealthKitStatus,
                            syncRecord: syncRecordsByEntryId[entry.id],
                            requestDelete: { requestDelete(entry) }
                        )
                    }
                }
            }
        }
    }
}

private struct FoodLogRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: FoodLogEntry
    let shouldShowHealthKitStatus: Bool
    let syncRecord: HealthKitFoodLogSyncRecord?
    let requestDelete: () -> Void

    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .padding(.trailing, appTheme.metrics.swipeRevealActionTrailingPadding)
                .opacity(deleteRevealProgress)

            rowContent
                .offset(x: visibleOffset)
                .gesture(swipeGesture)
                .onTapGesture {
                    guard horizontalOffset != 0 else { return }
                    closeSwipe()
                }
        }
        .contextMenu {
            Button(role: .destructive) {
                AppHaptics.selection()
                requestDelete()
            } label: {
                Label("Remove Log", systemImage: "trash")
            }
        }
        .accessibilityAction(named: "Remove Log", requestDelete)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.foodNameSnapshot)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("\(amountText) - P \(gramsText(entry.proteinSnapshot))g C \(gramsText(entry.carbsSnapshot))g F \(gramsText(entry.fatSnapshot))g")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if shouldShowHealthKitStatus {
                    HealthKitSyncStatusBadge(status: syncRecord?.status ?? .pending)
                }
            }

            Spacer(minLength: 8)

            Text(kcalText(entry.caloriesSnapshot))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, appTheme.metrics.spacing12)
        .padding(.vertical, appTheme.metrics.spacing10)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous))
        .contentShape(Rectangle())
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            AppHaptics.selection()
            requestDelete()
        } label: {
            Image(systemName: "trash")
                .font(AppTypography.cardTitle)
                .frame(width: appTheme.metrics.swipeRevealActionSize, height: appTheme.metrics.swipeRevealActionSize)
                .foregroundStyle(.white)
                .background(appTheme.colors.danger, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(entry.foodNameSnapshot) log")
    }

    private var amountText: String {
        "\(entry.consumedAmount.formatted(.number.precision(.fractionLength(0...1)))) \(entry.amountUnit.shortName)"
    }

    private var visibleOffset: CGFloat {
        clampedOffset(horizontalOffset + dragTranslation)
    }

    private var deleteRevealWidth: CGFloat {
        appTheme.metrics.swipeRevealWidth
    }

    private var deleteRevealProgress: CGFloat {
        min(1, abs(visibleOffset) / deleteRevealWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    closeSwipe()
                    return
                }

                let projectedOffset = horizontalOffset + value.predictedEndTranslation.width
                let shouldOpen = projectedOffset < -(deleteRevealWidth * 0.45) || value.translation.width < -36

                withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
                    horizontalOffset = shouldOpen ? -deleteRevealWidth : 0
                }
            }
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-deleteRevealWidth, offset))
    }

    private func closeSwipe() {
        withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
            horizontalOffset = 0
        }
    }
}

private struct SavedFoodCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let food: FoodItem
    let edit: () -> Void
    let delete: () -> Void

    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .padding(.trailing, appTheme.metrics.swipeRevealActionTrailingPadding)
                .opacity(deleteRevealProgress)

            cardContent
                .offset(x: visibleOffset)
                .gesture(swipeGesture)
                .onTapGesture {
                    guard horizontalOffset != 0 else { return }
                    closeSwipe()
                }
        }
    }

    private var cardContent: some View {
        FitnessCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    NutritionFoodIcon(systemImage: "fork.knife")

                    VStack(alignment: .leading, spacing: 7) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(food.name)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.84)

                            if let brand = food.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 6) {
                            FoodSourceBadge(source: food.source)
                            VerificationStatusBadge(status: food.verificationStatus)
                        }
                    }

                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    NutritionMacroChip(title: "kcal", value: kcalText(food.caloriesPer100g ?? 0))
                    NutritionMacroChip(title: "P", value: "\(gramsText(food.proteinPer100g ?? 0))g")
                    NutritionMacroChip(title: "C", value: "\(gramsText(food.carbsPer100g ?? 0))g")
                    NutritionMacroChip(title: "F", value: "\(gramsText(food.fatPer100g ?? 0))g")
                }

                HStack(spacing: 8) {
                    NavigationLink {
                        LogFoodView(food: food)
                    } label: {
                        Label("Log", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())

                    Button(action: edit) {
                        Image(systemName: "pencil")
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .background(appTheme.colors.cardBackgroundElevated, in: Circle())
                    .accessibilityLabel("Edit \(food.name)")
                }
            }
        }
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            AppHaptics.warning()
            delete()
        } label: {
            Image(systemName: "trash")
                .font(AppTypography.cardTitle)
                .frame(width: appTheme.metrics.swipeRevealActionSize, height: appTheme.metrics.swipeRevealActionSize)
                .foregroundStyle(.white)
                .background(appTheme.colors.danger, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete \(food.name)")
    }

    private var visibleOffset: CGFloat {
        clampedOffset(horizontalOffset + dragTranslation)
    }

    private var deleteRevealWidth: CGFloat {
        appTheme.metrics.swipeRevealWidth
    }

    private var deleteRevealProgress: CGFloat {
        min(1, abs(visibleOffset) / deleteRevealWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    closeSwipe()
                    return
                }

                let projectedOffset = horizontalOffset + value.predictedEndTranslation.width
                let shouldOpen = projectedOffset < -(deleteRevealWidth * 0.45) || value.translation.width < -36

                withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
                    horizontalOffset = shouldOpen ? -deleteRevealWidth : 0
                }
            }
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-deleteRevealWidth, offset))
    }

    private func closeSwipe() {
        withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
            horizontalOffset = 0
        }
    }
}

private struct FoodDatabaseSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let foodCount: Int

    var body: some View {
        FitnessCard {
            HStack(spacing: 12) {
                NutritionFoodIcon(systemImage: "checkmark.seal.fill")

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(foodCount) saved food\(foodCount == 1 ? "" : "s")")
                        .font(.title3.bold())
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Local foods are the source of truth. Imported and scanned foods will be reviewed before saving in later phases.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SelectedFoodSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let food: FoodItem

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    NutritionFoodIcon(systemImage: "fork.knife")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name)
                            .font(.title3.bold())
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)

                        Text(food.brand?.isEmpty == false ? food.brand ?? "" : "Saved local food")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    FoodSourceBadge(source: food.source)
                    VerificationStatusBadge(status: food.verificationStatus)
                }
            }
        }
    }
}

private struct ManualFoodTrustCard: View {
    @Environment(\.appTheme) private var appTheme

    let isEditing: Bool

    var body: some View {
        FitnessCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.doc.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 38, height: 38)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(isEditing ? "Editing local data" : "Manual and verified")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Saved values are reused for future logs. Existing food logs keep their original macro snapshots.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct QuickLogFoodCard: View {
    let food: FoodItem

    var body: some View {
        DashboardActionTile(
            title: food.name,
            subtitle: "\(kcalText(food.caloriesPer100g ?? 0)) kcal - \(gramsText(food.proteinPer100g ?? 0))g protein",
            systemImage: "fork.knife",
            showsChevron: false,
            width: 168,
            iconSize: 42
        )
    }
}

private struct NutritionActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        DashboardActionTile(title: title, subtitle: subtitle, systemImage: systemImage)
    }
}

private struct NutritionHubActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let status: String
    let isEnabled: Bool

    var body: some View {
        DashboardActionTile(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            status: status,
            isEnabled: isEnabled,
            layout: .horizontal
        )
    }
}

private struct NutritionEmptyState: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                FitnessIconBadge(systemImage: systemImage, size: 48)

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
                        .padding(.top, 2)
                }
            }
        }
    }
}

private struct NutritionSearchField: View {
    @Environment(\.appTheme) private var appTheme

    @Binding var searchText: String

    var body: some View {
        FitnessCard(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(appTheme.colors.textTertiary)

                TextField("Search foods or brands", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(appTheme.colors.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(appTheme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }
}

private struct MealTypePicker: View {
    @Environment(\.appTheme) private var appTheme

    @Binding var selectedMeal: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealType.allCases) { mealType in
                        FilterChip(
                            mealType.displayName,
                            systemImage: mealType.systemImage,
                            isSelected: selectedMeal == mealType
                        ) {
                            selectedMeal = mealType
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
    }
}

private struct NutritionMiniMacroPill: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
    }
}

private struct NutritionMacroChip: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FoodSourceBadge: View {
    @Environment(\.appTheme) private var appTheme

    let source: FoodDataSource

    var body: some View {
        Text(source.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(appTheme.colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(appTheme.colors.accentSurface, in: Capsule())
            .lineLimit(1)
    }
}

private struct VerificationStatusBadge: View {
    @Environment(\.appTheme) private var appTheme

    let status: FoodVerificationStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == .userVerified ? appTheme.colors.success : appTheme.colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(status == .userVerified ? appTheme.colors.success.opacity(0.14) : appTheme.colors.cardBackgroundElevated, in: Capsule())
            .lineLimit(1)
    }
}

private struct NutritionFoodIcon: View {
    let systemImage: String

    var body: some View {
        FitnessIconBadge(systemImage: systemImage, size: 42)
    }
}

private enum NutritionNoticeTone {
    case neutral
    case warning
    case danger
}

private struct NutritionNoticeCard: View {
    @Environment(\.appTheme) private var appTheme

    let message: String
    let systemImage: String
    let tone: NutritionNoticeTone

    var body: some View {
        FitnessCard(padding: 16) {
            Label(message, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return appTheme.colors.textSecondary
        case .warning:
            return appTheme.colors.warning
        case .danger:
            return appTheme.colors.danger
        }
    }
}

private struct NutritionTextField: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    @Binding var text: String
    let placeholder: String
    var suffix: String?
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(keyboardType == .default ? .words : .never)
                    .foregroundStyle(appTheme.colors.textPrimary)

                if let suffix {
                    Text(suffix)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
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

private func kcalText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}

private func gramsText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(value < 10 && value != 0 ? 1 : 0)))
}
