import Foundation

/// The immutable metadata shipped with Workout Guide.
///
/// The manifest is kept as a bundled resource so the catalog can retain the
/// upstream ids, source paths, and attribution records without copying or
/// reinterpreting them in app code. The current manifest contains no
/// instruction prose, so the model does not invent any.
enum ExerciseGuideCatalog {
    static let exercises: [ExerciseGuideEntry] = loadManifest()

    private struct IndexedEntry {
        let entry: ExerciseGuideEntry
        let name: String
        let slug: String
    }

    private static let indexedEntries: [IndexedEntry] = exercises.map {
        IndexedEntry(entry: $0, name: normalize($0.name), slug: normalize($0.slug))
    }

    private static let entriesBySlug: [String: ExerciseGuideEntry] = Dictionary(
        uniqueKeysWithValues: indexedEntries.map { ($0.slug, $0.entry) }
    )

    private static let entriesByName: [String: [ExerciseGuideEntry]] = Dictionary(
        grouping: indexedEntries,
        by: \IndexedEntry.name
    ).mapValues { $0.map(\.entry) }

    static func entry(forSlug slug: String) -> ExerciseGuideEntry? {
        entriesBySlug[normalize(slug)]
    }

    /// Finds an exact display-name match, optionally constrained by equipment.
    ///
    /// Equipment is intentionally a strict filter. The upstream catalog has
    /// separate entries for variants such as cable, machine, and bodyweight;
    /// returning a visually similar variant would make exercise details less
    /// trustworthy.
    static func entry(forName name: String, equipment: String? = nil) -> ExerciseGuideEntry? {
        let normalizedName = normalize(name)
        let candidates = entriesByName[normalizedName] ?? []

        guard let equipment else {
            return candidates.first
        }

        let normalizedEquipment = normalize(equipment)
        return candidates.first { normalize($0.equipment) == normalizedEquipment }
    }

    static func entries(matching query: String) -> [ExerciseGuideEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return exercises
        }

        return indexedEntries.compactMap { item in
            item.name.contains(normalizedQuery) || item.slug.contains(normalizedQuery)
                ? item.entry
                : nil
        }
    }

    private static func loadManifest() -> [ExerciseGuideEntry] {
        let bundles = [Bundle.main, Bundle(for: ExerciseGuideCatalogBundleToken.self)]
        let url = bundles
            .compactMap { $0.url(forResource: "manifest", withExtension: "json", subdirectory: "WorkoutGuide") }
            .first

        guard let url else {
            assertionFailure("Workout Guide manifest is not bundled")
            return []
        }

        do {
            return try JSONDecoder().decode([ExerciseGuideEntry].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Workout Guide manifest failed to decode: \(error)")
            return []
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ExerciseGuideCatalogBundleToken: NSObject {}

struct ExerciseGuideEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    let name: String
    let exerciseType: String
    let equipment: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let isStretch: Bool
    let frames: [ExerciseGuideFrame]
    let attribution: ExerciseGuideAttribution

    /// The three asset names produced by the Peakline Workout Guide import.
    var frameAssetNames: [String] {
        frames.map { assetName(frame: $0.index) }
    }

    /// Resolves one of the imported animation frames by its upstream index.
    /// Invalid indexes fall back to frame 1 so a bad persisted selection does
    /// not crash a detail or library surface.
    func assetName(frame: Int) -> String {
        let frameIndex = frames.contains { $0.index == frame } ? frame : 1
        return "workout_guide_\(slug.replacingOccurrences(of: "-", with: "_"))_frame_\(frameIndex)"
    }

    var muscleGroups: [String] {
        [primaryMuscle] + secondaryMuscles
    }
}

struct ExerciseGuideFrame: Codable, Hashable, Sendable {
    let index: Int
    let path: String
    let width: Int
    let height: Int
    let format: String
    let attribution: ExerciseGuideAttribution
}

struct ExerciseGuideAttribution: Codable, Hashable, Sendable {
    let creator: String
    let creatorUrl: String
    let license: String
    let licenseUrl: String
    let source: ExerciseGuideSourceAttribution?
}

struct ExerciseGuideSourceAttribution: Codable, Hashable, Sendable {
    let name: String
    let url: String
    let license: String
    let licenseUrl: String
    let changes: String?
}
