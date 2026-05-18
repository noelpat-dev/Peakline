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
    @Environment(\.appTheme) private var appTheme

    let status: SplitStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.caption2.weight(.bold))
            Text(status.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .ready, .progressOpportunity:
            return appTheme.colors.accent
        case .recentlyTrained, .inactive, .custom:
            return appTheme.colors.textSecondary
        case .prioritise:
            return appTheme.colors.warning
        }
    }
}
