import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingImportLedgerTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let journal: MappingJournal
        let point: MappingObservation
        var url: URL { root.appendingPathComponent(OfflineRestore.mappingName) }
        var previous: URL { url.appendingPathExtension("previous") }

        func open() async throws -> (MappingStorageOwner, MappingWorkflow.Snapshot) {
            let owner = MappingStorageOwner()
            let url = url
            return (owner, try await owner.open { FileMappingStore(url: url) })
        }

        func persisted() throws -> MappingJournal { try FileMappingStore(url: url).load() }
    }

    private enum Interruption: Error { case stopped }

    private let source = MappingImportSource(kind: .exchange, documentID: "workbook-A", bytes: Data("reviewed version".utf8))
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000.125)

    private func fixture(rich: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let (_, seeded, point) = try P33RevisionTests().seed(includeHistoricalJ5: rich)
        var workflow = seeded
        if rich {
            var edit = try workflow.correction(for: point.id)
            edit.reason = "Original controlled correction"
            edit.fields.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair),
                lower: 35, upper: 45, finalValue: nil, assessedAt: now)
            edit.fields.regulatory.wallAlteration = .slightlyWeathered
            try workflow.saveCorrection(edit, now: now)
            let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
            // Start with an accepted attachment so this fixture tests durable links
            // independently of the host's image type registry.
            let data = try P41PhotoTests().image()
            let attachment = PhotoAttachment(id: UUID(), originalFilename: "field.jpg", sha256: ManagedPhotoStore.digest(data),
                byteCount: data.count, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1,
                orientation: 1, representation: "Exact received original")
            let photo = PhotoObservation(id: UUID(), attachmentID: attachment.id, context: try workflow.journal.photoContext(for: point.id),
                source: .files, importedAt: now, capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown",
                metadata: .init(name: "Original"))
            let operation = PhotoImportOperation(version: 2, photo: photo, attachment: attachment)
            try files.stage(data, for: operation)
            try files.promote(operation)
            try workflow.registerPhoto(operation)
            try files.complete(operation)
            try workflow.correctPhoto(photo.id, baselineRevisionID: nil, metadata: .init(name: "Field caption"), reason: "Original photo history")
        }
        let fixture = Fixture(root: root, journal: workflow.journal, point: point)
        try FileMappingStore(url: fixture.url).save(fixture.journal)
        return fixture
    }

    private func update(_ snapshot: MappingWorkflow.Snapshot, point: MappingObservation,
                        baseline: MappingImportBaseline? = nil, notes: String = "Reviewed correction",
                        source: MappingImportSource? = nil) throws -> (MappingImportOperation, MappingObservation) {
        let workflow = MappingWorkflow(snapshot: snapshot)
        let target = MappingImportTarget(point)
        var edit = try workflow.correction(for: point.id)
        edit.fields.notes = notes
        edit.reason = "Confirmed source row"
        let proposal = try edit.snapshot(now: now)
        let operation = try MappingImportOperation(source: source ?? self.source, sourceRecordID: point.id.uuidString,
            target: target, kind: .update, baseline: try baseline ?? .capture(target: target, in: snapshot.committed),
            proposal: proposal, correction: .init(date: now, author: "Engineer", reason: edit.reason))
        return (operation, proposal)
    }

    private func newPoint(_ snapshot: MappingWorkflow.Snapshot) throws -> MappingObservation {
        var workflow = MappingWorkflow(snapshot: snapshot)
        workflow.draft = MappingDraft()
        workflow.draft.picket = "17.123456789"
        return try workflow.draftRecord(now: now)
    }

    private func expect(_ outcome: MappingImportOutcome, on owner: MappingStorageOwner,
                        _ operation: MappingImportOperation, _ proposal: MappingObservation?,
                        source: MappingImportSource? = nil) async throws {
        let result = try await owner.applyImport(operation, source: source ?? self.source, proposal: proposal)
        XCTAssertEqual(result, outcome)
    }

    func testCreateAppliesOnceAcrossReopenAndBindsSourceRowAcrossWorkbookVersions() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let proposal = try newPoint(snapshot)
        let op = try MappingImportOperation(source: source, sourceRecordID: "client-1",
            target: .init(proposal), kind: .create, proposal: proposal)
        try await expect(.applied, on: owner, op, proposal)
        let committed = try fixture.persisted()
        XCTAssertEqual(committed.observations, fixture.journal.observations + [proposal])
        XCTAssertEqual(committed.importLedger?[op.id]?.outcome, .applied)
        XCTAssertTrue(committed.revisions.isEmpty)
        let previous = try FileMappingStore(url: fixture.previous).load()
        XCTAssertEqual(previous.importLedger?[op.id]?.outcome, .pending)
        XCTAssertEqual(previous.observations, fixture.journal.observations)

        let (reopened, opened) = try await fixture.open()
        let bytes = try Data(contentsOf: fixture.url)
        try await expect(.applied, on: reopened, op, proposal)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        let amended = MappingImportSource(kind: .exchange, documentID: source.documentID, bytes: Data("edited".utf8))
        let anotherPoint = try newPoint(opened)
        let duplicate = try MappingImportOperation(source: amended, sourceRecordID: op.sourceRecordID,
            target: .init(anotherPoint), kind: .create, proposal: anotherPoint)
        try await expect(.rejected(.duplicateSourceRecord(operationID: op.id)), on: reopened, duplicate, anotherPoint, source: amended)
        let disk = try fixture.persisted()
        XCTAssertEqual(disk.observations, committed.observations)
        XCTAssertEqual(disk.importLedger?[duplicate.id]?.outcome, .rejected(.duplicateSourceRecord(operationID: op.id)))
    }

    func testUpdateAndReceiptCommitTogetherAndRetryPreservesRichEvidence() async throws {
        let fixture = try fixture(rich: true)
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        let files = ManagedPhotoStore(root: fixture.root.appendingPathComponent("photos"))
        let attachment = try XCTUnwrap(fixture.journal.photoAttachments.first)
        let image = try files.read(attachment)
        do {
            _ = try await owner.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterCommit { throw Interruption.stopped }
            }
            XCTFail("Expected interruption after durable commit")
        } catch Interruption.stopped {}

        let disk = try fixture.persisted()
        let previousRevision = try XCTUnwrap(fixture.journal.revisions.last)
        let applied = try XCTUnwrap(disk.revisions.last)
        XCTAssertEqual(disk.revisions, fixture.journal.revisions + [applied])
        XCTAssertEqual(applied.id, op.id)
        XCTAssertEqual(applied.version, 3)
        XCTAssertEqual(applied.previousRevisionID, previousRevision.id)
        XCTAssertEqual(applied.snapshot, proposal)
        XCTAssertEqual(disk.importLedger?[op.id]?.outcome, .applied)
        XCTAssertEqual(disk.observations, fixture.journal.observations)
        XCTAssertEqual(disk.measurements, fixture.journal.measurements)
        XCTAssertEqual(disk.photos, fixture.journal.photos)
        XCTAssertEqual(disk.photoAttachments, fixture.journal.photoAttachments)
        XCTAssertEqual(disk.photoRevisions, fixture.journal.photoRevisions)
        XCTAssertEqual(disk.photos.first?.context, fixture.journal.photos.first?.context)
        XCTAssertEqual(try files.read(attachment), image)
        XCTAssertEqual(applied.snapshot.ratings, previousRevision.snapshot.ratings)
        XCTAssertNotNil(applied.snapshot.ratings?.bartonQ)
        XCTAssertNotNil(applied.snapshot.ratings?.rmr89)
        XCTAssertNotNil(applied.snapshot.ratings?.gsi)
        XCTAssertNotNil(applied.snapshot.ratings?.regulatory)
        XCTAssertEqual(applied.snapshot.geology?.tectonicStructures, previousRevision.snapshot.geology?.tectonicStructures)
        let j5 = try XCTUnwrap(previousRevision.snapshot.geology?.jointSets.first { $0.identifier == .J5 })
        XCTAssertEqual(applied.snapshot.geology?.jointSets.first { $0.identifier == .J5 }, j5)
        XCTAssertEqual(j5.measurementIDs, fixture.point.measurementIDs)

        let (reopened, opened) = try await fixture.open()
        let recovery = try await reopened.importRecovery()
        XCTAssertTrue(recovery.isEmpty)
        try await expect(.applied, on: reopened, op, proposal)
        let duplicate = try MappingImportOperation(source: source, sourceRecordID: op.sourceRecordID,
            target: op.target, kind: .update, baseline: op.baseline, proposal: proposal, correction: op.correction)
        try await expect(.rejected(.duplicateSourceRecord(operationID: op.id)), on: reopened, duplicate, proposal)
        XCTAssertEqual(try fixture.persisted().revisions, disk.revisions)

        _ = try await reopened.transaction(snapshot: opened) { workflow in
            var edit = try workflow.correction(for: op.target.observationID)
            edit.reason = "Later field correction"
            edit.fields.notes = "Newest field values"
            return try workflow.saveCorrection(edit)
        }
        let (laterOwner, _) = try await fixture.open()
        try await expect(.applied, on: laterOwner, op, proposal)
        XCTAssertEqual(try fixture.persisted().history(for: fixture.point.id).map(\.version), [2, 3, 4])
    }

    func testStalePendingIsReconciledAgainstNewFieldRevisionAfterRestart() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        do {
            _ = try await owner.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterIntent { throw Interruption.stopped }
            }
            XCTFail("Expected pending operation")
        } catch Interruption.stopped {}
        let (_, fieldEdit) = try await owner.transaction(snapshot: snapshot) { workflow in
            var edit = try workflow.correction(for: op.target.observationID)
            edit.reason = "New field evidence"
            edit.fields.notes = "Field edit after preview"
            return try workflow.saveCorrection(edit)
        }

        let (reopened, _) = try await fixture.open()
        let conflict = MappingImportConflict.revisionChanged(currentID: fieldEdit.id, version: 2)
        let recovery = try await reopened.importRecovery()
        XCTAssertEqual(recovery, [.init(operation: op, conflict: conflict)])
        XCTAssertEqual(try fixture.persisted().importLedger?[op.id]?.outcome, .pending)
        try await expect(.rejected(conflict), on: reopened, op, proposal)
        let disk = try fixture.persisted()
        XCTAssertEqual(disk.importLedger?[op.id]?.outcome, .rejected(conflict))
        XCTAssertEqual(disk.revisions, [fieldEdit])
        XCTAssertEqual(disk.observations, fixture.journal.observations)
    }

    func testSameRevisionWithDifferentSnapshotAndWrongOwnerAreRejected() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        var different = fixture.journal
        different.observations[0].ratings = nil
        let baseline = try MappingImportBaseline.capture(target: .init(fixture.point), in: MappingCommittedSnapshot(different))
        let (op, proposal) = try update(snapshot, point: fixture.point, baseline: baseline)
        try await expect(.rejected(.observationChanged), on: owner, op, proposal)

        let new = try newPoint(snapshot)
        let wrongTarget = try MappingImportOperation(source: source, sourceRecordID: "wrong owner", target: .init(fixture.point),
            kind: .update, baseline: .capture(target: .init(fixture.point), in: snapshot.committed),
            proposal: new, correction: op.correction)
        try await expect(.rejected(.ownershipChanged), on: owner, wrongTarget, new)
        let disk = try fixture.persisted()
        XCTAssertEqual(disk.observations, fixture.journal.observations)
        XCTAssertTrue(disk.revisions.isEmpty)
        XCTAssertEqual(disk.importLedger?.entries.map(\.outcome), [.rejected(.observationChanged), .rejected(.ownershipChanged)])
    }

    func testBeforeIntentAndBeforeFinalCommitCanRestartRepeatedly() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        let bytes = try Data(contentsOf: fixture.url)
        do {
            _ = try await owner.applyImport(op, source: source, proposal: proposal) {
                if $0 == .beforeIntent { throw Interruption.stopped }
            }
            XCTFail("Expected interruption before any write")
        } catch Interruption.stopped {}
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        XCTAssertNil(try fixture.persisted().importLedger)

        let (reopened, _) = try await fixture.open()
        do {
            _ = try await reopened.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterIntent { throw POSIXError(.ENOSPC) }
            }
            XCTFail("Expected simulated no-space error")
        } catch let error as POSIXError { XCTAssertEqual(error.code, .ENOSPC) }
        let pending = try fixture.persisted()
        XCTAssertTrue(pending.revisions.isEmpty)
        XCTAssertEqual(pending.importLedger?[op.id]?.outcome, .pending)

        let (retry, _) = try await fixture.open()
        let recovery = try await retry.importRecovery()
        XCTAssertEqual(recovery, [.init(operation: op, conflict: nil)])
        do {
            _ = try await retry.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterCommit { throw Interruption.stopped }
            }
            XCTFail("Expected interruption during recovery")
        } catch Interruption.stopped {}
        let (finalOwner, _) = try await fixture.open()
        try await expect(.applied, on: finalOwner, op, proposal)
        XCTAssertEqual(try fixture.persisted().revisions.map(\.id), [op.id])
        XCTAssertEqual(try fixture.persisted().importLedger?[op.id]?.outcome, .applied)
    }

    func testRealPreviousWriteFailureLeavesIntentAndRetryDoesNotAppendTwice() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        let oldBackup = fixture.root.appendingPathComponent("held-previous")
        let previous = fixture.previous
        do {
            _ = try await owner.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterIntent {
                    try FileManager.default.moveItem(at: previous, to: oldBackup)
                    try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: false)
                }
            }
            XCTFail("Expected the real .previous write to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: oldBackup.path))
        }
        let pending = try fixture.persisted()
        XCTAssertEqual(pending.importLedger?[op.id]?.outcome, .pending)
        XCTAssertTrue(pending.revisions.isEmpty)
        try FileManager.default.removeItem(at: previous)
        try FileManager.default.moveItem(at: oldBackup, to: previous)
        try await expect(.applied, on: owner, op, proposal)
        XCTAssertEqual(try fixture.persisted().revisions.map(\.id), [op.id])
        XCTAssertEqual(try fixture.persisted().importLedger?[op.id]?.outcome, .applied)
    }

    func testMismatchedSourceOrProposalCannotConsumePendingIntent() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        do {
            _ = try await owner.applyImport(op, source: source, proposal: proposal) {
                if $0 == .afterIntent { throw Interruption.stopped }
            }
            XCTFail("Expected pending operation")
        } catch Interruption.stopped {}

        let bytes = try Data(contentsOf: fixture.url)
        let changed = MappingImportSource(kind: .exchange, documentID: source.documentID, bytes: Data("different bytes".utf8))
        do {
            _ = try await owner.applyImport(op, source: changed, proposal: proposal)
            XCTFail("Expected source mismatch")
        } catch let conflict as MappingImportConflict { XCTAssertEqual(conflict, .sourceChanged) }
        do {
            _ = try await owner.applyImport(op, source: source, proposal: fixture.point)
            XCTFail("Expected proposal mismatch")
        } catch let conflict as MappingImportConflict { XCTAssertEqual(conflict, .proposalChanged) }
        let reused = try MappingImportOperation(id: op.id, source: source, sourceRecordID: "another row",
            target: op.target, kind: .skip)
        do {
            _ = try await owner.applyImport(reused, source: source, proposal: nil)
            XCTFail("Expected operation identity mismatch")
        } catch let conflict as MappingImportConflict { XCTAssertEqual(conflict, .operationIDReused) }
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        try await expect(.applied, on: owner, op, proposal)
    }

    func testSkipConflictAndProtectedEvidenceDoNotWriteObservations() async throws {
        let fixture = try fixture(rich: true)
        let (owner, snapshot) = try await fixture.open()
        let point = try XCTUnwrap(snapshot.committed.observation(id: fixture.point.id))
        let target = MappingImportTarget(point)
        let skip = try MappingImportOperation(source: source, sourceRecordID: "unchanged", target: target, kind: .skip)
        let rejected = try MappingImportOperation(source: source, sourceRecordID: "unresolved", target: target,
            kind: .conflict, note: "Confirm observation UUID")
        try await expect(.skipped, on: owner, skip, nil)
        try await expect(.rejected(.previewConflict), on: owner, rejected, nil)

        var proposal = point
        proposal.ratings = nil
        let op = try MappingImportOperation(source: source, sourceRecordID: point.id.uuidString, target: target,
            kind: .update, baseline: .capture(target: target, in: snapshot.committed), proposal: proposal,
            correction: .init(date: now, author: nil, reason: "Attempt to replace ratings"))
        try await expect(.rejected(.protectedEvidence), on: owner, op, proposal)
        let disk = try fixture.persisted()
        XCTAssertEqual(disk.observations, fixture.journal.observations)
        XCTAssertEqual(disk.revisions, fixture.journal.revisions)
        XCTAssertEqual(disk.importLedger?.entries.map(\.outcome), [.skipped, .rejected(.previewConflict), .rejected(.protectedEvidence)])
    }

    func testCorruptAndIncompleteLedgersFailClosedAndCannotEraseReceipts() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        try await expect(.applied, on: owner, op, proposal)
        let committed = try fixture.persisted()
        var stripped = committed
        stripped.importLedger = nil
        let freshStore = FileMappingStore(url: fixture.url)
        _ = try freshStore.load()
        XCTAssertThrowsError(try freshStore.save(stripped))
        let previous = try Data(contentsOf: fixture.previous)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any])
        let ledger = try XCTUnwrap(object["importLedger"] as? [String: Any])
        var missing = ledger
        missing.removeValue(forKey: "fingerprint")
        var truncated = ledger
        truncated["entries"] = []
        var partial = committed
        partial.revisions = []
        let missingReceiptEvidence = try JSONEncoder().encode(partial)
        let corruptBytes = try [missing, truncated, NSNull()].map { value in
            var invalid = object
            invalid["importLedger"] = value
            return try JSONSerialization.data(withJSONObject: invalid)
        } + [missingReceiptEvidence]

        for bytes in corruptBytes {
            try bytes.write(to: fixture.url, options: .atomic)
            let store = FileMappingStore(url: fixture.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(committed))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
            XCTAssertEqual(try Data(contentsOf: fixture.previous), previous)
        }
    }

    func testOfflineBackupCarriesPendingAndAppliedEvidenceInExistingMappingEntry() async throws {
        let fixture = try fixture()
        let (owner, snapshot) = try await fixture.open()
        let (op, proposal) = try update(snapshot, point: fixture.point)
        try await expect(.applied, on: owner, op, proposal)
        let measurementSource = MeasurementBackupSource(url: fixture.root.appendingPathComponent("measurements-v1.json"), expectedBytes: nil)
        let token = BackupCancellation()
        let staging = try await owner.captureBackup(measurements: measurementSource,
            photos: fixture.root.appendingPathComponent("photos"), plans: fixture.root.appendingPathComponent("plans"),
            cancellation: token, parent: fixture.root)
        let backup = try OfflineBackup.package(staging, cancellation: token)
        defer { backup.files.cleanup() }
        let reader = try BackupArchiveReader(url: XCTUnwrap(backup.files.urls.first), cancellation: token)
        let current = try JSONDecoder().decode(MappingJournal.self, from: reader.data(OfflineBackup.mappingPath))
        XCTAssertEqual(current, try fixture.persisted())
        XCTAssertEqual(current.importLedger?[op.id]?.outcome, .applied)
        let previous = try XCTUnwrap(backup.manifest.files.first { $0.path.hasSuffix(".previous") })
        let prior = try JSONDecoder().decode(MappingJournal.self, from: reader.data(previous.path))
        XCTAssertEqual(prior.importLedger?[op.id]?.outcome, .pending)
        XCTAssertTrue(prior.revisions.isEmpty)
    }
}
