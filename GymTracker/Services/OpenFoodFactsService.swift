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
        try await PerformanceTracer.traceAsync(.openFoodFactsRequest) {
            try await productDraftUntraced(for: barcode)
        }
    }

    private func productDraftUntraced(for barcode: String) async throws -> FoodImportDraft {
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
        request.setValue("Peakline/1.0 (personal iOS nutrition app)", forHTTPHeaderField: "User-Agent")
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
    let energyKcalServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?
    let sugars100g: Double?
    let sugarsServing: Double?
    let fiber100g: Double?
    let fibre100g: Double?
    let fiberServing: Double?
    let fibreServing: Double?
    let salt100g: Double?
    let saltServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case sugars100g = "sugars_100g"
        case sugarsServing = "sugars_serving"
        case fiber100g = "fiber_100g"
        case fibre100g = "fibre_100g"
        case fiberServing = "fiber_serving"
        case fibreServing = "fibre_serving"
        case salt100g = "salt_100g"
        case saltServing = "salt_serving"
    }
}

struct OpenFoodFactsMapper {
    func draft(from response: OpenFoodFactsProductResponse, product: OpenFoodFactsProductDTO) -> FoodImportDraft {
        let servingInfo = servingSize(from: product.servingSize) ?? servingSize(from: product.quantity)
        let nutriments = product.nutriments
        let baseUnit = foodBaseUnit(for: servingInfo)

        return FoodImportDraft(
            barcode: BarcodeFoodLookupService.normalizedBarcode(response.code ?? ""),
            name: product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            brand: cleaned(product.brands),
            servingSize: servingInfo?.amount,
            baseUnit: baseUnit,
            caloriesPer100g: mappedPer100Value(nutriments?.energyKcal100g, servingValue: nutriments?.energyKcalServing, servingInfo: servingInfo),
            proteinPer100g: mappedPer100Value(nutriments?.proteins100g, servingValue: nutriments?.proteinsServing, servingInfo: servingInfo),
            carbsPer100g: mappedPer100Value(nutriments?.carbohydrates100g, servingValue: nutriments?.carbohydratesServing, servingInfo: servingInfo),
            fatPer100g: mappedPer100Value(nutriments?.fat100g, servingValue: nutriments?.fatServing, servingInfo: servingInfo),
            sugarPer100g: mappedPer100Value(nutriments?.sugars100g, servingValue: nutriments?.sugarsServing, servingInfo: servingInfo),
            fibrePer100g: mappedPer100Value(nutriments?.fiber100g ?? nutriments?.fibre100g, servingValue: nutriments?.fiberServing ?? nutriments?.fibreServing, servingInfo: servingInfo),
            saltPer100g: mappedPer100Value(nutriments?.salt100g, servingValue: nutriments?.saltServing, servingInfo: servingInfo),
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
            return .grams
        case .millilitres:
            return .millilitres
        case .serving:
            return .serving
        }
    }

    private func mappedPer100Value(
        _ per100Value: Double?,
        servingValue: Double?,
        servingInfo: (amount: Double, unit: FoodAmountUnit)?
    ) -> Double? {
        if let sanitized = NutritionDataIntegrityService.sanitizedNonNegative(per100Value) {
            return sanitized
        }

        guard
            let serving = NutritionDataIntegrityService.sanitizedNonNegative(servingValue),
            let servingInfo,
            servingInfo.amount > 0,
            servingInfo.unit == .grams || servingInfo.unit == .millilitres
        else {
            return nil
        }

        return serving / (servingInfo.amount / 100)
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
