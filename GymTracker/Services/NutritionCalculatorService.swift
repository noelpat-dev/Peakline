import Foundation

struct NutritionMacroSnapshot {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugar: Double?
    let fibre: Double?
    let salt: Double?
}

struct NutritionCalculatorService {
    func calculate(for food: FoodItem, consumedAmount: Double, unit: FoodAmountUnit) -> NutritionMacroSnapshot {
        let clampedAmount = max(consumedAmount, 0)
        let amountForPer100Calculation: Double

        switch unit {
        case .grams, .millilitres:
            amountForPer100Calculation = clampedAmount
        case .serving:
            amountForPer100Calculation = clampedAmount * max(food.servingSize ?? 100, 0)
        }

        let multiplier = amountForPer100Calculation / 100

        return NutritionMacroSnapshot(
            calories: scaled(food.caloriesPer100g, multiplier: multiplier),
            protein: scaled(food.proteinPer100g, multiplier: multiplier),
            carbs: scaled(food.carbsPer100g, multiplier: multiplier),
            fat: scaled(food.fatPer100g, multiplier: multiplier),
            sugar: scaledOptional(food.sugarPer100g, multiplier: multiplier),
            fibre: scaledOptional(food.fibrePer100g, multiplier: multiplier),
            salt: scaledOptional(food.saltPer100g, multiplier: multiplier)
        )
    }

    func totals(from entries: [FoodLogEntry]) -> NutritionMacroSnapshot {
        NutritionMacroSnapshot(
            calories: entries.reduce(0) { $0 + $1.caloriesSnapshot },
            protein: entries.reduce(0) { $0 + $1.proteinSnapshot },
            carbs: entries.reduce(0) { $0 + $1.carbsSnapshot },
            fat: entries.reduce(0) { $0 + $1.fatSnapshot },
            sugar: optionalTotal(entries.map(\.sugarSnapshot)),
            fibre: optionalTotal(entries.map(\.fibreSnapshot)),
            salt: optionalTotal(entries.map(\.saltSnapshot))
        )
    }

    private func scaled(_ value: Double?, multiplier: Double) -> Double {
        max(value ?? 0, 0) * multiplier
    }

    private func scaledOptional(_ value: Double?, multiplier: Double) -> Double? {
        guard let value else { return nil }
        return max(value, 0) * multiplier
    }

    private func optionalTotal(_ values: [Double?]) -> Double? {
        let presentValues = values.compactMap { $0 }
        guard !presentValues.isEmpty else { return nil }
        return presentValues.reduce(0, +)
    }
}
