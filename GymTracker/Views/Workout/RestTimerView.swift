import SwiftUI

struct RestTimerView: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var state: RestTimerState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let endDate = state.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = max(0, Int(endDate.timeIntervalSince(timeline.date)))

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(remainingText(remaining), systemImage: "timer")
                                .font(.headline.monospacedDigit())
                            if let exerciseName = state.exerciseName {
                                Text(nextSetText(exerciseName: exerciseName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("+30s") {
                            state.endDate = (state.endDate ?? Date()).addingTimeInterval(30)
                        }
                        .buttonStyle(.borderless)

                        Button("Skip") {
                            state = RestTimerState()
                        }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: remaining) { _, newValue in
                        if newValue == 0 {
                            state = RestTimerState()
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach([60, 90, 120, 180], id: \.self) { duration in
                    Button("\(duration / 60):\(String(format: "%02d", duration % 60))") {
                        state.endDate = Date().addingTimeInterval(TimeInterval(duration))
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
        .tint(appTheme.colors.accent)
    }

    private func nextSetText(exerciseName: String) -> String {
        if let nextSetNumber = state.nextSetNumber {
            return "\(exerciseName) - next set \(nextSetNumber)"
        }

        return exerciseName
    }

    private func remainingText(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
