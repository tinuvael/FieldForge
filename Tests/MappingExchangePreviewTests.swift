import XCTest
import zlib
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingExchangePreviewTests: XCTestCase {
    private let time = Date(timeIntervalSinceReferenceDate: 721234567.1234567)
    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "1A000000-0000-4000-8000-%012d", n))! }
    private func fixture(longOriginal: Bool = false, includeRegulatory: Bool = false, rmr89: RMR89Input? = nil) throws -> MappingJournal {
        var j = MappingJournal()
        j.projects = [.init(id: id(1), name: "Проект А"), .init(id: id(2), name: "Проект Б")]
        j.horizons = [.init(id: id(3), projectID: id(1), name: "А", elevationMeters: -120.12345678912345, elevationDatum: "mine"), .init(id: id(4), projectID: id(2), name: "Б", elevationMeters: nil, elevationDatum: "unknown")]
        j.excavations = [.init(id: id(5), projectID: id(1), name: "А", horizonIDs: [id(3)]), .init(id: id(6), projectID: id(2), name: "Б", horizonIDs: [id(4)])]
        j.selection = .init(projectID: id(1), horizonID: id(3), excavationID: id(5))
        let store = MappingTests.MemoryStore(); store.value = j
        var w = try MappingWorkflow(store: store)
        w.draft = MappingDraft(id: id(7)); w.draft.picket = "1+2"; w.draft.observedAtOverride = time; w.draft.timeZoneID = "UTC"
        w.draft.chainageOriginAndDirection = "От устья → север"
        if longOriginal { w.draft.notes = String(repeating: "🪨", count: 20_000) }
        w.draft.x = "123456789.12345679"; w.draft.y = "-0.12345678912345678"; w.draft.z = "-120.12345678912345"
        w.draft.crs = "mine"; w.draft.axes = "X north; Y east"; w.draft.coordinateProvenance = "manual; survey log"
        w.draft.startPicket = "1+0"; w.draft.endPicket = "2+0"; w.draft.observationPosition = .roof
        let m = try ManualOrientationInput(dipAngleText: "45,12345678912345", dipDirectionText: "360", reference: .gridNorth).observation(id: id(10), timestamp: time)
        try w.draft.addMeasurement(m)
        for (n, identifier) in JointSetIdentifier.allCases.enumerated() {
            var set = JointSetDraft(identifier: identifier, id: id(20 + n))
            set.representative = .init(dipAngleText: "45", dipDirectionText: "120", reference: .magneticNorth)
            set.measurementIDs = [m.id]; set.spacing = "0.125"; set.author = "Инженер"
            w.draft.jointSets.append(set)
        }
        var fault = TectonicStructureDraft(id: id(25)); fault.description = "Неполная ориентация"; fault.thickness = "0.125"
        w.draft.tectonicStructures = [fault]
        var q = BartonQInput(); q.rqd = "80"; q.rqdSource = .coreMeasured; q.location = .ordinary; q.contact = .wall
        q.assessmentSource = "log"; q.jn.select("F", parameter: .jn); q.jr.select("B", parameter: .jr); q.ja.select("C", parameter: .ja); q.jw.select("A", parameter: .jw); q.srf.select("G", parameter: .srf)
        w.draft.bartonQ = q
        if let rmr89 { w.draft.rmr89 = rmr89 } else { w.draft.rmr89.source = "Input only" }
        w.draft.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair), lower: 35, upper: 45, finalValue: nil, assessedAt: time)
        let original = try w.seedHistoricalJointSetPoint(now: time)
        var correction = try w.correction(for: original.id); correction.reason = "Проверка"; correction.fields.notes = "Исправлено 🪨 _x0020_\r\n=literal"
        if includeRegulatory { correction.fields.regulatory = .init(strength: .below1, wallAlteration: .crushed) }
        _ = try w.saveCorrection(correction, now: time.addingTimeInterval(1))
        try w.requestContext(.init(projectID: id(2), horizonID: id(4), excavationID: id(6)))
        w.draft = MappingDraft(id: id(8)); w.draft.picket = "2+0"; w.draft.observedAtOverride = time; w.draft.timeZoneID = "UTC"
        _ = try w.save(now: time)
        return w.journal
    }
    private func export(_ journal: MappingJournal, project: Int = 1) throws -> MappingExchangeExport {
        try .prepare(committed: .init(journal), selection: .init(projectID: id(project), firstDay: time, lastDay: time, timeZoneID: "UTC"), now: time.addingTimeInterval(10), id: id(99))
    }
    private func edit(_ export: MappingExchangeExport, sheet: String, row: Int = 0, values: [String: String]) -> MappingExchangeExport {
        var tables = export.tables
        let index = tables.firstIndex { $0.name == sheet }!
        for (key, value) in values { let c = tables[index].columns.firstIndex(of: key)!; tables[index].rows[row][c] = value.isEmpty ? .empty : .text(value) }
        return .init(id: export.id, snapshotAt: export.snapshotAt, tables: tables)
    }
    private func preview(_ export: MappingExchangeExport, journal: MappingJournal) throws -> MappingExchangePreview {
        let files = try export.write()
        return try .prepare(url: files.urls[0], committed: .init(journal))
    }
    private func parts(_ export: MappingExchangeExport) throws -> [String: Data] {
        let files = try export.write(); return try archiveParts(Data(contentsOf: files.urls[0]))
    }
    private func newPoint(_ export: MappingExchangeExport, token: UUID? = nil) -> MappingExchangeExport {
        var tables = export.tables, table = export.tables.first { $0.name == "points" }!
        var values = Dictionary(uniqueKeysWithValues: Swift.zip(table.columns, table.rows[0]))
        for key in ["point_id", "original_id", "revision_id", "version", "base_fingerprint", "created_at_utc", "created_at_reference_seconds", "corrected_at_utc", "corrected_at_reference_seconds", "updated_at_reference_seconds", "measurement_ids_json", "correction_reason", "correction_author", "interval_start_text", "interval_start_m", "interval_end_text", "interval_end_m", "position"] { values[key] = .empty }
        values["record_action"] = .text("new"); values["client_record_id"] = .text((token ?? id(80)).uuidString); values["has_geology"] = .text("false")
        table.rows.append(table.columns.map { values[$0]! }); tables[tables.firstIndex { $0.name == "points" }!] = table
        return .init(id: export.id, snapshotAt: export.snapshotAt, tables: tables)
    }
    private func patched<T: Codable>(_ original: T, fields: [String: String]) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(MappingExchangeExport.json(original).utf8)) as? [String: Any])
        for (key, value) in fields { object[key] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed) }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func bytes(_ export: MappingExchangeExport) throws -> Data {
        let files = try export.write()
        defer { files.cleanup() }
        return try Data(contentsOf: files.urls[0])
    }

    private func makeOwner(_ journal: MappingJournal) async throws -> (URL, MappingStorageOwner, MappingCommittedSnapshot) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("mapping.json")
        try FileMappingStore(url: file).save(journal)
        let owner = MappingStorageOwner()
        let snapshot = try await owner.open { FileMappingStore(url: file) }
        return (root, owner, snapshot.committed)
    }

    private func correction(_ workbook: MappingExchangeExport, row: Int = 0, note: String) -> MappingExchangeExport {
        edit(workbook, sheet: "points", row: row, values: ["notes": note, "correction_reason": "Проверено инженером"])
    }

    private func row(_ workbook: MappingExchangeExport, sheet: String, column: String, value: String) throws -> Int {
        let table = try XCTUnwrap(workbook.tables.first { $0.name == sheet })
        let index = try XCTUnwrap(table.columns.firstIndex(of: column))
        return try XCTUnwrap(table.rows.firstIndex { if case .text(value) = $0[index] { return true }; return false })
    }

    private func threePoints(_ journal: MappingJournal) throws -> MappingJournal {
        let store = MappingTests.MemoryStore()
        store.value = journal
        var workflow = try MappingWorkflow(store: store)
        try workflow.requestContext(.init(projectID: id(1), horizonID: id(3), excavationID: id(5)))
        for (n, picket) in [(60, "2+2"), (61, "2+3")] {
            workflow.draft = MappingDraft(id: id(n))
            workflow.draft.picket = picket
            workflow.draft.notes = "Исходное примечание \(n)"
            workflow.draft.observedAtOverride = time
            workflow.draft.timeZoneID = "UTC"
            try workflow.save(now: time)
        }
        return workflow.journal
    }

    private enum Interrupted: Error { case simulated }

    func testConfirmationWithoutActionDoesNotRecordSkips() async throws {
        let journal = try fixture()
        let (root, owner, snapshot) = try await makeOwner(journal)
        let file = try bytes(newPoint(correction(export(journal), note: "Предложение из Excel")))
        let preview = try MappingExchangePreview.prepare(data: file, committed: snapshot)
        XCTAssertEqual(preview.count(.new), 1)
        XCTAssertEqual(preview.count(.correction), 1)
        let mappingURL = root.appendingPathComponent("mapping.json")
        let original = try Data(contentsOf: mappingURL)

        for selection in [MappingExchangeImport.Selection(), .init(accepted: ["missing"],
            rejectedPending: [id(7).uuidString], rejectedConflicts: [id(7).uuidString])] {
            XCTAssertFalse(selection.hasAction(in: preview))
            let batch = try MappingExchangeImport.Batch(preview: preview, bytes: file, selection: selection, now: time)
            XCTAssertTrue(batch.items.allSatisfy { $0.action.operation == nil })
            let (unchanged, report) = try await owner.applyExchange(batch)
            XCTAssertEqual(report.count(.notProcessed), 2)
            XCTAssertEqual(report.count(.skipped), 0)
            XCTAssertEqual(unchanged.journal, journal)
            XCTAssertEqual(try Data(contentsOf: mappingURL), original)
        }

        let selection = MappingExchangeImport.Selection(accepted: [id(7).uuidString])
        XCTAssertTrue(selection.hasAction(in: preview))
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: file, selection: selection, now: time)
        XCTAssertEqual(batch.items.compactMap { $0.action.operation?.kind }, [.update, .skip])
    }

    func testConfirmationDisplaysNewPointContextAndManualCoordinateProvenance() throws {
        let journal = try fixture()
        let workbook = try newPoint(export(journal))
        let index = try row(workbook, sheet: "points", column: "client_record_id", value: id(80).uuidString)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Almaty"))
        let proposal = try XCTUnwrap(preview(edit(workbook, sheet: "points", row: index, values: [
            "observed_zone": zone.identifier, "observed_offset_seconds": String(zone.secondsFromGMT(for: time)),
            "chainage_origin_direction": "От устья на север"
        ]), journal: journal).records.first { $0.classification == .new })
        let point = try XCTUnwrap(proposal.proposed)
        let expected = [
            "project_id": point.projectID.uuidString, "horizon_id": point.horizonID.uuidString,
            "excavation_id": point.excavationID.uuidString, "picket": point.picket, "picket_convention_json": "Пикет 10 м",
            "chainage_origin_direction": "От устья на север", "has_coordinates": "Да",
            "x": "123456789.12345679", "y": "-0.12345678912345678", "z_m": "-120.12345678912345",
            "xy_units": "m", "crs": "mine", "axes": "X north; Y east", "coordinate_source": "Вручную",
            "coordinate_provenance": "manual; survey log", "z_origin": "Вручную", "observed_zone": zone.identifier,
            "observed_offset_seconds": String(zone.secondsFromGMT(for: time)),
            "observed_at_reference_seconds": String(time.timeIntervalSinceReferenceDate)
        ]
        let displayed = proposal.visibleChanges
        for (field, value) in expected {
            let change = try XCTUnwrap(displayed.first { $0.id.hasSuffix("/" + field) }, field)
            XCTAssertTrue(change.before.isEmpty, field)
            XCTAssertEqual(change.after, value, field)
            XCTAssertFalse(change.title.hasPrefix(field + " ·"), field)
        }
    }

    func testConfirmationExpandsStructuredChangesAndPreservesUnexpandedValues() throws {
        let before = #"{"jn":{"origin":"tableSelection","value":"12"},"future":{"comment":"old"}}"#
        let after = #"{"jn":{"origin":"manualWithinRow","value":"12"},"future":{"comment":"[new](https://example.com)"}}"#
        let q = MappingExchangePreview.Change(sheet: "assessments", record: "point/Q", field: "input_json",
            before: before, after: after, row: 2)
        let malformed = MappingExchangePreview.Change(sheet: "points", record: "point", field: "rock_json",
            before: #"{"code":"004"}"#, after: #"{"code":"#, row: 3)
        let record = MappingExchangePreview.Record(id: "point", classification: .correction, reason: "",
            changes: [q, malformed], proposed: nil)
        let displayed = record.visibleChanges
        let origin = try XCTUnwrap(displayed.first { $0.id == q.id + "/jn.origin" })
        XCTAssertEqual(origin.before, "Выбрана табличная величина")
        XCTAssertEqual(origin.after, "Ручной ввод в пределах строки")
        let fallback = try XCTUnwrap(displayed.first { $0.id == q.id })
        XCTAssertEqual(fallback.before, before)
        XCTAssertEqual(fallback.after, after)
        XCTAssertEqual(displayed.first { $0.id == malformed.id }?.after, malformed.after)
        XCTAssertEqual(Set(displayed.map(\.id)).count, displayed.count)
    }

    func testWorkbookBytesRoundTripPreservesPhotosDXFMeasurementsAndAssessmentHistory() async throws {
        var rmrInput = FinalFieldPolishTests.referenceInput()
        rmrInput.source = "Original RMR log"
        var journal = try threePoints(fixture(includeRegulatory: true, rmr89: rmrInput))
        let dxf = DXFFixtures.drawing("0\nLINE\n5\nAB\n10\n0\n20\n0\n30\n-20\n11\n10\n21\n0\n31\n20\n")
        let document = try DXFDocument.parse(dxf)
        let plan = MappingPlanReference(id: id(40), horizonID: id(3), attachmentID: id(41), version: "A",
            file: .init(originalFilename: "fixture.dxf", sha256: ManagedPlanStore.digest(dxf), byteCount: dxf.count,
                importedAt: time, units: .meters, crs: "mine grid", axes: "WCS XYZ", unitDeclaration: "userConfirmedAtImport",
                insertionUnits: document.insertionUnits))
        journal.plans = [plan]
        let memory = MappingTests.MemoryStore(); memory.value = journal
        var workflow = try MappingWorkflow(store: memory)
        let xy = PlanPoint(x: 2.5, y: 1)
        var location = try workflow.correction(for: id(7))
        location.reason = "Положение на плане"
        try location.fields.selectPlanPoint(xy, plan: plan, elevation: XCTUnwrap(PlanElevationSnap.resolve(xy, document: document, plan: plan).automatic))
        try workflow.saveCorrection(location, now: time.addingTimeInterval(2))
        let photoBytes = try P41PhotoTests().image()
        let attachment = PhotoAttachment(id: id(50), originalFilename: "field.jpg", sha256: ManagedPhotoStore.digest(photoBytes),
            byteCount: photoBytes.count, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1,
            orientation: 1, representation: "Exact original")
        let photo = PhotoObservation(id: id(51), attachmentID: attachment.id, context: try workflow.journal.photoContext(for: id(7)),
            source: .files, importedAt: time, capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown", metadata: .init(name: "Original"))
        let photoOp = PhotoImportOperation(version: 2, photo: photo, attachment: attachment)
        try workflow.registerPhoto(photoOp)
        try workflow.correctPhoto(photo.id, baselineRevisionID: nil, metadata: .init(name: "Field caption"), reason: "Photo history")
        journal = workflow.journal

        let (root, owner, snapshot) = try await makeOwner(journal)
        let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
        try files.stage(photoBytes, for: photoOp)
        try files.promote(photoOp)
        try files.complete(photoOp)

        let original = try XCTUnwrap(snapshot.observation(id: id(7)))
        var edited = try newPoint(export(journal), token: id(80))
        let first = try row(edited, sheet: "points", column: "point_id", value: id(7).uuidString)
        let second = try row(edited, sheet: "points", column: "point_id", value: id(60).uuidString)
        let third = try row(edited, sheet: "points", column: "point_id", value: id(61).uuidString)
        edited = correction(edited, row: first, note: "Уточнение по журналу 🪨")
        edited = edit(edited, sheet: "points", row: first, values: [
            "position": "face", "interval_start_text": "1+1", "interval_start_m": "11",
            "interval_end_text": "#CLEAR", "interval_end_m": "#CLEAR", "rock_json": #"{"code":"004","name":"Туф"}"#,
            "correction_author": "Инженер"])
        // An added row must not claim plan-derived coordinates from the copied point.
        let newRow = try row(edited, sheet: "points", column: "client_record_id", value: id(80).uuidString)
        edited = edit(edited, sheet: "points", row: newRow, values: Dictionary(uniqueKeysWithValues:
            ["x", "y", "z_m", "xy_units", "crs", "axes", "coordinate_source", "coordinate_provenance", "z_origin", "z_horizon_id",
             "z_horizon_elevation_m", "z_datum", "plan_id", "z_plan_geometry_json"].map { ($0, "") } +
             [("has_coordinates", "false"), ("notes", "Новая точка"), ("picket", "3+0"), ("chainage_m", "30")]))
        edited = correction(edited, row: second, note: "#CLEAR")
        edited = correction(edited, row: third, note: "Выборочно пропущено")

        edited = edit(edited, sheet: "joint_sets", row: try row(edited, sheet: "joint_sets", column: "joint_set_id", value: id(20).uuidString),
            values: ["spacing_m": "0.25", "persistence_m": "2.5", "aperture_mm": "0.8", "roughness": "Волнистая", "infill": "Кальцит", "notes": "Проверено"])
        edited = edit(edited, sheet: "tectonic_structures", values: ["type": "shearZone", "thickness_m": "0.375", "position": "Кровля", "description": "Зона сдвига"])

        let oldRatings = try XCTUnwrap(original.ratings)
        var q = try XCTUnwrap(oldRatings.bartonQ?.input)
        q.rqd = "85"
        for (parameter, category) in [(QParameter.jn, "G"), (.jr, "C"), (.ja, "D"), (.jw, "B"), (.srf, "F")] {
            var coefficient = q[parameter]
            coefficient.select(category, parameter: parameter)
            q[parameter] = coefficient
        }
        edited = edit(edited, sheet: "assessments", row: try row(edited, sheet: "assessments", column: "kind", value: "Q"), values:
            Dictionary(uniqueKeysWithValues: QParameter.allCases.map { ("\($0.rawValue)_text", q[$0].value) } +
                [("rqd_text", q.rqd), ("input_json", try MappingExchangeExport.json(q))]))
        var rmr = try XCTUnwrap(oldRatings.rmr89?.input)
        rmr.rqd = "93"; rmr.spacingMeters = "0.9"
        rmr.basicSelections?["rqd"] = "rqd-0"; rmr.basicSelections?["spacing"] = "spacing-1"
        edited = edit(edited, sheet: "assessments", row: try row(edited, sheet: "assessments", column: "kind", value: "RMR89-basic"),
            values: ["rqd_text": rmr.rqd, "rmr_spacing_m_text": rmr.spacingMeters, "input_json": try MappingExchangeExport.json(rmr)])
        let previousGSI = try XCTUnwrap(oldRatings.gsi)
        let gsi = GSIAssessment(selection: previousGSI.selection, lower: 37, upper: 48, finalValue: previousGSI.finalValue, assessedAt: previousGSI.assessedAt)
        edited = edit(edited, sheet: "assessments", row: try row(edited, sheet: "assessments", column: "kind", value: "GSI"),
            values: ["input_json": try MappingExchangeExport.json(gsi)])

        // Parse actual ZIP/worksheet bytes with an Excel-style DEFLATE rewrite.
        let workbookBytes = try zip(parts(edited).sorted { $0.key < $1.key }, deflated: true)
        let preview = try MappingExchangePreview.prepare(data: workbookBytes, committed: snapshot)
        XCTAssertEqual(preview.rowsProcessed, 4)
        XCTAssertEqual(preview.count(.new), 1)
        XCTAssertEqual(preview.count(.correction), 3, preview.records.map(\.reason).joined(separator: "\n"))
        XCTAssertFalse(preview.hasBlockingRecords)
        let reviewed = try XCTUnwrap(preview.records.first { $0.id == id(7).uuidString })
        let displayed = reviewed.visibleChanges
        for delta in reviewed.changes where delta.field != "input_json" {
            XCTAssertTrue(displayed.contains { $0.id == delta.id || $0.id.hasPrefix(delta.id + "/") }, delta.id)
        }
        for path in ["rock_json/code", "rock_json/name", "input_json/basicSelections.rqd", "input_json/basicSelections.spacing",
                     "input_json/lower", "input_json/upper"] + QParameter.allCases.map({ "input_json/\($0.rawValue).category" }) {
            XCTAssertTrue(displayed.contains { $0.id.hasSuffix("/" + path) }, path)
        }
        XCTAssertEqual(displayed.first { $0.id.hasSuffix("/input_json/lower") }?.after, "37")
        XCTAssertEqual(displayed.first { $0.id.hasSuffix("/interval_end_m") }?.after, "")
        XCTAssertEqual(displayed.first { $0.id.hasPrefix("tectonic_structures/") && $0.id.hasSuffix("/type") }?.after, "Зона сдвига")
        XCTAssertFalse(displayed.contains { $0.id.hasSuffix("/input_json") })
        let chosen: MappingExchangeImport.Selection = .init(accepted: [id(7).uuidString, id(60).uuidString, "new/\(id(80).uuidString)"])
        let date = time.addingTimeInterval(60)
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: workbookBytes, selection: chosen, now: date)
        let (updated, report) = try await owner.applyExchange(batch)
        XCTAssertFalse(report.interrupted)
        XCTAssertEqual(report.count(.applied), 3)
        XCTAssertEqual(report.count(.skipped), 1)
        XCTAssertEqual(updated.journal.observations.dropLast(), journal.observations[...])
        XCTAssertEqual(Array(updated.journal.revisions.prefix(journal.revisions.count)), journal.revisions)
        XCTAssertEqual(updated.journal.measurements, journal.measurements)
        XCTAssertEqual(updated.journal.photos, journal.photos)
        XCTAssertEqual(updated.journal.photoAttachments, journal.photoAttachments)
        XCTAssertEqual(updated.journal.photoRevisions, journal.photoRevisions)
        XCTAssertEqual(updated.journal.plans, [plan])
        XCTAssertEqual(try files.read(attachment), photoBytes)
        XCTAssertEqual(updated.observation(id: id(80))?.createdAt, date)
        XCTAssertEqual(updated.observation(id: id(60))?.notes, "")
        XCTAssertEqual(updated.observation(id: id(61))?.notes, journal.effectiveObservation(id: id(61))?.notes)

        let revised = try XCTUnwrap(updated.observation(id: id(7)))
        XCTAssertEqual(revised.createdAt, original.createdAt)
        XCTAssertEqual(revised.coordinates, original.coordinates)
        XCTAssertEqual(revised.geology?.jointSets.last, original.geology?.jointSets.last)
        XCTAssertEqual(revised.geology?.jointSets.first?.measurementIDs, original.geology?.jointSets.first?.measurementIDs)
        XCTAssertEqual(revised.geology?.jointSets.first?.revision, (original.geology?.jointSets.first?.revision ?? 0) + 1)
        XCTAssertEqual(revised.geology?.jointSets.first?.interpretedAt, date)
        XCTAssertEqual(revised.geology?.tectonicStructures.first?.orientation, original.geology?.tectonicStructures.first?.orientation)
        XCTAssertEqual(revised.ratings?.bartonQ?.input, q)
        XCTAssertEqual(revised.ratings?.bartonQ?.evaluation, try q.fieldEvaluation())
        XCTAssertEqual(revised.ratings?.bartonQ?.method, oldRatings.bartonQ?.method)
        XCTAssertEqual(revised.ratings?.rmr89?.method, RMR89Assessment.verifiedVersion)
        XCTAssertEqual(revised.ratings?.rmr89?.calculation?.value, 76)
        XCTAssertEqual(revised.ratings?.rmr89?.input.source, "Original RMR log")
        XCTAssertEqual(revised.ratings?.gsi, gsi)
        XCTAssertEqual(revised.ratings?.regulatory, oldRatings.regulatory)
        XCTAssertEqual(updated.latestRevisions[id(7)]?.correctedAt, date)
        XCTAssertEqual(updated.latestRevisions[id(7)]?.author, "Инженер")

        let reexport = try bytes(export(updated.journal))
        let reexported = try workbook(archiveParts(reexport))
        let rows = try XCTUnwrap(reexported.sheets["points"]?.rows)
        let exported = try XCTUnwrap(rows.first { $0["point_id"] == id(7).uuidString })
        XCTAssertEqual(exported["notes"], "Уточнение по журналу 🪨")
        XCTAssertEqual(exported["position"], "face")
        XCTAssertEqual(exported["interval_start_m"], "11.0")
        XCTAssertEqual(exported["interval_end_m"], "")
        XCTAssertEqual(exported["rock_json"], #"{"code":"004","name":"Туф"}"#)
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["persistence_m"], "2.5")
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["aperture_mm"], "0.8")
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["roughness"], "Волнистая")
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["infill"], "Кальцит")
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["notes"], "Проверено")
        XCTAssertEqual(reexported.sheets["joint_sets"]?.rows.first?["spacing_m"], "0.25")
        XCTAssertEqual(reexported.sheets["tectonic_structures"]?.rows.first?["type"], "shearZone")
        XCTAssertEqual(reexported.sheets["tectonic_structures"]?.rows.first?["thickness_m"], "0.375")
        XCTAssertEqual(reexported.sheets["tectonic_structures"]?.rows.first?["position"], "Кровля")
        XCTAssertEqual(reexported.sheets["tectonic_structures"]?.rows.first?["description"], "Зона сдвига")
        let assessments = try XCTUnwrap(reexported.sheets["assessments"]?.rows)
        XCTAssertEqual(assessments.first { $0["kind"] == "Q" }?["input_json"], try MappingExchangeExport.json(q))
        XCTAssertEqual(assessments.first { $0["kind"] == "RMR89-basic" }?["input_json"], try MappingExchangeExport.json(rmr))
        XCTAssertEqual(assessments.first { $0["kind"] == "GSI" }?["input_json"], try MappingExchangeExport.json(gsi))
        XCTAssertEqual(try MappingExchangePreview.prepare(data: reexport, committed: updated).count(.unchanged), 4)

        let restoredOwner = MappingStorageOwner()
        let mappingURL = root.appendingPathComponent("mapping.json")
        let reopened = try await restoredOwner.open { FileMappingStore(url: mappingURL) }
        let again = try MappingExchangePreview.prepare(data: workbookBytes, committed: reopened.committed)
        let retry = try MappingExchangeImport.Batch(preview: again, bytes: workbookBytes, selection: chosen, now: date.addingTimeInterval(5))
        let (stable, repeated) = try await restoredOwner.applyExchange(retry)
        XCTAssertEqual(repeated.count(.alreadyApplied), 3)
        XCTAssertEqual(stable.journal, updated.journal)
    }

    func testBatchInterruptionAndReopenFinishOnlyUncommittedRows() async throws {
        let journal = try threePoints(fixture())
        let (root, owner, before) = try await makeOwner(journal)
        var workbook = try export(journal)
        let ids = [id(7), id(60), id(61)]
        for pointID in ids {
            workbook = correction(workbook, row: try row(workbook, sheet: "points", column: "point_id", value: pointID.uuidString),
                                  note: "Проверено \(pointID)")
        }
        let bytes = try bytes(workbook)
        let preview = try MappingExchangePreview.prepare(data: bytes, committed: before)
        let selection = MappingExchangeImport.Selection(accepted: Set(ids.map(\.uuidString)))
        let date = time.addingTimeInterval(30)
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: bytes, selection: selection, now: date)
        let interruptedID = id(60)
        let (partial, report) = try await owner.applyExchange(batch) { operation, checkpoint in
            if operation.target.observationID == interruptedID, case .afterIntent = checkpoint { throw Interrupted.simulated }
        }
        XCTAssertTrue(report.interrupted)
        XCTAssertEqual(report.count(.applied), 1)
        XCTAssertEqual(report.count(.pending), 1)
        XCTAssertEqual(report.count(.notProcessed), 1)
        XCTAssertEqual(partial.journal.revisions.count, journal.revisions.count + 1)
        let recovered = MappingStorageOwner()
        let mappingURL = root.appendingPathComponent("mapping.json")
        let reopened = try await recovered.open { FileMappingStore(url: mappingURL) }
        let rechecked = try MappingExchangePreview.prepare(data: bytes, committed: reopened.committed)
        let retry = try MappingExchangeImport.Batch(preview: rechecked, bytes: bytes, selection: selection, now: date.addingTimeInterval(30))
        let (completed, result) = try await recovered.applyExchange(retry)
        XCTAssertFalse(result.interrupted)
        XCTAssertEqual(result.count(.alreadyApplied), 1)
        XCTAssertEqual(result.count(.applied), 2)
        XCTAssertEqual(completed.latestRevisions[id(60)]?.correctedAt, date)
        XCTAssertEqual(completed.latestRevisions[id(61)]?.correctedAt, date.addingTimeInterval(30))
        XCTAssertEqual(completed.journal.revisions.count, journal.revisions.count + 3)
        let overlapping = try MappingExchangeImport.Batch(preview: preview, bytes: bytes, selection: selection, now: date.addingTimeInterval(40))
        let (stable, overlappingReport) = try await recovered.applyExchange(overlapping)
        XCTAssertFalse(overlappingReport.interrupted)
        XCTAssertEqual(overlappingReport.count(.alreadyApplied), 3)
        XCTAssertEqual(stable.journal, completed.journal)
    }

    func testRejectPendingWorkbookConflictLeavesLocalRevisionIntact() async throws {
        let journal = try fixture()
        let (_, owner, before) = try await makeOwner(journal)
        let file = try bytes(correction(export(journal), note: "Excel"))
        let preview = try MappingExchangePreview.prepare(data: file, committed: before)
        let pointID = id(7), date = time.addingTimeInterval(30)
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: file,
            selection: .init(accepted: [pointID.uuidString]), now: date)
        let (partial, result) = try await owner.applyExchange(batch) { _, checkpoint in
            if case .afterIntent = checkpoint { throw Interrupted.simulated }
        }
        XCTAssertEqual(result.count(.pending), 1)
        let (changed, _) = try await owner.transaction(snapshot: MappingWorkflow.Snapshot(committed: partial, draft: .init(),
            pendingContext: nil, suspendedDrafts: [])) { workflow in
            var local = try workflow.correction(for: pointID)
            local.reason = "Полевое исправление"
            local.fields.notes = "Локально"
            try workflow.saveCorrection(local, now: date)
        }
        let stale = try MappingExchangePreview.prepare(data: file, committed: changed.committed)
        XCTAssertEqual(stale.count(.conflict), 1)
        XCTAssertEqual(stale.records.first?.receipt?.outcome, .pending)
        let rejection = MappingExchangeImport.Selection(rejectedPending: [pointID.uuidString])
        XCTAssertFalse(MappingExchangeImport.Selection().hasAction(in: stale))
        XCTAssertFalse(MappingExchangeImport.Selection(rejectedConflicts: [pointID.uuidString]).hasAction(in: stale))
        XCTAssertTrue(rejection.hasAction(in: stale))
        let decision = try MappingExchangeImport.Batch(preview: stale, bytes: file, selection: rejection, now: date)
        let (retained, report) = try await owner.applyExchange(decision)
        XCTAssertEqual(report.count(.rejected), 1)
        XCTAssertEqual(retained.journal.revisions, changed.journal.revisions)
        let pending = try await owner.importRecovery()
        XCTAssertTrue(pending.isEmpty)
    }

    func testQHistoricalMethodRoundTripsWithoutChangingMethodOrSource() async throws {
        var journal = try fixture(includeRegulatory: true)
        let point = try XCTUnwrap(journal.effectiveObservation(id: id(7)))
        var ratings = try XCTUnwrap(point.ratings)
        let old = try XCTUnwrap(ratings.bartonQ)
        let documented = try BartonQAssessment(input: old.input, now: old.assessedAt, method: QMethod.version)
        ratings = MappingRatings(bartonQ: documented, rmr89: ratings.rmr89, gsi: ratings.gsi, regulatory: ratings.regulatory)
        let updated = try patched(point, fields: ["ratings": MappingExchangeExport.json(ratings)])
        journal.revisions[0] = try patched(journal.revisions[0], fields: ["snapshot": MappingExchangeExport.json(updated)])
        let (_, owner, before) = try await makeOwner(journal)
        let original = try export(journal)
        let row = try row(original, sheet: "assessments", column: "kind", value: "Q")
        let workbook = edit(correction(original, note: "Документировано"), sheet: "assessments", row: row, values: ["rqd_text": "87"])
        let data = try bytes(workbook)
        let preview = try MappingExchangePreview.prepare(data: data, committed: before)
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: data,
            selection: .init(accepted: [id(7).uuidString]), now: time.addingTimeInterval(30))
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.applied), 1)
        let reexported = try self.workbook(archiveParts(bytes(export(after.journal))))
        let q = try XCTUnwrap(reexported.sheets["assessments"]?.rows.first { $0["kind"] == "Q" })
        XCTAssertEqual(q["method"], QMethod.version)
        XCTAssertEqual(q["rqd_text"], "87")
        let latest = try XCTUnwrap(after.observation(id: id(7))?.ratings?.bartonQ)
        XCTAssertEqual(latest.input.assessmentSource, documented.input.assessmentSource)
        XCTAssertEqual(latest.evaluation, try latest.input.evaluate())
    }

    func testConfirmRechecksFileObservationAndParentContext() async throws {
        let journal = try threePoints(fixture())
        let (_, owner, original) = try await makeOwner(journal)
        var workbook = try export(journal)
        for pointID in [id(7), id(60)] {
            workbook = correction(workbook, row: try row(workbook, sheet: "points", column: "point_id", value: pointID.uuidString), note: "Excel")
        }
        let edited = try bytes(workbook)
        let preview = try MappingExchangePreview.prepare(data: edited, committed: original)
        let selection = MappingExchangeImport.Selection(accepted: [id(7).uuidString, id(60).uuidString])
        XCTAssertThrowsError(try MappingExchangeImport.Batch(preview: preview, bytes: edited + Data([0]), selection: selection, now: time))
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: edited, selection: selection, now: time)

        let pointID = id(7), date = time
        let (changed, _) = try await owner.transaction(snapshot: MappingWorkflow.Snapshot(committed: original, draft: .init(),
            pendingContext: nil, suspendedDrafts: [])) { workflow in
            var local = try workflow.correction(for: pointID)
            local.reason = "Изменено локально"
            local.fields.notes = "Локальное значение"
            try workflow.saveCorrection(local, now: date)
        }
        let conflict = try MappingExchangePreview.prepare(data: edited, committed: changed.committed)
        let conflictingRow = try XCTUnwrap(conflict.records.first { $0.classification == .conflict })
        XCTAssertEqual(conflictingRow.changes.first { $0.field == "notes" }?.after, "Excel")
        let rejection = MappingExchangeImport.Selection(rejectedConflicts: [conflictingRow.id])
        XCTAssertTrue(rejection.hasAction(in: conflict))
        let rejectedBatch = try MappingExchangeImport.Batch(preview: conflict, bytes: edited, selection: rejection, now: date)
        XCTAssertEqual(rejectedBatch.items.first { $0.record.id == conflictingRow.id }?.action.operation?.kind, .conflict)
        let (updated, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.rejected), 1)
        XCTAssertEqual(report.count(.applied), 1)
        XCTAssertEqual(updated.observation(id: pointID)?.notes, "Локальное значение")
        XCTAssertEqual(updated.observation(id: id(60))?.notes, "Excel")

        let nextWorkbook = try correction(export(updated.journal), note: "После смены контекста")
        let nextBytes = try bytes(nextWorkbook)
        let nextPreview = try MappingExchangePreview.prepare(data: nextBytes, committed: updated)
        let nextBatch = try MappingExchangeImport.Batch(preview: nextPreview, bytes: nextBytes,
            selection: .init(accepted: [pointID.uuidString]), now: date)
        let horizonID = id(3)
        _ = try await owner.transaction(snapshot: changed) { workflow in
            var next = workflow.journal
            let index = try XCTUnwrap(next.horizons.firstIndex { $0.id == horizonID })
            let horizon = next.horizons[index]
            next.horizons[index] = .init(id: horizon.id, projectID: horizon.projectID, name: "Новый горизонт",
                elevationMeters: horizon.elevationMeters, elevationDatum: horizon.elevationDatum)
            try workflow.commit(next)
        }
        let (retained, rejected) = try await owner.applyExchange(nextBatch)
        XCTAssertEqual(rejected.count(.rejected), 1)
        XCTAssertEqual(retained.observation(id: pointID)?.notes, "Локальное значение")
        XCTAssertTrue(rejected.rows.contains { $0.status == .rejected && $0.detail.contains("контекст") })
    }

    func testWorkbookMetadataSheetsAndFieldSpecificValidation() throws {
        let journal = try fixture(rmr89: FinalFieldPolishTests.referenceInput())
        let base = try export(journal)
        let qRow = try row(base, sheet: "assessments", column: "kind", value: "Q")
        let rmrRow = try row(base, sheet: "assessments", column: "kind", value: "RMR89-basic")
        let editable = correction(base, note: "Уточнение")
        let gsiRow = try row(base, sheet: "assessments", column: "kind", value: "GSI")
        let gsi = try XCTUnwrap(journal.effectiveObservation(id: id(7))?.ratings?.gsi)
        let outOfRangeGSI = GSIAssessment(selection: gsi.selection, lower: 101, upper: 102, finalValue: nil, assessedAt: gsi.assessedAt)
        var wrongBand = FinalFieldPolishTests.referenceInput()
        wrongBand.basicSelections?["rqd"] = "unrecognized"
        let invalid = [
            edit(editable, sheet: "assessments", row: gsiRow, values: ["input_json": try MappingExchangeExport.json(outOfRangeGSI)]),
            edit(editable, sheet: "assessments", row: rmrRow, values: ["input_json": try MappingExchangeExport.json(wrongBand)]),
            edit(editable, sheet: "assessments", row: qRow, values: ["rqd_text": "101"]),
            edit(editable, sheet: "assessments", row: rmrRow, values: ["rmr_spacing_m_text": "0.05"]),
            edit(editable, sheet: "tectonic_structures", values: ["type": "unknown"]),
            edit(editable, sheet: "joint_sets", values: ["aperture_mm": "-0.1"])
        ]
        for version in invalid {
            let result = try preview(version, journal: journal)
            XCTAssertEqual(result.count(.invalid), 1, result.records.map(\.reason).joined(separator: ", "))
            XCTAssertFalse(result.records.contains(where: \.canApply))
            XCTAssertTrue(result.records[0].location.contains("строка 2"))
        }
        let knownKey = try row(base, sheet: "Формат", column: "key", value: "workbook_id")
        XCTAssertThrowsError(try preview(edit(base, sheet: "Формат", row: knownKey, values: ["value": id(88).uuidString]), journal: journal))
        XCTAssertThrowsError(try preview(edit(base, sheet: "Колонки", values: ["policy": "Другой текст"]), journal: journal))
        for sheet in ["Формат", "assessments"] {
            let missing = MappingExchangeExport(id: base.id, snapshotAt: base.snapshotAt, tables: base.tables.filter { $0.name != sheet })
            XCTAssertThrowsError(try preview(missing, journal: journal))
        }
        var tables = base.tables
        let points = try XCTUnwrap(tables.firstIndex { $0.name == "points" })
        tables[points].rows.append(tables[points].rows[0])
        let duplicate = edit(.init(id: base.id, snapshotAt: base.snapshotAt, tables: tables), sheet: "points", row: 1,
            values: ["point_id": id(7).uuidString.lowercased(), "notes": "Конфликтующий дубликат"])
        let ambiguous = try preview(duplicate, journal: journal)
        XCTAssertEqual(ambiguous.count(.invalid), 1)
        XCTAssertEqual(ambiguous.records.first?.location, "points · строки 2, 3")
        XCTAssertFalse(ambiguous.records.contains(where: \.canApply))
    }

    func testBlankAndClearRemainDistinctAndLegacyWorkbookIsReadable() throws {
        let journal = try fixture()
        let base = try export(journal)
        let blank = edit(base, sheet: "points", values: ["notes": ""])
        XCTAssertEqual(try preview(blank, journal: journal).count(.unchanged), 1)
        XCTAssertEqual(try preview(correction(base, note: "#CLEAR"), journal: journal).records[0].proposed?.notes, "")
        var tables = base.tables
        let format = try XCTUnwrap(tables.firstIndex { $0.name == "Формат" })
        tables[format].rows = Array(tables[format].rows.prefix(7)) + MappingExchangeExport.legacyInstructions.map { [.text($0.0), .text($0.1)] }
        let guide = try XCTUnwrap(tables.firstIndex { $0.name == "Колонки" })
        tables[guide] = MappingExchangeExport.legacyGuide
        XCTAssertEqual(try preview(.init(id: base.id, snapshotAt: base.snapshotAt, tables: tables), journal: journal).count(.unchanged), 1)
    }

    private func workbook(_ parts: [String: Data], limits: ExchangeLimits = .init()) throws -> ExchangeWorkbook { try .init(parts: parts, limits: limits) }

    func testUnmodifiedTwoProjectsExactEvidenceCoordinatesAndRevisionHistory() throws {
        let j = try fixture()
        for project in [1, 2] {
            let e = try export(j, project: project), p = try preview(e, journal: j)
            XCTAssertEqual(p.count(.unchanged), 1); XCTAssertFalse(p.hasBlockingRecords); XCTAssertEqual(p.count(.new), 0)
            XCTAssertEqual(p.records.first?.proposed, j.effectiveObservation(id: id(project == 1 ? 7 : 8)))
            let base = try ExchangeBaseline(workbook(parts(e)))
            XCTAssertEqual(base.snapshot.journal.observations, j.observations.filter { $0.projectID == id(project) })
            if project == 1 { XCTAssertEqual(base.snapshot.journal.revisions, j.revisions); XCTAssertEqual(base.snapshot.journal.measurements, j.measurements); XCTAssertEqual(base.snapshot.effectiveObservations[0].geology?.jointSets.count, 5) }
        }
    }
    func testNotesCorrectionPreservesExactCoordinates() throws {
        let j = try fixture(), e = try export(j)
        let edited = edit(e, sheet: "points", values: ["notes": "Новое описание", "correction_reason": "Уточнение"])
        let p = try preview(edited, journal: j)
        XCTAssertEqual(p.count(.correction), 1); XCTAssertFalse(p.hasBlockingRecords)
        XCTAssertEqual(p.records[0].proposed?.coordinates, j.effectiveObservation(id: id(7))?.coordinates)
        XCTAssertTrue(p.records[0].changes.contains { $0.field == "notes" && $0.before.contains("Исправлено") && $0.after == "Новое описание" })
        XCTAssertEqual(p.records[0].proposed?.measurementIDs, j.observations[0].measurementIDs)
    }
    func testRegulatorySourceRecordsAndHistoricalJ5SurviveExchangePreview() throws {
        let j = try fixture(includeRegulatory: true), e = try export(j)
        let effective = try XCTUnwrap(j.effectiveObservation(id: id(7)))
        XCTAssertEqual(try preview(e, journal: j).records.first?.proposed, effective)
        let edited = edit(e, sheet: "points", values: ["notes": "Новое описание", "correction_reason": "Уточнение"])
        let p = try preview(edited, journal: j)
        XCTAssertEqual(p.count(.correction), 1)
        XCTAssertEqual(p.records.first?.proposed?.ratings?.regulatory, .init(strength: .below1, wallAlteration: .crushed))
        XCTAssertEqual(p.records.first?.proposed?.geology?.jointSets.last, effective.geology?.jointSets.last)
        let j5 = edit(edited, sheet: "joint_sets", row: 4, values: ["notes": "Попытка изменить J5"])
        XCTAssertEqual(try preview(j5, journal: j).count(.unsupported), 1)
    }
    func testRMR89ExchangePreservesStoredCorrectionAndProtectsResult() throws {
        var input = FinalFieldPolishTests.referenceInput()
        input.apertureMillimeters = "2"; input.basicSelections?["aperture"] = "aperture-3"
        input.basicSelections?["overallCondition"] = "overallCondition-3"
        input.overallConditionContinuity = .continuous
        input.application = .foundations; input.orientationFavorability = .fair
        input.orientationDescription = "Documented foundation-specific interpretation"
        let j = try fixture(includeRegulatory: true, rmr89: input), e = try export(j)
        let snapshot = try XCTUnwrap(j.observations.first?.ratings?.rmr89)
        XCTAssertEqual(snapshot.calculation?.adjustedValue, 45)
        let p = try preview(e, journal: j)
        XCTAssertEqual(p.count(.unchanged), 1); XCTAssertEqual(p.records.first?.proposed?.ratings?.rmr89, snapshot)
        XCTAssertEqual(p.records.first?.proposed?.ratings?.rmr89?.input.overallConditionContinuity, .continuous)
        let assessments = try XCTUnwrap(e.tables.first { $0.name == "assessments" })
        let rmrRow = try XCTUnwrap(assessments.rows.firstIndex { if case .text("RMR89-basic") = $0[1] { return true }; return false })
        let modified = edit(e, sheet: "assessments", row: rmrRow, values: ["stored_rmr_calculation_json": "{}"])
        XCTAssertTrue(try preview(modified, journal: j).hasBlockingRecords)
    }
    func testNewPointExactDuplicateDivergentClientAndCollision() throws {
        let j = try fixture(), e = newPoint(try export(j))
        let p = try preview(e, journal: j); XCTAssertEqual(p.count(.new), 1); XCTAssertFalse(p.hasBlockingRecords)
        var tables = e.tables; let index = tables.firstIndex { $0.name == "points" }!
        tables[index].rows.append(tables[index].rows.last!)
        let duplicated = MappingExchangeExport(id: e.id, snapshotAt: e.snapshotAt, tables: tables)
        let d = try preview(duplicated, journal: j); XCTAssertEqual(d.count(.new), 1); XCTAssertEqual(d.count(.duplicate), 1)
        let divergent = edit(duplicated, sheet: "points", row: 2, values: ["notes": "Другая строка"])
        let a = try preview(divergent, journal: j); XCTAssertEqual(a.count(.invalid), 1); XCTAssertEqual(a.count(.new), 0)
        let c = try preview(newPoint(try export(j), token: id(7)), journal: j); XCTAssertEqual(c.count(.conflict), 1)
    }
    func testStaleBaseAndDivergentHistoryConflict() throws {
        let j = try fixture(), e = try export(j)
        let store = MappingTests.MemoryStore(); store.value = j
        var w = try MappingWorkflow(store: store), c = try w.correction(for: id(7)); c.reason = "Локально"; c.fields.notes = "Новая версия"
        _ = try w.saveCorrection(c, now: time.addingTimeInterval(20))
        let p = try preview(e, journal: w.journal); XCTAssertEqual(p.count(.conflict), 1); XCTAssertTrue(p.hasBlockingRecords)
    }
    func testImmutableMeasurementsParentIDsAndUnsupportedDeletion() throws {
        let j = try fixture(), e = try export(j)
        let evidence = try preview(edit(e, sheet: "measurements", values: ["original_dip_text": "30"]), journal: j)
        XCTAssertEqual(evidence.count(.unsupported), 1)
        let parent = try preview(edit(e, sheet: "points", values: ["horizon_id": id(4).uuidString]), journal: j)
        XCTAssertEqual(parent.count(.unsupported), 1)
        var tables = e.tables; tables[tables.firstIndex { $0.name == "joint_sets" }!].rows.removeLast()
        let missing = try preview(.init(id: e.id, snapshotAt: e.snapshotAt, tables: tables), journal: j)
        XCTAssertEqual(missing.count(.unsupported), 1)
        tables = e.tables; tables[tables.firstIndex { $0.name == "points" }!].rows = []
        let deleted = try preview(.init(id: e.id, snapshotAt: e.snapshotAt, tables: tables), journal: j)
        XCTAssertGreaterThan(deleted.count(.unsupported), 0); XCTAssertTrue(deleted.hasBlockingRecords)
    }
    func testMissingCorruptAndTamperedSourceRecordsAreRejected() throws {
        let j = try fixture(), e = try export(j)
        XCTAssertThrowsError(try preview(edit(e, sheet: "source_records", values: ["json_chunk": "{}"]), journal: j))
        XCTAssertThrowsError(try preview(edit(e, sheet: "source_records", values: ["point_id": id(70).uuidString]), journal: j))
        var tables = e.tables; tables[tables.firstIndex { $0.name == "source_records" }!].rows.removeLast()
        XCTAssertThrowsError(try preview(.init(id: e.id, snapshotAt: e.snapshotAt, tables: tables), journal: j))
    }
    func testInvalidUUIDParentNewUnitsTimeAndPrecision() throws {
        let j = try fixture(), e = newPoint(try export(j))
        for values in [["client_record_id": "not-a-uuid"], ["horizon_id": id(700).uuidString], ["x": "123456789.123456789"], ["observed_at_reference_seconds": "2023-11-09"], ["observed_at_utc": "2020-01-01T00:00:00.000Z"]] {
            let p = try preview(edit(e, sheet: "points", row: 1, values: values), journal: j)
            XCTAssertEqual(p.count(.invalid), 1, "\(values)"); XCTAssertTrue(p.hasBlockingRecords)
        }
        XCTAssertEqual(try preview(edit(e, sheet: "points", row: 1, values: ["xy_units": "feet"]), journal: j).count(.unsupported), 1)
    }
    func testJointInterpretationAndRatingInputsUseExistingValidationAndRequireAgreement() throws {
        let j = try fixture(), e = try export(j)
        var edited = edit(e, sheet: "joint_sets", values: ["notes": "Уточнено", "spacing_m": "0.25"])
        edited = edit(edited, sheet: "points", values: ["correction_reason": "Интерпретация"])
        XCTAssertEqual(try preview(edited, journal: j).count(.correction), 1)
        let disagreement = edit(edited, sheet: "joint_sets", values: ["original_dip_text": "35"])
        XCTAssertEqual(try preview(disagreement, journal: j).count(.unsupported), 1)
        let assessment = e.tables.first { $0.name == "assessments" }!
        let qRow = assessment.rows.firstIndex { row in if case .text("Q") = row[1] { return true }; return false }!
        var q = j.effectiveObservations[0].ratings!.bartonQ!.input; q.rqd = "85"
        var rating = edit(e, sheet: "assessments", row: qRow, values: ["rqd_text": "85", "input_json": try MappingExchangeExport.json(q)])
        rating = edit(rating, sheet: "points", values: ["correction_reason": "RQD"])
        XCTAssertEqual(try preview(rating, journal: j).count(.correction), 1)
        XCTAssertEqual(try preview(edit(rating, sheet: "assessments", row: qRow, values: ["rqd_text": "90"]), journal: j).count(.invalid), 1)
    }
    func testExcelStyleRewriteReorderedSheetsRowsSharedStringsAndDeflate() throws {
        let j = try fixture(), e = try export(j), original = try parts(e)
        var rewritten = original, strings: [String] = []
        let cell = try NSRegularExpression(pattern: #"(<c[^>]*?) t="inlineStr"([^>]*>)<is><t[^>]*>(.*?)</t></is></c>"#, options: [.dotMatchesLineSeparators])
        for path in original.keys.sorted() where path.hasPrefix("xl/worksheets/") {
            var xml = String(decoding: original[path]!, as: UTF8.self)
            for match in cell.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {
                let ns = xml as NSString, text = ns.substring(with: match.range(at: 3)), index = strings.count
                strings.append(text)
                let replacement = ns.substring(with: match.range(at: 1)) + " t=\"s\"" + ns.substring(with: match.range(at: 2)) + "<v>\(index)</v></c>"
                xml.replaceSubrange(Range(match.range, in: xml)!, with: replacement)
            }
            let row = try NSRegularExpression(pattern: #"<row\b[^>]*>.*?</row>"#, options: [.dotMatchesLineSeparators])
            let matches = row.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)), rowTexts = matches.map { (xml as NSString).substring(with: $0.range) }.reversed()
            for (match, replacement) in Swift.zip(matches.reversed(), rowTexts.reversed()) { xml.replaceSubrange(Range(match.range, in: xml)!, with: replacement) }
            rewritten[path] = Data(xml.utf8)
        }
        rewritten["xl/sharedStrings.xml"] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"\(ExchangeWorkbook.spreadsheet)\">" + strings.map { "<si><t xml:space=\"preserve\">\($0)</t></si>" }.joined() + "</sst>").utf8)
        func append(_ path: String, before: String, value: String) { rewritten[path] = Data(String(decoding: rewritten[path]!, as: UTF8.self).replacingOccurrences(of: before, with: value + before).utf8) }
        append("xl/_rels/workbook.xml.rels", before: "</Relationships>", value: "<Relationship Id=\"shared\" Type=\"\(ExchangeWorkbook.documentRelationships)sharedStrings\" Target=\"/xl/sharedStrings.xml\"/>")
        append("[Content_Types].xml", before: "</Types>", value: "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>")
        var book = String(decoding: rewritten["xl/workbook.xml"]!, as: UTF8.self)
        let sheet = try NSRegularExpression(pattern: #"<sheet\s[^>]*/>"#), matches = sheet.matches(in: book, range: NSRange(book.startIndex..., in: book))
        let names = matches.map { (book as NSString).substring(with: $0.range) }
        for (match, replacement) in Swift.zip(matches.reversed(), names) { book.replaceSubrange(Range(match.range, in: book)!, with: replacement) }
        rewritten["xl/workbook.xml"] = Data(book.utf8)
        let parts = try archiveParts(zip(rewritten.sorted { $0.key < $1.key }, deflated: true))
        let p = try MappingExchangePreview.prepare(workbook: workbook(parts), committed: .init(j))
        let old = try MappingExchangePreview.prepare(workbook: workbook(original), committed: .init(j))
        XCTAssertEqual(p.count(.unchanged), 1); XCTAssertFalse(p.hasBlockingRecords); XCTAssertEqual(p.proposalDigest, old.proposalDigest)
    }
    func testExcelAutoFilterAndSaveMetadataAllowOnlySafeWorkbookStructures() throws {
        let journal = try fixture(), exported = try export(journal)
        var package = try parts(exported)
        let path = "xl/workbook.xml"
        let original = String(decoding: package[path]!, as: UTF8.self)
        let metadata = """
        <mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:Choice Requires="x15"><x15ac:absPath xmlns:x15ac="http://schemas.microsoft.com/office/spreadsheetml/2010/11/ac" url="/unused/location/"/></mc:Choice></mc:AlternateContent>
        <xr:revisionPtr xmlns:xr="http://schemas.microsoft.com/office/spreadsheetml/2014/revision" revIDLastSave="0"/>
        """
        let filter = "<definedNames><definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"0\" hidden=\"1\">'Формат'!$A$1:$B$15</definedName></definedNames>"
        let features = """
        <extLst><ext uri="{B58B0392-4F1F-4190-BB64-5DF3571DCE5F}" xmlns:xcalcf="http://schemas.microsoft.com/office/spreadsheetml/2018/calcfeatures"><xcalcf:calcFeatures><xcalcf:feature name="microsoft.com:RD"/></xcalcf:calcFeatures></ext></extLst>
        """
        let saved = original.replacingOccurrences(of: "<sheets>", with: metadata + "<sheets>")
            .replacingOccurrences(of: "</workbook>", with: filter + features + "</workbook>")
        package[path] = Data(saved.utf8)
        let savedBytes = try zip(package.sorted { $0.key < $1.key }, deflated: true)
        XCTAssertEqual(try MappingExchangePreview.prepare(data: savedBytes, committed: .init(journal)).count(.unchanged), 1)
        for invalid in [saved.replacingOccurrences(of: "'Формат'!$A$1:$B$15", with: "[Other.xlsx]Sheet!$A$1"),
                        saved.replacingOccurrences(of: "_xlnm._FilterDatabase", with: "UnrecognizedName"),
                        saved.replacingOccurrences(of: "B58B0392-4F1F-4190-BB64-5DF3571DCE5F", with: "not-supported")] {
            package[path] = Data(invalid.utf8)
            XCTAssertThrowsError(try workbook(package))
        }
    }

    func testFormulaCachedResultNumericDateUnsupportedCellsAndExternalLinksRejected() throws {
        let e = try export(fixture()), original = try parts(e), path = "xl/worksheets/sheet7.xml"
        for value in ["<c r=\"A2\"><f>1+1</f><v>2</v></c>", "<c r=\"A2\" t=\"n\"><v>123456789123456</v></c>", "<c r=\"A2\" t=\"d\"><v>2023-11-09</v></c>", "<c r=\"A2\" t=\"b\"><v>1</v></c>"] {
            var bad = original
            let xml = String(decoding: bad[path]!, as: UTF8.self), regex = try NSRegularExpression(pattern: #"<c r="A2"[^>]*>.*?</c>"#, options: [.dotMatchesLineSeparators])
            bad[path] = Data(regex.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: value).utf8)
            XCTAssertThrowsError(try workbook(bad))
        }
        var external = original
        let rel = "xl/_rels/workbook.xml.rels"
        external[rel] = Data(String(decoding: original[rel]!, as: UTF8.self).replacingOccurrences(of: "Target=\"worksheets/sheet1.xml\"", with: "TargetMode=\"External\" Target=\"https://example.invalid/data\"").utf8)
        XCTAssertThrowsError(try workbook(external))
        external = original; external["xl/vbaProject.bin"] = Data([0]); XCTAssertThrowsError(try workbook(external))
        external = original; external["xl/connections.xml"] = Data("<connections/>".utf8); XCTAssertThrowsError(try workbook(external))
    }
    func testDTDXMLDepthAndExplicitComplexityLimitsRejectBeforePreview() throws {
        var p = try parts(export(fixture())), limits = ExchangeLimits()
        p["docProps/core.xml"] = Data("<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><a>&x;</a>".utf8)
        XCTAssertThrowsError(try workbook(p))
        p = try parts(export(fixture())); limits.xmlDepth = 3; XCTAssertThrowsError(try workbook(p, limits: limits))
        limits = .init(); limits.rows = 2; XCTAssertThrowsError(try workbook(p, limits: limits))
        limits = .init(); limits.cells = 10; XCTAssertThrowsError(try workbook(p, limits: limits))
        limits = .init(); limits.textUTF16 = 20; XCTAssertThrowsError(try workbook(p, limits: limits))
        limits = .init(); limits.xmlElements = 10; XCTAssertThrowsError(try workbook(p, limits: limits))
    }
    func testDuplicateJSONKeysRetypedExcelPrecisionLossAndMissingSourceChunk() throws {
        let j = try fixture(), e = try export(j)
        let truncated = edit(e, sheet: "points", values: ["x": "123456789.123457", "correction_reason": "Excel"])
        XCTAssertEqual(try preview(truncated, journal: j).count(.unsupported), 1)
        XCTAssertThrowsError(try ExchangeBaseline.decode([String: Int].self, #"{"x":1,"\u0078":2}"#))
        XCTAssertThrowsError(try ExchangeObservationProposal.object(ManualOrientationInput.self, #"{"dipAngleText":"45","dipAngleText":"30","dipDirectionText":"120","reference":"gridNorth","usesConventionalDipSide":false}"#))
        let longJournal = try fixture(longOriginal: true), long = try export(longJournal)
        XCTAssertEqual(try preview(long, journal: longJournal).count(.unchanged), 1)
        var tables = long.tables; let i = tables.firstIndex { $0.name == "source_records" }!
        let kind = tables[i].columns.firstIndex(of: "kind")!, index = tables[i].columns.firstIndex(of: "chunk_index")!
        let chunk = tables[i].rows.firstIndex { row in
            if case .text("original") = row[kind], case .text("1") = row[index] { return true }; return false
        }!
        tables[i].rows.remove(at: chunk)
        XCTAssertThrowsError(try preview(.init(id: long.id, snapshotAt: long.snapshotAt, tables: tables), journal: longJournal))
    }
    func testLegacyNilIntervalConventionIsNotReplacedByPointConvention() throws {
        var j = try fixture()
        func legacy(_ p: MappingObservation) throws -> MappingObservation {
            let g = p.geology!
            let geology = MappingGeology(start: .init(text: "10", meters: 10, convention: nil), end: .init(text: "20", meters: 20, convention: nil), position: g.position, jointSets: g.jointSets, tectonicStructures: g.tectonicStructures)
            return try patched(p, fields: ["geology": MappingExchangeExport.json(geology)])
        }
        j.observations[0] = try legacy(j.observations[0])
        j.revisions[0] = try patched(j.revisions[0], fields: ["snapshot": MappingExchangeExport.json(legacy(j.revisions[0].snapshot))])
        try j.validate()
        let edited = edit(try export(j), sheet: "points", values: ["interval_start_text": "11", "interval_start_m": "11", "correction_reason": "Граница"])
        let p = try preview(edited, journal: j)
        XCTAssertEqual(p.count(.correction), 1)
        let candidate = try XCTUnwrap(p.records.first?.proposed)
        XCTAssertEqual(candidate.geology?.start?.meters, 11)
        XCTAssertNil(candidate.geology?.start?.convention)
        XCTAssertEqual(candidate.picketConvention, .tenMeters)
    }
    func testZIPTraversalDuplicatesEncryptionCRCAndDecompressionBounds() throws {
        let bytes = Data("<xml/>".utf8)
        for entries in [[("../evil.xml", bytes)], [("xl/a.xml", bytes), ("xl/a.xml", bytes)], [("xl/a.xml", bytes), ("xl/A.xml", bytes)]] {
            XCTAssertThrowsError(try ExchangeArchive(data: zip(entries), limits: .init()))
        }
        var limits = ExchangeLimits(); limits.partBytes = 100
        XCTAssertThrowsError(try archiveParts(zip([("a", Data(repeating: 65, count: 10_000))], deflated: true), limits: limits))
        limits = .init(); limits.compressionRatio = 2
        XCTAssertThrowsError(try archiveParts(zip([("a", Data(repeating: 65, count: 10_000))], deflated: true), limits: limits))
        limits = .init(); limits.entries = 1
        XCTAssertThrowsError(try ExchangeArchive(data: zip([("a", bytes), ("b", bytes)]), limits: limits))
        var encrypted = try zip([("a", bytes)]); encrypted[6] |= 1
        XCTAssertThrowsError(try ExchangeArchive(data: encrypted, limits: .init()))
        var corrupt = try zip([("a", bytes)]); corrupt[31] ^= 1
        XCTAssertThrowsError(try archiveParts(corrupt))
    }
    func testCommittedGenerationStalenessNoMutationFailureOrCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("B2b-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileMappingStore(url: directory.appendingPathComponent("mapping.json")), j = try fixture()
        try store.save(j)
        let w = try MappingWorkflow(store: store), owner = MappingStorageOwner(store: store, committed: w.committed)
        let before = try Data(contentsOf: store.url), names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let e = try export(j), files = try e.write(), snapshot = try await owner.exchangeSnapshot()
        let p = try MappingExchangePreview.prepare(url: files.urls[0], committed: snapshot)
        XCTAssertFalse(p.isStale(comparedTo: snapshot)); let fresh = try await owner.exchangePreviewIsCurrent(p.generationID); XCTAssertTrue(fresh)
        XCTAssertThrowsError(try MappingExchangePreview.prepare(url: directory.appendingPathComponent("missing.xlsx"), committed: snapshot))
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MappingExchangePreview.prepare(url: files.urls[0], committed: snapshot)
        }
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), names)
        let (changed, _) = try await owner.transaction(snapshot: w.snapshot) { workflow in try workflow.createProject(name: "Локальное изменение") }
        XCTAssertTrue(p.isStale(comparedTo: changed.committed))
        let current = try await owner.exchangePreviewIsCurrent(p.generationID); XCTAssertFalse(current)
        await owner.retire()
        do { _ = try await owner.exchangePreviewIsCurrent(p.generationID); XCTFail("Retired owner") } catch {}
    }

    private func archiveParts(_ data: Data, limits: ExchangeLimits = .init()) throws -> [String: Data] {
        var archive = try ExchangeArchive(data: data, limits: limits)
        return try archive.readAll()
    }

    /// Independent tiny ZIP fixture encoder, including deliberate unsafe names/duplicates.
    private func zip(_ entries: [(key: String, value: Data)], deflated: Bool = false) throws -> Data {
        var data = Data(), central = Data()
        func word(_ n: Int, bytes: Int = 2) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
        for (name, input) in entries {
            let encoded = Data(name.utf8), offset = data.count
            let crc = Int(input.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(input.count)) })
            let payload: Data
            if deflated {
                var stream = z_stream()
                guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ExchangeImportError("fixture deflate init") }
                defer { deflateEnd(&stream) }
                var out = [UInt8](repeating: 0, count: Int(compressBound(uLong(input.count))) + 16)
                let status = input.withUnsafeBytes { source in out.withUnsafeMutableBytes { target in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(source.count)
                    stream.next_out = target.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(target.count)
                    return deflate(&stream, Z_FINISH)
                } }
                guard status == Z_STREAM_END else { throw ExchangeImportError("fixture deflate") }; payload = Data(out.prefix(Int(stream.total_out)))
            } else { payload = input }
            let local: [Data] = [word(0x04034b50, bytes: 4), word(20), word(0x800), word(deflated ? 8 : 0), word(0), word(0), word(crc, bytes: 4), word(payload.count, bytes: 4), word(input.count, bytes: 4), word(encoded.count), word(0), encoded, payload]
            for part in local { data.append(part) }
            let directory: [Data] = [word(0x02014b50, bytes: 4), word(20), word(20), word(0x800), word(deflated ? 8 : 0), word(0), word(0), word(crc, bytes: 4), word(payload.count, bytes: 4), word(input.count, bytes: 4), word(encoded.count), word(0), word(0), word(0), word(0), word(0, bytes: 4), word(offset, bytes: 4), encoded]
            for part in directory { central.append(part) }
        }
        let offset = data.count; data += central
        data += word(0x06054b50, bytes: 4) + word(0) + word(0) + word(entries.count) + word(entries.count) + word(central.count, bytes: 4) + word(offset, bytes: 4) + word(0)
        return data
    }
}

extension MappingExchangePreviewTests {
    private func regulatoryExport(_ journal: MappingJournal, identity: Bool = true, token: UUID? = nil) throws -> Data {
        let snapshot = try MappingCSVExport.prepare(journal: journal,
            selection: .init(projectID: id(1), firstDay: time, lastDay: time, timeZoneID: "UTC"),
            now: time, id: token ?? id(99), includeEnterprise: true)
        let files = try MappingExportFiles.write(snapshot, format: .enterpriseGeotechnical, includeRegulatoryIdentity: identity)
        defer { files.cleanup() }
        return try Data(contentsOf: files.urls[0])
    }

    private func editData(_ data: Data, _ transform: (String) throws -> String) throws -> Data {
        var parts = try archiveParts(data)
        let path = "xl/worksheets/sheet1.xml"
        parts[path] = try Data(transform(String(decoding: XCTUnwrap(parts[path]), as: UTF8.self)).utf8)
        return try zip(parts.sorted { $0.key < $1.key }, deflated: true)
    }

    private func cells(_ xml: String, _ replacements: [String: String]) throws -> String {
        var result = xml
        for (address, body) in replacements {
            let pattern = #"<c r="\#(address)"[^>]*?(?:/>|>.*?</c>)"#
            let range = try XCTUnwrap(result.range(of: pattern, options: .regularExpression), address)
            result.replaceSubrange(range, with: "<c r=\"\(address)\"\(body)")
        }
        return result
    }

    private func confirmedData(_ bytes: Data, committed: MappingCommittedSnapshot,
                               review: inout RegulatoryDataImport.Review) throws -> MappingExchangePreview {
        let preliminary = try RegulatoryDataImport.prepare(bytes: bytes, review: review, committed: committed)
        for record in preliminary.records where record.classification == .ambiguous && record.matchedID == nil {
            if let key = record.reviewID, record.candidates.count == 1 {
                review.matches[key] = record.candidates[0].id
            }
        }
        return try RegulatoryDataImport.prepare(bytes: bytes, review: review, committed: committed)
    }

    private func confirmedData(_ bytes: Data, committed: MappingCommittedSnapshot) throws -> MappingExchangePreview {
        var review = RegulatoryDataImport.Review()
        return try confirmedData(bytes, committed: committed, review: &review)
    }

    func testRegulatoryRoundTripRetainsEvidenceAndHistoricalSnapshots() async throws {
        var rmr = FinalFieldPolishTests.referenceInput()
        rmr.strengthTest = .ucs; rmr.strengthMPa = "180"; rmr.rqd = "80"
        rmr.basicSelections?["strength"] = "strength-1"
        rmr.basicSelections?["rqd"] = "rqd-1"
        rmr.jcond76 = JCond76Assessment(.slightlyRoughSoft)
        let memory = MappingTests.MemoryStore()
        memory.value = try fixture(includeRegulatory: true, rmr89: rmr)
        var workflow = try MappingWorkflow(store: memory)
        let rock = RockLithology(code: "004.20", name: "Туф")
        try workflow.addLithology(rock, projectID: id(1))
        var prior = try workflow.correction(for: id(7))
        prior.reason = "Сохранённая оценка GSI"
        prior.fields.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair),
            lower: 35, upper: 45, finalValue: 40, assessedAt: time)
        _ = try workflow.saveCorrection(prior, now: time.addingTimeInterval(5))
        let photoBytes = try P41PhotoTests().image()
        let attachment = PhotoAttachment(id: id(51), originalFilename: "field.jpg", sha256: ManagedPhotoStore.digest(photoBytes),
            byteCount: photoBytes.count, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1,
            orientation: 1, representation: "Exact original")
        let photo = PhotoObservation(id: id(52), attachmentID: attachment.id, context: try workflow.journal.photoContext(for: id(7)),
            source: .files, importedAt: time, capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown", metadata: .init(name: "Original"))
        let photoOp = PhotoImportOperation(version: 2, photo: photo, attachment: attachment)
        try workflow.registerPhoto(photoOp)
        let journal = workflow.journal
        let (root, owner, before) = try await makeOwner(journal)
        let files = ManagedPhotoStore(root: root.appendingPathComponent("photos"))
        try files.stage(photoBytes, for: photoOp)
        try files.promote(photoOp)
        try files.complete(photoOp)
        let workbook = try regulatoryExport(journal)
        let original = try XCTUnwrap(before.observation(id: id(7)))
        let read = try RegulatoryDataWorkbook.Read(bytes: workbook, limits: .init())
        XCTAssertEqual(read.rows[0].values.count, 30)
        XCTAssertEqual(read.rows[0].values[2], "123456789.12345679")
        XCTAssertEqual(read.rows[0].values[9], rmr.strengthMPa)
        XCTAssertEqual(read.rows[0].values[10], "80")
        XCTAssertEqual(read.rows[0].values[14], "0.125")
        XCTAssertEqual(read.rows[0].values[16], "12")
        XCTAssertEqual(read.rows[0].values[20], "0.125")
        XCTAssertEqual(read.rows[0].values[22], "120")
        XCTAssertEqual(read.rows[0].values[29], "40")
        let edited = try editData(workbook) {
            try cells($0, ["F5": " t=\"inlineStr\"><is><t>004.20</t></is></c>", "G5": "><v>3</v></c>", "I5": "><v>12</v></c>"])
        }
        let preview = try confirmedData(edited, committed: before)
        let proposal = try XCTUnwrap(preview.records.first)
        XCTAssertEqual(proposal.classification, .correction, proposal.reason)
        XCTAssertEqual(proposal.target?.observationID, original.id)
        XCTAssertEqual(proposal.visibleChanges.map(\.after), ["004.20", "3", "12"])
        let selection = MappingExchangeImport.Selection(accepted: [proposal.id])
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: edited, selection: selection, now: time)
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.applied), 1)
        XCTAssertEqual(after.journal.revisions.count, journal.revisions.count + 1)
        XCTAssertEqual(Array(after.journal.revisions.dropLast()), journal.revisions)
        XCTAssertEqual(after.journal.observations, journal.observations)
        XCTAssertEqual(after.journal.measurements, journal.measurements)
        XCTAssertEqual(after.journal.photos, journal.photos)
        XCTAssertEqual(after.journal.photoAttachments, journal.photoAttachments)
        XCTAssertEqual(try files.read(attachment), photoBytes)
        let updated = try XCTUnwrap(after.observation(id: original.id))
        XCTAssertEqual(updated.ratings?.bartonQ, original.ratings?.bartonQ)
        XCTAssertEqual(updated.ratings?.rmr89, original.ratings?.rmr89)
        XCTAssertEqual(updated.ratings?.gsi, original.ratings?.gsi)
        XCTAssertEqual(updated.geology?.jointSets.last?.identifier, .J5)
        XCTAssertEqual(updated.geology, original.geology)
        let reexport = try regulatoryExport(after.journal)
        let final = try RegulatoryDataWorkbook.Read(bytes: reexport, limits: .init()).rows[0].values
        XCTAssertEqual([final[5], final[6], final[8]], ["004.20", "3", "12"])
        XCTAssertEqual(RegulatoryDataWorkbook.protected.map { final[$0] }, RegulatoryDataWorkbook.protected.map { read.rows[0].values[$0] })
        let retry = try RegulatoryDataImport.prepare(bytes: edited, committed: after)
        let replay = try MappingExchangeImport.Batch(preview: retry, bytes: edited, selection: selection, now: time.addingTimeInterval(1))
        let (stable, repeated) = try await owner.applyExchange(replay)
        XCTAssertEqual(repeated.count(.alreadyApplied), 1)
        XCTAssertEqual(stable.journal, after.journal)
    }

    private func withOfficeParts(_ workbook: Data, extraWorksheet: Data, calcChain: Data) throws -> [String: Data] {
        var parts = try archiveParts(workbook)
        let book = "xl/workbook.xml", rels = "xl/_rels/workbook.xml.rels", types = "[Content_Types].xml"
        func insert(_ part: String, before anchor: String, _ text: String) throws {
            let xml = String(decoding: try XCTUnwrap(parts[part]), as: UTF8.self)
            XCTAssertTrue(xml.contains(anchor))
            parts[part] = Data(xml.replacingOccurrences(of: anchor, with: text + anchor).utf8)
        }
        let workbookXML = String(decoding: try XCTUnwrap(parts[book]), as: UTF8.self)
        XCTAssertTrue(workbookXML.contains("<sheets>"))
        parts[book] = Data(workbookXML.replacingOccurrences(of: "<sheets>",
            with: #"<sheets><sheet name="Filter" sheetId="14" state="hidden" r:id="filter"/>"#).utf8)
        let office = ExchangeWorkbook.documentRelationships
        try insert(rels, before: "</Relationships>", """
            <Relationship Id="filter" Type="\(office)worksheet" Target="worksheets/filter.xml"/>
            <Relationship Id="calc" Type="\(office)calcChain" Target="calcChain.xml"/>
            """)
        let content = "application/vnd.openxmlformats-officedocument.spreadsheetml."
        try insert(types, before: "</Types>", """
            <Override PartName="/xl/worksheets/filter.xml" ContentType="\(content)worksheet+xml"/>
            <Override PartName="/xl/calcChain.xml" ContentType="\(content)calcChain+xml"/>
            """)
        parts["xl/worksheets/filter.xml"] = extraWorksheet
        parts["xl/calcChain.xml"] = calcChain
        return parts
    }

    private func addSharedStrings(_ data: Data, to parts: inout [String: Data]) throws {
        let rels = "xl/_rels/workbook.xml.rels", types = "[Content_Types].xml"
        let sstType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"
        parts[rels] = Data(String(decoding: try XCTUnwrap(parts[rels]), as: UTF8.self)
            .replacingOccurrences(of: "</Relationships>", with: """
                <Relationship Id="strings" Type="\(ExchangeWorkbook.documentRelationships)sharedStrings" Target="sharedStrings.xml"/></Relationships>
                """).utf8)
        parts[types] = Data(String(decoding: try XCTUnwrap(parts[types]), as: UTF8.self)
            .replacingOccurrences(of: "</Types>", with: """
                <Override PartName="/xl/sharedStrings.xml" ContentType="\(sstType)"/></Types>
                """).utf8)
        parts["xl/sharedStrings.xml"] = data
    }

    func testRegulatorySelectiveReadSkipsLargeOfficePartsAndUsesNamedData() throws {
        let journal = try fixture()
        let book = try regulatoryExport(journal)
        let ns = ExchangeWorkbook.spreadsheet
        let auxRows = (1...15_000).map { "<row r=\"\($0)\"><c r=\"A\($0)\"><f>1+1</f><v>2</v></c></row>" }.joined()
        let chain = (1...60_000).map { "<c r=\"A\($0)\" i=\"14\"/>" }.joined()
        var parts = try withOfficeParts(book,
            extraWorksheet: Data("<worksheet xmlns=\"\(ns)\"><sheetData>\(auxRows)</sheetData></worksheet>".utf8),
            calcChain: Data("<calcChain xmlns=\"\(ns)\">\(chain)</calcChain>".utf8))
        let dataPath = "xl/worksheets/sheet1.xml"
        let data = String(decoding: try XCTUnwrap(parts[dataPath]), as: UTF8.self)
        // Office-converted dimensions can be stale. Import the actual cell addresses.
        // Formatted empty rows make the required worksheet larger and highly compressible.
        let emptyRows = (6...2500).map { "<row r=\"\($0)\"><c r=\"AD\($0)\"/></row>" }.joined()
        let revised = try cells(data, ["A4": " t=\"s\"><v>0</v></c>"])
            .replacingOccurrences(of: #"<dimension ref="[^"]*"/>"#, with: #"<dimension ref="A1"/>"#, options: .regularExpression)
            .replacingOccurrences(of: "</sheetData>", with: emptyRows + "</sheetData>")
        parts[dataPath] = Data(revised.utf8)
        XCTAssertTrue(revised.contains(#"<dimension ref="A1"/>"#))
        try addSharedStrings(Data("<sst xmlns=\"\(ns)\"><si><t>ID</t></si></sst>".utf8), to: &parts)
        let bytes = try zip(parts.sorted { $0.key < $1.key }, deflated: true)
        var limits = ExchangeLimits()
        limits.partBytes = 128 * 1024
        limits.expandedBytes = 192 * 1024
        XCTAssertGreaterThan(try XCTUnwrap(parts["xl/calcChain.xml"]).count, limits.expandedBytes)
        XCTAssertGreaterThan(try XCTUnwrap(parts["xl/worksheets/filter.xml"]).count, limits.expandedBytes)
        let parsed = try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)
        XCTAssertEqual(parsed.rows.map(\.number), [5])
        XCTAssertNotNil(parsed.manifest)
        XCTAssertEqual(try RegulatoryDataImport.prepare(bytes: bytes, committed: .init(journal), limits: limits).count(.unchanged), 1)

        limits.dataSheetBytes = try XCTUnwrap(parts[dataPath]).count - 1
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)) {
            XCTAssertTrue($0.localizedDescription.contains("Обязательный лист «Data»"), $0.localizedDescription)
        }
        limits.dataSheetBytes = 128 * 1024
        limits.expandedBytes = try XCTUnwrap(parts[dataPath]).count
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)) {
            XCTAssertTrue($0.localizedDescription.contains("Суммарный размер распаковываемых частей"), $0.localizedDescription)
        }
        limits.regulatoryDeclaredBytes = 192 * 1024
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)) {
            XCTAssertTrue($0.localizedDescription.contains("Суммарный заявленный размер"), $0.localizedDescription)
        }

        var cellLimits = ExchangeLimits()
        cellLimits.dataSheetCells = 100
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: cellLimits)) {
            XCTAssertTrue($0.localizedDescription.contains("предел ячеек листа Data"), $0.localizedDescription)
        }
        cellLimits = .init()
        cellLimits.dataSheetRetainedCells = 20
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: cellLimits)) {
            XCTAssertTrue($0.localizedDescription.contains("предел значимых ячеек листа Data"), $0.localizedDescription)
        }
    }

    func testRegulatorySkipsUnreferencedSharedStringsAndStyles() throws {
        let book = try editData(regulatoryExport(fixture(), identity: false)) { xml in
            try cells(xml, ["J5": "/>", "I5": "/>", "K5": "/>"])
                .replacingOccurrences(of: #"<v>[^<]*</v>"#, with: "", options: .regularExpression)
        }
        var parts = try archiveParts(book)
        try addSharedStrings(Data("unread shared strings".utf8), to: &parts)
        parts["xl/styles.xml"] = Data("unread styles".utf8)
        let bytes = try zip(parts.sorted { $0.key < $1.key }, deflated: true)
        XCTAssertEqual(try RegulatoryDataWorkbook.Read(bytes: bytes, limits: .init()).rows.count, 1)
    }

    func testRegulatoryRejectsPopulatedColumnsPastADAndRequiresVisibleData() async throws {
        let book = try regulatoryExport(fixture(), identity: false)
        for (row, cell) in [(4, #"<c r="AE4" t="inlineStr"><is><t>Q</t></is></c>"#),
                            (5, #"<c r="AE5" t="str"><f>1+1</f></c>"#)] {
            let invalid = try editData(book) { xml in
                let range = try XCTUnwrap(xml.range(of: #"<row r="\#(row)"[^>]*>.*?</row>"#, options: .regularExpression))
                var result = xml
                result.replaceSubrange(range, with: xml[range].replacingOccurrences(of: "</row>", with: cell + "</row>"))
                return result
            }
            XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: invalid, limits: .init())) {
                XCTAssertTrue($0.localizedDescription.contains("Data!AE\(row)"), $0.localizedDescription)
                XCTAssertTrue($0.localizedDescription.contains("Неподдерживаемая схема листа"), $0.localizedDescription)
            }
        }
        var parts = try archiveParts(book)
        let path = "xl/workbook.xml"
        parts[path] = Data(String(decoding: try XCTUnwrap(parts[path]), as: UTF8.self)
            .replacingOccurrences(of: #"name="Data""#, with: #"name="kart""#).utf8)
        let unsupported = try zip(parts.sorted { $0.key < $1.key })
        let committed = MappingCommittedSnapshot(try fixture())
        let coordinator = MappingExchangePreviewCoordinator()
        coordinator.activate(generation: committed.generationID)
        let work = MappingExchangePreviewCoordinator.Work(snapshot: { committed },
            read: { _, snapshot in try RegulatoryDataImport.prepare(bytes: unsupported, committed: snapshot) },
            isCurrent: { $0 == committed.generationID })
        let operation = try XCTUnwrap(coordinator.prepare(URL(fileURLWithPath: "/unused/legacy.xlsx"), work: work))
        await operation.task.value
        XCTAssertNil(coordinator.state.preview)
        XCTAssertTrue(try XCTUnwrap(coordinator.state.message).contains("требуется видимый лист Data"))
    }

    func testRegulatoryStreamsWorksheetAboveBufferedPartLimit() throws {
        let journal = try fixture()
        let book = try regulatoryExport(journal)
        var parts = try archiveParts(book)
        let path = "xl/worksheets/sheet1.xml"
        let source = try XCTUnwrap(parts[path])
        let closing = try XCTUnwrap(source.range(of: Data("</worksheet>".utf8)))
        // A deterministic low-entropy pattern with enough variation to keep the
        // compression ratio below the security threshold.
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
        var state: UInt32 = 42
        let comment = Data("<!--".utf8) + Data((0..<16_384).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return alphabet[Int(state >> 16) % alphabet.count]
        }) + Data("-->".utf8)
        var worksheet = Data(source[..<closing.lowerBound])
        for _ in 0..<2_100 { worksheet.append(comment) }
        worksheet.append(source[closing.lowerBound...])
        let limits = ExchangeLimits()
        XCTAssertGreaterThan(worksheet.count, limits.partBytes)
        parts[path] = worksheet
        let bytes = try zip(parts.sorted { $0.key < $1.key }, deflated: true)
        let preview = try RegulatoryDataImport.prepare(bytes: bytes, committed: .init(journal))
        XCTAssertEqual(preview.rowsProcessed, 1)
        XCTAssertEqual(preview.count(.unchanged), 1)
        XCTAssertFalse(preview.workbookBlocked)
    }

    func testProductionLayoutExposesSourceCandidateAndExclusionsBeforeAnyWrite() throws {
        let journal = try fixture()
        let book = try regulatoryExport(journal, identity: false)
        let production = try editData(book) { xml in
            var result = try cells(xml, ["B5": #" t="inlineStr"><is><t>-</t></is></c>"#,
                                         "AD5": #" t="str"><f>1+1</f><v>-</v></c>"#,
                                         "C5": #"><v>540000.10000000001</v></c>"#])
            let headers = [
                (1, #"<c r="BI1" t="inlineStr"><is><t>Ошибки в пополнении БД по картированию выработок</t></is></c>"#),
                (3, #"<c r="AI3" t="inlineStr"><is><t>№ точки наблюдения</t></is></c><c r="AJ3" t="inlineStr"><is><t>Примечание</t></is></c><c r="CP3" t="inlineStr"><is><t>Проверка угла и азимута 4 системы</t></is></c>"#),
                (4, #"<c r="AE4" t="inlineStr"><is><t>Q'</t></is></c><c r="AH4" t="inlineStr"><is><t>RMR76</t></is></c>"#)
            ]
            for (row, cells) in headers {
                let range = try XCTUnwrap(result.range(of: #"<row r="\#(row)"[^>]*>.*?</row>"#, options: .regularExpression))
                result.replaceSubrange(range, with: result[range].replacingOccurrences(of: "</row>", with: cells + "</row>"))
            }
            let placeholder = #"<row r="6"><c r="A6" t="inlineStr"><is><t>-</t></is></c><c r="AD6" t="str"><f>1+1</f><v>-</v></c><c r="AI6"><v>2</v></c></row>"#
            return result.replacingOccurrences(of: "A1:AD1", with: "A1:AJ1")
                .replacingOccurrences(of: "</sheetData>", with: placeholder + "</sheetData>")
                .replacingOccurrences(of: "</worksheet>", with: #"<conditionalFormatting sqref="A5"><cfRule type="expression" priority="1"><formula>1+1</formula></cfRule></conditionalFormatting></worksheet>"#)
        }
        let committed = MappingCommittedSnapshot(journal)
        let preview = try RegulatoryDataImport.prepare(bytes: production, committed: committed)
        XCTAssertTrue(preview.workbookBlocked)
        XCTAssertEqual(preview.worksheetRowsScanned, 6)
        XCTAssertEqual(preview.rowsProcessed, 1)
        XCTAssertEqual(preview.productionInput?.rows.first?.number, 5)
        XCTAssertEqual(preview.productionInput?.rows.first?.values[2], "540000.10000000001")
        XCTAssertEqual(preview.productionInput?.rows.first?.issues, [])
        XCTAssertFalse(preview.records.contains(where: \.canApply))
        XCTAssertTrue(preview.workbookBlockReasons.contains { $0.contains("Data!A3:A4") })
        XCTAssertTrue(preview.workbookBlockReasons.contains { $0.contains("AE:AH") && $0.contains("BI:CP") })
        XCTAssertThrowsError(try MappingExchangeImport.Batch(preview: preview, bytes: production,
            selection: .init(accepted: Set(preview.records.map(\.id))), now: time))
        XCTAssertEqual(committed.journal, journal)
    }

    func testWorksheetStreamRejectsSplitDTDAndCorruptFinalCRC() throws {
        let journal = try fixture()
        let book = try regulatoryExport(journal)
        let malicious = try editData(book) { xml in
            let root = try XCTUnwrap(xml.range(of: "<worksheet"))
            return String(repeating: " ", count: 1020) + "<!DOCTYPE worksheet>" + xml[root.lowerBound...]
        }
        XCTAssertThrowsError(try RegulatoryDataWorkbook.Read(bytes: malicious, limits: .init())) {
            XCTAssertTrue($0.localizedDescription.contains("DTD"), $0.localizedDescription)
        }

        // The archive directory is consistent. The CRC still has to be checked
        // at the end of the decoded stream, beyond the XML prefix.
        let xml = Data(("<worksheet><!--" + String(repeating: "x", count: 95_000) + "--></worksheet>").utf8)
        var invalid = try zip([("data.xml", xml)], deflated: true)
        let central = try XCTUnwrap(invalid.range(of: Data([0x50, 0x4b, 0x01, 0x02]))).lowerBound
        invalid[14] ^= 1
        invalid[central + 16] ^= 1
        var archive = try ExchangeArchive(data: invalid, limits: .init(), regulatory: true)
        let stream = try archive.streamDataSheet("data.xml")
        _ = try stream.preparePrefix()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 32_768)
        var count = 0
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            count += read
        }
        XCTAssertGreaterThan(count, 32_768)
        XCTAssertThrowsError(try stream.verifyCompletion()) {
            XCTAssertTrue($0.localizedDescription.contains("CRC-32"), $0.localizedDescription)
        }
    }

    func testSelectiveZIPRejectsSkippedEntryRatioAndRequiredPartOverrun() throws {
        var limits = ExchangeLimits()
        let bomb = try zip([("xl/calcChain.xml", Data(repeating: 65, count: 2 * 1024 * 1024))], deflated: true)
        XCTAssertThrowsError(try ExchangeArchive(data: bomb, limits: limits, regulatory: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Коэффициент сжатия"), $0.localizedDescription)
        }
        limits.fileBytes = bomb.count - 1
        XCTAssertThrowsError(try ExchangeArchive(data: bomb, limits: limits, regulatory: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Размер сжатого файла"), $0.localizedDescription)
        }

        // A one-entry archive with matching local/central sizes that understate output.
        var malformed = try zip([("required.xml", Data("<xml/>".utf8))], deflated: true)
        let central = try XCTUnwrap(malformed.range(of: Data([0x50, 0x4b, 0x01, 0x02]))).lowerBound
        malformed[22] = 5
        malformed[central + 24] = 5
        var archive = try ExchangeArchive(data: malformed, limits: .init(), regulatory: true)
        XCTAssertThrowsError(try archive.read("required.xml")) {
            XCTAssertTrue($0.localizedDescription.contains("DEFLATE"), $0.localizedDescription)
        }
        malformed[6] |= 1
        malformed[central + 8] |= 1
        XCTAssertThrowsError(try ExchangeArchive(data: malformed, limits: .init(), regulatory: true))
    }

    func testRegulatoryStructuralAndCellDiagnostics() throws {
        let journal = try fixture(includeRegulatory: true)
        let committed = MappingCommittedSnapshot(journal)
        let book = try regulatoryExport(journal)
        for edit in [["AD4": "/>"], ["A4": " t=\"inlineStr\"><is><t>PK</t></is></c>", "B4": " t=\"inlineStr\"><is><t>ID</t></is></c>"],
                     ["B4": " t=\"inlineStr\"><is><t>ID</t></is></c>"]] {
            let malformed = try editData(book) { try cells($0, edit) }
            XCTAssertThrowsError(try RegulatoryDataImport.prepare(bytes: malformed, committed: committed)) {
                XCTAssertTrue($0.localizedDescription.contains("несовместимые заголовки"), $0.localizedDescription)
            }
        }
        let invalidXML = try editData(book) { $0.replacingOccurrences(of: "</worksheet>", with: "</unknown>") }
        XCTAssertThrowsError(try RegulatoryDataImport.prepare(bytes: invalidXML, committed: committed)) {
            XCTAssertTrue($0.localizedDescription.contains("Некорректный XML XLSX"), $0.localizedDescription)
        }
        for (address, body) in [
            ("G5", "><f>1+2</f><v>3</v></c>"), ("G5", "><v>2</v></c>"),
            ("I5", "><v>7.0000000000000001</v></c>"), ("F5", "><v>4.2</v></c>"),
            ("F5", " t=\"inlineStr\"><is><t>00000</t></is></c>"), ("I5", " t=\"d\"><v>2026-11-11</v></c>"),
            ("O5", "><v>0.25</v></c>"), ("C5", "><v>123456789.123457</v></c>")
        ] {
            let edited = try editData(book) { try cells($0, [address: body]) }
            let preview = try confirmedData(edited, committed: committed)
            let record = try XCTUnwrap(preview.records.first)
            XCTAssertFalse(record.canApply)
            XCTAssertTrue(record.reason.contains("Data!\(address)"), record.reason)
        }
        let duplicate = try editData(book) { xml in
            let range = try XCTUnwrap(xml.range(of: #"<row r="5"[^>]*>.*?</row>"#, options: .regularExpression))
            let copy = String(xml[range]).replacingOccurrences(of: #"r="([A-Z]*)5""#, with: #"r="$1X""#, options: .regularExpression)
            return xml.replacingOccurrences(of: "</sheetData>", with: copy.replacingOccurrences(of: "X\"", with: "6\"") + "</sheetData>")
        }
        let preview = try RegulatoryDataImport.prepare(bytes: duplicate, committed: committed)
        XCTAssertEqual(preview.rowsProcessed, 2)
        XCTAssertEqual(preview.count(.duplicate), 1)
        XCTAssertFalse(preview.records.contains(where: \.canApply))
    }

    func testRegulatoryLegacyRequiresExplicitMatchAndClearingIsExplicit() throws {
        let journal = try fixture(includeRegulatory: true)
        var ambiguous = journal
        ambiguous.observations.append(try patched(journal.observations[0], fields: [
            "id": "\"\(id(70))\"", "measurementIDs": "[]", "geology": "null"
        ]))
        try ambiguous.validate()
        let current = MappingCommittedSnapshot(ambiguous)
        let book = try regulatoryExport(journal, identity: false)
        var package = try archiveParts(book)
        let core = "docProps/core.xml"
        let metadata = String(decoding: try XCTUnwrap(package[core]), as: UTF8.self)
        package[core] = Data(metadata.replacingOccurrences(of: #"<dc:identifier>.*?</dc:identifier>"#,
            with: "", options: .regularExpression).utf8)
        let anonymous = try zip(package.sorted { $0.key < $1.key }, deflated: true)
        XCTAssertNil(try RegulatoryDataWorkbook.Read(bytes: anonymous, limits: .init()).documentID)
        let edited = try editData(anonymous) { try cells($0, ["G5": " t=\"inlineStr\"><is><t>#CLEAR</t></is></c>", "I5": "/>"]) }
        let preview = try RegulatoryDataImport.prepare(bytes: edited, committed: current)
        let record = try XCTUnwrap(preview.records.first)
        XCTAssertEqual(record.classification, .ambiguous)
        XCTAssertEqual(Set(record.candidates.map(\.id)), [id(7), id(70)])
        XCTAssertNil(record.proposed)
        let wrong = try RegulatoryDataImport.prepare(bytes: edited, matches: [record.id: id(71)], committed: current)
        XCTAssertEqual(wrong.count(.ambiguous), 1)
        let correct = try RegulatoryDataImport.prepare(bytes: edited, matches: [record.id: id(7)], committed: current)
        let proposal = try XCTUnwrap(correct.records[0].proposed, correct.records[0].reason)
        XCTAssertNil(proposal.ratings?.regulatory?.wallAlteration)
        XCTAssertEqual(proposal.ratings?.regulatory?.strength, .below1)
    }

    func testRegulatoryFaultRowsRequireOneConsistentObservationProposal() throws {
        let memory = MappingTests.MemoryStore(); memory.value = try fixture()
        var workflow = try MappingWorkflow(store: memory)
        var correction = try workflow.correction(for: id(7))
        correction.reason = "Вторая структура"
        var fault = TectonicStructureDraft(id: id(50))
        fault.description = "Второй разлом"; fault.thickness = "0.25"
        correction.fields.tectonicStructures.append(fault)
        _ = try workflow.saveCorrection(correction, now: time.addingTimeInterval(5))
        let current = MappingCommittedSnapshot(workflow.journal)
        let book = try regulatoryExport(workflow.journal)
        let consistent = try editData(book) { try cells($0, ["I5": "><v>4</v></c>", "I6": "><v>4</v></c>"]) }
        let accepted = try confirmedData(consistent, committed: current)
        XCTAssertEqual(accepted.rowsProcessed, 2)
        XCTAssertEqual(accepted.count(.correction), 1)
        XCTAssertEqual(accepted.records.first?.proposed?.geology?.tectonicStructures.count, 2)
        let divergent = try editData(consistent) { try cells($0, ["I6": "><v>7</v></c>"]) }
        let refused = try confirmedData(divergent, committed: current)
        XCTAssertFalse(refused.records.contains(where: \.canApply))
        let missing = try editData(consistent) {
            $0.replacingOccurrences(of: #"<row r="6"[^>]*>.*?</row>"#, with: "", options: .regularExpression)
        }
        let incomplete = try confirmedData(missing, committed: current)
        XCTAssertEqual(incomplete.count(.invalid), 1)
    }

    func testRegulatoryStaleManifestAndApplyTimeRevisionConflict() async throws {
        let journal = try fixture()
        let (_, owner, before) = try await makeOwner(journal)
        let book = try regulatoryExport(journal)
        let edited = try editData(book) { try cells($0, ["I5": "><v>7</v></c>"]) }
        var decisions = RegulatoryDataImport.Review()
        let p = try confirmedData(edited, committed: before, review: &decisions)
        let selection = MappingExchangeImport.Selection(accepted: Set(p.records.map(\.id)))
        let batch = try MappingExchangeImport.Batch(preview: p, bytes: edited, selection: selection, now: time)
        XCTAssertThrowsError(try MappingExchangeImport.Batch(preview: p, bytes: book, selection: selection, now: time))
        let exchange = try bytes(correction(export(journal), note: "Новое полевое наблюдение"))
        let exchangePreview = try MappingExchangePreview.prepare(data: exchange, committed: before)
        let local = try MappingExchangeImport.Batch(preview: exchangePreview, bytes: exchange,
            selection: .init(accepted: [id(7).uuidString]), now: time.addingTimeInterval(10))
        let (newer, _) = try await owner.applyExchange(local)
        let stale = try RegulatoryDataImport.prepare(bytes: edited, review: decisions, committed: newer)
        XCTAssertEqual(stale.count(.conflict), 1)
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.rejected), 1)
        XCTAssertEqual(after.journal.revisions, newer.journal.revisions)
        let conflict = try XCTUnwrap(stale.records.first)
        XCTAssertTrue(conflict.regulatoryActions?.canResolveConflict == true)
        XCTAssertEqual(conflict.visibleChanges.first?.after, "7")
        decisions.takeExcelChanges[try XCTUnwrap(conflict.reviewID)] = try XCTUnwrap(conflict.graphFingerprint)
        let resolved = try RegulatoryDataImport.prepare(bytes: edited, review: decisions, committed: after)
        XCTAssertEqual(resolved.count(.correction), 1)
        XCTAssertEqual(resolved.records[0].proposed?.notes, "Новое полевое наблюдение")
        let approved = try MappingExchangeImport.Batch(preview: resolved, bytes: edited,
            selection: .init(accepted: [resolved.records[0].id]), now: time.addingTimeInterval(20))
        let (final, result) = try await owner.applyExchange(approved)
        XCTAssertEqual(result.count(.applied), 1)
        XCTAssertEqual(final.journal.revisions.count, newer.journal.revisions.count + 1)
    }

    func testRegulatoryPartialFailureAndPendingRecoveryUseOneLedger() async throws {
        let journal = try threePoints(fixture())
        let (root, owner, before) = try await makeOwner(journal)
        let book = try regulatoryExport(journal)
        let edited = try editData(book) { try cells($0, ["I5": "><v>2</v></c>", "I6": "><v>4</v></c>", "I7": "><v>5</v></c>"]) }
        var decisions = RegulatoryDataImport.Review()
        let p = try confirmedData(edited, committed: before, review: &decisions)
        XCTAssertEqual(p.count(.correction), 2)
        XCTAssertEqual(p.count(.invalid), 1)
        let selection = MappingExchangeImport.Selection(accepted: Set(p.records.map(\.id)))
        let batch = try MappingExchangeImport.Batch(preview: p, bytes: edited, selection: selection, now: time)
        let interruptedID = id(60)
        let (partial, report) = try await owner.applyExchange(batch) { operation, checkpoint in
            if operation.target.observationID == interruptedID, case .afterIntent = checkpoint { throw Interrupted.simulated }
        }
        XCTAssertTrue(report.interrupted)
        XCTAssertEqual(report.count(.applied), 1)
        XCTAssertEqual(report.count(.pending), 1)
        XCTAssertEqual(report.count(.rejected), 1)
        XCTAssertEqual(partial.journal.revisions.count, journal.revisions.count + 1)
        let reopened = MappingStorageOwner()
        let mappingURL = root.appendingPathComponent("mapping.json")
        let workflow = try await reopened.open { FileMappingStore(url: mappingURL) }
        let recovery = try await reopened.importRecovery()
        XCTAssertEqual(recovery.count, 1)
        XCTAssertNil(recovery[0].conflict)
        let checked = try RegulatoryDataImport.prepare(bytes: edited, review: decisions, committed: workflow.committed)
        let retry = try MappingExchangeImport.Batch(preview: checked, bytes: edited, selection: selection, now: time.addingTimeInterval(99))
        let (done, results) = try await reopened.applyExchange(retry)
        XCTAssertFalse(results.interrupted)
        XCTAssertEqual(results.count(.applied), 1)
        XCTAssertEqual(results.count(.alreadyApplied), 1)
        XCTAssertEqual(results.count(.rejected), 1)
        XCTAssertEqual(done.latestRevisions[id(60)]?.correctedAt, time)
        XCTAssertNil(done.latestRevisions[id(61)])
    }
}

extension MappingExchangePreviewTests {
    private func appendDataRows(_ bytes: Data, rows: [[String: MappingCSVExport.Cell]], start: Int) throws -> Data {
        try editData(bytes) { xml in
            let newRows = try rows.enumerated().map { offset, row in
                let number = start + offset
                let contents = try row.sorted { $0.key < $1.key }.map { column, value in
                    try MappingXLSXExport.cell(value, reference: "\(column)\(number)", style: 0, fieldNumeric: true)
                }.joined()
                return "<row r=\"\(number)\">" + contents + "</row>"
            }.joined()
            let last = start + rows.count - 1
            return xml.replacingOccurrences(of: "</sheetData>", with: newRows + "</sheetData>")
                .replacingOccurrences(of: #"(<(?:dimension|autoFilter) ref="[A-Z0-9]+:AD)[0-9]+"#, with: "$1" + "LASTROW", options: .regularExpression)
                .replacingOccurrences(of: "LASTROW", with: String(last))
        }
    }

    private func assignmentForData(plan: UUID? = nil) -> RegulatoryDataProposal.Assignment {
        .init(projectID: id(1), horizonID: id(3), observedAt: time, zoneID: "UTC", convention: .tenMeters,
              chainageOrigin: "От устья на север", planID: plan, north: .gridNorth)
    }

    private func operationalJournal() throws -> (MappingJournal, MappingPlanReference, MappingPlanReference) {
        var journal = MappingJournal()
        journal.projects = [.init(id: id(1), name: "Шахта",
            lithologies: [.init(code: "001.20", name: "Туф")])]
        journal.horizons = [.init(id: id(3), projectID: id(1), name: "Основной", elevationMeters: nil, elevationDatum: "mine"),
                            .init(id: id(4), projectID: id(1), name: "Другой", elevationMeters: nil, elevationDatum: "mine")]
        journal.excavations = [.init(id: id(5), projectID: id(1), name: "Штрек", horizonIDs: [id(3)]),
                               .init(id: id(6), projectID: id(1), name: "Штрек", horizonIDs: [id(4)])]
        let dxf = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n30\n0\n11\n1000\n21\n0\n31\n0\n")
        let file = ManagedPlanFile(originalFilename: "horizon.dxf", sha256: ManagedPlanStore.digest(dxf), byteCount: dxf.count,
            importedAt: time, units: .meters, crs: "Mine grid", axes: "WCS XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: nil)
        let plan = MappingPlanReference(id: id(40), horizonID: id(3), attachmentID: id(41), version: "A", file: file)
        let other = MappingPlanReference(id: id(42), horizonID: id(4), attachmentID: id(43), version: "B", file: file)
        journal.plans = [plan, other]
        for index in 0..<100 {
            journal.observations.append(MappingObservation(id: id(1000 + index), projectID: id(1), horizonID: id(3),
                excavationID: id(5), picket: "ПК \(index)", chainageMeters: Double(index * 10),
                chainageOriginAndDirection: "От устья на север", observedAt: time, observedTimeZoneID: "UTC", observedUTCOffsetSeconds: 0,
                createdAt: time, updatedAt: time, coordinates: nil, measurementIDs: [], notes: "", geology: nil, picketConvention: .tenMeters))
        }
        try journal.validate()
        return (journal, plan, other)
    }

    func testRegulatoryOperationalWorkbookAdds20Revises5AndResumesAfterRestart() async throws {
        let (journal, plan, otherPlan) = try operationalJournal()
        let (root, owner, before) = try await makeOwner(journal)
        let book = try regulatoryExport(journal)
        let legacy = try regulatoryExport(journal, identity: false)
        let dataPart = "xl/worksheets/sheet1.xml"
        let package = try archiveParts(book)
        XCTAssertEqual(package[dataPart], try archiveParts(legacy)[dataPart])
        XCTAssertTrue(String(decoding: try XCTUnwrap(package["xl/workbook.xml"]), as: UTF8.self).contains("state=\"hidden\""))
        let source = try RegulatoryDataWorkbook.Read(bytes: book, limits: .init())
        XCTAssertEqual(source.rows.count, 100)
        XCTAssertEqual(source.manifest?.bindings.count, 100)
        let edited = try editData(book) { xml in
            try cells(xml, [
                "B5": " t=\"inlineStr\"><is><t>ПК 0+5</t></is></c>", "F6": " t=\"inlineStr\"><is><t>001.20</t></is></c>",
                "J7": "><v>120</v></c>", "K8": "><v>75</v></c>", "V9": "><v>40</v></c>", "W9": "><v>112</v></c>"
            ])
        }
        var rows: [[String: MappingCSVExport.Cell]] = (100..<120).map { index in
            ["A": .text("Штрек"), "B": .text("ПК \(index)"), "C": .number(Double(index)), "D": .number(25),
             "E": .number(-120), "F": .text("001.20"), "G": .integer(0), "H": .number(1),
             "I": .integer(7), "J": .number(125), "K": .number(80), "L": .number(9), "M": .number(3), "N": .number(2),
             "P": .integer(4), "Q": .integer(12), "R": .integer(4), "S": .number(45), "T": .number(110),
             "U": .number(0.35), "V": .number(40), "W": .number(120)]
        }
        rows[19].removeValue(forKey: "D")
        let newRows = try appendDataRows(edited, rows: rows, start: 105)
        let ns = ExchangeWorkbook.spreadsheet
        let office = try withOfficeParts(newRows,
            extraWorksheet: Data("<worksheet xmlns=\"\(ns)\"><sheetData/></worksheet>".utf8),
            calcChain: Data("<calcChain xmlns=\"\(ns)\"/>".utf8))
        let expanded = try zip(office.sorted { $0.key < $1.key }, deflated: true)
        var review = RegulatoryDataImport.Review()
        review.assignment = assignmentForData(plan: plan.id)
        let uncertain = try RegulatoryDataImport.prepare(bytes: expanded, review: review, committed: before)
        let editedPicket = try XCTUnwrap(uncertain.records.first)
        XCTAssertEqual(editedPicket.classification, .ambiguous)
        for (index, record) in uncertain.records.prefix(5).enumerated() {
            let target = id(1000 + index)
            XCTAssertTrue(record.candidates.contains { $0.id == target })
            review.matches[try XCTUnwrap(record.reviewID)] = target
        }
        for record in uncertain.records.suffix(20) {
            XCTAssertTrue(record.regulatoryActions?.canCreateSeparately == true)
            review.createSeparately.insert(try XCTUnwrap(record.reviewID))
        }
        let preview = try RegulatoryDataImport.prepare(bytes: expanded, review: review, committed: before)
        XCTAssertEqual(preview.rowsProcessed, 120)
        XCTAssertEqual(preview.count(.new), 20, preview.records.filter { $0.classification == .invalid }.map(\.reason).joined(separator: "\n"))
        XCTAssertEqual(preview.count(.correction), 5)
        XCTAssertEqual(preview.count(.unchanged), 95)
        let eligible = preview.records.filter(\.canApply)
        let selection = MappingExchangeImport.Selection(accepted: Set(eligible.map(\.id)))
        let interruptedID = try XCTUnwrap(eligible.filter { $0.classification == .new }[1].target?.observationID)
        let date = time.addingTimeInterval(30)
        let batch = try MappingExchangeImport.Batch(preview: preview, bytes: expanded, selection: selection, now: date)
        let (partial, firstReport) = try await owner.applyExchange(batch) { op, checkpoint in
            if op.target.observationID == interruptedID, case .afterIntent = checkpoint { throw Interrupted.simulated }
        }
        XCTAssertEqual(partial.effectiveObservations.count, 101)
        XCTAssertEqual(firstReport.count(.pending), 1)
        XCTAssertEqual(partial.journal.revisions.count, 5)
        let reopened = MappingStorageOwner()
        let reopenedFile = root.appendingPathComponent("mapping.json")
        let reopenedWorkflow = try await reopened.open { FileMappingStore(url: reopenedFile) }
        let pending = try await reopened.importRecovery()
        XCTAssertEqual(pending.first?.operation.target.observationID, interruptedID)
        let withoutAssignment = try RegulatoryDataImport.prepare(bytes: expanded, committed: reopenedWorkflow.committed)
        XCTAssertEqual(withoutAssignment.records.first { $0.target?.observationID == interruptedID }?.canApply, true)
        let rechecked = try RegulatoryDataImport.prepare(bytes: expanded, review: review, committed: reopenedWorkflow.committed)
        let retry = try MappingExchangeImport.Batch(preview: rechecked, bytes: expanded,
            selection: .init(accepted: Set(rechecked.records.filter(\.canApply).map(\.id))), now: date.addingTimeInterval(60))
        let (consolidated, report) = try await reopened.applyExchange(retry)
        XCTAssertFalse(report.interrupted)
        XCTAssertEqual(consolidated.effectiveObservations.count, 120)
        XCTAssertEqual(consolidated.journal.revisions.count, 5)
        XCTAssertEqual(consolidated.journal.observations.prefix(100), journal.observations[...])
        let created = Array(consolidated.journal.observations.dropFirst(100))
        XCTAssertTrue(created.allSatisfy { $0.projectID == id(1) && $0.horizonID == id(3) && $0.excavationID == id(5) })
        XCTAssertEqual(consolidated.points(on: plan, excavationID: id(5)).count, 19)
        XCTAssertTrue(consolidated.points(on: otherPlan, excavationID: nil).isEmpty)
        XCTAssertEqual(consolidated.journal.plans, [plan, otherPlan])
        XCTAssertEqual(created[0].ratings?.rmr89?.input.jcond76?.rating, 12)
        XCTAssertEqual(created[0].ratings?.bartonQ?.input.rqdSource, .externalReport)
        XCTAssertNil(created[0].ratings?.bartonQ?.evaluation.result)
        XCTAssertEqual(created[0].geology?.tectonicStructures.first?.thicknessMeters, 0.35)
        XCTAssertEqual(created[0].geology?.jointSets.first?.representative.reference, .gridNorth)
        let reexport = try regulatoryExport(consolidated.journal, token: id(98))
        let verified = try RegulatoryDataImport.prepare(bytes: reexport, committed: consolidated)
        XCTAssertEqual(verified.count(.unchanged), 120)
        XCTAssertFalse(verified.records.contains(where: \.canApply))
        let repeatSource = try RegulatoryDataImport.prepare(bytes: expanded, committed: consolidated)
        let replay = try MappingExchangeImport.Batch(preview: repeatSource, bytes: expanded, selection: .init(), now: date)
        let (stable, repeated) = try await reopened.applyExchange(replay)
        XCTAssertEqual(repeated.count(.alreadyApplied), 25)
        XCTAssertEqual(stable.journal, consolidated.journal)
        let disk = try FileMappingStore(url: reopenedFile).load()
        XCTAssertEqual(disk, consolidated.journal)
    }

    func testRegulatoryLegacyCreationGroupsFaultsAndRetainsUnboundCoordinates() async throws {
        var (journal, plan, _) = try operationalJournal()
        journal.observations = []
        journal.projects[0].lithologies?.append(.init(code: "1.2", name: "Другой код"))
        let (_, owner, before) = try await makeOwner(journal)
        let legacy = try regulatoryExport(journal, identity: false)
        let added = try appendDataRows(legacy, rows: [
            ["A": .text("Штрек"), "B": .text("2+5"), "C": .number(12), "D": .number(30), "F": .number(1.2), "S": .number(40), "T": .number(0)],
            ["A": .text("Штрек"), "B": .text("2+5"), "C": .number(12), "D": .number(30), "F": .number(1.2), "S": .number(65), "T": .number(140)]
        ], start: 5)
        XCTAssertNil(try RegulatoryDataWorkbook.Read(bytes: added, limits: .init()).manifest)
        var review = RegulatoryDataImport.Review()
        review.assignment = assignmentForData()
        let first = try RegulatoryDataImport.prepare(bytes: added, review: review, committed: before)
        let ambiguous = try XCTUnwrap(first.records.first)
        XCTAssertEqual(ambiguous.classification, .ambiguous)
        XCTAssertTrue(ambiguous.regulatoryActions?.canGroup == true)
        review.groupFaults.insert(try XCTUnwrap(ambiguous.reviewID))
        let catalogue = try RegulatoryDataImport.prepare(bytes: added, review: review, committed: before)
        let rock = try XCTUnwrap(catalogue.records.first?.regulatoryActions)
        XCTAssertEqual(Set(rock.rockChoices.map(\.code)), ["001.20", "1.2"])
        review.rockCodes[try XCTUnwrap(rock.rockKey)] = "001.20"
        let prepared = try RegulatoryDataImport.prepare(bytes: added, review: review, committed: before)
        let proposed = try XCTUnwrap(prepared.records.first)
        XCTAssertEqual(proposed.classification, .new, proposed.reason)
        XCTAssertEqual(proposed.proposed?.chainageMeters, 25)
        XCTAssertEqual(proposed.proposed?.geology?.tectonicStructures.count, 2)
        XCTAssertTrue(proposed.reason.contains("подтвердите систему XY"))
        let batch = try MappingExchangeImport.Batch(preview: prepared, bytes: added, selection: .init(accepted: [proposed.id]), now: time)
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.applied), 1)
        XCTAssertEqual(after.effectiveObservations.count, 1)
        XCTAssertEqual(after.effectiveObservations.first?.coordinates?.x, 12)
        XCTAssertEqual(after.effectiveObservations.first?.rock?.code, "001.20")
        XCTAssertTrue(after.points(on: plan, excavationID: nil).isEmpty)
        let resaved = try editData(added) { $0 + "\n" }
        let ambiguousReplay = try RegulatoryDataImport.prepare(bytes: resaved, review: review, committed: after)
        XCTAssertEqual(ambiguousReplay.count(.ambiguous), 1)
        XCTAssertFalse(ambiguousReplay.records.contains(where: \.canApply))
        review.matches[try XCTUnwrap(ambiguousReplay.records[0].reviewID)] = after.effectiveObservations[0].id
        let reviewedReplay = try RegulatoryDataImport.prepare(bytes: resaved, review: review, committed: after)
        XCTAssertEqual(reviewedReplay.count(.unchanged), 1)
    }
}

extension MappingExchangePreviewTests {
    private func movedDataRow(_ xml: String, to number: Int) -> String {
        xml.replacingOccurrences(of: #"\br="([A-Z]*)[0-9]+""#, with: #"r="$1__ROW__""#, options: .regularExpression)
            .replacingOccurrences(of: "__ROW__", with: String(number))
    }

    private func reorderData(_ workbook: Data, order: [Int]) throws -> Data {
        try editData(workbook) { xml in
            let pattern = try NSRegularExpression(pattern: #"<row r="([0-9]+)"[^>]*>.*?</row>"#, options: [.dotMatchesLineSeparators])
            let source = xml as NSString
            let fragments = pattern.matches(in: xml, range: NSRange(location: 0, length: source.length)).compactMap { match
                -> (number: Int, xml: String, range: NSRange)? in
                guard let number = Int(source.substring(with: match.range(at: 1))), number > 4 else { return nil }
                return (number, source.substring(with: match.range), match.range)
            }
            XCTAssertEqual(Set(fragments.map(\.number)), Set(order))
            let first = try XCTUnwrap(fragments.first), last = try XCTUnwrap(fragments.last)
            let rows = Dictionary(uniqueKeysWithValues: fragments.map { ($0.number, $0.xml) })
            let replacement = try order.enumerated().map { offset, original in
                movedDataRow(try XCTUnwrap(rows[original]), to: offset + 5)
            }.joined()
            let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
            return source.replacingCharacters(in: range, with: replacement)
        }
    }

    func testRegulatoryInsertedAndSortedRowsNeverReuseAnOccupiedOriginalSlot() async throws {
        var (journal, plan, otherPlan) = try operationalJournal()
        journal.observations = Array(journal.observations.prefix(3))
        // Two observations share A/B across horizons. Only A1 distinguishes their Data rows.
        journal.observations[0].ratings = MappingRatings(bartonQ: nil, rmr89: nil,
            regulatory: .init(strength: .from5To25))
        var other = try patched(journal.observations[0], fields: [
            "id": "\"\(id(2000))\"", "horizonID": "\"\(id(4))\"", "excavationID": "\"\(id(6))\""
        ])
        other.ratings = MappingRatings(bartonQ: nil, rmr89: nil, regulatory: .init(strength: .from50To100))
        journal.observations.append(other)
        let (_, owner, before) = try await makeOwner(journal)
        let book = try regulatoryExport(journal)
        let edited = try editData(book) { try cells($0, ["I8": "><v>12</v></c>"]) }
        let inserted = try appendDataRows(edited, rows: [
            ["A": .text("Штрек"), "B": .text("ПК 55"), "C": .number(111), "D": .number(222)]
        ], start: 9)
        // Excel sorts full rows, leaving the separate hidden sheet unchanged.
        let sorted = try reorderData(inserted, order: [8, 9, 7, 5, 6])
        let hidden = "xl/worksheets/sheet2.xml"
        XCTAssertEqual(try archiveParts(sorted)[hidden],
                       try archiveParts(book)[hidden])
        var review = RegulatoryDataImport.Review()
        review.assignment = assignmentForData(plan: plan.id)
        let initial = try RegulatoryDataImport.prepare(bytes: sorted, review: review, committed: before)
        let ambiguous = try XCTUnwrap(initial.records.first)
        XCTAssertEqual(ambiguous.classification, .ambiguous)
        XCTAssertEqual(Set(ambiguous.candidates.map(\.id)), [id(1000), id(2000)])
        XCTAssertNil(ambiguous.target)
        XCTAssertEqual(initial.count(.unchanged), 3)
        XCTAssertEqual(initial.count(.new), 1)
        let relabelled = try editData(sorted) {
            try cells($0, ["B7": " t=\"inlineStr\"><is><t>ПК 95</t></is></c>"])
        }
        let unsettled = try RegulatoryDataImport.prepare(bytes: relabelled, review: review, committed: before)
        let movedAndRenamed = try XCTUnwrap(unsettled.records.first { $0.location == "Data · строки 7" })
        XCTAssertEqual(movedAndRenamed.classification, .ambiguous)
        XCTAssertFalse(movedAndRenamed.canApply)
        XCTAssertEqual(movedAndRenamed.regulatoryActions?.canCreateSeparately, true)
        let sharedAnchorChanged = try editData(sorted) {
            try cells($0, ["B5": " t=\"inlineStr\"><is><t>ПК 96</t></is></c>"])
        }
        let sharedAnchor = try RegulatoryDataImport.prepare(bytes: sharedAnchorChanged, review: review, committed: before)
        XCTAssertEqual(sharedAnchor.records.first?.classification, .ambiguous)
        XCTAssertFalse(sharedAnchor.records.first?.canApply ?? true)
        review.matches[try XCTUnwrap(ambiguous.reviewID)] = id(2000)
        let ready = try RegulatoryDataImport.prepare(bytes: sorted, review: review, committed: before)
        XCTAssertEqual(ready.count(.correction), 1)
        XCTAssertEqual(ready.records[0].target?.observationID, id(2000))
        let batch = try MappingExchangeImport.Batch(preview: ready, bytes: sorted,
            selection: .init(accepted: Set(ready.records.filter(\.canApply).map(\.id))), now: time.addingTimeInterval(1))
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.applied), 2)
        XCTAssertEqual(after.effectiveObservations.count, 5)
        XCTAssertEqual(after.journal.revisions.count, 1)
        XCTAssertEqual(after.observation(id: id(1000)), journal.observations[0])
        XCTAssertEqual(after.observation(id: id(2000))?.ratings?.regulatory?.strength, .from100To250)
        XCTAssertEqual(after.points(on: plan, excavationID: id(5)).map(\.displayPicket), ["ПК 55"])
        XCTAssertTrue(after.points(on: otherPlan, excavationID: nil).isEmpty)
        let reexport = try regulatoryExport(after.journal, token: id(98))
        let reordered = try reorderData(reexport, order: [9, 8, 7, 6, 5])
        let replay = try RegulatoryDataImport.prepare(bytes: reordered, committed: after)
        XCTAssertEqual(replay.count(.unchanged), 5)
        XCTAssertFalse(replay.records.contains(where: \.canApply))
        let checked = try MappingExchangeImport.Batch(preview: replay, bytes: reordered, selection: .init(), now: time)
        let (stable, _) = try await owner.applyExchange(checked)
        XCTAssertEqual(stable.journal, after.journal)
    }

    func testRegulatoryReorderedFaultsRetainIDsAndChangedFaultRequiresAChoice() async throws {
        let memory = MappingTests.MemoryStore(); memory.value = try fixture()
        var workflow = try MappingWorkflow(store: memory)
        var correction = try workflow.correction(for: id(7))
        correction.reason = "Вторая структура"
        var fault = TectonicStructureDraft(id: id(50))
        fault.orientation = .init(dipAngleText: "45", dipDirectionText: "120", reference: .gridNorth)
        fault.thickness = "0.25"; fault.description = "Второй разлом"
        correction.fields.tectonicStructures.append(fault)
        _ = try workflow.saveCorrection(correction, now: time.addingTimeInterval(1))
        let (_, owner, before) = try await makeOwner(workflow.journal)
        let book = try regulatoryExport(workflow.journal)
        let reordered = try reorderData(book, order: [6, 5])
        let unchanged = try RegulatoryDataImport.prepare(bytes: reordered, committed: before)
        XCTAssertEqual(unchanged.count(.unchanged), 1)
        let expanded = try editData(book) { xml in
            let source = try XCTUnwrap(xml.range(of: #"<row r="6"[^>]*>.*?</row>"#, options: .regularExpression))
            let third = movedDataRow(String(xml[source]), to: 7)
            let edited = xml.replacingOccurrences(of: "</sheetData>", with: third + "</sheetData>")
            return try cells(edited, ["U5": "><v>0.375</v></c>", "S7": "><v>75</v></c>",
                                       "T7": "><v>200</v></c>", "U7": "><v>0.5</v></c>"])
        }
        let sorted = try reorderData(expanded, order: [7, 6, 5])
        var review = RegulatoryDataImport.Review()
        let match = try confirmedData(sorted, committed: before, review: &review)
        let group = try XCTUnwrap(match.records.first)
        XCTAssertEqual(group.regulatoryActions?.canGroup, true)
        let key = try XCTUnwrap(group.reviewID)
        review.groupFaults.insert(key)
        let unsettled = try RegulatoryDataImport.prepare(bytes: sorted, review: review, committed: before)
        let unresolved = try XCTUnwrap(unsettled.records.first)
        XCTAssertEqual(unresolved.classification, .ambiguous)
        XCTAssertFalse(unresolved.canApply)
        let choices = try XCTUnwrap(unresolved.regulatoryActions?.faultMatches)
        XCTAssertEqual(choices.map(\.row), [5, 7])
        XCTAssertTrue(choices.allSatisfy { $0.choices.map(\.id) == [id(25)] })
        let modified = try XCTUnwrap(choices.first { $0.row == 7 })
        review.faultMatches[key] = [modified.id: id(25)]
        let ready = try RegulatoryDataImport.prepare(bytes: sorted, review: review, committed: before)
        let proposal = try XCTUnwrap(ready.records.first)
        XCTAssertEqual(proposal.classification, .correction, proposal.reason)
        XCTAssertEqual(proposal.changes.first { $0.before == "0.125" && $0.after == "0.375" }?.row, 7)
        let batch = try MappingExchangeImport.Batch(preview: ready, bytes: sorted,
            selection: .init(accepted: [proposal.id]), now: time.addingTimeInterval(2))
        let (after, report) = try await owner.applyExchange(batch)
        XCTAssertEqual(report.count(.applied), 1)
        let original = try XCTUnwrap(before.observation(id: id(7))?.geology?.tectonicStructures)
        let saved = try XCTUnwrap(after.observation(id: id(7))?.geology?.tectonicStructures)
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved[0].id, original[0].id)
        XCTAssertEqual(saved[0].description, original[0].description)
        XCTAssertEqual(saved[0].thicknessMeters, 0.375)
        XCTAssertEqual(saved[1], original[1])
        XCTAssertEqual(saved[2].thicknessMeters, 0.5)
        let reexport = try regulatoryExport(after.journal, token: id(98))
        let replay = try RegulatoryDataImport.prepare(bytes: reorderData(reexport, order: [7, 5, 6]), committed: after)
        XCTAssertEqual(replay.count(.unchanged), 1)
        XCTAssertFalse(replay.records.contains(where: \.canApply))
    }

    func testRegulatoryPreviewRetainsOnlyApprovalsForUnchangedProposals() async throws {
        var (journal, plan, _) = try operationalJournal()
        journal.observations = Array(journal.observations.prefix(3))
        let book = try regulatoryExport(journal)
        let edited = try editData(book) { try cells($0, ["I5": "><v>2</v></c>", "I6": "><v>4</v></c>", "I7": "><v>7</v></c>"]) }
        let expanded = try appendDataRows(edited, rows: [
            ["A": .text("Штрек"), "B": .text("ПК 55"), "C": .number(111), "D": .number(222)]
        ], start: 8)
        let corrected = try patched(journal.observations[2], fields: ["notes": "\"Новое замечание\""])
        journal.appendCorrection(id: id(3000), snapshot: corrected, now: time.addingTimeInterval(1), author: nil, reason: "Поле")
        let committed = MappingCommittedSnapshot(journal)
        let screen = MappingExchangePreviewCoordinator()
        screen.activate(generation: committed.generationID)
        let url = URL(fileURLWithPath: "/unused/Data.xlsx")
        var review = RegulatoryDataImport.Review()
        func publish(_ bytes: Data, using review: RegulatoryDataImport.Review,
                     snapshot: MappingCommittedSnapshot? = nil) async throws -> MappingExchangePreview {
            let current = snapshot ?? committed
            let work = MappingExchangePreviewCoordinator.Work(snapshot: { current },
                read: { _, snapshot in try RegulatoryDataImport.prepare(bytes: bytes, review: review, committed: snapshot) },
                isCurrent: { $0 == current.generationID })
            let operation = try XCTUnwrap(screen.prepare(url, work: work))
            await operation.task.value
            return try XCTUnwrap(screen.state.preview)
        }
        let initial = try await publish(expanded, using: review)
        let firstKey = try XCTUnwrap(initial.records[0].reviewID)
        let secondKey = try XCTUnwrap(initial.records[1].reviewID)
        let thirdKey = try XCTUnwrap(initial.records[2].reviewID)
        review.matches[firstKey] = id(1000)
        let matched = try await publish(expanded, using: review)
        let first = try XCTUnwrap(matched.records.first { $0.matchedID == id(1000) })
        screen.updateSelection(.init(accepted: [first.id]))

        review.matches[secondKey] = id(1001)
        let two = try await publish(expanded, using: review)
        let second = try XCTUnwrap(two.records.first { $0.matchedID == id(1001) })
        XCTAssertEqual(screen.state.selection.accepted, [first.id])
        screen.updateSelection(.init(accepted: [first.id, second.id]))

        review.assignment = assignmentForData(plan: plan.id)
        let assigned = try await publish(expanded, using: review)
        let new = try XCTUnwrap(assigned.records.first { $0.classification == .new })
        XCTAssertEqual(screen.state.selection.accepted, [first.id, second.id])
        screen.updateSelection(.init(accepted: [first.id, second.id, new.id]))

        review.matches[thirdKey] = id(1002)
        let stale = try await publish(expanded, using: review)
        let conflict = try XCTUnwrap(stale.records.first { $0.classification == .conflict })
        XCTAssertEqual(screen.state.selection.accepted, [first.id, second.id, new.id])
        review.takeExcelChanges[thirdKey] = try XCTUnwrap(conflict.graphFingerprint)
        let resolved = try await publish(expanded, using: review)
        let third = try XCTUnwrap(resolved.records.first { $0.matchedID == id(1002) })
        XCTAssertTrue(third.canApply)
        XCTAssertEqual(screen.state.selection.accepted, [first.id, second.id, new.id])
        screen.updateSelection(.init(accepted: [first.id, second.id, third.id, new.id]))

        let sorted = try reorderData(expanded, order: [8, 7, 5, 6])
        _ = try await publish(sorted, using: review)
        XCTAssertEqual(screen.state.selection.accepted, [first.id, second.id, third.id, new.id])
        let newer = try patched(journal.observations[0], fields: ["notes": "\"Ещё одна полевая правка\""])
        journal.appendCorrection(id: id(3001), snapshot: newer, now: time.addingTimeInterval(2), author: nil, reason: "Поле")
        let latest = MappingCommittedSnapshot(journal)
        screen.journalChanged(to: latest.generationID)
        XCTAssertTrue(screen.state.stale)
        let rechecked = try await publish(sorted, using: review, snapshot: latest)
        XCTAssertEqual(rechecked.records.first { $0.matchedID == id(1000) }?.classification, .conflict)
        XCTAssertEqual(screen.state.selection.accepted, [second.id, third.id, new.id])
        review.assignment.observedAt = time.addingTimeInterval(3600)
        _ = try await publish(sorted, using: review, snapshot: latest)
        XCTAssertEqual(screen.state.selection.accepted, [second.id, third.id])
        let changed = try editData(sorted) { try cells($0, ["I6": "><v>12</v></c>"]) }
        _ = try await publish(changed, using: review, snapshot: latest)
        XCTAssertEqual(screen.state.selection.accepted, [second.id])
    }
}

extension MappingExchangePreviewTests {
    private func sourceRow(_ source: String, row: Int, x: Double = 2.5, y: Double = 1, z: Double) -> RegulatoryDataWorkbook.Row {
        var values = Array(repeating: "", count: RegulatoryDataWorkbook.columns.count)
        values[0] = source
        values[2] = String(x)
        values[3] = String(y)
        values[4] = String(z)
        return .init(number: row, values: values, issues: [])
    }

    func testSourceBatchReusesVerifiedInclinedDXFAndPreservesUnassignedIdentity() throws {
        var journal = MappingJournal()
        let project = MappingProject(id: id(1), name: "Project")
        let first = MappingHorizon(id: id(2), projectID: project.id, name: "Upper", elevationMeters: 400, elevationDatum: "survey datum")
        let second = MappingHorizon(id: id(3), projectID: project.id, name: "Lower", elevationMeters: 300, elevationDatum: "survey datum")
        let upper = MappingExcavation(id: id(4), projectID: project.id, name: "A", horizonIDs: [first.id])
        let lower = MappingExcavation(id: id(5), projectID: project.id, name: "B", horizonIDs: [second.id])
        journal.projects = [project]
        journal.horizons = [first, second]
        journal.excavations = [upper, lower]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FF82-plans-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ManagedPlanStore(root: root)
        func plan(horizon: MappingHorizon, from: Double, through: Double) throws -> MappingPlanReference {
            let line = "0\nLINE\n10\n0\n20\n0\n30\n\(from)\n11\n10\n21\n0\n31\n\(through)\n"
            return try files.stage(data: DXFFixtures.drawing(line, units: 6), filename: "survey.dxf", horizonID: horizon.id,
                version: horizon.name, units: .meters, crs: "mine grid", axes: "WCS XYZ")
        }
        let firstPlan = try plan(horizon: first, from: 390, through: 430)
        let secondPlan = try plan(horizon: second, from: 290, through: 330)
        journal.plans = [firstPlan, secondPlan]
        let snapshot = MappingCommittedSnapshot(journal)
        let frame = RegulatorySourceImport.Frame(crs: "mine grid", axes: "WCS XYZ", xyUnits: "m", verticalDatum: "survey datum")
        var review = RegulatorySourceImport.Review(projectID: project.id, dataset: "survey", frame: frame, frameConfirmed: true)
        review.geometryRules = [
            firstPlan.id: .init(horizonID: first.id, excavationID: upper.id, frame: frame, maximumXYMeters: 1.5, maximumZMeters: 0),
            secondPlan.id: .init(horizonID: second.id, excavationID: lower.id, frame: frame, maximumXYMeters: 1.5, maximumZMeters: 0)
        ]
        review.ranges = [
            first.id: .init(minimum: 280, maximum: 440, datum: frame.verticalDatum),
            second.id: .init(minimum: 280, maximum: 440, datum: frame.verticalDatum)
        ]
        let rows = [sourceRow("P1", row: 5, z: 400), sourceRow("P2", row: 6, x: 7.5, z: 320),
                    sourceRow("P3", row: 7, z: 350)]
        let input = RegulatorySourceImport.Input(rows: rows, workbookSHA256: String(repeating: "a", count: 64))
        let plan = try RegulatorySourceImport.prepare(input, review: review, snapshot: snapshot, plans: files, now: time)
        XCTAssertEqual(plan.count(.new), 3)
        XCTAssertEqual(plan.changes.map(\.destination.horizonID), [first.id, second.id, nil])
        XCTAssertEqual(plan.changes.map(\.destination.excavationID), [upper.id, lower.id, nil])
        var override = review
        override.assignments["P1"] = .init(projectID: project.id, horizonID: second.id)
        let corrected = try RegulatorySourceImport.prepare(input, review: override, snapshot: snapshot, plans: files)
        XCTAssertEqual(corrected.changes.first?.destination.horizonID, second.id)
        XCTAssertNil(corrected.changes.first?.destination.excavationID)
        let saved = try RegulatorySourceImport.applying(plan, to: snapshot)
        try saved.validate()
        let original = try XCTUnwrap(saved.regulatorySourceObservations)
        XCTAssertEqual(original.map { $0.latest?.xyz[2] }, [400, 320, 350])
        XCTAssertTrue(original.allSatisfy { $0.latest?.cells[1].isEmpty == true })
        XCTAssertEqual(MappingCommittedSnapshot(saved).sourcePoints(on: firstPlan).map(\.id), [original[0].id])
        XCTAssertEqual(MappingCommittedSnapshot(saved).sourcePoints(on: secondPlan).map(\.id), [original[1].id])
        let dataProjection = try EnterpriseGeotechnicalWorkbook.prepare(points: [], journal: saved, sourceRecords: original)
        XCTAssertEqual(dataProjection.table.rows.count, 3)
        XCTAssertEqual(dataProjection.table.rows[0][0].csv, MappingCSVExport.Cell.text("P1").csv)
        XCTAssertEqual(dataProjection.table.rows[0][4].csv, MappingCSVExport.Cell.text(try XCTUnwrap(original[0].latest?.cells[4])).csv)
        let reassigned = try RegulatorySourceImport.assigning([original[2].id],
            destination: .init(projectID: project.id, horizonID: second.id), journal: saved, now: time.addingTimeInterval(1))
        try reassigned.validate()
        let updated = try XCTUnwrap(reassigned.regulatorySourceObservations)
        XCTAssertEqual(updated.map(\.id), original.map(\.id))
        XCTAssertEqual(updated[2].versions.first, original[2].latest)
        XCTAssertEqual(updated[2].latest?.destination.horizonID, second.id)
        let replay = try RegulatorySourceImport.prepare(input, review: review, snapshot: .init(reassigned), plans: files)
        XCTAssertEqual(replay.count(.unchanged), 3)
        XCTAssertFalse(replay.canApply)
        var anotherDataset = review
        anotherDataset.dataset = "separate survey"
        XCTAssertEqual(try RegulatorySourceImport.prepare(input, review: anotherDataset, snapshot: .init(reassigned), plans: files).count(.new), 3)


        let edit = RegulatorySourceImport.Input(rows: [rows[0], rows[1], sourceRow("P3", row: 12, z: 351)],
                                                workbookSHA256: String(repeating: "b", count: 64))
        let beforeEdit = MappingCommittedSnapshot(reassigned)
        let edited = try RegulatorySourceImport.prepare(edit, review: review, snapshot: beforeEdit, plans: files)
        XCTAssertEqual(edited.count(.correction), 1)
        let revised = try RegulatorySourceImport.applying(edited, to: beforeEdit)
        XCTAssertEqual(revised.regulatorySourceObservations?.last?.id, original[2].id)
        XCTAssertEqual(revised.regulatorySourceObservations?.last?.latest?.xyz[2], 351)
        XCTAssertEqual(revised.regulatorySourceObservations?.last?.latest?.destination.horizonID, second.id)
        XCTAssertEqual(try RegulatorySourceImport.prepare(input, review: review, snapshot: .init(revised), plans: files).count(.conflict), 1)
    }

    func testSourceBatchRequiresMetadataConfirmationAndRollsBackAsOneTransaction() async throws {
        let journal = try fixture()
        let (root, owner, snapshot) = try await makeOwner(journal)
        let workflow = try MappingWorkflow(store: FileMappingStore(url: root.appendingPathComponent("mapping.json")))
        let source = sourceRow("source-1", row: 5, z: 400.1234)
        let input = RegulatorySourceImport.Input(rows: [source], workbookSHA256: String(repeating: "c", count: 64))
        var review = RegulatorySourceImport.Review(projectID: id(1), dataset: "survey")
        XCTAssertThrowsError(try RegulatorySourceImport.prepare(input, review: review, snapshot: snapshot))
        review.frameConfirmed = true
        let duplicate = RegulatorySourceImport.Input(rows: [source, sourceRow("source-1", row: 6, z: 402)], workbookSHA256: input.workbookSHA256)
        let invalid = try RegulatorySourceImport.prepare(duplicate, review: review, snapshot: snapshot)
        XCTAssertFalse(invalid.canApply)
        XCTAssertThrowsError(try RegulatorySourceImport.applying(invalid, to: snapshot))
        let plan = try RegulatorySourceImport.prepare(input, review: review, snapshot: snapshot)
        XCTAssertEqual(plan.count(.new), 1)
        XCTAssertNil(plan.changes.first?.destination.horizonID)
        do {
            let _: (MappingWorkflow.Snapshot, Bool) = try await owner.transaction(snapshot: workflow.snapshot) { workflow in
                try workflow.commit(RegulatorySourceImport.applying(plan, to: workflow.committed))
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let after = try await owner.exchangeSnapshot()
        XCTAssertEqual(after.journal, journal)
        XCTAssertEqual(try FileMappingStore(url: root.appendingPathComponent("mapping.json")).load(), journal)
        let (saved, _) = try await owner.transaction(snapshot: workflow.snapshot) { workflow in
            try workflow.commit(RegulatorySourceImport.applying(plan, to: workflow.committed))
        }
        let reopened = try FileMappingStore(url: root.appendingPathComponent("mapping.json")).load()
        XCTAssertEqual(reopened, saved.journal)
        XCTAssertEqual(reopened.regulatorySourceObservations?.first?.latest?.xyz[2], 400.1234)
        XCTAssertThrowsError(try RegulatorySourceImport.applying(plan, to: saved.committed))
    }

    func testSourceThreeWayConflictRequiresFieldDecision() throws {
        let snapshot = MappingCommittedSnapshot(try fixture())
        let review = RegulatorySourceImport.Review(projectID: id(1), dataset: "survey", frameConfirmed: true)
        let row = sourceRow("three-way", row: 5, z: 400)
        func input(_ rqd: String, _ hash: String) -> RegulatorySourceImport.Input {
            var cells = row.values
            cells[10] = rqd
            return .init(rows: [.init(number: row.number, values: cells, issues: [])],
                         workbookSHA256: String(repeating: hash, count: 64))
        }
        let original = input("65", "a")
        let imported = try RegulatorySourceImport.applying(
            RegulatorySourceImport.prepare(original, review: review, snapshot: snapshot), to: snapshot)
        let record = try XCTUnwrap(imported.regulatorySourceObservations?.first)
        var fields = try XCTUnwrap(record.latest?.cells)
        fields[10] = "72"
        let local = MappingCommittedSnapshot(try RegulatorySourceImport.editing(record, fields: fields, journal: imported))
        XCTAssertFalse(try RegulatorySourceImport.prepare(original, review: review, snapshot: local).canApply)
        let excel = input("81", "b")
        let check = try RegulatorySourceImport.prepare(excel, review: review, snapshot: local)
        XCTAssertThrowsError(try RegulatorySourceImport.applying(check, to: local))
        let conflict = try XCTUnwrap(check.changes.first?.conflicts.first)
        XCTAssertEqual(conflict.column, 10)
        XCTAssertEqual([conflict.baseline, conflict.local, conflict.incoming], ["65", "72", "81"])
        var choice = review
        choice.resolutions[conflict] = .keepLocal
        let merged = try RegulatorySourceImport.applying(
            RegulatorySourceImport.prepare(excel, review: choice, snapshot: local), to: local)
        let latest = try XCTUnwrap(merged.regulatorySourceObservations?.first?.latest)
        XCTAssertEqual(latest.cells[10], "72")
        XCTAssertEqual(latest.sourceBaseline[10], "81")
        XCTAssertFalse(try RegulatorySourceImport.prepare(excel, review: review, snapshot: .init(merged)).canApply)
    }

    func testMixedWorkbookAtomicallyReplaysAndRevisesBothRowTypes() async throws {
        let nativeJournal = try fixture()
        let baseline = MappingCommittedSnapshot(nativeJournal)
        var row = sourceRow("EXT-1", row: 5, z: 409.1234567890123)
        var source = row.values
        source[10] = "65"
        row = .init(number: row.number, values: source, issues: [])
        let input = RegulatorySourceImport.Input(rows: [row], workbookSHA256: String(repeating: "a", count: 64))
        let review = RegulatorySourceImport.Review(projectID: id(1), dataset: "test survey", frameConfirmed: true)
        let plan = try RegulatorySourceImport.prepare(input, review: review, snapshot: baseline, now: time)
        let journal = try RegulatorySourceImport.applying(plan, to: baseline)
        let sourceRecord = try XCTUnwrap(journal.regulatorySourceObservations?.first)
        let nativeID = try XCTUnwrap(journal.observations.first?.id)
        let (root, owner, committed) = try await makeOwner(journal)
        let workbook = try regulatoryExport(journal)
        let unchanged = try RegulatoryDataImport.prepare(bytes: workbook, committed: committed)
        let sourceInput = try XCTUnwrap(unchanged.productionInput)
        XCTAssertEqual(unchanged.count(.unchanged), 1)
        let replay = try RegulatorySourceImport.prepare(sourceInput, review: .init(), snapshot: committed)
        XCTAssertEqual(replay.count(.unchanged), 1)
        let replayBatch = try MappingExchangeImport.Batch(preview: unchanged, bytes: workbook, selection: .init(), now: time, mixed: true)
        XCTAssertEqual(try MappingExchangeImport.applyingMixed(replayBatch, sourcePlan: replay, to: committed), journal)

        let edited = try editData(workbook) { try cells($0, ["I5": "><v>7</v></c>", "K6": "><v>80</v></c>"]) }
        var nativeReview = RegulatoryDataImport.Review()
        let resolved = try confirmedData(edited, committed: committed, review: &nativeReview)
        XCTAssertEqual(resolved.count(.correction), 1)
        let pending = try RegulatorySourceImport.prepare(XCTUnwrap(resolved.productionInput), review: .init(), snapshot: committed)
        XCTAssertEqual(pending.count(.correction), 1)
        let empty = try MappingExchangeImport.Batch(preview: resolved, bytes: edited, selection: .init(), now: time, mixed: true)
        do {
            _ = try await owner.applyMixedExchange(empty, sourcePlan: pending)
            XCTFail("Expected mixed batch refusal")
        } catch is ExchangeImportError {}
        XCTAssertEqual(try FileMappingStore(url: root.appendingPathComponent("mapping.json")).load(), journal)

        let approved = try MappingExchangeImport.Batch(preview: resolved, bytes: edited,
            selection: .init(accepted: Set(resolved.records.filter(\.canApply).map(\.id))), now: time, mixed: true)
        let staged = try MappingExchangeImport.applyingMixed(approved, sourcePlan: pending, to: committed)
        XCTAssertThrowsError(try FileMappingStore(url: root.appendingPathComponent("mapping.json")).save(staged))
        let committedEdit = try await owner.applyMixedExchange(approved, sourcePlan: pending)
        let updated = try FileMappingStore(url: root.appendingPathComponent("mapping.json")).load()
        XCTAssertEqual(updated, committedEdit.journal)
        XCTAssertEqual(updated.observations.map(\.id), journal.observations.map(\.id))
        XCTAssertEqual(updated.revisions.last?.observationID, nativeID)
        let changed = try XCTUnwrap(updated.regulatorySourceObservations?.first)
        XCTAssertEqual(changed.id, sourceRecord.id)
        XCTAssertEqual(changed.key, sourceRecord.key)
        XCTAssertEqual(changed.latest?.cells[10], "80")
        XCTAssertEqual(changed.latest?.sourceBaseline[10], "65")
        XCTAssertEqual(changed.latest?.destination, sourceRecord.latest?.destination)
        XCTAssertEqual(changed.latest?.cells[4], source[4])
        let replayEdited = try RegulatoryDataImport.prepare(bytes: edited, committed: committedEdit)
        let replaySource = try RegulatorySourceImport.prepare(XCTUnwrap(replayEdited.productionInput), review: .init(), snapshot: committedEdit)
        let replayedBatch = try MappingExchangeImport.Batch(preview: replayEdited, bytes: edited, selection: .init(), now: time, mixed: true)
        let replayed = try await owner.applyMixedExchange(replayedBatch, sourcePlan: replaySource)
        XCTAssertEqual(replayed.generationID, committedEdit.generationID)
        XCTAssertEqual(replayed.journal, updated)
        let tampered = try editData(workbook) { try cells($0, ["A6": #" t="inlineStr"><is><t>another-source</t></is></c>"#]) }
        XCTAssertThrowsError(try RegulatoryDataImport.prepare(bytes: tampered, committed: committed))
        let rounded = try editData(workbook) { try cells($0, ["E6": "><v>409.1234567890124</v></c>"]) }
        let roundedPreview = try RegulatoryDataImport.prepare(bytes: rounded, committed: committed)
        let roundedPlan = try RegulatorySourceImport.prepare(XCTUnwrap(roundedPreview.productionInput), review: .init(), snapshot: committed)
        XCTAssertEqual(roundedPlan.count(.invalid), 1)

        var parts = try archiveParts(workbook)
        let path = "xl/worksheets/sheet2.xml"
        var metadata = String(decoding: try XCTUnwrap(parts[path]), as: UTF8.self)
        let range = try XCTUnwrap(metadata.range(of: #"<row r="4"[^>]*>.*?</row>"#, options: .regularExpression))
        let duplicate = metadata[range].replacingOccurrences(of: #"<row r="4""#, with: #"<row r="5""#)
            .replacingOccurrences(of: #"<c r="A4""#, with: #"<c r="A5""#)
        metadata.insert(contentsOf: duplicate, at: range.upperBound)
        parts[path] = Data(metadata.utf8)
        XCTAssertThrowsError(try RegulatoryDataImport.prepare(bytes: zip(parts.sorted { $0.key < $1.key }, deflated: true), committed: committed))
    }

    func testActualProductionWorkbookImportsAndReplaysElevenSourceRows() throws {
        let url = ProcessInfo.processInfo.environment["FIELD_FORGE_PRODUCTION_XLSX"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/БД_ПГР.xlsx")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Set FIELD_FORGE_PRODUCTION_XLSX to the original production workbook.")
        }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        let base = try fixture()
        let baseSnapshot = MappingCommittedSnapshot(base)
        let preview = try RegulatoryDataImport.prepare(bytes: bytes, committed: baseSnapshot)
        let input = try XCTUnwrap(preview.productionInput)
        XCTAssertEqual(input.rows.count, 11)
        let review = RegulatorySourceImport.Review(projectID: id(1), dataset: "production-db-pgr", frameConfirmed: true)
        let plan = try RegulatorySourceImport.prepare(input, review: review, snapshot: baseSnapshot)
        XCTAssertEqual(plan.count(.new), 11)
        XCTAssertEqual(plan.count(.invalid), 0)
        let saved = try RegulatorySourceImport.applying(plan, to: baseSnapshot)
        try saved.validate()
        let records = try XCTUnwrap(saved.regulatorySourceObservations)
        XCTAssertEqual(records.count, 11)
        XCTAssertEqual(Set(records.map(\.id)).count, 11)
        XCTAssertTrue(records.allSatisfy { $0.latest?.destination.horizonID == nil && $0.latest?.destination.excavationID == nil })
        let replay = try RegulatorySourceImport.prepare(input, review: review, snapshot: MappingCommittedSnapshot(saved))
        XCTAssertEqual(replay.count(.unchanged), 11)
        XCTAssertEqual(replay.count(.new), 0)

        let original = records[0]
        let originalVersion = try XCTUnwrap(original.latest)
        let localRQD = originalVersion.cells[10] == "77.75" ? "79.25" : "77.75"
        var localFields = originalVersion.cells
        localFields[10] = localRQD
        var invalidFields = localFields
        invalidFields[10] = "101"
        XCTAssertThrowsError(try RegulatorySourceImport.editing(original, fields: invalidFields, journal: saved))
        invalidFields = localFields
        invalidFields[2] = "0"
        XCTAssertThrowsError(try RegulatorySourceImport.editing(original, fields: invalidFields, journal: saved))
        let locallyEdited = try RegulatorySourceImport.editing(original, fields: localFields, journal: saved, now: time)
        let localSnapshot = MappingCommittedSnapshot(locallyEdited)
        let unchangedSource = try RegulatorySourceImport.prepare(input, review: review, snapshot: localSnapshot)
        XCTAssertEqual(unchangedSource.count(.unchanged), 11)
        XCTAssertFalse(unchangedSource.canApply)
        XCTAssertEqual(locallyEdited.regulatorySourceObservations?.first?.versions.first, originalVersion)

        func amendment(_ changes: [Int: String], hash: String) -> RegulatorySourceImport.Input {
            let modified = input.rows.map { row -> RegulatoryDataWorkbook.Row in
                guard row.number == input.rows.first?.number else { return row }
                var values = row.values
                for (column, value) in changes { values[column] = value }
                return .init(number: row.number, values: values, issues: row.issues)
            }
            return .init(rows: modified, workbookSHA256: String(repeating: hash, count: 64))
        }
        let strength = originalVersion.cells[9] == "56.25" ? "55.25" : "56.25"
        let differentField = amendment([9: strength], hash: "a")
        let merge = try RegulatorySourceImport.prepare(differentField, review: review, snapshot: localSnapshot)
        XCTAssertEqual(merge.count(.correction), 1)
        let merged = try RegulatorySourceImport.applying(merge, to: localSnapshot)
        let mergedRecord = try XCTUnwrap(merged.regulatorySourceObservations?.first)
        XCTAssertEqual(mergedRecord.latest?.cells[9], strength)
        XCTAssertEqual(mergedRecord.latest?.cells[10], localRQD)
        let mergedSnapshot = MappingCommittedSnapshot(merged)
        let sameField = amendment([9: strength, 10: "63.125"], hash: "b")
        let conflict = try RegulatorySourceImport.prepare(sameField, review: review, snapshot: mergedSnapshot)
        XCTAssertTrue(conflict.blocked)
        XCTAssertThrowsError(try RegulatorySourceImport.applying(conflict, to: mergedSnapshot))
        let field = try XCTUnwrap(conflict.changes.flatMap(\.conflicts).first)
        XCTAssertEqual(field.column, 10)
        XCTAssertEqual(field.baseline, originalVersion.cells[10])
        XCTAssertEqual(field.local, localRQD)
        XCTAssertEqual(field.incoming, "63.125")
        var resolvedReview = review
        resolvedReview.resolutions[field] = .keepLocal
        let keep = try RegulatorySourceImport.prepare(sameField, review: resolvedReview, snapshot: mergedSnapshot)
        let kept = try RegulatorySourceImport.applying(keep, to: mergedSnapshot)
        XCTAssertEqual(kept.regulatorySourceObservations?.first?.latest?.cells[10], localRQD)
        XCTAssertEqual(kept.regulatorySourceObservations?.first?.latest?.sourceBaseline[10], "63.125")
        resolvedReview.resolutions[field] = .acceptExcel
        let accept = try RegulatorySourceImport.prepare(sameField, review: resolvedReview, snapshot: mergedSnapshot)
        let accepted = try RegulatorySourceImport.applying(accept, to: mergedSnapshot)
        XCTAssertEqual(accepted.regulatorySourceObservations?.first?.latest?.cells[10], "63.125")
        let identicalField = amendment([9: strength, 10: localRQD], hash: "c")
        let identical = try RegulatorySourceImport.prepare(identicalField, review: review, snapshot: mergedSnapshot)
        XCTAssertFalse(identical.blocked)
        XCTAssertEqual(identical.count(.correction), 1)
        let converged = try RegulatorySourceImport.applying(identical, to: mergedSnapshot)
        XCTAssertFalse(try XCTUnwrap(converged.regulatorySourceObservations?.first?.latest).hasLocalEdits)

        var sourceOnlyJournal = kept
        sourceOnlyJournal.observations = []
        sourceOnlyJournal.revisions = []
        sourceOnlyJournal.measurements = []
        let export = try MappingCSVExport.prepare(journal: sourceOnlyJournal,
            selection: .init(projectID: id(1), firstDay: time, lastDay: time, timeZoneID: "UTC"),
            now: time, includeEnterprise: true)
        let files = try MappingExportFiles.write(export, format: .enterpriseGeotechnical)
        defer { files.cleanup() }
        let exportedPreview = try RegulatoryDataImport.prepare(bytes: Data(contentsOf: try XCTUnwrap(files.urls.first)),
            committed: MappingCommittedSnapshot(kept))
        let exportedInput = try XCTUnwrap(exportedPreview.productionInput)
        XCTAssertEqual(exportedInput.suggestedProjectID, id(1))
        XCTAssertEqual(exportedInput.suggestedDataset, "production-db-pgr")
        let exportedReview = RegulatorySourceImport.Review(projectID: exportedInput.suggestedProjectID,
            dataset: try XCTUnwrap(exportedInput.suggestedDataset), frame: try XCTUnwrap(exportedInput.suggestedFrame), frameConfirmed: true)
        let exportReplay = try RegulatorySourceImport.prepare(exportedInput, review: exportedReview,
            snapshot: MappingCommittedSnapshot(kept))
        let sourceByID = Dictionary(uniqueKeysWithValues: (kept.regulatorySourceObservations ?? []).map { ($0.key.sourceID, $0.latest!.cells) })
        let changedColumns = exportedInput.rows.compactMap { row -> String? in
            guard let original = sourceByID[row.values[0]] else { return "unknown-source" }
            let indexes = original.indices.filter { original[$0] != row.values[$0] }
            return indexes.isEmpty ? nil : "row\(row.number):" + indexes.map(String.init).joined(separator: ",")
        }
        XCTAssertEqual(exportReplay.count(.unchanged), 11, "Changed A:AD columns: \(changedColumns)")
        XCTAssertEqual(exportReplay.count(.new), 0)
        XCTAssertFalse(exportReplay.canApply)
        XCTAssertEqual(exportedInput.rows.first?.values[10], localRQD)

        let mixedBytes = try regulatoryExport(kept)
        let mixedSnapshot = MappingCommittedSnapshot(kept)
        let mixed = try RegulatoryDataImport.prepare(bytes: mixedBytes, committed: mixedSnapshot)
        let mixedSource = try RegulatorySourceImport.prepare(XCTUnwrap(mixed.productionInput), review: .init(), snapshot: mixedSnapshot)
        XCTAssertEqual(mixed.count(.unchanged), kept.observations.filter { $0.projectID == id(1) }.count)
        XCTAssertEqual(mixedSource.count(.unchanged), 11)
        let mixedBatch = try MappingExchangeImport.Batch(preview: mixed, bytes: mixedBytes, selection: .init(), now: time, mixed: true)
        XCTAssertEqual(try MappingExchangeImport.applyingMixed(mixedBatch, sourcePlan: mixedSource, to: mixedSnapshot), kept)
    }
}
