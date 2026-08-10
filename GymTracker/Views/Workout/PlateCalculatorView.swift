import SwiftUI

struct PlateCalculatorView: View {
    @Environment(\.appTheme) private var appTheme

    @State private var targetWeight: Double
    @State private var barWeight = 20.0

    private let calculator = PlateCalculator()

    init(targetWeight: Double = 100) {
        _targetWeight = State(initialValue: max(20, targetWeight))
    }

    private var plateCounts: [Double: Int] {
        calculator.plateCounts(targetWeight: targetWeight, barWeight: barWeight)
    }

    var body: some View {
        Form {
            Section {
                Text("Metric only. Enter the total barbell weight in kilograms. During a live workout, open this calculator beside a set to prefill that set's load.")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)

                Stepper("Target: \(format(targetWeight)) kg", value: $targetWeight, in: 20...400, step: 2.5)
                    .accessibilityLabel("Target weight")
                    .accessibilityValue("\(format(targetWeight)) kilograms")
                    .accessibilityIdentifier("plate-calculator-target")

                Stepper("Bar: \(format(barWeight)) kg", value: $barWeight, in: 5...30, step: 1)
                    .accessibilityLabel("Bar weight")
                    .accessibilityValue("\(format(barWeight)) kilograms")
                    .accessibilityIdentifier("plate-calculator-bar")
            } header: {
                Text("Metric Weights")
            }

            Section {
                if plateCounts.isEmpty {
                    Text("No plates needed.")
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(Array(plateCounts.keys.sorted(by: >)), id: \.self) { plate in
                        LabeledContent("\(format(plate)) kg", value: "× \(plateCounts[plate, default: 0])")
                    }
                }
            } header: {
                Text("Plates Per Side")
            } footer: {
                Text("Load this plate stack on each side of a \(format(barWeight)) kg bar.")
            }
        }
        .peaklineGroupedContent()
        .navigationTitle("Plate Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("plate-calculator-screen")
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
