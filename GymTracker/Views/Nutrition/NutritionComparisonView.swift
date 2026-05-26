import SwiftData
import SwiftUI
import UIKit

struct NutritionComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query private var savedFoods: [FoodItem]

    let importedDraft: FoodImportDraft?
    let labelDraft: FoodImportDraft
    let localFood: FoodItem?
    let comparison: NutritionComparisonResult

    @State private var name: String
    @State private var brand: String
    @State private var servingSize: String
    @State private var baseUnit: FoodAmountUnit
    @State private var finalValues: [ComparedNutrientKind: String]
    @State private var errorText: String?
    @State private var savedFoodForLogging: NutritionComparisonLogRoute?
    @State private var isRawTextExpanded = false

    init(importedDraft: FoodImportDraft? = nil, labelDraft: FoodImportDraft, localFood: FoodItem? = nil) {
        self.importedDraft = importedDraft
        self.labelDraft = labelDraft
        self.localFood = localFood

        let service = NutritionComparisonService()
        let importedSnapshot = importedDraft.map { NutritionSourceSnapshot(draft: $0, source: nil) }
        let labelSnapshot = NutritionSourceSnapshot(draft: labelDraft, source: .labelScan)
        let localSnapshot = localFood.map(NutritionSourceSnapshot.init(food:))
        let comparison = service.compare(imported: importedSnapshot, label: labelSnapshot, local: localSnapshot)
        self.comparison = comparison

        let initialName = Self.cleanedText(localFood?.name)
            ?? importedDraft.flatMap { Self.cleanedText($0.name) }
            ?? Self.cleanedText(labelDraft.name)
            ?? ""
        let initialBrand = Self.cleanedText(localFood?.brand)
            ?? importedDraft.flatMap { Self.cleanedText($0.brand) }
            ?? Self.cleanedText(labelDraft.brand)
            ?? ""
        let initialServing = localFood?.servingSize
            ?? importedDraft?.servingSize
            ?? labelDraft.servingSize
        let initialBaseUnit = localFood?.baseUnit
            ?? importedDraft?.baseUnit
            ?? labelDraft.baseUnit

        _name = State(initialValue: initialName)
        _brand = State(initialValue: initialBrand)
        _servingSize = State(initialValue: Self.fieldText(initialServing))
        _baseUnit = State(initialValue: initialBaseUnit)
        _finalValues = State(initialValue: Dictionary(uniqueKeysWithValues: comparison.rows.map { row in
            (row.nutrient, Self.fieldText(row.finalValue))
        }))
    }

    var body: some View {
        FitnessScreen(
            title: "Resolve Nutrition",
            subtitle: localFood == nil
                ? "Compare imported data with the scanned label, then save one confirmed local version."
                : "Local saved data stays preferred until you choose to update it.",
            systemImage: "checklist.checked"
        ) {
            overviewCard
            warningsCard
            sourceCards
            resolutionControls
            identityCard
            finalMacroSummary

            DashboardSection(title: "Compare Values") {
                LazyVStack(spacing: 12) {
                    ForEach(comparison.rows) { row in
                        NutritionConflictRowView(
                            row: row,
                            finalText: binding(for: row.nutrient),
                            onUseCandidate: applyCandidate
                        )
                    }
                }
            }

            rawEvidenceCard

            if let errorText {
                ComparisonNoticeCard(message: errorText, systemImage: "exclamationmark.triangle", foregroundColor: appTheme.colors.danger)
            }

            Button {
                save(shouldLog: false)
            } label: {
                Label(localFood == nil ? "Save Confirmed Food" : "Update Local Food", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())

            Button {
                save(shouldLog: true)
            } label: {
                Label(localFood == nil ? "Save & Log Today" : "Update & Log Today", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryFitnessButtonStyle())
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $savedFoodForLogging) { route in
            if let food = savedFoods.first(where: { $0.id == route.id }) {
                LogFoodView(food: food)
            } else {
                missingSavedFoodView
            }
        }
    }

    private var missingSavedFoodView: some View {
        FitnessScreen(
            title: "Food unavailable",
            subtitle: "Go back and try again.",
            systemImage: "exclamationmark.triangle"
        ) {
            ComparisonNoticeCard(
                message: "The selected food is no longer available.",
                systemImage: "exclamationmark.triangle",
                foregroundColor: appTheme.colors.warning
            )
        }
    }

    private var overviewCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(overallTint)
                        .frame(width: 42, height: 42)
                        .background(overallTint.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(comparison.overallStatus.displayName)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(matchCountLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(appTheme.colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.accentSurface, in: Capsule())
                        }

                        Text(overviewMessage)
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(comparison.sources) { source in
                        NutritionSourceBadge(source: source.source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var matchCountLabel: String {
        comparison.matchingCount == 1 ? "1 match" : "\(comparison.matchingCount) matches"
    }

    @ViewBuilder
    private var warningsCard: some View {
        if !comparison.warnings.isEmpty || localFood != nil {
            DashboardSection(title: "Review Notes") {
                FitnessCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        if localFood != nil {
                            Label("Saving will update the existing local food. Nothing changes until you confirm.", systemImage: "checkmark.seal")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(comparison.warnings.prefix(8), id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var sourceCards: some View {
        DashboardSection(title: "Sources") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(comparison.sources) { source in
                    NutritionSourceCard(source: source)
                }
            }
        }
    }

    private var resolutionControls: some View {
        DashboardSection(title: "Resolution") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Apply a source to the editable final values. This never saves automatically.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        Button {
                            applyAll(from: .labelScan)
                        } label: {
                            Label("Use All Label Values", systemImage: "text.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())

                        if importedDraft != nil {
                            Button {
                                applyAll(from: .openFoodFacts)
                                applyAll(from: .editedOpenFoodFacts)
                            } label: {
                                Label("Use All Open Food Facts Values", systemImage: "network")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NeutralFitnessButtonStyle())
                        }

                        if localFood != nil {
                            Button {
                                applyAll(from: .localVerified)
                                applyAll(from: .localEdited)
                            } label: {
                                Label("Use Existing Local Values", systemImage: "checkmark.seal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NeutralFitnessButtonStyle())
                        }

                        Button {
                            applySuggestions()
                        } label: {
                            Label("Reset Suggestions", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeutralFitnessButtonStyle())
                    }
                }
            }
        }
    }

    private var identityCard: some View {
        DashboardSection(title: "Food Identity") {
            FitnessCard {
                VStack(spacing: 14) {
                    ComparisonTextField(title: "Food name", text: $name, placeholder: "Required")
                    ComparisonTextField(title: "Brand", text: $brand, placeholder: "Optional")

                    if let barcode = comparison.barcode, !barcode.isEmpty {
                        ComparisonStaticField(title: "Barcode", value: barcode)
                    }

                    Picker("Base unit", selection: $baseUnit) {
                        Text("g").tag(FoodAmountUnit.grams)
                        Text("ml").tag(FoodAmountUnit.millilitres)
                        Text("serving").tag(FoodAmountUnit.serving)
                    }
                    .pickerStyle(.segmented)

                    ComparisonTextField(
                        title: "Serving size",
                        text: $servingSize,
                        placeholder: "Optional",
                        suffix: baseUnit == .millilitres ? "ml" : "g",
                        keyboardType: .decimalPad
                    )
                }
            }
        }
    }

    private var finalMacroSummary: some View {
        DashboardSection(title: baseUnit == .millilitres ? "Final per 100ml" : "Final per 100g") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ComparisonMetricCard(title: "Calories", value: parsedValue(for: .calories), unit: "kcal")
                ComparisonMetricCard(title: "Protein", value: parsedValue(for: .protein), unit: "g")
                ComparisonMetricCard(title: "Carbs", value: parsedValue(for: .carbs), unit: "g")
                ComparisonMetricCard(title: "Fat", value: parsedValue(for: .fat), unit: "g")
            }
        }
    }

    @ViewBuilder
    private var rawEvidenceCard: some View {
        if let rawText = labelDraft.rawOCRText?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty {
            DashboardSection(title: "Label Evidence") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            isRawTextExpanded.toggle()
                        } label: {
                            HStack {
                                Label("OCR text", systemImage: "doc.text.viewfinder")
                                Spacer()
                                Image(systemName: isRawTextExpanded ? "chevron.up" : "chevron.down")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(appTheme.colors.accent)

                        if isRawTextExpanded {
                            Text(rawText)
                                .font(.footnote.monospaced())
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var overviewMessage: String {
        if comparison.reviewCount > 0 {
            return "\(comparison.reviewCount) values need your attention. Choose one source or edit the final values before saving."
        }
        if comparison.overallStatus == .consistent {
            return "Imported and label values are close. Review the final values, then save your local verified copy."
        }
        return "Some values are missing or rounded differently. The final saved food remains fully editable."
    }

    private var overallTint: Color {
        switch comparison.overallStatus {
        case .consistent:
            return appTheme.colors.success
        case .someDifferences, .singleSource:
            return appTheme.colors.warning
        case .needsReview:
            return appTheme.colors.danger
        }
    }

    private func binding(for nutrient: ComparedNutrientKind) -> Binding<String> {
        Binding {
            finalValues[nutrient] ?? ""
        } set: { newValue in
            finalValues[nutrient] = newValue
        }
    }

    private func applyCandidate(_ candidate: NutritionValueCandidate) {
        finalValues[candidate.nutrient] = Self.fieldText(candidate.value)
    }

    private func applyAll(from source: NutritionSourceType) {
        for row in comparison.rows {
            guard let candidate = row.candidates.first(where: { $0.source == source }) else { continue }
            applyCandidate(candidate)
        }
    }

    private func applySuggestions() {
        for row in comparison.rows {
            finalValues[row.nutrient] = Self.fieldText(row.suggestedValue?.value)
        }
    }

    private func parsedValue(for nutrient: ComparedNutrientKind) -> Double? {
        parseOptionalNonNegative(finalValues[nutrient] ?? "") ?? nil
    }

    private var parsedValues: ResolvedComparisonValues? {
        guard
            let servingSize = parseOptionalNonNegative(servingSize),
            let calories = parseOptionalNonNegative(finalValues[.calories] ?? ""),
            let protein = parseOptionalNonNegative(finalValues[.protein] ?? ""),
            let carbs = parseOptionalNonNegative(finalValues[.carbs] ?? ""),
            let fat = parseOptionalNonNegative(finalValues[.fat] ?? ""),
            let sugar = parseOptionalNonNegative(finalValues[.sugar] ?? ""),
            let fibre = parseOptionalNonNegative(finalValues[.fibre] ?? ""),
            let salt = parseOptionalNonNegative(finalValues[.salt] ?? "")
        else {
            return nil
        }

        return ResolvedComparisonValues(
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

    private func save(shouldLog: Bool) {
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

        let integrityService = NutritionDataIntegrityService()
        if let duplicateFood = integrityService.existingFood(matchingBarcode: comparison.barcode, in: savedFoods, excluding: localFood?.id) {
            errorText = integrityService.duplicateBarcodeMessage(for: duplicateFood)
            return
        }

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now
        let food: FoodItem

        if let localFood {
            localFood.barcode = comparison.barcode
            localFood.name = trimmedName
            localFood.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            localFood.servingSize = values.servingSize
            localFood.baseUnit = baseUnit
            localFood.caloriesPer100g = values.calories
            localFood.proteinPer100g = values.protein
            localFood.carbsPer100g = values.carbs
            localFood.fatPer100g = values.fat
            localFood.sugarPer100g = values.sugar
            localFood.fibrePer100g = values.fibre
            localFood.saltPer100g = values.salt
            localFood.source = .editedLabelScan
            localFood.verificationStatus = .userVerified
            localFood.updatedAt = now
            food = localFood
        } else {
            food = FoodItem(
                barcode: comparison.barcode,
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
                source: .editedLabelScan,
                verificationStatus: .userVerified,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(food)
        }

        do {
            try modelContext.save()
        } catch {
            if localFood == nil {
                modelContext.delete(food)
            }
            errorText = "Couldn't save this resolved food locally. Try again."
            return
        }

        if shouldLog {
            savedFoodForLogging = NutritionComparisonLogRoute(id: food.id)
        } else {
            dismiss()
        }
    }

    private func parseOptionalNonNegative(_ text: String) -> Double?? {
        NutritionDataIntegrityService.parseOptionalNonNegative(text)
    }

    private static func fieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func cleanedText(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private struct NutritionComparisonLogRoute: Identifiable, Hashable {
    let id: UUID
}

private struct ResolvedComparisonValues {
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

private struct NutritionConflictRowView: View {
    @Environment(\.appTheme) private var appTheme

    let row: NutritionComparisonRow
    @Binding var finalText: String
    let onUseCandidate: (NutritionValueCandidate) -> Void

    var body: some View {
        FitnessCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.nutrient.displayName)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        if let explanation = row.explanation {
                            Text(explanation)
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    ComparisonStatusBadge(status: row.status)
                }

                HStack(spacing: 8) {
                    CandidateValuePill(title: "Local", candidate: row.localValue, onUseCandidate: onUseCandidate)
                    CandidateValuePill(title: "Label", candidate: row.labelScanValue, onUseCandidate: onUseCandidate)
                    CandidateValuePill(title: "OFF", candidate: row.importedValue, onUseCandidate: onUseCandidate)
                }

                HStack(spacing: 10) {
                    Text("Final")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(width: 42, alignment: .leading)

                    TextField("Missing", text: $finalText)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(finalText.isEmpty && row.status != .unresolved ? appTheme.colors.warning.opacity(0.45) : appTheme.colors.cardBorder, lineWidth: 1)
                        }

                    Text(row.unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .frame(width: 34, alignment: .trailing)
                }

                ForEach(row.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CandidateValuePill: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let candidate: NutritionValueCandidate?
    let onUseCandidate: (NutritionValueCandidate) -> Void

    var body: some View {
        Button {
            if let candidate {
                onUseCandidate(candidate)
            }
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(appTheme.colors.textSecondary)

                Text(valueText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(candidate == nil ? appTheme.colors.textTertiary : appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(candidate?.basis.displayName ?? "Missing")
                    .font(.caption2)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(candidate == nil ? appTheme.colors.cardBorder : appTheme.colors.accent.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(candidate == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private var valueText: String {
        guard let candidate, let value = candidate.value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0...2))))\(candidate.unit)"
    }

    private var accessibilityLabel: String {
        guard let candidate, let value = candidate.value else {
            return "\(title) missing"
        }
        return "Use \(title) value \(value.formatted(.number.precision(.fractionLength(0...2)))) \(candidate.unit)"
    }
}

private struct ComparisonStatusBadge: View {
    @Environment(\.appTheme) private var appTheme

    let status: NutritionConflictStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .match:
            return appTheme.colors.success
        case .minorDifference, .missingFromOneSource, .onlyOneSourceAvailable:
            return appTheme.colors.warning
        case .majorDifference, .basisMismatch, .suspiciousValue, .unresolved:
            return appTheme.colors.danger
        }
    }
}

private struct NutritionSourceBadge: View {
    @Environment(\.appTheme) private var appTheme

    let source: NutritionSourceType

    var body: some View {
        Label(source.displayName, systemImage: source.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(appTheme.colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(appTheme.colors.accentSurface, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct NutritionSourceCard: View {
    @Environment(\.appTheme) private var appTheme

    let source: NutritionSourceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: source.source.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(appTheme.colors.accent)
                .frame(width: 34, height: 34)
                .background(appTheme.colors.accentSurface, in: Circle())

            Text(source.source.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(source.productName ?? "Unnamed food")
                .font(.caption)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)

            Text(source.basis.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ComparisonMetricCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            Text(valueText)
                .font(.title3.bold())
                .foregroundStyle(value == nil ? appTheme.colors.warning : appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var valueText: String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1))))\(unit)"
    }
}

private struct ComparisonTextField: View {
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
                    .stroke(placeholder == "Required" && text.isEmpty ? appTheme.colors.warning : appTheme.colors.cardBorder, lineWidth: 1)
            }
        }
    }
}

private struct ComparisonStaticField: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct ComparisonNoticeCard: View {
    let message: String
    let systemImage: String
    let foregroundColor: Color

    var body: some View {
        FitnessCard(padding: 16) {
            Label(message, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
