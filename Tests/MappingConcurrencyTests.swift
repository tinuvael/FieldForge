import XCTest
import os
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Hooks run on the storage executor. Gates prove overlap without timing sleeps.
// The file is used only by the storage queue. Tests read its immutable URLs after
// barriers; the hook itself is synchronized and invoked without holding the lock.
private final class GatedMappingStore: MappingStore, @unchecked Sendable {
    let file: FileMappingStore
    private let hook = OSAllocatedUnfairLock<(@Sendable () throws -> Void)?>(initialState: nil)
    var beforeSave: (@Sendable () throws -> Void)? {
        get { hook.withLock { $0 } }
        set { hook.withLock { $0 = newValue } }
    }
    init(_ url: URL) { file = FileMappingStore(url: url) }
    func load() throws -> MappingJournal {
        XCTAssertFalse(Thread.isMainThread)
        return try file.load()
    }
    func save(_ journal: MappingJournal) throws {
        XCTAssertFalse(Thread.isMainThread)
        try beforeSave?()
        try file.save(journal)
    }
}

@MainActor final class MappingConcurrencyTests: XCTestCase {
    private func setup() async throws -> (URL, GatedMappingStore, MappingModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FieldForge-A4-\(UUID())")
        let store = GatedMappingStore(root.appendingPathComponent("mapping.json"))
        let owner = MappingStorageOwner()
        let initial = try await owner.open { store }
        let model = MappingModel(workflow: MappingWorkflow(snapshot: initial), storage: owner, photoStore: ManagedPhotoStore(root: root.appendingPathComponent("photos")), planStore: ManagedPlanStore(root: root.appendingPathComponent("plans")))
        let p = try await model.persist { try $0.createProject(name: "A4") }
        try await model.persist { try $0.requestContext(MappingContext(projectID: p)) }
        let h = try await model.persist { try $0.createHorizon(elevation: "100") }
        try await model.persist { try $0.requestContext(MappingContext(projectID: p, horizonID: h)) }
        let e = try await model.persist { try $0.createExcavation(name: "A", horizonIDs: [h]) }
        try await model.persist { try $0.requestContext(MappingContext(projectID: p, horizonID: h, excavationID: e)) }
        return (root, store, model)
    }

    func testPublishedWorkflowCannotWriteOutsideStorageOwner() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try Data(contentsOf: store.file.url), journal = model.workflow!.journal
        XCTAssertThrowsError(try model.performThrowing { _ = try $0.createProject(name: "bypass") })
        XCTAssertEqual(model.workflow!.journal, journal)
        XCTAssertEqual(try Data(contentsOf: store.file.url), bytes)
        let id = try await model.persist { try $0.createProject(name: "admitted") }
        XCTAssertEqual(model.workflow!.journal.projects.last?.id, id)
    }

    func testCancelledPhotoAfterPromotionCommitsAndRepeatedRetryKeepsOneOriginal() async throws {
        let (root, _, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        model.perform { $0.draft.picket = "6" }
        await model.saveDraft(id: model.workflow!.draft.id)
        let point = model.workflow!.journal.observations[0]
        let context = try model.workflow!.journal.photoContext(for: point.id)
        let files = try XCTUnwrap(model.photoStore), image = try P41PhotoTests().image(90)
        let promoted = expectation(description: "original promoted before journal commit")
        let gate = DispatchSemaphore(value: 0)
        files.checkpoint = { phase in
            if phase == .promotion {
                promoted.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success)
            }
        }
        let task = Task { await model.importPhoto(ReceivedPhoto(data: image, filename: "a5.jpg", source: .files,
            representation: "received bytes"), context: context) }
        await fulfillment(of: [promoted], timeout: 5)
        let operation = try XCTUnwrap(model.retainedPhotos.values.first?.operation)
        XCTAssertTrue(model.workflow!.journal.photos.isEmpty)
        XCTAssertEqual(try files.read(operation.attachment), image)
        task.cancel(); gate.signal(); await task.value
        files.checkpoint = nil
        await model.retryPhoto(operation); await model.retryPhoto(operation)
        XCTAssertNil(model.photoError)
        XCTAssertEqual(model.workflow!.journal.photos, [operation.photo])
        XCTAssertEqual(model.workflow!.journal.photoAttachments, [operation.attachment])
        XCTAssertEqual(try files.read(operation.attachment), image)
        XCTAssertTrue(try files.pending().isEmpty)
    }

    func testFIFOTransactionsRebaseStaleInputsWithoutLostUpdatesAndKeepExactPrevious() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = model.workflow!.snapshot, owner = model.storage
        let entered = expectation(description: "first write entered"), gate = DispatchSemaphore(value: 0)
        store.beforeSave = { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        let first = Task { try await owner.transaction(snapshot: snapshot) { try $0.createProject(name: "first") } }
        await fulfillment(of: [entered], timeout: 5)
        // No second write can enter this hook until the first completes.
        store.beforeSave = nil
        let second = Task { try await owner.transaction(snapshot: snapshot) { try $0.createProject(name: "second") } }
        gate.signal()
        let (a, _) = try await first.value, (b, _) = try await second.value
        XCTAssertEqual(Array(b.journal.projects.suffix(2).map(\.name)), ["first", "second"])
        let previous = try JSONDecoder().decode(MappingJournal.self, from: Data(contentsOf: store.file.backupURL))
        XCTAssertEqual(previous, a.journal)
        XCTAssertEqual(try Data(contentsOf: store.file.url), try encoded(b.journal))
        let reopened = try await owner.run { try FileMappingStore(url: store.file.url).load() }
        XCTAssertEqual(reopened, b.journal); XCTAssertEqual(reopened.schemaVersion, 8)
    }

    func testBusyRequestsAreExplicitCancellationReconcilesAndContextSwitchFollowsSave() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalContext = model.workflow!.context
        let other = try await model.persist { try $0.createExcavation(name: "B", horizonIDs: [$0.context.horizonID!]) }
        let horizon = try await model.persist { try $0.createHorizon(elevation: "200") }
        model.perform { $0.draft.picket = "1"; $0.draft.notes = "retained" }
        let draft = model.workflow!.draft, before = model.workflow!.journal
        let entered = expectation(description: "commit pending"), gate = DispatchSemaphore(value: 0)
        store.beforeSave = { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        let save = Task { await model.saveDraft(id: draft.id) }
        await fulfillment(of: [entered], timeout: 5)
        let state = model.savingState
        XCTAssertTrue(model.isSaving); XCTAssertEqual(model.workflow!.journal, before)
        let exportSnapshot = model.workflow!.journal
        let selection = MappingExportSelection(projectID: originalContext.projectID!, firstDay: Date(), lastDay: Date(), timeZoneID: "UTC")
        let export = try await Task.detached { try MappingCSVExport.prepare(journal: exportSnapshot, selection: selection) }.value
        XCTAssertEqual(export.pointCount, before.observations.count)
        for context in [MappingContext(projectID: originalContext.projectID, horizonID: originalContext.horizonID, excavationID: other),
                        MappingContext(projectID: originalContext.projectID, horizonID: horizon)] {
            do { try await model.persist { try $0.requestContext(context) }; XCTFail("Busy context accepted") } catch { }
        }
        await model.saveDraft(id: draft.id) // rapid duplicate: actionable busy response
        XCTAssertNotNil(model.error); XCTAssertEqual(model.savingState, state)
        model.perform { $0.draft.notes = "must be rejected" }
        XCTAssertEqual(model.workflow!.draft.notes, draft.notes)
        save.cancel() // cancellation cannot suppress reconciliation of an accepted commit
        gate.signal(); await save.value
        store.beforeSave = nil
        XCTAssertFalse(model.isSaving); XCTAssertNil(model.error)
        XCTAssertEqual(model.workflow!.journal.observations.map(\.id), [draft.id])
        XCTAssertEqual(model.workflow!.journal.observations[0].excavationID, originalContext.excavationID)
        XCTAssertEqual(exportSnapshot, before) // export requested during save uses the committed value
        let nextContext = MappingContext(projectID: originalContext.projectID, horizonID: originalContext.horizonID, excavationID: other)
        try await model.persist { try $0.requestContext(nextContext) }
        XCTAssertEqual(model.workflow!.context, nextContext)
        XCTAssertEqual(model.workflow!.journal.observations.count, 1)
        // A retry with the completed draft identity never saves the new empty draft.
        await model.saveDraft(id: draft.id)
        XCTAssertEqual(model.workflow!.journal.observations.count, 1)
    }

    func testFailedSaveRetainsDraftAndPreviousExternalChangesFailClosedThenSafeRetry() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        model.perform { $0.draft.picket = "2"; $0.draft.notes = "complete draft" }
        let before = model.workflow!.journal, draft = model.workflow!.draft
        let bytes = try Data(contentsOf: store.file.url), backup = try Data(contentsOf: store.file.backupURL)
        store.beforeSave = { throw StorageError.changedFile }
        await model.saveDraft(id: draft.id)
        XCTAssertEqual(model.workflow!.draft, draft); XCTAssertEqual(model.workflow!.journal, before)
        if case .failed = model.savingState {} else { XCTFail("Missing recoverable state") }
        XCTAssertEqual(try Data(contentsOf: store.file.backupURL), backup)
        store.beforeSave = nil
        let changed = bytes + Data(" ".utf8)
        try changed.write(to: store.file.url, options: .atomic)
        await model.saveDraft(id: draft.id)
        XCTAssertEqual(model.workflow!.draft, draft)
        XCTAssertEqual(try Data(contentsOf: store.file.url), changed)
        XCTAssertEqual(try Data(contentsOf: store.file.backupURL), backup)
        try bytes.write(to: store.file.url, options: .atomic) // only the test restores its own fixture
        await model.saveDraft(id: draft.id)
        XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.observations.map(\.id), [draft.id])
        XCTAssertEqual(try Data(contentsOf: store.file.backupURL), bytes)
    }

    func testRevisionRejectedWhilePendingThenCommitsAgainstLatestRevision() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        model.perform { $0.draft.picket = "3" }
        await model.saveDraft(id: model.workflow!.draft.id)
        var correction = try model.workflow!.correction(for: model.workflow!.journal.observations[0].id)
        correction.reason = "A4 correction"; correction.fields.notes = "corrected"
        let frozen = correction
        let entered = expectation(description: "pending metadata"), gate = DispatchSemaphore(value: 0)
        store.beforeSave = { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        let metadata = Task { try await model.persist { try $0.createProject(name: "pending") } }
        await fulfillment(of: [entered], timeout: 5)
        do { _ = try await model.persist { try $0.saveCorrection(frozen) }; XCTFail("Busy revision accepted") } catch { }
        XCTAssertTrue(model.workflow!.journal.revisions.isEmpty)
        gate.signal(); _ = try await metadata.value; store.beforeSave = nil
        _ = try await model.persist { try $0.saveCorrection(frozen) }
        XCTAssertEqual(model.workflow!.journal.revisions.count, 1)
        XCTAssertEqual(model.workflow!.journal.effectiveObservations[0].notes, "corrected")
    }

    func testCommandThrowAfterBufferedCommitLeavesDiskAndBackupUnchanged() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = model.workflow!.journal
        let bytes = try Data(contentsOf: store.file.url), backup = try Data(contentsOf: store.file.backupURL)
        do {
            try await model.persist { workflow in
                _ = try workflow.createProject(name: "must not escape")
                throw StorageError.invalidRecord
            }
            XCTFail("Failed command accepted")
        } catch { }
        XCTAssertEqual(model.workflow!.journal, journal)
        XCTAssertEqual(try Data(contentsOf: store.file.url), bytes)
        XCTAssertEqual(try Data(contentsOf: store.file.backupURL), backup)
        _ = try await model.persist { try $0.createProject(name: "retry") }
        XCTAssertEqual(model.workflow!.journal.projects.count, journal.projects.count + 1)
    }

    func testDXFBusyFailureMissingOriginalRecoveryAndRetryUseSameIdentity() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try XCTUnwrap(model.planStore), h = model.workflow!.context.horizonID!
        let data = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n11\n10\n21\n0\n")
        let id = UUID(), attachment = UUID(), importedAt = Date()
        let plan = try await model.storage.run {
            try files.stage(data: data, filename: "a4.dxf", horizonID: h, version: "1", units: .meters,
                crs: "unknown", axes: "unknown", id: id, attachmentID: attachment, importedAt: importedAt)
        }
        let repeated = try await model.storage.run {
            try files.stage(data: data, filename: "a4.dxf", horizonID: h, version: "1", units: .meters,
                crs: "unknown", axes: "unknown", id: id, attachmentID: attachment, importedAt: importedAt)
        }
        XCTAssertEqual(repeated, plan); XCTAssertEqual(try files.pending(), [plan])
        model.perform { $0.draft.picket = "4" }
        let entered = expectation(description: "save before plan"), gate = DispatchSemaphore(value: 0)
        store.beforeSave = { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        let save = Task { await model.saveDraft(id: model.workflow!.draft.id) }
        await fulfillment(of: [entered], timeout: 5)
        do { try await model.registerPlan(plan); XCTFail("Busy plan registration accepted") } catch { }
        XCTAssertTrue(model.workflow!.journal.plans.isEmpty)
        gate.signal(); await save.value
        store.beforeSave = { throw StorageError.changedFile }
        do { try await model.registerPlan(plan); XCTFail("Failed registration accepted") } catch { }
        XCTAssertEqual(try files.pending(), [plan]); XCTAssertEqual(try files.read(plan), data)
        store.beforeSave = nil
        try FileManager.default.removeItem(at: files.fileURL(plan)) // simulate incomplete byte preparation
        do { try await model.registerPlan(plan); XCTFail("Unavailable original referenced") } catch { }
        XCTAssertTrue(model.workflow!.journal.plans.isEmpty)
        do { try files.supply(Data("wrong".utf8), for: plan); XCTFail("Wrong replacement accepted") } catch { }
        try await model.storage.run { try files.supply(data, for: plan) }
        try await model.registerPlan(plan); try await model.registerPlan(plan)
        XCTAssertEqual(model.workflow!.journal.plans, [plan]); XCTAssertTrue(try files.pending().isEmpty)
        XCTAssertEqual(try files.read(plan), data)
    }

    func testPhotoImportLocksContextAndCancelledCallerStillPublishesFrozenPoint() async throws {
        let (root, _, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        model.perform { $0.draft.picket = "5" }
        await model.saveDraft(id: model.workflow!.draft.id)
        let point = model.workflow!.journal.observations[0]
        let context = try model.workflow!.journal.photoContext(for: point.id)
        let files = try XCTUnwrap(model.photoStore)
        let image = try P41PhotoTests().image(100)
        let entered = expectation(description: "photo intent persisted"), gate = DispatchSemaphore(value: 0)
        files.checkpoint = { phase in
            if phase == .intent { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        }
        let photo = Task { await model.importPhoto(ReceivedPhoto(data: image, filename: "original.jpg", source: .files,
            representation: "received bytes"), context: context) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(model.isSaving)
        do { try await model.persist { try $0.requestContext(MappingContext()) }; XCTFail("Photo context changed during write") } catch { }
        photo.cancel(); gate.signal(); await photo.value
        files.checkpoint = nil
        XCTAssertNil(model.photoError); XCTAssertEqual(model.workflow!.journal.photos.count, 1)
        let saved = model.workflow!.journal.photos[0]
        XCTAssertEqual(saved.context, context)
        XCTAssertEqual(try files.read(model.workflow!.journal.photoAttachments[0]), image)
        try await model.persist { try $0.requestContext(MappingContext()) }
        XCTAssertEqual(model.workflow!.journal.photos[0].context, context)
    }

    func testCoordinateSelectionRefusedDuringSaveThenPreservesXYAndZAcceptanceRules() async throws {
        let (root, store, model) = try await setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try XCTUnwrap(model.planStore), horizon = model.workflow!.context.horizonID!
        let data = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n30\n-20\n11\n10\n21\n0\n31\n20\n")
        let plan = try await model.storage.run {
            try files.stage(data: data, filename: "selection.dxf", horizonID: horizon, version: "1",
                units: .meters, crs: "mine grid", axes: "WCS XYZ")
        }
        try await model.registerPlan(plan)
        let request = try model.workflow!.planSelectionRequest(plan)
        let point = PlanPoint(x: 2.5, y: 1)
        let elevation = try XCTUnwrap(PlanElevationSnap.resolve(point, document: DXFDocument.parse(data), plan: plan).automatic)
        let before = model.workflow!.draft, journal = model.workflow!.journal
        let entered = expectation(description: "durable save pending"), gate = DispatchSemaphore(value: 0)
        store.beforeSave = { entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now() + 10), .success) }
        let save = Task { try await model.persist { try $0.createProject(name: "pending selection") } }
        await fulfillment(of: [entered], timeout: 5)
        let savingDraft = model.workflow!.draft, state = model.savingState
        XCTAssertTrue(model.isSaving)
        let busyMessage = "Дождитесь завершения сохранения и повторите действие."
        // MappingView's frozen request and the plan view's fallback share admission.
        XCTAssertThrowsError(try model.performThrowing { try $0.selectPlanPoint(point, request: request, elevation: elevation) }) {
            XCTAssertEqual($0.localizedDescription, busyMessage)
        }
        XCTAssertThrowsError(try model.performThrowing { try $0.selectPlanPoint(point, planID: plan.id, elevation: elevation) }) {
            XCTAssertEqual($0.localizedDescription, busyMessage)
        }
        model.perform { try $0.selectPlanPoint(point, request: request, elevation: elevation) }
        XCTAssertEqual(model.error, busyMessage)
        XCTAssertEqual(model.workflow!.draft, savingDraft)
        XCTAssertEqual(model.workflow!.journal, journal); XCTAssertEqual(model.savingState, state)
        gate.signal(); _ = try await save.value; store.beforeSave = nil
        XCTAssertEqual(model.workflow!.draft, before); XCTAssertNil(model.error)

        try model.performThrowing { try $0.selectPlanPoint(point, request: request, elevation: elevation) }
        XCTAssertEqual(model.workflow!.draft.x, "2.5"); XCTAssertEqual(model.workflow!.draft.y, "1")
        XCTAssertEqual(model.workflow!.draft.z, "-10"); XCTAssertEqual(model.workflow!.draft.zPlanGeometry, elevation)
        // No proposed Z retains manual input; explicit DXF Z acceptance replaces it.
        model.perform { $0.draft.z = "-12.125" }
        try model.performThrowing { try $0.selectPlanPoint(point, planID: plan.id) }
        XCTAssertEqual(model.workflow!.draft.z, "-12.125")
        XCTAssertEqual(model.workflow!.draft.zOrigin, .manualOverride); XCTAssertNil(model.workflow!.draft.zPlanGeometry)
        try model.performThrowing { try $0.selectPlanPoint(point, request: request, elevation: elevation) }
        XCTAssertEqual(model.workflow!.draft.z, "-10")
        XCTAssertEqual(model.workflow!.draft.zOrigin, .planGeometry); XCTAssertEqual(model.workflow!.draft.zPlanGeometry, elevation)
    }

    private func encoded(_ journal: MappingJournal) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(journal)
    }
}

/// Instrumentation only: no timing thresholds or sleep-based correctness assertions.
private final class MainQueueHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var last = DispatchTime.now().uptimeNanoseconds
    private(set) var count = 0
    private(set) var maximumGapMS = 0.0
    func tick() {
        XCTAssertTrue(Thread.isMainThread)
        lock.lock(); defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        maximumGapMS = max(maximumGapMS, Double(now - last) / 1_000_000)
        last = now; count += 1
    }
}

@MainActor final class MappingResponsivenessTests: XCTestCase {
    func testA4FocusedSaveResponsiveness() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIELD_FORGE_STORAGE_A4"] == "1", "Opt in to the two A4 fixture saves")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FieldForge-A4-responsiveness-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for size in [1_000, 5_000] {
            let fixture = try MappingStorageBenchmarkTests.fixture(size)
            let store = GatedMappingStore(root.appendingPathComponent("\(size).json")), owner = MappingStorageOwner()
            try await owner.run { _ = try store.load(); try store.save(fixture) }
            let workflow = try await owner.open { store }
            let model = MappingModel(workflow: MappingWorkflow(snapshot: workflow), storage: owner, photoStore: ManagedPhotoStore(root: root.appendingPathComponent("photos")))
            model.perform { $0.draft.picket = "9000"; $0.draft.notes = "A4 responsiveness" }
            let heartbeat = MainQueueHeartbeat(), timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(16))
            timer.setEventHandler { heartbeat.tick() }
            timer.resume()
            // A main-queue callback must run while the storage transaction is held.
            let probe = expectation(description: "MainActor runs while persistence is pending")
            let gate = DispatchSemaphore(value: 0)
            store.beforeSave = {
                DispatchQueue.main.async { probe.fulfill() }
                XCTAssertEqual(gate.wait(timeout: .now() + 10), .success)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let save = Task { await model.saveDraft(id: model.workflow!.draft.id) }
            await fulfillment(of: [probe], timeout: 5)
            XCTAssertTrue(model.isSaving)
            gate.signal(); await save.value
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            timer.cancel()
            XCTAssertNil(model.error); XCTAssertEqual(model.workflow!.journal.observations.count, size + 1)
            print("A4_RESPONSIVENESS,size=\(size),save_ms=\(elapsed),main_ticks=\(heartbeat.count),max_main_gap_ms=\(heartbeat.maximumGapMS)")
        }
    }
}
