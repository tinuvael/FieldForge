import XCTest
import ImageIO
import UniformTypeIdentifiers
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class PhotoPackageExportTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func png(_ gray: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer)); return data as Data
    }
    private func seed(filename: String = "same.png") throws -> (PhotoPackageExport, [UUID: Data]) {
        let root = try temporary(), project = UUID(), horizon = UUID(), excavation = UUID(), point = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000), oldDate = date.addingTimeInterval(-86400 * 30)
        var journal = MappingJournal()
        journal.projects = [.init(id: project, name: "Рудник Юникод")]
        journal.horizons = [.init(id: horizon, projectID: project, name: "+393", elevationDatum: "local")]
        journal.excavations = [.init(id: excavation, projectID: project, name: "Выработка", horizonIDs: [horizon])]
        func observation(_ fieldDate: Date, picket: String) -> MappingObservation {
            MappingObservation(id: point, projectID: project, horizonID: horizon, excavationID: excavation,
                picket: picket, chainageMeters: Double(picket)!, chainageOriginAndDirection: "survey origin; increasing",
                observedAt: fieldDate, observedTimeZoneID: "UTC", observedUTCOffsetSeconds: 0,
                createdAt: oldDate, updatedAt: oldDate, coordinates: nil, measurementIDs: [], notes: "", geology: nil)
        }
        journal.observations = [observation(oldDate, picket: "1")]
        let revision = UUID()
        journal.revisions = [.init(id: revision, observationID: point, version: 2, previousRevisionID: nil,
            correctedAt: date, author: nil, reason: "Field date correction", snapshot: observation(date, picket: "2"))]
        let store = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent("originals"), withIntermediateDirectories: true)
        var originals: [UUID: Data] = [:]
        for i in 0..<2 {
            let data = try png(CGFloat(i)), attachmentID = UUID(), photoID = UUID()
            let a = PhotoAttachment(id: attachmentID, originalFilename: filename, sha256: ManagedPhotoStore.digest(data),
                byteCount: data.count, format: UTType.png.identifier, mimeType: "image/png", pixelWidth: 2,
                pixelHeight: 2, orientation: 1, representation: "exact received bytes")
            let context = PhotoContext(projectID: project, horizonID: horizon, excavationID: excavation, pointID: point,
                pointRevisionID: i == 0 ? point : revision, pointVersion: i == 0 ? 1 : 2,
                locationBasis: i == 0 ? .unknownBeforeFirstSave : .pointRevision)
            journal.photos.append(.init(id: photoID, attachmentID: attachmentID, context: context, source: .files,
                importedAt: date.addingTimeInterval(86400 * 60), capturedAt: nil, captureTimeText: nil,
                captureTimeProvenance: "unknown", metadata: .init(name: "=1+1 Фото", description: "Русский\nтекст")))
            journal.photoAttachments.append(a); originals[photoID] = data
            try data.write(to: store.originalURL(a))
        }
        try journal.validate()
        let selection = MappingExportSelection(projectID: project, firstDay: date, lastDay: date, timeZoneID: "UTC")
        let snapshot = try MappingCSVExport.prepare(journal: journal, selection: selection, now: date)
        return (try PhotoPackageExport.prepare(snapshot: snapshot, journal: journal, store: store), originals)
    }
    /// Independent central-directory reader, including CRC-32 and local-entry consistency.
    private func unzip(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func word(_ i: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(b[i + $1]) << ($1 * 8) } }
        XCTAssertGreaterThanOrEqual(b.count, 22)
        XCTAssertEqual(word(b.count - 22, 4), 0x06054b50)
        var position = word(b.count - 6, 4), result: [String: Data] = [:]
        for _ in 0..<word(b.count - 12, 2) {
            XCTAssertEqual(word(position, 4), 0x02014b50); XCTAssertEqual(word(position + 10, 2), 0)
            let size = word(position + 20, 4), length = word(position + 28, 2), local = word(position + 42, 4)
            let name = String(decoding: b[(position + 46)..<(position + 46 + length)], as: UTF8.self)
            XCTAssertNil(result[name]); XCTAssertEqual(word(local, 4), 0x04034b50)
            let start = local + 30 + word(local + 26, 2) + word(local + 28, 2)
            let content = Data(b[start..<(start + size)])
            var crc: UInt32 = 0xFFFFFFFF
            for byte in content {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
            }
            XCTAssertEqual(word(position + 16, 4), Int(crc ^ 0xFFFFFFFF))
            XCTAssertEqual(word(start + size, 4), 0x08074b50)
            XCTAssertEqual(word(start + size + 8, 4), size)
            result[name] = content
            position += 46 + length + word(position + 30, 2) + word(position + 32, 2)
        }
        return result
    }
    private func package(_ files: MappingExportFiles) throws -> [String: Data] {
        try unzip(Data(contentsOf: XCTUnwrap(files.urls.first)))
    }
    private func manifest(_ entries: [String: Data]) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(entries[PhotoPackageExport.prefix + "manifest.json"])) as? [String: Any])
    }
    func testTwoOriginalsAreExactAndZIPIsReadable() throws {
        let (export, originals) = try seed()
        XCTAssertEqual(export.snapshot.pointCount, 1); XCTAssertEqual(export.items.count, 2)
        let files = try export.write(); defer { files.cleanup() }
        let entries = try package(files)
        XCTAssertEqual(entries.count, 4)
        for item in export.items { XCTAssertEqual(entries[PhotoPackageExport.prefix + item.path], originals[item.photo.id]) }
        let m = try manifest(entries)
        XCTAssertEqual(m["archive_status"] as? String, "complete")
        XCTAssertEqual(m["included_original_count"] as? Int, 2)
    }
    func testManifestAndExcelPreserveUUIDsHistoricalContextAndUnknownCapture() throws {
        let (export, _) = try seed()
        let files = try export.write(); defer { files.cleanup() }
        let entries = try package(files), m = try manifest(entries)
        let photos = try XCTUnwrap(m["photographs"] as? [[String: Any]])
        let xlsx = try unzip(XCTUnwrap(entries[PhotoPackageExport.prefix + "FieldForge-Mapping.xlsx"]))
        let register = String(decoding: try XCTUnwrap(xlsx["xl/worksheets/sheet21.xml"]), as: UTF8.self)
        for item in export.items {
            let row = try XCTUnwrap(photos.first { $0["photo_id"] as? String == item.photo.id.uuidString })
            XCTAssertEqual(row["attachment_id"] as? String, item.attachment.id.uuidString)
            XCTAssertEqual(row["point_id"] as? String, item.photo.context.pointID.uuidString)
            XCTAssertEqual(row["context_revision_id"] as? String, item.photo.context.pointRevisionID.uuidString)
            XCTAssertEqual(row["included"] as? Bool, true)
            for value in [item.photo.id.uuidString, item.attachment.id.uuidString, item.photo.context.pointID.uuidString,
                          item.photo.context.pointRevisionID.uuidString, item.path, "UNKNOWN", "=1+1 Фото"] {
                XCTAssertTrue(register.contains(value), value)
            }
        }
        XCTAssertTrue(register.contains("unknownBeforeFirstSave")); XCTAssertFalse(register.contains("<f>"))
        XCTAssertTrue(register.contains("field_observed_at_utc"))
        XCTAssertTrue(register.contains("Русский\nтекст"))
    }
    func testMissingAndChangedSincePreviewRequireExplicitPartialConfirmation() throws {
        let (export, _) = try seed()
        try FileManager.default.removeItem(at: export.store.originalURL(export.items[0].attachment))
        let url = export.store.originalURL(export.items[1].attachment)
        var data = try Data(contentsOf: url); data[0] ^= 1; try data.write(to: url)
        var updated: PhotoPackageExport?
        XCTAssertThrowsError(try export.write()) { error in updated = (error as? PhotoPackageConfirmationRequired)?.export }
        let incomplete = try XCTUnwrap(updated)
        XCTAssertEqual(Set(incomplete.items.map { $0.check.status }), ["missing", "sha256Mismatch"])
        XCTAssertThrowsError(try incomplete.write())
        let files = try incomplete.write(allowIncomplete: true); defer { files.cleanup() }
        let entries = try package(files), m = try manifest(entries)
        XCTAssertEqual(m["archive_status"] as? String, "incomplete")
        XCTAssertEqual(m["listed_photo_count"] as? Int, 2); XCTAssertEqual(m["included_original_count"] as? Int, 0)
        XCTAssertEqual(entries.count, 2)
        let xlsx = try unzip(XCTUnwrap(entries[PhotoPackageExport.prefix + "FieldForge-Mapping.xlsx"]))
        let text = xlsx.values.map { String(decoding: $0, as: UTF8.self) }.joined()
        XCTAssertTrue(text.contains("INCOMPLETE")); XCTAssertTrue(text.contains("missing")); XCTAssertTrue(text.contains("sha256Mismatch"))
    }
    func testUnsafeAndDuplicateOriginalNamesCannotBecomeArchivePaths() throws {
        let (export, _) = try seed(filename: "../../evil\\same.png")
        let files = try export.write(); defer { files.cleanup() }
        let entries = try package(files)
        XCTAssertEqual(Set(export.items.map(\.path)).count, 2)
        XCTAssertTrue(entries.keys.allSatisfy { !$0.hasPrefix("/") && !$0.contains("..") && !$0.contains("\\") && !$0.contains("evil") })
        let zip = try XLSXArchive(url: try temporary().appendingPathComponent("paths.zip"), append: { try $1.write(contentsOf: $0) })
        defer { zip.close() }
        for unsafe in ["/absolute", "../escape", "a/../b", "a\\b", "a//b", "a/", "a\u{0000}b"] {
            XCTAssertThrowsError(try zip.bytes(unsafe) { try $0(Data()) })
        }
        try zip.bytes("safe") { try $0(Data()) }
        XCTAssertThrowsError(try zip.bytes("safe") { try $0(Data()) })
    }
    func testCancellationAndWriteFailureOnlyRemoveOperationOutputs() throws {
        let (export, originals) = try seed(), parent = try temporary()
        for cancel in [true, false] {
            var writes = 0
            XCTAssertThrowsError(try export.write(parent: parent, append: { data, handle in
                writes += 1
                if writes == 2 { if cancel { throw CancellationError() }; throw CocoaError(.fileWriteOutOfSpace) }
                try handle.write(contentsOf: data)
            }))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
            for item in export.items { XCTAssertEqual(try Data(contentsOf: export.store.originalURL(item.attachment)), originals[item.photo.id]) }
        }
        let files = try export.write(parent: parent)
        files.cleanup()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
        for item in export.items { XCTAssertEqual(try Data(contentsOf: export.store.originalURL(item.attachment)), originals[item.photo.id]) }
    }
    func testIncompleteOperationSizeMismatchAndSymbolicLinkAreExplicit() throws {
        let (export, _) = try seed()
        let item = export.items[0], url = export.store.originalURL(item.attachment)
        try Data([1]).write(to: url)
        XCTAssertEqual(try export.store.inspectForExport(item.attachment, photoID: item.photo.id).status, "sizeMismatch")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: export.store.originalURL(export.items[1].attachment))
        XCTAssertEqual(try export.store.inspectForExport(item.attachment, photoID: item.photo.id).status, "unsafeSource")
        let intent = export.store.root.appendingPathComponent("operations/\(item.photo.id.uuidString).json")
        try FileManager.default.createDirectory(at: intent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unfinished".utf8).write(to: intent)
        XCTAssertEqual(try export.store.inspectForExport(item.attachment, photoID: item.photo.id).status, "incompleteOperation")
        XCTAssertEqual(try Data(contentsOf: intent), Data("unfinished".utf8))
    }
}
