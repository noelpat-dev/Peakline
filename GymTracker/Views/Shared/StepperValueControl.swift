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
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 0) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .frame(width: 38, height: 38)
                }
                .disabled(!canDecrement)

                Button(action: edit) {
                    HStack(spacing: 3) {
                        Text(valueText)
                            .font(.system(.headline, design: .rounded).monospacedDigit().weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if let unitSuffix {
                            Text(unitSuffix)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 38, height: 38)
                }
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
}
