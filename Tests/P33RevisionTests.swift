import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
private typealias RevisionReading = FieldForgeCore.Measurement
#else
@testable import FieldForge
private typealias RevisionReading = FieldForge.Measurement
#endif

@MainActor final class P33RevisionTests: XCTestCase {
    let fieldTime = Date(timeIntervalSince1970: 1_700_000_000.123456)
    let correctionTime = Date(timeIntervalSince1970: 1_800_000_000.987654)
    func seed() throws -> (MappingTests.MemoryStore, MappingWorkflow, MappingObservation) {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        let manual = try ManualOrientationInput(dipAngleText: "45,125", dipDirectionText: "360", reference: .gridNorth)
            .observation(notes: "Compass log", timestamp: fieldTime)
        var raw = MockSensorProvider.sample(dip: 60, direction: 270, timestamp: fieldTime.addingTimeInterval(1))
        raw.source = .coreMotion; raw.referenceFrame = .magneticNorthZVertical; raw.magneticAccuracy = .high; raw.magneticField.x = 40
        let sensor = RevisionReading.process(raw)
        try w.draft.addMeasurement(manual); try w.draft.addMeasurement(sensor)
        w.draft.picketConvention = .legacyMeters; w.draft.picket = "ПК 0+005"; w.draft.observedAtOverride = fieldTime; w.draft.timeZoneID = "Asia/Almaty"
        w.draft.startPicket = "5"; w.draft.endPicket = "10"; w.draft.observationPosition = .roof
        for id in [JointSetIdentifier.J1, .J2] {
            var set = JointSetDraft(identifier: id)
            set.representative = ManualOrientationInput(dipAngleText: "41.123456789", dipDirectionText: "120", reference: .magneticNorth)
            set.measurementIDs = [manual.id, sensor.id]; set.notes = "Field interpretation"; w.draft.jointSets.append(set)
        }
        var fault = TectonicStructureDraft(); fault.thickness = "0.125"; fault.description = "Trace; orientation unknown"
        w.draft.tectonicStructures = [fault]
        var q = BartonQInput(); q.rqd = "80"; q.rqdSource = .coreMeasured; q.location = .ordinary; q.contact = .wall
        q.assessmentSource = "Field log"; q.jn.select("F", parameter: .jn); q.jr.select("B", parameter: .jr)
        q.ja.select("C", parameter: .ja); q.jw.select("A", parameter: .jw); q.srf.select("G", parameter: .srf)
        w.draft.bartonQ = q; w.draft.rmr89.source = "Input only"
        let point = try w.save(now: fieldTime.addingTimeInterval(10))
        return (store, w, point)
    }
    func withDirectory(_ body: (URL) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path)
    }
    func testJ1AndFaultCorrectionKeepsOriginalEvidenceAndUnchangedInterpretationsExact() async throws {
        let (store, initial, original) = try seed(); var w = initial
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let evidence = try encoder.encode(w.journal.measurements)
        var draft = try w.correction(for: original.id)
        XCTAssertFalse(draft.hasChanges); XCTAssertEqual(draft.fields.jointSets[0].representative.dipAngleText, "41.123456789")
        draft.fields.jointSets[0].representative.dipAngleText = "52,123456789"
        draft.fields.tectonicStructures[0].thickness = "0,75"; draft.reason = "Correct compass transcription and fault thickness"
        draft.author = "Field engineer"
        let revision = try w.saveCorrection(draft, now: correctionTime)
        XCTAssertEqual(revision.version, 2); XCTAssertNil(revision.previousRevisionID); XCTAssertEqual(revision.correctedAt, correctionTime)
        XCTAssertEqual(revision.author, draft.author); XCTAssertEqual(revision.reason, draft.reason)
        XCTAssertEqual(w.journal.observations, [original]); XCTAssertEqual(w.observations.count, 1)
        XCTAssertEqual(revision.snapshot.id, original.id); XCTAssertEqual(revision.snapshot.observedAt, fieldTime)
        XCTAssertEqual(revision.snapshot.geology?.jointSets[0].revision, 2)
        XCTAssertEqual(revision.snapshot.geology?.jointSets[0].interpretedAt, correctionTime)
        XCTAssertEqual(revision.snapshot.geology?.jointSets[0].measurementIDs, original.measurementIDs)
        XCTAssertEqual(revision.snapshot.geology?.jointSets[1], original.geology?.jointSets[1])
        XCTAssertEqual(revision.snapshot.geology?.tectonicStructures[0].thicknessMeters, 0.75)
        XCTAssertEqual(revision.snapshot.ratings, original.ratings)
        XCTAssertEqual(try encoder.encode(w.journal.measurements), evidence)
        XCTAssertEqual(try MappingWorkflow(store: store).observations, [revision.snapshot])
        XCTAssertTrue(MappingObservationDifference.fields(before: original, after: revision.snapshot).contains("J1 · ориентация и север"))
    }
    func testSequentialRevisionsHistoryAndUndoByAppend() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var first = try w.correction(for: original.id); first.reason = "Picket"; first.fields.picket = "25"
        let a = try w.saveCorrection(first, now: correctionTime)
        var second = try w.correction(for: original.id); second.reason = "Notes"; second.fields.notes = "Revised"
        let b = try w.saveCorrection(second, now: correctionTime.addingTimeInterval(0.123456))
        var undo = try w.correction(for: original.id); undo.reason = "Restore original picket and notes"
        undo.fields.picket = original.picket; undo.fields.notes = original.notes
        let c = try w.saveCorrection(undo, now: correctionTime.addingTimeInterval(5))
        XCTAssertEqual(w.journal.history(for: original.id).map(\.version), [2, 3, 4])
        XCTAssertEqual(b.previousRevisionID, a.id); XCTAssertEqual(c.previousRevisionID, b.id)
        XCTAssertEqual(Set([a.id, b.id, c.id]).count, 3); XCTAssertEqual(w.observations, [original])
        XCTAssertEqual(w.journal.history(for: original.id)[0].snapshot.picket, "25")
        XCTAssertEqual(w.journal.history(for: original.id)[1].snapshot.notes, "Revised")
        XCTAssertTrue(w.journal.history(for: original.id)[2].snapshot.notes.isEmpty)
    }
    func testPlanMovePicketAndDateFiltersUseSingleEffectiveMarkerAndFrozenRevision() async throws {
        let (_, initial, original) = try seed(); var w = initial
        try withDirectory { path in
            let files = ManagedPlanStore(root: path.appendingPathComponent("plans"))
            let data = try DXFRealTests.data(200)
            let plan = try files.stage(data: data, filename: "200.dxf", horizonID: original.horizonID,
                version: "Survey A", units: .millimeters, crs: "mine grid", axes: "X north, Y east")
            try w.registerPlan(plan)
            var first = try w.correction(for: original.id); first.reason = "Locate on survey"
            try first.fields.selectPlanPoint(PlanPoint(x: 123.123456789, y: 456), plan: plan)
            let a = try w.saveCorrection(first, now: correctionTime)
            var second = try w.correction(for: original.id); second.reason = "Correct location and date"; second.fields.picket = "17,125"
            second.fields.observedAtOverride = fieldTime.addingTimeInterval(86400)
            try second.fields.selectPlanPoint(PlanPoint(x: 999.123456789, y: -12), plan: plan)
            let b = try w.saveCorrection(second, now: correctionTime.addingTimeInterval(1))
            XCTAssertEqual(w.points(on: plan).count, 1); XCTAssertEqual(w.points(on: plan)[0], b.snapshot)
            XCTAssertEqual(b.snapshot.coordinates?.units, "mm"); XCTAssertEqual(b.snapshot.coordinates?.planID, plan.id)
            XCTAssertEqual(b.snapshot.coordinates?.crs, plan.file?.crs); XCTAssertEqual(b.snapshot.coordinates?.axes, plan.file?.axes)
            XCTAssertTrue(b.snapshot.coordinates?.provenance.contains("Survey A") == true)
            XCTAssertEqual(a.snapshot.coordinates?.x, 123.123456789); XCTAssertEqual(b.snapshot.coordinates?.x, 999.123456789)
            XCTAssertEqual(b.snapshot.coordinates?.z, 393); XCTAssertEqual(b.snapshot.coordinates?.zOrigin, .horizonDefault)
            var q = MappingJournalQuery(); q.picket = "17,125"
            XCTAssertEqual(q.apply(w.journal.effectiveObservations, projectID: original.projectID).count, 1)
            q.picket = "ПК 0+005"; XCTAssertTrue(q.apply(w.journal.effectiveObservations, projectID: original.projectID).isEmpty)
            let other = try files.stage(data: data, filename: "200.dxf", horizonID: original.horizonID,
                version: "Survey B", units: .meters, crs: "mine grid", axes: "X north, Y east")
            try w.registerPlan(other); XCTAssertTrue(w.points(on: other).isEmpty)
            XCTAssertEqual(w.journal.observations, [original])
        }
    }
    func testManualPlanOverrideAndZClearPreserveHistoryWithoutUnitConversion() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.fields.x = "1.123456789"; edit.fields.y = "-2"; edit.fields.z = ""
        edit.reason = "Manual location; height unknown"
        let r = try w.saveCorrection(edit, now: correctionTime)
        XCTAssertEqual(r.snapshot.coordinates?.source, "manual"); XCTAssertEqual(r.snapshot.coordinates?.units, "m")
        XCTAssertNil(r.snapshot.coordinates?.z); XCTAssertEqual(r.snapshot.coordinates?.zOrigin, .manualOverride)
        XCTAssertNil(r.snapshot.coordinates?.zHorizonID); XCTAssertEqual(original.coordinates?.z, 393)
    }
    func testQRecalculationUsesFrozenMethodAndRMRRemainsInputOnly() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var draft = try w.correction(for: original.id); draft.fields.bartonQ.rqd = "60"; draft.fields.rmr89.source = "Corrected source notes"
        draft.reason = "Correct RQD from core log"
        let r = try w.saveCorrection(draft, now: correctionTime)
        XCTAssertEqual(original.ratings?.bartonQ?.evaluation.result?.value ?? 0, 40.0 / 3, accuracy: 1e-14)
        XCTAssertEqual(r.snapshot.ratings?.bartonQ?.evaluation.result?.value, 10)
        XCTAssertEqual(r.snapshot.ratings?.bartonQ?.method, QMethod.version)
        XCTAssertEqual(r.snapshot.ratings?.bartonQ?.assessedAt, correctionTime)
        XCTAssertEqual(r.snapshot.ratings?.rmr89?.input.source, "Corrected source notes")
        try r.snapshot.ratings?.rmr89?.validate()
    }
    func testInvalidCorrectionsAndFailedSaveRetainDraftAndGraphThenRetry() async throws {
        let (store, initial, original) = try seed(); var w = initial
        var draft = try w.correction(for: original.id); draft.fields.notes = "Retain on retry"
        for invalid in ["", "   \n"] {
            draft.reason = invalid; let before = draft
            XCTAssertThrowsError(try w.saveCorrection(draft)); XCTAssertEqual(draft, before); XCTAssertEqual(w.journal, initial.journal)
        }
        draft.reason = "Correct"; draft.fields.jointSets[0].representative.dipAngleText = "91"
        XCTAssertThrowsError(try w.saveCorrection(draft)); XCTAssertEqual(w.journal, initial.journal)
        draft.fields.jointSets[0].representative.dipAngleText = "40"
        store.fail = true; let before = draft
        XCTAssertThrowsError(try w.saveCorrection(draft)); XCTAssertEqual(draft, before); XCTAssertEqual(w.journal, initial.journal)
        store.fail = false; let r = try w.saveCorrection(draft, now: correctionTime)
        XCTAssertEqual(w.observations, [r.snapshot]); XCTAssertEqual(w.journal.revisions.count, 1)
    }
    func testEvidenceMutationAdditionRemovalAndStaleDraftAreRejected() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var remove = try w.correction(for: original.id); remove.reason = "Attempt removal"; remove.fields.removeMeasurement(id: original.measurementIDs[0])
        XCTAssertThrowsError(try w.saveCorrection(remove))
        var add = try w.correction(for: original.id); add.reason = "Attempt addition"
        try add.fields.addMeasurement(ManualOrientationInput(dipAngleText: "30", dipDirectionText: "90").observation())
        XCTAssertThrowsError(try w.saveCorrection(add)); XCTAssertEqual(w.journal, initial.journal)
        var stale = try w.correction(for: original.id); stale.reason = "First"
        try w.saveCorrection(stale, now: correctionTime)
        stale.reason = "Old editor"; XCTAssertThrowsError(try w.saveCorrection(stale))
        XCTAssertEqual(w.journal.revisions.count, 1)
    }
    func testPartialUnknownTectonicsAndOptionalIntervalCanBeCorrected() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.reason = "Partial orientation"
        edit.fields.tectonicStructures[0].orientation.dipDirectionText = "135"; edit.fields.tectonicStructures[0].orientation.reference = .trueNorth
        edit.fields.startPicket = ""; edit.fields.endPicket = ""; edit.fields.observationPosition = .face
        let a = try w.saveCorrection(edit, now: correctionTime)
        XCTAssertNil(a.snapshot.geology?.start); XCTAssertEqual(a.snapshot.geology?.position, .face)
        XCTAssertEqual(a.snapshot.geology?.tectonicStructures[0].orientation.dipAngleText, "")
        var next = try w.correction(for: original.id); next.reason = "Unknown orientation"
        next.fields.tectonicStructures[0].orientation.dipDirectionText = ""
        let b = try w.saveCorrection(next, now: correctionTime.addingTimeInterval(1))
        XCTAssertEqual(b.snapshot.geology?.tectonicStructures[0].orientation.dipDirectionText, "")
        XCTAssertEqual(a.snapshot.geology?.tectonicStructures[0].orientation.dipDirectionText, "135")
    }
    func testNoOpCorrectionPreservesExactHistoricalTimesOffsetsAssessmentsAndPrecision() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.reason = "Confirm original transcription"
        let revision = try w.saveCorrection(edit, now: correctionTime)
        XCTAssertEqual(revision.snapshot, original); XCTAssertEqual(revision.snapshot.observedUTCOffsetSeconds, original.observedUTCOffsetSeconds)
        XCTAssertEqual(revision.snapshot.observedTimeZoneID, "Asia/Almaty")
        XCTAssertEqual(MappingObservationDifference.fields(before: original, after: revision.snapshot), ["Полевые значения не изменены"])
    }
    func testFileReopenAppendOnlyAndRealBackupFailureRetry() async throws {
        let (_, initial, original) = try seed()
        try withDirectory { path in
            let url = path.appendingPathComponent("mapping.json"); let store = FileMappingStore(url: url)
            try store.save(initial.journal); var w = try MappingWorkflow(store: store)
            var edit = try w.correction(for: original.id); edit.reason = "Retry disk failure"; edit.fields.notes = "Corrected"
            let bytes = try Data(contentsOf: url)
            try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: false)
            XCTAssertThrowsError(try w.saveCorrection(edit)); XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(w.journal, initial.journal); XCTAssertEqual(edit.fields.notes, "Corrected")
            try FileManager.default.removeItem(at: store.backupURL)
            let revision = try w.saveCorrection(edit, now: correctionTime)
            let reopened = try MappingWorkflow(store: FileMappingStore(url: url))
            XCTAssertEqual(reopened.journal, w.journal); XCTAssertEqual(reopened.observations, [revision.snapshot])
            XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
            var altered = reopened.journal; altered.revisions = []; XCTAssertThrowsError(try store.save(altered))
            altered = reopened.journal
            altered.revisions[0] = MappingObservationRevision(id: revision.id, observationID: revision.observationID,
                version: revision.version, previousRevisionID: revision.previousRevisionID, correctedAt: revision.correctedAt,
                author: revision.author, reason: "Rewrite historic reason", snapshot: revision.snapshot)
            XCTAssertNoThrow(try altered.validate()) // A valid but rewritten audit entry is still forbidden by the store.
            XCTAssertThrowsError(try store.save(altered))
            altered = reopened.journal; altered.measurements[0].notes = "Tamper"; XCTAssertThrowsError(try store.save(altered))
            altered = reopened.journal; altered.observations = []; XCTAssertThrowsError(try store.save(altered))
        }
    }
    func testCurrentRichRecordsOpenWithoutRewriteAndCorrectionKeepsExactPreviousBytes() async throws {
        let (_, initial, original) = try seed()
        try withDirectory { path in
            let url = path.appendingPathComponent("mapping.json")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial.journal)) as? [String: Any])
            let bytes = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try bytes.write(to: url)
            let store = FileMappingStore(url: url); var w = try MappingWorkflow(store: store)
            XCTAssertEqual(w.journal.observations, initial.journal.observations); XCTAssertEqual(w.journal.measurements, initial.journal.measurements)
            XCTAssertEqual(w.journal.schemaVersion, 8); XCTAssertTrue(w.journal.revisions.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            var edit = try w.correction(for: original.id); edit.reason = "After reopen"; edit.fields.picket = "10"
            try w.saveCorrection(edit, now: correctionTime)
            XCTAssertEqual(try FileMappingStore(url: url).load(), w.journal)
            XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
        }
    }
    func testOldSchemaRefusalPreservesExistingBackupAndOriginalBytes() async throws {
        try withDirectory { path in
            let url = path.appendingPathComponent("mapping.json")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: CurrentMappingFixture.data) as? [String: Any])
            json["schemaVersion"] = 5
            let bytes = try JSONSerialization.data(withJSONObject: json)
            try bytes.write(to: url); try Data("Existing unrelated backup".utf8).write(to: url.appendingPathExtension("p5-backup"))
            let store = FileMappingStore(url: url)
            XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(MappingJournal()))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testPlanVersionSwitchAndManualOverrideLeaveCaptureDraftUntouched() async throws {
        let (_, initial, original) = try seed(); var w = initial
        w.draft.picket = "200"; w.draft.notes = "Unsaved capture"
        let captureDraft = w.draft
        try withDirectory { path in
            let files = ManagedPlanStore(root: path.appendingPathComponent("plans"))
            let a = try files.stage(data: DXFRealTests.data(200), filename: "200.dxf", horizonID: original.horizonID,
                version: "A", units: .millimeters, crs: "frame A", axes: "WCS XY")
            let b = try files.stage(data: DXFRealTests.data(300), filename: "300.dxf", horizonID: original.horizonID,
                version: "B", units: .unknown, crs: "frame B", axes: "WCS XY")
            try w.registerPlan(a); try w.registerPlan(b)
            var edit = try w.correction(for: original.id); edit.reason = "Use A"
            try edit.fields.selectPlanPoint(PlanPoint(x: 10, y: 20), plan: a); let first = try w.saveCorrection(edit, now: correctionTime)
            edit = try w.correction(for: original.id); edit.reason = "Use B with manual XY override"
            try edit.fields.selectPlanPoint(PlanPoint(x: 30, y: 40), plan: b); edit.fields.x = "30.123456789"
            let second = try w.saveCorrection(edit, now: correctionTime.addingTimeInterval(1))
            XCTAssertTrue(w.points(on: a).isEmpty); XCTAssertEqual(w.points(on: b), [second.snapshot])
            XCTAssertEqual(first.snapshot.coordinates?.units, "mm"); XCTAssertEqual(second.snapshot.coordinates?.units, "drawing")
            XCTAssertEqual(second.snapshot.coordinates?.source, "manualInPlan"); XCTAssertEqual(second.snapshot.coordinates?.crs, "frame B")
            XCTAssertEqual(second.snapshot.coordinates?.planID, b.id); XCTAssertEqual(w.draft, captureDraft)
            // A correction opened from the all-horizon journal uses its frozen plan scope explicitly.
            w.draft = MappingDraft()
            let other = try w.createHorizon(elevation: "-120")
            try w.requestContext(MappingContext(projectID: original.projectID, horizonID: other))
            XCTAssertTrue(w.points(on: b).isEmpty)
            XCTAssertEqual(w.points(on: b, restrictToSelection: false), [second.snapshot])
        }
    }
    func testInvalidCoordinatesRatingsIntervalsAndForeignEvidenceDoNotPublish() async throws {
        let (_, initial, original) = try seed(); var w = initial
        let changes: [(inout MappingDraft) -> Void] = [
            { $0.x = "NaN" }, { $0.z = "inf" }, { $0.startPicket = "20"; $0.endPicket = "10" },
            { $0.bartonQ.rqd = "101" }, { $0.rmr89.rqd = "-1" },
            { $0.jointSets[0].measurementIDs.append(UUID()) }, { $0.tectonicStructures[0].thickness = "-1" }
        ]
        for change in changes {
            var draft = try w.correction(for: original.id); draft.reason = "Invalid source transcription"; change(&draft.fields)
            let preserved = draft
            XCTAssertThrowsError(try w.saveCorrection(draft)); XCTAssertEqual(w.journal, initial.journal); XCTAssertEqual(draft, preserved)
        }
    }
    func testInterpretationRemovalReadditionAndHistoryOwnership() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.reason = "Withdraw J1 interpretation"
        edit.fields.jointSets.removeFirst(); let first = try w.saveCorrection(edit, now: correctionTime)
        XCTAssertEqual(first.snapshot.geology?.jointSets.map(\.identifier), [.J2])
        var reuse = try w.correction(for: original.id); reuse.reason = "Attempt UUID reuse after withdrawal"
        var reused = JointSetDraft(identifier: .J1, id: original.geology!.jointSets[0].id)
        reused.representative = ManualOrientationInput(dipAngleText: "30", dipDirectionText: "180")
        reuse.fields.jointSets.append(reused)
        XCTAssertThrowsError(try w.saveCorrection(reuse, now: correctionTime.addingTimeInterval(0.5)))
        edit = try w.correction(for: original.id); edit.reason = "New J1 interpretation"; edit.fields.addJointSet()
        edit.fields.jointSets[0].representative = ManualOrientationInput(dipAngleText: "30", dipDirectionText: "180")
        let second = try w.saveCorrection(edit, now: correctionTime.addingTimeInterval(1))
        XCTAssertNotEqual(second.snapshot.geology?.jointSets[0].id, original.geology?.jointSets[0].id)
        XCTAssertEqual(second.snapshot.geology?.jointSets[0].revision, 1)
        XCTAssertEqual(w.journal.observations[0].geology?.jointSets[0], original.geology?.jointSets[0])
        XCTAssertEqual(w.journal.measurements.count, 2)
    }
    func testCurrentLiteralUnknownLocationAndHistoricOffsetStayExact() async throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: CurrentMappingFixture.data) as? [String: Any])
        var points = json["observations"] as! [[String: Any]]
        points[0].removeValue(forKey: "coordinates")
        points[0]["observedTimeZoneID"] = "Asia/Almaty"; points[0]["observedUTCOffsetSeconds"] = 21600
        json["observations"] = points
        try withDirectory { path in
            let url = path.appendingPathComponent("mapping.json")
            let bytes = try JSONSerialization.data(withJSONObject: json); try bytes.write(to: url)
            var w = try MappingWorkflow(store: FileMappingStore(url: url)); let original = w.observations[0]
            var edit = try w.correction(for: original.id); edit.reason = "Retain historical time"; edit.fields.notes = "Reviewed"
            let revision = try w.saveCorrection(edit, now: correctionTime)
            XCTAssertNil(revision.snapshot.coordinates); XCTAssertNil(revision.snapshot.geology); XCTAssertNil(revision.snapshot.ratings)
            XCTAssertEqual(revision.snapshot.observedUTCOffsetSeconds, 21600)
            XCTAssertEqual(revision.snapshot.observedAt, original.observedAt)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("previous")), bytes)
        }
    }
    func testOldSchemaHeaderCannotSilentlyDiscardExistingCorrectionHistory() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.reason = "Retain history"; edit.fields.notes = "Effective corrected point"
        try w.saveCorrection(edit, now: correctionTime)
        for version in 1...6 {
            try withDirectory { path in
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w.journal)) as? [String: Any])
                json["schemaVersion"] = version
                let bytes = try JSONSerialization.data(withJSONObject: json), url = path.appendingPathComponent("mapping.json")
                try bytes.write(to: url)
                let store = FileMappingStore(url: url)
                XCTAssertThrowsError(try store.load())
                XCTAssertThrowsError(try store.save(MappingJournal()))
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("p\(version)-backup").path))
            }
        }
    }
    func testCorruptedRevisionChainOwnershipSnapshotsAndMissingTableFailClosed() async throws {
        let (_, initial, original) = try seed(); var w = initial
        var edit = try w.correction(for: original.id); edit.reason = "Correction"; edit.fields.notes = "Revised"
        try w.saveCorrection(edit, now: correctionTime)
        let encoded = try JSONEncoder().encode(w.journal)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 3 }, { $0["previousRevisionID"] = UUID().uuidString },
            { $0["observationID"] = UUID().uuidString }, { $0["reason"] = "  " }, { $0["author"] = "  " },
            { var snapshot = $0["snapshot"] as! [String: Any]; snapshot["measurementIDs"] = []; $0["snapshot"] = snapshot },
            { var snapshot = $0["snapshot"] as! [String: Any]; snapshot["projectID"] = UUID().uuidString; $0["snapshot"] = snapshot },
            { var snapshot = $0["snapshot"] as! [String: Any]; snapshot["chainageMeters"] = 500; $0["snapshot"] = snapshot }
        ]
        for change in changes {
            var json = root; var revisions = json["revisions"] as! [[String: Any]]; change(&revisions[0]); json["revisions"] = revisions
            let graph = try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try graph.validate())
        }
        var json = root; json.removeValue(forKey: "revisions")
        XCTAssertThrowsError(try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: json)))
        var duplicate = w.journal; duplicate.revisions.append(duplicate.revisions[0]); XCTAssertThrowsError(try duplicate.validate())
    }
}
