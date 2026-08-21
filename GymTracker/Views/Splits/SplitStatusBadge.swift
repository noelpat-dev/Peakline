import SwiftUI

enum SplitStatus: Hashable {
    case ready
    case recentlyTrained
    case progressOpportunity
    case prioritise
    case inactive
    case custom

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .recentlyTrained:
            return "Recent"
        case .progressOpportunity:
            return "Progress"
        case .prioritise:
            return "Prioritise"
        case .inactive:
            return "Inactive"
        case .custom:
            return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            return "checkmark"
        case .recentlyTrained:
            return "clock.arrow.circlepath"
        case .progressOpportunity:
            return "arrow.up"
        case .prioritise:
            return "exclamationmark"
        case .inactive:
            return "pause"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

struct SplitStatusBadge: View {
    let status: SplitStatus

    var body: some View {
        StatusBadge(status.title, systemImage: status.systemImage, role: role)
            .accessibilityElement(children: .combine)
    }

    private var role: StatusBadge.Role {
        switch status {
        case .ready, .progressOpportunity:
            return .accent
        case .recentlyTrained, .inactive, .custom:
            return .neutral
        case .prioritise:
            return .warning
        }
    }
}
