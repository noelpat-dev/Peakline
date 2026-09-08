import SwiftUI

struct RestTimerView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var state: RestTimerState
    var showsActiveTimer = true

    @State private var completionDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsActiveTimer, state.endDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = state.remainingSeconds(at: timeline.date)

                    Group {
                        if state.isComplete {
                            restCompleteContent
                        } else {
                            activeTimerContent(
                                remaining: remaining,
                                date: timeline.date
                            )
                        }
                    }
                    .transition(.opacity)
                    .onChange(of: remaining, initial: true) { _, newValue in
                        guard
                            newValue == 0,
                            !state.isComplete,
                            let endDate = state.endDate,
                            timeline.date >= endDate
                        else { return }
                        complete(at: timeline.date)
                    }
                }
            }

            if !showsActiveTimer || state.endDate == nil {
                HStack(spacing: 10) {
                    ForEach([60, 90, 120, 180], id: \.self) { duration in
                        Button(remainingText(duration)) {
                            start(durationSeconds: duration)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                    }
                }
                .accessibilityIdentifier("workout-rest-timer-presets")
            }
        }
        .tint(appTheme.colors.accent)
        .onDisappear {
            completionDismissTask?.cancel()
            completionDismissTask = nil
        }
    }

    @ViewBuilder
    private func activeTimerContent(remaining: Int, date: Date) -> some View {
        let isUrgent = remaining > 0 && remaining <= 10
        let ringColor = isUrgent ? appTheme.warningColor : appTheme.colors.accent
        let pulsePhase = remaining % 2

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(appTheme.colors.cardBorder.opacity(0.72), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: max(0.02, state.progress(at: date)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(isUrgent && !reduceMotion && pulsePhase == 0 ? 0.55 : 1)
                    .animation(
                        reduceMotion
                            ? AppMotion.reducedMotionAnimation(policy: .immediate)
                            : .easeInOut(duration: AppMotion.restUrgencyPulseDuration),
                        value: pulsePhase
                    )
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(remainingText(remaining))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(appTheme.colors.textPrimary)

                if let exerciseName = state.exerciseName {
                    Text(nextSetText(exerciseName: exerciseName))
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer()

            Button("+30s") {
                state.extend(by: 30)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)

            Button("Skip") {
                resetTimer()
            }
            .buttonStyle(.borderless)
            .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
        .accessibilityValue("\(remainingText(remaining)) remaining")
        .accessibilityIdentifier("workout-rest-timer-active")
    }

    private var restCompleteContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textSuccess)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Rest Complete")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                Text("Ready for the next set.")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            Spacer()

            Button("Dismiss") {
                resetTimer()
            }
            .buttonStyle(.borderless)
            .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest complete")
        .accessibilityValue("Ready for the next set")
        .accessibilityIdentifier("workout-rest-timer-complete")
    }

    private func start(durationSeconds: Int) {
        withAnimation(AppMotion.animation(for: .sheetPresent, reduceMotion: reduceMotion)) {
            state.start(
                durationSeconds: durationSeconds,
                exerciseName: state.exerciseName,
                nextSetNumber: state.nextSetNumber
            )
        }
    }

    private func complete(at date: Date) {
        guard !state.isComplete else { return }

        withAnimation(
            AppMotion.animation(
                for: .smooth,
                reduceMotion: reduceMotion,
                policy: .opacity
            )
        ) {
            state.markComplete(at: date)
        }

        completionDismissTask?.cancel()
        completionDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            resetTimer()
        }
    }

    private func resetTimer() {
        withAnimation(
            AppMotion.animation(
                for: .smooth,
                reduceMotion: reduceMotion,
                policy: .opacity
            )
        ) {
            state.reset()
        }
        completionDismissTask?.cancel()
        completionDismissTask = nil
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
