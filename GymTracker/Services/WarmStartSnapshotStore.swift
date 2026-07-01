import Foundation

struct WarmStartSnapshotEnvelope<Payload: Codable>: Codable {
    let schemaVersion: Int
    let screenKey: String
    let sourceSignature: String
    let createdAt: Date
    let payload: Payload
}

actor WarmStartSnapshotStore {
    static let shared = WarmStartSnapshotStore()

    private let directoryURL: URL
    private let schemaVersion = 1

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = baseURL
                .appendingPathComponent("Peakline", isDirectory: true)
                .appendingPathComponent("WarmStartSnapshots", isDirectory: true)
        }
    }

    func load<Payload: Codable>(
        _ payloadType: Payload.Type,
        screenKey: String,
        matching sourceSignature: String? = nil,
        maxAge: TimeInterval? = nil
    ) async -> WarmStartSnapshotEnvelope<Payload>? {
        let fileURL = fileURL(for: screenKey)

        return PerformanceTracer.trace(.warmStartLoad) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=missing")
                return nil
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let envelope = try decoder.decode(WarmStartSnapshotEnvelope<Payload>.self, from: data)

                guard envelope.schemaVersion == schemaVersion else {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=schema")
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }

                guard envelope.screenKey == screenKey else {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=screen_key")
                    return nil
                }

                if let sourceSignature, envelope.sourceSignature != sourceSignature {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=signature")
                    return nil
                }

                if let maxAge, Date().timeIntervalSince(envelope.createdAt) > maxAge {
                    PerformanceTracer.mark(.warmStartCacheMiss, "screen=\(screenKey) reason=expired")
                    return nil
                }

                PerformanceTracer.mark(.warmStartCacheHit, "screen=\(screenKey) bytes=\(data.count)")
                return envelope
            } catch {
                PerformanceTracer.mark(.warmStartDecodeFailed, "screen=\(screenKey) error=\(String(describing: error))")
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
        }
    }

    func save<Payload: Codable>(
        _ payload: Payload,
        screenKey: String,
        sourceSignature: String
    ) async {
        PerformanceTracer.trace(.warmStartPersist) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let envelope = WarmStartSnapshotEnvelope(
                    schemaVersion: schemaVersion,
                    screenKey: screenKey,
                    sourceSignature: sourceSignature,
                    createdAt: Date(),
                    payload: payload
                )
                let data = try encoder.encode(envelope)
                try data.write(to: fileURL(for: screenKey), options: [.atomic])
                PerformanceTracer.mark(.warmStartPersist, "screen=\(screenKey) bytes=\(data.count)")
            } catch {
                PerformanceTracer.mark(.warmStartPersist, "screen=\(screenKey) error=\(String(describing: error))")
            }
        }
    }

    func clear(screenKey: String) async {
        try? FileManager.default.removeItem(at: fileURL(for: screenKey))
    }

    func snapshotFileURL(forTesting screenKey: String) -> URL {
        fileURL(for: screenKey)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fileURL(for screenKey: String) -> URL {
        let safeName = screenKey.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        return directoryURL.appendingPathComponent(String(safeName)).appendingPathExtension("json")
    }
}
