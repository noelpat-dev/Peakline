import Foundation
import SwiftData
import UserNotifications

struct WorkoutPerformanceService {
    func calculatePerformanceScore(for workout: WorkoutSession) -> WorkoutPerformanceScore {
        calculatePerformanceScore(for: workout, recentWorkouts: [])
    }

    func calculatePerformanceScore(for workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> WorkoutPerformanceScore {
        guard workout.completed else {
            return WorkoutPerformanceScore(score: 25, label: .incomplete, contributingFactors: [.missedWorkout])
        }

        let completedSets = completedWorkingSets(in: workout)
        let plannedSets = max(1, workout.exerciseLogs.reduce(0) { $0 + max($1.targetSets, $1.setLogs.filter { !$0.isWarmup }.count) })
        let completionRatio = min(1, Double(completedSets.count) / Double(plannedSets))
        let volume = completedVolume(in: workout)
        let recentComparable = recentWorkouts
            .filter { $0.id != workout.id && $0.completed && baseSplitName($0.splitNameSnapshot) == baseSplitName(workout.splitNameSnapshot) }
            .prefix(5)
        let averageVolume = recentComparable.isEmpty ? nil : recentComparable.map { completedVolume(in: $0) }.reduce(0, +) / Double(recentComparable.count)

        var score = 45 + Int((completionRatio * 35).rounded())
        var factors: [WorkoutPerformanceFactor] = []

        if completionRatio >= 0.85 {
            factors.append(.completedMostSets)
        }

        if let averageVolume, averageVolume > 0 {
            if volume >= averageVolume * 1.08 {
                score += 10
                factors.append(.volumeAboveAverage)
            } else if volume <= averageVolume * 0.90 {
                score -= 12
                factors.append(.volumeBelowAverage)
            }
        }

        if progressedStrength(workout: workout, recentWorkouts: Array(recentComparable)) {
            score += 8
            factors.append(.strengthProgressed)
        }

        if repsDropped(workout: workout, recentWorkouts: Array(recentComparable)) {
            score -= 8
            factors.append(.repsDropped)
        }

        if let durationMinutes = workout.durationMinutes, durationMinutes < 25, completedSets.count >= 3 {
            score -= 5
            factors.append(.shorterThanUsual)
        }

        if let difficulty = workout.perceivedDifficulty, difficulty >= 8 {
            score -= 6
            factors.append(.highDifficulty)
        }

        if let energy = workout.energyLevel, energy >= 4 {
            score += 4
            factors.append(.highEnergy)
        }

        if let soreness = workout.sorenessLevel, soreness >= 4 {
            score -= 5
            factors.append(.highSoreness)
        }

        let clamped = min(100, max(0, score))
        return WorkoutPerformanceScore(score: clamped, label: label(for: clamped), contributingFactors: factors)
    }

    func completedVolume(in workout: WorkoutSession) -> Double {
        completedWorkingSets(in: workout).reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    func completionRatio(in workout: WorkoutSession) -> Double {
        let completed = completedWorkingSets(in: workout).count
        let planned = max(1, workout.exerciseLogs.reduce(0) { $0 + max($1.targetSets, $1.setLogs.filter { !$0.isWarmup }.count) })
        return min(1, Double(completed) / Double(planned))
    }

    func estimatedEffort(in workout: WorkoutSession) -> Double? {
        let rpes = workout.exerciseLogs.flatMap(\.setLogs).compactMap(\.rpe)
        if !rpes.isEmpty {
            return rpes.reduce(0, +) / Double(rpes.count)
        }
        return workout.perceivedDifficulty.map(Double.init)
    }

    private func completedWorkingSets(in workout: WorkoutSession) -> [SetLog] {
        workout.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }
    }

    private func label(for score: Int) -> WorkoutPerformanceLabel {
        switch score {
        case 85...100:
            return .strong
        case 70..<85:
            return .good
        case 55..<70:
            return .moderate
        case 40..<55:
            return .reduced
        default:
            return .incomplete
        }
    }

    private func progressedStrength(workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> Bool {
        guard let currentBest = bestEstimatedOneRepMax(in: workout), currentBest > 0 else { return false }
        let priorBest = recentWorkouts.compactMap(bestEstimatedOneRepMax(in:)).max() ?? 0
        return priorBest > 0 && currentBest >= priorBest * 1.02
    }

    private func repsDropped(workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> Bool {
        let currentAverage = averageWorkingReps(in: workout)
        let priorAverage = recentWorkouts.compactMap(averageWorkingReps(in:)).first
        guard let currentAverage, let priorAverage, priorAverage > 0 else { return false }
        return currentAverage <= priorAverage * 0.88
    }

    private func bestEstimatedOneRepMax(in workout: WorkoutSession) -> Double? {
        workout.exerciseLogs
            .flatMap(\.setLogs)
            .filter { $0.completed && !$0.isWarmup }
            .map { $0.weight * (1 + Double($0.reps) / 30) }
            .max()
    }

    private func averageWorkingReps(in workout: WorkoutSession) -> Double? {
        let sets = completedWorkingSets(in: workout)
        guard !sets.isEmpty else { return nil }
        return Double(sets.map(\.reps).reduce(0, +)) / Double(sets.count)
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }
}

struct SleepWorkoutCorrelationService {
    private let performanceService = WorkoutPerformanceService()
    private let scoring = SleepScoringService()

    func correlate(
        workouts: [WorkoutSession],
        sleepSessions: [ResolvedSleepSession],
        historicalSleepSessions: [SleepSession],
        settings: SleepSettings,
        endingOn evaluationDate: Date = .now,
        calendar: Calendar = .current
    ) -> [SleepWorkoutCorrelation] {
        let eligibleResolvedSleep = sleepSessions.filter { $0.endDate <= evaluationDate }
        let eligibleHistoricalSleep = historicalSleepSessions.filter {
            $0.status == .completed && $0.wakeAt <= evaluationDate
        }
        let sortedWorkouts = workouts.sorted { $0.date > $1.date }
        return sortedWorkouts.map { workout in
            let workoutDay = calendar.startOfDay(for: workout.date)
            let sleepDate = calendar.date(byAdding: .day, value: -1, to: workoutDay) ?? workoutDay.addingTimeInterval(-86_400)
            let sleep = eligibleResolvedSleep.first { calendar.isDate($0.sleepDate, inSameDayAs: sleepDate) }
            let performance = performanceService.calculatePerformanceScore(for: workout, recentWorkouts: sortedWorkouts.filter { $0.date < workout.date })
            let recoveryScore = sleep.map { scoring.score(for: $0, recentSessions: eligibleHistoricalSleep, settings: settings) }

            return SleepWorkoutCorrelation(
                workoutID: workout.id,
                workoutDate: workout.date,
                splitName: baseSplitName(workout.splitNameSnapshot),
                resolvedSleepSession: sleep,
                sleepDuration: sleep?.asleepDuration,
                sleepQuality: sleep?.qualityRating,
                recoveryScore: recoveryScore,
                performanceScore: performance.score,
                volumeCompletedRatio: performanceService.completionRatio(in: workout),
                estimatedEffort: performanceService.estimatedEffort(in: workout),
                completedVolume: performanceService.completedVolume(in: workout)
            )
        }
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }
}
