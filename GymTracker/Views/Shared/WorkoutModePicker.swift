import SwiftUI

struct WorkoutModePicker: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var selection: WorkoutMode

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(WorkoutMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .font(.headline)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(mode.subtitle)
                                .font(.caption)
                                .foregroundStyle(selection == mode ? .primary.opacity(0.75) : appTheme.mutedText)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .foregroundStyle(selection == mode ? .primary : appTheme.mutedText)
                    .background(selection == mode ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selection == mode ? appTheme.colors.accent.opacity(0.38) : appTheme.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
