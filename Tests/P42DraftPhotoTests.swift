import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class P42DraftPhotoTests: XCTestCase {
    func setup() throws -> (URL, FileMappingStore, MappingModel, ManagedPhotoStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (_, initial) = try P2MappingTests().configured()
        let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
        _ = try store.load(); try store.save(initial.journal); try store.save(initial.journal)
        let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
        return (root, store, MappingModel(workflow: try MappingWorkflow(store: store), photoStore: files), files)
    }
    func received(_ color: UInt8 = 100) throws -> ReceivedPhoto {
        ReceivedPhoto(data: try P41PhotoTests().image(color), filename: nil, source: .camera,
            representation: "camera UIImage encoded to JPEG by app; original encoded bytes unavailable")
    }
    @discardableResult func add(_ model: MappingModel, _ color: UInt8 = 100) async throws -> PhotoImportOperation {
        let session = try model.beginDraftPhotos()
        await model.receiveDraftPhoto(try received(color), session: session)
        model.endDraftPhotos(session)
        return try XCTUnwrap(model.workflow!.draft.photos.last)
    }
    func testContextParkingKeepsUnrelatedPendingSavedPointPhotoBytes() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "1"; let point = try model.workflow!.save()
        let image = try received()
        let operation = try files.makeOperation(data: image.data, filename: nil,
            context: model.workflow!.journal.photoContext(for: point.id), source: image.source, representation: image.representation)
        model.retainedPhotos[operation.id] = RetainedPhotoImport(operation: operation, data: image.data)
        model.workflow!.draft.notes = "Unfinished next point"
        let other = try model.workflow!.createProject(name: "Other")
        try model.workflow!.requestContext(MappingContext(projectID: other))
        model.perform { try $0.preserveAndSwitch() }
        XCTAssertEqual(model.retainedPhotos[operation.id]?.data, image.data)
        XCTAssertEqual(model.retainedPhotos[operation.id]?.operation, operation)
    }
    func testPhotoDraftSurvivesExcavationChangeAndParkedContextWithCaptureProvenance() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let originalContext = model.workflow!.context, id = model.workflow!.draft.id
        model.workflow!.draft.picket = "1+7"
        let operation = try await add(model)
        let nextExcavation = try model.workflow!.createExcavation(name: "Next", horizonIDs: [originalContext.horizonID!])
        let inFlight = try model.beginDraftPhotos()
        let beforeSelection = model.workflow!.draft
        try model.workflow!.requestContext(MappingContext(projectID: originalContext.projectID, horizonID: originalContext.horizonID, excavationID: nextExcavation))
        XCTAssertEqual(model.workflow!.draft, beforeSelection); XCTAssertNil(model.workflow!.pendingContext)
        await model.receiveDraftPhoto(try received(200), session: inFlight)
        model.endDraftPhotos(inFlight)
        XCTAssertEqual(model.workflow!.draft.photos.count, 2)
        let expected = model.workflow!.draft
        let other = try model.workflow!.createProject(name: "Other")
        try model.workflow!.requestContext(MappingContext(projectID: other))
        model.perform { try $0.preserveAndSwitch() }
        XCTAssertNotNil(model.retainedPhotos[operation.id])
        model.perform { try $0.requestContext(MappingContext(projectID: originalContext.projectID, horizonID: originalContext.horizonID)) }
        XCTAssertEqual(model.workflow!.draft, expected)
        await model.saveDraft(id: id)
        XCTAssertNil(model.error); XCTAssertTrue(model.success)
        XCTAssertEqual(model.workflow!.journal.observations.first?.excavationID, nextExcavation)
        XCTAssertEqual(model.workflow!.journal.photos.first, operation.photo)
        XCTAssertEqual(operation.photo.context.excavationID, originalContext.excavationID)
        XCTAssertEqual(try files.read(operation.attachment), try received().data)
        try model.workflow!.journal.validate()
    }
    func testThreePhotosBeforeFirstSaveOneAtomicGraphAndRelaunchUnknownLocation() async throws {
        let (root, store, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let before = model.workflow!.journal, context = model.workflow!.context, id = model.workflow!.draft.id
        model.workflow!.draft.z = "" // no XY, no Z, no DXF
        for color in [UInt8(30), 100, 200] { try await add(model, color) }
        let operations = model.workflow!.draft.photos
        XCTAssertEqual(Set(operations.map { $0.attachment.sha256 }).count, 3)
        XCTAssertEqual(model.workflow!.journal, before); XCTAssertTrue(try files.pending().isEmpty)
        XCTAssertEqual(model.retainedPhotos.count, 3)
        // Invalid point never writes images or publishes a partial point.
        await model.saveDraft(id: id)
        XCTAssertEqual(model.workflow!.journal, before); XCTAssertEqual(model.retainedPhotos.count, 3)
        XCTAssertTrue(try files.pending().isEmpty)
        model.workflow!.draft.picket = "5"
        await model.saveDraft(id: id)
        XCTAssertTrue(model.success); XCTAssertNil(model.error)
        let reopened = try MappingWorkflow(store: FileMappingStore(url: store.url))
        XCTAssertEqual(reopened.journal.photos, operations.map(\.photo))
        XCTAssertEqual(reopened.journal.photoAttachments, operations.map(\.attachment))
        XCTAssertEqual(reopened.journal.observations.map(\.id), [id])
        XCTAssertNil(reopened.journal.observations[0].coordinates?.x); XCTAssertNil(reopened.journal.observations[0].coordinates?.y)
        XCTAssertNil(reopened.journal.observations[0].coordinates?.z)
        XCTAssertTrue(reopened.journal.revisions.isEmpty); XCTAssertEqual(reopened.journal.measurements, before.measurements)
        for operation in operations { XCTAssertEqual(try files.read(operation.attachment), try received(operation == operations[0] ? 30 : operation == operations[1] ? 100 : 200).data) }
        XCTAssertTrue(model.retainedPhotos.isEmpty); XCTAssertTrue(try files.pending().isEmpty)
        XCTAssertEqual(model.workflow!.context, context); XCTAssertFalse(model.workflow!.draft.hasChanges)
        XCTAssertEqual(model.workflow!.draft.z, "393"); XCTAssertNotEqual(model.workflow!.draft.id, id)
        await model.saveDraft(id: id) // A queued retry after commit cannot publish the next point.
        XCTAssertEqual(model.workflow!.journal.observations.count, 1)
    }
    func testActualStagingFailureCameraOnlyBytesAndOrdinaryRetrySameIdentities() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "5"; model.workflow!.draft.notes = "retain everything"
        let op = try await add(model); let before = model.workflow!.draft, graph = model.workflow!.journal
        files.checkpoint = { phase in
            if phase == .intent { try FileManager.default.createDirectory(at: files.stagingURL(op), withIntermediateDirectories: false) }
        }
        await model.saveDraft(id: before.id)
        XCTAssertNotNil(model.error); XCTAssertEqual(model.workflow!.draft, before); XCTAssertEqual(model.workflow!.journal, graph)
        XCTAssertEqual(model.retainedPhotos[op.id]?.data, try received().data)
        XCTAssertNil(op.attachment.originalFilename); XCTAssertEqual(try files.pending(), [op])
        files.checkpoint = nil; try FileManager.default.removeItem(at: files.stagingURL(op))
        await model.saveDraft(id: before.id)
        XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(try files.read(op.attachment), try received().data); XCTAssertTrue(model.retainedPhotos.isEmpty)
        await model.saveDraft(id: before.id)
        XCTAssertEqual(model.workflow!.journal.observations.count, 1)
    }
    func testActualJournalBackupFailureRetainsWholeDraftAndDurableOriginalRetry() async throws {
        let (root, store, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "5"; try model.workflow!.draft.addMeasurement(ManualOrientationInput(dipAngleText: "41.123456789", dipDirectionText: "359.25", reference: .magneticNorth).observation(notes: "Original"))
        let op = try await add(model), before = model.workflow!.draft, graph = model.workflow!.journal
        try FileManager.default.removeItem(at: store.backupURL)
        try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: false)
        await model.saveDraft(id: before.id)
        XCTAssertEqual(model.workflow!.journal, graph); XCTAssertEqual(model.workflow!.draft, before)
        XCTAssertEqual(try FileMappingStore(url: store.url).load(), graph)
        XCTAssertTrue(model.retainedPhotos.isEmpty); XCTAssertEqual(try files.read(op.attachment), try received().data)
        let restarted = MappingModel(workflow: try MappingWorkflow(store: FileMappingStore(url: store.url)), photoStore: files)
        await restarted.retryPhoto(op)
        XCTAssertEqual(restarted.workflow!.journal, graph) // Never invent a point from a disk intent.
        XCTAssertFalse(restarted.workflow!.draft.hasChanges)
        try FileManager.default.removeItem(at: store.backupURL)
        await model.saveDraft(id: before.id)
        XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        XCTAssertEqual(model.workflow!.journal.measurements, before.measurements)
        XCTAssertTrue(model.workflow!.journal.revisions.isEmpty)
    }
    func testPhotosAloneContextCancelDiscardAndLateCompletionCannotResurrect() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let original = model.workflow!.context
        let other = try model.workflow!.createProject(name: "Other")
        let session = try model.beginDraftPhotos()
        await model.receiveDraftPhoto(try received(), session: session)
        model.endDraftPhotos(session)
        XCTAssertTrue(model.workflow!.draft.hasChanges)
        let before = model.workflow!.draft
        try model.workflow!.requestContext(MappingContext(projectID: other))
        XCTAssertEqual(model.workflow!.context, original)
        model.workflow!.cancelContextChange(); XCTAssertEqual(model.workflow!.draft, before)
        // Picker still active: Save is explicitly refused, even with a valid picket.
        let pending = try model.beginDraftPhotos()
        model.workflow!.draft.picket = "5"; await model.saveDraft(id: before.id)
        XCTAssertTrue(model.workflow!.journal.observations.isEmpty)
        try model.workflow!.requestContext(MappingContext(projectID: other))
        model.perform { try $0.confirmDiscard() }
        let next = model.workflow!.draft
        await model.receiveDraftPhoto(try received(200), session: pending); model.endDraftPhotos(pending)
        XCTAssertEqual(model.workflow!.draft, next); XCTAssertTrue(model.retainedPhotos.isEmpty)
        XCTAssertTrue(model.workflow!.journal.photos.isEmpty); XCTAssertTrue(try files.pending().isEmpty)
        XCTAssertEqual(model.workflow!.context.projectID, other)
    }
    func testTwoSuccessivePointsUnknownCaptureLocationSurvivesXYEditAndStaleSession() async throws {
        let (root, _, model, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let context = model.workflow!.context
        let session = try model.beginDraftPhotos()
        await model.receiveDraftPhoto(try received(30), session: session); model.endDraftPhotos(session)
        let first = model.workflow!.draft.photos[0]
        model.workflow!.draft.picket = "5"; model.workflow!.draft.x = "123.123456789"; model.workflow!.draft.y = "456"
        model.workflow!.draft.observedAtOverride = Date(timeIntervalSince1970: 100)
        model.workflow!.draft.notes = "A"; model.workflow!.draft.startPicket = "5"; model.workflow!.draft.endPicket = "10"
        await model.saveDraft(id: session.context.pointID)
        await model.receiveDraftPhoto(try received(100), session: session)
        XCTAssertTrue(model.workflow!.draft.photos.isEmpty); XCTAssertFalse(model.workflow!.draft.hasChanges)
        XCTAssertNil(model.workflow!.draft.observedAtOverride); XCTAssertEqual(model.workflow!.draft.x, "")
        let second = try await add(model, 200)
        model.workflow!.draft.picket = "10"; await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertEqual(model.workflow!.context, context)
        XCTAssertEqual(model.workflow!.journal.photos, [first.photo, second.photo])
        XCTAssertNotEqual(first.photo.context.pointID, second.photo.context.pointID)
        XCTAssertEqual(first.photo.context.locationBasis, .unknownBeforeFirstSave)
        XCTAssertEqual(model.workflow!.journal.observations[0].coordinates?.x, 123.123456789)
        XCTAssertEqual(model.workflow!.journal.observations[1].coordinates?.zOrigin, .horizonDefault)
        XCTAssertEqual(model.workflow!.journal.observations[1].notes, "")
        XCTAssertTrue(model.workflow!.journal.revisions.isEmpty)
    }
    func testRemovalAndDiscardAfterFailedSaveNeverDeleteStagedOrSavedOriginals() async throws {
        let (root, store, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "5"; let saved = try await add(model)
        await model.saveDraft(id: model.workflow!.draft.id)
        let savedGraph = model.workflow!.journal
        model.workflow!.draft.picket = "10"; let draft = try await add(model, 200)
        try FileManager.default.removeItem(at: store.backupURL)
        try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: false)
        await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertEqual(try files.read(draft.attachment), try received(200).data)
        model.removeDraftPhoto(draft.id, draftID: model.workflow!.draft.id)
        XCTAssertEqual(try files.pending(), [draft]); XCTAssertEqual(model.workflow!.journal, savedGraph)
        XCTAssertEqual(try files.read(saved.attachment), try received().data)
        await model.retryPhoto(draft); XCTAssertEqual(model.workflow!.journal, savedGraph)
        XCTAssertEqual(try files.read(draft.attachment), try received(200).data)
    }
    func testThumbnailFailureAfterAtomicCommitIsSavedAndRetryDoesNotDuplicate() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "5"; let op = try await add(model)
        files.checkpoint = { if $0 == .thumbnail { throw P41PhotoTests.Failure.injected } }
        await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertTrue(model.success); XCTAssertNil(model.error); XCTAssertNotNil(model.photoError)
        XCTAssertFalse(model.workflow!.draft.hasChanges); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
        files.checkpoint = nil; await model.retryPhoto(op); await model.retryPhoto(op)
        XCTAssertEqual(model.workflow!.journal.photos, [op.photo]); XCTAssertEqual(model.workflow!.journal.observations.count, 1)
        XCTAssertTrue(try files.pending().isEmpty)
    }
    func testCancelledPickerLeavesCleanDraftAndRequiredLocationContractFailsClosed() throws {
        let (root, _, model, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let session = try model.beginDraftPhotos(); XCTAssertTrue(model.workflow!.draft.hasChanges)
        model.endDraftPhotos(session); XCTAssertFalse(model.workflow!.draft.hasChanges)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session.context)) as? [String: Any])
        json.removeValue(forKey: "locationBasis")
        XCTAssertThrowsError(try JSONDecoder().decode(PhotoContext.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testIntentCreationFailureCameraRetryAndSavedPhotosStayInTheirProject() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let originalContext = model.workflow!.context
        model.workflow!.draft.picket = "5"; let first = try await add(model)
        try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
        let blocked = files.root.appendingPathComponent("operations")
        try Data("blocked directory".utf8).write(to: blocked)
        await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertEqual(model.retainedPhotos[first.id]?.data, try received().data)
        XCTAssertFalse(files.hasIntent(first)); XCTAssertTrue(model.workflow!.journal.photos.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.photos, [first.photo])
        let p = try model.workflow!.createProject(name: "B")
        try model.workflow!.requestContext(MappingContext(projectID: p))
        let h = try model.workflow!.createHorizon(elevation: "-120")
        try model.workflow!.requestContext(MappingContext(projectID: p, horizonID: h))
        let e = try model.workflow!.createExcavation(name: "B", horizonIDs: [h])
        try model.workflow!.requestContext(MappingContext(projectID: p, horizonID: h, excavationID: e))
        XCTAssertTrue(model.workflow!.observations.isEmpty)
        model.workflow!.draft.picket = "5"; let second = try await add(model, 200)
        await model.saveDraft(id: model.workflow!.draft.id)
        XCTAssertEqual(model.workflow!.observations.map(\.id), [second.photo.context.pointID])
        XCTAssertEqual(second.photo.context.projectID, p)
        try model.workflow!.requestContext(originalContext)
        XCTAssertEqual(model.workflow!.observations.map(\.id), [first.photo.context.pointID])
        XCTAssertEqual(model.workflow!.journal.photos, [first.photo, second.photo])
        XCTAssertEqual(try files.read(first.attachment), try received().data)
    }
    func testSaveLocksContextAndDetectsConcurrentFieldEditWithoutLosingPhoto() async throws {
        let (root, _, model, files) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        model.workflow!.draft.picket = "5"; let op = try await add(model)
        let id = model.workflow!.draft.id, graph = model.workflow!.journal
        let intent = expectation(description: "intent on disk")
        let resume = DispatchSemaphore(value: 0)
        files.checkpoint = { phase in
            if phase == .intent { intent.fulfill(); _ = resume.wait(timeout: .now() + 10) }
        }
        let save = Task { await model.saveDraft(id: id) }
        await fulfillment(of: [intent], timeout: 5)
        XCTAssertTrue(model.workflow!.draft.saving)
        XCTAssertThrowsError(try model.workflow!.requestContext(MappingContext()))
        model.workflow!.draft.notes = "edit from another editor while awaiting disk"
        resume.signal(); await save.value
        XCTAssertEqual(model.workflow!.journal, graph); XCTAssertNotNil(model.error)
        XCTAssertEqual(model.workflow!.draft.notes, "edit from another editor while awaiting disk")
        XCTAssertEqual(model.workflow!.draft.photos, [op]); XCTAssertEqual(try files.read(op.attachment), try received().data)
        files.checkpoint = nil; await model.saveDraft(id: id)
        XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.photos, [op.photo])
    }
}
