import SwiftUI

enum AppMotion {
    static let popupMountDelay: UInt64 = 16_000_000
    static let popupExitDuration: UInt64 = 280_000_000
    static let ratingSelectionDelay: UInt64 = 150_000_000

    static func popupEntrance(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .snappy(duration: 0.42, extraBounce: 0.08)
    }

    static func popupExit(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .smooth(duration: 0.28)
    }

    static func quickSpring(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .spring(response: 0.24, dampingFraction: 0.78)
    }

    static func popupTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: 0.94, anchor: .center))
                    .combined(with: .offset(y: 28)),
                removal: .opacity
                    .combined(with: .scale(scale: 0.96, anchor: .center))
                    .combined(with: .offset(y: 18))
            )
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
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(appTheme.colors.accent.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.24), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .animation(AppMotion.quickSpring(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
