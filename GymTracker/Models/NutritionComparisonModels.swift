import Foundation

enum NutritionSourceType: String, Codable, CaseIterable, Hashable {
    case localVerified
    case localEdited
    case openFoodFacts
    case editedOpenFoodFacts
    case labelScan
    case manual

    var displayName: String {
        switch self {
        case .localVerified:
            return "Local saved"
        case .localEdited:
            return "Edited local"
        case .openFoodFacts:
            return "Open Food Facts"
        case .editedOpenFoodFacts:
            return "Edited import"
        case .labelScan:
            return "Label scan"
        case .manual:
            return "Manual"
        }
    }

    var systemImage: String {
        switch self {
        case .localVerified, .localEdited:
            return "checkmark.seal.fill"
        case .openFoodFacts, .editedOpenFoodFacts:
            return "network"
        case .labelScan:
            return "text.viewfinder"
        case .manual:
            return "square.and.pencil"
        }
    }
}

enum ComparedNutrientKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case calories
    case protein
    case carbs
    case fat
    case sugar
    case fibre
    case salt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calories:
            return "Calories"
        case .protein:
            return "Protein"
        case .carbs:
            return "Carbs"
        case .fat:
            return "Fat"
        case .sugar:
            return "Sugar"
        case .fibre:
            return "Fibre"
        case .salt:
            return "Salt"
        }
    }

    var shortName: String {
        switch self {
        case .calories:
            return "kcal"
        case .protein:
            return "P"
        case .carbs:
            return "C"
        case .fat:
            return "F"
        case .sugar:
            return "Sug"
        case .fibre:
            return "Fib"
        case .salt:
            return "Salt"
        }
    }

    var unit: String {
        switch self {
        case .calories:
            return "kcal"
        case .protein, .carbs, .fat, .sugar, .fibre, .salt:
            return "g"
        }
    }
}

enum NutritionConflictStatus: String, Codable, Hashable {
    case match
    case minorDifference
    case majorDifference
    case missingFromOneSource
    case onlyOneSourceAvailable
    case basisMismatch
    case suspiciousValue
    case unresolved

    var displayName: String {
        switch self {
        case .match:
            return "Match"
        case .minorDifference:
            return "Small difference"
        case .majorDifference:
            return "Needs review"
        case .missingFromOneSource:
            return "Missing value"
        case .onlyOneSourceAvailable:
            return "Only one source"
        case .basisMismatch:
            return "Different basis"
        case .suspiciousValue:
            return "Check this"
        case .unresolved:
            return "Unresolved"
        }
    }
}

enum NutritionComparisonOverallStatus: String, Codable, Hashable {
    case consistent
    case someDifferences
    case needsReview
    case singleSource

    var displayName: String {
        switch self {
        case .consistent:
            return "Values look consistent"
        case .someDifferences:
            return "Some differences"
        case .needsReview:
            return "Needs review"
        case .singleSource:
            return "Single source"
        }
    }
}

struct NutritionValueCandidate: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var nutrient: ComparedNutrientKind
    var value: Double?
    var unit: String
    var basis: NutritionBasis
    var source: NutritionSourceType
    var confidence: Double?
    var note: String?
}

struct NutritionSourceSnapshot: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var source: NutritionSourceType
    var productName: String?
    var brand: String?
    var barcode: String?
    var servingSize: Double?
    var baseUnit: FoodAmountUnit
    var basis: NutritionBasis
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var sugar: Double?
    var fibre: Double?
    var salt: Double?
    var confidence: Double?
    var rawText: String?
    var capturedAt: Date?
    var warnings: [String]

    init(
        source: NutritionSourceType,
        productName: String? = nil,
        brand: String? = nil,
        barcode: String? = nil,
        servingSize: Double? = nil,
        baseUnit: FoodAmountUnit = .grams,
        basis: NutritionBasis = .per100g,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        sugar: Double? = nil,
        fibre: Double? = nil,
        salt: Double? = nil,
        confidence: Double? = nil,
        rawText: String? = nil,
        capturedAt: Date? = nil,
        warnings: [String] = []
    ) {
        self.source = source
        self.productName = productName
        self.brand = brand
        self.barcode = barcode
        self.servingSize = servingSize
        self.baseUnit = baseUnit
        self.basis = basis
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.sugar = sugar
        self.fibre = fibre
        self.salt = salt
        self.confidence = confidence
        self.rawText = rawText
        self.capturedAt = capturedAt
        self.warnings = warnings
    }

    init(draft: FoodImportDraft, source overrideSource: NutritionSourceType? = nil) {
        let parseConfidence = draft.nutritionParseResult?.overallConfidence.comparisonConfidence
        let basis = draft.nutritionParseResult?.selectedBasis.comparableBasis ?? draft.baseUnit.defaultNutritionBasis
        self.init(
            source: overrideSource ?? NutritionSourceType(foodDataSource: draft.source),
            productName: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            brand: draft.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            barcode: draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            servingSize: draft.servingSize,
            baseUnit: draft.baseUnit,
            basis: basis,
            calories: draft.caloriesPer100g,
            protein: draft.proteinPer100g,
            carbs: draft.carbsPer100g,
            fat: draft.fatPer100g,
            sugar: draft.sugarPer100g,
            fibre: draft.fibrePer100g,
            salt: draft.saltPer100g,
            confidence: parseConfidence ?? NutritionSourceType(foodDataSource: draft.source).defaultConfidence,
            rawText: draft.rawOCRText,
            capturedAt: Date.now,
            warnings: draft.nutritionParseResult?.warnings.map(\.message) ?? []
        )
    }

    init(food: FoodItem) {
        let source: NutritionSourceType = food.verificationStatus == .userVerified ? .localVerified : .localEdited
        self.init(
            source: source,
            productName: food.name,
            brand: food.brand,
            barcode: food.barcode,
            servingSize: food.servingSize,
            baseUnit: food.baseUnit,
            basis: food.baseUnit.defaultNutritionBasis,
            calories: food.caloriesPer100g,
            protein: food.proteinPer100g,
            carbs: food.carbsPer100g,
            fat: food.fatPer100g,
            sugar: food.sugarPer100g,
            fibre: food.fibrePer100g,
            salt: food.saltPer100g,
            confidence: 1.0,
            capturedAt: food.updatedAt,
            warnings: []
        )
    }

    func value(for nutrient: ComparedNutrientKind) -> Double? {
        switch nutrient {
        case .calories:
            return calories
        case .protein:
            return protein
        case .carbs:
            return carbs
        case .fat:
            return fat
        case .sugar:
            return sugar
        case .fibre:
            return fibre
        case .salt:
            return salt
        }
    }
}

struct NutritionComparisonRow: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var nutrient: ComparedNutrientKind
    var importedValue: NutritionValueCandidate?
    var labelScanValue: NutritionValueCandidate?
    var localValue: NutritionValueCandidate?
    var suggestedValue: NutritionValueCandidate?
    var finalValue: Double?
    var unit: String
    var status: NutritionConflictStatus
    var explanation: String?
    var warnings: [String]

    var candidates: [NutritionValueCandidate] {
        [localValue, labelScanValue, importedValue].compactMap { $0 }
    }
}

struct NutritionComparisonResult: Codable, Equatable, Hashable {
    var productName: String?
    var brand: String?
    var barcode: String?
    var basis: NutritionBasis
    var sources: [NutritionSourceSnapshot]
    var rows: [NutritionComparisonRow]
    var overallStatus: NutritionComparisonOverallStatus
    var warnings: [String]
    var comparedAt: Date

    var matchingCount: Int {
        rows.filter { $0.status == .match }.count
    }

    var reviewCount: Int {
        rows.filter {
            [.majorDifference, .basisMismatch, .suspiciousValue, .unresolved].contains($0.status)
        }.count
    }
}

private extension NutritionSourceType {
    init(foodDataSource: FoodDataSource) {
        switch foodDataSource {
        case .manual:
            self = .manual
        case .openFoodFacts:
            self = .openFoodFacts
        case .editedOpenFoodFacts:
            self = .editedOpenFoodFacts
        case .labelScan, .editedLabelScan:
            self = .labelScan
        }
    }

    var defaultConfidence: Double {
        switch self {
        case .localVerified:
            return 1.0
        case .localEdited:
            return 0.95
        case .labelScan:
            return 0.7
        case .editedOpenFoodFacts:
            return 0.75
        case .openFoodFacts:
            return 0.65
        case .manual:
            return 0.9
        }
    }
}

private extension NutritionParseConfidence {
    var comparisonConfidence: Double {
        switch self {
        case .high:
            return 0.9
        case .medium:
            return 0.65
        case .low:
            return 0.35
        }
    }
}

private extension FoodAmountUnit {
    var defaultNutritionBasis: NutritionBasis {
        switch self {
        case .grams:
            return .per100g
        case .millilitres:
            return .per100ml
        case .serving:
            return .perServing
        }
    }
}

private extension NutritionBasis {
    var comparableBasis: NutritionBasis {
        switch self {
        case .per100g, .per100ml, .perServing:
            return self
        case .unknown:
            return .unknown
        }
    }
}

