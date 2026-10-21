import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingXLSXExportTests: XCTestCase {
    private let csv = MappingCSVExportTests()
    private func snapshot() throws -> MappingCSVExport {
        let (_, w, p) = try P33RevisionTests().seed()
        return try MappingCSVExport.prepare(journal: w.journal, selection: csv.selection(p, "2023-11-14T12:00:00Z"))
    }
    /// Independent central-directory reader (not the production ZIP implementation).
    /// Python zipfile independently checks CRCs and descriptors in the external validation.
    private func parts(_ export: MappingCSVExport) throws -> [String: Data] {
        let files = try MappingExportFiles.write(export, format: .xlsx); defer { files.cleanup() }
        return try unzip(Data(contentsOf: XCTUnwrap(files.urls.first)))
    }
    private func unzip(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func word(_ offset: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) } }
        XCTAssertEqual(word(bytes.count - 22, 4), 0x06054b50)
        let count = word(bytes.count - 12, 2), start = word(bytes.count - 6, 4)
        var pos = start, result: [String: Data] = [:]
        for _ in 0..<count {
            XCTAssertEqual(word(pos, 4), 0x02014b50)
            XCTAssertEqual(word(pos + 10, 2), 0) // store method
            let size = word(pos + 20, 4), length = word(pos + 28, 2), local = word(pos + 42, 4)
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + length)], as: UTF8.self)
            XCTAssertEqual(word(local, 4), 0x04034b50)
            let content = local + 30 + word(local + 26, 2) + word(local + 28, 2)
            XCTAssertNil(result[name]); result[name] = Data(bytes[content..<(content + size)])
            XCTAssertEqual(word(content + size, 4), 0x08074b50)
            XCTAssertEqual(word(content + size + 4, 4), word(pos + 16, 4))
            XCTAssertEqual(word(content + size + 8, 4), size)
            pos += 46 + length + word(pos + 30, 2) + word(pos + 32, 2)
        }
        XCTAssertEqual(pos, bytes.count - 22)
        return result
    }
    private func xml(_ data: Data) throws -> SheetReader {
        let reader = SheetReader(), parser = XMLParser(data: data); parser.delegate = reader
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "XML parsing")
        return reader
    }
    /// Compare every emitted sheet cell against its typed snapshot (no CSV apostrophes).
    @discardableResult private func verify(_ export: MappingCSVExport) throws -> [String: Data] {
        let package = try parts(export)
        XCTAssertEqual(package.count, 22 + export.fieldTables.count)
        for (name, data) in package { XCTAssertTrue(name.hasSuffix(".xml") || name.hasSuffix(".rels")); _ = try xml(data) }
        let book = try xml(XCTUnwrap(package["xl/workbook.xml"]))
        XCTAssertEqual(book.sheetNames, export.fieldTables.filter { $0.name != "field_links" }.map(\.name) + ["Сводка"] + export.tables.map(\.name) + export.fieldTables.filter { $0.name == "field_links" }.map(\.name))
        for (i, table) in export.tables.enumerated() {
            let data = try XCTUnwrap(package["xl/worksheets/sheet\(i + 2 + export.fieldTables.filter { $0.name != "field_links" }.count).xml"]), reader = try xml(data)
            XCTAssertEqual(reader.rowCount, table.rows.count + 1)
            XCTAssertEqual(reader.pane?["state"], "frozen"); XCTAssertEqual(reader.pane?["ySplit"], "1")
            XCTAssertEqual(reader.filter, "A1:\(MappingXLSXExport.column(table.columns.count))\(table.rows.count + 1)")
            XCTAssertEqual(reader.formulas, 0); XCTAssertEqual(reader.merges, 0)
            for (j, name) in table.columns.enumerated() {
                XCTAssertEqual(reader.cells[MappingXLSXExport.column(j + 1) + "1"]?.value, name)
            }
            for (r, row) in table.rows.enumerated() {
                for (c, value) in row.enumerated() {
                    let actual = try XCTUnwrap(reader.cells[MappingXLSXExport.column(c + 1) + String(r + 2)])
                    switch value {
                    case .text(let text): XCTAssertEqual(actual.type, "inlineStr"); XCTAssertEqual(actual.value, text)
                    case .number(let number):
                        if let number {
                            XCTAssertEqual(Double(actual.value), number)
                            XCTAssertEqual(actual.type, try MappingXLSXExport.numericText(number).isText ? "inlineStr" : "n")
                        } else { XCTAssertEqual(actual.value, ""); XCTAssertNil(actual.type) }
                    case .integer(let n): XCTAssertEqual(actual.value, n.map(String.init) ?? "")
                    case .timestamp(let date): XCTAssertEqual(actual.value, date.map(MappingCSVExport.iso) ?? "")
                    case .empty: XCTAssertEqual(actual.value, ""); XCTAssertNil(actual.type)
                    }
                }
            }
        }
        return package
    }
    func testAllTablesTypedCellsStylesAndFrozenHeaders() async throws {
        let package = try verify(snapshot())
        let styles = String(decoding: try XCTUnwrap(package["xl/styles.xml"]), as: UTF8.self)
        XCTAssertTrue(styles.contains("FF243746")); XCTAssertTrue(styles.contains("FFF0F5F7"))
        XCTAssertFalse(package.keys.contains { $0.contains("externalLink") || $0.contains("vba") })
    }
    func testTwoProjectsDatePeriodsScopesAndEmptySheetsUseSharedSelection() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        w.draft.picket = "20"; w.draft.observedAtOverride = csv.instant("2023-11-15T00:00:00Z"); _ = try w.save()
        try w.requestContext(MappingContext())
        let project = try w.createProject(name: "Второй проект"); try w.requestContext(MappingContext(projectID: project))
        let h = try w.createHorizon(elevation: "200"); try w.requestContext(MappingContext(projectID: project, horizonID: h))
        let e = try w.createExcavation(name: "Вторая", horizonIDs: [h]); try w.requestContext(MappingContext(projectID: project, horizonID: h, excavationID: e))
        w.draft.picket = "30"; w.draft.observedAtOverride = p.observedAt; let other = try w.save()
        for (point, day, count) in [(p, "2023-11-14T12:00:00Z", 1), (p, "2023-11-15T12:00:00Z", 1), (other, "2023-11-14T12:00:00Z", 1), (other, "2000-01-01T12:00:00Z", 0)] {
            var s = csv.selection(point, day); s.horizonID = point.horizonID; s.excavationID = point.excavationID
            let export = try MappingCSVExport.prepare(journal: w.journal, selection: s)
            XCTAssertEqual(export.pointCount, count); try verify(export)
        }
    }
    func testTimezoneDSTBoundariesRemainIdenticalInWorkbook() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        for (day, hours) in [("2024-03-10T12:00:00Z", 23.0), ("2024-11-03T12:00:00Z", 25.0)] {
            let s = csv.selection(p, day, zone: "America/New_York"), b = try s.bounds()
            XCTAssertEqual(b.end.timeIntervalSince(b.start), hours * 3600)
            for (instant, count) in [(b.start, 1), (b.end.addingTimeInterval(-0.001), 1), (b.end, 0)] {
                var c = try w.correction(for: p.id); c.reason = "Boundary"; c.fields.observedAtOverride = instant; c.fields.timeZoneID = s.timeZoneID
                _ = try w.saveCorrection(c)
                let export = try MappingCSVExport.prepare(journal: w.journal, selection: s)
                XCTAssertEqual(export.pointCount, count); try verify(export)
            }
        }
    }
    func testCorrectedPointOnceOriginalEvidenceAndStoredQWithPrecision() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        var c = try w.correction(for: p.id); c.reason = "Location"; c.fields.picket = "25"
        c.fields.x = "-123.12345678912345"; c.fields.y = "999999.123456789"; c.fields.notes = "=1+1"
        let revision = try w.saveCorrection(c)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: csv.selection(p, "2023-11-14T12:00:00Z"))
        try verify(export)
        let point = try XCTUnwrap(csv.rows(export, "points").first)
        XCTAssertEqual(export.pointCount, 1); XCTAssertEqual(point["revision_id"], revision.id.uuidString)
        XCTAssertEqual(try csv.rows(export, "measurements").count, 2)
        XCTAssertEqual(try csv.rows(export, "joint_sets").count, 2)
        XCTAssertEqual(try csv.rows(export, "interpretation_evidence").count, 4)
        XCTAssertEqual(try csv.rows(export, "assessments").first?["stored_q"].flatMap(Double.init), p.ratings?.bartonQ?.evaluation.result?.value)
        XCTAssertEqual(w.journal.measurements, initial.journal.measurements); XCTAssertEqual(w.journal.observations, [p])
    }
    func testCompletePartialUnknownFaultsIncompleteQAndInputOnlyRMR() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        w.draft.picket = "5"; w.draft.observedAtOverride = csv.instant("2024-01-01T00:00:00Z")
        var complete = TectonicStructureDraft(); complete.orientation = ManualOrientationInput(dipAngleText: "45.123456789123456", dipDirectionText: "120", reference: .trueNorth)
        var partial = TectonicStructureDraft(); partial.orientation.dipAngleText = "30"
        w.draft.tectonicStructures = [complete, partial, TectonicStructureDraft()]
        w.draft.bartonQ.missingReason = "Нет данных"; w.draft.rmr89.source = "Только ввод"
        let p = try w.save(), export = try MappingCSVExport.prepare(journal: w.journal, selection: csv.selection(p, "2024-01-01T12:00:00Z"))
        try verify(export)
        XCTAssertEqual(try csv.rows(export, "tectonic_structures").count, 3)
        XCTAssertTrue(try csv.rows(export, "assessments").allSatisfy { $0["stored_q"] == "" })
    }
    func testPhotoRegistersMissingFilesUnknownTimeHistoricalContextAndPlanRelationships() async throws {
        try verify(richSnapshot())
    }
    private func richSnapshot() throws -> MappingCSVExport {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let a = PhotoAttachment(id: UUID(), originalFilename: "фото, \"оригинал\".jpg", sha256: String(repeating: "a", count: 64), byteCount: 500, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1, orientation: 1, representation: "received bytes unchanged")
        var context = try w.journal.photoContext(for: p.id); context.locationBasis = .unknownBeforeFirstSave
        let photo = PhotoObservation(id: UUID(), attachmentID: a.id, context: context, source: .files, importedAt: p.observedAt, capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown", metadata: PhotoMetadata(name: "=1+1", description: "Русский, \"кавычки\"\nвторая строка"))
        try w.registerPhoto(PhotoImportOperation(version: 2, photo: photo, attachment: a))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let plans = ManagedPlanStore(root: temp)
        let plan = try plans.stage(data: DXFRealTests.data(200), filename: "survey.dxf", horizonID: p.horizonID, version: "survey-A", units: .millimeters, crs: "Mine grid", axes: "X north, Y east")
        try w.registerPlan(plan)
        var c = try w.correction(for: p.id); c.reason = "Position"
        try c.fields.selectPlanPoint(PlanPoint(x: -123.12345678912345, y: 456), plan: plan)
        c.fields.notes = "Русский, \"кавычки\"\nвторая строка"; _ = try w.saveCorrection(c)
        return try MappingCSVExport.prepare(journal: w.journal, selection: csv.selection(p, "2023-11-14T12:00:00Z"))
    }
    func testLiteralFormulaStringsControlEscapesAndNumericCellLimits() async throws {
        for value in ["=1+1", "+1", "-1", "@SUM(A1)", "'literal", " \t=1+1", "Русский, \"кавычки\"\nстрока"] {
            let xml = try MappingXLSXExport.cell(.text(value), reference: "A1", style: 0)
            let reader = try self.xml(Data(("<root>" + xml + "</root>").utf8))
            XCTAssertEqual(reader.cells["A1"]?.value, value); XCTAssertEqual(reader.cells["A1"]?.type, "inlineStr"); XCTAssertEqual(reader.formulas, 0)
        }
        XCTAssertEqual(MappingXLSXExport.escape("\u{0001}\r_x0041_ & < >"), "_x0001__x000D__x005F_x0041_ &amp; &lt; &gt;")
        for n in [123.12345678912345, 1.2345678901234567e-100, Double.leastNonzeroMagnitude] { XCTAssertTrue(try MappingXLSXExport.numericText(n).isText) }
        for n in [0.0, -42, 123.123456789, 1e20] { XCTAssertFalse(try MappingXLSXExport.numericText(n).isText) }
        XCTAssertTrue(try MappingXLSXExport.cell(.integer(1234567890123456), reference: "A1", style: 0).contains("inlineStr"))
        XCTAssertThrowsError(try MappingXLSXExport.numericText(.nan))
        XCTAssertThrowsError(try MappingXLSXExport.numericText(.infinity))
        XCTAssertThrowsError(try MappingXLSXExport.cell(.text(String(repeating: "я", count: 32_768)), reference: "A1", style: 0))
        XCTAssertNoThrow(try MappingXLSXExport.cell(.text(String(repeating: "я", count: 32_767)), reference: "A1", style: 0))
        XCTAssertEqual(MappingXLSXExport.column(16_384), "XFD")
    }
    func testSummaryCountsWarningsUnitsProvenanceAndPrecisionPolicy() async throws {
        let export = try richSnapshot(), summary = try MappingXLSXExport.summary(export)
        let all = summary.rows.map { row in row.map { if case .text(let s) = $0 { return s }; return "" }.joined() }.joined(separator: "\n")
        for text in ["15 значащих", "НЕ полная", "Barton Q", "RMR89", "unknownBeforeFirstSave", "xy_units", "32767"].dropLast() { XCTAssertTrue(all.contains(text)) }
        XCTAssertTrue(summary.rows.contains { row in if case .text("Фото без времени съёмки") = row[0], case .integer(1) = row[1] { return true }; return false })
    }
    func testFrozenSnapshotRepeatDismissAndCleanupPreserveSources() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: csv.selection(p, "2023-11-14T12:00:00Z"))
        var c = try w.correction(for: p.id); c.reason = "Later"; c.fields.picket = "999"; _ = try w.saveCorrection(c)
        let first = try MappingExportFiles.write(export, format: .xlsx), bytes = try Data(contentsOf: first.urls[0])
        first.cleanup(); XCTAssertFalse(FileManager.default.fileExists(atPath: first.directory.path))
        let second = try MappingExportFiles.write(export, format: .xlsx); defer { second.cleanup() }
        XCTAssertNotEqual(first.directory, second.directory); XCTAssertEqual(try Data(contentsOf: second.urls[0]), bytes)
        let path: URL
        do { let dismissed = try MappingExportFiles.write(export, format: .xlsx); path = dismissed.directory }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(w.journal.observations, [p]); try verify(export)
    }
    func testPartialWriteFailureCancellationRetryAndOnlyOwnedFilesRemoved() async throws {
        let export = try snapshot(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json"), bytes = Data("evidence".utf8); try bytes.write(to: source)
        enum Failure: Error { case disk }
        var writes = 0
        XCTAssertThrowsError(try MappingExportFiles.write(export, parent: root, format: .xlsx, xlsxAppend: { data, handle in
            try handle.write(contentsOf: data); writes += 1; if writes == 20 { throw Failure.disk }
        }))
        for cancelAfter in [0, 30] {
            let task = Task.detached {
                if cancelAfter == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                var count = 0
                return try MappingExportFiles.write(export, parent: root, format: .xlsx, xlsxAppend: { data, handle in
                    try handle.write(contentsOf: data); count += 1; if count == cancelAfter { withUnsafeCurrentTask { $0?.cancel() } }
                })
            }
            do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["source.json"])
        let retry = try MappingExportFiles.write(export, parent: root, format: .xlsx); retry.cleanup()
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testOversizedCellFailureCleansPartialWorkbookWithoutTruncation() async throws {
        let original = try snapshot()
        let export = MappingCSVExport(id: original.id, snapshotAt: original.snapshotAt, selection: original.selection,
            tables: [.init(name: "projects", columns: ["name"], rows: [[.text(String(repeating: "x", count: 32_768))]])], manifest: original.manifest)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try MappingExportFiles.write(export, parent: root, format: .xlsx))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testIndependentWorkbookFixtureWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["P52_EXPORT_FIXTURE_DIR"] else { throw XCTSkip("Opt-in independent workbook fixture") }
        let export = try richSnapshot(), root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = try MappingExportFiles.write(export, format: .xlsx); defer { files.cleanup() }
        let target = root.appendingPathComponent("FieldForge-Mapping.xlsx")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: files.urls[0], to: target)
        var expected: [String: Any] = [:]
        for table in export.tables {
            expected[table.name] = ["columns": table.columns, "rows": table.rows.map { row in row.map { value -> [String: Any] in
                switch value {
                case .text(let s): return ["type": "s", "value": s]
                case .number(let n):
                    guard let n else { return ["type": "blank"] }; let cell = try! MappingXLSXExport.numericText(n)
                    return ["type": cell.isText ? "s" : "n", "value": cell.isText ? cell.value as Any : n as Any]
                case .integer(let n): return n.map { ["type": "n", "value": $0] } ?? ["type": "blank"]
                case .timestamp(let d): return d.map { ["type": "s", "value": MappingCSVExport.iso($0)] } ?? ["type": "blank"]
                case .empty: return ["type": "blank"]
                }
            } }]
        }
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("expected.json"))
    }
}

private final class SheetReader: NSObject, XMLParserDelegate {
    struct Cell { let type: String?; var value: String }
    var cells: [String: Cell] = [:], sheetNames: [String] = [], rowCount = 0, formulas = 0, merges = 0
    var pane: [String: String]?, filter: String?, current: String?, capture = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch name {
        case "c": current = attributes["r"]; if let current { cells[current] = Cell(type: attributes["t"], value: "") }
        case "t", "v": capture = true
        case "sheet": sheetNames.append(attributes["name"] ?? "")
        case "row": rowCount += 1
        case "f": formulas += 1
        case "mergeCell": merges += 1
        case "pane": pane = attributes
        case "autoFilter": filter = attributes["ref"]
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if capture, let current { cells[current]?.value += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" || name == "v" { capture = false }; if name == "c" { current = nil }
    }
}
