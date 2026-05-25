import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = AppThemeMetrics().radius32
    var padding: CGFloat = AppThemeMetrics().spacing24
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(appTheme.colors.accent.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: colorScheme == .dark ? 16 : 24, y: 12)
    }

    private var cardBackground: AnyShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(appTheme.colors.cardBackground)
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.16)
    }
}
