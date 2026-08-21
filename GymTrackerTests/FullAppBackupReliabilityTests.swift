import SwiftData
import XCTest
@testable import GymTracker

@MainActor
final class FullAppBackupReliabilityTests: XCTestCase {
    func testFirebaseBackupChunkingHandlesDataWithNonZeroStartIndex() {
        let bytes = Data((0..<32).map(UInt8.init))
        let slicedData = bytes[5..<29]
        XCTAssertEqual(slicedData.startIndex, 5)

        let chunks = FirebaseFullAppBackupStore.split(slicedData, chunkByteLimit: 7)

        XCTAssertEqual(chunks.map(\.count), [7, 7, 7, 3])
        XCTAssertEqual(chunks.reduce(into: Data(), { $0.append($1) }), Data(slicedData))
    }

    func testFullAppBackupRoundTripsEveryStoredDomainAndPreferences() throws {
        let sourceDefaults = makeDefaults("source")
        let targetDefaults = makeDefaults("target")
        let sourceTemplateStore = makeTemplateStore("source")
        let targetTemplateStore = makeTemplateStore("target")
        sourceDefaults.set("black", forKey: "appTheme")
        sourceDefaults.set("dark", forKey: "appAppearance")
        HydrationSettingsStore(defaults: sourceDefaults).saveDailyTargetML(3_200)
        NutritionGoalService(defaults: sourceDefaults).saveGoal(
            NutritionGoal(
                dailyCaloriesTarget: 2_500,
                dailyProteinTarget: 180,
                dailyCarbsTarget: nil,
                dailyFatTarget: nil,
                dailyFibreTarget: 32,
                trainingDayCaloriesTarget: nil,
                restDayCaloriesTarget: nil,
                isEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        try sourceTemplateStore.save(CustomWorkoutTemplate(
            name: "Push Express",
            exercises: [
                CustomWorkoutTemplateExercise(
                    exerciseName: "Bench Press",
                    orderIndex: 0,
                    plannedSets: 3,
                    targetRepMin: 5,
                    targetRepMax: 8
                )
            ]
        ))

        let service = FullAppBackupService(
            defaults: sourceDefaults,
            templateStore: sourceTemplateStore
        )
        let envelope = try service.makeEnvelope(in: source.mainContext)
        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(envelope.counts.workoutTemplateCount, 1)
        let data = try service.encode(envelope)

        let target = try makeContainer()
        let summary = try FullAppBackupService(
            defaults: targetDefaults,
            templateStore: targetTemplateStore
        )
            .importBackup(from: data, into: target.mainContext, replaceExisting: true)

        XCTAssertEqual(summary.counts.userProfileCount, 1)
        XCTAssertEqual(summary.counts.exerciseCount, 1)
        XCTAssertEqual(summary.counts.splitCount, 1)
        XCTAssertEqual(summary.counts.workoutCount, 1)
        XCTAssertEqual(summary.counts.foodItemCount, 1)
        XCTAssertEqual(summary.counts.foodLogCount, 1)
        XCTAssertEqual(summary.counts.hydrationCount, 1)
        XCTAssertEqual(summary.counts.sleepCount, 1)
        XCTAssertEqual(summary.counts.napCount, 1)
        XCTAssertGreaterThan(summary.counts.coachRecordCount, 0)

        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(
            try target.mainContext.fetch(FetchDescriptor<TrainingSplit>()).first?.activeRotationIndex,
            0
        )
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<FoodLogEntry>()), 1)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<SleepSession>()), 1)
        XCTAssertEqual(HydrationSettingsStore(defaults: targetDefaults).dailyTargetML(), 3_200)
        XCTAssertEqual(NutritionGoalService(defaults: targetDefaults).loadGoal().dailyProteinTarget, 180)
        XCTAssertEqual(NutritionGoalService(defaults: targetDefaults).loadGoal().dailyFibreTarget, 32)
        XCTAssertEqual(targetDefaults.string(forKey: "appTheme"), "black")
        XCTAssertEqual(targetDefaults.string(forKey: "appAppearance"), "dark")
        XCTAssertEqual(targetTemplateStore.loadTemplates().map(\.name), ["Push Express"])
    }

    func testRestoreValidationRejectsDuplicateIdentifiersBeforeMutation() throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let service = FullAppBackupService(templateStore: makeTemplateStore("duplicate-source"))
        let envelope = try service.makeEnvelope(in: source.mainContext)
        var invalidData = envelope.data
        invalidData.exercises.append(try XCTUnwrap(invalidData.exercises.first))
        let invalidEnvelope = FullAppBackupEnvelope(
            schemaVersion: envelope.schemaVersion,
            exportedAt: envelope.exportedAt,
            appName: envelope.appName,
            appVersion: envelope.appVersion,
            preferences: envelope.preferences,
            data: invalidData
        )
        let target = try makeContainer()
        try insertFullSample(in: target.mainContext)
        let originalWorkoutID = try XCTUnwrap(
            target.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.id
        )

        XCTAssertThrowsError(
            try service.importBackup(invalidEnvelope, into: target.mainContext, replaceExisting: true)
        ) { error in
            XCTAssertEqual(error as? FullAppBackupError, .duplicateIdentifier("exercise"))
        }
        XCTAssertEqual(
            try target.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.id,
            originalWorkoutID
        )
    }

    func testCorruptTemplateFileProtectsLocalContentAndFailsBackupCreation() throws {
        let templateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FullAppBackupReliabilityTests")
            .appendingPathComponent("corrupt-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(
            at: templateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not valid template JSON".utf8).write(to: templateURL, options: .atomic)

        let container = try makeContainer()
        let service = FullAppBackupService(
            templateStore: WorkoutTemplateStore(fileURL: templateURL)
        )

        XCTAssertEqual(try service.userContentCount(in: container.mainContext), 1)
        XCTAssertThrowsError(try service.makeEnvelope(in: container.mainContext))
    }

    func testRestoreRollsBackModelsAndTemplatesWhenCommitFails() throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let sourceTemplates = makeTemplateStore("rollback-source")
        try sourceTemplates.save(CustomWorkoutTemplate(name: "Cloud Template", exercises: []))
        let envelope = try FullAppBackupService(templateStore: sourceTemplates)
            .makeEnvelope(in: source.mainContext)

        let target = try makeContainer()
        try insertFullSample(in: target.mainContext)
        let targetTemplates = makeTemplateStore("rollback-target")
        try targetTemplates.save(CustomWorkoutTemplate(name: "Local Template", exercises: []))
        let originalWorkoutID = try XCTUnwrap(
            target.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.id
        )
        let failingService = FullAppBackupService(
            templateStore: targetTemplates,
            beforeCommit: { throw InjectedBackupFailure() }
        )

        XCTAssertThrowsError(
            try failingService.importBackup(envelope, into: target.mainContext, replaceExisting: true)
        )
        XCTAssertEqual(
            try target.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.id,
            originalWorkoutID
        )
        XCTAssertEqual(targetTemplates.loadTemplates().map(\.name), ["Local Template"])
    }

    func testRestoreRejectsRemoteMetadataCountMismatchWithoutMutatingStore() async throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let target = try makeContainer()
        let store = InMemoryRemoteFullAppBackupStore()
        let saveCoordinator = BackupCoordinator(store: store)
        let passphrase = "correct horse battery staple"
        guard case .saved = await saveCoordinator.saveLatestBackup(
            in: source.mainContext,
            passphrase: passphrase
        ), let record = store.record else {
            return XCTFail("Expected a saved record")
        }

        var tamperedCounts = record.metadata.counts
        tamperedCounts.workoutCount += 1
        store.record = RemoteFullAppBackupRecord(
            metadata: FullAppBackupMetadata(
                createdAt: record.metadata.createdAt,
                exportedAt: record.metadata.exportedAt,
                counts: tamperedCounts,
                compressedByteCount: record.metadata.compressedByteCount,
                appVersion: record.metadata.appVersion
            ),
            crypto: record.crypto,
            encryptedData: record.encryptedData
        )

        let outcome = await BackupCoordinator(store: store).restoreLatestBackup(
            in: target.mainContext,
            replaceExisting: true,
            passphrase: passphrase
        )
        guard case .failed(let message) = outcome else {
            return XCTFail("Expected integrity failure, got \(outcome)")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("integrity"))
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testCryptoHonoursStoredIterationCountAndRejectsUnsupportedAlgorithms() throws {
        let service = BackupEncryptionService()
        let salt = Data(repeating: 7, count: BackupEncryptionService.saltByteCount)
        let material = try service.deriveKey(
            passphrase: "correct horse battery staple",
            salt: salt,
            iterationCount: 12_345
        )
        let payload = try service.encrypt(plaintext: Data("peakline".utf8), keyMaterial: material)
        XCTAssertEqual(payload.crypto.iterationCount, 12_345)

        let derivedAgain = try service.deriveKey(
            passphrase: "correct horse battery staple",
            salt: salt,
            iterationCount: payload.crypto.iterationCount
        )
        XCTAssertEqual(
            try service.decrypt(
                ciphertext: payload.ciphertext,
                crypto: payload.crypto,
                keyData: derivedAgain.keyData
            ),
            Data("peakline".utf8)
        )

        let unsupported = BackupCryptoMetadata(
            algorithm: "AES-CBC",
            iterationCount: payload.crypto.iterationCount,
            salt: salt,
            nonce: try XCTUnwrap(payload.crypto.nonceData),
            tag: try XCTUnwrap(payload.crypto.tagData)
        )
        XCTAssertThrowsError(try unsupported.validateSupported())
    }

    func testVersionedSchemaReopensLegacyBaselineStore() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeaklineLegacy-\(UUID().uuidString).store")
        var legacyContainer: ModelContainer? = try ModelContainer(
            for: Schema(PeaklineSchemaV1.models),
            configurations: [
                ModelConfiguration(
                    "PeaklineLegacy",
                    schema: Schema(PeaklineSchemaV1.models),
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            ]
        )
        legacyContainer?.mainContext.insert(UserProfile(trainingDaysPerWeek: 4))
        try legacyContainer?.mainContext.save()
        legacyContainer = nil

        let migrated = try PeaklineModelStore.makeContainer(
            isStoredInMemoryOnly: false,
            storeURL: storeURL
        )
        XCTAssertEqual(
            try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).first?.trainingDaysPerWeek,
            4
        )
    }

    func testCloudCoordinatorKeepsExistingBackupWhenLocalStoreHasNoUserContent() async throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let empty = try makeContainer()
        let store = InMemoryRemoteFullAppBackupStore()
        let coordinator = BackupCoordinator(store: store)
        let passphrase = "correct horse battery staple"

        let saved = await coordinator.saveLatestBackup(in: source.mainContext, passphrase: passphrase)
        guard case .saved(let savedMetadata) = saved else {
            return XCTFail("Expected save, got \(saved)")
        }
        XCTAssertGreaterThan(savedMetadata.counts.userContentCount, 0)

        let emptySave = await coordinator.saveLatestBackup(in: empty.mainContext, passphrase: passphrase)
        guard case .keptExistingBackup(let keptMetadata) = emptySave else {
            return XCTFail("Expected existing backup to be kept, got \(emptySave)")
        }
        XCTAssertEqual(keptMetadata.counts.userContentCount, savedMetadata.counts.userContentCount)
    }

    func testCancelledBackupDoesNotPublishACloudRecord() async throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let store = InMemoryRemoteFullAppBackupStore()
        let coordinator = BackupCoordinator(store: store)

        let task = Task {
            await coordinator.saveLatestBackup(
                in: source.mainContext,
                passphrase: "correct horse battery staple"
            )
        }
        task.cancel()
        let outcome = await task.value

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("cancel"))
        XCTAssertNil(store.record)
    }

    func testRestoreRequiresExplicitReplaceWhenStoreHasUserContent() async throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let target = try makeContainer()
        try insertFullSample(in: target.mainContext)
        let store = InMemoryRemoteFullAppBackupStore()
        let coordinator = BackupCoordinator(store: store)
        let passphrase = "correct horse battery staple"

        _ = await coordinator.saveLatestBackup(in: source.mainContext, passphrase: passphrase)
        let skipped = await coordinator.restoreLatestBackup(in: target.mainContext, replaceExisting: false, passphrase: passphrase)
        XCTAssertEqual(skipped, .skippedStoreNotEmpty)

        let restored = await coordinator.restoreLatestBackup(in: target.mainContext, replaceExisting: true, passphrase: passphrase)
        guard case .restored(let summary) = restored else {
            return XCTFail("Expected restore, got \(restored)")
        }
        XCTAssertEqual(summary.counts.workoutCount, 1)
    }

    func testEncryptedBackupRejectsWrongPassphrase() async throws {
        let source = try makeContainer()
        try insertFullSample(in: source.mainContext)
        let target = try makeContainer()
        let store = InMemoryRemoteFullAppBackupStore()
        let coordinator = BackupCoordinator(store: store)

        let saved = await coordinator.saveLatestBackup(in: source.mainContext, passphrase: "correct horse battery staple")
        guard case .saved = saved else {
            return XCTFail("Expected save, got \(saved)")
        }

        let restoreCoordinator = BackupCoordinator(store: store)
        let restored = await restoreCoordinator.restoreLatestBackup(in: target.mainContext, replaceExisting: true, passphrase: "wrong passphrase")
        guard case .failed(let message) = restored else {
            return XCTFail("Expected failed restore, got \(restored)")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("passphrase"))
    }

    func testLatestMetadataDoesNotDownloadEncryptedBackupPayload() async {
        let expected = FullAppBackupMetadata(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            counts: FullAppBackupCounts(
                userProfileCount: 0,
                exerciseCount: 0,
                splitCount: 0,
                workoutCount: 0,
                recommendationCount: 0,
                bodyweightCount: 0,
                foodItemCount: 0,
                foodLogCount: 0,
                hydrationCount: 0,
                sleepCount: 0,
                napCount: 0,
                coachRecordCount: 0,
                userContentCount: 0
            ),
            compressedByteCount: 0,
            appVersion: nil
        )
        let store = MetadataProbeBackupStore(metadata: expected)
        let coordinator = BackupCoordinator(store: store)

        let outcome = await coordinator.latestMetadata()

        XCTAssertEqual(outcome, .available(expected))
        XCTAssertEqual(store.metadataRequestCount, 1)
        XCTAssertEqual(store.recordRequestCount, 0)
    }

    func testStartupSnapshotUsesImmediateSuccessorAfterLegs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let rotationNames = ["Push", "Pull", "Legs", "Upper", "Lower"]
        let splits = rotationNames.enumerated().map { index, name in
            TrainingSplit(
                name: name,
                splitType: .custom,
                activeRotationIndex: index,
                daysPerWeek: 5
            )
        }
        splits.forEach(context.insert)
        let legs = try XCTUnwrap(splits.first { $0.name == "Legs" })
        let workout = WorkoutSession(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            splitId: legs.id,
            splitNameSnapshot: legs.name,
            endedAt: Date(timeIntervalSince1970: 1_800_003_600),
            durationSeconds: 3_600,
            completed: true
        )
        let exerciseLog = ExerciseLog(
            workoutSessionId: workout.id,
            exerciseId: UUID(),
            exerciseNameSnapshot: "Leg Press",
            orderIndex: 0
        )
        let setLog = SetLog(
            exerciseLogId: exerciseLog.id,
            setNumber: 1,
            weight: 100,
            reps: 8,
            completed: true
        )
        setLog.exerciseLog = exerciseLog
        exerciseLog.setLogs = [setLog]
        exerciseLog.workoutSession = workout
        workout.exerciseLogs = [exerciseLog]
        context.insert(workout)
        try context.save()

        let projections = try StartupSnapshotBuilder.materialize(in: context)
        let derived = await StartupSnapshotBuilder.makePure(from: projections.pureProjection)
        let snapshot = StartupSnapshotBuilder.makeBundle(from: projections, derived: derived)

        XCTAssertEqual(snapshot.activeSplitCount, 5)
        XCTAssertEqual(snapshot.trainingCall.recommendedSplitName, "Upper")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            TrainingSplit.self,
            SplitExercise.self,
            Exercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            Recommendation.self,
            BodyweightLog.self,
            FoodItem.self,
            FoodLogEntry.self,
            HydrationEntry.self,
            SleepSession.self,
            NapSession.self,
            DailyCoachCheckIn.self,
            CoachActionHistoryEntry.self,
            SavedCoachDeloadBlock.self,
            CoachExerciseMetadata.self,
            CoachRecommendationFeedback.self,
            CoachPreferences.self,
            CoachSplitMetadata.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "FullAppBackupReliabilityTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemplateStore(_ name: String) -> WorkoutTemplateStore {
        WorkoutTemplateStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("FullAppBackupReliabilityTests")
                .appendingPathComponent("\(name)-\(UUID().uuidString).json")
        )
    }

    private func insertFullSample(in context: ModelContext) throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = UserProfile(trainingDaysPerWeek: 5, preferredSplitType: .custom, bodyweight: 82)
        let exercise = Exercise(
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            movementPattern: .push,
            equipment: .barbell,
            isCompound: true,
            createdAt: date,
            updatedAt: date
        )
        let split = TrainingSplit(name: "Push", splitType: .custom, createdAt: date, updatedAt: date, daysPerWeek: 4)
        let splitExercise = SplitExercise(
            splitId: split.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: 3,
            minReps: 5,
            maxReps: 8
        )
        splitExercise.split = split
        split.exercises = [splitExercise]

        let workout = WorkoutSession(
            date: date,
            splitId: split.id,
            splitNameSnapshot: split.name,
            endedAt: date.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            perceivedDifficulty: 4,
            completed: true
        )
        let log = ExerciseLog(
            workoutSessionId: workout.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: 0,
            targetSets: 1,
            minReps: 5,
            maxReps: 8
        )
        let set = SetLog(exerciseLogId: log.id, setNumber: 1, weight: 100, reps: 6, rpe: 8, completed: true)
        set.exerciseLog = log
        log.setLogs = [set]
        log.workoutSession = workout
        workout.exerciseLogs = [log]

        let food = FoodItem(name: "Greek Yogurt", caloriesPer100g: 120, proteinPer100g: 10)
        let foodLog = FoodLogEntry(
            foodItemId: food.id,
            foodNameSnapshot: food.name,
            consumedAmount: 150,
            amountUnit: .grams,
            mealType: .snack,
            caloriesSnapshot: 180,
            proteinSnapshot: 15,
            carbsSnapshot: 6,
            fatSnapshot: 4,
            loggedAt: date
        )

        context.insert(profile)
        context.insert(exercise)
        context.insert(split)
        context.insert(workout)
        context.insert(Recommendation(type: .nextSplit, title: "Train Push", message: "Push next.", reason: "Cycle", confidence: 0.8))
        context.insert(BodyweightLog(date: date, weight: 82, unit: .metric, notes: "Morning"))
        context.insert(food)
        context.insert(foodLog)
        context.insert(HydrationEntry(amountML: 750, loggedAt: date, source: .manual, context: .postWorkout))
        context.insert(SleepSession(confirmedSleepStartAt: date, wakeAt: date.addingTimeInterval(28_800), durationMinutes: 480, source: .manual, confidence: .medium, status: .completed))
        context.insert(NapSession(startDate: date, endDate: date.addingTimeInterval(1_800), source: .manual))
        context.insert(DailyCoachCheckIn(date: date, energy: 4, soreness: 2, stress: 2, motivation: 5, note: "Good"))
        context.insert(CoachPreferences(showDiagnostics: true))
        context.insert(CoachSplitMetadata(splitId: split.id, splitName: split.name))
        context.insert(CoachActionHistoryEntry(action: .reduceAccessories, outcome: .applied, readinessCategory: .ready, fatigueRiskLevel: .moderate, confidence: .medium, shortReason: "Tired", splitName: split.name, beforeTotalSets: 12, afterTotalSets: 9))
        context.insert(SavedCoachDeloadBlock(endsAt: date.addingTimeInterval(432_000), duration: .fiveDays, volumeReduction: .twentyFivePercent, focus: .maintainFrequency, reason: "Fatigue", splitName: split.name))
        context.insert(CoachExerciseMetadata(exerciseId: exercise.id, role: .priorityLift, primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps], movementPattern: .push))
        context.insert(CoachRecommendationFeedback(action: .reduceAccessories, tags: [.helpful], note: "Accurate", splitName: split.name, readinessCategory: .ready, fatigueRiskLevel: .moderate, confidence: .medium))
        try context.save()
    }
}

private struct InjectedBackupFailure: Error {}

final class StartupPresentationReducerTests: XCTestCase {
    func testFastReadyPathRevealsThenHides() {
        var state = StartupPresentationState.animating
        state = StartupPresentationReducer.reduce(state, event: .criticalReady)
        XCTAssertEqual(state, .revealing)

        state = StartupPresentationReducer.reduce(state, event: .revealFinished)
        XCTAssertEqual(state, .hidden)
    }

    func testSlowPathSettlesBeforeItReveals() {
        var state = StartupPresentationState.animating
        state = StartupPresentationReducer.reduce(state, event: .slowThresholdReached)
        XCTAssertEqual(state, .holdingSlow)

        state = StartupPresentationReducer.reduce(state, event: .criticalReady)
        XCTAssertEqual(state, .revealing)
    }

    func testInterruptionRemovesSplashAndResumeDoesNotReplayAnimation() {
        var state = StartupPresentationReducer.reduce(
            .animating,
            event: .interrupted
        )
        XCTAssertEqual(state, .interrupted)

        state = StartupPresentationReducer.reduce(state, event: .resumeAfterInteraction)
        XCTAssertEqual(state, .holdingSlow)
    }

    func testLateEventsCannotReopenHiddenPresentation() {
        XCTAssertEqual(
            StartupPresentationReducer.reduce(.hidden, event: .start),
            .hidden
        )
        XCTAssertEqual(
            StartupPresentationReducer.reduce(.hidden, event: .resumeAfterInteraction),
            .hidden
        )
    }
}

private final class MetadataProbeBackupStore: RemoteFullAppBackupStoring {
    private let metadata: FullAppBackupMetadata?
    private(set) var metadataRequestCount = 0
    private(set) var recordRequestCount = 0

    init(metadata: FullAppBackupMetadata?) {
        self.metadata = metadata
    }

    func latestMetadata() async throws -> FullAppBackupMetadata? {
        metadataRequestCount += 1
        return metadata
    }

    func latestRecord() async throws -> RemoteFullAppBackupRecord? {
        recordRequestCount += 1
        return nil
    }

    func saveRecord(_ record: RemoteFullAppBackupRecord) async throws {}
}
