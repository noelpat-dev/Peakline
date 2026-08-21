import SwiftUI

struct StepperValueControl: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let valueText: String
    let unitSuffix: String?
    let canDecrement: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let edit: () -> Void

    @State private var direction: ValueDirection = .neutral

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
                    direction = .decrement
                    decrement()
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.badge)
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                }
                .disabled(!canDecrement)
                .accessibilityLabel("Decrease \(label)")
                .accessibilityValue(currentValueAccessibilityText)
                .accessibilityIdentifier("stepper-\(identifierBase)-decrement")

                Button {
                    edit()
                } label: {
                    HStack(spacing: 3) {
                        Text(valueText)
                            .font(AppTypography.workoutNumber)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .contentTransition(
                                reduceMotion
                                    ? .opacity
                                    : .numericText(countsDown: direction == .decrement)
                            )
                            .animation(
                                reduceMotion
                                    ? AppMotion.reducedMotionAnimation(policy: .immediate)
                                    : .easeInOut(duration: AppMotion.stepperRollDuration),
                                value: valueText
                            )

                        if let unitSuffix {
                            Text(unitSuffix)
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(label)")
                .accessibilityValue(currentValueAccessibilityText)
                .accessibilityIdentifier("stepper-\(identifierBase)-edit")

                Button {
                    direction = .increment
                    increment()
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.badge)
                        .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                }
                .accessibilityLabel("Increase \(label)")
                .accessibilityValue(currentValueAccessibilityText)
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

    private var currentValueAccessibilityText: String {
        if let unitSuffix {
            return "\(valueText) \(unitSuffix)"
        }

        return valueText
    }

    private enum ValueDirection {
        case neutral
        case increment
        case decrement
    }
}
