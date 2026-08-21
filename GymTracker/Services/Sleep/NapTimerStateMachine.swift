import Foundation
import SwiftData
import UserNotifications

/// A value-only timer model for the Nap Timer route.
///
/// The timer deliberately stores dates instead of an incrementing counter. A view
/// can be recreated, backgrounded, or restored from persistence without drifting
/// from wall-clock time. `completed` is only reached after the caller confirms
/// that the repository save succeeded; a failed save returns to the running or
/// elapsed state through the reducer.
struct NapTimerMachineState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case idle
        case running
        case elapsed
        case finishing
        case completed
        case discardConfirmation
    }

    var phase: Phase
    var selectedMinutes: Int
    var startedAt: Date?
    var plannedEndAt: Date?
    var endDate: Date?
    var lastError: NapTimerError?

    static func idle(selectedMinutes: Int = 30) -> NapTimerMachineState {
        NapTimerMachineState(
            phase: .idle,
            selectedMinutes: max(NapTimerStateMachine.minimumDurationMinutes, selectedMinutes),
            startedAt: nil,
            plannedEndAt: nil,
            endDate: nil,
            lastError: nil
        )
    }

    var isActive: Bool {
        switch phase {
        case .running, .elapsed, .finishing, .discardConfirmation:
            return true
        case .idle, .completed:
            return false
        }
    }

    /// Elapsed seconds derived from the state dates at the supplied instant.
    func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }

        switch phase {
        case .idle:
            return 0
        case .running, .discardConfirmation:
            return max(0, now.timeIntervalSince(startedAt))
        case .elapsed:
            guard let plannedEndAt else { return max(0, now.timeIntervalSince(startedAt)) }
            return max(0, plannedEndAt.timeIntervalSince(startedAt))
        case .finishing, .completed:
            guard let endDate else { return max(0, now.timeIntervalSince(startedAt)) }
            return max(0, endDate.timeIntervalSince(startedAt))
        }
    }

    /// Remaining seconds derived from the planned end date.
    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle:
            return TimeInterval(max(0, selectedMinutes) * 60)
        case .running, .discardConfirmation:
            guard let plannedEndAt else { return 0 }
            return max(0, plannedEndAt.timeIntervalSince(now))
        case .elapsed, .finishing, .completed:
            return 0
        }
    }

    /// The only end date that may be persisted for a running timer.
    ///
    /// Finishing before the planned end uses the actual finish time. Finishing
    /// after the planned end uses the planned end, so this value can never be in
    /// the future relative to `now`.
    func effectiveEndDate(at now: Date) -> Date? {
        guard let startedAt, let plannedEndAt else { return nil }
        guard now >= startedAt else { return nil }
        return min(now, plannedEndAt)
    }
}

enum NapTimerError: String, Codable, LocalizedError, Equatable, Sendable {
    case invalidDuration
    case notRunning
    case tooShort
    case clockBeforeStart
    case cannotDiscardWhileIdle

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Choose a nap duration of at least 10 minutes."
        case .notRunning:
            return "There is no nap timer in progress."
        case .tooShort:
            return "Nap timers must run for at least 10 minutes before they can be saved."
        case .clockBeforeStart:
            return "The device clock moved before the timer started. Keep the timer running and try again."
        case .cannotDiscardWhileIdle:
            return "There is no active nap timer to discard."
        }
    }
}

struct NapTimerCompletion: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}

enum NapTimerAction: Equatable, Sendable {
    case selectDuration(minutes: Int)
    case start(now: Date)
    case tick(now: Date)
    case finish(now: Date)
    case finishSucceeded
    case finishFailed
    case requestDiscard
    case confirmDiscard
    case cancelDiscard(now: Date)
    case reset
}

enum NapTimerEffect: Equatable, Sendable {
    case none
    case persist(NapTimerCompletion)
    case discard
    case error(NapTimerError)
}

struct NapTimerTransition: Equatable, Sendable {
    let state: NapTimerMachineState
    let effect: NapTimerEffect
}

/// Pure reducer for Nap Timer lifecycle and destructive-action confirmation.
enum NapTimerStateMachine {
    static let minimumDurationMinutes = 10

    static func reduce(_ state: NapTimerMachineState, _ action: NapTimerAction) -> NapTimerTransition {
        switch action {
        case let .selectDuration(minutes):
            guard state.phase == .idle, minutes >= minimumDurationMinutes else {
                return transition(state, effect: .error(.invalidDuration))
            }
            return transition(
                NapTimerMachineState(
                    phase: .idle,
                    selectedMinutes: minutes,
                    startedAt: nil,
                    plannedEndAt: nil,
                    endDate: nil,
                    lastError: nil
                )
            )

        case let .start(now):
            guard state.phase == .idle, state.selectedMinutes >= minimumDurationMinutes else {
                return transition(state, effect: .error(.invalidDuration))
            }
            let plannedEndAt = now.addingTimeInterval(TimeInterval(state.selectedMinutes * 60))
            return transition(
                NapTimerMachineState(
                    phase: .running,
                    selectedMinutes: state.selectedMinutes,
                    startedAt: now,
                    plannedEndAt: plannedEndAt,
                    endDate: nil,
                    lastError: nil
                )
            )

        case let .tick(now):
            guard state.phase == .running,
                  let plannedEndAt = state.plannedEndAt,
                  now >= plannedEndAt else {
                return transition(state)
            }
            return transition(
                state.with(phase: .elapsed, lastError: nil)
            )

        case let .finish(now):
            guard state.phase == .running || state.phase == .elapsed else {
                return transition(state, effect: .error(.notRunning))
            }
            guard let startedAt = state.startedAt, let plannedEndAt = state.plannedEndAt else {
                return transition(state, effect: .error(.notRunning))
            }
            guard now >= startedAt else {
                return transition(state.with(lastError: .clockBeforeStart), effect: .error(.clockBeforeStart))
            }

            let endDate = min(now, plannedEndAt)
            let completion = NapTimerCompletion(startDate: startedAt, endDate: endDate)
            guard completion.duration >= TimeInterval(minimumDurationMinutes * 60) else {
                return transition(state.with(lastError: .tooShort), effect: .error(.tooShort))
            }

            return transition(
                state.with(phase: .finishing, endDate: endDate, lastError: nil),
                effect: .persist(completion)
            )

        case .finishSucceeded:
            guard state.phase == .finishing else { return transition(state) }
            return transition(state.with(phase: .completed, lastError: nil))

        case .finishFailed:
            guard state.phase == .finishing else { return transition(state) }
            let phase: NapTimerMachineState.Phase
            if let plannedEndAt = state.plannedEndAt, let now = state.endDate {
                phase = now >= plannedEndAt ? .elapsed : .running
            } else {
                phase = .running
            }
            return transition(state.with(phase: phase, clearEndDate: true))

        case .requestDiscard:
            guard state.isActive else {
                return transition(state, effect: .error(.cannotDiscardWhileIdle))
            }
            guard state.phase != .finishing else { return transition(state) }
            return transition(state.with(phase: .discardConfirmation, lastError: nil))

        case .confirmDiscard:
            guard state.phase == .discardConfirmation else { return transition(state) }
            return transition(.idle(selectedMinutes: state.selectedMinutes), effect: .discard)

        case let .cancelDiscard(now):
            guard state.phase == .discardConfirmation else { return transition(state) }
            let phase: NapTimerMachineState.Phase
            if let plannedEndAt = state.plannedEndAt, now >= plannedEndAt {
                phase = .elapsed
            } else {
                phase = .running
            }
            return transition(state.with(phase: phase, lastError: nil))

        case .reset:
            return transition(.idle(selectedMinutes: state.selectedMinutes))
        }
    }

    private static func transition(_ state: NapTimerMachineState, effect: NapTimerEffect = .none) -> NapTimerTransition {
        NapTimerTransition(state: state, effect: effect)
    }
}

private extension NapTimerMachineState {
    func with(
        phase: Phase? = nil,
        endDate: Date? = nil,
        clearEndDate: Bool = false,
        lastError: NapTimerError? = nil
    ) -> NapTimerMachineState {
        NapTimerMachineState(
            phase: phase ?? self.phase,
            selectedMinutes: selectedMinutes,
            startedAt: startedAt,
            plannedEndAt: plannedEndAt,
            endDate: clearEndDate ? nil : endDate ?? self.endDate,
            lastError: lastError
        )
    }
}
