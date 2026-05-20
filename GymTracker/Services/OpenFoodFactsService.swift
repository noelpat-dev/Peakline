import Foundation

enum OpenFoodFactsError: LocalizedError {
    case invalidBarcode
    case invalidResponse
    case productNotFound
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "Enter a valid barcode."
        case .invalidResponse:
            return "Open Food Facts returned an unexpected response."
        case .productNotFound:
            return "No Open Food Facts product matched this barcode."
        case .httpStatus(let code):
            return "Open Food Facts returned HTTP \(code)."
        }
    }
}

struct OpenFoodFactsService {
    private let session: URLSession
    private let baseURL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func productDraft(for barcode: String) async throws -> FoodImportDraft {
        let normalizedBarcode = BarcodeFoodLookupService.normalizedBarcode(barcode)
        guard !normalizedBarcode.isEmpty else {
            throw OpenFoodFactsError.invalidBarcode
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(normalizedBarcode).json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,status,status_verbose,product_name,brands,quantity,serving_size,nutriments,image_front_url,ingredients_text,allergens_tags,nutrition_grades"
            )
        ]

        guard let url = components?.url else {
            throw OpenFoodFactsError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.setValue("GymTracker/1.0 (personal iOS nutrition app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenFoodFactsError.httpStatus(httpResponse.statusCode)
        }

        let productResponse = try JSONDecoder().decode(OpenFoodFactsProductResponse.self, from: data)
        guard productResponse.status == 1, let product = productResponse.product else {
            throw OpenFoodFactsError.productNotFound
        }

        return OpenFoodFactsMapper().draft(from: productResponse, product: product)
    }
}

struct OpenFoodFactsProductResponse: Decodable {
    let code: String?
    let status: Int
    let statusVerbose: String?
    let product: OpenFoodFactsProductDTO?

    enum CodingKeys: String, CodingKey {
        case code
        case status
        case statusVerbose = "status_verbose"
        case product
    }
}

struct OpenFoodFactsProductDTO: Decodable {
    let productName: String?
    let brands: String?
    let quantity: String?
    let servingSize: String?
    let nutriments: OpenFoodFactsNutrimentsDTO?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case quantity
        case servingSize = "serving_size"
        case nutriments
    }
}

struct OpenFoodFactsNutrimentsDTO: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let sugars100g: Double?
    let fiber100g: Double?
    let fibre100g: Double?
    let salt100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case sugars100g = "sugars_100g"
        case fiber100g = "fiber_100g"
        case fibre100g = "fibre_100g"
        case salt100g = "salt_100g"
    }
}

struct OpenFoodFactsMapper {
    func draft(from response: OpenFoodFactsProductResponse, product: OpenFoodFactsProductDTO) -> FoodImportDraft {
        let servingInfo = servingSize(from: product.servingSize) ?? servingSize(from: product.quantity)
        let nutriments = product.nutriments
        let baseUnit = foodBaseUnit(for: servingInfo)
        let servingMultiplier = max(servingInfo?.amount ?? 0, 0) / 100

        return FoodImportDraft(
            barcode: BarcodeFoodLookupService.normalizedBarcode(response.code ?? ""),
            name: product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            brand: cleaned(product.brands),
            servingSize: servingInfo?.amount,
            baseUnit: baseUnit,
            caloriesPer100g: mappedNutritionValue(nutriments?.energyKcal100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            proteinPer100g: mappedNutritionValue(nutriments?.proteins100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            carbsPer100g: mappedNutritionValue(nutriments?.carbohydrates100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            fatPer100g: mappedNutritionValue(nutriments?.fat100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            sugarPer100g: mappedNutritionValue(nutriments?.sugars100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            fibrePer100g: mappedNutritionValue(nutriments?.fiber100g ?? nutriments?.fibre100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            saltPer100g: mappedNutritionValue(nutriments?.salt100g, baseUnit: baseUnit, servingMultiplier: servingMultiplier),
            source: .openFoodFacts
        )
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func foodBaseUnit(for servingInfo: (amount: Double, unit: FoodAmountUnit)?) -> FoodAmountUnit {
        guard let servingInfo else { return .grams }

        switch servingInfo.unit {
        case .grams:
            return .serving
        case .millilitres:
            return .millilitres
        case .serving:
            return .serving
        }
    }

    private func mappedNutritionValue(_ value: Double?, baseUnit: FoodAmountUnit, servingMultiplier: Double) -> Double? {
        guard let sanitized = NutritionDataIntegrityService.sanitizedNonNegative(value) else { return nil }
        guard baseUnit == .serving, servingMultiplier > 0 else { return sanitized }
        return sanitized * servingMultiplier
    }

    private func servingSize(from text: String?) -> (amount: Double, unit: FoodAmountUnit)? {
        guard let text else { return nil }
        let lowercased = text.lowercased()
        guard let amount = firstNumber(in: lowercased) else { return nil }

        if lowercased.contains("ml") {
            return (amount, .millilitres)
        }

        return (amount, .grams)
    }

    private func firstNumber(in text: String) -> Double? {
        let pattern = #"([0-9]+(?:[\.,][0-9]+)?)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }
}
