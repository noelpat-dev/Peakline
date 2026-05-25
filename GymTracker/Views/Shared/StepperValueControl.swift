import SwiftUI

struct StepperValueControl: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let valueText: String
    let unitSuffix: String?
    let canDecrement: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let edit: () -> Void

    init(
        label: String,
        valueText: String,
        unitSuffix: String? = nil,
        canDecrement: Bool = true,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        edit: @escaping () -> Void
    ) {
        self.label = label
        self.valueText = valueText
        self.unitSuffix = unitSuffix
        self.canDecrement = canDecrement
        self.decrement = decrement
        self.increment = increment
        self.edit = edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 0) {
                Button {
                    AppHaptics.selection()
                    decrement()
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.badge)
                        .frame(width: 38, height: 38)
                }
                .disabled(!canDecrement)
                .accessibilityIdentifier("stepper-\(identifierBase)-decrement")

                Button {
                    AppHaptics.selection()
                    edit()
                } label: {
                    HStack(spacing: 3) {
                        Text(valueText)
                            .font(AppTypography.workoutNumber)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if let unitSuffix {
                            Text(unitSuffix)
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stepper-\(identifierBase)-edit")

                Button {
                    AppHaptics.selection()
                    increment()
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.badge)
                        .frame(width: 38, height: 38)
                }
                .accessibilityIdentifier("stepper-\(identifierBase)-increment")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(appTheme.colors.textPrimary)
            .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(appTheme.colors.cardBorder, lineWidth: 1)
            )
        }
    }

    private var identifierBase: String {
        let filtered = label.lowercased().filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? "value" : String(filtered)
    }
}
