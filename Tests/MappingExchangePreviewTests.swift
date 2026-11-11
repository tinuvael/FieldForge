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
        let files = try export.write(); return try ExchangeArchive(url: files.urls[0], limits: .init()).parts
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
        let reexported = try workbook(ExchangeArchive(data: reexport, limits: .init()).parts)
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
        let reexported = try self.workbook(ExchangeArchive(data: bytes(export(after.journal)), limits: .init()).parts)
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
        let archive = try ExchangeArchive(data: zip(rewritten.sorted { $0.key < $1.key }, deflated: true), limits: .init())
        let p = try MappingExchangePreview.prepare(workbook: workbook(archive.parts), committed: .init(j))
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
        XCTAssertThrowsError(try ExchangeArchive(data: zip([("a", Data(repeating: 65, count: 10_000))], deflated: true), limits: limits))
        limits = .init(); limits.compressionRatio = 2
        XCTAssertThrowsError(try ExchangeArchive(data: zip([("a", Data(repeating: 65, count: 10_000))], deflated: true), limits: limits))
        limits = .init(); limits.entries = 1
        XCTAssertThrowsError(try ExchangeArchive(data: zip([("a", bytes), ("b", bytes)]), limits: limits))
        var encrypted = try zip([("a", bytes)]); encrypted[6] |= 1
        XCTAssertThrowsError(try ExchangeArchive(data: encrypted, limits: .init()))
        var corrupt = try zip([("a", bytes)]); corrupt[31] ^= 1
        XCTAssertThrowsError(try ExchangeArchive(data: corrupt, limits: .init()))
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
