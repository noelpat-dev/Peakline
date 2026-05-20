import Foundation

struct NutritionDataIntegrityService {
    func existingFood(
        matchingBarcode barcode: String?,
        in foods: [FoodItem],
        excluding excludedFoodId: UUID? = nil
    ) -> FoodItem? {
        let normalizedBarcode = BarcodeFoodLookupService.normalizedBarcode(barcode ?? "")
        guard !normalizedBarcode.isEmpty else { return nil }

        return foods.first { food in
            if let excludedFoodId, food.id == excludedFoodId {
                return false
            }
            return BarcodeFoodLookupService.normalizedBarcode(food.barcode ?? "") == normalizedBarcode
        }
    }

    func duplicateBarcodeMessage(for food: FoodItem) -> String {
        "This barcode is already saved locally as \(food.name). Use the saved version or edit that food instead of creating a duplicate."
    }

    func per100NutritionWarning(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        sugar: Double?,
        fibre: Double?,
        salt: Double?,
        baseUnit: FoodAmountUnit
    ) -> String? {
        let basis: String
        switch baseUnit {
        case .grams:
            basis = "per 100g"
        case .millilitres:
            basis = "per 100ml"
        case .serving:
            basis = "per serving"
        }

        if (calories ?? 0) > 900 {
            return "Calories look unusually high \(basis). Check the label before saving."
        }

        if [protein, carbs, fat, sugar, fibre].compactMap({ $0 }).contains(where: { $0 > 100 }) {
            return "One macro is above 100g \(basis). Check the label before saving."
        }

        if (salt ?? 0) > 10 {
            return "Salt looks unusually high \(basis). Check the label before saving."
        }

        return nil
    }

    static func parseOptionalNonNegative(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return .some(value)
    }

    static func sanitizedNonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
