import SwiftUI

struct GlassIconBadge: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let systemName: String
    var size: CGFloat = 72
    var tint: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(AppTypography.rounded(size: size * 0.38, weight: .bold))
            .foregroundStyle(tint ?? appTheme.colors.accent)
            .frame(width: size, height: size)
            .background(badgeBackground, in: Circle())
            .overlay {
                Circle()
                    .fill((tint ?? appTheme.colors.accent).opacity(colorScheme == .dark ? 0.10 : 0.07))
            }
            .overlay {
                Circle()
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 10, y: 6)
            .accessibilityHidden(true)
    }

    private var badgeBackground: AnyShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(appTheme.colors.cardBackgroundElevated)
        } else {
            AnyShapeStyle(.thinMaterial)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.10)
    }
}
