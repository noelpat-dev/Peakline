import SwiftUI
import UIKit

enum AppMotion {
    static let popupMountDelay: UInt64 = 16_000_000
    static let popupExitDuration: UInt64 = 240_000_000
    static let ratingSelectionDelay: UInt64 = 150_000_000
    static let popupContentRevealDelay: UInt64 = 70_000_000
    static let popupSecondaryRevealDelay: UInt64 = 80_000_000
    static let celebrationIconPulseDuration: TimeInterval = 0.58
    static let cardPressScale: CGFloat = 0.992
    static let selectedControlScale: CGFloat = 1.02
    static let emphasizedControlScale: CGFloat = 1.035
    static let cardAppearOffset: CGFloat = 14

    static func instantOr(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : animation
    }

    static func press(reduceMotion: Bool) -> Animation {
        instantOr(.easeOut(duration: 0.11), reduceMotion: reduceMotion)
    }

    static func navigation(reduceMotion: Bool) -> Animation {
        instantOr(.easeInOut(duration: 0.22), reduceMotion: reduceMotion)
    }

    static func tapConfirm(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.22, dampingFraction: 0.78, blendDuration: 0.04), reduceMotion: reduceMotion)
    }

    static func cardAppear(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.06), reduceMotion: reduceMotion)
    }

    static func listChange(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.32, dampingFraction: 0.88, blendDuration: 0.05), reduceMotion: reduceMotion)
    }

    static func selection(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.04), reduceMotion: reduceMotion)
    }

    static func progress(reduceMotion: Bool) -> Animation {
        instantOr(.easeOut(duration: 0.34), reduceMotion: reduceMotion)
    }

    static func swipeReveal(reduceMotion: Bool) -> Animation {
        instantOr(.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08), reduceMotion: reduceMotion)
    }

    static func sheet(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.04), reduceMotion: reduceMotion)
    }

    static func sheetPopup(reduceMotion: Bool) -> Animation {
        sheet(reduceMotion: reduceMotion)
    }

    static func toggle(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.25, dampingFraction: 0.82, blendDuration: 0.03), reduceMotion: reduceMotion)
    }

    static func workoutCompletion(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.44, dampingFraction: 0.76, blendDuration: 0.06), reduceMotion: reduceMotion)
    }

    static func popupEntrance(reduceMotion: Bool) -> Animation {
        sheet(reduceMotion: reduceMotion)
    }

    static func popupExit(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .easeInOut(duration: 0.24)
    }

    static func quickSpring(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.28, dampingFraction: 0.84), reduceMotion: reduceMotion)
    }

    static func swipeRevealSnap(reduceMotion: Bool) -> Animation {
        swipeReveal(reduceMotion: reduceMotion)
    }

    static func selectionSpring(reduceMotion: Bool) -> Animation {
        selection(reduceMotion: reduceMotion)
    }

    static func reorderSpring(reduceMotion: Bool) -> Animation {
        listChange(reduceMotion: reduceMotion)
    }

    static func progressFill(reduceMotion: Bool) -> Animation {
        progress(reduceMotion: reduceMotion)
    }

    static func transientConfirmation(reduceMotion: Bool) -> Animation {
        tapConfirm(reduceMotion: reduceMotion)
    }

    static func gentleFade(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .easeInOut(duration: 0.2)
    }

    static func popupTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: 0.96, anchor: .center))
                    .combined(with: .offset(y: 22)),
                removal: .opacity
                    .combined(with: .scale(scale: 0.98, anchor: .center))
                    .combined(with: .offset(y: 12))
            )
    }

    @MainActor
    static func smoothNavigate(reduceMotion: Bool, _ action: @escaping @MainActor () -> Void) {
        withAnimation(navigation(reduceMotion: reduceMotion)) {
            action()
        }
    }
}

enum AppHaptics {
    private static var lastSelectionAt = Date.distantPast
    private static var lastImpactAt = Date.distantPast
    private static var lastNotificationAt = Date.distantPast
    private static let selectionInterval: TimeInterval = 0.06
    private static let impactInterval: TimeInterval = 0.08
    private static let notificationInterval: TimeInterval = 0.18

    static func selection() {
        perform {
            guard shouldPlay(since: &lastSelectionAt, minimumInterval: selectionInterval) else { return }
            let selectionGenerator = UISelectionFeedbackGenerator()
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        }
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        perform {
            guard shouldPlay(since: &lastImpactAt, minimumInterval: impactInterval) else { return }
            let impactGenerator = UIImpactFeedbackGenerator(style: style)
            impactGenerator.prepare()
            impactGenerator.impactOccurred()
        }
    }

    static func lightImpact() {
        impact(.light)
    }

    static func mediumImpact() {
        impact(.medium)
    }

    static func success() {
        notify(.success)
    }

    static func warning() {
        notify(.warning)
    }

    static func error() {
        notify(.error)
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        perform {
            guard shouldPlay(since: &lastNotificationAt, minimumInterval: notificationInterval) else { return }
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
        }
    }

    private static func perform(_ feedback: @escaping () -> Void) {
        if Thread.isMainThread {
            feedback()
        } else {
            DispatchQueue.main.async {
                feedback()
            }
        }
    }

    private static func shouldPlay(since lastPlayedAt: inout Date, minimumInterval: TimeInterval) -> Bool {
        let now = Date.now
        guard now.timeIntervalSince(lastPlayedAt) >= minimumInterval else { return false }
        lastPlayedAt = now
        return true
    }
}

private struct SmoothPopupCardMotion: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool
    let hiddenScale: CGFloat
    let hiddenOffset: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : hiddenScale), anchor: anchor)
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : hiddenOffset))
    }
}

extension View {
    func smoothPopupCardMotion(
        isVisible: Bool,
        reduceMotion: Bool,
        hiddenScale: CGFloat = 0.94,
        hiddenOffset: CGFloat = 28,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(
            SmoothPopupCardMotion(
                isVisible: isVisible,
                reduceMotion: reduceMotion,
                hiddenScale: hiddenScale,
                hiddenOffset: hiddenOffset,
                anchor: anchor
            )
        )
    }
}

struct LiquidGlassPopupBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isVisible: Bool

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color.black
                    .opacity(colorScheme == .dark ? 0.58 : 0.24)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(colorScheme == .dark ? 0.18 : 0.26)

                Color.black
                    .opacity(colorScheme == .dark ? 0.34 : 0.16)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(true)
    }
}

struct LiquidGlassPopupCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = 34
    var padding: CGFloat = 24
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                if reduceTransparency {
                    shape.fill(appTheme.colors.cardBackground.opacity(colorScheme == .dark ? 0.96 : 0.94))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                shape
                    .fill(appTheme.colors.accent.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.10))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.18 : 0.28),
                                .white.opacity(0.045),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 86)
                    .blur(radius: 28)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -42, y: -28)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 26, x: 0, y: 18)
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.accentForeground)
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(appTheme.colors.accent.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.24), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? AppMotion.cardPressScale : 1))
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
