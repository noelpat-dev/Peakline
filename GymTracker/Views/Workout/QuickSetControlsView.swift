import SwiftUI

struct QuickSetControlsView: View {
    @Environment(\.appTheme) private var appTheme

    let canCopyPrevious: Bool
    let canCopyLastSession: Bool
    let suggestion: String
    let copyPrevious: () -> Void
    let copyLastSession: () -> Void
    let markComplete: () -> Void
    var completeTitle = "Complete"
    var completeAccessibilityIdentifier = "quick-set-complete"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                quickButton("Copy previous", systemImage: "doc.on.doc", action: copyPrevious)
                    .disabled(!canCopyPrevious)
                quickButton("Copy last", systemImage: "clock.arrow.circlepath", action: copyLastSession)
                    .disabled(!canCopyLastSession)
                quickButton(
                    completeTitle,
                    systemImage: "checkmark.circle.fill",
                    accessibilityIdentifier: completeAccessibilityIdentifier,
                    action: markComplete
                )
            }

            Text(suggestion)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quickButton(
        _ title: String,
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(AppTypography.metadataEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(appTheme.colors.textPrimary)
        .accessibilityIdentifier(accessibilityIdentifier ?? "quick-set-\(identifier(for: title))")
    }

    private func identifier(for title: String) -> String {
        let filtered = title.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let raw = String(filtered).split(separator: "-").joined(separator: "-")
        return raw.isEmpty ? "action" : raw
    }
}
