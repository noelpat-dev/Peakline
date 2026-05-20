import SwiftData
import SwiftUI

struct NutritionDashboardView: View {
    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
    private var logEntries: [FoodLogEntry]

    private let calculator = NutritionCalculatorService()

    private var todaysEntries: [FoodLogEntry] {
        logEntries.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }

    private var totals: NutritionMacroSnapshot {
        calculator.totals(from: todaysEntries)
    }

    private var recentlyLoggedFoods: [FoodItem] {
        let recentIds = logEntries.map(\.foodItemId)
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
        FitnessScreen(title: nil) {
            DashboardHeaderView(
                dateText: todayDateText,
                title: "Nutrition",
                subtitle: "Fuel today and keep macros visible"
            )

            NutritionHeroCard(totals: totals, entryCount: todaysEntries.count)

            DashboardSection(title: "Macros") {
                MacroSummaryGrid(totals: totals)
            }

            DashboardSection(title: "Quick Actions") {
                LazyVGrid(columns: actionColumns, spacing: 12) {
                    NavigationLink {
                        AddFoodHubView()
                    } label: {
                        NutritionActionCard(
                            title: "Add Food",
                            subtitle: "Create or log local foods",
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FoodDatabaseView()
                    } label: {
                        NutritionActionCard(
                            title: "Saved Foods",
                            subtitle: "\(foodItems.count) verified local items",
                            systemImage: "tray.full.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NutritionInsightsDashboardView()
                    } label: {
                        NutritionActionCard(
                            title: "Insights",
                            subtitle: "Targets, trends, and training context",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NutritionTargetsView()
                    } label: {
                        NutritionActionCard(
                            title: "Targets",
                            subtitle: "Set calories and macro goals",
                            systemImage: "target"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !recentlyLoggedFoods.isEmpty {
                DashboardSection(title: "Quick Log") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentlyLoggedFoods) { food in
                                NavigationLink {
                                    LogFoodView(food: food)
                                } label: {
                                    QuickLogFoodCard(food: food)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollClipDisabled()
                }
            }

            DashboardSection(title: "Today") {
                if todaysEntries.isEmpty {
                    NavigationLink {
                        AddFoodHubView()
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
                    .buttonStyle(.plain)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(MealType.allCases) { mealType in
                            let entries = todaysEntries
                                .filter { $0.mealType == mealType }
                                .sorted { $0.loggedAt < $1.loggedAt }

                            if !entries.isEmpty {
                                MealSectionCard(mealType: mealType, entries: entries)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var todayDateText: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct AddFoodHubView: View {
    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @State private var showingManualEntry = false

    var body: some View {
        FitnessScreen(
            title: "Add Food",
            subtitle: "Save verified foods locally, then log them fast.",
            systemImage: "plus.circle"
        ) {
            DashboardSection(title: "Available Now") {
                LazyVStack(spacing: 12) {
                    NavigationLink {
                        BarcodeScannerView()
                    } label: {
                        NutritionHubActionCard(
                            title: "Scan Barcode",
                            subtitle: "Check saved foods first, then import nutrition data.",
                            systemImage: "barcode.viewfinder",
                            status: "Fast lookup",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NutritionLabelScanView()
                    } label: {
                        NutritionHubActionCard(
                            title: "Scan Label",
                            subtitle: "Read a nutrition label from a photo, then confirm values.",
                            systemImage: "text.viewfinder",
                            status: "OCR MVP",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)

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
                    .buttonStyle(.plain)

                    NavigationLink {
                        FoodDatabaseView()
                    } label: {
                        NutritionHubActionCard(
                            title: "Saved Foods",
                            subtitle: foodItems.isEmpty ? "Create a food first, then reuse it here." : "Log one of \(foodItems.count) local foods.",
                            systemImage: "tray.full",
                            status: "Local",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodEntryView()
        }
    }
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
                            Text("Choose the base unit used for logging. Macro values below remain per 100g or 100ml for predictable scaling.")
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
        baseUnit == .millilitres ? "Macros per 100ml" : "Macros per 100g"
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

            if amountUnit == .serving && food.servingSize == nil {
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

        let healthPreferences = HealthKitPreferenceStore().load()
        if healthPreferences.isHealthKitEnabled,
           healthPreferences.writeNutritionToHealthKit,
           healthPreferences.autoSyncNewFoodLogs {
            Task {
                _ = await NutritionHealthKitBridge().sync(entries: [entry], foodItemsById: [food.id: food], preferences: healthPreferences)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Today's Intake")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .textCase(.uppercase)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(kcalText(totals.calories))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text("kcal")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "flame.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 56, height: 56)
                    .background(appTheme.colors.accentSurface, in: Circle())
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
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(appTheme.colors.cardBackground)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(appTheme.colors.accent.opacity(0.16))
                        .frame(width: 170, height: 170)
                        .blur(radius: 36)
                        .offset(x: 54, y: -68)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(appTheme.colors.accent.opacity(0.22), lineWidth: 1)
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
            NutritionMetricCard(label: "Fat", value: "\(gramsText(totals.fat))g", caption: "daily intake", systemImage: "drop.fill")
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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(caption)")
    }
}

private struct MealSectionCard: View {
    @Environment(\.appTheme) private var appTheme

    let mealType: MealType
    let entries: [FoodLogEntry]

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
                        FoodLogRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct FoodLogRow: View {
    @Environment(\.appTheme) private var appTheme

    let entry: FoodLogEntry

    private var syncRecord: HealthKitFoodLogSyncRecord? {
        HealthKitSyncStateStore().record(for: entry.id)
    }

    private var shouldShowHealthKitStatus: Bool {
        HealthKitPreferenceStore().load().isHealthKitEnabled
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.foodNameSnapshot)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("\(amountText) - P \(gramsText(entry.proteinSnapshot))g C \(gramsText(entry.carbsSnapshot))g F \(gramsText(entry.fatSnapshot))g")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if shouldShowHealthKitStatus {
                    HealthKitSyncStatusBadge(status: syncRecord?.status ?? .pending)
                }
            }

            Spacer(minLength: 8)

            Text(kcalText(entry.caloriesSnapshot))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var amountText: String {
        "\(entry.consumedAmount.formatted(.number.precision(.fractionLength(0...1)))) \(entry.amountUnit.shortName)"
    }
}

private struct SavedFoodCard: View {
    @Environment(\.appTheme) private var appTheme

    let food: FoodItem
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
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

                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTheme.colors.danger)
                    .background(appTheme.colors.danger.opacity(0.12), in: Circle())
                    .accessibilityLabel("Delete \(food.name)")
                }
            }
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
    @Environment(\.appTheme) private var appTheme

    let food: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NutritionFoodIcon(systemImage: "fork.knife")

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text("\(kcalText(food.caloriesPer100g ?? 0)) kcal - \(gramsText(food.proteinPer100g ?? 0))g protein")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 168, height: 142, alignment: .topLeading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }
}

private struct NutritionActionCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 38, height: 38)
                    .background(appTheme.colors.accentSurface, in: Circle())

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(appTheme.colors.accent.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct NutritionHubActionCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    let status: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary)
                .frame(width: 44, height: 44)
                .background(isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isEnabled ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)

                    Text(status)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated, in: Capsule())
                        .lineLimit(1)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: isEnabled ? "chevron.right" : "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isEnabled ? appTheme.colors.cardBorder : appTheme.colors.cardBorder.opacity(0.8), lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityElement(children: .combine)
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
    @Environment(\.appTheme) private var appTheme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.accent)
            .frame(width: 42, height: 42)
            .background(appTheme.colors.accentSurface, in: Circle())
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
