import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var goal: TrainingGoal
    var experienceLevel: ExperienceLevel
    var liftingStartDate: Date?
    var trainingDaysPerWeek: Int
    var preferredSplitType: SplitType
    var bodyweight: Double?
    var unitSystem: UnitSystem
    var injuryNotes: String?
    var exercisesToAvoid: [String]
    var notificationsEnabled: Bool
    var dailyCheckInTime: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        goal: TrainingGoal = .hypertrophy,
        experienceLevel: ExperienceLevel = .beginner,
        liftingStartDate: Date? = nil,
        trainingDaysPerWeek: Int = 3,
        preferredSplitType: SplitType = .pushPullLegs,
        bodyweight: Double? = nil,
        unitSystem: UnitSystem = .metric,
        injuryNotes: String? = nil,
        exercisesToAvoid: [String] = [],
        notificationsEnabled: Bool = false,
        dailyCheckInTime: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.goal = goal
        self.experienceLevel = experienceLevel
        self.liftingStartDate = liftingStartDate
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.preferredSplitType = preferredSplitType
        self.bodyweight = bodyweight
        self.unitSystem = unitSystem
        self.injuryNotes = injuryNotes
        self.exercisesToAvoid = exercisesToAvoid
        self.notificationsEnabled = notificationsEnabled
        self.dailyCheckInTime = dailyCheckInTime
    }
}
