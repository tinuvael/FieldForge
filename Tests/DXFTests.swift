import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Small synthetic ASCII DXF fixtures. Expected coordinates are literal CAD control
/// vertices/cardinal circle points, not outputs of the parser. See docs/p2-dxf.md.
enum DXFFixtures {
    static func drawing(_ entities: String, units: Int = 6) -> Data {
        Data("0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n\(units)\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n\(entities)0\nENDSEC\n0\nEOF\n".utf8)
    }
    static let line = "0\nLINE\n10\n100\n20\n200\n11\n300\n21\n400\n"
    static let lwpolyline = "0\nLWPOLYLINE\n90\n3\n70\n1\n10\n0\n20\n0\n10\n10\n20\n0\n10\n10\n20\n20\n"
    static let polyline = "0\nPOLYLINE\n70\n1\n0\nVERTEX\n10\n-5\n20\n-10\n0\nVERTEX\n10\n5\n20\n-10\n0\nSEQEND\n"
    static let circle = "0\nCIRCLE\n10\n50\n20\n60\n40\n10\n"
    static let arc = "0\nARC\n10\n0\n20\n0\n40\n20\n50\n270\n51\n90\n"
}

final class DXFTests: XCTestCase {
    func testIndependentLineAndPolylineControlVertices() throws {
        let d = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + DXFFixtures.lwpolyline + DXFFixtures.polyline))
        XCTAssertEqual(d.insertionUnits, 6); XCTAssertEqual(d.paths.count, 3)
        XCTAssertEqual(d.paths[0], [PlanPoint(x: 100, y: 200), PlanPoint(x: 300, y: 400)])
        XCTAssertEqual(d.paths[1], [PlanPoint(x: 0,y: 0), PlanPoint(x: 10,y: 0), PlanPoint(x: 10,y: 20), PlanPoint(x: 0,y: 0)])
        XCTAssertEqual(d.paths[2], [PlanPoint(x: -5,y: -10), PlanPoint(x: 5,y: -10), PlanPoint(x: -5,y: -10)])
        let text = "\u{FEFF}999\nCAD fixture comment\n" + String(data: DXFFixtures.drawing(DXFFixtures.line), encoding: .utf8)!
        XCTAssertEqual(try DXFDocument.parse(Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)).paths[0], d.paths[0])
    }
    func testCircleAndCounterclockwiseArcCardinalCoordinates() throws {
        let d = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.circle + DXFFixtures.arc))
        let c = d.paths[0], a = d.paths[1]
        XCTAssertEqual(c[0], PlanPoint(x: 60, y: 60))
        XCTAssertEqual(c[90].x, 50, accuracy: 1e-10); XCTAssertEqual(c[90].y, 70, accuracy: 1e-10)
        XCTAssertEqual(c[180].x, 40, accuracy: 1e-10); XCTAssertEqual(c[270].y, 50, accuracy: 1e-10)
        XCTAssertEqual(a.first!.x, 0, accuracy: 1e-10); XCTAssertEqual(a.first!.y, -20, accuracy: 1e-10)
        XCTAssertEqual(a[90].x, 20, accuracy: 1e-10); XCTAssertEqual(a[90].y, 0, accuracy: 1e-10)
        XCTAssertEqual(a.last!.x, 0, accuracy: 1e-10); XCTAssertEqual(a.last!.y, 20, accuracy: 1e-10)
    }
    func testViewportKnownScreenCoordinatesAfterPanZoomAndWindowRotation() {
        let bounds = PlanBounds(minX: 100, minY: 200, maxX: 300, maxY: 400)
        let fitted = PlanViewport(bounds: bounds, width: 448, height: 248)
        XCTAssertEqual(fitted.screen(PlanPoint(x: 100, y: 200)), PlanPoint(x: 124,y: 224))
        XCTAssertEqual(fitted.drawing(PlanPoint(x: 224,y: 124)), PlanPoint(x: 200,y: 300))
        let moved = PlanViewport(bounds: bounds, width: 448, height: 248, zoom: 2, pan: PlanPoint(x: 35,y: -17))
        XCTAssertEqual(moved.screen(PlanPoint(x: 250,y: 350)), PlanPoint(x: 359,y: 7))
        XCTAssertEqual(moved.drawing(PlanPoint(x: 359,y: 7)), PlanPoint(x: 250,y: 350))
        let portrait = PlanViewport(bounds: bounds, width: 248, height: 448)
        XCTAssertEqual(portrait.drawing(PlanPoint(x: 24,y: 324)), PlanPoint(x: 100,y: 200))
        // Large mine coordinates must stay Double-precision before screen rebasing.
        let large = PlanViewport(bounds: PlanBounds(minX: 1e9,minY: -1e9,maxX: 1e9+200,maxY: -1e9+200),width: 448,height: 248,zoom: 7)
        let p = PlanPoint(x: 1e9+0.125,y: -1e9+199.875)
        XCTAssertEqual(large.drawing(large.screen(p)), p)
        XCTAssertFalse(moved.containsScreenPoint(moved.screen(PlanPoint(x: Double.greatestFiniteMagnitude, y: 0))))
        XCTAssertTrue(moved.containsScreenPoint(PlanPoint(x: 224, y: 124)))
    }
    func testCorruptionBinaryUnsupportedAndNonDefaultOCSAreExplicit() throws {
        let malformed = [Data(), Data("broken".utf8), Data([0,1,2]), Data("0\nEOF\n".utf8),
                         DXFFixtures.drawing("0\nLINE\n10\nnan\n20\n0\n11\n1\n21\n2\n"),
                         DXFFixtures.drawing("0\nPOLYLINE\n70\n0\n"),
                         DXFFixtures.drawing("0\nCIRCLE\n10\n0\n20\n0\n40\n-1\n"),
                         DXFFixtures.drawing("0\nLWPOLYLINE\n90\n4\n10\n0\n20\n0\n")]
        for data in malformed { XCTAssertThrowsError(try DXFDocument.parse(data)) }
        let unsupported = "0\nINSERT\n2\nBLOCK_A\n10\n0\n20\n0\n0\nSPLINE\n"
        XCTAssertThrowsError(try DXFDocument.parse(DXFFixtures.drawing(unsupported)))
        let partial = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + unsupported + DXFFixtures.circle + "210\n0\n220\n1\n230\n0\n"))
        XCTAssertEqual(partial.paths.count, 1)
        XCTAssertTrue(partial.warnings.contains { $0.contains("INSERT") })
        XCTAssertTrue(partial.warnings.contains { $0.contains("SPLINE") })
        XCTAssertTrue(partial.warnings.contains { $0.contains("OCS") })
        let bulge = DXFFixtures.lwpolyline + "42\n0.5\n"
        let d = try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.line + bulge))
        XCTAssertEqual(d.paths.count, 1); XCTAssertTrue(d.warnings.contains { $0.contains("bulge") })
    }
    func testMultipleImportsIntegrityRecoveryPlanPointsAndIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ManagedPlanStore(root: directory)
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        let context = w.context
        let a = try files.stage(data: DXFFixtures.drawing(DXFFixtures.line), filename: "survey.dxf", horizonID: context.horizonID!, version: "A", units: .unknown, crs: "", axes: "")
        let b = try files.stage(data: DXFFixtures.drawing(DXFFixtures.circle), filename: "survey.dxf", horizonID: context.horizonID!, version: "B", units: .meters, crs: "mine grid A", axes: "X north; Y east")
        store.fail = true; XCTAssertThrowsError(try w.registerPlan(a)); XCTAssertEqual(try files.pending().count, 2)
        store.fail = false
        let reopened = ManagedPlanStore(root: directory)
        XCTAssertTrue(try reopened.pending().contains(a)); XCTAssertEqual(try reopened.read(a), DXFFixtures.drawing(DXFFixtures.line))
        try w.registerPlan(a); files.complete(a); try w.registerPlan(b); files.complete(b)
        XCTAssertEqual(w.plans.count, 2); XCTAssertEqual(try files.pending().count, 0)
        w.draft.picket = "5"; w.draft.notes = "retain"; w.draft.z = "390.5"
        let date = Date(timeIntervalSince1970: 123); w.draft.observedAtOverride = date
        try w.selectPlanPoint(PlanPoint(x: 100,y: 200), planID: a.id)
        XCTAssertEqual(w.draft.z, "390.5"); XCTAssertEqual(w.draft.notes, "retain"); XCTAssertEqual(w.draft.observedAtOverride, date)
        let first = try w.save()
        XCTAssertEqual(first.coordinates?.units, "drawing"); XCTAssertEqual(first.coordinates?.crs, "unknown")
        XCTAssertEqual(first.coordinates?.planID, a.id); XCTAssertEqual(first.coordinates?.source, "plan")
        XCTAssertEqual(first.coordinates?.zOrigin, .manualOverride)
        XCTAssertEqual(w.points(on: a), [first]); XCTAssertTrue(w.points(on: b).isEmpty)
        w.draft.picket = "10"; try w.selectPlanPoint(PlanPoint(x: 100,y: 200), planID: a.id)
        let second = try w.save(); XCTAssertEqual(w.points(on: a), [first, second]) // overlapping records survive
        XCTAssertEqual(w.points(on: a, excavationID: UUID()), [])
        let otherH = try w.createHorizon(elevation: "615")
        try w.requestContext(MappingContext(projectID: context.projectID,horizonID: otherH))
        XCTAssertTrue(w.plans.isEmpty); XCTAssertTrue(w.points(on: a).isEmpty)
        XCTAssertThrowsError(try w.selectPlanPoint(PlanPoint(x: 0,y: 0),planID: a.id))
        let otherP = try w.createProject(name: "Other")
        try w.requestContext(MappingContext(projectID: otherP))
        XCTAssertTrue(w.plans.isEmpty); XCTAssertTrue(w.points(on: a).isEmpty)
        try w.requestContext(context); XCTAssertEqual(w.points(on: a).map(\.id), [first.id, second.id])
        let intact = try files.read(a)
        var changed = intact; changed[changed.count - 2] = 88
        try changed.write(to: files.fileURL(a))
        XCTAssertThrowsError(try files.read(a)) // Same length, changed SHA-256.
        try Data("damage".utf8).write(to: files.fileURL(a))
        XCTAssertThrowsError(try files.read(a)); XCTAssertEqual(w.points(on: a), [first, second])
    }
    func testHiddenLayersAndPaperSpaceAreSkippedWithWarnings() throws {
        let table = "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n0\nLAYER\n2\nHIDDEN\n70\n1\n62\n7\n0\nENDTAB\n0\nENDSEC\n"
        let source = String(data: DXFFixtures.drawing(DXFFixtures.line + DXFFixtures.circle + "8\nHIDDEN\n" + DXFFixtures.arc + "67\n1\n"), encoding: .utf8)!
            .replacingOccurrences(of: "0\nSECTION\n2\nENTITIES", with: table + "0\nSECTION\n2\nENTITIES")
        let drawing = try DXFDocument.parse(Data(source.utf8))
        XCTAssertEqual(drawing.paths.count, 1)
        XCTAssertTrue(drawing.warnings.contains { $0.contains("visibility") })
    }
    func testUnsupportedImportDoesNotCreateManagedOperations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = ManagedPlanStore(root: dir)
        XCTAssertThrowsError(try files.stage(data: Data("corrupt".utf8), filename: "x.dxf", horizonID: UUID(), version: "1", units: .unknown, crs: "", axes: ""))
        XCTAssertEqual(try files.pending(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
    func testPlanXYEditingRetainsDeclaredUnitsAndClearedZ() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ManagedPlanStore(root: directory)
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let plan = try files.stage(data: DXFFixtures.drawing(DXFFixtures.line, units: 4),filename: "mm.dxf",horizonID: w.context.horizonID!,version: "1",units: .millimeters,crs: "",axes: "")
        try w.registerPlan(plan)
        w.draft.z = ""; try w.selectPlanPoint(PlanPoint(x: 1000,y: 2000),planID: plan.id)
        XCTAssertEqual(w.draft.z, ""); w.draft.x = "1100"; w.draft.picket = "5"
        let record = try w.save()
        XCTAssertEqual(record.coordinates?.x, 1100); XCTAssertEqual(record.coordinates?.y, 2000)
        XCTAssertEqual(record.coordinates?.units, "mm"); XCTAssertEqual(record.coordinates?.source, "manualInPlan")
        XCTAssertNil(record.coordinates?.z); XCTAssertEqual(record.coordinates?.zOrigin, .manualOverride)
        XCTAssertEqual(record.coordinates?.planID, plan.id)
        try w.selectPlanPoint(PlanPoint(x: 1000,y: 2000),planID: plan.id)
        w.draft.y = ""; w.draft.picket = "10"
        let partial = try w.save()
        XCTAssertEqual(partial.coordinates?.x, 1000); XCTAssertNil(partial.coordinates?.y)
        XCTAssertEqual(partial.coordinates?.units, "mm")
        XCTAssertEqual(w.points(on: plan), [record]) // Partial coordinates stay saved, without a misleading marker.
    }
}
