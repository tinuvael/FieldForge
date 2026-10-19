import Foundation

enum PhotoSource: String, Codable { case camera, photos, files }
enum PhotoCategory: String, Codable, CaseIterable {
    case roof, leftWall, rightWall, face, joint, fault, generalCondition, other
    var label: String {
        switch self {
        case .roof: return "Кровля"
        case .leftWall: return "Левый борт"
        case .rightWall: return "Правый борт"
        case .face: return "Забой"
        case .joint: return "Трещина"
        case .fault: return "Нарушение"
        case .generalCondition: return "Общее состояние"
        case .other: return "Другое"
        }
    }
}

enum PhotoLocationBasis: String, Codable {
    case pointRevision
    case unknownBeforeFirstSave
}

/// Version 1 identifies the original point UUID; later versions identify the exact P3.3 revision.
/// No copy of the point, coordinates or geological evidence is created.
struct PhotoContext: Codable, Equatable {
    let projectID: UUID
    let horizonID: UUID
    let excavationID: UUID
    let pointID: UUID
    let pointRevisionID: UUID
    let pointVersion: Int
    var locationBasis: PhotoLocationBasis = .pointRevision
}

struct PhotoMetadata: Codable, Equatable {
    var name: String
    var number = ""
    var description = ""
    var category: PhotoCategory?
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StorageError.invalidRecord }
    }
}

struct PhotoObservation: Codable, Equatable, Identifiable {
    let id: UUID
    let attachmentID: UUID
    let context: PhotoContext
    let source: PhotoSource
    let importedAt: Date
    let capturedAt: Date?
    /// Exact EXIF wall time/offset retained even when no UTC instant can be established.
    let captureTimeText: String?
    let captureTimeProvenance: String
    let metadata: PhotoMetadata
}

struct PhotoMetadataRevision: Codable, Equatable, Identifiable {
    let id: UUID
    let photoID: UUID
    let previousRevisionID: UUID?
    let version: Int
    let correctedAt: Date
    let reason: String
    let metadata: PhotoMetadata
}

struct PhotoAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    let originalFilename: String?
    let sha256: String
    let byteCount: Int
    let format: String // ImageIO UTI, detected from bytes
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int
    /// Received bytes are preserved. Provider identity to library original is not assumed.
    let representation: String
    var relativePath: String { "originals/\(id.uuidString)" }
    var thumbnailPath: String { "thumbnails/\(id.uuidString).jpg" }
    func validate() throws {
        guard sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              (1...ManagedPhotoStore.maximumBytes).contains(byteCount), pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 100_000, pixelHeight <= 100_000, (1...8).contains(orientation),
              !format.isEmpty, !mimeType.isEmpty, !representation.isEmpty else { throw StorageError.invalidRecord }
    }
}

extension MappingJournal {
    func photoContext(for id: UUID) throws -> PhotoContext {
        guard let point = effectiveObservation(id: id) else { throw StorageError.invalidRecord }
        let revision = history(for: id).last
        return PhotoContext(projectID: point.projectID, horizonID: point.horizonID, excavationID: point.excavationID,
                            pointID: id, pointRevisionID: revision?.id ?? id, pointVersion: revision?.version ?? 1)
    }
    func photoPoint(_ context: PhotoContext) -> MappingObservation? {
        if context.pointVersion == 1, context.pointRevisionID == context.pointID {
            return observations.first { $0.id == context.pointID }
        }
        return revisions.first { $0.id == context.pointRevisionID && $0.observationID == context.pointID && $0.version == context.pointVersion }?.snapshot
    }
    func metadata(for photo: PhotoObservation) -> PhotoMetadata {
        photoRevisions.last { $0.photoID == photo.id }?.metadata ?? photo.metadata
    }
    func validatePhotos() throws {
        guard Set(photos.map(\.id)).count == photos.count,
              Set(photos.map(\.attachmentID)).count == photos.count,
              Set(photoAttachments.map(\.id)).count == photoAttachments.count,
              Set(photoAttachments.map(\.id)) == Set(photos.map(\.attachmentID)),
              Set(photoAttachments.map(\.id)).isDisjoint(with: Set(plans.map(\.attachmentID))),
              Set(photoRevisions.map(\.id)).count == photoRevisions.count else { throw StorageError.invalidRecord }
        for attachment in photoAttachments { try attachment.validate() }
        for photo in photos {
            try photo.metadata.validate()
            guard let point = photoPoint(photo.context), point.projectID == photo.context.projectID,
                  point.horizonID == photo.context.horizonID, point.excavationID == photo.context.excavationID,
                  photo.importedAt.timeIntervalSinceReferenceDate.isFinite,
                  photo.capturedAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
                  !photo.captureTimeProvenance.isEmpty else { throw StorageError.invalidRecord }
            if photo.context.locationBasis == .unknownBeforeFirstSave {
                guard photo.context.pointVersion == 1, photo.context.pointRevisionID == photo.context.pointID else { throw StorageError.invalidRecord }
            }
        }
        var latest: [UUID: PhotoMetadataRevision] = [:]
        for revision in photoRevisions {
            try revision.metadata.validate()
            guard photos.contains(where: { $0.id == revision.photoID }),
                  revision.version == (latest[revision.photoID]?.version ?? 1) + 1,
                  revision.previousRevisionID == latest[revision.photoID]?.id,
                  revision.correctedAt.timeIntervalSinceReferenceDate.isFinite,
                  !revision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StorageError.invalidRecord }
            latest[revision.photoID] = revision
        }
    }
}

extension MappingWorkflow {
    mutating func registerPhoto(_ operation: PhotoImportOperation) throws {
        // A retry after successful journal commit is a no-op, even if metadata was later corrected.
        if let existing = journal.photos.first(where: { $0.id == operation.photo.id }) {
            guard existing == operation.photo, journal.photoAttachments.contains(operation.attachment) else { throw StorageError.invalidRecord }
            return
        }
        var next = journal
        next.photos.append(operation.photo); next.photoAttachments.append(operation.attachment)
        try commit(next)
    }
    mutating func correctPhoto(_ photoID: UUID, baselineRevisionID: UUID?, metadata: PhotoMetadata,
                               reason: String, now: Date = Date()) throws {
        let previous = journal.photoRevisions.last { $0.photoID == photoID }
        guard previous?.id == baselineRevisionID else { throw MappingError.invalid("Метаданные уже изменены. Откройте фотографию заново.") }
        var next = journal
        next.photoRevisions.append(PhotoMetadataRevision(id: UUID(), photoID: photoID, previousRevisionID: previous?.id,
            version: (previous?.version ?? 1) + 1, correctedAt: now, reason: reason, metadata: metadata))
        try commit(next)
    }
}
