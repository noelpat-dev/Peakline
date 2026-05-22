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
            Section("Weights") {
                Stepper("Target: \(format(targetWeight))kg", value: $targetWeight, in: 20...400, step: 2.5)
                Stepper("Bar: \(format(barWeight))kg", value: $barWeight, in: 5...30, step: 1)
            }

            Section {
                if plateCounts.isEmpty {
                    Text("No plates needed.")
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(Array(plateCounts.keys.sorted(by: >)), id: \.self) { plate in
                        LabeledContent("\(format(plate))kg", value: "x\(plateCounts[plate, default: 0])")
                    }
                }
            } footer: {
                Text("Load this plate stack on each side of a \(format(barWeight))kg bar.")
            }
        }
        .navigationTitle("Plate Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
