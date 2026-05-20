import SwiftUI

enum CelebrationStyle {
    case nextExercise
    case completedWorkout
    case pr
    case recovery
}

struct WorkoutCelebrationOverlay: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let message: String
    let icon: String
    let primaryActionTitle: String
    let primaryActionIcon: String?
    var style: CelebrationStyle = .nextExercise
    let isVisible: Bool
    var isPrimaryActionDisabled = false
    let primaryAction: () -> Void

    @State private var iconPulse = false
    @State private var contentRevealed = false
    @State private var buttonRevealed = false

    var body: some View {
        ZStack {
            backdrop

            LiquidGlassPopupCard(cornerRadius: 34, padding: 24) {
                VStack(spacing: 18) {
                    celebrationIcon

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)

                        Text(message)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scaleEffect(reduceMotion ? 1 : (contentRevealed ? 1 : 0.98))
                    .opacity(contentRevealed ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (contentRevealed ? 0 : 6))

                    Button(action: primaryAction) {
                        Label {
                            Text(primaryActionTitle)
                        } icon: {
                            if let primaryActionIcon {
                                Image(systemName: primaryActionIcon)
                            }
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isPrimaryActionDisabled)
                    .accessibilityLabel(primaryActionTitle)
                    .scaleEffect(reduceMotion ? 1 : (buttonRevealed ? 1 : 0.96))
                    .opacity(buttonRevealed ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (buttonRevealed ? 0 : 8))
                }
            }
            .frame(maxWidth: 430)
            .padding(.horizontal, 20)
            .smoothPopupCardMotion(
                isVisible: isVisible,
                reduceMotion: reduceMotion,
                hiddenScale: 0.94,
                hiddenOffset: 28
            )
        }
        .ignoresSafeArea()
        .onAppear {
            updateContentVisibility(isVisible)
        }
        .onChange(of: isVisible) { _, newValue in
            updateContentVisibility(newValue)
        }
    }

    private var celebrationIcon: some View {
        ZStack {
            Circle()
                .stroke(iconTint.opacity(0.28), lineWidth: 1.5)
                .frame(width: 92, height: 92)
                .scaleEffect(reduceMotion ? 1 : (iconPulse ? 1.45 : 0.72))
                .opacity(reduceMotion ? 0.24 : (iconPulse ? 0 : 0.62))

            Circle()
                .fill(iconTint.opacity(0.10))
                .frame(width: 88, height: 88)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.82))

            GlassIconBadge(systemName: iconName, size: 70)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.78))
        }
        .accessibilityHidden(true)
    }

    private var backdrop: some View {
        LiquidGlassPopupBackdrop(isVisible: isVisible)
    }

    private var iconTint: Color {
        switch style {
        case .completedWorkout:
            return appTheme.successColor
        case .pr:
            return appTheme.warningColor
        case .recovery:
            return appTheme.colors.accent
        case .nextExercise:
            return appTheme.colors.accent
        }
    }

    private var iconName: String {
        if !icon.isEmpty {
            return icon
        }

        switch style {
        case .nextExercise:
            return "arrow.right.circle.fill"
        case .completedWorkout:
            return "checkmark.seal.fill"
        case .pr:
            return "star.fill"
        case .recovery:
            return "bolt.heart.fill"
        }
    }

    private func updateContentVisibility(_ visible: Bool) {
        if reduceMotion {
            iconPulse = visible
            contentRevealed = visible
            buttonRevealed = visible
            return
        }

        if visible {
            withAnimation(.easeOut(duration: 0.72)) {
                iconPulse = true
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard isVisible else { return }

                withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                    contentRevealed = true
                }

                try? await Task.sleep(nanoseconds: 80_000_000)
                guard isVisible else { return }

                withAnimation(AppMotion.popupEntrance(reduceMotion: reduceMotion)) {
                    buttonRevealed = true
                }
            }
        } else {
            withAnimation(AppMotion.popupExit(reduceMotion: reduceMotion)) {
                iconPulse = false
                contentRevealed = false
                buttonRevealed = false
            }
        }
    }
}
