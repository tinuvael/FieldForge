import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class GSIChartTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testTouchCoordinatesAndOutsideDragDoNotClampOrRound() throws {
        let p = try XCTUnwrap(GSIChartPosition.touch(x: 75, y: 200, width: 300, height: 500))
        XCTAssertEqual(p, GSIChartPosition(x: 0.25, y: 0.4))
        XCTAssertEqual(GSIChartPosition.touch(x: 150, y: 400, width: 600, height: 1000), p)
        for (x, y, w, h) in [(-1.0, 1.0, 300.0, 500.0), (301, 1, 300, 500), (1, 501, 300, 500), (1, 1, 0, 500), (.nan, 1, 300, 500)] {
            XCTAssertNil(GSIChartPosition.touch(x: x, y: y, width: w, height: h))
        }
    }
    func testIndependentSourceContourControls() throws {
        // Independent transcriptions from Table 5.34's PDF drawing operators, printed p.126.
        // These source-space checkpoints are not generated from GSIChart.contours.
        for (x, y, expected) in [(304.9227959, 281.2905974, 90), (320.6692959, 299.4105974, 80),
                                  (327.0967959, 309.9729004, 75), (336.3170996, 371.7663979, 55),
                                  (343.4701044, 384.6459999, 50), (387.2880054, 395.127307, 35),
                                  (427.649501, 483.7995994, 10)] {
            let p = GSIChartPosition(x: (x-289.24)/155.9765042, y: (y-267.216507)/257.5161922)
            XCTAssertEqual(GSIChart.estimate(p)?.value, expected)
        }
        XCTAssertEqual(GSIChart.contours.count, 19)
    }
    func testInvalidRegionsAndPublishedAxisOrder() {
        XCTAssertNil(GSIChart.categories(GSIChartPosition(x: 0.8, y: 0.05)))
        XCTAssertNil(GSIChart.categories(GSIChartPosition(x: 0.2, y: 0.95)))
        XCTAssertNil(GSIChart.categories(GSIChartPosition(x: 1.01, y: 0.5)))
        XCTAssertNil(GSIChart.estimate(GSIChartPosition(x: 0, y: 0))) // No invented 100 contour.
        XCTAssertNil(GSIChart.estimate(GSIChartPosition(x: 1, y: 1))) // No invented zero contour.
        XCTAssertEqual(GSIChart.categories(GSIChartPosition(x: 0.5, y: 0.4))?.structure, .veryBlocky)
        XCTAssertEqual(GSIChart.categories(GSIChartPosition(x: 0.5, y: 0.4))?.surface, .fair)
        let edge = GSIChart.surfaceEdges[3], row = GSIChart.structureEdges[1]
        XCTAssertNil(GSIChart.categories(GSIChartPosition(x: edge, y: row.nextDown)))
        XCTAssertNotNil(GSIChart.categories(GSIChartPosition(x: edge, y: row)))
    }
    func testAdjacentContoursBracketInterpolationAndIntegerBoundary() throws {
        // On y=0.5 a horizontal transect crosses the calibrated 55 and 50 lines.
        let high = GSIChart.contours.first { $0.value == 55 }!, low = GSIChart.contours.first { $0.value == 50 }!
        func crossing(_ c: GSIChart.Contour, y: Double) -> Double {
            c.a.x + (y-c.a.y) * (c.b.x-c.a.x)/(c.b.y-c.a.y)
        }
        let a = crossing(high, y: 0.5), b = crossing(low, y: 0.5)
        XCTAssertEqual(GSIChart.estimate(GSIChartPosition(x: a, y: 0.5))?.value, 55)
        XCTAssertEqual(GSIChart.estimate(GSIChartPosition(x: b, y: 0.5))?.value, 50)
        let mid = try XCTUnwrap(GSIChart.estimate(GSIChartPosition(x: (a+b)/2, y: 0.5)))
        XCTAssertEqual(mid.lower, 50); XCTAssertEqual(mid.upper, 55)
        XCTAssertTrue((52...53).contains(mid.value))
        for step in 0...100 {
            let result = try XCTUnwrap(GSIChart.estimate(GSIChartPosition(x: a+(b-a)*Double(step)/100, y: 0.5)))
            XCTAssertTrue((50...55).contains(result.value))
        }
    }
    func testExactPositionSaveReopenCorrectionAndCategoricalCompatibility() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("mapping.json")
        let store = FileMappingStore(url: file), (_, initial) = try P2MappingTests().configured()
        try store.save(initial.journal); var w = try MappingWorkflow(store: store)
        let p = GSIChartPosition(x: 0.512345678912345, y: 0.456789123456789)
        w.draft.picket = "1"; w.draft.gsi = try GSIAssessment(position: p, assessedAt: now)
        let original = try w.save(now: now)
        var reopened = try MappingWorkflow(store: FileMappingStore(url: file))
        var edit = try reopened.correction(for: original.id)
        XCTAssertEqual(edit.fields.gsi?.chartPosition, p)
        let newPosition = GSIChartPosition(x: 0.6, y: 0.55)
        edit.fields.gsi = try GSIAssessment(position: newPosition, assessedAt: now.addingTimeInterval(60)); edit.reason = "Уточнение диаграммы"
        let revision = try reopened.saveCorrection(edit, now: now.addingTimeInterval(60))
        XCTAssertEqual(revision.snapshot.ratings?.gsi?.chartPosition, newPosition)
        XCTAssertEqual(try FileMappingStore(url: file).load().observations.first, original)
        let legacy = GSIAssessment(selection: GSIChartSelection(structure: .veryBlocky, surface: .fair), lower: 35, upper: 45, finalValue: 40, assessedAt: now)
        let decoded = try JSONDecoder().decode(GSIAssessment.self, from: JSONEncoder().encode(legacy))
        try decoded.validate(); XCTAssertEqual(decoded, legacy); XCTAssertNil(decoded.chartPosition)
        edit = try reopened.correction(for: original.id); edit.reason = "Старая оценка"; edit.fields.gsi = legacy
        _ = try reopened.saveCorrection(edit, now: now.addingTimeInterval(120))
        XCTAssertNil(try FileMappingStore(url: file).load().effectiveObservation(id: original.id)?.ratings?.gsi?.chartPosition)
    }
    func testTamperedResultPositionOrVersionRejectsWithoutWriting() throws {
        let gsi = try GSIAssessment(position: GSIChartPosition(x: 0.5, y: 0.45), assessedAt: now)
        try gsi.validate()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(gsi)) as? [String: Any])
        for (key, value) in [("finalValue", 99 as Any), ("method", "invented"), ("chartPosition", ["x": 0.9, "y": 0.05])] {
            var changed = object; changed[key] = value
            let decoded = try JSONDecoder().decode(GSIAssessment.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertThrowsError(try decoded.validate())
        }
    }
    func testOrdinaryEnterpriseAndRelationalExportsKeepNewGSIAndExactPosition() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let p = GSIChartPosition(x: 0.5, y: 0.45), gsi = try GSIAssessment(position: p, assessedAt: now)
        w.draft.gsi = gsi; w.draft.picket = "1"; w.draft.observedAtOverride = now
        _ = try w.save(now: now)
        let selection = MappingExportSelection(projectID: try XCTUnwrap(w.context.projectID), firstDay: now, lastDay: now, timeZoneID: "UTC")
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection, now: now, includeEnterprise: true)
        let ordinary = try XCTUnwrap(export.fieldTables.first { $0.name == "Наблюдения" })
        let value = try XCTUnwrap(ordinary.columns.firstIndex(of: "GSI · оценка"))
        guard case .number(let n) = ordinary.rows[0][value] else { return XCTFail("GSI must be a numeric Excel cell") }
        XCTAssertEqual(n, gsi.finalValue)
        XCTAssertEqual(export.enterpriseTables.count, 3)
        let enterprise = export.enterpriseTables[0]
        XCTAssertTrue(enterprise.columns.contains("GSI X")); XCTAssertTrue(enterprise.columns.contains("GSI Y"))
        let raw = try XCTUnwrap(export.tables.first { $0.name == "assessments" })
        XCTAssertTrue(String(decoding: raw.data, as: UTF8.self).contains(GSIChart.version))
        for table in export.tables + export.fieldTables + export.enterpriseTables {
            XCTAssertTrue(table.rows.allSatisfy { $0.count == table.columns.count }, table.name)
        }
    }
}
