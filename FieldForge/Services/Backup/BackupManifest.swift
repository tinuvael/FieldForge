import Foundation

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// DispatchQueue work is deliberately non-suspending. The lock transfers task
/// cancellation into that executor; all mutable state is protected by this lock.
final class BackupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value || Task.isCancelled { throw CancellationError() }
    }
}

struct BackupReport: Codable, Equatable, Sendable {
    struct Problem: Codable, Equatable, Sendable {
        let path: String
        let reason: String
    }
    let problems: [Problem]
    var complete: Bool { problems.isEmpty }
}

struct BackupManifest: Codable, Equatable, Sendable {
    static let version = 1
    struct File: Codable, Equatable, Sendable {
        let path: String
        let byteCount: Int
        let sha256: String
    }
    /// Relationships are derived from the authoritative graph and rechecked by the reader.
    struct Attachment: Codable, Equatable, Sendable {
        let kind: String
        let recordID: UUID
        let attachmentID: UUID
        let projectID: UUID
        let pointID: UUID?
        let pointRevisionID: UUID?
        let path: String
        let byteCount: Int?
        let sha256: String?
    }
    let formatVersion: Int
    let mappingSchemaVersion: Int
    let applicationVersion: String?
    let createdAtUTC: String
    let projectCount: Int
    let observationCount: Int
    let measurementIDs: [UUID]
    let independentJournalPresent: Bool
    let files: [File]
    let attachments: [Attachment]
    let pendingOperationPaths: [String]
    let completenessStatus: String
    let report: BackupReport

    static func attachments(in journal: MappingJournal) throws -> [Attachment] {
        let byAttachment = Dictionary(uniqueKeysWithValues: journal.photoAttachments.map { ($0.id, $0) })
        let byHorizon = Dictionary(uniqueKeysWithValues: journal.horizons.map { ($0.id, $0) })
        let photos = try journal.photos.map { photo -> Attachment in
            guard let a = byAttachment[photo.attachmentID] else { throw StorageError.invalidRecord }
            return Attachment(kind: "photo", recordID: photo.id, attachmentID: a.id, projectID: photo.context.projectID,
                pointID: photo.context.pointID, pointRevisionID: photo.context.pointRevisionID,
                path: "photos/" + a.relativePath, byteCount: a.byteCount, sha256: a.sha256)
        }
        let plans = try journal.plans.map { plan -> Attachment in
            guard let horizon = byHorizon[plan.horizonID] else { throw StorageError.invalidRecord }
            return Attachment(kind: "dxf", recordID: plan.id, attachmentID: plan.attachmentID, projectID: horizon.projectID,
                pointID: nil, pointRevisionID: nil, path: "plans/originals/\(plan.attachmentID.uuidString).dxf",
                byteCount: plan.file?.byteCount, sha256: plan.file?.sha256)
        }
        return photos + plans
    }
}

/// All paths are application-managed sources. It is never a second data store.
struct BackupSources: Sendable {
    let mapping: URL
    let measurements: URL
    let photos: URL
    let plans: URL
}
struct BackupStaging: Sendable {
    let directory: URL
    let manifest: BackupManifest
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
struct VerifiedBackup: Sendable {
    let files: MappingExportFiles
    let manifest: BackupManifest
    let report: BackupReport
    let byteCount: Int
}
