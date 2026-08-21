import SwiftUI

struct QuickNoteChipsView: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var text: String

    var notes: [String] = NoteTemplateProvider.quickNotes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(notes, id: \.self) { note in
                    Button {
                        var updatedText = text
                        NoteTemplateProvider.append(note, to: &updatedText)
                        text = updatedText
                    } label: {
                        Text(note)
                            .font(AppTypography.chip)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
