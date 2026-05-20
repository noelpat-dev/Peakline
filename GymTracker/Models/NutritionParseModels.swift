import Foundation

enum NutritionNutrientKind: String, Codable, CaseIterable, Hashable {
    case energyKJ
    case calories
    case fat
    case saturatedFat
    case carbohydrates
    case sugars
    case fibre
    case protein
    case salt
    case sodium

    var displayName: String {
        switch self {
        case .energyKJ:
            return "Energy"
        case .calories:
            return "Calories"
        case .fat:
            return "Fat"
        case .saturatedFat:
            return "Saturates"
        case .carbohydrates:
            return "Carbs"
        case .sugars:
            return "Sugars"
        case .fibre:
            return "Fibre"
        case .protein:
            return "Protein"
        case .salt:
            return "Salt"
        case .sodium:
            return "Sodium"
        }
    }
}

enum NutritionUnit: String, Codable, CaseIterable, Hashable {
    case kcal
    case kj
    case grams
    case milligrams
    case millilitres
    case unknown

    var shortName: String {
        switch self {
        case .kcal:
            return "kcal"
        case .kj:
            return "kJ"
        case .grams:
            return "g"
        case .milligrams:
            return "mg"
        case .millilitres:
            return "ml"
        case .unknown:
            return ""
        }
    }
}

enum NutritionBasis: String, Codable, CaseIterable, Hashable {
    case per100g
    case per100ml
    case perServing
    case unknown

    var displayName: String {
        switch self {
        case .per100g:
            return "Per 100g"
        case .per100ml:
            return "Per 100ml"
        case .perServing:
            return "Per serving"
        case .unknown:
            return "Basis unclear"
        }
    }
}

enum NutritionParseConfidence: String, Codable, CaseIterable, Hashable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high:
            return "Detected"
        case .medium:
            return "Check"
        case .low:
            return "Review"
        }
    }
}

enum NutritionParseWarning: String, Codable, CaseIterable, Hashable, Identifiable {
    case missingCalories
    case missingProtein
    case missingCarbs
    case missingFat
    case basisNotDetected
    case onlyServingValuesDetected
    case servingSizeMissing
    case usedKJToKcalConversion
    case sodiumConvertedToSalt
    case valueLooksTooHigh
    case valueLooksTooLow
    case sugarGreaterThanCarbs
    case saturatedFatGreaterThanFat
    case energyDoesNotMatchMacros
    case ambiguousColumn
    case ambiguousNutrient
    case ocrLikelyMisread

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingCalories:
            return "Calories were not detected. Check the label before saving."
        case .missingProtein:
            return "Protein was not detected."
        case .missingCarbs:
            return "Carbohydrates were not detected."
        case .missingFat:
            return "Fat was not detected."
        case .basisNotDetected:
            return "The parser could not clearly tell whether values are per 100g, per 100ml, or per serving."
        case .onlyServingValuesDetected:
            return "Only per-serving values were detected. Check the serving size before saving."
        case .servingSizeMissing:
            return "Serving size was not detected."
        case .usedKJToKcalConversion:
            return "Calories were converted from kJ. Please check the value."
        case .sodiumConvertedToSalt:
            return "Sodium was converted to salt using sodium x 2.5."
        case .valueLooksTooHigh:
            return "One or more values look unusually high for the detected basis."
        case .valueLooksTooLow:
            return "One or more values look unusually low."
        case .sugarGreaterThanCarbs:
            return "Sugars are higher than carbohydrates. Check the label."
        case .saturatedFatGreaterThanFat:
            return "Saturates are higher than total fat. Check the label."
        case .energyDoesNotMatchMacros:
            return "Calories do not closely match the detected macros."
        case .ambiguousColumn:
            return "A column was ambiguous. Check that the correct per-100 value was chosen."
        case .ambiguousNutrient:
            return "A nutrient label was ambiguous. Check the detected value."
        case .ocrLikelyMisread:
            return "Some common OCR corrections were applied. Please review the numbers."
        }
    }
}

struct ParsedServingSize: Equatable, Hashable {
    var amount: Double
    var unit: NutritionUnit
    var sourceLine: String
    var confidence: NutritionParseConfidence
}

struct ParsedNutrientAlternative: Equatable, Hashable {
    var amount: Double
    var unit: NutritionUnit
    var basis: NutritionBasis
    var sourceLine: String
}

struct ParsedNutrientValue: Equatable, Hashable, Identifiable {
    var id: UUID
    var nutrient: NutritionNutrientKind
    var amount: Double
    var unit: NutritionUnit
    var basis: NutritionBasis
    var confidence: NutritionParseConfidence
    var sourceLine: String
    var sourceLineIndex: Int?
    var alternatives: [ParsedNutrientAlternative]
    var warnings: [NutritionParseWarning]

    init(
        id: UUID = UUID(),
        nutrient: NutritionNutrientKind,
        amount: Double,
        unit: NutritionUnit,
        basis: NutritionBasis,
        confidence: NutritionParseConfidence,
        sourceLine: String,
        sourceLineIndex: Int? = nil,
        alternatives: [ParsedNutrientAlternative] = [],
        warnings: [NutritionParseWarning] = []
    ) {
        self.id = id
        self.nutrient = nutrient
        self.amount = amount
        self.unit = unit
        self.basis = basis
        self.confidence = confidence
        self.sourceLine = sourceLine
        self.sourceLineIndex = sourceLineIndex
        self.alternatives = alternatives
        self.warnings = warnings
    }
}

struct NutritionParseResult: Equatable, Hashable {
    var values: [ParsedNutrientValue]
    var selectedBasis: NutritionBasis
    var availableBases: [NutritionBasis]
    var servingSize: ParsedServingSize?
    var warnings: [NutritionParseWarning]
    var overallConfidence: NutritionParseConfidence
    var rawLines: [String]
    var normalizedLines: [String]

    func value(for nutrient: NutritionNutrientKind) -> ParsedNutrientValue? {
        values.first { $0.nutrient == nutrient }
    }
}
