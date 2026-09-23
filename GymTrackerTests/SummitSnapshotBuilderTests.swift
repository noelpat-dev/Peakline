import XCTest
import SwiftData
@testable import GymTracker

@MainActor
final class SummitSnapshotBuilderTests: XCTestCase {
    func testInputsKeepOnlyCompletedWorkingSetsAndConvertPounds() {
        let bench = exercise(name: "Bench press", pattern: .push, equipment: .barbell, isCompound: true)
        let complete = workout(
            date: date(2026, 9, 20),
            exercises: [(
                bench,
                [
                    set(number: 1, weight: 132.277357, reps: 8, completed: true),
                    set(number: 2, weight: 132.277357, reps: 8, warmup: true, completed: true),
                    set(number: 3, weight: 132.277357, reps: 0, completed: true),
                    set(number: 4, weight: 132.277357, reps: 8, completed: false)
                ]
            )]
        )
        let incomplete = workout(
            date: date(2026, 9, 21),
            completed: false,
            exercises: [(bench, [set(number: 1, weight: 132.277357, reps: 8, completed: true)])]
        )

        let inputs = SummitSnapshotBuilder.inputs(
            from: [complete, incomplete],
            exercises: [bench],
            unitSystem: .imperial
        )

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].sets.count, 1)
        XCTAssertEqual(inputs[0].sets[0].pattern, .push)
        XCTAssertFalse(inputs[0].sets[0].isBodyweight)
        XCTAssertTrue(inputs[0].sets[0].isCompound)
        XCTAssertEqual(
            inputs[0].sets[0].weightKg,
            SummitWeightFormatting.kilograms(132.277357, unitSystem: .imperial),
            accuracy: 0.0001
        )
    }

    func testBodyweightInputsUseEachLogsRecordedUnit() {
        let logs = [
            BodyweightLog(date: date(2026, 9, 1), weight: 176, unit: .imperial),
            BodyweightLog(date: date(2026, 9, 2), weight: 80, unit: .metric)
        ]

        let inputs = SummitSnapshotBuilder.bodyweightInputs(from: logs)

        XCTAssertEqual(inputs[0].weightKg, SummitWeightFormatting.kilograms(176, unitSystem: .imperial), accuracy: 0.0001)
        XCTAssertEqual(inputs[1].weightKg, 80, accuracy: 0.0001)
    }

    func testThreeSessionSnapshotKeepsPRsLoadsAndLiftTrend() {
        let benchID = UUID()
        let sessions = [
            inputSession(id: UUID(), date: date(2026, 9, 10), exerciseID: benchID, name: "Bench press", weight: 60, reps: 8),
            inputSession(id: UUID(), date: date(2026, 9, 16), exerciseID: benchID, name: "Bench press", weight: 60, reps: 8),
            inputSession(id: UUID(), date: date(2026, 9, 23), exerciseID: benchID, name: "Bench press", weight: 70, reps: 8)
        ]
        let now = date(2026, 9, 23)

        let snapshot = SummitSnapshotBuilder.build(
            sessions: sessions,
            bodyweights: [],
            profileBodyweightKg: 80,
            expeditionStart: nil,
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(snapshot.log.count, 3)
        XCTAssertEqual(snapshot.log.first?.id, sessions.last?.id)
        XCTAssertTrue(snapshot.log.last?.prs.isEmpty ?? false)
        XCTAssertEqual(snapshot.log.first?.prs.count, 1)
        XCTAssertEqual(snapshot.log.first?.setCount, 1)
        XCTAssertFalse(snapshot.log.first?.isLowerRoute ?? true)
        XCTAssertEqual(snapshot.altitude.totalMetres, 9)
        XCTAssertEqual(snapshot.altitude.gainedToday, 3)
        XCTAssertEqual(snapshot.month.monthStart, calendar().date(from: DateComponents(year: 2026, month: 9, day: 1)))
        XCTAssertEqual(snapshot.month.todayIndex, 22)
        XCTAssertEqual(snapshot.month.dayLoads.count, 30)
        XCTAssertEqual(snapshot.month.dayLoads[22], 1)
        XCTAssertEqual(snapshot.month.previousMonthLoads.count, 31)
        XCTAssertEqual(snapshot.lifts.count, 1)
        XCTAssertEqual(snapshot.lifts.first?.name, "Bench press")
        XCTAssertEqual(snapshot.lifts.first?.shortName, "BENCH")
        XCTAssertEqual(snapshot.lifts.first?.weeklyBest.count, 12)
        XCTAssertEqual(snapshot.cairn.recentWeeks.count, 12)
    }

    func testBodyweightAtEachSessionUsesTheLatestPriorLog() {
        let pullUpID = UUID()
        let sessions = [
            inputSession(id: UUID(), date: date(2026, 9, 12), exerciseID: pullUpID, name: "Pull-up", pattern: .pull, bodyweight: true, weight: 20, reps: 8),
            inputSession(id: UUID(), date: date(2026, 9, 17), exerciseID: pullUpID, name: "Pull-up", pattern: .pull, bodyweight: true, weight: 20, reps: 8)
        ]

        let snapshot = SummitSnapshotBuilder.build(
            sessions: sessions,
            bodyweights: [SummitBodyweightInput(date: date(2026, 9, 15), weightKg: 100)],
            profileBodyweightKg: 70,
            expeditionStart: nil,
            now: date(2026, 9, 23),
            calendar: calendar()
        )

        XCTAssertEqual(snapshot.log.map(\.metres), [5, 6])
    }

    func testLiftBestSetsCanComeFromTheSameSession() {
        let exerciseID = UUID()
        let setIDs = [UUID(), UUID(), UUID()]
        var first = inputSession(
            id: UUID(), date: date(2026, 9, 10), exerciseID: exerciseID,
            name: "Bench press", weight: 150, reps: 1
        )
        first.sets = [150.0, 140.0, 130.0].enumerated().map { index, weight in
            var set = first.sets[0]
            set.id = setIDs[index]
            set.weightKg = weight
            return set
        }
        let sessions = [
            first,
            inputSession(id: UUID(), date: date(2026, 9, 16), exerciseID: exerciseID, name: "Bench press", weight: 50, reps: 1),
            inputSession(id: UUID(), date: date(2026, 9, 23), exerciseID: exerciseID, name: "Bench press", weight: 60, reps: 1)
        ]

        let snapshot = SummitSnapshotBuilder.build(
            sessions: sessions,
            bodyweights: [],
            profileBodyweightKg: 80,
            expeditionStart: nil,
            now: date(2026, 9, 23),
            calendar: calendar()
        )

        XCTAssertEqual(snapshot.lifts.first?.bestSets.map(\.id), setIDs)
    }

    func testCompoundLiftsArePreferredWhenSelectingSixRecentExercises() {
        let benchID = UUID()
        let curlID = UUID()
        let sessions = (0..<3).flatMap { offset in
            let sessionDate = date(2026, 9, 20 + offset)
            return [
                inputSession(id: UUID(), date: sessionDate, exerciseID: benchID, name: "Bench press", pattern: .push, compound: true, weight: 40, reps: 8),
                inputSession(id: UUID(), date: sessionDate, exerciseID: curlID, name: "Biceps curl", pattern: .isolation, compound: false, weight: 100, reps: 8)
            ]
        }

        let snapshot = SummitSnapshotBuilder.build(
            sessions: sessions,
            bodyweights: [],
            profileBodyweightKg: 80,
            expeditionStart: nil,
            now: date(2026, 9, 23),
            calendar: calendar()
        )

        XCTAssertEqual(snapshot.lifts.map(\.name), ["Bench press", "Biceps curl"])
    }

    func testFiveHundredSessionsWithTwentySetsBuildsInsideMeasureBlock() {
        let now = date(2026, 9, 23)
        let fixtureCalendar = calendar()
        let exerciseID = UUID()
        let sessions = (0..<500).map { offset in
            let sessionDate = fixtureCalendar.date(byAdding: .day, value: -offset, to: now)!
            let sets = (0..<20).map { setNumber in
                SummitSetInput(
                    exerciseID: exerciseID,
                    exerciseName: "Deadlift",
                    pattern: .hinge,
                    isBodyweight: false,
                    isCompound: true,
                    weightKg: 100 + Double(setNumber),
                    reps: 5
                )
            }
            return SummitSessionInput(
                id: UUID(),
                date: sessionDate,
                title: "Strength",
                durationMinutes: 60,
                sets: sets
            )
        }

        measure {
            _ = SummitSnapshotBuilder.build(
                sessions: sessions,
                bodyweights: [],
                profileBodyweightKg: 80,
                expeditionStart: nil,
                now: now,
                calendar: fixtureCalendar
            )
        }
    }

    private func exercise(
        name: String,
        pattern: MovementPattern,
        equipment: EquipmentType,
        isCompound: Bool
    ) -> Exercise {
        Exercise(
            name: name,
            primaryMuscleGroup: .chest,
            movementPattern: pattern,
            equipment: equipment,
            isCompound: isCompound
        )
    }

    private func workout(
        date: Date,
        completed: Bool = true,
        exercises: [(Exercise, [SetLog])]
    ) -> WorkoutSession {
        let sessionID = UUID()
        let logs = exercises.enumerated().map { index, entry in
            let logID = UUID()
            return ExerciseLog(
                id: logID,
                workoutSessionId: sessionID,
                exerciseId: entry.0.id,
                exerciseNameSnapshot: entry.0.name,
                orderIndex: index,
                setLogs: entry.1.map { set in
                    SetLog(
                        exerciseLogId: logID,
                        setNumber: set.setNumber,
                        weight: set.weight,
                        reps: set.reps,
                        isWarmup: set.isWarmup,
                        completed: set.completed
                    )
                }
            )
        }
        return WorkoutSession(
            id: sessionID,
            date: date,
            splitNameSnapshot: "Strength",
            durationMinutes: 50,
            completed: completed,
            exerciseLogs: logs
        )
    }

    private func set(
        number: Int,
        weight: Double,
        reps: Int,
        warmup: Bool = false,
        completed: Bool
    ) -> SetLog {
        SetLog(setNumber: number, weight: weight, reps: reps, isWarmup: warmup, completed: completed)
    }

    private func inputSession(
        id: UUID,
        date: Date,
        exerciseID: UUID,
        name: String,
        pattern: MovementPattern = .push,
        bodyweight: Bool = false,
        compound: Bool = true,
        weight: Double,
        reps: Int
    ) -> SummitSessionInput {
        SummitSessionInput(
            id: id,
            date: date,
            title: "Strength",
            durationMinutes: 50,
            sets: [SummitSetInput(
                exerciseID: exerciseID,
                exerciseName: name,
                pattern: pattern,
                isBodyweight: bodyweight,
                isCompound: compound,
                weightKg: weight,
                reps: reps
            )]
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
