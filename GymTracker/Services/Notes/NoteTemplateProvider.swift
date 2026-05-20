import Foundation

enum NoteTemplateProvider {
    static let quickNotes = [
        "Felt strong",
        "Felt heavy",
        "Good form",
        "Poor form",
        "Shoulder discomfort",
        "Knee discomfort",
        "Equipment busy",
        "Increase next time",
        "Repeat next time",
        "Lower next time"
    ]

    static func append(_ note: String, to text: inout String) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }

        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            text = trimmedNote
        } else if !existing.localizedCaseInsensitiveContains(trimmedNote) {
            text = "\(existing)\n\(trimmedNote)"
        }
    }
}
