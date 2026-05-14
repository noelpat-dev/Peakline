import Foundation

protocol DisplayableEnum: RawRepresentable, CaseIterable, Identifiable where RawValue == String {
    var displayName: String { get }
}

extension DisplayableEnum {
    var id: String { rawValue }
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

enum TrainingGoal: String, Codable, DisplayableEnum {
    case strength
    case hypertrophy
    case fatLoss
    case generalFitness
    case sportPerformance
}

enum ExperienceLevel: String, Codable, DisplayableEnum {
    case beginner
    case intermediate
    case advanced
    case unsure
}

enum SplitType: String, Codable, DisplayableEnum {
    case pushPullLegs
    case upperLower
    case fullBody
    case broSplit
    case custom
}

enum UnitSystem: String, Codable, DisplayableEnum {
    case metric
    case imperial
}

enum MuscleGroup: String, Codable, DisplayableEnum {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case fullBody
    case other
}

enum MovementPattern: String, Codable, DisplayableEnum {
    case push
    case pull
    case squat
    case hinge
    case carry
    case isolation
    case core
    case other
}

enum EquipmentType: String, Codable, DisplayableEnum {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case smithMachine
    case other
}

enum RecommendationType: String, Codable, DisplayableEnum {
    case nextSplit
    case increaseWeight
    case repeatWeight
    case reduceWeight
    case deload
    case missedSplit
    case plateau
    case volumeWarning
    case consistency
    case recovery
}
