import Foundation
import SwiftData

@Model
final class Recommendation {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var type: RecommendationType
    var splitId: UUID?
    var exerciseId: UUID?
    var title: String
    var message: String
    var reason: String
    var confidence: Double
    var dismissed: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        type: RecommendationType,
        splitId: UUID? = nil,
        exerciseId: UUID? = nil,
        title: String,
        message: String,
        reason: String,
        confidence: Double,
        dismissed: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.splitId = splitId
        self.exerciseId = exerciseId
        self.title = title
        self.message = message
        self.reason = reason
        self.confidence = confidence
        self.dismissed = dismissed
    }
}
