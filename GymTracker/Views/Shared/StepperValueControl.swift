import SwiftUI

struct StepperValueControl: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let valueText: String
    let numericValue: Double
    let unitSuffix: String?
    let canDecrement: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let edit: () -> Void

    @State private var direction: StepperValueDirection = .neutral
    @State private var renderedValueText: String

    init(
        label: String,
        valueText: String,
        numericValue: Double,
        unitSuffix: String? = nil,
        canDecrement: Bool = true,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        edit: @escaping () -> Void
    ) {
        self.label = label
        self.valueText = valueText
        self.numericValue = numericValue
        self.unitSuffix = unitSuffix
        self.canDecrement = canDecrement
        self.decrement = decrement
        self.increment = increment
        self.edit = edit
        _renderedValueText = State(initialValue: valueText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)

            HStack(spacing: 0) {
                Button {
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
                        Text(renderedValueText)
                            .font(AppTypography.workoutNumber)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .contentTransition(transition.contentTransition)
                            .animation(transition.animation, value: renderedValueText)

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
        .onChange(of: displayInput) { oldValue, newValue in
            direction = StepperValueDirection.derived(
                from: oldValue.numericValue,
                to: newValue.numericValue
            )
            renderedValueText = newValue.text
        }
    }

    private var transition: StepperValueTransition {
        StepperValueTransition.resolve(reduceMotion: reduceMotion, direction: direction)
    }

    private var displayInput: DisplayInput {
        DisplayInput(numericValue: numericValue, text: valueText)
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

    private struct DisplayInput: Equatable {
        let numericValue: Double
        let text: String
    }
}

/// Direction of the last typed or stepped change, derived from the numeric
/// values rather than from the most recently tapped button.
enum StepperValueDirection: Equatable {
    case neutral
    case increment
    case decrement

    static func derived(from previousValue: Double, to newValue: Double) -> StepperValueDirection {
        if newValue > previousValue {
            return .increment
        }

        if newValue < previousValue {
            return .decrement
        }

        return .neutral
    }
}

/// Numeric roll vs. Reduce Motion direct-state behaviour for the stepper value.
enum StepperValueTransition: Equatable {
    case immediate
    case numericRoll(direction: StepperValueDirection)

    static func resolve(reduceMotion: Bool, direction: StepperValueDirection) -> StepperValueTransition {
        guard !reduceMotion, direction != .neutral else {
            return .immediate
        }

        return .numericRoll(direction: direction)
    }

    var contentTransition: ContentTransition {
        switch self {
        case .immediate:
            return .opacity
        case .numericRoll(let direction):
            return .numericText(countsDown: direction == .decrement)
        }
    }

    var animation: Animation {
        switch self {
        case .immediate:
            return AppMotion.reducedMotionAnimation(policy: .immediate)
        case .numericRoll:
            return .easeInOut(duration: AppMotion.stepperRollDuration)
        }
    }
}
