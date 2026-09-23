import Foundation
import SwiftData

/// One local dataset, independent of authentication. Kept separate so the V1
/// entities (and their persisted identities) remain unchanged during migration.
@Model
final class LocalWorkspaceMetadata {
    @Attribute(.unique) var id: UUID
    var initialized: Bool = false
    var bootstrapVersion: Int = 0
    var catalogueVersion: Int = 0
    var revision: Int = 0
    var operationGeneration: Int = 0
    var backupProjectID: String?
    var backupUID: String?
    var lastBoundProjectID: String?
    var lastBoundUID: String?
    var lastBackupFingerprint: String?
    var lastAttemptedBackupAt: Date?
    var lastSuccessfulBackupAt: Date?
    var backupState: String?
    var backupError: String?
    var lastRemoteGenerationID: String?
    var provenanceData: Data?
    var pendingRestoreID: UUID?

    init(id: UUID = UUID()) { self.id = id }
}

struct CatalogueProvenance: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let recordID: UUID
        let initialFingerprint: String
    }
    var exercises: [String: Entry] = [:]
    var appliedTemplateIDs: [String] = []
}

/// Portable dataset facts only: an archive never confers account ownership.
struct WorkspacePortableState: Codable, Equatable, Sendable {
    var initialized: Bool
    var bootstrapVersion: Int
    var catalogueVersion: Int
    var provenance: CatalogueProvenance
}

struct WorkspaceOperationContext: Equatable, Sendable {
    let workspaceID: UUID
    let projectID: String
    let uid: String
    let generation: Int
}

struct WorkspaceContentSummary: Equatable, Sendable {
    var categories: [String: Int]
    var itemCount: Int { categories.values.reduce(0, +) }
    var hasMeaningfulContent: Bool { itemCount > 0 }
    var description: String {
        categories.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }
}

enum WorkspaceError: LocalizedError {
    case duplicateWorkspace, backupNotConnected, differentAccount, staleOperation
    var errorDescription: String? {
        switch self {
        case .duplicateWorkspace: "This store contains conflicting workspace identities. Your data has been left in place."
        case .backupNotConnected: "Connect this workspace to backup in Settings before uploading."
        case .differentAccount: "This data belongs to a different backup account. Restore the new account with explicit replacement, or export your data and start a new workspace."
        case .staleOperation: "The workspace or account changed. The previous operation was cancelled."
        }
    }
}
