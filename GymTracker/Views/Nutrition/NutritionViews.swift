import SwiftData
import SwiftUI

struct DeferredNutritionDashboardHost: View {
    let initialPayload: NutritionDashboardWarmStartPayload?

    @State private var isLiveMounted = false
    @State private var isVisible = false

    private var totals: NutritionMacroSnapshot {
        initialPayload?.totals
            ?? NutritionMacroSnapshot(
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                sugar: nil,
                fibre: nil,
                salt: nil
            )
    }

    var body: some View {
        Group {
            if isLiveMounted {
                NutritionDashboardView()
            } else {
                FitnessScreen(title: nil) {
                    NutritionHeroCard(
                        totals: totals,
                        entryCount: initialPayload?.dayEntries.count ?? 0,
                        isToday: true
                    )
                    .accessibilityIdentifier("nutrition-hero")

                    DashboardSection(title: "Coach Context") {
                        ReadinessContextCard(
                            readiness: initialPayload?.readiness
                                ?? CoachIntelligenceService.emptySnapshot().readiness,
                            focus: .nutrition,
                            title: "Nutrition in today's readiness"
                        )
                    }

                    DashboardSection(title: "Macros") {
                        MacroSummaryGrid(totals: totals)
                    }
                }
                .navigationTitle("Nutrition")
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("nutrition-screen")
            }
        }
        .onAppear {
            isVisible = true
            guard !isLiveMounted else { return }
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    guard isVisible else { return }
                    isLiveMounted = true
                }
            }
        }
        .onDisappear { isVisible = false }
    }
}

struct NutritionDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared

    @Query
    private var foodItems: [FoodItem]

    @Query
    private var logEntries: [FoodLogEntry]

    @Query
    private var completedSessions: [WorkoutSession]

    @State private var healthPreferences = HealthKitPreferenceStore().load()
    @State private var nutritionGoal = NutritionGoalService().loadGoal()
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private let calculator = NutritionCalculatorService()
    private let nutritionGoalStore = NutritionGoalService()
    @State private var pendingDeleteLogEntryID: UUID?
    @State private var dashboardSnapshot = NutritionDashboardSnapshot.empty
    @State private var lastDashboardSignature: String?
    @State private var selectedRoute: NutritionRoute?
    @State private var activeFoodLogSwipeID: UUID?
    @State private var didRequestInitialRefresh = false
    @State private var isPreparingInitialSnapshot = true
    @State private var dashboardRefreshTask: Task<Void, Never>?

    init() {
        _foodItems = Query(Self.foodItemsDescriptor)
        _logEntries = Query(Self.logEntriesDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        if let warm = NutritionWarmStartStore.shared.dashboard {
            _dashboardSnapshot = State(initialValue: NutritionDashboardSnapshot(warm))
            _selectedDate = State(initialValue: warm.selectedDate)
            _isPreparingInitialSnapshot = State(initialValue: false)
        }
    }

    private static var foodItemsDescriptor: FetchDescriptor<FoodItem> {
        var descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        descriptor.fetchLimit = 180
        return descriptor
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

    private var currentDashboardSnapshot: NutritionDashboardSnapshot {
        dashboardSnapshot
    }

    private var dashboardSignature: String {
        let foodItemsSignature = foodItems.prefix(180).map(foodItemSignature).joined(separator: ",")
        let logEntriesSignature = logEntries.prefix(160).map(foodLogEntrySignature).joined(separator: ",")
        let workoutsSignature = completedSessions.prefix(40).map(workoutSignature).joined(separator: ",")
        let nutritionGoalSignature = String(nutritionGoal.updatedAt.timeIntervalSince1970)
        let healthKitSignature = healthPreferences.isHealthKitEnabled ? "healthkit-on" : "healthkit-off"
        let parts: [String] = [
            foodItemsSignature,
            logEntriesSignature,
            workoutsSignature,
            nutritionGoalSignature,
            healthKitSignature,
            String(selectedDate.timeIntervalSince1970),
            readinessRefreshClock.token.signature
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

    private func refreshDashboardSnapshot(force: Bool = false) {
        let signature = dashboardSignature
        guard force || signature != lastDashboardSignature else {
            isPreparingInitialSnapshot = false
            return
        }
        let nextSnapshot = PerformanceTracer.trace(.nutritionDashboardSnapshot) {
            makeDashboardSnapshot()
        }
        AppMotion.withoutAnimation {
            dashboardSnapshot = nextSnapshot
            lastDashboardSignature = signature
            isPreparingInitialSnapshot = false
        }
    }

    private func makeDashboardSnapshot() -> NutritionDashboardSnapshot {
        let dayEntries = foodLogs(on: selectedDate)
        let recentFoods = recentlyLoggedFoods(from: logEntries, foodItems: foodItems)
        let readiness = WarmRouteSnapshots.overallReadiness(fallback: CoachIntelligenceService.emptySnapshot().readiness)
        let healthKitSyncRecords = healthKitSyncRecordsByEntryId(for: dayEntries)

        return NutritionDashboardSnapshot(
            dayEntries: dayEntries.map(NutritionFoodLogSnapshot.init),
            totals: calculator.totals(from: dayEntries),
            readiness: readiness,
            recentlyLoggedFoods: recentFoods.map(SavedFoodSnapshot.init),
            mealEntries: Dictionary(grouping: dayEntries.map(NutritionFoodLogSnapshot.init), by: \.mealType),
            isTrainingDay: hasCompletedWorkout(on: selectedDate),
            shouldShowHealthKitStatus: healthPreferences.isHealthKitEnabled,
            healthKitSyncRecordsByEntryId: healthKitSyncRecords
        )
    }

    private func foodLogs(on date: Date) -> [FoodLogEntry] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return [] }
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate<FoodLogEntry> { entry in
                entry.loggedAt >= start && entry.loggedAt < end
            },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        descriptor.fetchLimit = 160
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func hasCompletedWorkout(on date: Date) -> Bool {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return false }
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.completed && session.date >= start && session.date < end
            }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
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
            if isPreparingInitialSnapshot {
                SwiftUI.ProgressView("Preparing nutrition…")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .accessibilityIdentifier("nutrition-loading")
            } else {
                NutritionDayNavigator(
                    selectedDate: $selectedDate,
                    canMoveForward: !isToday,
                    moveBackward: { moveSelectedDay(by: -1) },
                    moveForward: { moveSelectedDay(by: 1) }
                )

            NutritionHeroCard(
                totals: snapshot.totals,
                entryCount: snapshot.dayEntries.count,
                isToday: isToday
            )
            .accessibilityIdentifier("nutrition-hero")

            if isToday {
                DashboardSection(title: "Coach Context") {
                    ReadinessContextCard(
                        readiness: snapshot.readiness,
                        focus: .nutrition,
                        title: "Nutrition in today's readiness"
                    )
                }
            } else {
                DashboardSection(title: "Day Context") {
                    HistoricalNutritionContextCard(isTrainingDay: snapshot.isTrainingDay)
                }
            }

            DashboardSection(title: "Macros") {
                MacroSummaryGrid(totals: snapshot.totals)
            }

            if isToday {
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
                            navigateToSavedFoods()
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
            }

            if isToday && !snapshot.recentlyLoggedFoods.isEmpty {
                DashboardSection(title: "Quick Log") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(snapshot.recentlyLoggedFoods) { food in
                                    NavigationLink {
                                    LogFoodView(snapshot: food)
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

                DashboardSection(title: isToday ? "Today" : "Meals") {
                if snapshot.dayEntries.isEmpty {
                    if isToday {
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
                        NutritionEmptyState(
                            title: "Nothing logged",
                            message: "No food was recorded on this day.",
                            systemImage: "fork.knife.circle",
                            actionTitle: nil
                        )
                    }
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
                                    allowsDeletion: isToday,
                                    activeSwipeID: $activeFoodLogSwipeID,
                                    requestDelete: { pendingDeleteLogEntryID = $0.id }
                                )
                            }
                        }
                    }
                }
                }
            }
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("nutrition-screen")
        .navigationDestination(item: $selectedRoute) { route in
            Group {
                switch route {
                case .addFood:
                    AddFoodHubView()
                case .savedFoods(let preparedRoute):
                    FoodDatabaseView(route: preparedRoute)
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
            .onAppear {
                NavigationInteraction.destinationDidAppear(
                    key: "nutrition.\(route.analyticsName)"
                )
            }
        }
        .alert("Remove food log?", isPresented: deleteLogAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDeleteLogEntryID = nil
            }
            Button("Remove Log", role: .destructive) {
                deletePendingLogEntry()
            }
        } message: {
            Text("This removes the logged entry from your daily totals. The saved food stays in your food database.")
        }
        .onAppear {
            readinessRefreshClock.start()
            healthPreferences = HealthKitPreferenceStore().load()
            nutritionGoal = nutritionGoalStore.loadGoal()
            // Build the first snapshot on the appear turn so the pushed
            // frame is fully populated instead of a "Preparing" placeholder.
            let shouldForceRefresh = !didRequestInitialRefresh
            didRequestInitialRefresh = true
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                refreshDashboardSnapshot(force: shouldForceRefresh)
            }
        }
        .onChange(of: dashboardSignature) { _, _ in
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                refreshDashboardSnapshot()
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            selectedDate = min(
                Calendar.current.startOfDay(for: newDate),
                Calendar.current.startOfDay(for: .now)
            )
            pendingDeleteLogEntryID = nil
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                refreshDashboardSnapshot(force: true)
            }
        }
        .onDisappear {
            dashboardRefreshTask?.cancel()
        }
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func navigate(to route: NutritionRoute) {
        NavigationInteraction.perform(
            key: "nutrition.\(route.analyticsName)",
            destinationClass: route.destinationClass,
            haptic: .selection
        ) {
            selectedRoute = route
        }
    }

    private func navigateToSavedFoods() {
        let catalog = SavedFoodCatalogSnapshot(foods: foodItems.map(SavedFoodSnapshot.init))
        SavedFoodWarmStartStore.shared.update(catalog)
        guard let preparedRoute = SavedFoodWarmStartStore.shared.preparedRoute() else { return }
        navigate(to: .savedFoods(preparedRoute))
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private func moveSelectedDay(by value: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) else { return }
        selectedDate = min(
            Calendar.current.startOfDay(for: date),
            Calendar.current.startOfDay(for: .now)
        )
    }

    private var deleteLogAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteLogEntryID != nil
        } set: { isShowing in
            if !isShowing {
                pendingDeleteLogEntryID = nil
            }
        }
    }

    private func deletePendingLogEntry() {
        guard let pendingDeleteLogEntryID else { return }
        let id = pendingDeleteLogEntryID
        let descriptor = FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.id == id })
        guard let entry = try? modelContext.fetch(descriptor).first else { return }
        HealthKitSyncStateStore().removeRecord(for: id)
        modelContext.delete(entry)
        try? modelContext.save()
        AppHaptics.warning()
        self.pendingDeleteLogEntryID = nil
    }
}

private struct NutritionDayNavigator: View {
    @Environment(\.appTheme) private var appTheme

    @Binding var selectedDate: Date
    let canMoveForward: Bool
    let moveBackward: () -> Void
    let moveForward: () -> Void

    private var today: Date {
        Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        FitnessCard(style: .compact, padding: 14) {
            HStack(spacing: 10) {
                navigationButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Previous nutrition day",
                    action: moveBackward
                )

                DatePicker(
                    "Nutrition date",
                    selection: $selectedDate,
                    in: Date.distantPast...today,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("nutrition-date-picker")

                navigationButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Next nutrition day",
                    isDisabled: !canMoveForward,
                    action: moveForward
                )
            }
        }
    }

    private func navigationButton(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                .background(
                    appTheme.elevatedCardBackground,
                    in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous)
                        .stroke(appTheme.colors.cardBorder.opacity(0.56), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? appTheme.colors.textTertiary : appTheme.colors.textPrimary)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HistoricalNutritionContextCard: View {
    @Environment(\.appTheme) private var appTheme

    let isTrainingDay: Bool

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(spacing: 14) {
                FitnessIconBadge(
                    systemImage: isTrainingDay ? "figure.strengthtraining.traditional" : "moon.zzz.fill",
                    size: 44
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(isTrainingDay ? "Training Day" : "Rest Day")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(
                        isTrainingDay
                            ? "A completed workout was logged on this date."
                            : "No completed workout was logged on this date."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

fileprivate enum NutritionRoute: Hashable, Identifiable {
    case addFood
    case savedFoods(SavedFoodPreparedRoute)
    case insights
    case targets
    case barcode
    case labelScan

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .addFood: return "add-food"
        case .savedFoods: return "saved-foods"
        case .insights: return "insights"
        case .targets: return "targets"
        case .barcode: return "barcode"
        case .labelScan: return "label-scan"
        }
    }

    var destinationClass: NavigationDestinationClass {
        switch self {
        case .addFood, .savedFoods, .targets:
            return .warm
        case .insights, .barcode, .labelScan:
            return .deep
        }
    }
}

private struct NutritionDashboardSnapshot {
    var dayEntries: [NutritionFoodLogSnapshot]
    var totals: NutritionMacroSnapshot
    var readiness: ReadinessScore
    var recentlyLoggedFoods: [SavedFoodSnapshot]
    var mealEntries: [MealType: [NutritionFoodLogSnapshot]]
    var isTrainingDay: Bool
    var shouldShowHealthKitStatus: Bool
    var healthKitSyncRecordsByEntryId: [UUID: HealthKitFoodLogSyncRecord]

    init(
        dayEntries: [NutritionFoodLogSnapshot],
        totals: NutritionMacroSnapshot,
        readiness: ReadinessScore,
        recentlyLoggedFoods: [SavedFoodSnapshot],
        mealEntries: [MealType: [NutritionFoodLogSnapshot]],
        isTrainingDay: Bool,
        shouldShowHealthKitStatus: Bool,
        healthKitSyncRecordsByEntryId: [UUID: HealthKitFoodLogSyncRecord]
    ) {
        self.dayEntries = dayEntries
        self.totals = totals
        self.readiness = readiness
        self.recentlyLoggedFoods = recentlyLoggedFoods
        self.mealEntries = mealEntries
        self.isTrainingDay = isTrainingDay
        self.shouldShowHealthKitStatus = shouldShowHealthKitStatus
        self.healthKitSyncRecordsByEntryId = healthKitSyncRecordsByEntryId
    }

    static let empty = NutritionDashboardSnapshot(
        dayEntries: [],
        totals: NutritionMacroSnapshot(calories: 0, protein: 0, carbs: 0, fat: 0, sugar: nil, fibre: nil, salt: nil),
        readiness: CoachIntelligenceService.emptySnapshot().readiness,
        recentlyLoggedFoods: [],
        mealEntries: [:],
        isTrainingDay: false,
        shouldShowHealthKitStatus: false,
        healthKitSyncRecordsByEntryId: [:]
    )

    init(_ payload: NutritionDashboardWarmStartPayload) {
        dayEntries = payload.dayEntries
        totals = payload.totals
        readiness = payload.readiness
        recentlyLoggedFoods = payload.recentlyLoggedFoods
        mealEntries = payload.mealEntries
        isTrainingDay = payload.isTrainingDay
        shouldShowHealthKitStatus = payload.shouldShowHealthKitStatus
        healthKitSyncRecordsByEntryId = payload.healthKitSyncRecordsByEntryId
    }
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
            Group {
                switch route {
                case .barcode:
                    BarcodeScannerView()
                case .labelScan:
                    NutritionLabelScanView()
                case .savedFoods(let preparedRoute):
                    FoodDatabaseView(route: preparedRoute)
                }
            }
            .onAppear {
                NavigationInteraction.destinationDidAppear(
                    key: "add-food.\(route.analyticsName)"
                )
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
            navigateToSavedFoods()
        } label: {
            savedFoodsActionCard
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private func navigate(to route: AddFoodHubRoute) {
        NavigationInteraction.perform(
            key: "add-food.\(route.analyticsName)",
            destinationClass: .deep,
            haptic: .selection
        ) {
            selectedRoute = route
        }
    }

    private func navigateToSavedFoods() {
        let catalog = SavedFoodCatalogSnapshot(foods: foodItems.map(SavedFoodSnapshot.init))
        SavedFoodWarmStartStore.shared.update(catalog)
        guard let preparedRoute = SavedFoodWarmStartStore.shared.preparedRoute() else { return }
        navigate(to: .savedFoods(preparedRoute))
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
            subtitle: "Read a nutrition table from a photo or screenshot, then confirm values.",
            systemImage: "text.viewfinder",
            status: "On-device OCR",
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
    case savedFoods(SavedFoodPreparedRoute)

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .barcode: return "barcode"
        case .labelScan: return "label-scan"
        case .savedFoods: return "saved-foods"
        }
    }
}

struct FoodDatabaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var catalog: SavedFoodCatalogSnapshot
    @State private var searchText = ""
    @State private var showingManualEntry = false
    @State private var editingFood: SavedFoodSnapshot?
    @State private var pendingDelete: SavedFoodSnapshot?

    init(route: SavedFoodPreparedRoute) {
        let prepared = SavedFoodWarmStartStore.shared.snapshot(for: route)
            ?? .empty
        _catalog = State(initialValue: prepared)
    }

    var body: some View {
        let visibleFoods = catalog.filtered(by: searchText)

        List {
            FoodDatabaseSummaryCard(foodCount: catalog.foods.count)
                .savedFoodsListRowStyle(rowInsets(top: appTheme.metrics.screenPadding, bottom: appTheme.metrics.screenContentSpacing))

            Button {
                showingManualEntry = true
            } label: {
                Label("Create Manual Food", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
            .savedFoodsListRowStyle(rowInsets(bottom: appTheme.metrics.screenContentSpacing))

            NutritionSearchField(searchText: $searchText)
                .savedFoodsListRowStyle(rowInsets(bottom: appTheme.metrics.screenContentSpacing))

            if visibleFoods.isEmpty {
                Button {
                    if catalog.foods.isEmpty {
                        showingManualEntry = true
                    }
                } label: {
                    NutritionEmptyState(
                        title: catalog.foods.isEmpty ? "No saved foods yet" : "No matching foods",
                        message: catalog.foods.isEmpty
                            ? "Create your first manual food so it can be logged again in seconds."
                            : "Try another food or brand name.",
                        systemImage: catalog.foods.isEmpty ? "tray" : "magnifyingglass",
                        actionTitle: catalog.foods.isEmpty ? "Create Food" : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(!catalog.foods.isEmpty)
                .savedFoodsListRowStyle(rowInsets(bottom: appTheme.metrics.screenBottomPadding))
            } else {
                ForEach(visibleFoods) { food in
                    let isLastFood = food.id == visibleFoods.last?.id

                    SavedFoodCard(
                        food: food,
                        edit: { editingFood = food },
                        delete: { pendingDelete = food }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            AppHaptics.warning()
                            pendingDelete = food
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(appTheme.colors.danger)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("saved-food-row-\(food.name)")
                    .savedFoodsListRowStyle(rowInsets(bottom: isLastFood ? appTheme.metrics.screenBottomPadding : 12))
                }
            }
        }
        .listStyle(.plain)
        .peaklineGroupedContent()
        .navigationTitle("Saved Foods")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodEntryView(onSave: applySavedFood)
        }
        .sheet(item: $editingFood) { food in
            ManualFoodEntryView(foodSnapshot: food, onSave: applySavedFood)
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

    private func rowInsets(top: CGFloat = 0, bottom: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(
            top: top,
            leading: appTheme.metrics.screenPadding,
            bottom: bottom,
            trailing: appTheme.metrics.screenPadding
        )
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
        let foodID = pendingDelete.id
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { $0.id == foodID }
        )
        guard let food = try? modelContext.fetch(descriptor).first else {
            self.pendingDelete = nil
            return
        }
        modelContext.delete(food)
        do {
            try modelContext.save()
            catalog = catalog.removing(id: foodID)
            SavedFoodWarmStartStore.shared.remove(id: foodID)
            AppHaptics.warning()
            self.pendingDelete = nil
        } catch {
            AppHaptics.error()
        }
    }

    private func applySavedFood(_ food: SavedFoodSnapshot) {
        catalog = catalog.upserting(food)
        SavedFoodWarmStartStore.shared.update(catalog)
    }
}

private extension View {
    func savedFoodsListRowStyle(_ insets: EdgeInsets) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct ManualFoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    private let foodSnapshot: SavedFoodSnapshot?
    private let onSave: ((SavedFoodSnapshot) -> Void)?

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

    init(food: FoodItem? = nil, onSave: ((SavedFoodSnapshot) -> Void)? = nil) {
        self.init(foodSnapshot: food.map(SavedFoodSnapshot.init), onSave: onSave)
    }

    init(foodSnapshot: SavedFoodSnapshot?, onSave: ((SavedFoodSnapshot) -> Void)? = nil) {
        self.foodSnapshot = foodSnapshot
        self.onSave = onSave
        _name = State(initialValue: foodSnapshot?.name ?? "")
        _brand = State(initialValue: foodSnapshot?.brand ?? "")
        _servingSize = State(initialValue: Self.fieldText(foodSnapshot?.servingSize))
        _baseUnit = State(initialValue: foodSnapshot?.baseUnit ?? .grams)
        _calories = State(initialValue: Self.fieldText(foodSnapshot?.caloriesPer100g))
        _protein = State(initialValue: Self.fieldText(foodSnapshot?.proteinPer100g))
        _carbs = State(initialValue: Self.fieldText(foodSnapshot?.carbsPer100g))
        _fat = State(initialValue: Self.fieldText(foodSnapshot?.fatPer100g))
        _sugar = State(initialValue: Self.fieldText(foodSnapshot?.sugarPer100g))
        _fibre = State(initialValue: Self.fieldText(foodSnapshot?.fibrePer100g))
        _salt = State(initialValue: Self.fieldText(foodSnapshot?.saltPer100g))
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: foodSnapshot == nil ? "Manual Food" : "Edit Food",
                subtitle: "User-confirmed nutrition stays local and reusable.",
                systemImage: "square.and.pencil"
            ) {
                ManualFoodTrustCard(isEditing: foodSnapshot != nil)

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
                    NoticeCard(validationWarning, tone: .warning, systemImage: "exclamationmark.triangle")
                }

                if let errorText {
                    NoticeCard(errorText, tone: .danger, systemImage: "exclamationmark.triangle")
                }

                Button {
                    save()
                } label: {
                    Label(foodSnapshot == nil ? "Save Food" : "Update Food", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
            .navigationTitle(foodSnapshot == nil ? "Manual Food" : "Edit Food")
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
            return "Macros per 100 g"
        case .millilitres:
            return "Macros per 100 mL"
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

        let savedFood: FoodItem
        if let foodSnapshot {
            let foodID = foodSnapshot.id
            let descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate<FoodItem> { $0.id == foodID }
            )
            guard let food = try? modelContext.fetch(descriptor).first else {
                errorText = "This saved food is no longer available."
                return
            }
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
            savedFood = food
        } else {
            let food = FoodItem(
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
            modelContext.insert(food)
            savedFood = food
        }

        do {
            try modelContext.save()
            let snapshot = SavedFoodSnapshot(savedFood)
            SavedFoodWarmStartStore.shared.upsert(snapshot)
            onSave?(snapshot)
            AppHaptics.success()
            dismiss()
        } catch {
            AppHaptics.error()
            errorText = "Could not save this food."
        }
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

    let food: SavedFoodSnapshot

    @State private var consumedAmount: String
    @State private var amountUnit: FoodAmountUnit
    @State private var mealType: MealType = .lunch
    @State private var notes = ""
    @State private var errorText: String?

    private let calculator = NutritionCalculatorService()

    init(food: FoodItem) {
        self.init(snapshot: SavedFoodSnapshot(food))
    }

    init(snapshot: SavedFoodSnapshot) {
        food = snapshot
        _consumedAmount = State(initialValue: Self.defaultAmountText(for: snapshot))
        _amountUnit = State(initialValue: snapshot.baseUnit)
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
                NoticeCard("Serving logs use 100 g unless this food has a serving size.", tone: .neutral, systemImage: "info.circle")
            }

            if let errorText {
                NoticeCard(errorText, tone: .danger, systemImage: "exclamationmark.triangle")
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

        errorText = nil

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
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(entry)
            errorText = "Could not log this food locally. Try again."
            AppHaptics.error()
            return
        }
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

    private static func defaultAmountText(for food: SavedFoodSnapshot) -> String {
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
    let isToday: Bool

    var body: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Today's Intake")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(kcalText(totals.calories))
                                .font(AppTypography.heroMetric)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            Text("kcal")
                                .font(AppTypography.compactCardTitle)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }

                    Spacer(minLength: 12)

                    FitnessIconBadge(systemImage: "flame.fill", size: 54)
                }

                Text(heroMessage)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    PeaklineText.joinedMetadata([
                        "Protein \(gramsText(totals.protein)) g",
                        "Carbs \(gramsText(totals.carbs)) g",
                        "Fat \(gramsText(totals.fat)) g"
                    ])
                )
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isToday ? "Today's" : "Selected day") intake, \(kcalText(totals.calories)) calories, \(gramsText(totals.protein)) grams protein")
    }

    private var heroMessage: String {
        if entryCount == 0 {
            return isToday
                ? "Log a meal to connect today's food with your training."
                : "No nutrition was recorded on this day."
        }

        if !isToday {
            return "Recorded meals and macros for this day."
        }

        if totals.protein >= 100 {
            return "Protein is building nicely today. Keep the rest of the day consistent."
        }

        return "Protein is the clearest lever for recovery. Keep it visible as you log meals."
    }
}

private struct MacroSummaryGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let totals: NutritionMacroSnapshot

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            NutritionMetricCard(label: "Protein", value: "\(gramsText(totals.protein)) g", caption: "recovery focus", systemImage: "bolt.heart.fill")
            NutritionMetricCard(label: "Carbs", value: "\(gramsText(totals.carbs)) g", caption: "training fuel", systemImage: "leaf.fill")
            NutritionMetricCard(label: "Fat", value: "\(gramsText(totals.fat)) g", caption: "daily intake", systemImage: "drop.fill")
            NutritionMetricCard(label: "Fibre", value: "\(gramsText(totals.fibre ?? 0)) g", caption: "daily target", systemImage: "chart.bar.fill")
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
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textAccent)

                    Spacer()
                }

                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AppTypography.chip)
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
    let entries: [NutritionFoodLogSnapshot]
    let shouldShowHealthKitStatus: Bool
    let syncRecordsByEntryId: [UUID: HealthKitFoodLogSyncRecord]
    let allowsDeletion: Bool
    @Binding var activeSwipeID: UUID?
    let requestDelete: (NutritionFoodLogSnapshot) -> Void

    private var totals: NutritionMacroSnapshot {
        NutritionMacroSnapshot(
            calories: entries.reduce(0) { $0 + $1.caloriesSnapshot },
            protein: entries.reduce(0) { $0 + $1.proteinSnapshot },
            carbs: entries.reduce(0) { $0 + $1.carbsSnapshot },
            fat: entries.reduce(0) { $0 + $1.fatSnapshot },
            sugar: nil,
            fibre: nil,
            salt: nil
        )
    }

    var body: some View {
        FitnessCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    FitnessIconBadge(systemImage: mealType.systemImage, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mealType.displayName)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(
                            PeaklineText.joinedMetadata([
                                PeaklineText.count(entries.count, singular: "item"),
                                "P \(gramsText(totals.protein)) g",
                                "C \(gramsText(totals.carbs)) g",
                                "F \(gramsText(totals.fat)) g"
                            ])
                        )
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 8)

                    Text("\(kcalText(totals.calories)) kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appTheme.colors.textAccent)
                        .lineLimit(1)
                }

                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        FoodLogRow(
                            entry: entry,
                            shouldShowHealthKitStatus: shouldShowHealthKitStatus,
                            syncRecord: syncRecordsByEntryId[entry.id],
                            allowsDeletion: allowsDeletion,
                            activeSwipeID: $activeSwipeID,
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

    let entry: NutritionFoodLogSnapshot
    let shouldShowHealthKitStatus: Bool
    let syncRecord: HealthKitFoodLogSyncRecord?
    let allowsDeletion: Bool
    @Binding var activeSwipeID: UUID?
    let requestDelete: () -> Void

    var body: some View {
        SwipeRevealRow(
            id: entry.id,
            activeID: $activeSwipeID,
            isEnabled: allowsDeletion
        ) {
            rowContent
        } action: {
            deleteAction
        }
        .accessibilityActions {
            if allowsDeletion {
                Button("Remove Log", action: requestDelete)
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.foodNameSnapshot)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(
                    PeaklineText.joinedMetadata([
                        amountText,
                        "P \(gramsText(entry.proteinSnapshot)) g",
                        "C \(gramsText(entry.carbsSnapshot)) g",
                        "F \(gramsText(entry.fatSnapshot)) g"
                    ])
                )
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

}

private struct SavedFoodCard: View {
    @Environment(\.appTheme) private var appTheme

    let food: SavedFoodSnapshot
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        cardContent
            .accessibilityAction(named: "Delete Food") {
                delete()
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                NutritionFoodIcon(systemImage: "fork.knife")

                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)

                        if let brand = food.brand, !brand.isEmpty {
                            Text(brand)
                                .font(AppTypography.metadata)
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
                NutritionMacroChip(title: "P", value: "\(gramsText(food.proteinPer100g ?? 0)) g")
                NutritionMacroChip(title: "C", value: "\(gramsText(food.carbsPer100g ?? 0)) g")
                NutritionMacroChip(title: "F", value: "\(gramsText(food.fatPer100g ?? 0)) g")
            }

            HStack(spacing: 8) {
                NavigationLink {
                    LogFoodView(snapshot: food)
                } label: {
                    Label("Log", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .accessibilityIdentifier("log-saved-food-\(food.name)")

                Button(action: edit) {
                    Image(systemName: "pencil")
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appTheme.colors.textPrimary)
                .background(appTheme.colors.cardBackgroundElevated, in: Circle())
                .accessibilityLabel("Edit \(food.name)")
                .accessibilityIdentifier("edit-saved-food-\(food.name)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.cardBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: appTheme.metrics.radius20, style: .continuous)
                .stroke(appTheme.cardBorder.opacity(0.58), lineWidth: 1)
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
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Local foods are the source of truth. Imported and scanned foods will be reviewed before saving in later phases.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SelectedFoodSummaryCard: View {
    @Environment(\.appTheme) private var appTheme

    let food: SavedFoodSnapshot

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    NutritionFoodIcon(systemImage: "fork.knife")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)

                        Text(food.brand?.isEmpty == false ? food.brand ?? "" : "Saved local food")
                            .font(AppTypography.body)
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
                    .font(AppTypography.compactCardTitle)
                    .foregroundStyle(appTheme.colors.textAccent)
                    .frame(width: 38, height: 38)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(isEditing ? "Editing local data" : "Manual and verified")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Saved values are reused for future logs. Existing food logs keep their original macro snapshots.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct QuickLogFoodCard: View {
    let food: SavedFoodSnapshot

    var body: some View {
        DashboardActionTile(
            title: food.name,
            subtitle: "\(kcalText(food.caloriesPer100g ?? 0)) kcal · \(gramsText(food.proteinPer100g ?? 0)) g protein",
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
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle {
                    Label(actionTitle, systemImage: "arrow.right")
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textAccent)
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
                .font(AppTypography.chip)
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
                .font(AppTypography.badge)
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius14, style: .continuous))
    }
}

private struct FoodSourceBadge: View {
    let source: FoodDataSource

    var body: some View {
        StatusBadge(source.displayName, role: .accent)
    }
}

private struct VerificationStatusBadge: View {
    let status: FoodVerificationStatus

    var body: some View {
        StatusBadge(
            status.displayName,
            role: status == .userVerified ? .success : .neutral
        )
    }
}

private struct NutritionFoodIcon: View {
    let systemImage: String

    var body: some View {
        FitnessIconBadge(systemImage: systemImage, size: 42)
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
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(keyboardType == .default ? .words : .never)
                    .foregroundStyle(appTheme.colors.textPrimary)

                if let suffix {
                    Text(suffix)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius16, style: .continuous)
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
