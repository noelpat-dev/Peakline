import SwiftUI

struct WorkoutModePicker: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: WorkoutMode

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(WorkoutMode.allCases) { mode in
                Button {
                    AppHaptics.selection()
                    withAnimation(AppMotion.chip(reduceMotion: reduceMotion)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .font(AppTypography.sectionTitle)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(AppTypography.bodyEmphasis)
                            Text(mode.subtitle)
                                .font(AppTypography.metadata)
                                .foregroundStyle(selection == mode ? appTheme.colors.textPrimary.opacity(0.75) : appTheme.mutedText)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(appTheme.metrics.spacing12)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .foregroundStyle(selection == mode ? appTheme.colors.textPrimary : appTheme.mutedText)
                    .background(selection == mode ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous)
                            .stroke(selection == mode ? appTheme.colors.accent.opacity(0.38) : appTheme.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous))
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
    }
}
