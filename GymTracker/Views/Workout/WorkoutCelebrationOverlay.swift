import SwiftUI

enum CelebrationStyle {
    case nextExercise
    case completedWorkout
    case pr
    case recovery
}

struct WorkoutCelebrationOverlay: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let message: String
    let icon: String
    let primaryActionTitle: String
    let primaryActionIcon: String?
    var style: CelebrationStyle = .nextExercise
    let primaryAction: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            backdrop

            GlassCard(cornerRadius: 34, padding: 24) {
                VStack(spacing: 18) {
                    GlassIconBadge(systemName: iconName, size: 70)

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
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .accessibilityLabel(primaryActionTitle)
                }
            }
            .frame(maxWidth: 430)
            .padding(.horizontal, 20)
            .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1 : 0.96))
            .opacity(hasAppeared ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(message)")
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.18 : 0.28)

            Color.black
                .opacity(colorScheme == .dark ? 0.45 : 0.22)
        }
        .accessibilityHidden(true)
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

private struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(appTheme.colors.accent.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
    }
}
