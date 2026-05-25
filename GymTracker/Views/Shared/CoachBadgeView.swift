import SwiftUI

enum CoachBadgeState: String, CaseIterable {
    case baseline
    case addReps
    case repeatTarget
    case increaseLoad
    case reduceLoad
    case possiblePlateau
    case fatigueRisk
    case ready
    case recovery
    case missedSplit
    case pr

    init(recommendationType: TargetRecommendationType) {
        switch recommendationType {
        case .baseline:
            self = .baseline
        case .addReps:
            self = .addReps
        case .repeatTarget:
            self = .repeatTarget
        case .increaseLoad:
            self = .increaseLoad
        case .reduceLoad:
            self = .reduceLoad
        case .possiblePlateau:
            self = .possiblePlateau
        case .fatigueRisk:
            self = .fatigueRisk
        case .ready:
            self = .ready
        }
    }

    var label: String {
        switch self {
        case .baseline:
            return "Baseline"
        case .addReps:
            return "Add reps"
        case .repeatTarget:
            return "Repeat"
        case .increaseLoad:
            return "Increase"
        case .reduceLoad:
            return "Reduce"
        case .possiblePlateau:
            return "Plateau"
        case .fatigueRisk:
            return "Fatigue"
        case .ready:
            return "Ready"
        case .recovery:
            return "Recovery"
        case .missedSplit:
            return "Due"
        case .pr:
            return "PR"
        }
    }

    var systemImage: String {
        switch self {
        case .baseline:
            return "scope"
        case .addReps:
            return "plus"
        case .repeatTarget:
            return "repeat"
        case .increaseLoad:
            return "arrow.up"
        case .reduceLoad:
            return "arrow.down"
        case .possiblePlateau:
            return "exclamationmark.triangle"
        case .fatigueRisk:
            return "bolt.slash"
        case .ready:
            return "checkmark"
        case .recovery:
            return "leaf"
        case .missedSplit:
            return "calendar.badge.exclamationmark"
        case .pr:
            return "star"
        }
    }
}

struct CoachBadgeView: View {
    @Environment(\.appTheme) private var appTheme

    let state: CoachBadgeState

    init(state: CoachBadgeState) {
        self.state = state
    }

    init(recommendationType: TargetRecommendationType) {
        self.state = CoachBadgeState(recommendationType: recommendationType)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.systemImage)
                .font(AppTypography.badge)
            Text(state.label)
                .font(AppTypography.chip)
        }
        .padding(.horizontal, appTheme.metrics.spacing10)
        .padding(.vertical, appTheme.metrics.spacing6)
        .foregroundStyle(foregroundColor)
        .background(badgeColor.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var badgeColor: Color {
        switch state {
        case .baseline, .repeatTarget:
            return .secondary
        case .addReps, .increaseLoad, .ready, .pr:
            return appTheme.successColor
        case .reduceLoad, .possiblePlateau, .fatigueRisk, .recovery, .missedSplit:
            return appTheme.warningColor
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .baseline, .repeatTarget:
            return .secondary
        case .addReps, .increaseLoad, .ready, .pr:
            return appTheme.successColor
        case .reduceLoad, .possiblePlateau, .fatigueRisk, .recovery, .missedSplit:
            return appTheme.warningColor
        }
    }
}
