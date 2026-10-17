import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class DXFAnnotationTests: XCTestCase {
    func testPointOnlyAndPlainRotatedUnicodeAnnotationsHaveDefinedCoordinatesAndSize() throws {
        let point = "0\nPOINT\n10\n123.125\n20\n-22.5\n30\n350\n"
        let text = "0\nTEXT\n10\n10\n20\n20\n30\n9\n40\n2.5\n50\n90\n1\n  ПК \\U+0410 %%d  \n"
        let mtext = "0\nMTEXT\n10\n30\n20\n40\n30\n50\n40\n3\n71\n1\n50\n1.5707963267948966\n3\nПервая\\P\n1\nВторая\\~строка\n"
        let d = try DXFDocument.parse(DXFFixtures.drawing(point + text + mtext))
        XCTAssertEqual(d.points, [DXFVertex(x: 123.125, y: -22.5, z: 350)])
        XCTAssertEqual(d.labels.count, 2)
        XCTAssertEqual(d.labels[0].position, DXFVertex(x: 10, y: 20, z: 9))
        XCTAssertEqual(d.labels[0].text, "  ПК А °  ")
        XCTAssertEqual(d.labels[0].height, 2.5); XCTAssertEqual(d.labels[0].rotationDegrees, 90)
        XCTAssertFalse(d.labels[0].topAligned)
        XCTAssertEqual(d.labels[1].text, "Первая\nВторая\u{00A0}строка")
        XCTAssertEqual(d.labels[1].rotationDegrees, 90, accuracy: 1e-10); XCTAssertTrue(d.labels[1].topAligned)
        XCTAssertTrue(d.warnings.contains { $0.contains("POINT") })
        XCTAssertTrue(d.warnings.contains { $0.contains("TEXT/MTEXT") })
        let onlyPoint = try DXFDocument.parse(DXFFixtures.drawing(point))
        XCTAssertTrue(onlyPoint.paths.isEmpty)
        XCTAssertEqual(onlyPoint.bounds, PlanBounds(minX: 123.125, minY: -22.5, maxX: 123.125, maxY: -22.5))
        XCTAssertEqual(try DXFDocument.parse(DXFFixtures.drawing(text)).labels.count, 1)
    }
    func testUnsupportedAnnotationFeaturesAreCountedInsteadOfInvented() throws {
        let text = "0\nTEXT\n10\n1\n20\n2\n40\n2\n1\nLabel\n"
        let mtext = "0\nMTEXT\n10\n1\n20\n2\n40\n2\n1\nLabel\n"
        let rich = "0\nMTEXT\n10\n1\n20\n2\n40\n2\n1\n{\\C1;red} text\n"
        let d = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + text + "72\n1\n" + text + "71\n2\n"
            + mtext + "71\n5\n" + rich + "0\nINSERT\n" + "0\nSPLINE\n"))
        XCTAssertTrue(d.labels.isEmpty)
        let columns = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + mtext + "75\n1\n50\n2\n50\n3\n"))
        XCTAssertTrue(columns.labels.isEmpty)
        XCTAssertTrue(columns.warnings.contains { $0.contains("columns") })
        for feature in ["alignment/mirror", "attachment/direction", "formatting", "INSERT", "SPLINE"] {
            XCTAssertTrue(d.warnings.contains { $0.contains(feature) }, feature)
        }
        XCTAssertTrue(d.warnings.contains { $0.contains("TEXT (alignment/mirror/width/oblique): 2") })
        XCTAssertThrowsError(try DXFDocument.parse(DXFFixtures.drawing(text + "40\n5\n")))
        XCTAssertNil(DXFAnnotationText.decode("\\S1/2;", multiline: true))
        XCTAssertNil(DXFAnnotationText.decode("%<field>%", multiline: true))
        let direction = try DXFDocument.parse(DXFFixtures.drawing(mtext + "50\n0\n11\n0\n21\n1\n"))
        XCTAssertEqual(direction.labels[0].rotationDegrees, 90)
        let angleLast = try DXFDocument.parse(DXFFixtures.drawing(mtext + "11\n0\n21\n1\n50\n0\n"))
        XCTAssertEqual(angleLast.labels[0].rotationDegrees, 0)
    }
    func testLegacyCyrillicAndUnsupportedEncodingAreExplicit() throws {
        let text = "0\nTEXT\n10\n1\n20\n2\n40\n2\n1\nГоризонт\n"
        let source = String(data: DXFFixtures.drawing(text), encoding: .utf8)!
            .replacingOccurrences(of: "9\n$INSUNITS", with: "9\n$DWGCODEPAGE\n3\nANSI_1251\n9\n$INSUNITS")
        let cp1251 = try XCTUnwrap(source.data(using: .windowsCP1251))
        XCTAssertEqual(try DXFDocument.parse(cp1251).labels.first?.text, "Горизонт")
        let unsupported = source.replacingOccurrences(of: "ANSI_1251", with: "ANSI_1252")
        XCTAssertThrowsError(try DXFDocument.parse(XCTUnwrap(unsupported.data(using: .windowsCP1251))))
    }
    func testClosed3DSequencesPreserveZAndRejectMeshFitVertexFlagsVisibilityAndOCS() throws {
        let vertices = "0\nVERTEX\n70\n32\n10\n1\n20\n2\n30\n100\n0\nVERTEX\n70\n32\n10\n3\n20\n4\n30\n200\n0\nSEQEND\n"
        let d = try DXFDocument.parse(DXFFixtures.drawing("0\nPOLYLINE\n70\n9\n" + vertices))
        XCTAssertEqual(d.paths[0], [PlanPoint(x: 1, y: 2), PlanPoint(x: 3, y: 4), PlanPoint(x: 1, y: 2)])
        XCTAssertEqual(d.polylines[0].vertices.map(\.z), [100, 200]); XCTAssertTrue(d.polylines[0].closed)
        for flag in [10, 12, 16, 32, 64, 72] {
            let skipped = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + "0\nPOLYLINE\n70\n\(flag)\n" + vertices))
            XCTAssertTrue(skipped.polylines.isEmpty)
            XCTAssertTrue(skipped.warnings.contains { $0.contains("POLYLINE") && $0.contains("Пропущено") })
        }
        for fields in ["60\n1\n", "67\n1\n", "410\nLayout1\n", "210\n0\n220\n1\n230\n0\n"] {
            let skipped = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + "0\nPOLYLINE\n70\n8\n" + fields + vertices))
            XCTAssertTrue(skipped.polylines.isEmpty)
        }
        for layerFields in ["70\n1\n62\n7\n", "70\n0\n62\n-7\n"] {
            let source = String(data: DXFFixtures.drawing(DXFFixtures.line + "0\nPOLYLINE\n70\n8\n8\nHIDDEN\n" + vertices), encoding: .utf8)!
                .replacingOccurrences(of: "0\nSECTION\n2\nENTITIES", with: "0\nSECTION\n2\nTABLES\n0\nLAYER\n2\nHIDDEN\n" + layerFields + "0\nENDSEC\n0\nSECTION\n2\nENTITIES")
            let hidden = try DXFDocument.parse(Data(source.utf8))
            XCTAssertTrue(hidden.polylines.isEmpty); XCTAssertEqual(hidden.paths.count, 1)
        }
        let badVertex = vertices.replacingOccurrences(of: "70\n32\n", with: "70\n64\n")
        XCTAssertTrue(try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + "0\nPOLYLINE\n70\n8\n" + badVertex)).polylines.isEmpty)
        XCTAssertThrowsError(try DXFDocument.parse(DXFFixtures.drawing("0\nPOLYLINE\n70\n8\n0\nVERTEX\n70\n32\n10\n1\n20\n2\n")))
    }
}
