import CoreGraphics
import Foundation

struct NutritionOCRLine: Identifiable, Equatable {
    let id: UUID
    let text: String
    let confidence: Float?
    let boundingBox: CGRect?

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float? = nil,
        boundingBox: CGRect? = nil
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct NutritionOCRResult: Equatable {
    let rawText: String
    let lines: [NutritionOCRLine]
    let processedAt: Date
}

enum NutritionLabelOCRError: LocalizedError, Equatable {
    case invalidImage
    case noTextDetected
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "GymTracker could not read that image."
        case .noTextDetected:
            return "No readable nutrition label text was detected."
        case .requestFailed(let message):
            return message
        }
    }
}
