import Foundation
import SwiftData

struct LocalBackupImportSummary: Equatable {
    let workoutCount: Int
    let exerciseCount: Int
    let splitCount: Int
    let importedAt: Date
}

@MainActor
struct LocalBackupImportService {
    private let exportService = LocalBackupExportService()

    func importBackup(
        from data: Data,
        into context: ModelContext,
        replaceSeedDataWhenNoWorkouts: Bool = false
    ) throws -> LocalBackupImportSummary {
        let envelope = try exportService.decodeEnvelope(from: data)
        return try importBackup(
            envelope,
            into: context,
            replaceSeedDataWhenNoWorkouts: replaceSeedDataWhenNoWorkouts
        )
    }

    func importBackup(
        _ envelope: PeaklineExportEnvelope,
        into context: ModelContext,
        replaceSeedDataWhenNoWorkouts: Bool = false
    ) throws -> LocalBackupImportSummary {
        do {
            if replaceSeedDataWhenNoWorkouts {
                try removeStarterDataIfSafe(for: envelope, in: context)
            }

            try importExercises(envelope.exercises, into: context)
            try importSplits(envelope.splits, into: context)
            try importWorkouts(envelope.workouts, into: context)
            try TrainingRotationService().normalizePersistedRotation(in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        if envelope.workouts.contains(where: \.completed) {
            WorkoutWarmStartInvalidation.shared.invalidate(reason: .importedWorkouts)
        }

        return LocalBackupImportSummary(
            workoutCount: envelope.workouts.count,
            exerciseCount: envelope.exercises.count,
            splitCount: envelope.splits.count,
            importedAt: Date()
        )
    }

    private func removeStarterDataIfSafe(for envelope: PeaklineExportEnvelope, in context: ModelContext) throws {
        guard !envelope.workouts.isEmpty else { return }
        let existingWorkoutCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        guard existingWorkoutCount == 0 else { return }

        try context.fetch(FetchDescriptor<TrainingSplit>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Exercise>()).forEach(context.delete)
        try context.save()
    }

    private func importExercises(_ dtos: [ExerciseExportDTO], into context: ModelContext) throws {
        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        var exercisesByID = Dictionary(uniqueKeysWithValues: existingExercises.map { ($0.id, $0) })

        for dto in dtos {
            let exercise = exercisesByID[dto.id] ?? Exercise(
                id: dto.id,
                name: dto.name,
                primaryMuscleGroup: muscleGroup(dto.primaryMuscleGroup),
                secondaryMuscleGroups: dto.secondaryMuscleGroups.map(muscleGroup),
                movementPattern: movementPattern(dto.movementPattern),
                equipment: equipment(dto.equipment),
                isCompound: dto.isCompound,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )

            exercise.name = dto.name
            exercise.primaryMuscleGroup = muscleGroup(dto.primaryMuscleGroup)
            exercise.secondaryMuscleGroups = dto.secondaryMuscleGroups.map(muscleGroup)
            exercise.movementPattern = movementPattern(dto.movementPattern)
            exercise.equipment = equipment(dto.equipment)
            exercise.isCompound = dto.isCompound
            exercise.isArchived = dto.isArchived
            exercise.createdAt = dto.createdAt
            exercise.updatedAt = dto.updatedAt

            if exercisesByID[dto.id] == nil {
                context.insert(exercise)
                exercisesByID[dto.id] = exercise
            }
        }
    }

    private func importSplits(_ dtos: [TrainingSplitExportDTO], into context: ModelContext) throws {
        let existingSplits = try context.fetch(FetchDescriptor<TrainingSplit>())
        var splitsByID = Dictionary(uniqueKeysWithValues: existingSplits.map { ($0.id, $0) })

        for dto in dtos {
            let split = splitsByID[dto.id] ?? TrainingSplit(
                id: dto.id,
                name: dto.name,
                splitType: splitType(dto.splitType),
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                isActive: dto.isActive,
                activeRotationIndex: dto.activeRotationIndex,
                daysPerWeek: dto.daysPerWeek
            )

            split.name = dto.name
            split.splitType = splitType(dto.splitType)
            split.createdAt = dto.createdAt
            split.updatedAt = dto.updatedAt
            split.isActive = dto.isActive
            split.activeRotationIndex = dto.activeRotationIndex
            split.daysPerWeek = dto.daysPerWeek

            let existingChildrenByID = Dictionary(uniqueKeysWithValues: split.exercises.map { ($0.id, $0) })
            let importedChildren = dto.exercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { childDTO in
                    let child = existingChildrenByID[childDTO.id] ?? SplitExercise(
                        id: childDTO.id,
                        splitId: split.id,
                        exerciseId: childDTO.exerciseId,
                        exerciseNameSnapshot: childDTO.exerciseName,
                        orderIndex: childDTO.orderIndex,
                        targetSets: childDTO.targetSets,
                        minReps: childDTO.minReps,
                        maxReps: childDTO.maxReps,
                        restSeconds: childDTO.restSeconds,
                        notes: childDTO.notes
                    )
                    child.splitId = split.id
                    child.exerciseId = childDTO.exerciseId
                    child.exerciseNameSnapshot = childDTO.exerciseName
                    child.orderIndex = childDTO.orderIndex
                    child.targetSets = childDTO.targetSets
                    child.minReps = childDTO.minReps
                    child.maxReps = childDTO.maxReps
                    child.restSeconds = childDTO.restSeconds
                    child.notes = childDTO.notes
                    child.split = split
                    return child
                }

            let importedChildIDs = Set(importedChildren.map(\.id))
            for child in split.exercises where !importedChildIDs.contains(child.id) {
                context.delete(child)
            }
            split.exercises = importedChildren

            if splitsByID[dto.id] == nil {
                context.insert(split)
                splitsByID[dto.id] = split
            }
        }
    }

    private func importWorkouts(_ dtos: [WorkoutSessionExportDTO], into context: ModelContext) throws {
        let existingWorkouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        var workoutsByID = Dictionary(uniqueKeysWithValues: existingWorkouts.map { ($0.id, $0) })

        for dto in dtos {
            let session = workoutsByID[dto.id] ?? WorkoutSession(
                id: dto.id,
                date: dto.date,
                splitId: dto.splitId,
                splitNameSnapshot: dto.splitName,
                startedAt: dto.startedAt,
                endedAt: dto.endedAt,
                durationMinutes: dto.durationMinutes,
                durationSeconds: dto.durationSeconds,
                pausedAt: dto.pausedAt,
                accumulatedPausedSeconds: dto.accumulatedPausedSeconds ?? 0,
                perceivedDifficulty: dto.perceivedDifficulty,
                energyLevel: dto.energyLevel,
                sorenessLevel: dto.sorenessLevel,
                notes: dto.notes,
                completed: dto.completed
            )

            session.date = dto.date
            session.splitId = dto.splitId
            session.splitNameSnapshot = dto.splitName
            session.startedAt = dto.startedAt ?? dto.date
            session.endedAt = dto.endedAt
            session.durationMinutes = dto.durationMinutes
            session.durationSeconds = dto.durationSeconds
            session.pausedAt = dto.pausedAt
            session.accumulatedPausedSeconds = dto.accumulatedPausedSeconds ?? 0
            session.perceivedDifficulty = dto.perceivedDifficulty
            session.energyLevel = dto.energyLevel
            session.sorenessLevel = dto.sorenessLevel
            session.notes = dto.notes
            session.completed = dto.completed

            let existingLogsByID = Dictionary(uniqueKeysWithValues: session.exerciseLogs.map { ($0.id, $0) })
            let importedLogs = dto.exerciseLogs
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { logDTO in
                    makeExerciseLog(from: logDTO, session: session, existingLogsByID: existingLogsByID, context: context)
                }

            let importedLogIDs = Set(importedLogs.map(\.id))
            for log in session.exerciseLogs where !importedLogIDs.contains(log.id) {
                context.delete(log)
            }
            session.exerciseLogs = importedLogs

            if workoutsByID[dto.id] == nil {
                context.insert(session)
                workoutsByID[dto.id] = session
            }
        }
    }

    private func makeExerciseLog(
        from dto: ExerciseLogExportDTO,
        session: WorkoutSession,
        existingLogsByID: [UUID: ExerciseLog],
        context: ModelContext
    ) -> ExerciseLog {
        let log = existingLogsByID[dto.id] ?? ExerciseLog(
            id: dto.id,
            workoutSessionId: session.id,
            exerciseId: dto.exerciseId,
            exerciseNameSnapshot: dto.exerciseName,
            orderIndex: dto.orderIndex,
            targetSets: dto.targetSets,
            minReps: dto.minReps,
            maxReps: dto.maxReps,
            notes: dto.notes
        )

        log.workoutSessionId = session.id
        log.exerciseId = dto.exerciseId
        log.exerciseNameSnapshot = dto.exerciseName
        log.orderIndex = dto.orderIndex
        log.targetSets = dto.targetSets
        log.minReps = dto.minReps
        log.maxReps = dto.maxReps
        log.notes = dto.notes
        log.workoutSession = session

        let existingSetsByID = Dictionary(uniqueKeysWithValues: log.setLogs.map { ($0.id, $0) })
        let importedSets = dto.setLogs
            .sorted { $0.setNumber < $1.setNumber }
            .map { setDTO in
                let set = existingSetsByID[setDTO.id] ?? SetLog(
                    id: setDTO.id,
                    exerciseLogId: log.id,
                    setNumber: setDTO.setNumber,
                    weight: setDTO.weight,
                    reps: setDTO.reps,
                    rpe: setDTO.rpe,
                    isWarmup: setDTO.isWarmup,
                    completed: setDTO.completed
                )
                set.exerciseLogId = log.id
                set.setNumber = setDTO.setNumber
                set.weight = setDTO.weight
                set.reps = setDTO.reps
                set.rpe = setDTO.rpe
                set.isWarmup = setDTO.isWarmup
                set.completed = setDTO.completed
                set.exerciseLog = log
                return set
            }

        let importedSetIDs = Set(importedSets.map(\.id))
        for set in log.setLogs where !importedSetIDs.contains(set.id) {
            context.delete(set)
        }
        log.setLogs = importedSets

        return log
    }

    private func muscleGroup(_ rawValue: String) -> MuscleGroup {
        MuscleGroup(rawValue: rawValue) ?? .other
    }

    private func movementPattern(_ rawValue: String) -> MovementPattern {
        MovementPattern(rawValue: rawValue) ?? .other
    }

    private func equipment(_ rawValue: String) -> EquipmentType {
        EquipmentType(rawValue: rawValue) ?? .other
    }

    private func splitType(_ rawValue: String) -> SplitType {
        SplitType(rawValue: rawValue) ?? .custom
    }
}
