import Foundation

enum BarcodeLookupState: Equatable {
    case idle
    case checkingLocal(String)
    case fetchingRemote(String)
    case localFound(FoodItem)
    case remoteFound(FoodImportDraft)
    case remoteIncomplete(FoodImportDraft)
    case notFound(barcode: String)
    case error(message: String, barcode: String?)

    static func == (lhs: BarcodeLookupState, rhs: BarcodeLookupState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.checkingLocal(let lhsBarcode), .checkingLocal(let rhsBarcode)):
            return lhsBarcode == rhsBarcode
        case (.fetchingRemote(let lhsBarcode), .fetchingRemote(let rhsBarcode)):
            return lhsBarcode == rhsBarcode
        case (.localFound(let lhsFood), .localFound(let rhsFood)):
            return lhsFood.id == rhsFood.id
        case (.remoteFound(let lhsDraft), .remoteFound(let rhsDraft)):
            return lhsDraft == rhsDraft
        case (.remoteIncomplete(let lhsDraft), .remoteIncomplete(let rhsDraft)):
            return lhsDraft == rhsDraft
        case (.notFound(let lhsBarcode), .notFound(let rhsBarcode)):
            return lhsBarcode == rhsBarcode
        case (.error(let lhsMessage, let lhsBarcode), .error(let rhsMessage, let rhsBarcode)):
            return lhsMessage == rhsMessage && lhsBarcode == rhsBarcode
        default:
            return false
        }
    }
}

struct BarcodeFoodLookupService {
    private let openFoodFactsService: OpenFoodFactsService

    init(openFoodFactsService: OpenFoodFactsService = OpenFoodFactsService()) {
        self.openFoodFactsService = openFoodFactsService
    }

    func lookupRemote(barcode rawBarcode: String) async -> BarcodeLookupState {
        await PerformanceTracer.traceAsync(.barcodeLookup) {
            await lookupRemoteUntraced(barcode: rawBarcode)
        }
    }

    private func lookupRemoteUntraced(barcode rawBarcode: String) async -> BarcodeLookupState {
        let barcode = Self.normalizedBarcode(rawBarcode)
        guard !barcode.isEmpty else {
            return .error(message: "Enter a valid barcode.", barcode: nil)
        }

        do {
            var draft = try await openFoodFactsService.productDraft(for: barcode)
            if draft.barcode.isEmpty {
                draft.barcode = barcode
            }
            return draft.isIncomplete ? .remoteIncomplete(draft) : .remoteFound(draft)
        } catch OpenFoodFactsError.productNotFound {
            return .notFound(barcode: barcode)
        } catch {
            return .error(message: error.localizedDescription, barcode: barcode)
        }
    }

    func findLocalFood(by rawBarcode: String, in localFoods: [FoodItem]) -> FoodItem? {
        let barcode = Self.normalizedBarcode(rawBarcode)
        return localFoods.first { food in
            guard let storedBarcode = food.barcode else { return false }
            return Self.normalizedBarcode(storedBarcode) == barcode
        }
    }

    static func normalizedBarcode(_ barcode: String) -> String {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly = trimmed.filter(\.isNumber)

        // UPC-A can arrive as EAN-13 with a leading zero. Keep the first pass stable:
        // store and compare the scanned digit sequence without converting formats.
        return digitsOnly.isEmpty ? trimmed : String(digitsOnly)
    }
}
