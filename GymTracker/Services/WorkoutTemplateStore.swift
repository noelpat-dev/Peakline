import Foundation

struct CustomWorkoutTemplate: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceSplitName: String?
    var sourceWorkoutModeRawValue: String?
    var sourceWorkoutStartedAt: Date?
    var notes: String?
    var exercises: [CustomWorkoutTemplateExercise]
}

struct CustomWorkoutTemplateExercise: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var exerciseId: UUID?
    var exerciseName: String
    var orderIndex: Int
    var plannedSets: Int?
    var targetRepMin: Int?
    var targetRepMax: Int?
    var lastUsedWeight: Double?
    var lastUsedReps: Int?
    var notes: String?
}

struct WorkoutTemplateStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func loadTemplates() -> [CustomWorkoutTemplate] {
        (try? loadTemplatesForBackup()) ?? []
    }

    /// Presence alone is enough for startup/restore safety checks. Decoding is
    /// deliberately deferred to backup creation so a damaged template file can
    /// never make a populated local install look empty or prevent app startup.
    var hasStoredTemplateData: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Unlike the UI-facing loader, backup creation must surface a corrupt or
    /// unreadable template file so an apparently successful backup cannot omit it.
    func loadTemplatesForBackup() throws -> [CustomWorkoutTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder
            .decode([CustomWorkoutTemplate].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ template: CustomWorkoutTemplate) throws {
        var templates = try loadTemplatesForBackup()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        try write(templates)
    }

    func delete(_ template: CustomWorkoutTemplate) throws {
        try write(loadTemplatesForBackup().filter { $0.id != template.id })
    }

    func replaceAll(with templates: [CustomWorkoutTemplate]) throws {
        try write(templates)
    }

    private func write(_ templates: [CustomWorkoutTemplate]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(templates.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: [.atomic])
    }

    private static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Peakline", isDirectory: true)
    }

    private static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("WorkoutTemplates.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
