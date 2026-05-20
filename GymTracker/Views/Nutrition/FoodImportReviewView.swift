import SwiftData
import SwiftUI
import UIKit

struct FoodImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query private var savedFoods: [FoodItem]

    let draft: FoodImportDraft
    let onRetakeLabelScan: (() -> Void)?

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
    @State private var savedFoodForLogging: FoodItem?
    @State private var isDetectedTextExpanded = false
    @State private var didCopyDetectedText = false

    init(draft: FoodImportDraft, onRetakeLabelScan: (() -> Void)? = nil) {
        self.draft = draft
        self.onRetakeLabelScan = onRetakeLabelScan
        _name = State(initialValue: draft.name)
        _brand = State(initialValue: draft.brand ?? "")
        _servingSize = State(initialValue: Self.fieldText(draft.servingSize))
        _baseUnit = State(initialValue: draft.baseUnit)
        _calories = State(initialValue: Self.fieldText(draft.caloriesPer100g))
        _protein = State(initialValue: Self.fieldText(draft.proteinPer100g))
        _carbs = State(initialValue: Self.fieldText(draft.carbsPer100g))
        _fat = State(initialValue: Self.fieldText(draft.fatPer100g))
        _sugar = State(initialValue: Self.fieldText(draft.sugarPer100g))
        _fibre = State(initialValue: Self.fieldText(draft.fibrePer100g))
        _salt = State(initialValue: Self.fieldText(draft.saltPer100g))
    }

    var body: some View {
        FitnessScreen(
            title: screenTitle,
            subtitle: screenSubtitle,
            systemImage: "checkmark.seal"
        ) {
            importSourceCard

            if let parseResult = draft.nutritionParseResult {
                parsedNutritionCard(parseResult)
                parseWarningsCard(parseResult)
            }

            if hasDetectedText {
                detectedTextCard
            }

            DashboardSection(title: "Food Identity") {
                FitnessCard {
                    VStack(spacing: 14) {
                        if !draft.barcode.isEmpty {
                            ReviewTextField(title: "Barcode", text: .constant(draft.barcode), placeholder: "", isReadOnly: true)
                        }
                        ReviewTextField(title: "Food name", text: $name, placeholder: "Required")
                        ReviewTextField(title: "Brand", text: $brand, placeholder: "Optional")
                    }
                }
            }

            DashboardSection(title: "Nutrition Basis") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Base unit", selection: $baseUnit) {
                            Text("g").tag(FoodAmountUnit.grams)
                            Text("ml").tag(FoodAmountUnit.millilitres)
                            Text("serving").tag(FoodAmountUnit.serving)
                        }
                        .pickerStyle(.segmented)

                        ReviewTextField(
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
                        ReviewTextField(title: "Calories", text: $calories, placeholder: missingPlaceholder(draft.caloriesPer100g), suffix: "kcal", keyboardType: .decimalPad)
                        ReviewTextField(title: "Protein", text: $protein, placeholder: missingPlaceholder(draft.proteinPer100g), suffix: "g", keyboardType: .decimalPad)
                        ReviewTextField(title: "Carbs", text: $carbs, placeholder: missingPlaceholder(draft.carbsPer100g), suffix: "g", keyboardType: .decimalPad)
                        ReviewTextField(title: "Fat", text: $fat, placeholder: missingPlaceholder(draft.fatPer100g), suffix: "g", keyboardType: .decimalPad)
                    }
                }
            }

            DashboardSection(title: "Optional Details") {
                FitnessCard {
                    VStack(spacing: 14) {
                        ReviewTextField(title: "Sugar", text: $sugar, placeholder: missingPlaceholder(draft.sugarPer100g), suffix: "g", keyboardType: .decimalPad)
                        ReviewTextField(title: "Fibre", text: $fibre, placeholder: missingPlaceholder(draft.fibrePer100g), suffix: "g", keyboardType: .decimalPad)
                        ReviewTextField(title: "Salt", text: $salt, placeholder: missingPlaceholder(draft.saltPer100g), suffix: "g", keyboardType: .decimalPad)
                    }
                }
            }

            if let warningText {
                ReviewNoticeCard(message: warningText, systemImage: "exclamationmark.triangle", foregroundColor: appTheme.colors.warning)
            }

            if let errorText {
                ReviewNoticeCard(message: errorText, systemImage: "exclamationmark.triangle", foregroundColor: appTheme.colors.danger)
            }

            Button {
                save(shouldLog: false)
            } label: {
                Label("Save Locally", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFitnessButtonStyle())
            .accessibilityLabel("Save confirmed food")

            Button {
                save(shouldLog: true)
            } label: {
                Label("Save & Log Today", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryFitnessButtonStyle())
            .accessibilityLabel("Save and log food today")
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $savedFoodForLogging) { food in
            LogFoodView(food: food)
        }
    }

    private var screenTitle: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "Review Food Details"
        case .labelScan, .editedLabelScan:
            return draft.nutritionParseResult == nil ? "Review Label Scan" : "Review Detected Nutrition"
        case .manual:
            return "Create Food"
        }
    }

    private var screenSubtitle: String {
        switch draft.source {
        case .labelScan, .editedLabelScan:
            return draft.nutritionParseResult == nil
                ? "Use the detected text as a guide, then confirm each value."
                : "We filled these from the label scan. Check them before saving."
        default:
            return "Confirm values before saving to your local database."
        }
    }

    private var navigationTitle: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "Review"
        case .labelScan, .editedLabelScan:
            return "Label Scan"
        case .manual:
            return "Create Food"
        }
    }

    private var importSourceCard: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sourceSystemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 42, height: 42)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(sourceTitle)
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(sourceBadge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(appTheme.colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(appTheme.colors.accentSurface, in: Capsule())
                    }

                    Text(sourceMessage)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func parsedNutritionCard(_ parseResult: NutritionParseResult) -> some View {
        DashboardSection(title: "Detected Nutrition") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 42, height: 42)
                            .background(appTheme.colors.accentSurface, in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(parseResult.values.isEmpty ? "No auto-fill yet" : "Auto-fill suggestions")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)

                                confidenceBadge(parseResult.overallConfidence)
                            }

                            Text(parseResult.values.isEmpty
                                ? "We found text, but could not confidently detect nutrition values. Fill the fields manually or retake the photo."
                                : "\(parseResult.values.count) values detected from the label. All fields remain editable.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(parseResult.selectedBasis.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(appTheme.colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(appTheme.colors.accentSurface, in: Capsule())

                        if let servingSize = parseResult.servingSize {
                            Text("Serving \(Self.fieldText(servingSize.amount))\(servingSize.unit.shortName)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ParsedNutrientMetric(title: "Calories", value: parseResult.value(for: .calories), fallbackUnit: "kcal")
                        ParsedNutrientMetric(title: "Protein", value: parseResult.value(for: .protein), fallbackUnit: "g")
                        ParsedNutrientMetric(title: "Carbs", value: parseResult.value(for: .carbohydrates), fallbackUnit: "g")
                        ParsedNutrientMetric(title: "Fat", value: parseResult.value(for: .fat), fallbackUnit: "g")
                    }

                    let optionalValues = [
                        parseResult.value(for: .sugars),
                        parseResult.value(for: .fibre),
                        parseResult.value(for: .salt)
                    ].compactMap { $0 }

                    if !optionalValues.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(optionalValues) { value in
                                ParsedNutrientPill(value: value)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func parseWarningsCard(_ parseResult: NutritionParseResult) -> some View {
        if !parseResult.warnings.isEmpty {
            DashboardSection(title: "Review Notes") {
                FitnessCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(parseResult.warnings.prefix(6)) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func confidenceBadge(_ confidence: NutritionParseConfidence) -> some View {
        Text(confidence.displayName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(confidenceTint(confidence))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(confidenceTint(confidence).opacity(0.14), in: Capsule())
    }

    private func confidenceTint(_ confidence: NutritionParseConfidence) -> Color {
        switch confidence {
        case .high:
            return appTheme.colors.success
        case .medium:
            return appTheme.colors.warning
        case .low:
            return appTheme.colors.danger
        }
    }

    private var detectedTextCard: some View {
        DashboardSection(title: "Detected Label Text") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "text.viewfinder")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                            .frame(width: 42, height: 42)
                            .background(appTheme.colors.accentSurface, in: Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(draft.nutritionParseResult == nil ? "OCR helper" : "Raw OCR text")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)

                                Text(draft.nutritionParseResult == nil ? "Needs review" : "Transparent")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(appTheme.colors.warning)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(appTheme.colors.warning.opacity(0.14), in: Capsule())
                            }

                            Text("OCR may misread numbers. Enter the per 100g or per 100ml values from the detected label text.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(displayedDetectedText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                        }
                        .lineLimit(isDetectedTextExpanded ? nil : 10)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button {
                            isDetectedTextExpanded.toggle()
                        } label: {
                            Label(isDetectedTextExpanded ? "Show Less" : "Show More", systemImage: isDetectedTextExpanded ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appTheme.colors.accent)

                        Button {
                            UIPasteboard.general.string = detectedRawText
                            didCopyDetectedText = true
                        } label: {
                            Label(didCopyDetectedText ? "Copied" : "Copy Text", systemImage: didCopyDetectedText ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appTheme.colors.accent)
                        .accessibilityLabel("Copy detected label text")

                        if let onRetakeLabelScan {
                            Button {
                                dismiss()
                                onRetakeLabelScan()
                            } label: {
                                Label("Retake", systemImage: "camera")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(appTheme.colors.accent)
                            .accessibilityLabel("Retake label photo")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var sourceSystemImage: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "network"
        case .labelScan, .editedLabelScan:
            return "text.viewfinder"
        case .manual:
            return draft.barcode.isEmpty ? "square.and.pencil" : "barcode.viewfinder"
        }
    }

    private var sourceTitle: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "Open Food Facts import"
        case .labelScan, .editedLabelScan:
            return draft.nutritionParseResult == nil ? "Label scan" : "Parsed label scan"
        case .manual:
            return draft.barcode.isEmpty ? "Manual food" : "Manual barcode food"
        }
    }

    private var sourceBadge: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "Review"
        case .labelScan, .editedLabelScan:
            return draft.nutritionParseResult == nil ? "OCR MVP" : "Auto-filled"
        case .manual:
            return "Local"
        }
    }

    private var sourceMessage: String {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return "Review the label values before saving. Future scans will use your local saved copy."
        case .labelScan, .editedLabelScan:
            if draft.nutritionParseResult != nil {
                return "Parsed OCR values are suggestions. Your saved food only becomes trusted after you confirm it."
            }
            if draft.barcode.isEmpty {
                return "Detected text stays on this review screen. Only your confirmed food values are saved."
            }
            return "Detected text helps you fill the values. The confirmed food will keep this barcode for future local matches."
        case .manual:
            return draft.barcode.isEmpty
                ? "Create a verified food from values you trust."
                : "This barcode will be attached to the local food you create."
        }
    }

    private var hasDetectedText: Bool {
        !detectedRawText.isEmpty
    }

    private var detectedRawText: String {
        (draft.rawOCRText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedDetectedText: String {
        detectedRawText.isEmpty ? "No detected text." : detectedRawText
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

    private var parsedValues: ParsedReviewValues? {
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

        return ParsedReviewValues(
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

    private var warningText: String? {
        guard let values = parsedValues else { return nil }
        if !values.hasNutrition {
            return "Add at least one calorie or macro value before saving."
        }

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
        if let duplicateFood = integrityService.existingFood(matchingBarcode: draft.barcode, in: savedFoods) {
            errorText = integrityService.duplicateBarcodeMessage(for: duplicateFood)
            return
        }

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now
        let food = FoodItem(
            barcode: draft.barcode.isEmpty ? nil : draft.barcode,
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
            source: savedSource,
            verificationStatus: .userVerified,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(food)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(food)
            errorText = "Couldn't save this food locally. Try again."
            return
        }

        if shouldLog {
            savedFoodForLogging = food
        } else {
            dismiss()
        }
    }

    private var savedSource: FoodDataSource {
        switch draft.source {
        case .openFoodFacts, .editedOpenFoodFacts:
            return isEditedImportedDraft ? .editedOpenFoodFacts : .openFoodFacts
        case .labelScan, .editedLabelScan:
            return isEditedImportedDraft ? .editedLabelScan : .labelScan
        case .manual:
            return .manual
        }
    }

    private var isEditedImportedDraft: Bool {
        name != draft.name
            || brand != (draft.brand ?? "")
            || servingSize != Self.fieldText(draft.servingSize)
            || baseUnit != draft.baseUnit
            || calories != Self.fieldText(draft.caloriesPer100g)
            || protein != Self.fieldText(draft.proteinPer100g)
            || carbs != Self.fieldText(draft.carbsPer100g)
            || fat != Self.fieldText(draft.fatPer100g)
            || sugar != Self.fieldText(draft.sugarPer100g)
            || fibre != Self.fieldText(draft.fibrePer100g)
            || salt != Self.fieldText(draft.saltPer100g)
    }

    private func parseOptionalNonNegative(_ text: String) -> Double?? {
        NutritionDataIntegrityService.parseOptionalNonNegative(text)
    }

    private func missingPlaceholder(_ value: Double?) -> String {
        value == nil ? "Missing" : "Optional"
    }

    private static func fieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct ParsedReviewValues {
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

private struct ParsedNutrientMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: ParsedNutrientValue?
    let fallbackUnit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)

                Spacer(minLength: 4)

                Text(value?.confidence.displayName ?? "Missing")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(confidenceTint)
            }

            Text(valueText)
                .font(.title3.bold())
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value?.basis.displayName ?? "Not detected")
                .font(.caption2)
                .foregroundStyle(appTheme.colors.textTertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(value == nil ? appTheme.colors.warning.opacity(0.35) : appTheme.colors.cardBorder, lineWidth: 1)
        }
    }

    private var valueText: String {
        guard let value else { return "-" }
        let amount = value.amount.formatted(.number.precision(.fractionLength(0...1)))
        let unit = value.unit.shortName.isEmpty ? fallbackUnit : value.unit.shortName
        return "\(amount)\(unit)"
    }

    private var confidenceTint: Color {
        guard let value else { return appTheme.colors.warning }
        switch value.confidence {
        case .high:
            return appTheme.colors.success
        case .medium:
            return appTheme.colors.warning
        case .low:
            return appTheme.colors.danger
        }
    }
}

private struct ParsedNutrientPill: View {
    @Environment(\.appTheme) private var appTheme

    let value: ParsedNutrientValue

    var body: some View {
        VStack(spacing: 2) {
            Text(amountText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value.nutrient.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var amountText: String {
        "\(value.amount.formatted(.number.precision(.fractionLength(0...2))))\(value.unit.shortName)"
    }
}

private struct ReviewTextField: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    @Binding var text: String
    let placeholder: String
    var suffix: String?
    var keyboardType: UIKeyboardType = .default
    var isReadOnly = false

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
                    .disabled(isReadOnly)

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
                    .stroke(placeholder == "Missing" && text.isEmpty ? appTheme.colors.warning : appTheme.colors.cardBorder, lineWidth: 1)
            }
        }
    }
}

private struct ReviewNoticeCard: View {
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
