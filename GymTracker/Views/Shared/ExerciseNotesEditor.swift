import SwiftUI

struct ExerciseNotesEditor: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var text: String

    let title: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(appTheme.colors.textPrimary)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(8)
                    .foregroundStyle(appTheme.colors.textPrimary)
            }
            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous)
                    .stroke(appTheme.colors.cardBorder, lineWidth: 1)
            }

            QuickNoteChipsView(text: $text)
        }
    }
}
