import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class P41PhotoTests: XCTestCase {
    enum Failure: Error { case injected }
    func directory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }; try body(root)
    }
    func image(_ color: UInt8 = 10, exif: [CFString: Any]? = nil, gps: [CFString: Any]? = nil) throws -> Data {
        let bytes = Data([color, 20, 30, 255, color, 40, 50, 255])
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let cg = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary] = exif }
        if let gps { properties[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(writer, cg, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer)); return data as Data
    }
    func seed() throws -> (MappingTests.MemoryStore, MappingWorkflow, MappingObservation) {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        // A legacy horizon with no known elevation gives an entirely unlocated point.
        store.value.horizons[0].elevationMeters = nil
        w = try MappingWorkflow(store: store); w.draft.picket = "5"
        let point = try w.save(); XCTAssertNil(point.coordinates); XCTAssertTrue(w.journal.plans.isEmpty)
        return (store, w, point)
    }
    func begin(_ files: ManagedPhotoStore, _ w: MappingWorkflow, _ point: MappingObservation, color: UInt8 = 10) throws -> PhotoImportOperation {
        try files.begin(data: image(color), filename: "same.jpg", context: w.journal.photoContext(for: point.id),
            source: .files, representation: "received bytes unchanged")
    }
    func finish(_ op: PhotoImportOperation, _ files: ManagedPhotoStore, _ w: inout MappingWorkflow) throws {
        try files.promote(op); try w.registerPhoto(op); try files.complete(op)
    }
    func testThreeDifferentPhotosUnlocatedPointNamesDatesBytesAndRelaunch() throws {
        try directory { root in
            let (_, initial, point) = try seed(); let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
            _ = try store.load(); try store.save(initial.journal)
            var w = try MappingWorkflow(store: store); let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
            let originals = w.journal.observations; let measurements = w.journal.measurements; let revisions = w.journal.revisions
            for n in 1...3 {
                let data = try image(UInt8(n * 60), exif: [kCGImagePropertyExifDateTimeOriginal: "2020:01:0\(n) 12:00:00", kCGImagePropertyExifOffsetTimeOriginal: "+05:00"])
                let op = try files.begin(data: data, filename: "same.jpg", context: w.journal.photoContext(for: point.id), source: .files,
                    representation: "received file", now: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)))
                try finish(op, files, &w)
                try w.correctPhoto(op.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "Фото \(n)", number: String(n), description: "Отдельное описание", category: .roof), reason: "Field annotation")
                XCTAssertEqual(try files.read(op.attachment), data)
                XCTAssertNotEqual(op.photo.capturedAt, op.photo.importedAt)
                XCTAssertEqual(op.attachment.format, UTType.jpeg.identifier)
                XCTAssertEqual(op.attachment.pixelWidth, 2); XCTAssertEqual(op.attachment.pixelHeight, 1)
            }
            let reopened = try MappingWorkflow(store: FileMappingStore(url: store.url))
            XCTAssertEqual(reopened.journal, w.journal); XCTAssertEqual(reopened.journal.photos.count, 3)
            XCTAssertEqual(Set(w.journal.photoAttachments.map(\.relativePath)).count, 3)
            XCTAssertEqual(Set(w.journal.photos.compactMap(\.capturedAt)).count, 3)
            XCTAssertEqual(w.journal.photos.map { w.journal.metadata(for: $0).name }, ["Фото 1", "Фото 2", "Фото 3"])
            XCTAssertEqual(w.journal.observations, originals); XCTAssertEqual(w.journal.measurements, measurements); XCTAssertEqual(w.journal.revisions, revisions)
            XCTAssertTrue(try files.pending().isEmpty)
        }
    }
    func testUnknownCaptureTimeNeverUsesImportTimeAndWallTimeKeepsUnknownOffset() throws {
        try directory { root in
            let (_, w, point) = try seed(); let files = ManagedPhotoStore(root: root)
            let noTime = try begin(files, w, point)
            XCTAssertNil(noTime.photo.capturedAt); XCTAssertNil(noTime.photo.captureTimeText)
            let op = try files.begin(data: image(exif: [kCGImagePropertyExifDateTimeOriginal: "2020:02:03 04:05:06"]), filename: nil,
                context: w.journal.photoContext(for: point.id), source: .photos, representation: "provider may transcode")
            XCTAssertNil(op.photo.capturedAt); XCTAssertTrue(op.photo.captureTimeText?.contains("offset unknown") == true)
            XCTAssertEqual(op.attachment.representation, "provider may transcode")
            let camera = try files.begin(data: image(), filename: nil, context: w.journal.photoContext(for: point.id),
                source: .camera, representation: "UIImage encoded JPEG; original unavailable", now: Date(timeIntervalSince1970: 1_800_000_000))
            XCTAssertNil(camera.photo.capturedAt); XCTAssertNil(camera.photo.captureTimeText)
            let cameraMetadata = try files.begin(data: image(), filename: nil, context: w.journal.photoContext(for: point.id),
                source: .camera, representation: "UIImage encoded JPEG; original unavailable",
                captureWallTime: "2020:01:02 03:04:05", captureUTCOffset: "+05:00", captureSubseconds: "123456")
            let base = try XCTUnwrap(ISO8601DateFormatter().date(from: "2020-01-01T22:04:05Z"))
            XCTAssertEqual(try XCTUnwrap(cameraMetadata.photo.capturedAt).timeIntervalSince(base), 0.123456, accuracy: 0.000001)
            XCTAssertTrue(cameraMetadata.photo.captureTimeText?.contains(".123456") == true)
            XCTAssertTrue(cameraMetadata.photo.captureTimeProvenance.contains("camera EXIF"))
        }
    }
    func testFrozenContextSurvivesSelectionAndPointCorrectionAndResolvesExactRevision() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root)
            var correction = try w.correction(for: point.id); correction.fields.x = "100.123456789"; correction.reason = "survey"
            let revision = try w.saveCorrection(correction)
            let op = try begin(files, w, point)
            XCTAssertEqual(op.photo.context.pointRevisionID, revision.id); XCTAssertEqual(op.photo.context.pointVersion, 2)
            let frozen = w.journal.photoPoint(op.photo.context)
            correction = try w.correction(for: point.id); correction.fields.x = "900"; correction.reason = "new survey"
            _ = try w.saveCorrection(correction)
            let other = try w.createProject(name: "B"); try w.requestContext(MappingContext(projectID: other))
            try finish(op, files, &w)
            XCTAssertEqual(w.journal.photoPoint(op.photo.context), frozen)
            XCTAssertNotEqual(w.journal.effectiveObservation(id: point.id)?.coordinates, frozen?.coordinates)
            XCTAssertTrue(w.observations.isEmpty)
            XCTAssertEqual(w.journal.photos.filter { $0.context.projectID == other }.count, 0)
            XCTAssertEqual(w.journal.photos[0].context.projectID, point.projectID)
        }
    }
    func testFailureAtEveryFileCheckpointRestartAndRetryKeepsUUIDs() throws {
        for failure in [ManagedPhotoStore.Checkpoint.intent, .staging, .promotion, .thumbnail] {
            try directory { root in
                let (store, initial, point) = try seed(); var w = initial
                let files = ManagedPhotoStore(root: root); let data = try image()
                files.checkpoint = { if $0 == failure { throw Failure.injected } }
                do { let op = try begin(files, w, point); try finish(op, files, &w); XCTFail("must inject failure") } catch {}
                let restarted = ManagedPhotoStore(root: root)
                let pending = try XCTUnwrap(restarted.pending().first)
                XCTAssertEqual(try restarted.pending().count, 1)
                if failure != .thumbnail { XCTAssertTrue(w.journal.photos.isEmpty); XCTAssertTrue(w.journal.photoAttachments.isEmpty) }
                if failure == .intent { try restarted.supply(data, for: pending) }
                var resumed = try MappingWorkflow(store: store)
                try finish(pending, restarted, &resumed)
                // Simulate crash after journal commit and before removing intent; register is idempotent.
                try resumed.registerPhoto(pending); try resumed.registerPhoto(pending)
                XCTAssertEqual(resumed.journal.photos.map(\.id), [pending.id])
                XCTAssertEqual(resumed.journal.photoAttachments.map(\.id), [pending.attachment.id])
                XCTAssertEqual(try restarted.read(pending.attachment), data)
                XCTAssertTrue(try restarted.pending().isEmpty)
            }
        }
    }
    func testJournalFailureDoesNotPublishLinkAndRestartRetriesPromotedOriginal() throws {
        try directory { root in
            let (store, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point); try files.promote(op)
            store.fail = true; XCTAssertThrowsError(try w.registerPhoto(op))
            XCTAssertTrue(w.journal.photos.isEmpty); XCTAssertTrue(w.journal.photoAttachments.isEmpty)
            XCTAssertEqual(try files.pending(), [op]); XCTAssertEqual(try files.read(op.attachment), try image())
            store.fail = false; var resumed = try MappingWorkflow(store: store)
            try finish(op, ManagedPhotoStore(root: root), &resumed); XCTAssertEqual(resumed.journal.photos, [op.photo])
        }
    }
    func testMissingCorruptOriginalKeepsRecordAndNeverShowsStaleThumbnail() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point); try finish(op, files, &w)
            let graph = w.journal; let original = try files.read(op.attachment)
            try Data(repeating: 0, count: original.count).write(to: files.originalURL(op.attachment))
            XCTAssertThrowsError(try files.read(op.attachment)); XCTAssertThrowsError(try files.thumbnail(op.attachment))
            try FileManager.default.removeItem(at: files.originalURL(op.attachment))
            XCTAssertThrowsError(try files.read(op.attachment)); XCTAssertThrowsError(try files.thumbnail(op.attachment))
            XCTAssertEqual(w.journal, graph); try w.journal.validate()
        }
    }
    func testThumbnailIsRegeneratedAndContainsNoEXIFGPS() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root)
            let data = try image(gps: [kCGImagePropertyGPSLatitude: 10.0, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 20.0, kCGImagePropertyGPSLongitudeRef: "E"])
            let originalSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let originalProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
            XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
            let op = try files.begin(data: data, filename: "wrong-extension.png", context: w.journal.photoContext(for: point.id),
                source: .files, representation: "received bytes")
            try finish(op, files, &w)
            XCTAssertEqual(op.attachment.format, UTType.jpeg.identifier)
            XCTAssertNil(w.journal.photoPoint(op.photo.context)?.coordinates)
            let before = try files.read(op.attachment)
            try FileManager.default.removeItem(at: files.thumbnailURL(op.attachment))
            let thumbnail = try files.thumbnail(op.attachment)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertNil(props[kCGImagePropertyGPSDictionary]); XCTAssertEqual(try files.read(op.attachment), before)
        }
    }
    func testInvalidImageAndCancelledSelectionLeaveNoOperationOrRecords() throws {
        try directory { root in
            let (_, w, point) = try seed(); let files = ManagedPhotoStore(root: root)
            // Cancelled/denied selection never calls begin; initial state remains unchanged.
            XCTAssertTrue(try files.pending().isEmpty); XCTAssertTrue(w.journal.photos.isEmpty)
            for data in [Data(), Data("not an image".utf8), Data(try image().prefix(20))] {
                XCTAssertThrowsError(try files.begin(data: data, filename: "a.jpg", context: w.journal.photoContext(for: point.id), source: .files, representation: "received"))
            }
            XCTAssertTrue(try files.pending().isEmpty); XCTAssertTrue(w.journal.photos.isEmpty)
        }
    }
    func testWrongReplacementCannotOverwriteStagedBytes() throws {
        try directory { root in
            let (_, w, point) = try seed(); let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point)
            XCTAssertThrowsError(try files.supply(image(240), for: op))
            try files.promote(op); XCTAssertEqual(try files.read(op.attachment), try image())
        }
    }
    func testMetadataRevisionsAreSeparateAndRejectStaleEdits() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point); try finish(op, files, &w)
            let original = w.journal
            try w.correctPhoto(op.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "Corrected", number: "9", description: "note", category: .joint), reason: "typo")
            XCTAssertEqual(w.journal.photos, original.photos); XCTAssertEqual(w.journal.observations, original.observations)
            XCTAssertEqual(w.journal.revisions, original.revisions); XCTAssertEqual(w.journal.metadata(for: op.photo).name, "Corrected")
            XCTAssertThrowsError(try w.correctPhoto(op.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "Stale"), reason: "stale"))
            XCTAssertThrowsError(try w.correctPhoto(op.id, baselineRevisionID: w.journal.photoRevisions.last?.id, metadata: PhotoMetadata(name: "Empty reason"), reason: " "))
        }
    }
    func testCrossProjectOrUnknownPointRevisionAndDanglingAttachmentAreRejected() throws {
        try directory { root in
            let (_, w, point) = try seed(); let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point)
            var bad = w.journal; bad.photos = [op.photo]; XCTAssertThrowsError(try bad.validate())
            bad.photoAttachments = [op.attachment]; try bad.validate()
            let context = PhotoContext(projectID: UUID(), horizonID: point.horizonID, excavationID: point.excavationID,
                pointID: point.id, pointRevisionID: point.id, pointVersion: 1)
            let wrong = try files.begin(data: image(), filename: "same.jpg", context: context, source: .files, representation: "received")
            bad.photos = [wrong.photo]; bad.photoAttachments = [wrong.attachment]; XCTAssertThrowsError(try bad.validate())
            bad = w.journal; bad.photoAttachments = [op.attachment]; XCTAssertThrowsError(try bad.validate())
        }
    }
    func testSchema6MigrationBacksUpExactBytesAndKeepsP33History() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial
            var draft = try w.correction(for: point.id); draft.fields.notes = "corrected"; draft.reason = "field log"
            _ = try w.saveCorrection(draft)
            var legacy = w.journal; legacy.schemaVersion = 6
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any])
            for key in ["photos", "photoAttachments", "photoRevisions"] { object.removeValue(forKey: key) }
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
            let url = root.appendingPathComponent("mapping.json"); try bytes.write(to: url)
            let migrated = try FileMappingStore(url: url).load()
            XCTAssertEqual(migrated.schemaVersion, 7); XCTAssertEqual(migrated.revisions, w.journal.revisions)
            XCTAssertEqual(migrated.observations, w.journal.observations); XCTAssertEqual(migrated.measurements, w.journal.measurements)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("p6-backup")), bytes)
            XCTAssertEqual(try FileMappingStore(url: url).load(), migrated)
        }
    }
    func testMigrationBackupCollisionFailsWithoutChangingSourceAndWritesAreBlocked() throws {
        try directory { root in
            let (_, w, _) = try seed(); var legacy = w.journal; legacy.schemaVersion = 6
            let bytes = try JSONEncoder().encode(legacy); let url = root.appendingPathComponent("mapping.json")
            try bytes.write(to: url); try Data("different backup".utf8).write(to: url.appendingPathExtension("p6-backup"))
            let store = FileMappingStore(url: url); XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(w.journal))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testCorruptedSchema7TablesFailClosedAndOldHeaderCannotHidePhotos() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
            let op = try begin(files, w, point); try finish(op, files, &w)
            var oldHeader = w.journal; oldHeader.schemaVersion = 6; XCTAssertThrowsError(try oldHeader.validate())
            let encoder = JSONEncoder()
            for key in ["photos", "photoAttachments", "photoRevisions"] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(w.journal)) as? [String: Any]); object.removeValue(forKey: key)
                let bytes = try JSONSerialization.data(withJSONObject: object); let url = root.appendingPathComponent("mapping.json"); try bytes.write(to: url)
                let store = FileMappingStore(url: url); XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(w.journal))
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }
    @MainActor func testPhotosPreserveAllP33OriginalEvidenceAndRevisionBytes() async throws {
        try directory { root in
            let (_, initial, point) = try P33RevisionTests().seed(); var w = initial
            var draft = try w.correction(for: point.id); draft.fields.x = "125.123456789"; draft.reason = "Survey correction"
            _ = try w.saveCorrection(draft)
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let original = try encoder.encode(w.journal.observations)
            let evidence = try encoder.encode(w.journal.measurements)
            let history = try encoder.encode(w.journal.revisions)
            let files = ManagedPhotoStore(root: root)
            let op = try begin(files, w, point); try finish(op, files, &w)
            try w.correctPhoto(op.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "Evidence image"), reason: "Label")
            XCTAssertEqual(try encoder.encode(w.journal.observations), original)
            XCTAssertEqual(try encoder.encode(w.journal.measurements), evidence)
            XCTAssertEqual(try encoder.encode(w.journal.revisions), history)
            XCTAssertEqual(w.journal.photoPoint(op.photo.context)?.coordinates?.x, 125.123456789)
        }
    }
    func testActualJournalBackupWriteFailureRetainsIntentAndNoPublishedLink() throws {
        try directory { root in
            let (_, initial, point) = try seed()
            let store = FileMappingStore(url: root.appendingPathComponent("mapping.json")); _ = try store.load(); try store.save(initial.journal)
            var w = try MappingWorkflow(store: store); let before = try Data(contentsOf: store.url)
            let files = ManagedPhotoStore(root: root.appendingPathComponent("photos")); let op = try begin(files, w, point)
            try files.promote(op)
            // A directory where the previous-snapshot file must be is an actual filesystem write error.
            try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: true)
            XCTAssertThrowsError(try w.registerPhoto(op)); XCTAssertTrue(w.journal.photos.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.url), before); XCTAssertEqual(try files.pending(), [op])
            try FileManager.default.removeItem(at: store.backupURL)
            var restarted = try MappingWorkflow(store: FileMappingStore(url: store.url)); try finish(op, files, &restarted)
            XCTAssertEqual(restarted.journal.photos.map(\.id), [op.id])
        }
    }
    func testUnreadableOperationAndUnwritableIntentNeverPublishAndKeepEvidence() throws {
        try directory { root in
            let (_, w, point) = try seed(); let files = ManagedPhotoStore(root: root)
            try Data("occupied path".utf8).write(to: root.appendingPathComponent("operations"))
            XCTAssertThrowsError(try begin(files, w, point)); XCTAssertTrue(w.journal.photos.isEmpty)
            try FileManager.default.removeItem(at: root.appendingPathComponent("operations"))
            let op = try begin(files, w, point); let staged = try Data(contentsOf: files.stagingURL(op))
            let invalid = Data("invalid operation JSON".utf8); try invalid.write(to: files.operationURL(op))
            XCTAssertThrowsError(try files.pending()); XCTAssertThrowsError(try files.promote(op))
            XCTAssertEqual(try Data(contentsOf: files.stagingURL(op)), staged)
            XCTAssertEqual(try Data(contentsOf: files.operationURL(op)), invalid)
        }
    }
    func testFileStoreRejectsRemovingOriginalPhotoOrMetadataHistory() throws {
        try directory { root in
            let (_, initial, point) = try seed(); var w = initial; let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
            let op = try begin(files, w, point); try finish(op, files, &w)
            let store = FileMappingStore(url: root.appendingPathComponent("mapping.json")); _ = try store.load(); try store.save(w.journal)
            var bad = w.journal; bad.photos = []; bad.photoAttachments = []; XCTAssertThrowsError(try store.save(bad))
            try w.correctPhoto(op.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "New"), reason: "rename"); try store.save(w.journal)
            bad = w.journal; bad.photoRevisions = []; XCTAssertThrowsError(try store.save(bad))
        }
    }
}
