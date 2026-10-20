import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Results describe received managed originals, not a claim about a camera/library master.
struct PhotoOriginalCheck: Codable {
    let status: String
    let actualByteCount: Int?
    let actualSHA256: String?
    let error: String?
    var available: Bool { status == "verified" }
}

extension ManagedPhotoStore {
    /// Read only this UUID's regular managed original. Copy and digest the SAME chunks.
    /// Output, if requested, belongs exclusively to the export operation, never this store.
    func inspectForExport(_ attachment: PhotoAttachment, photoID: UUID, copyTo: URL? = nil) throws -> PhotoOriginalCheck {
        try Task.checkCancellation()
        func failed(_ status: String, _ message: String, count: Int? = nil, hash: String? = nil) -> PhotoOriginalCheck {
            PhotoOriginalCheck(status: status, actualByteCount: count, actualSHA256: hash, error: message)
        }
        let intent = root.appendingPathComponent("operations/\(photoID.uuidString).json")
        if FileManager.default.fileExists(atPath: intent.path) {
            return failed("incompleteOperation", "Операция вложения не завершена; выполните восстановление в карточке фотографии.")
        }
        let url = originalURL(attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { return failed("missing", "Оригинал отсутствует.") }
        let expected = root.resolvingSymlinksInPath().appendingPathComponent("originals/\(attachment.id.uuidString)")
        let input: FileHandle
        do {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  url.resolvingSymlinksInPath().path == expected.path else {
                return failed("unsafeSource", "Оригинал не является обычным файлом по управляемому UUID-пути.")
            }
            input = try FileHandle(forReadingFrom: url)
        } catch { return failed("unreadable", "Не удалось открыть оригинал: \(error.localizedDescription)") }
        defer { try? input.close() }
        var output: FileHandle?
        if let copyTo {
            guard !FileManager.default.fileExists(atPath: copyTo.path),
                  FileManager.default.createFile(atPath: copyTo.path, contents: nil) else { throw CocoaError(.fileWriteFileExists) }
            output = try FileHandle(forWritingTo: copyTo)
        }
        defer { try? output?.close() }
        var count = 0, hash = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do { chunk = try input.read(upToCount: 256 * 1024) ?? Data() }
            catch { return failed("unreadable", "Ошибка чтения оригинала: \(error.localizedDescription)", count: count) }
            if chunk.isEmpty { break }
            count += chunk.count
            hash.update(data: chunk)
            // A changed/unbounded source cannot consume unlimited disk space.
            if count > Self.maximumBytes {
                return failed("sizeMismatch", "Оригинал превышает допустимый размер.", count: count)
            }
            try output?.write(contentsOf: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == attachment.byteCount else { return failed("sizeMismatch", "Размер оригинала не совпадает.", count: count, hash: digest) }
        guard digest == attachment.sha256 else { return failed("sha256Mismatch", "SHA-256 оригинала не совпадает.", count: count, hash: digest) }
        try output?.synchronize()
        return PhotoOriginalCheck(status: "verified", actualByteCount: count, actualSHA256: digest, error: nil)
    }
}

struct PhotoPackageConfirmationRequired: Error {
    let export: PhotoPackageExport
}

/// Selection is exclusively inherited from the existing typed mapping snapshot.
/// Originals are rechecked into private staging before entering the ZIP. Only one
/// original is staged at a time; source changes can never corrupt an included entry.
struct PhotoPackageExport {
    static let version = "FieldForge-Photo-Export/1"
    static let prefix = "FieldForge-Photos/"
    struct Item {
        let photo: PhotoObservation
        let attachment: PhotoAttachment
        var check: PhotoOriginalCheck
        var path: String { "originals/photo-\(photo.id.uuidString).\(PhotoPackageExport.fileExtension(attachment))" }
    }
    let snapshot: MappingCSVExport
    let store: ManagedPhotoStore
    var items: [Item]
    var availableCount: Int { items.filter { $0.check.available }.count }
    var unavailableCount: Int { items.count - availableCount }
    var availableBytes: Int { items.filter { $0.check.available }.reduce(0) { $0 + ($1.check.actualByteCount ?? 0) } }
    var archiveStatus: String { unavailableCount == 0 ? "complete" : "incomplete" }

    static func fileExtension(_ attachment: PhotoAttachment) -> String {
        let type = UTType(attachment.format)
        // Preserve safe source spelling (jpg vs jpeg), only when it matches detected format.
        let source = attachment.originalFilename.map { URL(fileURLWithPath: $0).pathExtension.lowercased() } ?? ""
        if safeExtension(source), UTType(filenameExtension: source) == type, type != nil { return source }
        let detected = type?.preferredFilenameExtension ?? "bin"
        return safeExtension(detected) ? detected : "bin"
    }
    private static func safeExtension(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9]{1,16}$", options: .regularExpression) != nil
    }

    static func prepare(snapshot: MappingCSVExport, journal: MappingJournal, store: ManagedPhotoStore) throws -> Self {
        try journal.validatePhotos()
        let rows = snapshot.tables.first { $0.name == "photos" }
        guard let rows, let column = rows.columns.firstIndex(of: "photo_id") else { throw StorageError.invalidRecord }
        let ids = Set(rows.rows.compactMap { row -> UUID? in
            if case .text(let value) = row[column] { return UUID(uuidString: value) }; return nil
        })
        let attachments = Dictionary(uniqueKeysWithValues: journal.photoAttachments.map { ($0.id, $0) })
        let photos = journal.photos.filter { ids.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard photos.count == rows.rows.count else { throw StorageError.invalidRecord }
        let items = try photos.map { photo -> Item in
            try Task.checkCancellation()
            guard let a = attachments[photo.attachmentID] else { throw StorageError.invalidRecord }
            return Item(photo: photo, attachment: a, check: try store.inspectForExport(a, photoID: photo.id))
        }
        return Self(snapshot: snapshot, store: store, items: items)
    }

    func write(allowIncomplete: Bool = false, parent: URL = FileManager.default.temporaryDirectory,
               append: @escaping (Data, FileHandle) throws -> Void = { try $1.write(contentsOf: $0) }) throws -> MappingExportFiles {
        try Task.checkCancellation()
        if unavailableCount > 0 && !allowIncomplete { throw PhotoPackageConfirmationRequired(export: self) }
        let directory = parent.appendingPathComponent("FieldForge-Photo-Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let zip = directory.appendingPathComponent("FieldForge-Photos.zip")
            let archive = try XLSXArchive(url: zip, append: append)
            defer { archive.close() }
            func addFile(_ url: URL, path: String) throws {
                let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                try archive.bytes(Self.prefix + path) { emit in
                    while true {
                        try Task.checkCancellation()
                        let chunk = try input.read(upToCount: 256 * 1024) ?? Data()
                        if chunk.isEmpty { break }; try emit(chunk)
                    }
                }
            }
            var result = self
            for i in result.items.indices {
                try Task.checkCancellation()
                let staged = directory.appendingPathComponent("verified-original")
                let item = result.items[i]
                result.items[i].check = try store.inspectForExport(item.attachment, photoID: item.photo.id, copyTo: staged)
                if result.items[i].check.available { try addFile(staged, path: item.path) }
                if FileManager.default.fileExists(atPath: staged.path) { try FileManager.default.removeItem(at: staged) }
            }
            // A file may disappear/change since preview: require confirmation again.
            if result.unavailableCount > 0 && !allowIncomplete { throw PhotoPackageConfirmationRequired(export: result) }
            let workbook = directory.appendingPathComponent("FieldForge-Mapping.xlsx")
            try MappingXLSXExport.write(result.workbookSnapshot(), to: workbook,
                                       photoPackageStatus: result.archiveStatus.uppercased())
            try addFile(workbook, path: "FieldForge-Mapping.xlsx")
            try FileManager.default.removeItem(at: workbook)
            let manifest = try result.manifest()
            try archive.bytes(Self.prefix + "manifest.json") { try $0(manifest) }
            try archive.finish(); archive.close()
            try Task.checkCancellation()
            return MappingExportFiles(directory: directory, urls: [zip])
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    func manifest() throws -> Data {
        let mapping = try JSONSerialization.jsonObject(with: snapshot.manifest) as? [String: Any] ?? [:]
        let keys = ["project_id", "horizon_id", "excavation_id", "first_day_inclusive", "last_day_inclusive", "calendar", "timezone", "start_inclusive_utc", "end_exclusive_utc", "effective_policy"]
        let selection = Dictionary(uniqueKeysWithValues: keys.map { ($0, mapping[$0] ?? NSNull()) })
        let rows: [[String: Any]] = items.map { item in
            let p = item.photo, a = item.attachment, c = p.context, check = item.check
            return ["photo_id": p.id.uuidString, "attachment_id": a.id.uuidString,
                    "point_id": c.pointID.uuidString, "context_revision_id": c.pointRevisionID.uuidString,
                    "context_point_version": c.pointVersion, "project_id": c.projectID.uuidString,
                    "horizon_id": c.horizonID.uuidString, "excavation_id": c.excavationID.uuidString,
                    "capture_location_basis": c.locationBasis.rawValue,
                    "original_filename": a.originalFilename ?? NSNull(), "format": a.format,
                    "representation": a.representation, "expected_byte_count": a.byteCount,
                    "actual_byte_count": check.actualByteCount as Any? ?? NSNull(),
                    "sha256_expected": a.sha256, "sha256_actual": check.actualSHA256 ?? NSNull(),
                    "archive_relative_path": item.path, "included": check.available,
                    "integrity_status": check.status, "error": check.error ?? NSNull()]
        }
        let data: [String: Any] = ["format": Self.version, "export_id": snapshot.id.uuidString,
            "created_at_utc": MappingCSVExport.iso(Date()), "snapshot_at_utc": MappingCSVExport.iso(snapshot.snapshotAt),
            "snapshot_reference_seconds": snapshot.snapshotAt.timeIntervalSinceReferenceDate,
            "selection": selection, "archive_status": archiveStatus, "observation_count": snapshot.pointCount,
            "listed_photo_count": items.count, "included_original_count": availableCount,
            "unavailable_original_count": unavailableCount, "included_original_bytes": availableBytes,
            "path_base": "Directory containing manifest.json and FieldForge-Mapping.xlsx",
            "purpose": "Workstation PHOTO EXPORT only; not a complete database backup or restore package.",
            "metadata_profile": "Exact managed received-original bytes, including embedded private EXIF/GPS; no sanitization or re-encoding. Representation limitations remain in workbook/manifest.",
            "photographs": rows]
        return try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Append package-only columns and a convenient joined register; ordinary CSV/XLSX stays unchanged.
    func workbookSnapshot() -> MappingCSVExport {
        typealias Cell = MappingCSVExport.Cell
        typealias Table = MappingCSVExport.Table
        func rows(_ name: String) -> [[String: Cell]] {
            guard let t = snapshot.tables.first(where: { $0.name == name }) else { return [] }
            return t.rows.map { Dictionary(uniqueKeysWithValues: zip(t.columns, $0)) }
        }
        func text(_ value: Cell?) -> String { if case .text(let s) = value { return s }; return "" }
        let byPhoto = Dictionary(uniqueKeysWithValues: items.map { ($0.photo.id.uuidString, $0) })
        let byAttachment = Dictionary(uniqueKeysWithValues: items.map { ($0.attachment.id.uuidString, $0) })
        let extra = ["archive_relative_path", "archive_integrity_status", "archive_included", "actual_byte_count", "sha256_actual", "archive_error", "archive_status"]
        func values(_ item: Item) -> [Cell] {
            [.text(item.path), .text(item.check.status), .text(String(item.check.available)),
             .integer(item.check.actualByteCount), item.check.actualSHA256.map(Cell.text) ?? .empty,
             item.check.error.map(Cell.text) ?? .empty, .text(archiveStatus.uppercased())]
        }
        let tables = snapshot.tables.map { table -> Table in
            guard table.name == "photos" || table.name == "photo_attachments" else { return table }
            let idColumn = table.columns.firstIndex(of: table.name == "photos" ? "photo_id" : "attachment_id")!
            let integrity = table.columns.firstIndex(of: "original_integrity")!
            let augmented = table.rows.map { row -> [Cell] in
                let item = (table.name == "photos" ? byPhoto : byAttachment)[text(row[idColumn])]!
                var row = row; row[integrity] = .text(item.check.status)
                return row + values(item)
            }
            return Table(name: table.name, columns: table.columns + extra, rows: augmented)
        }
        let projects = rows("projects"), horizons = rows("horizons"), excavations = rows("excavations"), points = rows("points")
        let photoTable = snapshot.tables.first { $0.name == "photos" }!
        let attachmentTable = snapshot.tables.first { $0.name == "photo_attachments" }!
        let attachmentColumns = attachmentTable.columns.filter { $0 != "attachment_id" && $0 != "original_integrity" }
        let registerRows = rows("photos").map { photo -> [Cell] in
            let item = byPhoto[text(photo["photo_id"])]!
            let point = points.first { text($0["point_id"]) == text(photo["point_id"]) } ?? [:]
            let a = rows("photo_attachments").first { text($0["attachment_id"]) == item.attachment.id.uuidString } ?? [:]
            let project = projects.first { text($0["project_id"]) == text(photo["project_id"]) }?["name"] ?? .empty
            let horizon = horizons.first { text($0["horizon_id"]) == text(photo["horizon_id"]) }?["name"] ?? .empty
            let excavation = excavations.first { text($0["excavation_id"]) == text(photo["excavation_id"]) }?["name"] ?? .empty
            var cells: [Cell] = [project, horizon, excavation, point["picket"] ?? .empty, point["observed_at_utc"] ?? .empty,
                point["observed_at_reference_seconds"] ?? .empty, point["observed_zone"] ?? .empty,
                .text(item.photo.capturedAt == nil ? "UNKNOWN" : "known")]
            cells += photoTable.columns.map { $0 == "original_integrity" ? .text(item.check.status) : photo[$0] ?? .empty }
            cells += attachmentColumns.map { a[$0] ?? .empty }
            return cells + values(item)
        }
        let register = Table(name: "photo_register", columns: ["project_name", "horizon_name", "excavation_name", "current_point_picket", "field_observed_at_utc", "field_observed_at_reference_seconds", "field_observed_zone", "capture_time_status"] + photoTable.columns + attachmentColumns + extra, rows: registerRows)
        return MappingCSVExport(id: snapshot.id, snapshotAt: snapshot.snapshotAt, selection: snapshot.selection,
                                tables: tables + [register], manifest: snapshot.manifest)
    }
}
