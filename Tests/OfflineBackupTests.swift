import XCTest
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class OfflineBackupTests: XCTestCase {
    struct Fixture: Sendable {
        let root: URL
        let journal: MappingJournal
        let sources: BackupSources
        let measurementSource: MeasurementBackupSource
        let mappingBytes: Data
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func image(_ color: UInt8) throws -> Data {
        try P41PhotoTests().image(color, exif: [kCGImagePropertyExifDateTimeOriginal: "2020:02:03 04:05:06"],
                                 gps: [kCGImagePropertyGPSLatitude: 43.25, kCGImagePropertyGPSLatitudeRef: "N"])
    }
    /// Backup consumes an already durable photo graph; ImageIO-generated originals
    /// carry EXIF/GPS, while import/type-registry qualification stays in P4 tests.
    private func operation(data: Data, context: PhotoContext, source: PhotoSource = .files) -> PhotoImportOperation {
        let a = PhotoAttachment(id: UUID(), originalFilename: "same.jpg", sha256: ManagedPhotoStore.digest(data),
            byteCount: data.count, format: UTType.jpeg.identifier, mimeType: "image/jpeg", pixelWidth: 2,
            pixelHeight: 1, orientation: 1, representation: "Exact received original")
        let photo = PhotoObservation(id: UUID(), attachmentID: a.id, context: context, source: source,
            importedAt: Date(), capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown", metadata: .init(name: "Original"))
        return .init(version: 2, photo: photo, attachment: a)
    }

    private nonisolated static func waitFor(_ semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { semaphore.wait(); continuation.resume() }
        }
    }
    private func seed() throws -> Fixture {
        let root = try directory()
        let (_, initial, first) = try P33RevisionTests().seed(); var w = initial
        for i in 1...2 {
            var edit = try w.correction(for: first.id); edit.reason = "Correction \(i)"; edit.fields.notes = "Revision \(i)"
            if i == 1 {
                for id in [JointSetIdentifier.J3, .J4, .J5] {
                    var set = JointSetDraft(identifier: id)
                    set.representative = ManualOrientationInput(dipAngleText: "32.123456789", dipDirectionText: "150", reference: .gridNorth)
                    edit.fields.jointSets.append(set)
                }
                edit.fields.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair), lower: 35, upper: 45,
                                                finalValue: nil, assessedAt: Date(timeIntervalSince1970: 1_800_000_000))
            }
            _ = try w.saveCorrection(edit, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)))
        }
        let p = try w.createProject(name: "Independent B")
        try w.requestContext(.init(projectID: p)); let h = try w.createHorizon(elevation: "-120")
        try w.requestContext(.init(projectID: p, horizonID: h)); let e = try w.createExcavation(name: "B", horizonIDs: [h])
        try w.requestContext(.init(projectID: p, horizonID: h, excavationID: e)); w.draft.picket = "2+1.123456789"
        _ = try w.save(now: Date(timeIntervalSince1970: 1_800_000_010))
        let photos = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
        let plans = ManagedPlanStore(root: root.appendingPathComponent("plans"))
        for (i, point) in w.journal.observations.enumerated() {
            let data = try image(UInt8(i))
            let op = operation(data: data, context: try w.journal.photoContext(for: point.id))
            try photos.stage(data, for: op)
            try photos.promote(op); try w.registerPhoto(op)
            try FileManager.default.removeItem(at: photos.operationURL(op))
            try data.write(to: photos.thumbnailURL(op.attachment))
            try w.correctPhoto(op.photo.id, baselineRevisionID: nil, metadata: .init(name: "Field photo \(i)", description: "History"), reason: "Caption")
            let dxf = try DXFRealTests.data(200)
            let plan = try plans.stage(data: dxf, filename: "same.dxf", horizonID: point.horizonID, version: "A",
                                       units: .meters, crs: "mine grid", axes: "X east, Y north")
            try w.registerPlan(plan); plans.complete(plan)
        }
        let mapping = FileMappingStore(url: root.appendingPathComponent("mapping-v1.json"))
        try mapping.save(w.journal)
        let measurements = FileMeasurementStore(url: root.appendingPathComponent("measurements-v1.json"))
        try measurements.save(w.journal.measurements)
        // Preserve pre-existing historical recovery files as exact opaque evidence.
        try Data("historical mapping backup".utf8).write(to: mapping.backupURL)
        try Data("legacy backup bytes".utf8).write(to: measurements.legacyBackupURL)
        return Fixture(root: root, journal: w.journal,
            sources: .init(mapping: mapping.url, measurements: measurements.url, photos: photos.root, plans: plans.root),
            measurementSource: try measurements.backupSource(), mappingBytes: try Data(contentsOf: mapping.url))
    }
    private func capture(_ f: Fixture, token: BackupCancellation = BackupCancellation(),
                         hook: @escaping @Sendable (String) throws -> Void = { _ in }) async throws -> BackupStaging {
        try await Task.detached {
            try OfflineBackup.capture(journal: f.journal, mappingBytes: f.mappingBytes, sources: f.sources,
                measurements: f.measurementSource, cancellation: token, parent: f.root, didStageFile: hook)
        }.value
    }
    private func package(_ f: Fixture) async throws -> VerifiedBackup {
        let staged = try await capture(f)
        return try await Task.detached { try OfflineBackup.package(staged, cancellation: BackupCancellation()) }.value
    }
    private func entries(_ backup: VerifiedBackup) throws -> [String: Data] {
        let reader = try BackupArchiveReader(url: XCTUnwrap(backup.files.urls.first), cancellation: BackupCancellation())
        return try Dictionary(uniqueKeysWithValues: reader.entries.map { ($0.path, try reader.data($0.path)) })
    }
    private func rewrite(_ entries: [String: Data], root: URL) throws -> URL {
        let zip = root.appendingPathComponent(UUID().uuidString + ".zip")
        let writer = try XLSXArchive(url: zip, append: { try $1.write(contentsOf: $0) }); defer { writer.close() }
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) { try writer.bytes(path) { try $0(data) } }
        try writer.finish(); return zip
    }
    private func manifest(_ data: Data, change: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    func testSHA256PublishedVectorsAndBoundedStreaming() throws {
        let root = try directory(), file = root.appendingPathComponent("vector")
        try Data("abc".utf8).write(to: file)
        let result = try OfflineBackup.digest(file, cancellation: BackupCancellation())
        XCTAssertEqual(result.0, 3)
        XCTAssertEqual(result.1, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data().write(to: file)
        XCTAssertEqual(try OfflineBackup.digest(file, cancellation: BackupCancellation()).1,
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        try Data(repeating: 97, count: 700_000).write(to: file)
        var chunks = 0
        _ = try OfflineBackup.digest(file, cancellation: BackupCancellation()) { chunk in
            XCTAssertLessThanOrEqual(chunk.count, 256 * 1024); chunks += 1
        }
        XCTAssertEqual(chunks, 3)
    }

    func testTwoProjectsHistoryInterpretationsExactOriginalsAndReadOnlyVerification() async throws {
        let f = try seed(), before = try OfflineBackup.inventory(f.sources)
        let backup = try await package(f); defer { backup.files.cleanup() }
        XCTAssertTrue(backup.report.complete); XCTAssertEqual(backup.manifest.projectCount, 2)
        XCTAssertEqual(backup.manifest.observationCount, 2); XCTAssertEqual(backup.manifest.attachments.count, 4)
        let contents = try entries(backup)
        XCTAssertEqual(contents[OfflineBackup.mappingPath], f.mappingBytes)
        let decoded = try JSONDecoder().decode(MappingJournal.self, from: XCTUnwrap(contents[OfflineBackup.mappingPath]))
        XCTAssertEqual(decoded, f.journal); XCTAssertEqual(decoded.revisions.count, 2)
        XCTAssertEqual(decoded.revisions.last?.snapshot.geology?.jointSets.count, 5)
        XCTAssertNotNil(decoded.revisions.last?.snapshot.ratings?.gsi)
        XCTAssertEqual(decoded.photoRevisions.count, 2); XCTAssertEqual(decoded.measurements.count, 2)
        for a in backup.manifest.attachments {
            let live = try XCTUnwrap(before[a.path]); XCTAssertEqual(contents[a.path], try Data(contentsOf: live))
        }
        for file in backup.manifest.files {
            let data = try XCTUnwrap(contents[file.path])
            XCTAssertEqual(file.byteCount, data.count)
            XCTAssertEqual(file.sha256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        XCTAssertEqual(contents["mapping/recovery/mapping-v1.json.previous"], Data("historical mapping backup".utf8))
        XCTAssertEqual(contents["measurements/recovery/measurements-v1.json.phase1-backup"], Data("legacy backup bytes".utf8))
        XCTAssertEqual(contents[OfflineBackup.measurementPath], f.measurementSource.expectedBytes)
        XCTAssertEqual(backup.manifest.measurementIDs, f.journal.measurements.map(\.id))
        let zip = try XCTUnwrap(backup.files.urls.first), zipBefore = try Data(contentsOf: zip)
        let validation = try await Task.detached { try BackupValidator.verify(zip) }.value
        XCTAssertTrue(validation.report.complete); XCTAssertEqual(try Data(contentsOf: zip), zipBefore)
        XCTAssertEqual(try OfflineBackup.inventory(f.sources), before)
        XCTAssertEqual(try Data(contentsOf: f.sources.mapping), f.mappingBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("restored").path))
    }
    func testMissingPhotoAndCorruptDXFPreserveBytesAndAreNeverComplete() async throws {
        let f = try seed(), photo = try XCTUnwrap(f.journal.photoAttachments.first), plan = try XCTUnwrap(f.journal.plans.first)
        try FileManager.default.removeItem(at: f.sources.photos.appendingPathComponent(photo.relativePath))
        let dxf = ManagedPlanStore(root: f.sources.plans).fileURL(plan), broken = Data("damaged DXF".utf8)
        try broken.write(to: dxf)
        let backup = try await package(f); defer { backup.files.cleanup() }
        XCTAssertFalse(backup.report.complete); XCTAssertEqual(backup.report.problems.count, 2)
        let contents = try entries(backup)
        XCTAssertEqual(contents["plans/originals/\(plan.attachmentID.uuidString).dxf"], broken)
        XCTAssertNil(contents["photos/" + photo.relativePath])
        XCTAssertEqual(try Data(contentsOf: dxf), broken)
    }
    func testDurablePhotoAndDXFPendingOperationsStagingOrphansAndMalformedManifestsArePreserved() async throws {
        let f = try seed(), photos = ManagedPhotoStore(root: f.sources.photos), plans = ManagedPlanStore(root: f.sources.plans)
        let data = try image(50)
        let op = operation(data: data, context: try f.journal.photoContext(for: f.journal.observations[0].id), source: .camera)
        try photos.stage(data, for: op)
        let plan = try plans.stage(data: DXFRealTests.data(200), filename: "pending.dxf", horizonID: f.journal.horizons[0].id,
                                   version: "pending", units: .meters, crs: "local", axes: "XY")
        let malformed = f.sources.photos.appendingPathComponent("operations/\(UUID().uuidString).json")
        try Data("bad manifest".utf8).write(to: malformed)
        let backup = try await package(f); defer { backup.files.cleanup() }
        XCTAssertFalse(backup.report.complete); XCTAssertEqual(backup.manifest.pendingOperationPaths.count, 3)
        let contents = try entries(backup)
        XCTAssertEqual(contents["photos/staging/\(op.id.uuidString)"], try Data(contentsOf: photos.stagingURL(op)))
        XCTAssertNotNil(contents["plans/originals/\(plan.attachmentID.uuidString).dxf"])
        XCTAssertTrue(backup.report.problems.contains { $0.reason.contains("недействительные UUID") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: photos.operationURL(op).path))
    }
    func testArchiveCorruptionTruncationAndMissingEntriesFailVerification() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let original = try entries(backup)
        var changed = original; let photo = try XCTUnwrap(backup.manifest.attachments.first)
        changed[photo.path] = Data("corrupted original".utf8)
        for values in [changed, original.filter { $0.key != photo.path }] {
            let result = try BackupValidator.verify(rewrite(values, root: f.root))
            XCTAssertFalse(result.report.complete)
        }
        let zip = try XCTUnwrap(backup.files.urls.first)
        var bytes = try Data(contentsOf: zip); bytes.removeLast(10)
        let truncated = f.root.appendingPathComponent("truncated.zip"); try bytes.write(to: truncated)
        XCTAssertFalse(try BackupValidator.verify(truncated).report.complete)
        bytes = try Data(contentsOf: zip); bytes[100] ^= 0x80
        let crc = f.root.appendingPathComponent("crc.zip"); try bytes.write(to: crc)
        XCTAssertFalse(try BackupValidator.verify(crc).report.complete)
    }
    func testUnsupportedMalformedMetadataCountsUUIDLinksAndFalseCompletenessRejected() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let original = try entries(backup), data = try XCTUnwrap(original["manifest.json"])
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { $0["formatVersion"] = 99 }, { $0["mappingSchemaVersion"] = 7 },
            { $0["projectCount"] = 999 }, { $0["independentJournalPresent"] = false },
            { $0["measurementIDs"] = [UUID().uuidString] }, { $0["createdAtUTC"] = "yesterday" },
            { $0["files"] = "wrong type" },
            { object in var files = try XCTUnwrap(object["files"] as? [[String: Any]]); files.append(files[0]); object["files"] = files },
            { object in var a = try XCTUnwrap(object["attachments"] as? [[String: Any]]); a[0]["pointID"] = UUID().uuidString; object["attachments"] = a },
            { $0["report"] = ["problems": [["path": "invented", "reason": "false"]]] }
        ]
        for mutation in mutations {
            var values = original; values["manifest.json"] = try manifest(data, change: mutation)
            XCTAssertFalse(try BackupValidator.verify(rewrite(values, root: f.root)).report.complete)
        }
        var malformed = original; malformed["manifest.json"] = Data("{}".utf8)
        XCTAssertFalse(try BackupValidator.verify(rewrite(malformed, root: f.root)).report.complete)
        var dangling = original
        var journal = f.journal; journal.observations.removeAll()
        let raw = try JSONEncoder().encode(journal); dangling[OfflineBackup.mappingPath] = raw
        dangling["manifest.json"] = try manifest(data) { object in
            var files = try XCTUnwrap(object["files"] as? [[String: Any]])
            let i = try XCTUnwrap(files.firstIndex { $0["path"] as? String == OfflineBackup.mappingPath })
            files[i]["byteCount"] = raw.count; files[i]["sha256"] = ManagedPhotoStore.digest(raw); object["files"] = files
        }
        XCTAssertFalse(try BackupValidator.verify(rewrite(dangling, root: f.root)).report.complete)
    }
    func testUnsafePathsDuplicatesAndAmbiguousZIPMetadataRejected() async throws {
        let root = try directory()
        // Start with valid independently controlled entries, then mutate both name occurrences.
        let safe = try rewrite(["abc/def": Data("bytes".utf8), "ghi/jkl": Data("other".utf8)], root: root)
        let source = try Data(contentsOf: safe)
        for name in ["../evil", "/ab/def", "C:/file", "a\\b/def", "abc/def"] {
            var bytes = source
            let old = Data((name == "abc/def" ? "ghi/jkl" : "abc/def").utf8), new = Data(name.utf8)
            XCTAssertEqual(old.count, new.count)
            while let range = bytes.range(of: old) { bytes.replaceSubrange(range, with: new); if old == new { break } }
            let bad = root.appendingPathComponent(UUID().uuidString + ".zip"); try bytes.write(to: bad)
            XCTAssertThrowsError(try BackupArchiveReader(url: bad, cancellation: BackupCancellation()))
        }
        XCTAssertFalse(BackupArchiveReader.safePath("a//b")); XCTAssertFalse(BackupArchiveReader.safePath("a/./b"))
        XCTAssertFalse(BackupArchiveReader.safePath("a/../b")); XCTAssertFalse(BackupArchiveReader.safePath("a/\u{0}b"))
        var bytes = source; bytes[8] = 8 // local compression method disagrees with directory
        let bad = root.appendingPathComponent("method.zip"); try bytes.write(to: bad)
        XCTAssertThrowsError(try BackupArchiveReader(url: bad, cancellation: BackupCancellation()))
    }
    func testChangedStagingManifestCannotReplaceTheCapturedManifest() async throws {
        let f = try seed(), staged = try await capture(f)
        let url = staged.directory.appendingPathComponent("manifest.json")
        let changed = try manifest(Data(contentsOf: url)) { $0["createdAtUTC"] = "2020-01-01T00:00:00.000Z" }
        try changed.write(to: url)
        do {
            _ = try await Task.detached { try OfflineBackup.package(staged, cancellation: BackupCancellation()) }.value
            XCTFail("Staging manifest replacement accepted")
        } catch is BackupError {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.root.path).contains { $0.hasPrefix("FieldForge-Backup-") })
        XCTAssertEqual(try Data(contentsOf: f.sources.mapping), f.mappingBytes)
    }

    func testCancellationDuringCaptureAndVerificationCleansOnlyTemporaryOutput() async throws {
        let f = try seed(), token = BackupCancellation()
        do {
            _ = try await capture(f, token: token) { _ in token.cancel() }
            XCTFail("Cancelled capture succeeded")
        } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(try Data(contentsOf: f.sources.mapping), f.mappingBytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.root.path).contains { $0.hasPrefix("FieldForge-Backup-") })
        let staged = try await capture(f), other = BackupCancellation()
        do {
            _ = try await Task.detached { try OfflineBackup.package(staged, cancellation: other, verifying: { other.cancel() }) }.value
            XCTFail("Cancelled verification succeeded")
        } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.root.path).contains { $0.hasPrefix("FieldForge-Backup-") })
    }
    func testConcurrentExternalSameSizeMutationAndAddedFilesAreDetected() async throws {
        for addition in [false, true] {
            let f = try seed(), target = try XCTUnwrap(OfflineBackup.inventory(f.sources)["mapping/recovery/mapping-v1.json.previous"])
            do {
                _ = try await capture(f) { path in
                    if path == "mapping/recovery/mapping-v1.json.previous" {
                        if addition { try Data("new durable file".utf8).write(to: f.sources.photos.appendingPathComponent("originals/\(UUID().uuidString)")) }
                        else { var bytes = try Data(contentsOf: target); bytes[0] ^= 1; try bytes.write(to: target, options: .atomic) }
                    }
                }
                XCTFail("External modification ignored")
            } catch StorageError.changedFile {} catch { XCTFail("Unexpected \(error)") }
            XCTAssertEqual(try Data(contentsOf: f.sources.mapping), f.mappingBytes)
        }
    }
    func testStorageOwnerFIFOAndIndependentJournalWriterUseOneCapturedGeneration() async throws {
        let f = try seed(), owner = MappingStorageOwner(), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let opened = try await owner.open { FileMappingStore(url: f.sources.mapping) }
        let capture = Task {
            try await owner.captureBackup(measurements: f.measurementSource, photos: f.sources.photos, plans: f.sources.plans,
                cancellation: BackupCancellation(), parent: f.root, didStageFile: { path in
                    if path == OfflineBackup.mappingPath { entered.signal(); release.wait() }
                })
        }
        await Self.waitFor(entered)
        let mutation = Task { try await owner.transaction(snapshot: opened) { workflow in _ = try workflow.createProject(name: "After backup") } }
        let attempted = DispatchSemaphore(value: 0)
        let independent = Task.detached {
            attempted.signal()
            let file = FileMeasurementStore(url: f.sources.measurements)
            try file.save([])
        }
        await Self.waitFor(attempted)
        release.signal()
        let staged = try await capture.value
        let (newSnapshot, _) = try await mutation.value; try await independent.value
        XCTAssertEqual(newSnapshot.committed.journal.projects.count, 3)
        XCTAssertEqual(staged.manifest.projectCount, 2)
        XCTAssertEqual(staged.manifest.measurementIDs, f.journal.measurements.map(\.id))
        let backup = try await Task.detached { try OfflineBackup.package(staged, cancellation: BackupCancellation()) }.value
        defer { backup.files.cleanup() }
        XCTAssertTrue(backup.report.complete)
        XCTAssertEqual(try entries(backup)[OfflineBackup.mappingPath], f.mappingBytes)
        XCTAssertEqual(try FileMeasurementStore(url: f.sources.measurements).load().count, 0)
    }
    func testOwnerRejectsExternalMappingReplacementWithoutAdoptingOrWritingIt() async throws {
        let f = try seed(), owner = MappingStorageOwner()
        _ = try await owner.open { FileMappingStore(url: f.sources.mapping) }
        let replacement = Data("external invalid database".utf8); try replacement.write(to: f.sources.mapping)
        do {
            _ = try await owner.captureBackup(measurements: f.measurementSource, photos: f.sources.photos, plans: f.sources.plans, cancellation: BackupCancellation(), parent: f.root)
            XCTFail("External replacement adopted")
        } catch StorageError.changedFile {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(try Data(contentsOf: f.sources.mapping), replacement)
    }
    func testMissingChangedIndependentJournalAndUnsafeSourceRefuseCapture() async throws {
        for change in [0, 1, 2] {
            let f = try seed()
            if change == 0 { try FileManager.default.removeItem(at: f.sources.measurements) }
            if change == 1 { try Data("external".utf8).write(to: f.sources.measurements) }
            if change == 2 {
                let photo = try XCTUnwrap(f.journal.photoAttachments.first), url = f.sources.photos.appendingPathComponent(photo.relativePath)
                try FileManager.default.removeItem(at: url)
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: f.sources.measurements)
            }
            do { _ = try await capture(f); XCTFail("Changed/unsafe source accepted") } catch {}
            XCTAssertEqual(try Data(contentsOf: f.sources.mapping), f.mappingBytes)
        }
    }
    func testFreshAbsentJournalsAreExplicitAndBackupDoesNotCreateLiveFiles() async throws {
        let root = try directory(), owner = MappingStorageOwner(), mapping = root.appendingPathComponent("mapping.json"), measurements = root.appendingPathComponent("measurements.json")
        _ = try await owner.open { FileMappingStore(url: mapping) }
        let staged = try await owner.captureBackup(measurements: .init(url: measurements, expectedBytes: nil), photos: root.appendingPathComponent("photos"),
            plans: root.appendingPathComponent("plans"), cancellation: BackupCancellation(), parent: root)
        let backup = try await Task.detached { try OfflineBackup.package(staged, cancellation: BackupCancellation()) }.value
        defer { backup.files.cleanup() }
        XCTAssertTrue(backup.report.complete); XCTAssertFalse(backup.manifest.independentJournalPresent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mapping.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: measurements.path))
    }
    func testLegacyIndependentInspectionDoesNotMigrateAndCorruptJournalIsExplicitlyIncomplete() async throws {
        let f = try seed()
        // Use the exact legacy wire contract from the existing compatibility fixtures.
        let legacy = Phase1Fixtures.journal
        let records = try FileMeasurementStore.inspectBackup(legacy)
        XCTAssertFalse(records.isEmpty)
        try legacy.write(to: f.sources.measurements)
        let legacyFixture = Fixture(root: f.root, journal: f.journal, sources: f.sources,
            measurementSource: .init(url: f.sources.measurements, expectedBytes: legacy), mappingBytes: f.mappingBytes)
        let backup = try await package(legacyFixture); defer { backup.files.cleanup() }
        XCTAssertTrue(backup.report.complete); XCTAssertEqual(try entries(backup)[OfflineBackup.measurementPath], legacy)
        XCTAssertEqual(try Data(contentsOf: f.sources.measurements), legacy)
        let invalid = Data("corrupted journal".utf8); try invalid.write(to: f.sources.measurements)
        let bad = Fixture(root: f.root, journal: f.journal, sources: f.sources,
            measurementSource: .init(url: f.sources.measurements, expectedBytes: invalid), mappingBytes: f.mappingBytes)
        let partial = try await package(bad); defer { partial.files.cleanup() }
        XCTAssertFalse(partial.report.complete); XCTAssertEqual(try entries(partial)[OfflineBackup.measurementPath], invalid)
    }
}

extension OfflineBackupTests {
    private struct LiveFixture {
        let url: URL
        let journal: MappingJournal
        let measurements: FileMeasurementStore
        let owner: MappingStorageOwner
        let original: Data
    }
    private func restoreLive(parent: URL) async throws -> LiveFixture {
        let live = parent.appendingPathComponent("FieldForge")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: false)
        let file = FileMappingStore(url: live.appendingPathComponent(OfflineRestore.mappingName))
        var journal = MappingJournal(); journal.projects.append(.init(id: UUID(), name: "Previous dataset"))
        try file.save(journal)
        let measurements = FileMeasurementStore(url: live.appendingPathComponent(OfflineRestore.measurementName))
        try measurements.save([])
        try Data("opaque recovery evidence".utf8).write(to: live.appendingPathComponent("mapping-v1.json.previous"))
        try Data("unmanaged metadata retained".utf8).write(to: live.appendingPathComponent("storage-metadata"))
        let owner = MappingStorageOwner()
        let mappingURL = file.url
        _ = try await owner.open { FileMappingStore(url: mappingURL) }
        return .init(url: live, journal: journal, measurements: measurements, owner: owner, original: try Data(contentsOf: file.url))
    }
    private enum RestoreInterruption: Error { case crash }

    func testRestoreRoundTripExactEvidenceTwoProjectsAndRetainedProtection() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let live = try await restoreLive(parent: f.root)
        let source = try live.measurements.backupSource()
        let preview = try await Task.detached { try OfflineRestore.prepare(backup.files.urls[0]) }.value
        defer { preview.cleanup() }
        // Preview/staging never changes current data; activation is a separate call.
        XCTAssertEqual(try Data(contentsOf: source.url), source.expectedBytes)
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), live.original)
        let recovery = try await live.owner.restore(preview, measurements: source)
        let reopened = try MappingWorkflow(store: FileMappingStore(url: live.url.appendingPathComponent(OfflineRestore.mappingName)))
        XCTAssertEqual(reopened.journal, f.journal)
        XCTAssertEqual(reopened.journal.revisions.last?.snapshot.geology?.jointSets.count, 5)
        XCTAssertEqual(reopened.journal.photoRevisions.count, 2)
        for file in backup.manifest.files {
            XCTAssertEqual(try Data(contentsOf: OfflineRestore.destination(file.path, root: live.url, installed: true)),
                           try Data(contentsOf: preview.package.appendingPathComponent(file.path)))
        }
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), f.mappingBytes)
        XCTAssertEqual(try FileMeasurementStore(url: source.url).load(), f.journal.measurements.sorted { $0.timestamp > $1.timestamp })
        XCTAssertTrue(try BackupValidator.verify(recovery).report.complete)
        let previous = recovery.deletingLastPathComponent().appendingPathComponent("previous")
        XCTAssertEqual(try Data(contentsOf: previous.appendingPathComponent(OfflineRestore.mappingName)), live.original)
        XCTAssertEqual(try Data(contentsOf: previous.appendingPathComponent("storage-metadata")), Data("unmanaged metadata retained".utf8))
        // Old UI and independent store instances cannot save even if invoked later.
        do { try await live.owner.run { throw RestoreInterruption.crash }; XCTFail("Retired owner ran") }
        catch { XCTAssertTrue(error is StorageError) }
        XCTAssertThrowsError(try live.measurements.save([]))
        // Subsequent backup includes imported history as opaque recovery evidence.
        let fresh = FileMappingStore(url: live.url.appendingPathComponent(OfflineRestore.mappingName))
        let current = try fresh.load(), independent = FileMeasurementStore(url: source.url)
        _ = try independent.load()
        let captured = try OfflineBackup.capture(journal: current, mappingBytes: fresh.backupBytes(for: current),
            sources: .init(mapping: fresh.url, measurements: source.url, photos: live.url.appendingPathComponent("photos"), plans: live.url.appendingPathComponent("plans")),
            measurements: independent.backupSource(), cancellation: BackupCancellation())
        defer { captured.cleanup() }
        XCTAssertTrue(captured.manifest.report.complete)
        XCTAssertTrue(captured.manifest.files.contains { $0.path.hasPrefix("mapping/recovery/restored/") })
    }
    func testRestoreCrashAtEveryActivationCheckpoint() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
        for step in OfflineRestore.Checkpoint.allCases {
            let parent = try directory(), live = try await restoreLive(parent: parent)
            do {
                _ = try await live.owner.restore(preview, measurements: live.measurements.backupSource()) { if $0 == step { throw RestoreInterruption.crash } }
                XCTFail("Expected interruption")
            } catch { XCTAssertTrue(error is RestoreInterruption) }
            try OfflineRestore.recover(live: live.url)
            try OfflineRestore.recover(live: live.url) // recovery itself is idempotent
            let bytes = try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName))
            XCTAssertEqual(bytes, step == .committed ? f.mappingBytes : live.original, step.rawValue)
            let opened = try FileMappingStore(url: live.url.appendingPathComponent(OfflineRestore.mappingName)).load()
            XCTAssertEqual(opened, step == .committed ? f.journal : live.journal)
            let transactions = try FileManager.default.contentsOfDirectory(at: OfflineRestore.recoveryRoot(live.url), includingPropertiesForKeys: nil)
            XCTAssertTrue(try transactions.contains {
                let zip = $0.appendingPathComponent("pre-restore.zip")
                guard FileManager.default.fileExists(atPath: zip.path) else { return false }
                return try BackupValidator.verify(zip).report.complete
            })
        }
    }
    func testRestoreRecoveryInterruptedAndCorruptIntentFailsClosed() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
        for step in OfflineRestore.RecoveryCheckpoint.allCases {
            let live = try await restoreLive(parent: directory())
            do { _ = try await live.owner.restore(preview, measurements: live.measurements.backupSource()) { if $0 == .newMoved { throw RestoreInterruption.crash } } }
            catch { XCTAssertTrue(error is RestoreInterruption) }
            XCTAssertThrowsError(try OfflineRestore.recover(live: live.url) { if $0 == step { throw RestoreInterruption.crash } })
            try OfflineRestore.recover(live: live.url)
            XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), live.original)
            try Data("corrupt intent".utf8).write(to: OfflineRestore.recoveryRoot(live.url).appendingPathComponent("active.json"))
            XCTAssertThrowsError(try OfflineRestore.recover(live: live.url))
            XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), live.original)
        }
    }
    func testRestoreRejectsIncompleteUnsupportedUnsafeAndCorruptArchives() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let live = try await restoreLive(parent: f.root), values = try entries(backup)
        var invalid: [[String: Data]] = []
        for key in ["formatVersion", "mappingSchemaVersion"] {
            var next = values; next["manifest.json"] = try manifest(XCTUnwrap(values["manifest.json"])) { $0[key] = 999 }; invalid.append(next)
        }
        // The production writer itself refuses traversal; mutate a safe ZIP's
        // two filename headers to exercise restore's reader boundary.
        let safe = try rewrite(["abc/def": Data()], root: f.root)
        var unsafe = try Data(contentsOf: safe)
        while let range = unsafe.range(of: Data("abc/def".utf8)) { unsafe.replaceSubrange(range, with: Data("../evil".utf8)) }
        let unsafeURL = f.root.appendingPathComponent("unsafe.zip"); try unsafe.write(to: unsafeURL)
        XCTAssertThrowsError(try OfflineRestore.prepare(unsafeURL))
        var duplicateRelation = values
        duplicateRelation["manifest.json"] = try manifest(XCTUnwrap(values["manifest.json"])) { $0["projectCount"] = 99 }
        invalid.append(duplicateRelation)
        var missing = values; missing.removeValue(forKey: backup.manifest.attachments[0].path); invalid.append(missing)
        var corrupt = values; corrupt[OfflineBackup.mappingPath] = Data("invalid".utf8); invalid.append(corrupt)
        for entry in invalid {
            let archive = try rewrite(entry, root: f.root)
            XCTAssertThrowsError(try OfflineRestore.prepare(archive))
        }
        try FileManager.default.removeItem(at: f.sources.photos.appendingPathComponent(f.journal.photoAttachments[0].relativePath))
        let incomplete = try await package(f); defer { incomplete.files.cleanup() }
        let incompleteArchive = incomplete.files.urls[0]
        do {
            let accepted = try OfflineRestore.prepare(incompleteArchive); accepted.cleanup()
            XCTFail("Incomplete archive accepted")
        } catch { XCTAssertTrue(error is BackupError) }
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), live.original)
    }
    func testRestoreCancellationCapacityExtractionAndStagingMutation() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let token = BackupCancellation(); token.cancel()
        let parent = try directory()
        XCTAssertThrowsError(try OfflineRestore.prepare(backup.files.urls[0], parent: parent, cancellation: token))
        XCTAssertThrowsError(try OfflineRestore.prepare(backup.files.urls[0], parent: parent, capacity: { _ in 0 }))
        let during = BackupCancellation()
        XCTAssertThrowsError(try OfflineRestore.prepare(backup.files.urls[0], parent: parent, cancellation: during, didExtract: { _ in during.cancel() }))
        XCTAssertThrowsError(try OfflineRestore.prepare(backup.files.urls[0], parent: parent, didExtract: { _ in throw RestoreInterruption.crash }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
        let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
        let live = try await restoreLive(parent: f.root)
        XCTAssertThrowsError(try OfflineRestore.activate(preview, live: live.url, journal: live.journal, mappingBytes: live.original,
            measurements: live.measurements.backupSource(), capacity: { _ in 0 }))
        try Data("staging changed after verification".utf8).write(to: preview.package.appendingPathComponent(OfflineBackup.mappingPath))
        do { _ = try await live.owner.restore(preview, measurements: live.measurements.backupSource()); XCTFail("Changed staging accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), live.original)
    }
    func testRestoreUnprotectableCurrentDataRefusesReplacement() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
        let live = try await restoreLive(parent: f.root)
        let bytes = Data("unreadable existing database".utf8)
        try bytes.write(to: live.url.appendingPathComponent(OfflineRestore.mappingName))
        do { _ = try await live.owner.restore(preview, measurements: live.measurements.backupSource()); XCTFail("Current corruption bypassed") } catch {}
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), bytes)
    }
    func testRestoreLegacyIndependentBytesAndExplicitAbsence() async throws {
        for legacy in [true, false] {
            let f = try seed()
            if legacy { try Phase1Fixtures.journal.write(to: f.sources.measurements) }
            else { try FileManager.default.removeItem(at: f.sources.measurements) }
            let changed = Fixture(root: f.root, journal: f.journal, sources: f.sources,
                measurementSource: .init(url: f.sources.measurements, expectedBytes: legacy ? Phase1Fixtures.journal : nil), mappingBytes: f.mappingBytes)
            let backup = try await package(changed); defer { backup.files.cleanup() }
            let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
            let live = try await restoreLive(parent: f.root)
            _ = try await live.owner.restore(preview, measurements: live.measurements.backupSource())
            let url = live.url.appendingPathComponent(OfflineRestore.measurementName)
            let reopened = FileMeasurementStore(url: url)
            XCTAssertEqual(try reopened.load().count, legacy ? 3 : 0)
            XCTAssertEqual(try reopened.load().count, legacy ? 3 : 0)
            if legacy { XCTAssertEqual(try Data(contentsOf: url), Phase1Fixtures.journal) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        }
    }
    func testRestoreCoordinatesConcurrentMappingAndIndependentWriters() async throws {
        let f = try seed(), backup = try await package(f); defer { backup.files.cleanup() }
        let preview = try OfflineRestore.prepare(backup.files.urls[0]); defer { preview.cleanup() }
        let live = try await restoreLive(parent: f.root)
        let source = try live.measurements.backupSource()
        let ready = DispatchSemaphore(value: 0), attempt = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let writerWork: @Sendable () throws -> Bool = {
            let old = FileMeasurementStore(url: source.url); _ = try old.load()
            ready.signal(); attempt.wait()
            do { try old.save([]); return false } catch { return error is StorageError }
        }
        let writer = Task.detached { try writerWork() }
        await Self.waitFor(ready)
        let restore = Task {
            try await live.owner.restore(preview, measurements: source) {
                if $0 == .protected { entered.signal(); release.wait() }
            }
        }
        await Self.waitFor(entered)
        let queued = Task { () -> Bool in
            do { try await live.owner.run { return () }; return false } catch { return error is StorageError }
        }
        attempt.signal(); release.signal()
        _ = try await restore.value
        let rejectedMeasurement = try await writer.value, rejectedMapping = await queued.value
        XCTAssertTrue(rejectedMeasurement); XCTAssertTrue(rejectedMapping)
        XCTAssertEqual(try Data(contentsOf: source.url), f.measurementSource.expectedBytes)
        XCTAssertEqual(try Data(contentsOf: live.url.appendingPathComponent(OfflineRestore.mappingName)), f.mappingBytes)
    }

}
