import Foundation

enum ExerciseSubstitutionReason: String, CaseIterable, Identifiable {
    case equipmentBusy
    case exerciseHurts
    case noTime
    case preferAlternative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equipmentBusy:
            return "Equipment busy"
        case .exerciseHurts:
            return "Exercise hurts"
        case .noTime:
            return "No time"
        case .preferAlternative:
            return "Prefer alternative"
        }
    }
}

struct ExerciseSubstitutionService {
    func alternatives(for exerciseId: UUID, in exercises: [Exercise], limit: Int = 6) -> [Exercise] {
        guard let source = exercises.first(where: { $0.id == exerciseId }) else { return [] }

        return exercises
            .filter { $0.id != exerciseId && !$0.isArchived }
            .map { candidate in
                (exercise: candidate, score: score(candidate, against: source))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.exercise.name < $1.exercise.name
                }

                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.exercise)
    }

    private func score(_ candidate: Exercise, against source: Exercise) -> Int {
        var score = 0

        if candidate.primaryMuscleGroup == source.primaryMuscleGroup {
            score += 4
        }

        if candidate.movementPattern == source.movementPattern {
            score += 3
        }

        if candidate.isCompound == source.isCompound {
            score += 1
        }

        if candidate.equipment != source.equipment {
            score += 1
        }

        if !Set(candidate.secondaryMuscleGroups).isDisjoint(with: Set(source.secondaryMuscleGroups)) {
            score += 1
        }

        return score
    }
}
