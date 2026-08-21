import Foundation
import SwiftData

enum FoodAmountUnit: String, Codable, DisplayableEnum, Sendable {
    case grams
    case millilitres
    case serving

    var shortName: String {
        switch self {
        case .grams:
            return "g"
        case .millilitres:
            return "ml"
        case .serving:
            return "serving"
        }
    }
}

enum MealType: String, Codable, DisplayableEnum, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case preWorkout
    case postWorkout

    var systemImage: String {
        switch self {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "fork.knife"
        case .dinner:
            return "moon.stars.fill"
        case .snack:
            return "takeoutbag.and.cup.and.straw.fill"
        case .preWorkout:
            return "bolt.fill"
        case .postWorkout:
            return "checkmark.seal.fill"
        }
    }
}

enum FoodDataSource: String, Codable, DisplayableEnum, Sendable {
    case manual
    case openFoodFacts
    case editedOpenFoodFacts
    case labelScan
    case editedLabelScan
}

enum FoodVerificationStatus: String, Codable, DisplayableEnum, Sendable {
    case unverified
    case userVerified
    case imported
    case edited
}

enum HydrationEntrySource: String, Codable, CaseIterable, DisplayableEnum {
    case manual
    case quickAdd
    case preset
    case healthKit
}

enum HydrationEntryContext: String, Codable, CaseIterable, DisplayableEnum {
    case general
    case preWorkout
    case duringWorkout
    case postWorkout
    case morning
    case evening
}

enum HydrationStatus: String, Codable, CaseIterable, DisplayableEnum {
    case low
    case behind
    case onTrack
    case complete
    case aboveTarget
}

enum RecoverySignalConfidence: String, Codable, CaseIterable, DisplayableEnum {
    case unknown
    case low
    case medium
    case high
}

struct DailyHydrationSummary {
    let date: Date
    let totalML: Int
    let targetML: Int
    let progress: Double
    let remainingML: Int
    let status: HydrationStatus
    let lastLoggedAt: Date?
}

struct HydrationRecoverySignal {
    let status: HydrationStatus
    let completionRatio: Double
    let totalML: Int
    let targetML: Int
    let lastLoggedAt: Date?
    let confidence: RecoverySignalConfidence
}

@Model
final class HydrationEntry {
    @Attribute(.unique) var id: UUID
    var amountML: Int
    var loggedAt: Date
    var source: HydrationEntrySource
    var context: HydrationEntryContext
    var linkedWorkoutID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        amountML: Int,
        loggedAt: Date = .now,
        source: HydrationEntrySource = .quickAdd,
        context: HydrationEntryContext = .general,
        linkedWorkoutID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amountML = amountML
        self.loggedAt = loggedAt
        self.source = source
        self.context = context
        self.linkedWorkoutID = linkedWorkoutID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var barcode: String?
    var name: String
    var brand: String?
    var servingSize: Double?
    var baseUnit: FoodAmountUnit
    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var sugarPer100g: Double?
    var fibrePer100g: Double?
    var saltPer100g: Double?
    var source: FoodDataSource
    var verificationStatus: FoodVerificationStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        barcode: String? = nil,
        name: String,
        brand: String? = nil,
        servingSize: Double? = nil,
        baseUnit: FoodAmountUnit = .grams,
        caloriesPer100g: Double? = nil,
        proteinPer100g: Double? = nil,
        carbsPer100g: Double? = nil,
        fatPer100g: Double? = nil,
        sugarPer100g: Double? = nil,
        fibrePer100g: Double? = nil,
        saltPer100g: Double? = nil,
        source: FoodDataSource = .manual,
        verificationStatus: FoodVerificationStatus = .userVerified,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.servingSize = servingSize
        self.baseUnit = baseUnit
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.sugarPer100g = sugarPer100g
        self.fibrePer100g = fibrePer100g
        self.saltPer100g = saltPer100g
        self.source = source
        self.verificationStatus = verificationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FoodLogEntry {
    @Attribute(.unique) var id: UUID
    var foodItemId: UUID
    var foodNameSnapshot: String
    var brandSnapshot: String?
    var consumedAmount: Double
    var amountUnit: FoodAmountUnit
    var mealType: MealType
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var sugarSnapshot: Double?
    var fibreSnapshot: Double?
    var saltSnapshot: Double?
    var loggedAt: Date
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        foodItemId: UUID,
        foodNameSnapshot: String,
        brandSnapshot: String? = nil,
        consumedAmount: Double,
        amountUnit: FoodAmountUnit,
        mealType: MealType,
        caloriesSnapshot: Double,
        proteinSnapshot: Double,
        carbsSnapshot: Double,
        fatSnapshot: Double,
        sugarSnapshot: Double? = nil,
        fibreSnapshot: Double? = nil,
        saltSnapshot: Double? = nil,
        loggedAt: Date = .now,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.foodItemId = foodItemId
        self.foodNameSnapshot = foodNameSnapshot
        self.brandSnapshot = brandSnapshot
        self.consumedAmount = consumedAmount
        self.amountUnit = amountUnit
        self.mealType = mealType
        self.caloriesSnapshot = caloriesSnapshot
        self.proteinSnapshot = proteinSnapshot
        self.carbsSnapshot = carbsSnapshot
        self.fatSnapshot = fatSnapshot
        self.sugarSnapshot = sugarSnapshot
        self.fibreSnapshot = fibreSnapshot
        self.saltSnapshot = saltSnapshot
        self.loggedAt = loggedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
