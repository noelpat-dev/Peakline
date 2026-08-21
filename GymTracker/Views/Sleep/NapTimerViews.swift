import SwiftData
import SwiftUI

struct NapSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var start = Date.now.addingTimeInterval(-30 * 60)
    @State private var end = Date.now
    @State private var quality: Int?
    @State private var note = ""
    @State private var errorText: String?
    @State private var showingTimer = false

    private let repository = NapSessionRepository()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Log Nap",
                subtitle: "Add short recovery sleep without changing overnight data.",
                systemImage: "moonphase.first.quarter"
            ) {
                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SleepRow(
                            title: "Nap Time",
                            subtitle: "Set when the nap started and ended.",
                            systemImage: "clock"
                        )

                        DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-nap-start")
                        DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("sleep-nap-end")
                    }
                }

                SleepQuietAction(title: "Use Nap Timer", systemImage: "timer") {
                    showingTimer = true
                }
                .accessibilityIdentifier("sleep-nap-timer")

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Quality")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                    SleepQualityPicker(selection: $quality)
                        .accessibilityIdentifier("sleep-nap-quality")
                    }
                }

                SleepCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                    TextField("Felt refreshed, still tired, post-workout nap", text: $note, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(12)
                            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .accessibilityIdentifier("sleep-nap-error")
                }

                SleepActionButton(title: "Save Nap", systemImage: "checkmark", style: .primary) {
                    saveNap()
                }
                .accessibilityIdentifier("sleep-nap-save")
            }
            .navigationTitle("Log Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingTimer) {
                NapTimerView()
            }
        }
    }

    private func saveNap() {
        do {
            try repository.addNap(start: start, end: end, quality: quality, note: note, in: modelContext)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct NapTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var timerState = NapTimerMachineState.idle(selectedMinutes: 30)
    @State private var now = Date.now
    @State private var quality: Int?
    @State private var errorText: String?
    @State private var showingCloseConfirmation = false

    private let options = [20, 30, 45, 90]
    private let repository = NapSessionRepository()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Nap Timer",
                subtitle: "Set a short recovery window. The saved end time always comes from the clock.",
                systemImage: "timer"
            ) {
                SleepCard(style: .hero) {
                    VStack(alignment: .center, spacing: 14) {
                        SleepIcon(systemImage: timerState.phase == .idle ? "timer" : "moon.zzz.fill", size: 60)

                        Text(timerText)
                            .font(AppTypography.heroMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                            .accessibilityIdentifier("sleep-nap-timer-value")

                        Text(stateTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sleep-nap-timer-hero")

                SleepCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Timer length")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Menu {
                            ForEach(options, id: \.self) { minutes in
                                Button("\(minutes) minutes") {
                                    transition(.selectDuration(minutes: minutes))
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(timerState.selectedMinutes) minutes")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
                        }
                        .disabled(timerState.phase != .idle)
                        .accessibilityLabel("Nap timer length")
                        .accessibilityValue("\(timerState.selectedMinutes) minutes")
                        .accessibilityIdentifier("sleep-nap-timer-length")

                        SleepQualityPicker(selection: $quality)
                            .disabled(timerState.phase != .idle)
                            .accessibilityIdentifier("sleep-nap-timer-quality")
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sleep-nap-timer-error")
                }

                SleepActionButton(
                    title: primaryActionTitle,
                    systemImage: primaryActionSystemImage,
                    style: .primary
                ) {
                    switch timerState.phase {
                    case .idle:
                        transition(.start(now: timerStartDate))
                    case .running, .elapsed:
                        finishNap()
                    case .completed:
                        dismiss()
                    case .finishing, .discardConfirmation:
                        break
                    }
                }
                .disabled(timerState.phase == .finishing || timerState.phase == .discardConfirmation)
                .accessibilityIdentifier("sleep-nap-timer-primary")
            }
            .navigationTitle("Nap Timer")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(timerState.isActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { requestClose() }
                        .disabled(timerState.phase == .finishing)
                        .accessibilityIdentifier("sleep-nap-timer-close")
                }
            }
            .onReceive(timer) { value in
                now = value
                transition(.tick(now: value))
            }
            .alert("Discard nap timer?", isPresented: $showingCloseConfirmation) {
                Button("Keep Timer", role: .cancel) {
                    transition(.cancelDiscard(now: .now))
                }
                Button("Discard", role: .destructive) {
                    transition(.confirmDiscard)
                    dismiss()
                }
            } message: {
                Text("The running timer has not been saved.")
            }
        }
    }

    private var elapsedSeconds: Int {
        Int(timerState.elapsed(at: now))
    }

    private var timerText: String {
        guard timerState.phase != .idle else { return "\(timerState.selectedMinutes):00" }
        return "\(elapsedSeconds / 60):\(String(format: "%02d", elapsedSeconds % 60))"
    }

    private var stateTitle: String {
        switch timerState.phase {
        case .idle:
            return "Ready when you are"
        case .running:
            return "Nap in progress"
        case .elapsed:
            return "Target reached · finish when ready"
        case .finishing:
            return "Saving nap"
        case .completed:
            return "Nap saved"
        case .discardConfirmation:
            return "Confirm discard"
        }
    }

    private var primaryActionTitle: String {
        switch timerState.phase {
        case .idle:
            return "Start Nap Timer"
        case .running, .elapsed:
            return "Finish Nap"
        case .finishing:
            return "Saving…"
        case .completed:
            return "Done"
        case .discardConfirmation:
            return "Finish Nap"
        }
    }

    private var primaryActionSystemImage: String {
        switch timerState.phase {
        case .idle:
            return "timer"
        case .finishing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .running, .elapsed, .discardConfirmation:
            return "checkmark.circle.fill"
        }
    }

    private var timerStartDate: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestNapElapsedFixture") {
            return Date.now.addingTimeInterval(-11 * 60)
        }
        #endif
        return .now
    }

    private func requestClose() {
        guard timerState.isActive else {
            dismiss()
            return
        }
        transition(.requestDiscard)
        showingCloseConfirmation = true
    }

    private func finishNap() {
        let transition = NapTimerStateMachine.reduce(timerState, .finish(now: .now))
        timerState = transition.state
        errorText = nil

        switch transition.effect {
        case let .persist(completion):
            do {
                try repository.addNap(
                    start: completion.startDate,
                    end: completion.endDate,
                    quality: quality,
                    note: "Nap timer",
                    source: .napTimer,
                    in: modelContext
                )
                timerState = NapTimerStateMachine.reduce(timerState, .finishSucceeded).state
            } catch {
                timerState = NapTimerStateMachine.reduce(timerState, .finishFailed).state
                errorText = error.localizedDescription
            }
        case let .error(error):
            errorText = error == .tooShort
                ? "Keep the timer running for at least 10 minutes before saving a nap."
                : error.localizedDescription
        case .none, .discard:
            break
        }
    }

    private func transition(_ action: NapTimerAction) {
        let result = NapTimerStateMachine.reduce(timerState, action)
        timerState = result.state
        if case let .error(error) = result.effect {
            errorText = error.localizedDescription
        } else {
            switch action {
            case .tick, .finishFailed:
                break
            default:
                errorText = nil
            }
        }
    }
}

