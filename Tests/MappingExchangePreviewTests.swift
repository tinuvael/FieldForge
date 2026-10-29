import XCTest
import zlib
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingExchangePreviewTests: XCTestCase {
    private let time = Date(timeIntervalSinceReferenceDate: 721234567.1234567)
    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", n))! }
    private func fixture(longOriginal: Bool = false) throws -> MappingJournal {
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
        w.draft.bartonQ = q; w.draft.rmr89.source = "Input only"
        w.draft.gsi = GSIAssessment(selection: .init(structure: .veryBlocky, surface: .fair), lower: 35, upper: 45, finalValue: nil, assessedAt: time)
        let original = try w.save(now: time)
        var correction = try w.correction(for: original.id); correction.reason = "Проверка"; correction.fields.notes = "Исправлено 🪨 _x0020_\r\n=literal"
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
    func testNotesAndManualCoordinatesCorrectionWithoutRounding() throws {
        let j = try fixture(), e = try export(j)
        let edited = edit(e, sheet: "points", values: ["notes": "Новое описание", "x": "123456789.1234568", "correction_reason": "Уточнение"])
        let p = try preview(edited, journal: j)
        XCTAssertEqual(p.count(.correction), 1); XCTAssertFalse(p.hasBlockingRecords)
        XCTAssertEqual(p.records[0].proposed?.coordinates?.x, 123456789.1234568)
        XCTAssertTrue(p.records[0].changes.contains { $0.field == "notes" && $0.before.contains("Исправлено") && $0.after == "Новое описание" })
        XCTAssertEqual(p.records[0].proposed?.measurementIDs, j.observations[0].measurementIDs)
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
        XCTAssertEqual(try preview(disagreement, journal: j).count(.invalid), 1)
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
        XCTAssertEqual(try preview(truncated, journal: j).count(.invalid), 1)
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
            return try ExchangeObservationProposal.patched(p, fields: ["geology": MappingExchangeExport.json(geology)])
        }
        j.observations[0] = try legacy(j.observations[0])
        j.revisions[0] = try ExchangeObservationProposal.patched(j.revisions[0], fields: ["snapshot": MappingExchangeExport.json(legacy(j.revisions[0].snapshot))])
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
