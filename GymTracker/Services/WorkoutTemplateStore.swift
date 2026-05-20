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

struct WorkoutTemplateStore {
    private let filename = "WorkoutTemplates.json"

    func loadTemplates() -> [CustomWorkoutTemplate] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let templates = try? decoder.decode([CustomWorkoutTemplate].self, from: data)
        else { return [] }

        return templates.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ template: CustomWorkoutTemplate) throws {
        var templates = loadTemplates()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        try write(templates)
    }

    func delete(_ template: CustomWorkoutTemplate) throws {
        try write(loadTemplates().filter { $0.id != template.id })
    }

    private func write(_ templates: [CustomWorkoutTemplate]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(templates.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: [.atomic])
    }

    private var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Peakline", isDirectory: true)
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(filename)
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

