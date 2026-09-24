import ActivityKit
import Foundation
import SwiftData

@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()

    enum EndReason: Equatable {
        case finished
        case discarded
    }

    private struct ActiveWorkout {
        let sessionID: UUID
        let exercisesByID: [UUID: Exercise]
        let bodyweightKg: Double
        let unitSystem: UnitSystem
        let previousBestE1RMByExercise: [UUID: Double]?
    }

    private struct PRFingerprint: Hashable {
        let setID: UUID
        let weightKg: Double
        let reps: Int
    }

    private var activity: Activity<WorkoutActivityAttributes>?
    private var activeWorkout: ActiveWorkout?
    private var activeSessionID: UUID?
    private var generation = UUID()
    private var currentSession: WorkoutSession?
    private var enteredSetIDs: Set<UUID> = []
    private var pendingChangedSetIDs: [UUID] = []
    private var currentRestEndsAt: Date?
    private var activePRFlash: WorkoutActivityAttributes.PRFlash?
    private var flashedPRFingerprints: Set<PRFingerprint> = []
    private var demoBaselineState: WorkoutActivityAttributes.ContentState?
    private var deadlineTask: Task<Void, Never>?
    private var updateThrottle = WorkoutLiveActivityUpdateThrottle()

    private init() {}

    /// Starts asynchronously so store reads and ActivityKit never delay the workout transition.
    func start(
        session: WorkoutSession,
        exercises: [Exercise],
        modelContext: ModelContext
    ) {
        guard activeSessionID != session.id else { return }

        resetForNewActivity()
        let requestGeneration = UUID()
        generation = requestGeneration
        activeSessionID = session.id
        currentSession = session

        Task { @MainActor [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                self.clearActiveWorkout(generation: requestGeneration)
                return
            }

            let historyReader = WorkoutLiveActivityHistoryReader(modelContainer: modelContext.container)
            let preparation = await historyReader.prepare(
                sessionID: session.id,
                sessionDate: session.date
            )
            guard self.generation == requestGeneration else { return }
            let unitSystem = UnitSystem(rawValue: preparation.unitSystem) ?? .metric
            let exercisesByID = Dictionary(
                exercises.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            self.activeWorkout = ActiveWorkout(
                sessionID: session.id,
                exercisesByID: exercisesByID,
                bodyweightKg: preparation.bodyweightKg,
                unitSystem: unitSystem,
                previousBestE1RMByExercise: preparation.previousBestE1RMByExercise
            )
            self.enteredSetIDs.formUnion(Self.persistedCompletedSetIDs(in: session))

            let pendingChangedSetIDs = self.pendingChangedSetIDs
            self.pendingChangedSetIDs.removeAll()
            if let latestSession = self.currentSession,
               let activeWorkout = self.activeWorkout {
                for setID in pendingChangedSetIDs {
                    self.capturePRIfNeeded(
                        changedSetID: setID,
                        session: latestSession,
                        activeWorkout: activeWorkout,
                        now: .now
                    )
                }
            }

            for existingActivity in Activity<WorkoutActivityAttributes>.activities {
                await existingActivity.end(nil, dismissalPolicy: .immediate)
            }
            guard self.generation == requestGeneration,
                  let latestSession = self.currentSession else { return }

            let now = Date()
            let initialState = self.makeCurrentState(for: latestSession, now: now)
            let attributes = WorkoutActivityAttributes(
                sessionID: latestSession.id,
                sessionTitle: latestSession.splitNameSnapshot,
                startedAt: latestSession.startedAt ?? latestSession.date
            )
            let content = ActivityContent(
                state: initialState,
                staleDate: WorkoutLiveActivityStateMapper.staleDate(for: initialState, now: now)
            )

            do {
                self.activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                self.updateThrottle.reset(initialState: initialState)
                self.scheduleDeadlineUpdate(for: requestGeneration)
            } catch {
                self.clearActiveWorkout(generation: requestGeneration)
            }
        }
    }

    /// Use for a set edit or rest-timer change. Call once after the action has updated its models.
    func update(
        session: WorkoutSession,
        restEndsAt: Date?,
        changedSetID: UUID? = nil
    ) {
        guard activeSessionID == session.id else { return }
        let requestGeneration = generation

        currentSession = session
        currentRestEndsAt = restEndsAt
        if let changedSetID {
            enteredSetIDs = WorkoutLiveActivityStateMapper.enteredSetIDs(
                afterEditing: changedSetID,
                in: session,
                previouslyEntered: enteredSetIDs
            )
            if activeWorkout == nil {
                pendingChangedSetIDs.append(changedSetID)
            }
        }

        Task { @MainActor [weak self] in
            guard let self,
                  self.generation == requestGeneration,
                  let activeWorkout = self.activeWorkout,
                  let latestSession = self.currentSession,
                  activeWorkout.sessionID == latestSession.id else { return }

            let now = Date()
            self.expireDeadlines(at: now)
            self.capturePRIfNeeded(
                changedSetID: changedSetID,
                session: latestSession,
                activeWorkout: activeWorkout,
                now: now
            )
            let state = self.makeCurrentState(for: latestSession, now: now)
            self.scheduleDeadlineUpdate(for: requestGeneration)
            await self.publish(state, generation: requestGeneration, now: now)
        }
    }

    func end(sessionID: UUID, reason: EndReason) {
        let dismissalPolicy: ActivityUIDismissalPolicy = reason == .discarded ? .immediate : .default
        if activeSessionID == sessionID {
            generation = UUID()
            resetForNewActivity()
        }

        Task { @MainActor in
            for existingActivity in Activity<WorkoutActivityAttributes>.activities
                where existingActivity.attributes.sessionID == sessionID {
                await existingActivity.end(nil, dismissalPolicy: dismissalPolicy)
            }
        }
    }

    #if DEBUG
    /// Board fixture for screenshots. A second invocation ends any previous demo before requesting one.
    func startDemo(resting: Bool, showingPR: Bool) {
        resetForNewActivity()
        let requestGeneration = UUID()
        generation = requestGeneration
        activeSessionID = nil
        let now = Date()
        currentRestEndsAt = resting ? now.addingTimeInterval(120) : nil

        let baseline = WorkoutActivityAttributes.ContentState(
            exerciseName: "Bench press",
            setIndexInExercise: 3,
            setsInExercise: 4,
            overallSetIndex: 7,
            overallSetCount: 18,
            completedSetCount: 6,
            exercisesLeft: 4,
            nextWeightKg: 100,
            nextReps: 5,
            restEndsAt: currentRestEndsAt,
            metresGained: 32,
            pr: nil,
            unitSystem: UnitSystem.metric.rawValue,
            pausedAt: nil,
            accumulatedPausedSeconds: 0
        )
        demoBaselineState = baseline

        if showingPR {
            let flash = WorkoutActivityAttributes.PRFlash(
                exerciseName: "Bench press",
                weightKg: 100,
                reps: 5,
                until: now.addingTimeInterval(WorkoutLiveActivityPRTracker.prFlashDuration)
            )
            activePRFlash = flash
        }

        let attributes = WorkoutActivityAttributes(
            sessionID: UUID(),
            sessionTitle: "PUSH · UPPER",
            startedAt: now.addingTimeInterval(-32 * 60)
        )
        Task { @MainActor [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                self.resetForNewActivity()
                return
            }

            for existingActivity in Activity<WorkoutActivityAttributes>.activities {
                await existingActivity.end(nil, dismissalPolicy: .immediate)
            }
            guard self.generation == requestGeneration else { return }

            do {
                let requestTime = Date()
                let state = self.demoState(from: baseline, now: requestTime)
                let content = ActivityContent(
                    state: state,
                    staleDate: WorkoutLiveActivityStateMapper.staleDate(for: state, now: requestTime)
                )
                self.activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                self.updateThrottle.reset(initialState: state)
                self.scheduleDeadlineUpdate(for: requestGeneration)
            } catch {
                self.resetForNewActivity()
            }
        }
    }

    func flashDemoPR() {
        guard let demoBaselineState, activity != nil else { return }
        let requestGeneration = generation
        let now = Date()
        activePRFlash = WorkoutActivityAttributes.PRFlash(
            exerciseName: "Bench press",
            weightKg: 100,
            reps: 5,
            until: now.addingTimeInterval(WorkoutLiveActivityPRTracker.prFlashDuration)
        )
        Task { @MainActor [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            await self.publish(
                self.demoState(from: demoBaselineState, now: now),
                generation: requestGeneration,
                now: now
            )
            self.scheduleDeadlineUpdate(for: requestGeneration)
        }
    }
    #endif

    private func capturePRIfNeeded(
        changedSetID: UUID?,
        session: WorkoutSession,
        activeWorkout: ActiveWorkout,
        now: Date
    ) {
        guard let changedSetID,
              enteredSetIDs.contains(changedSetID),
              let previousBest = activeWorkout.previousBestE1RMByExercise else { return }

        let currentSetInputs = WorkoutLiveActivityStateMapper.setInputs(
            from: session,
            exercisesByID: activeWorkout.exercisesByID,
            unitSystem: activeWorkout.unitSystem,
            enteredSetIDs: enteredSetIDs
        )
        guard let candidate = WorkoutLiveActivityPRTracker.newPRCandidate(
            for: changedSetID,
            currentSetInputs: currentSetInputs,
            previousBestE1RMByExercise: previousBest,
            bodyweightKg: activeWorkout.bodyweightKg
        ) else { return }

        let fingerprint = PRFingerprint(
            setID: candidate.id,
            weightKg: candidate.weightKg,
            reps: candidate.reps
        )
        guard flashedPRFingerprints.insert(fingerprint).inserted else { return }

        activePRFlash = WorkoutActivityAttributes.PRFlash(
            exerciseName: candidate.exerciseName,
            weightKg: candidate.weightKg,
            reps: candidate.reps,
            until: now.addingTimeInterval(WorkoutLiveActivityPRTracker.prFlashDuration)
        )
    }

    private func makeCurrentState(
        for session: WorkoutSession,
        now: Date
    ) -> WorkoutActivityAttributes.ContentState {
        guard let activeWorkout else {
            return demoState(from: demoBaselineState ?? Self.emptyDemoState(), now: now)
        }
        return WorkoutLiveActivityStateMapper.makeState(
            from: session,
            exercisesByID: activeWorkout.exercisesByID,
            enteredSetIDs: enteredSetIDs,
            bodyweightKg: activeWorkout.bodyweightKg,
            unitSystem: activeWorkout.unitSystem,
            restEndsAt: currentRestEndsAt,
            prFlash: activePRFlash,
            now: now
        )
    }

    private func demoState(
        from baseline: WorkoutActivityAttributes.ContentState,
        now: Date
    ) -> WorkoutActivityAttributes.ContentState {
        var state = baseline
        state.restEndsAt = currentRestEndsAt.flatMap { $0 > now ? $0 : nil }
        state.pr = activePRFlash.flatMap { $0.until > now ? $0 : nil }
        return state
    }

    private func publish(
        _ state: WorkoutActivityAttributes.ContentState,
        generation requestGeneration: UUID,
        now: Date
    ) async {
        guard generation == requestGeneration,
              let activity,
              updateThrottle.shouldSend(state) else { return }
        let content = ActivityContent(
            state: state,
            staleDate: WorkoutLiveActivityStateMapper.staleDate(for: state, now: now)
        )
        await activity.update(content)
    }

    private func scheduleDeadlineUpdate(for requestGeneration: UUID) {
        deadlineTask?.cancel()

        let deadlines = [activePRFlash?.until, currentRestEndsAt]
            .compactMap { $0 }
            .filter { $0 > Date() }
        guard let nextDeadline = deadlines.min() else {
            deadlineTask = nil
            return
        }

        let nanoseconds = UInt64(max(0, nextDeadline.timeIntervalSinceNow) * 1_000_000_000)
        deadlineTask = Task { @MainActor [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard let self,
                  !Task.isCancelled,
                  self.generation == requestGeneration else { return }

            let now = Date()
            self.expireDeadlines(at: now)
            if let session = self.currentSession {
                let state = self.makeCurrentState(for: session, now: now)
                await self.publish(state, generation: requestGeneration, now: now)
            } else if let demoBaselineState = self.demoBaselineState {
                let state = self.demoState(from: demoBaselineState, now: now)
                await self.publish(state, generation: requestGeneration, now: now)
            }
            self.scheduleDeadlineUpdate(for: requestGeneration)
        }
    }

    private func expireDeadlines(at now: Date) {
        if let activePRFlash, activePRFlash.until <= now {
            self.activePRFlash = nil
        }
        if let currentRestEndsAt, currentRestEndsAt <= now {
            self.currentRestEndsAt = nil
        }
    }

    private func resetForNewActivity() {
        deadlineTask?.cancel()
        deadlineTask = nil
        activeWorkout = nil
        activeSessionID = nil
        currentSession = nil
        enteredSetIDs.removeAll()
        pendingChangedSetIDs.removeAll()
        currentRestEndsAt = nil
        activePRFlash = nil
        flashedPRFingerprints.removeAll()
        demoBaselineState = nil
        activity = nil
        updateThrottle.reset()
    }

    private func clearActiveWorkout(generation requestGeneration: UUID) {
        guard generation == requestGeneration else { return }
        resetForNewActivity()
        generation = UUID()
    }

    private static func persistedCompletedSetIDs(in session: WorkoutSession) -> Set<UUID> {
        Set(
            session.exerciseLogs
                .flatMap(\.setLogs)
                .filter { $0.completed && !$0.isWarmup }
                .map(\.id)
        )
    }

    private static func emptyDemoState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: "Bench press",
            setIndexInExercise: 3,
            setsInExercise: 4,
            overallSetIndex: 7,
            overallSetCount: 18,
            completedSetCount: 6,
            exercisesLeft: 4,
            nextWeightKg: 100,
            nextReps: 5,
            restEndsAt: nil,
            metresGained: 32,
            pr: nil,
            unitSystem: UnitSystem.metric.rawValue,
            pausedAt: nil,
            accumulatedPausedSeconds: 0
        )
    }
}

private struct WorkoutLiveActivityPreparation: Sendable {
    let unitSystem: String
    let bodyweightKg: Double
    let previousBestE1RMByExercise: [UUID: Double]?
}

@ModelActor
private actor WorkoutLiveActivityHistoryReader {
    func prepare(sessionID: UUID, sessionDate: Date) -> WorkoutLiveActivityPreparation {
        let bodyweightLogs = (try? modelContext.fetch(
            FetchDescriptor<BodyweightLog>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []
        let profiles = (try? modelContext.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile = profiles.max { $0.updatedAt < $1.updatedAt }
        let unitSystem = profile?.unitSystem ?? .metric
        let profileBodyweightKg = profile?.bodyweight.map {
            SummitWeightFormatting.kilograms($0, unitSystem: unitSystem)
        }
        let resolvedBodyweightKg = WorkoutLiveActivityStateMapper.bodyweightKilograms(
            for: sessionDate,
            bodyweightLogs: bodyweightLogs,
            profileBodyweightKg: profileBodyweightKg
        )

        let history: [WorkoutSession]?
        do {
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate<WorkoutSession> { $0.completed },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            history = try modelContext.fetch(descriptor)
        } catch {
            history = nil
        }

        let previousBest = history.map { sessions in
            let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            return WorkoutLiveActivityPRTracker.previousBestE1RMByExercise(
                in: sessions.filter { $0.id != sessionID && $0.date <= sessionDate },
                exercises: exercises,
                bodyweightLogs: bodyweightLogs,
                profileBodyweightKg: profileBodyweightKg,
                unitSystem: unitSystem
            )
        }
        return WorkoutLiveActivityPreparation(
            unitSystem: unitSystem.rawValue,
            bodyweightKg: resolvedBodyweightKg,
            previousBestE1RMByExercise: previousBest
        )
    }
}

enum WorkoutLiveActivityStateMapper {
    static func enteredSetIDs(
        afterEditing setID: UUID,
        in session: WorkoutSession,
        previouslyEntered: Set<UUID>
    ) -> Set<UUID> {
        var result = previouslyEntered
        guard let set = session.exerciseLogs
            .flatMap(\.setLogs)
            .first(where: { $0.id == setID }),
              !set.isWarmup,
              set.reps > 0 else {
            result.remove(setID)
            return result
        }

        // Copied load and rep targets remain pending until a valid set edit is made.
        result.insert(setID)
        return result
    }

    static func makeState(
        from session: WorkoutSession,
        exercisesByID: [UUID: Exercise],
        enteredSetIDs: Set<UUID>,
        bodyweightKg: Double,
        unitSystem: UnitSystem,
        restEndsAt: Date?,
        prFlash: WorkoutActivityAttributes.PRFlash?,
        now: Date = .now
    ) -> WorkoutActivityAttributes.ContentState {
        let exerciseLogs = session.exerciseLogs.enumerated()
            .sorted {
                $0.element.orderIndex == $1.element.orderIndex
                    ? $0.offset < $1.offset
                    : $0.element.orderIndex < $1.element.orderIndex
            }
            .map(\.element)

        let setCounts = exerciseLogs.map { exerciseLog -> (ExerciseLog, Int, Int) in
            let sets = exerciseLog.setLogs.filter { !$0.isWarmup }
            let expected = max(exerciseLog.targetSets, sets.count)
            let completed = sets.filter { $0.completed || enteredSetIDs.contains($0.id) }.count
            return (exerciseLog, expected, completed)
        }
        let totalSetCount = setCounts.reduce(0) { $0 + $1.1 }
        let completedSetCount = setCounts.reduce(0) { $0 + min($1.1, $1.2) }
        let currentIndex = setCounts.firstIndex { $0.2 < $0.1 }
            ?? max(0, setCounts.count - 1)
        let current = setCounts.indices.contains(currentIndex) ? setCounts[currentIndex] : nil
        let currentExercise = current?.0
        let currentExerciseModel = currentExercise.flatMap { exercisesByID[$0.exerciseId] }
        let currentName = currentExercise.map {
            $0.exerciseNameSnapshot.isEmpty
                ? currentExerciseModel?.name ?? "Exercise"
                : $0.exerciseNameSnapshot
        } ?? session.splitNameSnapshot
        let setsInExercise = current?.1 ?? 0
        let setsDoneInExercise = current.map { min($0.1, $0.2) } ?? 0
        let exercisesLeft = setCounts.filter { $0.2 < $0.1 }.count
        let nextSet = currentExercise?.setLogs
            .filter { !$0.isWarmup && !$0.completed && !enteredSetIDs.contains($0.id) }
            .sorted { $0.setNumber < $1.setNumber }
            .first
        let nextWeightKg: Double?
        if let nextSet,
           !(currentExerciseModel?.equipment == .bodyweight && nextSet.weight == 0) {
            nextWeightKg = SummitWeightFormatting.kilograms(nextSet.weight, unitSystem: unitSystem)
        } else {
            nextWeightKg = nil
        }

        let setInputs = Self.setInputs(
            from: session,
            exercisesByID: exercisesByID,
            unitSystem: unitSystem,
            enteredSetIDs: enteredSetIDs
        )
        let validPR = prFlash.flatMap { $0.until > now ? $0 : nil }
        let validRestEnd = restEndsAt.flatMap { $0 > now ? $0 : nil }

        return WorkoutActivityAttributes.ContentState(
            exerciseName: currentName,
            setIndexInExercise: setsInExercise > 0 ? min(setsDoneInExercise + 1, setsInExercise) : 0,
            setsInExercise: setsInExercise,
            overallSetIndex: totalSetCount > 0 ? min(completedSetCount + 1, totalSetCount) : 0,
            overallSetCount: totalSetCount,
            completedSetCount: completedSetCount,
            exercisesLeft: exercisesLeft,
            nextWeightKg: nextWeightKg,
            nextReps: nextSet.map(\.reps).flatMap { $0 > 0 ? $0 : nil },
            restEndsAt: validRestEnd,
            metresGained: SummitProgressService.metres(for: setInputs, bodyweightKg: bodyweightKg),
            pr: validPR,
            unitSystem: unitSystem.rawValue,
            pausedAt: session.pausedAt,
            accumulatedPausedSeconds: session.accumulatedPausedSeconds
        )
    }

    static func setInputs(
        from session: WorkoutSession,
        exercisesByID: [UUID: Exercise],
        unitSystem: UnitSystem,
        enteredSetIDs: Set<UUID>
    ) -> [SummitSetInput] {
        session.exerciseLogs.enumerated()
            .sorted {
                $0.element.orderIndex == $1.element.orderIndex
                    ? $0.offset < $1.offset
                    : $0.element.orderIndex < $1.element.orderIndex
            }
            .flatMap { _, exerciseLog in
                let exercise = exercisesByID[exerciseLog.exerciseId]
                return exerciseLog.setLogs
                    .filter {
                        !$0.isWarmup
                            && ($0.completed || enteredSetIDs.contains($0.id))
                            && $0.reps > 0
                    }
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { set in
                        SummitSetInput(
                            id: set.id,
                            exerciseID: exerciseLog.exerciseId,
                            exerciseName: exerciseLog.exerciseNameSnapshot.isEmpty
                                ? exercise?.name ?? "Exercise"
                                : exerciseLog.exerciseNameSnapshot,
                            pattern: exercise?.movementPattern ?? .other,
                            isBodyweight: exercise?.equipment == .bodyweight,
                            isCompound: exercise?.isCompound ?? false,
                            weightKg: SummitWeightFormatting.kilograms(set.weight, unitSystem: unitSystem),
                            reps: set.reps
                        )
                    }
            }
    }

    static func bodyweightKilograms(
        for sessionDate: Date,
        bodyweightLogs: [BodyweightLog],
        profileBodyweightKg: Double?
    ) -> Double {
        let latestLogged = bodyweightLogs
            .filter { $0.date <= sessionDate }
            .max { $0.date < $1.date }
            .map { SummitWeightFormatting.kilograms($0.weight, unitSystem: $0.unit) }
        return latestLogged ?? profileBodyweightKg ?? 75
    }

    static func staleDate(
        for state: WorkoutActivityAttributes.ContentState,
        now: Date = .now
    ) -> Date? {
        [state.pr?.until, state.restEndsAt]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }
}

struct WorkoutLiveActivityUpdateThrottle {
    private(set) var lastState: WorkoutActivityAttributes.ContentState?

    mutating func shouldSend(_ state: WorkoutActivityAttributes.ContentState) -> Bool {
        guard lastState != state else { return false }
        lastState = state
        return true
    }

    mutating func reset(initialState: WorkoutActivityAttributes.ContentState? = nil) {
        lastState = initialState
    }
}

struct WorkoutLiveActivityPRCandidate: Equatable {
    let id: UUID
    let exerciseName: String
    let weightKg: Double
    let reps: Int
}

enum WorkoutLiveActivityPRTracker {
    static let prFlashDuration: TimeInterval = 8

    static func previousBestE1RMByExercise(
        in sessions: [WorkoutSession],
        exercises: [Exercise],
        bodyweightLogs: [BodyweightLog],
        profileBodyweightKg: Double?,
        unitSystem: UnitSystem
    ) -> [UUID: Double] {
        let inputs = SummitSnapshotBuilder.inputs(
            from: sessions,
            exercises: exercises,
            unitSystem: unitSystem
        )
        let bodyweightInputs = SummitSnapshotBuilder.bodyweightInputs(from: bodyweightLogs)
            .sorted { $0.date < $1.date }
        var bodyweightIndex = 0
        var latestLoggedBodyweight: Double?
        var previousBest: [UUID: Double] = [:]

        for session in inputs {
            while bodyweightIndex < bodyweightInputs.count,
                  bodyweightInputs[bodyweightIndex].date <= session.date {
                latestLoggedBodyweight = bodyweightInputs[bodyweightIndex].weightKg
                bodyweightIndex += 1
            }
            let bodyweightKg = latestLoggedBodyweight ?? profileBodyweightKg ?? 75
            var sessionBest: [UUID: Double] = [:]

            for set in session.sets {
                let effectiveLoad = SummitProgressService.effectiveLoad(for: set, bodyweightKg: bodyweightKg)
                let e1RM = TrainingAnalyticsService.estimatedOneRepMax(weight: effectiveLoad, reps: set.reps)
                sessionBest[set.exerciseID] = max(sessionBest[set.exerciseID] ?? -.infinity, e1RM)
            }

            for (exerciseID, e1RM) in sessionBest {
                previousBest[exerciseID] = max(previousBest[exerciseID] ?? -.infinity, e1RM)
            }
        }
        return previousBest
    }

    static func newPRCandidate(
        for changedSetID: UUID,
        currentSetInputs: [SummitSetInput],
        previousBestE1RMByExercise: [UUID: Double],
        bodyweightKg: Double
    ) -> WorkoutLiveActivityPRCandidate? {
        let setsByExercise = Dictionary(grouping: currentSetInputs, by: \.exerciseID)
        for (exerciseID, sets) in setsByExercise {
            guard let sessionBest = sets.max(by: {
                let lhsLoad = SummitProgressService.effectiveLoad(for: $0, bodyweightKg: bodyweightKg)
                let rhsLoad = SummitProgressService.effectiveLoad(for: $1, bodyweightKg: bodyweightKg)
                return TrainingAnalyticsService.estimatedOneRepMax(weight: lhsLoad, reps: $0.reps)
                    < TrainingAnalyticsService.estimatedOneRepMax(weight: rhsLoad, reps: $1.reps)
            }),
            sessionBest.id == changedSetID,
            let previousBest = previousBestE1RMByExercise[exerciseID] else { continue }

            let effectiveLoad = SummitProgressService.effectiveLoad(for: sessionBest, bodyweightKg: bodyweightKg)
            let e1RM = TrainingAnalyticsService.estimatedOneRepMax(weight: effectiveLoad, reps: sessionBest.reps)
            guard e1RM > previousBest else { continue }
            return WorkoutLiveActivityPRCandidate(
                id: sessionBest.id,
                exerciseName: sessionBest.exerciseName,
                weightKg: sessionBest.weightKg,
                reps: sessionBest.reps
            )
        }
        return nil
    }
}
