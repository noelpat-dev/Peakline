import SwiftData
import SwiftUI

struct SleepModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Query
    private var sessions: [SleepSession]

    @Query
    private var workouts: [WorkoutSession]

    @Binding var settings: SleepSettings
    @State private var selectedMinutes: Int
    @State private var now = Date()
    @State private var errorMessage: String?

    private let repository = SleepSessionRepository()

    init(settings: Binding<SleepSettings>) {
        self._settings = settings
        self._selectedMinutes = State(initialValue: settings.wrappedValue.defaultWindDownMinutes)
        self._sessions = Query(Self.sessionsDescriptor)
        self._workouts = Query(Self.workoutsDescriptor)
    }

    private static var sessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.colors.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        windDownSummary
                        windDownOptionsCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 150)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom) {
                sleepModeActions
            }
            .navigationTitle("Sleep Mode")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sleep-mode-close")
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { value in
                now = value
            }
        }
    }

    private var windDownSummary: some View {
        SleepCard(style: .hero, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind-down")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(durationHeadline)
                            .font(AppTypography.heroMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 5) {
                        FitnessIconBadge(
                            systemImage: "bed.double.fill",
                            size: 44,
                            tint: appTheme.colors.textPrimary,
                            background: appTheme.colors.cardBackgroundElevated
                        )

                        Text(selectedMinutes == 0 ? "Tracking now" : "Tracking later")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(appTheme.colors.cardBackgroundElevated)

                            Capsule()
                                .fill(appTheme.colors.accent)
                                .frame(width: proxy.size.width * windDownFraction)
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Estimated start")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)

                        Spacer(minLength: 8)

                        Text(estimatedStart.formatted(date: .omitted, time: .shortened))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var windDownOptionsCard: some View {
        SleepCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wind-down length")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Spacer(minLength: 8)

                        Text("You can adjust the start in the morning")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind-down length")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("You can adjust the start in the morning")
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(SleepSettings.windDownOptions, id: \.self) { minutes in
                        SleepWindDownOptionButton(
                            minutes: minutes,
                            isSelected: minutes == selectedMinutes
                        ) {
                            selectedMinutes = minutes
                        }
                        .accessibilityIdentifier("sleep-mode-winddown-\(minutes)")
                    }
                }
            }
        }
    }

    private var sleepModeActions: some View {
        VStack(spacing: 10) {
            SleepModeActionButton(title: "Start Sleep Mode", systemImage: "moon.zzz.fill", style: .primary) {
                start(minutes: selectedMinutes)
            }
            .accessibilityIdentifier("sleep-mode-start")

            Button("Start now") {
                start(minutes: 0)
            }
            .font(AppTypography.bodyEmphasis)
            .foregroundStyle(appTheme.colors.textSecondary)
            .frame(minHeight: appTheme.metrics.minimumHitTarget)
            .accessibilityIdentifier("sleep-mode-start-now")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            reduceTransparency
                ? AnyShapeStyle(appTheme.colors.cardBackground)
                : AnyShapeStyle(.thinMaterial)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appTheme.colors.cardBorder)
                .frame(height: 1)
        }
    }

    private var estimatedStart: Date {
        now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
    }

    private var durationHeadline: String {
        selectedMinutes == 0 ? "Now" : "\(selectedMinutes) min"
    }

    private var windDownFraction: CGFloat {
        CGFloat(max(0.12, Double(selectedMinutes) / Double(SleepSettings.windDownOptions.max() ?? 60)))
    }

    private func start(minutes: Int) {
        do {
            _ = try repository.startSleepMode(windDownMinutes: minutes, in: modelContext)
            settings.defaultWindDownMinutes = minutes == 0 ? settings.defaultWindDownMinutes : minutes
            let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sessions)
            let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
            let notificationSettings = settings
            Task {
                await SleepNotificationScheduler().refreshAllSleepNotifications(settings: notificationSettings, sessions: sessionSnapshots, workouts: workoutSnapshots)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SleepWindDownOptionButton: View {
    @Environment(\.appTheme) private var appTheme

    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Text("\(minutes)m")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? appTheme.colors.accentForeground : appTheme.colors.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
        }
        .buttonStyle(PeaklineButtonPressStyle())
        .accessibilityLabel("\(minutes) minute wind-down")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        isSelected ? appTheme.colors.accent : appTheme.colors.cardBackgroundElevated
    }

    private var border: Color {
        isSelected ? appTheme.colors.accent.opacity(0.36) : appTheme.colors.cardBorder
    }
}

private struct SleepModeActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppTypography.compactCardTitle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: style == .primary ? 58 : 52)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return appTheme.colors.accentForeground
        case .secondary:
            return appTheme.colors.textPrimary
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent
        case .secondary:
            return appTheme.colors.cardBackgroundElevated
        }
    }

    private var border: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent.opacity(0.4)
        case .secondary:
            return appTheme.colors.cardBorder
        }
    }
}

