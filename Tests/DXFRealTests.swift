import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class DXFRealTests: XCTestCase {
    static func data(_ level: Int) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: DXFRealTests.self)
        #endif
        let root = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent("DXFReal/horizon_\(level)_3d.dxf"))
    }
    // Literal controls independently audited from original group-code pairs (not this parser).
    // SHA-256 also agrees with the owner's archive manifest. All polylines are open, flag 8;
    // every VERTEX is flag 32. See docs/p2-hotfix-verification.md for the audit procedure.
    struct Control {
        let level: Int, count: Int, vertices: Int
        let hash: String
        let bounds: PlanBounds
        let first: DXFVertex, last: DXFVertex
        let minZ: Double, maxZ: Double
    }
    static let controls = [
        Control(level: 200, count: 13, vertices: 627,
            hash: "75915a3ceffefa765553b88b6a0e663a893d070a318f29755f6d36b924f64790",
            bounds: PlanBounds(minX: 4320, minY: 10054.5, maxX: 5337.978491389462, maxY: 10354.5),
            first: DXFVertex(x: 5279.867228626928, y: 10207, z: 250),
            last: DXFVertex(x: 4320, y: 10354.5, z: 200), minZ: 150, maxZ: 250),
        Control(level: 300, count: 13, vertices: 627,
            hash: "209eb7ceb89446f61a1765c975cee8281e0fb866af231cd2c688a22dd9b077b1",
            bounds: PlanBounds(minX: 4320, minY: 9914.5, maxX: 5337.998076178854, maxY: 10214.5),
            first: DXFVertex(x: 5293.289076208976, y: 10067, z: 350),
            last: DXFVertex(x: 4320, y: 10214.5, z: 300), minZ: 250, maxZ: 350),
        Control(level: 400, count: 4, vertices: 294,
            hash: "c711ebee6a2e2a23ca5ae0e7faa0171387d9f37f3457070fd0981aaec5f82cd0",
            bounds: PlanBounds(minX: 4500, minY: 9847, maxX: 5337.97534562561, maxY: 10073),
            first: DXFVertex(x: 5000, y: 10003, z: 400),
            last: DXFVertex(x: 5000, y: 9997, z: 400), minZ: 350, maxZ: 400)
    ]
    func testAllThreeOriginalFilesImportWithIndependentXYZCountsLayersAndBounds() throws {
        for c in Self.controls {
            let bytes = try Self.data(c.level)
            XCTAssertEqual(ManagedPlanStore.digest(bytes), c.hash)
            let drawing = try DXFDocument.parse(bytes)
            XCTAssertEqual(drawing.insertionUnits, 6)
            XCTAssertEqual(drawing.paths.count, c.count)
            XCTAssertEqual(drawing.polylines.count, c.count)
            XCTAssertTrue(drawing.polylines.allSatisfy { $0.is3D && !$0.closed })
            XCTAssertEqual(drawing.paths.reduce(0) { $0 + $1.count }, c.vertices)
            let vertices = drawing.polylines.flatMap(\.vertices)
            XCTAssertEqual(vertices.count, c.vertices)
            XCTAssertEqual(vertices.first, c.first); XCTAssertEqual(vertices.last, c.last)
            XCTAssertEqual(vertices.map(\.z).min(), c.minZ); XCTAssertEqual(vertices.map(\.z).max(), c.maxZ)
            XCTAssertEqual(drawing.bounds, c.bounds)
            XCTAssertEqual(drawing.paths, drawing.polylines.map { $0.vertices.map(\.xy) })
            let layers = drawing.polylines.map(\.layer)
            XCTAssertEqual(layers.first, "RAMP_LEFT")
            XCTAssertEqual(layers.filter { $0 == "RAMP_RIGHT" }.count, c.level == 400 ? 1 : 2)
            XCTAssertEqual(layers.last, c.level == 400 ? "ADIT_400_RIGHT" : "DRIFT_\(c.level)_03_RIGHT")
            XCTAssertFalse(drawing.warnings.contains { $0.hasPrefix("Пропущено") })
        }
    }
    func testOriginalFileStoragePickingZDraftMarkersIsolationAndCorruptImportPreserveEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ManagedPlanStore(root: root)
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        var saved: [MappingObservation] = [], plans: [MappingPlanReference] = []
        for c in Self.controls {
            let bytes = try Self.data(c.level)
            let plan = try files.stage(data: bytes, filename: "horizon_\(c.level)_3d.dxf", horizonID: w.context.horizonID!,
                version: "original-\(c.level)", units: .meters, crs: "synthetic local level \(c.level)", axes: "X/Y plan; Z up")
            try w.registerPlan(plan); files.complete(plan); plans.append(plan)
            XCTAssertEqual(try files.read(plan), bytes)
            let drawing = try DXFDocument.parse(files.read(plan))
            let viewport = PlanViewport(bounds: drawing.bounds, width: 448, height: 248, zoom: 2, pan: PlanPoint(x: 35, y: -17))
            let selected = viewport.drawing(PlanPoint(x: 259, y: 107))
            XCTAssertEqual(selected, c.bounds.center)
            w.draft.picket = "\(c.level)"; w.draft.notes = "unsaved draft"
            w.draft.observedAtOverride = Date(timeIntervalSince1970: 1234)
            // Numeric horizon is +393, independent of the source ramp's varying Z.
            try w.selectPlanPoint(selected, planID: plan.id)
            XCTAssertEqual(w.draft.z, "393"); XCTAssertEqual(w.draft.zOrigin, .horizonDefault)
            w.draft.z = "-12.125"
            try w.selectPlanPoint(c.first.xy, planID: plan.id)
            XCTAssertEqual(w.draft.z, "-12.125"); XCTAssertEqual(w.draft.picket, "\(c.level)")
            XCTAssertEqual(w.draft.notes, "unsaved draft"); XCTAssertEqual(w.draft.observedAtOverride, Date(timeIntervalSince1970: 1234))
            let record = try w.save(); saved.append(record)
            XCTAssertEqual(record.coordinates?.x, c.first.x); XCTAssertEqual(record.coordinates?.y, c.first.y)
            XCTAssertEqual(record.coordinates?.z, -12.125); XCTAssertEqual(w.draft.z, "393")
            XCTAssertEqual(w.points(on: plan), [record])
            XCTAssertEqual(viewport.screen(c.first.xy), viewport.screen(drawing.paths[0][0]))
            XCTAssertThrowsError(try files.stage(data: Data("corrupt".utf8), filename: "broken.dxf", horizonID: w.context.horizonID!,
                version: "bad", units: .unknown, crs: "", axes: ""))
            XCTAssertEqual(w.observations, saved)
            XCTAssertEqual(try files.read(plan), bytes)
        }
        for (plan, record) in zip(plans, saved) { XCTAssertEqual(w.points(on: plan), [record]) }
    }
}
