import Foundation
import ImageIO
import Darwin

struct RestorePreview: Sendable {
    let directory: URL
    let archive: URL
    let manifest: BackupManifest
    let byteCount: Int
    var package: URL { directory.appendingPathComponent("package") }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

/// V1 restoration uses the B1a reader/validator. All methods run off MainActor.
/// Only MappingStorageOwner may call activate. Recovery runs before either store opens.
enum OfflineRestore {
    enum Checkpoint: String, CaseIterable, Sendable {
        case protected, intent, oldMoved, newMoved, reopened, committed
    }
    struct Intent: Codable {
        let version: Int
        let id: UUID
        let originalInode: UInt64
        let manifestSHA256: String
        var committed: Bool
    }
    static let marker = "restored-format-v1"
    static let mappingName = "mapping-v1.json"
    static let measurementName = "measurements-v1.json"
    private static var fm: FileManager { FileManager.default }
    static func recoveryRoot(_ live: URL) -> URL { live.deletingLastPathComponent().appendingPathComponent(live.lastPathComponent + "-Restore") }
    private static func pointer(_ live: URL) -> URL { recoveryRoot(live).appendingPathComponent("active.json") }
    private static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    /// Provider access is held by the caller only while this bounded streaming copy runs.
    static func prepare(_ source: URL, parent: URL = FileManager.default.temporaryDirectory,
                        cancellation: BackupCancellation = BackupCancellation(),
                        capacity: (@Sendable (URL) throws -> Int64)? = nil,
                        didExtract: (String) throws -> Void = { _ in }) throws -> RestorePreview {
        let directory = parent.appendingPathComponent("FieldForge-Restore-Preview-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true, let count = size.fileSize, count >= 22, count < Int(UInt32.max) else {
                throw BackupError.invalid("Недопустимый размер архива ZIP32.")
            }
            try requireCapacity(directory, bytes: Int64(count) * 3, capacity: capacity)
            let archive = directory.appendingPathComponent("source.zip")
            try copy(source, archive, cancellation: cancellation)
            let validation = try BackupValidator.verify(archive, cancellation: cancellation)
            let manifest = try eligible(validation)
            let package = directory.appendingPathComponent("package")
            try fm.createDirectory(at: package, withIntermediateDirectories: false)
            let reader = try BackupArchiveReader(url: archive, cancellation: cancellation)
            guard reader.entries.count <= 65_534,
                  reader.entries.reduce(Int64(0), { $0 + Int64($1.size) }) < Int64(UInt32.max) else { throw StorageError.invalidRecord }
            for entry in reader.entries {
                try cancellation.check()
                let target = package.appendingPathComponent(entry.path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: target.path, contents: nil) else { throw StorageError.invalidRecord }
                let handle = try FileHandle(forWritingTo: target)
                do { try reader.stream(entry) { try handle.write(contentsOf: $0) }; try handle.synchronize(); try handle.close() }
                catch { try? handle.close(); throw error }
                try didExtract(entry.path)
            }
            try validateFiles(manifest, root: package, installed: false, cancellation: cancellation)
            try cancellation.check()
            return RestorePreview(directory: directory, archive: archive, manifest: manifest, byteCount: count)
        } catch { try? fm.removeItem(at: directory); throw error }
    }
    static func eligible(_ validation: BackupValidation) throws -> BackupManifest {
        guard let manifest = validation.manifest, validation.report.complete,
              manifest.completenessStatus == "complete", manifest.report.complete,
              manifest.pendingOperationPaths.isEmpty else {
            throw BackupError.invalid("Архив не является полной проверенной резервной копией. " + validation.report.problems.map(\.reason).joined(separator: "; "))
        }
        // The existing DXF parser and ImageIO metadata reader are in-memory
        // decoders. Refuse oversized originals rather than risking process OOM.
        guard manifest.files.allSatisfy({ file in
            (!file.path.hasPrefix("plans/originals/") || file.byteCount <= 32 * 1024 * 1024) &&
            (!file.path.hasPrefix("photos/originals/") || file.byteCount <= 128 * 1024 * 1024)
        }) else { throw BackupError.invalid("Оригинал превышает безопасный предел восстановления: DXF 32 МиБ, фото 128 МиБ.") }
        return manifest
    }
    static func requireCapacity(_ directory: URL, bytes: Int64,
                                capacity: (@Sendable (URL) throws -> Int64)? = nil) throws {
        let free = try capacity?(directory) ?? (fm.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard bytes >= 0, free > bytes + 32 * 1024 * 1024 else { throw BackupError.invalid("Недостаточно свободного места для безопасного восстановления.") }
    }
    /// Exact destination mapping. Historical sidecars stay opaque and cannot become
    /// current journals or collide with this operation's pre-restore recovery point.
    static func destination(_ path: String, root: URL, installed: Bool) -> URL {
        guard installed else { return root.appendingPathComponent(path) }
        switch path {
        case OfflineBackup.mappingPath: return root.appendingPathComponent(mappingName)
        case OfflineBackup.measurementPath: return root.appendingPathComponent(measurementName)
        case "manifest.json": return root.appendingPathComponent(marker + "/manifest.json")
        default:
            if path.hasPrefix("mapping/recovery/") || path.hasPrefix("measurements/recovery/") {
                return root.appendingPathComponent(marker + "/history/" + path)
            }
            return root.appendingPathComponent(path)
        }
    }
    static func validateFiles(_ manifest: BackupManifest, root: URL, installed: Bool,
                              cancellation: BackupCancellation = BackupCancellation()) throws {
        _ = try eligible(BackupValidation(manifest: manifest, report: manifest.report))
        guard manifest.files.allSatisfy({ BackupArchiveReader.safePath($0.path) }) else { throw StorageError.invalidRecord }
        guard try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: destination("manifest.json", root: root, installed: installed))) == manifest else {
            throw StorageError.changedFile
        }
        for file in manifest.files {
            let url = destination(file.path, root: root, installed: installed)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw StorageError.invalidRecord }
            let digest = try OfflineBackup.digest(url, cancellation: cancellation)
            guard digest.0 == file.byteCount, digest.1 == file.sha256 else { throw StorageError.changedFile }
        }
        let journal = try JSONDecoder().decode(MappingJournal.self, from: Data(contentsOf: destination(OfflineBackup.mappingPath, root: root, installed: installed)))
        try journal.validate()
        guard journal.projects.count == manifest.projectCount, journal.observations.count == manifest.observationCount,
              try BackupManifest.attachments(in: journal) == manifest.attachments else { throw StorageError.invalidRecord }
        if manifest.independentJournalPresent {
            let records = try FileMeasurementStore.inspectBackup(Data(contentsOf: destination(OfflineBackup.measurementPath, root: root, installed: installed)))
            guard records.map(\.id) == manifest.measurementIDs else { throw StorageError.invalidRecord }
        }
        for attachment in journal.photoAttachments {
            try cancellation.check()
            let url = destination("photos/" + attachment.relativePath, root: root, installed: installed)
            guard let image = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(image) > 0,
                  CGImageSourceGetStatus(image) == .statusComplete,
                  CGImageSourceGetType(image) as String? == attachment.format,
                  CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil,
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? Int) == attachment.pixelWidth,
                  (properties[kCGImagePropertyPixelHeight] as? Int) == attachment.pixelHeight else { throw StorageError.invalidRecord }
        }
        for plan in journal.plans {
            try cancellation.check()
            _ = try DXFDocument.parse(Data(contentsOf: destination("plans/originals/\(plan.attachmentID.uuidString).dxf", root: root, installed: installed)))
        }
        // Refuse injected files, links and special entries, including unreferenced originals.
        var actual = Set<String>()
        func walk(_ directory: URL, _ relative: String) throws {
            for child in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) {
                try cancellation.check()
                let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                let info = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                guard info.isSymbolicLink != true else { throw StorageError.invalidRecord }
                if info.isDirectory == true { try walk(child, path) }
                else { guard info.isRegularFile == true else { throw StorageError.invalidRecord }; actual.insert(path) }
            }
        }
        try walk(root, "")
        let expected = Set((manifest.files.map(\.path) + ["manifest.json"]).map {
            String(destination($0, root: root, installed: installed).path.dropFirst(root.path.count + 1))
        })
        guard actual == expected else { throw StorageError.invalidRecord }
    }

    /// Never a series of per-file atomic replacements. A durable intent guards two
    /// directory renames; startup rolls back any uncommitted intent before opening stores.
    static func activate(_ preview: RestorePreview, live: URL, journal: MappingJournal, mappingBytes: Data?,
                         measurements: MeasurementBackupSource,
                         capacity: (@Sendable (URL) throws -> Int64)? = nil,
                         checkpoint: (Checkpoint) throws -> Void = { _ in }) throws -> URL {
        guard !exists(pointer(live)), live.lastPathComponent == "FieldForge",
              measurements.url == live.appendingPathComponent(measurementName) else { throw StorageError.writesBlocked }
        let manifest = try eligible(BackupValidator.verify(preview.archive))
        guard manifest == preview.manifest else { throw StorageError.changedFile }
        try validateFiles(manifest, root: preview.package, installed: false)
        try fm.createDirectory(at: recoveryRoot(live), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID(), transaction = recoveryRoot(live).appendingPathComponent(id.uuidString)
        try fm.createDirectory(at: transaction, withIntermediateDirectories: false)
        let incoming = transaction.appendingPathComponent("incoming"), previous = transaction.appendingPathComponent("previous")
        // Protection ZIP plus new installed dataset and conservative overhead; the
        // old directory is retained by rename, never deleted or copied over live data.
        if !exists(live) {
            guard mappingBytes == nil, measurements.expectedBytes == nil, journal == MappingJournal() else { throw StorageError.changedFile }
            try fm.createDirectory(at: live, withIntermediateDirectories: false)
        }
        let oldSources = BackupSources(mapping: live.appendingPathComponent(mappingName), measurements: measurements.url,
            photos: live.appendingPathComponent("photos"), plans: live.appendingPathComponent("plans"))
        let oldSize = try OfflineBackup.inventory(oldSources).values.reduce(Int64(0)) {
            $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        try requireCapacity(transaction, bytes: oldSize * 3 + Int64(preview.byteCount) * 2, capacity: capacity)
        let capture = try OfflineBackup.capture(journal: journal, mappingBytes: mappingBytes, sources: oldSources,
            measurements: measurements, cancellation: BackupCancellation(), parent: transaction)
        let backup = try OfflineBackup.package(capture, cancellation: BackupCancellation())
        defer { backup.files.cleanup() }
        _ = try eligible(BackupValidator.verify(backup.files.urls[0]))
        let protection = transaction.appendingPathComponent("pre-restore.zip")
        try fm.moveItem(at: backup.files.urls[0], to: protection)
        try syncFile(protection); try syncDirectory(transaction)
        try fm.createDirectory(at: incoming, withIntermediateDirectories: false)
        for path in manifest.files.map(\.path) + ["manifest.json"] {
            try copy(preview.package.appendingPathComponent(path), destination(path, root: incoming, installed: true), cancellation: BackupCancellation())
        }
        try validateFiles(manifest, root: incoming, installed: true)
        try syncTree(incoming); try syncDirectory(transaction)
        try syncTree(live)
        try checkpoint(.protected)
        let inode = try inode(live)
        let manifestHash = try OfflineBackup.digest(destination("manifest.json", root: incoming, installed: true), cancellation: BackupCancellation()).1
        var intent = Intent(version: 1, id: id, originalInode: inode, manifestSHA256: manifestHash, committed: false)
        try writeIntent(intent, live: live)
        try checkpoint(.intent)
        try fm.moveItem(at: live, to: previous)
        try syncDirectory(transaction); try syncDirectory(live.deletingLastPathComponent())
        try checkpoint(.oldMoved)
        try fm.moveItem(at: incoming, to: live)
        try syncDirectory(transaction); try syncDirectory(live.deletingLastPathComponent())
        try checkpoint(.newMoved)
        try validateFiles(manifest, root: live, installed: true)
        // Authoritative reopen, with independent compatibility inspection but no migration.
        _ = try MappingWorkflow(store: FileMappingStore(url: live.appendingPathComponent(mappingName)))
        _ = try FileMeasurementStore(url: live.appendingPathComponent(measurementName)).loadRestored()
        try checkpoint(.reopened)
        intent.committed = true
        try writeIntent(intent, live: live)
        try checkpoint(.committed)
        try fm.removeItem(at: pointer(live)); try syncDirectory(recoveryRoot(live))
        return protection
    }
    /// Idempotent across crashes during recovery too. Original directory inode binds
    /// the no-previous case to the old dataset; missing/ambiguous data fails closed.
    enum RecoveryCheckpoint: CaseIterable { case displaced, returned }
    static func recover(live: URL, checkpoint: (RecoveryCheckpoint) throws -> Void = { _ in }) throws {
        let active = pointer(live)
        guard exists(active) else { return }
        let bytes = try Data(contentsOf: active)
        guard bytes.count < 4096 else { throw StorageError.invalidRecord }
        let intent = try JSONDecoder().decode(Intent.self, from: bytes)
        guard intent.version == 1 else { throw StorageError.unsupportedVersion }
        let transaction = recoveryRoot(live).appendingPathComponent(intent.id.uuidString)
        let previous = transaction.appendingPathComponent("previous"), rejected = transaction.appendingPathComponent("rejected")
        if intent.committed, exists(live) {
            let manifestURL = destination("manifest.json", root: live, installed: true)
            if (try? OfflineBackup.digest(manifestURL, cancellation: BackupCancellation()).1) == intent.manifestSHA256,
               let manifest = try? JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: manifestURL)),
               (try? validateFiles(manifest, root: live, installed: true)) != nil {
                try fm.removeItem(at: active); try syncDirectory(recoveryRoot(live)); return
            }
        }
        if exists(previous) {
            guard try inode(previous) == intent.originalInode else { throw StorageError.invalidRecord }
            if exists(live) {
                try fm.moveItem(at: live, to: rejected); try syncDirectory(transaction); try syncDirectory(live.deletingLastPathComponent())
                try checkpoint(.displaced)
            }
            try fm.moveItem(at: previous, to: live)
            try syncDirectory(transaction); try syncDirectory(live.deletingLastPathComponent())
            try checkpoint(.returned)
        }
        guard exists(live), try inode(live) == intent.originalInode else { throw StorageError.writesBlocked }
        try fm.removeItem(at: active); try syncDirectory(recoveryRoot(live))
    }
    private static func inode(_ url: URL) throws -> UInt64 {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true,
              let value = try fm.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber else { throw StorageError.invalidRecord }
        return value.uint64Value
    }
    private static func writeIntent(_ intent: Intent, live: URL) throws {
        try JSONEncoder().encode(intent).write(to: pointer(live), options: .atomic)
        try syncFile(pointer(live)); try syncDirectory(recoveryRoot(live)); try syncDirectory(live.deletingLastPathComponent())
    }
    static func copy(_ source: URL, _ target: URL, cancellation: BackupCancellation) throws {
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: target.path, contents: nil) else { throw StorageError.invalidRecord }
        let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
        _ = try OfflineBackup.digest(source, cancellation: cancellation) { try output.write(contentsOf: $0) }
        try output.synchronize()
    }
    private static func syncFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.synchronize()
    }
    private static func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY); guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    private static func syncTree(_ url: URL) throws {
        for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
            let info = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw StorageError.invalidRecord }
            if info.isDirectory == true { try syncTree(child) }
            else { guard info.isRegularFile == true else { throw StorageError.invalidRecord }; try syncFile(child) }
        }
        try syncDirectory(url)
    }
}
