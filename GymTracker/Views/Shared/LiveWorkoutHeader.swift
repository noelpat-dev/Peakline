import SwiftUI

struct LiveWorkoutHeader: View {
    @Environment(\.appTheme) private var appTheme

    let startedAt: Date
    let endedAt: Date?
    let pausedAt: Date?
    let accumulatedPausedSeconds: Int
    let currentExerciseIndex: Int
    let totalExercises: Int
    let togglePause: () -> Void
    let finish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let displayDate = endedAt ?? timeline.date
            let isPaused = pausedAt != nil

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPaused ? "Workout paused" : "Live workout")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text(totalExercises == 0 ? "No exercises selected" : "Exercise \(min(currentExerciseIndex + 1, totalExercises)) of \(totalExercises)")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textPrimary)
                    }

                    Spacer()

                    Text(elapsedText(at: displayDate))
                        .font(AppTypography.workoutLargeNumber)
                        .foregroundStyle(isPaused ? appTheme.mutedText : appTheme.colors.accent)
                }

                SwiftUI.ProgressView(value: totalExercises == 0 ? 0 : Double(min(currentExerciseIndex + 1, totalExercises)), total: Double(max(totalExercises, 1)))
                    .tint(appTheme.colors.accentHighlight)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        pauseButton(isPaused: isPaused)
                        finishButton
                    }

                    VStack(spacing: 10) {
                        pauseButton(isPaused: isPaused)
                        finishButton
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func pauseButton(isPaused: Bool) -> some View {
        Button {
            AppHaptics.selection()
            togglePause()
        } label: {
            Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeutralFitnessButtonStyle())
        .disabled(endedAt != nil)
        .accessibilityIdentifier(isPaused ? "workout-logger-resume" : "workout-logger-pause")
    }

    private var finishButton: some View {
        Button {
            AppHaptics.success()
            finish()
        } label: {
            Label("Finish", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
        .accessibilityIdentifier("workout-logger-finish")
    }

    private func elapsedText(at date: Date) -> String {
        let livePauseSeconds: Int
        if let pausedAt {
            livePauseSeconds = max(0, Int(date.timeIntervalSince(pausedAt)))
        } else {
            livePauseSeconds = 0
        }

        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)) - accumulatedPausedSeconds - livePauseSeconds)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
