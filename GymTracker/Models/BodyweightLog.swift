import Foundation
import SwiftData

@Model
final class BodyweightLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weight: Double
    var unit: UnitSystem
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weight: Double,
        unit: UnitSystem,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.unit = unit
        self.notes = notes
    }
}
