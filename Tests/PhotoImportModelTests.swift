import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class PhotoImportModelTests: XCTestCase {
    func setup() throws -> (URL, MappingTests.MemoryStore, MappingModel, ManagedPhotoStore, PhotoContext, ReceivedPhoto) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (store, workflow, point) = try P41PhotoTests().seed()
        let files = ManagedPhotoStore(root: root)
        let model = MappingModel(workflow: workflow, photoStore: files)
        let photo = ReceivedPhoto(data: try P41PhotoTests().image(180), filename: nil, source: .camera,
            representation: "camera UIImage encoded to JPEG by app; original encoded bytes unavailable")
        return (root, store, model, files, try workflow.journal.photoContext(for: point.id), photo)
    }
    func testCameraInMemoryOnlyIntentSavedStagingWriteFailsLiveRetryUsesSameBytesAndUUIDs() async throws {
        let (root, store, model, files, context, photo) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        // Actual filesystem failure at the staging destination, after intent persistence.
        files.checkpoint = { phase in
            if phase == .intent {
                let operation = try XCTUnwrap(files.pending().first)
                try FileManager.default.createDirectory(at: files.stagingURL(operation), withIntermediateDirectories: false)
            }
        }
        await model.importPhoto(photo, context: context)
        let op = try XCTUnwrap(model.pendingPhotos.first)
        XCTAssertEqual(try files.pending(), [op]); XCTAssertEqual(op.photo.context, context)
        XCTAssertNil(op.attachment.originalFilename); XCTAssertEqual(op.photo.source, .camera)
        XCTAssertEqual(model.retainedPhotos[op.id]?.data, photo.data)
        XCTAssertTrue(model.workflow!.journal.photos.isEmpty); XCTAssertTrue(model.workflow!.journal.photoAttachments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.originalURL(op.attachment).path))
        XCTAssertTrue(model.photoError!.contains("без повторной съёмки"))
        // A new process has no memory fallback and must not claim recovery of unwritten bytes.
        let restarted = MappingModel(workflow: try MappingWorkflow(store: store), photoStore: files)
        await restarted.retryPhoto(op)
        XCTAssertTrue(restarted.workflow!.journal.photos.isEmpty)
        XCTAssertTrue(restarted.photoError!.contains("после перезапуска невозможно"))
        files.checkpoint = nil
        try FileManager.default.removeItem(at: files.stagingURL(op))
        try await model.persist { workflow in
            var correction = try workflow.correction(for: context.pointID)
            correction.fields.x = "123"; correction.reason = "Survey correction while import pending"
            try workflow.saveCorrection(correction)
            let project = try workflow.createProject(name: "Other project")
            try workflow.requestContext(MappingContext(projectID: project))
        }
        await model.retryPhoto(op) // Normal UI action; no external file or second shutter.
        XCTAssertNil(model.photoError)
        XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(model.workflow!.journal.photoAttachments, [op.attachment])
        XCTAssertEqual(try files.read(op.attachment), photo.data)
        XCTAssertEqual(model.workflow!.journal.photos[0].context, context)
        XCTAssertTrue(model.retainedPhotos.isEmpty); XCTAssertTrue(model.pendingPhotos.isEmpty)
        await model.retryPhoto(op) // Queued repeat after successful commit/cleanup is a verified no-op.
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos.count, 1)
        XCTAssertEqual(model.workflow!.journal.photoAttachments.count, 1)
        XCTAssertTrue(model.retainedPhotos.isEmpty); XCTAssertTrue(try files.pending().isEmpty)
    }
    func testIntentCreationFailureRetainsCameraBytesAndContextForNormalLiveRetry() async throws {
        let (root, _, model, files, context, photo) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("operations")
        try Data("occupied path".utf8).write(to: blocked)
        await model.importPhoto(photo, context: context)
        let op = try XCTUnwrap(model.pendingPhotos.first)
        XCTAssertEqual(model.retainedPhotos[op.id]?.data, photo.data)
        XCTAssertEqual(op.photo.context, context); XCTAssertFalse(files.hasIntent(op))
        XCTAssertTrue(model.workflow!.journal.photos.isEmpty)
        XCTAssertTrue(model.photoError!.contains("завершение приложения потеряет"))
        try FileManager.default.removeItem(at: blocked)
        await model.retryPhoto(op)
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(try files.read(op.attachment), photo.data)
        XCTAssertTrue(model.pendingPhotos.isEmpty); XCTAssertTrue(model.retainedPhotos.isEmpty)
    }
    func testJournalWriteFailureReleasesVolatileBytesOnlyAfterVerifiedOriginalAndRestartsWithoutDuplicates() async throws {
        let (root, store, model, files, context, photo) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = model.workflow!.journal; store.fail = true
        await model.importPhoto(photo, context: context)
        let op = try XCTUnwrap(model.pendingPhotos.first)
        XCTAssertEqual(model.workflow!.journal, before)
        XCTAssertEqual(model.retainedPhotos[op.id]?.data, photo.data) // A4 retains live bytes until journal commit.
        XCTAssertEqual(try files.read(op.attachment), photo.data); XCTAssertEqual(try files.pending(), [op])
        store.fail = false
        let restarted = MappingModel(workflow: try MappingWorkflow(store: store), photoStore: ManagedPhotoStore(root: root))
        await restarted.retryPhoto(op)
        XCTAssertNil(restarted.photoError); XCTAssertEqual(restarted.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(restarted.workflow!.journal.observations, before.observations)
        XCTAssertEqual(restarted.workflow!.journal.measurements, before.measurements)
        XCTAssertEqual(restarted.workflow!.journal.revisions, before.revisions)
        await restarted.retryPhoto(op)
        XCTAssertNil(restarted.photoError); XCTAssertEqual(restarted.workflow!.journal.photos.count, 1)
        XCTAssertTrue(restarted.pendingPhotos.isEmpty); XCTAssertTrue(restarted.retainedPhotos.isEmpty)
    }
    func testBusyWriterStillRetainsReceivedCameraImageForNormalRetry() async throws {
        let (root, _, model, files, context, photo) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        model.photoBusy = true
        await model.importPhoto(photo, context: context)
        let op = try XCTUnwrap(model.pendingPhotos.first)
        XCTAssertEqual(model.retainedPhotos[op.id]?.data, photo.data)
        XCTAssertFalse(files.hasIntent(op)); XCTAssertTrue(model.workflow!.journal.photos.isEmpty)
        model.photoBusy = false
        await model.retryPhoto(op)
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(try files.read(op.attachment), photo.data)
        XCTAssertTrue(model.retainedPhotos.isEmpty); XCTAssertTrue(model.pendingPhotos.isEmpty)
    }
    func testThumbnailFailureAfterCommitRetryAndSuccessfulImportReleaseAllVolatileData() async throws {
        let (root, _, model, files, context, photo) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        files.checkpoint = { if $0 == .thumbnail { throw P41PhotoTests.Failure.injected } }
        await model.importPhoto(photo, context: context)
        let op = try XCTUnwrap(model.pendingPhotos.first)
        XCTAssertEqual(model.workflow!.journal.photos, [op.photo]); XCTAssertTrue(model.retainedPhotos.isEmpty)
        files.checkpoint = nil
        await model.retryPhoto(op)
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertTrue(model.pendingPhotos.isEmpty); XCTAssertTrue(model.retainedPhotos.isEmpty)
        await model.importPhoto(photo, context: context) // Uninterrupted success through importPhoto itself.
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos.count, 2)
        XCTAssertTrue(model.pendingPhotos.isEmpty); XCTAssertTrue(model.retainedPhotos.isEmpty)
    }
}
