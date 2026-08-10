import Foundation

enum ExerciseSubstitutionReason: String, Codable, CaseIterable, Identifiable {
    case equipmentBusy
    case painOrDiscomfort
    case noTime
    case preferAlternative
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equipmentBusy:
            return "Equipment busy"
        case .painOrDiscomfort:
            return "Pain / discomfort"
        case .noTime:
            return "No time"
        case .preferAlternative:
            return "Prefer alternative"
        case .other:
            return "Other"
        }
    }
}

struct ExerciseSubstitutionCandidate: Identifiable, Equatable {
    var id: String { exerciseName }
    let exerciseName: String
    let exerciseId: UUID
    let primaryMuscle: String?
    let equipment: String?
    let movementPattern: String?
    let score: Double
    let reason: String
    let iconKey: ExerciseIconKey?
}

struct ExerciseSubstitutionService {
    func alternatives(for exerciseId: UUID, in exercises: [Exercise], limit: Int = 6) -> [Exercise] {
        candidates(for: exerciseId, in: exercises, usedExerciseIDs: [], reason: nil, limit: limit)
            .compactMap { candidate in
                exercises.first { $0.id == candidate.exerciseId }
            }
    }

    func candidates(
        for exerciseId: UUID,
        in exercises: [Exercise],
        completedSessions: [WorkoutSession],
        reason substitutionReason: ExerciseSubstitutionReason?,
        limit: Int = 8
    ) -> [ExerciseSubstitutionCandidate] {
        let usedExerciseIDs = Set(
            completedSessions.flatMap { session in
                session.exerciseLogs.map(\.exerciseId)
            }
        )

        return candidates(
            for: exerciseId,
            in: exercises,
            usedExerciseIDs: usedExerciseIDs,
            reason: substitutionReason,
            limit: limit
        )
    }

    func candidates(
        for exerciseId: UUID,
        in exercises: [Exercise],
        usedExerciseIDs: Set<UUID>,
        reason substitutionReason: ExerciseSubstitutionReason?,
        limit: Int = 8
    ) -> [ExerciseSubstitutionCandidate] {
        guard let source = exercises.first(where: { $0.id == exerciseId }) else { return [] }

        return exercises
            .filter { $0.id != exerciseId && !$0.isArchived }
            .map { candidate in
                candidateDTO(
                    candidate,
                    source: source,
                    score: score(candidate, against: source, usedExerciseIDs: usedExerciseIDs, substitutionReason: substitutionReason)
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.exerciseName < $1.exerciseName
                }

                return $0.score > $1.score
            }
            .prefix(limit)
            .filter { $0.score > 0 }
    }

    func substitutionNote(originalName: String, replacementName: String, reason: ExerciseSubstitutionReason) -> String {
        "[Substitution: \(replacementName) replaced \(originalName) - \(reason.displayName)]"
    }

    private func score(
        _ candidate: Exercise,
        against source: Exercise,
        usedExerciseIDs: Set<UUID>,
        substitutionReason: ExerciseSubstitutionReason?
    ) -> Double {
        var score: Double = 0

        if candidate.primaryMuscleGroup == source.primaryMuscleGroup {
            score += 50
        }

        if candidate.movementPattern == source.movementPattern {
            score += 25
        }

        if candidate.isCompound == source.isCompound {
            score += 10
        }

        if candidate.equipment == source.equipment {
            score += substitutionReason == .equipmentBusy ? 4 : 15
        } else if substitutionReason == .equipmentBusy {
            score += 12
        }

        if !Set(candidate.secondaryMuscleGroups).isDisjoint(with: Set(source.secondaryMuscleGroups)) {
            score += 8
        }

        if usedExerciseIDs.contains(candidate.id) {
            score += 10
        }

        if substitutionReason == .painOrDiscomfort, candidate.movementPattern != source.movementPattern {
            score -= 6
        }

        return score
    }

    private func candidateDTO(_ candidate: Exercise, source: Exercise, score: Double) -> ExerciseSubstitutionCandidate {
        let reason: String
        if candidate.primaryMuscleGroup == source.primaryMuscleGroup && candidate.movementPattern == source.movementPattern {
            reason = "Same muscle and movement pattern."
        } else if candidate.primaryMuscleGroup == source.primaryMuscleGroup {
            reason = "Same primary muscle with a different setup."
        } else if candidate.movementPattern == source.movementPattern {
            reason = "Similar movement pattern."
        } else {
            reason = "Closest available library match."
        }

        return ExerciseSubstitutionCandidate(
            exerciseName: candidate.name,
            exerciseId: candidate.id,
            primaryMuscle: candidate.primaryMuscleGroup.displayName,
            equipment: candidate.equipment.displayName,
            movementPattern: candidate.movementPattern.displayName,
            score: score,
            reason: reason,
            iconKey: ExerciseIconMapper.iconKey(forName: candidate.name)
        )
    }
}
