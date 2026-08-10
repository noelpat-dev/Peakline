import SwiftUI

enum CelebrationStyle: Equatable {
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

    @State private var prBurstActive = false
    @State private var hasPlayedPRBurst = false

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 18) {
                celebrationIcon

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(AppTypography.heroTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)

                        Text(message)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        primaryAction()
                    } label: {
                        Label {
                            Text(primaryActionTitle)
                        } icon: {
                            if let primaryActionIcon {
                                Image(systemName: primaryActionIcon)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .disabled(isPrimaryActionDisabled)
                    .accessibilityLabel(primaryActionTitle)
                    .accessibilityIdentifier("workout-celebration-primary")
                }
            }
            .padding(appTheme.metrics.spacing24)
            .frame(maxWidth: .infinity)
            .background(
                appTheme.colors.cardBackground,
                in: RoundedRectangle(cornerRadius: appTheme.metrics.radius32, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius32, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: style == .pr ? 1.5 : 1)
                    .allowsHitTesting(false)
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
        .task(id: isVisible) {
            if !isVisible {
                AppMotion.withoutAnimation {
                    prBurstActive = false
                    hasPlayedPRBurst = false
                }
                return
            }

            guard style == .pr, !reduceMotion, !hasPlayedPRBurst else { return }
            hasPlayedPRBurst = true
            AppMotion.withoutAnimation {
                prBurstActive = false
            }
            await Task.yield()
            guard !Task.isCancelled, isVisible else { return }
            prBurstActive = true
        }
    }

    @ViewBuilder
    private var celebrationIcon: some View {
        if style == .pr {
            ZStack {
                if !reduceMotion {
                    PRCelebrationStarburst(
                        isActive: prBurstActive,
                        primaryColor: appTheme.warningColor,
                        secondaryColor: appTheme.colors.accent,
                        reduceMotion: reduceMotion
                    )
                }

                baseCelebrationIcon
                    .scaleEffect(reduceMotion ? 1 : (prBurstActive ? 1 : 0.72))
                    .animation(
                        AppMotion.prCelebrationIconPop(reduceMotion: reduceMotion),
                        value: prBurstActive
                    )
            }
            .frame(height: 136)
            .accessibilityHidden(true)
        } else {
            baseCelebrationIcon
                .accessibilityHidden(true)
        }
    }

    private var baseCelebrationIcon: some View {
        ZStack {
            Circle()
                .stroke(iconTint.opacity(0.28), lineWidth: 1.5)
                .frame(width: 92, height: 92)
                .opacity(0.24)

            Circle()
                .fill(iconTint.opacity(0.10))
                .frame(width: 88, height: 88)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.82))

            GlassIconBadge(systemName: iconName, size: 70, tint: iconTint)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.78))
        }
    }

    private var backdrop: some View {
        Color.black
            .opacity(isVisible ? 0.18 : 0)
            .accessibilityHidden(true)
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

    private var cardBorderColor: Color {
        style == .pr ? iconTint.opacity(0.58) : appTheme.colors.cardBorder
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

}

private struct PRCelebrationStarburst: View {
    let isActive: Bool
    let primaryColor: Color
    let secondaryColor: Color
    let reduceMotion: Bool

    private let sparkCount = 12

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(primaryColor.opacity(index == 0 ? 0.72 : 0.42), lineWidth: index == 0 ? 2 : 1.5)
                    .frame(width: 92, height: 92)
                    .scaleEffect(isActive ? (index == 0 ? 1.50 : 1.72) : 0.66)
                    .opacity(isActive ? 0 : (index == 0 ? 0.78 : 0.54))
                    .animation(
                        AppMotion.prCelebrationRing(index: index, reduceMotion: reduceMotion),
                        value: isActive
                    )
            }

            ForEach(0..<sparkCount, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? primaryColor : secondaryColor)
                    .frame(
                        width: index.isMultiple(of: 3) ? 4 : 3,
                        height: index.isMultiple(of: 3) ? 17 : 12
                    )
                    .offset(y: isActive ? -72 : -40)
                    .rotationEffect(.degrees((Double(index) * 30) - 90))
                    .scaleEffect(isActive ? 1 : 0.38)
                    .opacity(isActive ? 0 : 0.92)
                    .animation(
                        AppMotion.prCelebrationSpark(index: index, reduceMotion: reduceMotion),
                        value: isActive
                    )
            }
        }
        .frame(width: 164, height: 136)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
