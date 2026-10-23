import Foundation
import os
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct PhotoImportOperation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { photo.id }
    let version: Int
    let photo: PhotoObservation
    let attachment: PhotoAttachment
    func validate() throws {
        guard version == 2, photo.attachmentID == attachment.id else { throw StorageError.invalidRecord }
        try photo.metadata.validate(); try attachment.validate()
    }
}

/// Mutations are confined to MappingStorageOwner in the application. Every accepted image has an intent BEFORE any byte write.
/// Originals and operation manifests are never cleaned up implicitly. Thumbnails are disposable.
// Immutable root; all filesystem mutations are serialized by MappingStorageOwner.
// The test checkpoint is synchronized independently; invoke it outside the lock.
final class ManagedPhotoStore: Sendable {
    static let maximumBytes = 100_000_000
    enum Checkpoint { case intent, staging, promotion, thumbnail }
    let root: URL
    private let checkpointState = OSAllocatedUnfairLock<(@Sendable (Checkpoint) throws -> Void)?>(initialState: nil)
    var checkpoint: (@Sendable (Checkpoint) throws -> Void)? {
        get { checkpointState.withLock { $0 } }
        set { checkpointState.withLock { $0 = newValue } }
    }
    init(root: URL) { self.root = root }
    func originalURL(_ attachment: PhotoAttachment) -> URL { root.appendingPathComponent(attachment.relativePath) }
    func thumbnailURL(_ attachment: PhotoAttachment) -> URL { root.appendingPathComponent(attachment.thumbnailPath) }
    func stagingURL(_ operation: PhotoImportOperation) -> URL { root.appendingPathComponent("staging/\(operation.id.uuidString)") }
    func operationURL(_ operation: PhotoImportOperation) -> URL { root.appendingPathComponent("operations/\(operation.id.uuidString).json") }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func prepareDirectories() throws {
        for directory in ["operations", "staging", "originals", "thumbnails"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
    }
    func makeOperation(data: Data, filename: String?, context: PhotoContext, source: PhotoSource,
               representation: String, captureWallTime: String? = nil, captureUTCOffset: String? = nil, captureSubseconds: String? = nil, now: Date = Date()) throws -> PhotoImportOperation {
        guard !data.isEmpty, data.count <= Self.maximumBytes,
              let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(image), let uti = UTType(type as String), uti.conforms(to: .image),
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { throw MappingError.invalid("Файл не является поддерживаемым изображением или превышает 100 МБ.") }
        // Decode a bounded preview before accepting truncated/corrupt image data.
        guard CGImageSourceCreateThumbnailAtIndex(image, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil,
            CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete else { throw StorageError.invalidRecord }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let imageWallTime = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        let wallTime = imageWallTime ?? captureWallTime
        let offset = imageWallTime == nil ? captureUTCOffset : exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
        let subseconds = imageWallTime == nil ? captureSubseconds : exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String
        let timeSource = imageWallTime == nil ? "camera EXIF metadata" : "image EXIF"
        let captureText = wallTime.map { $0 + (subseconds.map { "." + $0 } ?? "") + (offset.map { " " + $0 } ?? " (offset unknown)") }
        var capture: Date?
        if let wallTime, let offset {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss ZZZZZ"; formatter.isLenient = false
            capture = formatter.date(from: wallTime + " " + offset)
            if let subseconds, subseconds.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
               let fraction = Double("0." + subseconds), let whole = capture {
                capture = whole.addingTimeInterval(fraction)
            }
        }
        let attachment = PhotoAttachment(id: UUID(), originalFilename: filename.map { URL(fileURLWithPath: $0).lastPathComponent },
            sha256: Self.digest(data), byteCount: data.count, format: uti.identifier,
            mimeType: uti.preferredMIMEType ?? "application/octet-stream", pixelWidth: width, pixelHeight: height,
            orientation: props[kCGImagePropertyOrientation] as? Int ?? 1, representation: representation)
        let operation = PhotoImportOperation(version: 2, photo: PhotoObservation(id: UUID(), attachmentID: attachment.id,
            context: context, source: source, importedAt: now, capturedAt: capture, captureTimeText: captureText,
            captureTimeProvenance: capture != nil ? "\(timeSource) DateTimeOriginal + OffsetTimeOriginal; unverified" :
                wallTime != nil ? "\(timeSource) wall time; UTC offset unknown; instant unknown" : "unknown",
            metadata: PhotoMetadata(name: filename ?? "Фотография")), attachment: attachment)
        try operation.validate()
        return operation
    }
    func begin(data: Data, filename: String?, context: PhotoContext, source: PhotoSource,
               representation: String, captureWallTime: String? = nil, captureUTCOffset: String? = nil,
               captureSubseconds: String? = nil, now: Date = Date()) throws -> PhotoImportOperation {
        let operation = try makeOperation(data: data, filename: filename, context: context, source: source,
            representation: representation, captureWallTime: captureWallTime, captureUTCOffset: captureUTCOffset,
            captureSubseconds: captureSubseconds, now: now)
        try stage(data, for: operation)
        return operation
    }
    /// Identity is allocated before I/O so a live caller can retain bytes even if intent creation fails.
    func stage(_ data: Data, for operation: PhotoImportOperation) throws {
        try operation.validate(); try verify(data, attachment: operation.attachment); try prepareDirectories()
        if hasIntent(operation) {
            guard try loadOperation(operationURL(operation)) == operation else { throw StorageError.invalidRecord }
        } else {
            try JSONEncoder().encode(operation).write(to: operationURL(operation), options: .atomic)
            try checkpoint?(.intent)
        }
        if FileManager.default.fileExists(atPath: originalURL(operation.attachment).path) {
            _ = try read(operation.attachment)
        } else { try supply(data, for: operation) }
    }
    func hasIntent(_ operation: PhotoImportOperation) -> Bool {
        FileManager.default.fileExists(atPath: operationURL(operation).path)
    }
    /// Recover a failed staging write with the exact same bytes and identities.
    func supply(_ data: Data, for operation: PhotoImportOperation) throws {
        try operation.validate()
        guard try loadOperation(operationURL(operation)) == operation else { throw StorageError.invalidRecord }
        try verify(data, attachment: operation.attachment)
        try data.write(to: stagingURL(operation), options: .atomic)
        try checkpoint?(.staging)
    }
    func promote(_ operation: PhotoImportOperation) throws {
        try operation.validate()
        guard try loadOperation(operationURL(operation)) == operation else { throw StorageError.invalidRecord }
        let original = originalURL(operation.attachment)
        if FileManager.default.fileExists(atPath: original.path) { _ = try read(operation.attachment); return }
        let data = try Data(contentsOf: stagingURL(operation)); try verify(data, attachment: operation.attachment)
        try FileManager.default.moveItem(at: stagingURL(operation), to: original)
        try checkpoint?(.promotion)
        _ = try read(operation.attachment)
    }
    private func verify(_ data: Data, attachment: PhotoAttachment) throws {
        guard data.count == attachment.byteCount, Self.digest(data) == attachment.sha256 else {
            throw MappingError.invalid("Оригинал повреждён: размер или SHA-256 не совпадает. Запись сохранена.")
        }
    }
    func read(_ attachment: PhotoAttachment) throws -> Data {
        let url = originalURL(attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MappingError.invalid("Оригинал отсутствует. Запись и ожидаемый SHA-256 сохранены.") }
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == attachment.byteCount else {
            throw MappingError.invalid("Оригинал повреждён: размер не совпадает. Запись сохранена.")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe); try verify(data, attachment: attachment); return data
    }
    func thumbnail(_ attachment: PhotoAttachment) throws -> Data {
        // Always verify the original, even when a cached thumbnail exists.
        let data = try read(attachment)
        let destination = thumbnailURL(attachment)
        if let cached = try? Data(contentsOf: destination),
           let source = CGImageSourceCreateWithData(cached as CFData, nil),
           CGImageSourceCreateImageAtIndex(source, 0, nil) != nil { return cached }
        try checkpoint?(.thumbnail)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 400] as CFDictionary) else {
            throw MappingError.invalid("Не удалось создать миниатюру. Оригинал сохранён.")
        }
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw StorageError.invalidRecord }
        // New derivative carries no original EXIF/GPS dictionary.
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw StorageError.invalidRecord }
        try prepareDirectories(); try (output as Data).write(to: destination, options: .atomic)
        return output as Data
    }
    func pending() throws -> [PhotoImportOperation] {
        let directory = root.appendingPathComponent("operations")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map(loadOperation)
    }
    private func loadOperation(_ url: URL) throws -> PhotoImportOperation {
        let operation = try JSONDecoder().decode(PhotoImportOperation.self, from: Data(contentsOf: url))
        try operation.validate()
        guard url.lastPathComponent == "\(operation.id.uuidString).json" else { throw StorageError.invalidRecord }
        return operation
    }
    func complete(_ operation: PhotoImportOperation) throws {
        // Caller must have committed the exact pair. Keep intent until thumbnail succeeds as well.
        _ = try thumbnail(operation.attachment)
        try FileManager.default.removeItem(at: operationURL(operation))
        if FileManager.default.fileExists(atPath: stagingURL(operation).path) { try FileManager.default.removeItem(at: stagingURL(operation)) }
    }
}
