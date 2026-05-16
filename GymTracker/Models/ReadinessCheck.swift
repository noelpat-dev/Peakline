import Foundation
import SwiftData

@Model
final class ReadinessCheck {
    @Attribute(.unique) var id: UUID
    var date: Date
    var energyLevel: Int
    var sorenessLevel: Int
    var availableMinutes: Int
    var motivationLevel: Int

    init(
        id: UUID = UUID(),
        date: Date = .now,
        energyLevel: Int = ReadinessLevel.normal.rawValue,
        sorenessLevel: Int = SorenessLevel.mild.rawValue,
        availableMinutes: Int = 60,
        motivationLevel: Int = ReadinessLevel.normal.rawValue
    ) {
        self.id = id
        self.date = date
        self.energyLevel = energyLevel
        self.sorenessLevel = sorenessLevel
        self.availableMinutes = availableMinutes
        self.motivationLevel = motivationLevel
    }
}

enum ReadinessLevel: Int, CaseIterable, Identifiable {
    case low = 1
    case normal = 2
    case high = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }
}

enum SorenessLevel: Int, CaseIterable, Identifiable {
    case none = 1
    case mild = 2
    case high = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .mild:
            return "Mild"
        case .high:
            return "High"
        }
    }
}
