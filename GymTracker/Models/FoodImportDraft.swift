import Foundation

struct FoodImportDraft: Identifiable, Hashable {
    let id = UUID()
    var barcode: String
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
    var rawOCRText: String? = nil
    var nutritionParseResult: NutritionParseResult? = nil

    var hasCoreMacros: Bool {
        caloriesPer100g != nil || proteinPer100g != nil || carbsPer100g != nil || fatPer100g != nil
    }

    var isIncomplete: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasCoreMacros
    }
}
