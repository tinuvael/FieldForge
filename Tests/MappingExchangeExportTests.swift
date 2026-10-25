import XCTest
import CryptoKit
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingExchangeExportTests: XCTestCase {
    private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    private let time = Date(timeIntervalSinceReferenceDate: 721234567.1234567)
    private func fixture(longOriginal: Bool = false) throws -> MappingJournal {
        var j = MappingJournal()
        j.projects = [MappingProject(id: uuid(1), name: "Проект А"), MappingProject(id: uuid(2), name: "Проект Б")]
        j.horizons = [MappingHorizon(id: uuid(3), projectID: uuid(1), name: "А", elevationMeters: -120.12345678912345, elevationDatum: "mine datum"),
                      MappingHorizon(id: uuid(4), projectID: uuid(2), name: "Б", elevationMeters: nil, elevationDatum: "unknown"),
                      MappingHorizon(id: uuid(9), projectID: uuid(1), name: "А2", elevationMeters: 1, elevationDatum: "unknown")]
        j.excavations = [MappingExcavation(id: uuid(5), projectID: uuid(1), name: "Штрек А", horizonIDs: [uuid(3), uuid(9)]),
                         MappingExcavation(id: uuid(6), projectID: uuid(2), name: "Штрек Б", horizonIDs: [uuid(4)])]
        j.selection = .init(projectID: uuid(1), horizonID: uuid(3), excavationID: uuid(5))
        let store = MappingTests.MemoryStore(); store.value = j
        var w = try MappingWorkflow(store: store)
        w.draft = MappingDraft(id: uuid(7)); w.draft.suggestElevation(j.horizons[0])
        w.draft.picket = "1+2.123456789"; w.draft.observedAtOverride = time; w.draft.timeZoneID = "Asia/Almaty"
        w.draft.chainageOriginAndDirection = "От устья → север"
        w.draft.notes = longOriginal ? String(repeating: "🪨", count: 20000) : "Исходное наблюдение"
        w.draft.x = "123456789.12345679"; w.draft.y = "-0.12345678912345678"
        w.draft.crs = "local mine"; w.draft.axes = "X north; Y east"; w.draft.coordinateProvenance = "Survey notebook; manually entered"
        w.draft.startPicket = "1+0"; w.draft.endPicket = "2+0"; w.draft.observationPosition = .roof
        let m = try ManualOrientationInput(dipAngleText: "45,12345678912345", dipDirectionText: "360", reference: .gridNorth)
            .observation(notes: "=SUM(A1:A9)", id: uuid(10), timestamp: time)
        let sensor = Measurement.process(MockSensorProvider.sample(dip: 60, direction: 270, timestamp: time), id: uuid(11))
        try w.draft.addMeasurement(m); try w.draft.addMeasurement(sensor)
        for (i, identifier) in JointSetIdentifier.allCases.enumerated() {
            var set = JointSetDraft(identifier: identifier, id: uuid(20 + i))
            set.representative = .init(dipAngleText: "41,12345678912345", dipDirectionText: "120", reference: .magneticNorth)
            set.measurementIDs = [m.id, sensor.id]; set.spacing = "0.125"; set.author = "Инженер"; set.notes = "@test"
            w.draft.jointSets.append(set)
        }
        var fault = TectonicStructureDraft(id: uuid(25)); fault.description = "<Разлом & трещина>"; fault.thickness = "0.125"
        w.draft.tectonicStructures = [fault]
        var q = BartonQInput(); q.rqd = "80"; q.rqdSource = .coreMeasured; q.location = .ordinary; q.contact = .wall
        q.assessmentSource = "Field log"; q.jn.select("F", parameter: .jn); q.jr.select("B", parameter: .jr)
        q.ja.select("C", parameter: .ja); q.jw.select("A", parameter: .jw); q.srf.select("G", parameter: .srf)
        w.draft.bartonQ = q; w.draft.rmr89.source = "Input only"
        w.draft.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair), lower: 35, upper: 45, finalValue: nil, assessedAt: time)
        let original = try w.save(now: time)
        var c = try w.correction(for: original.id); c.reason = "Исправление"; c.author = "Инженер"
        c.fields.notes = " =1+1\r\n+cmd\t-1 @test _x0020_ 'текст 🪨"
        c.fields.jointSets[0].representative.dipAngleText = "52,125"; c.fields.z = "-121.12345678912345"
        let r = try w.saveCorrection(c, now: time.addingTimeInterval(1.234567))
        try w.requestContext(.init(projectID: uuid(2), horizonID: uuid(4), excavationID: uuid(6)))
        w.draft = MappingDraft(id: uuid(8)); w.draft.picket = "1+2.123456789"; w.draft.observedAtOverride = time; w.draft.timeZoneID = "UTC"
        _ = try w.save(now: time)
        j = w.journal
        j.revisions = [.init(id: uuid(30), observationID: r.observationID, version: r.version,
            previousRevisionID: nil, correctedAt: r.correctedAt, author: r.author, reason: r.reason, snapshot: r.snapshot)]
        try j.validate(); return j
    }
    private func selection(_ project: Int = 1) -> MappingExportSelection {
        .init(projectID: uuid(project), horizonID: nil, excavationID: nil, firstDay: time, lastDay: time, timeZoneID: "UTC")
    }
    private func export(_ j: MappingJournal, project: Int = 1) throws -> MappingExchangeExport {
        try .prepare(committed: .init(j), selection: selection(project), now: time, id: uuid(99))
    }
    private func table(_ e: MappingExchangeExport, _ name: String) throws -> MappingCSVExport.Table { try XCTUnwrap(e.tables.first { $0.name == name }) }
    private func rows(_ e: MappingExchangeExport, _ name: String) throws -> [[String: String]] {
        try table(e, name).rows.map { row in Dictionary(uniqueKeysWithValues: zip(try table(e, name).columns, row.map {
            if case .text(let text) = $0 { return text }; return ""
        })) }
    }
    private func source<T: Decodable>(_ type: T.Type, _ e: MappingExchangeExport, kind: String, id: UUID) throws -> T {
        let chunks = try rows(e, "source_records").filter { $0["kind"] == kind && $0["record_id"] == id.uuidString }
            .sorted { Int($0["chunk_index"]!)! < Int($1["chunk_index"]!)! }
        XCTAssertFalse(chunks.isEmpty)
        let data = Data(chunks.compactMap { $0["json_chunk"] }.joined().utf8)
        XCTAssertEqual(chunks.first?["sha256"], SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        return try JSONDecoder().decode(type, from: data)
    }

    func testTwoProjectsRelationshipsOriginalEffectiveValuesAndAllTypedSourceRecords() async throws {
        let j = try fixture(), e = try export(j)
        XCTAssertEqual(try export(fixture()).tables.flatMap(\.rows).count, e.tables.flatMap(\.rows).count)
        let point = try XCTUnwrap(rows(e, "points").first)
        for (column, id) in [("point_id", 7), ("project_id", 1), ("horizon_id", 3), ("excavation_id", 5), ("original_id", 7), ("revision_id", 30)] {
            XCTAssertEqual(point[column], uuid(id).uuidString)
        }
        XCTAssertEqual(point["record_action"], "existing"); XCTAssertEqual(point["version"], "2")
        XCTAssertEqual(point["z_origin"], "manualOverride")
        XCTAssertEqual(point["x"], "123456789.12345679"); XCTAssertEqual(point["coordinate_source"], "manual")
        XCTAssertEqual(point["crs"], "local mine"); XCTAssertEqual(point["axes"], "X north; Y east")
        XCTAssertEqual(point["observed_zone"], "Asia/Almaty")
        XCTAssertEqual(point["observed_offset_seconds"], "21600")
        XCTAssertEqual(Double(try XCTUnwrap(point["observed_at_reference_seconds"])), time.timeIntervalSinceReferenceDate)
        XCTAssertEqual(try rows(e, "joint_sets").map { $0["identifier"]! }.sorted(), ["J1", "J2", "J3", "J4", "J5"])
        XCTAssertEqual(try rows(e, "interpretation_evidence").count, 10)
        XCTAssertEqual(try rows(e, "measurements").count, 2)
        XCTAssertEqual(try rows(e, "joint_sets").first?["original_dip_text"], "52,125")
        XCTAssertEqual(try source(MappingObservation.self, e, kind: "original", id: uuid(7)), j.observations[0])
        XCTAssertEqual(try source(MappingObservation.self, e, kind: "original", id: uuid(7)).coordinates?.zOrigin, .horizonDefault)
        XCTAssertEqual(try source(MappingObservationRevision.self, e, kind: "revision", id: uuid(30)), j.revisions[0])
        for m in j.measurements { XCTAssertEqual(try source(Measurement.self, e, kind: "measurement", id: m.id), m) }
        let other = try export(j, project: 2), otherPoint = try XCTUnwrap(rows(other, "points").first)
        XCTAssertEqual(otherPoint["point_id"], uuid(8).uuidString)
        XCTAssertEqual(otherPoint["revision_id"], uuid(8).uuidString); XCTAssertEqual(otherPoint["version"], "1")
        XCTAssertEqual(otherPoint["x"], ""); XCTAssertEqual(otherPoint["z_m"], ""); XCTAssertEqual(otherPoint["has_coordinates"], "false")
        XCTAssertEqual(try rows(other, "measurements").count, 0)
        XCTAssertEqual(try rows(other, "projects").map { $0["project_id"]! }, [uuid(2).uuidString])
        XCTAssertFalse(try rows(other, "source_records").contains { $0["point_id"] == uuid(7).uuidString })
        try verifyWorkbook(e)
        try verifyWorkbook(other)
        if let path = ProcessInfo.processInfo.environment["FIELD_FORGE_EXCHANGE_SAMPLE"] {
            let files = try e.write(); defer { files.cleanup() }
            try Data(contentsOf: files.urls[0]).write(to: URL(fileURLWithPath: path))
        }
    }

    func testPlanDerivedZAndPhotoHistoryRetainFullProvenanceWithoutReadingAttachments() async throws {
        var j = try fixture()
        let data = DXFFixtures.drawing("0\nLINE\n5\nAB\n10\n0\n20\n0\n30\n-20\n11\n10\n21\n0\n31\n20\n")
        let document = try DXFDocument.parse(data)
        let plan = MappingPlanReference(id: uuid(40), horizonID: uuid(3), attachmentID: uuid(41), version: "A",
            file: ManagedPlanFile(originalFilename: "fixture.dxf", sha256: ManagedPlanStore.digest(data), byteCount: data.count,
                importedAt: time, units: .meters, crs: "mine grid", axes: "WCS XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: document.insertionUnits))
        j.plans = [plan]
        let store = MappingTests.MemoryStore(); store.value = j
        var w = try MappingWorkflow(store: store)
        let xy = PlanPoint(x: 2.5, y: 1)
        let elevation = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: document, plan: plan).automatic)
        var c = try w.correction(for: uuid(7)); c.reason = "Locate on plan"
        try c.fields.selectPlanPoint(xy, plan: plan, elevation: elevation)
        let revision = try w.saveCorrection(c, now: time.addingTimeInterval(3))
        j = w.journal
        j.revisions[1] = .init(id: uuid(31), observationID: revision.observationID, version: revision.version,
            previousRevisionID: revision.previousRevisionID, correctedAt: revision.correctedAt, author: revision.author, reason: revision.reason, snapshot: revision.snapshot)
        let attachment = PhotoAttachment(id: uuid(50), originalFilename: "нет файла.jpg", sha256: String(repeating: "a", count: 64),
            byteCount: 500, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1, orientation: 1, representation: "received bytes unchanged")
        let context = PhotoContext(projectID: uuid(1), horizonID: uuid(3), excavationID: uuid(5), pointID: uuid(7),
            pointRevisionID: uuid(7), pointVersion: 1, locationBasis: .unknownBeforeFirstSave)
        let photo = PhotoObservation(id: uuid(51), attachmentID: attachment.id, context: context, source: .files, importedAt: time,
            capturedAt: nil, captureTimeText: "2023:11:09 12:00:00", captureTimeProvenance: "unknown offset", metadata: .init(name: "Original"))
        let metadata = PhotoMetadataRevision(id: uuid(52), photoID: photo.id, previousRevisionID: nil, version: 2,
            correctedAt: time, reason: "Description", metadata: .init(name: "Current"))
        j.photos = [photo]; j.photoAttachments = [attachment]; j.photoRevisions = [metadata]
        try j.validate()
        let e = try export(j), point = try XCTUnwrap(rows(e, "points").first)
        XCTAssertEqual(point["z_origin"], "planGeometry"); XCTAssertEqual(point["coordinate_source"], "plan")
        XCTAssertEqual(point["plan_id"], plan.id.uuidString)
        XCTAssertEqual(try JSONDecoder().decode(PlanGeometryElevation.self, from: Data(try XCTUnwrap(point["z_plan_geometry_json"]).utf8)), elevation)
        XCTAssertEqual(try source(MappingPlanReference.self, e, kind: "plan", id: plan.id), plan)
        XCTAssertEqual(try source(PhotoObservation.self, e, kind: "photo", id: photo.id), photo)
        XCTAssertEqual(try source(PhotoAttachment.self, e, kind: "photo_attachment", id: attachment.id), attachment)
        XCTAssertEqual(try source(PhotoMetadataRevision.self, e, kind: "photo_revision", id: metadata.id), metadata)
        XCTAssertEqual(try rows(e, "photos").first?["capture_location_basis"], "unknownBeforeFirstSave")
        XCTAssertEqual(try rows(e, "photos").first?["captured_at_utc"], "")
        XCTAssertEqual(try rows(e, "photo_point_contexts").first?["revision_id"], uuid(7).uuidString)
        try verifyWorkbook(e)
    }

    func testFingerprintsIgnoreRowOrderButDetectRevisionEvidenceAndParentChanges() async throws {
        let j = try fixture(), a = try MappingExchangeExport.fingerprint(uuid(7), in: .init(j))
        var reordered = j; reordered.projects.reverse(); reordered.horizons.reverse(); reordered.excavations.reverse()
        reordered.observations.reverse(); reordered.measurements.reverse()
        reordered.excavations[1].horizonIDs = Set([uuid(9), uuid(3)])
        XCTAssertEqual(a, try MappingExchangeExport.fingerprint(uuid(7), in: .init(reordered)))
        var changed = j; changed.measurements[0].notes = "Other evidence"
        XCTAssertNotEqual(a, try MappingExchangeExport.fingerprint(uuid(7), in: .init(changed)))
        changed = j; changed.projects[0].name = "Renamed"
        XCTAssertNotEqual(a, try MappingExchangeExport.fingerprint(uuid(7), in: .init(changed)))
        changed = j; changed.projects[1].name = "Other project"
        XCTAssertEqual(a, try MappingExchangeExport.fingerprint(uuid(7), in: .init(changed)))
        changed = j; changed.revisions.removeAll()
        XCTAssertNotEqual(a, try MappingExchangeExport.fingerprint(uuid(7), in: .init(changed)))
        XCTAssertEqual(try rows(export(j), "points").first?["base_fingerprint"], a)
    }

    func testLongOriginalEvidenceChunksReassembleWithoutLoss() async throws {
        let j = try fixture(longOriginal: true), e = try export(j)
        XCTAssertEqual(try source(MappingObservation.self, e, kind: "original", id: uuid(7)), j.observations[0])
        let chunks = try rows(e, "source_records").filter { $0["kind"] == "original" && $0["record_id"] == uuid(7).uuidString }
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0["json_chunk"]!.utf16.count <= 16000 })
        try verifyWorkbook(e)
    }

    func testReportCompatibilityAndExplicitRefusalCleanup() async throws {
        let j = try fixture()
        let report = try MappingCSVExport.prepare(journal: j, selection: selection(), now: time, id: uuid(99))
        let before = report.tables.map(\.data)
        _ = try export(j)
        XCTAssertEqual(report.tables.map(\.data), before)
        for format in [MappingExportFormat.csv, .xlsx, .enterpriseGeotechnical] {
            let snapshot = try MappingCSVExport.prepare(journal: j, selection: selection(), now: time, id: uuid(99), includeEnterprise: format == .enterpriseGeotechnical)
            let files = try MappingExportFiles.write(snapshot, format: format); defer { files.cleanup() }
            XCTAssertFalse(files.urls.isEmpty)
            if format != .csv {
                let parts = try unzip(Data(contentsOf: files.urls[0]))
                let workbook = try parse(XCTUnwrap(parts["xl/workbook.xml"]))
                XCTAssertFalse(workbook.sheetNames.contains("source_records"))
                let styles = String(decoding: try XCTUnwrap(parts["xl/styles.xml"]), as: UTF8.self)
                XCTAssertTrue(styles.contains("cellXfs count=\"6\""))
            }
        }
        var invalid = j; invalid.horizons.removeFirst()
        XCTAssertThrowsError(try export(invalid))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("existing.xlsx"); try Data([1, 2, 3]).write(to: sentinel)
        let oversized = MappingExchangeExport(id: uuid(99), snapshotAt: time,
            tables: [.init(name: "points", columns: ["notes"], rows: [[.text(String(repeating: "я", count: 32768))]])])
        XCTAssertThrowsError(try oversized.write(parent: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["existing.xlsx"])
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([1, 2, 3]))
    }

    func testFIFOReadWaitsForAcceptedCommitAndRetainedGenerationStaysFrozen() async throws {
        let store = MappingTests.MemoryStore(); store.value = try fixture()
        let w = try MappingWorkflow(store: store), snapshot = w.snapshot
        let owner = MappingStorageOwner(store: store, committed: w.committed)
        let old = try await owner.exchangeSnapshot()
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let write = Task {
            try await owner.transaction(snapshot: snapshot) { workflow in
                started.signal(); release.wait()
                var j = workflow.journal; j.projects[0].name = "Committed later"
                try workflow.commit(j)
            }
        }
        await withCheckedContinuation { continuation in DispatchQueue.global().async { started.wait(); continuation.resume() } }
        let read = Task { try await owner.exchangeSnapshot() }
        release.signal(); _ = try await write.value
        let latest = try await read.value
        XCTAssertEqual(latest.journal.projects[0].name, "Committed later")
        XCTAssertEqual(old.journal.projects[0].name, "Проект А")
        await owner.retire()
        do { _ = try await owner.exchangeSnapshot(); XCTFail("Retired owner must reject reads") } catch { }
    }

    // Independent ZIP central-directory and XML inspection of actual emitted cells.
    private func unzip(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func word(_ p: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(b[p + $1]) << (8 * $1) } }
        XCTAssertEqual(word(b.count - 22, 4), 0x06054b50)
        var pos = word(b.count - 6, 4), result: [String: Data] = [:]
        for _ in 0..<word(b.count - 12, 2) {
            XCTAssertEqual(word(pos, 4), 0x02014b50); XCTAssertEqual(word(pos + 10, 2), 0)
            let size = word(pos + 20, 4), length = word(pos + 28, 2), local = word(pos + 42, 4)
            let name = String(decoding: b[(pos + 46)..<(pos + 46 + length)], as: UTF8.self)
            let start = local + 30 + word(local + 26, 2) + word(local + 28, 2)
            XCTAssertNil(result[name]); result[name] = Data(b[start..<(start + size)])
            pos += 46 + length + word(pos + 30, 2) + word(pos + 32, 2)
        }
        XCTAssertEqual(pos, b.count - 22); return result
    }
    private func parse(_ data: Data) throws -> ExchangeSheetReader {
        let reader = ExchangeSheetReader(), parser = XMLParser(data: data); parser.delegate = reader
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "XML"); return reader
    }
    private func verifyWorkbook(_ e: MappingExchangeExport) throws {
        let files = try e.write(); defer { files.cleanup() }
        XCTAssertEqual(files.urls[0].lastPathComponent, "FieldForge Exchange.xlsx")
        let parts = try unzip(Data(contentsOf: files.urls[0]))
        XCTAssertEqual(parts.count, e.tables.count + 7)
        for (_, data) in parts { _ = try parse(data) }
        XCTAssertFalse(parts.keys.contains { $0.contains("externalLink") || $0.contains("vba") })
        XCTAssertEqual(try parse(XCTUnwrap(parts["xl/workbook.xml"])).sheetNames, e.tables.map(\.name))
        for (i, table) in e.tables.enumerated() {
            let reader = try parse(XCTUnwrap(parts["xl/worksheets/sheet\(i + 1).xml"]))
            XCTAssertEqual(reader.formulas, 0)
            for (r, row) in ([table.columns.map(MappingCSVExport.Cell.text)] + table.rows).enumerated() {
                for (c, value) in row.enumerated() {
                    let actual = try XCTUnwrap(reader.cells[MappingXLSXExport.column(c + 1) + String(r + 1)])
                    switch value {
                    case .text(let text): XCTAssertEqual(actual.type, "inlineStr"); XCTAssertEqual(actual.value, text)
                    case .empty: XCTAssertNil(actual.type); XCTAssertEqual(actual.value, "")
                    default: XCTFail("Exchange must contain text or null, never numeric/date cells")
                    }
                }
            }
        }

    }
}

private final class ExchangeSheetReader: NSObject, XMLParserDelegate {
    struct Cell { let type: String?; var value = "" }
    var cells: [String: Cell] = [:], sheetNames: [String] = [], formulas = 0
    private var current: String?, capture = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "c", let r = attributes["r"] { current = r; cells[r] = Cell(type: attributes["t"]) }
        if name == "t" || name == "v" { capture = true }
        if name == "f" { formulas += 1 }
        if name == "sheet" { sheetNames.append(attributes["name"] ?? "") }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if capture, let current { cells[current]?.value += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" || name == "v" { capture = false }
        if name == "c", let key = current, let value = cells[key]?.value {
            // Decode ST_Xstring once; protected literal _xHHHH_ remains literal.
            let regex = try! NSRegularExpression(pattern: "_[xX]([0-9a-fA-F]{4})_")
            var decoded = value
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                let code = (value as NSString).substring(with: match.range(at: 1))
                if let v = UInt32(code, radix: 16), let scalar = UnicodeScalar(v), let range = Range(match.range, in: decoded) { decoded.replaceSubrange(range, with: String(scalar)) }
            }
            cells[key]?.value = decoded; current = nil
        }
    }
}
