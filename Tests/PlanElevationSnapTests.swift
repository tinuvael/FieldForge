import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class PlanElevationSnapTests: XCTestCase {
    private func line(_ za: Double?, _ zb: Double?, y: Double = 0, x: Double = 10, handle: String = "AB") -> String {
        "0\nLINE\n5\n\(handle)\n10\n0\n20\n\(y)\n" + (za.map { "30\n\($0)\n" } ?? "") +
            "11\n\(x)\n21\n\(y)\n" + (zb.map { "31\n\($0)\n" } ?? "")
    }
    private func plan(_ data: Data, units: PlanUnits = .meters, horizon: UUID = UUID(), version: String = "A") throws -> MappingPlanReference {
        let document = try DXFDocument.parse(data)
        return MappingPlanReference(id: UUID(), horizonID: horizon, attachmentID: UUID(), version: version,
            file: ManagedPlanFile(originalFilename: "fixture.dxf", sha256: ManagedPlanStore.digest(data), byteCount: data.count,
                importedAt: Date(), units: units, crs: "mine grid", axes: "WCS XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: document.insertionUnits))
    }
    private func resolve(_ entities: String, point: PlanPoint = PlanPoint(x: 2.5, y: 1), units: PlanUnits = .meters,
                         insertionUnits: Int = 6, policy: PlanElevationSnapPolicy = PlanElevationSnapPolicy()) throws -> PlanElevationResolution {
        let data = DXFFixtures.drawing(entities, units: insertionUnits)
        return try PlanElevationSnap.resolve(point, document: DXFDocument.parse(data), plan: plan(data, units: units), policy: policy)
    }
    func testXYProjectionInterpolationClampingAndNegativeElevations() throws {
        // Quarter of a 10 m ramp from -20 to +20: -10 m, distance 1 m. No vertex is nearby.
        let c = try XCTUnwrap(resolve(line(-20, 20)).automatic)
        XCTAssertEqual(c.elevationMeters, -10); XCTAssertEqual(c.distanceMeters, 1); XCTAssertEqual(c.parameter, 0.25)
        XCTAssertEqual(c.selectedXY, PlanPoint(x: 2.5, y: 1)); XCTAssertEqual(c.segment.handle, "AB")
        XCTAssertEqual(try resolve(line(-20, 20), point: PlanPoint(x: -1, y: 0)).automatic?.elevationMeters, -20)
        XCTAssertEqual(try resolve(line(-20, 20), point: PlanPoint(x: 11, y: 0)).automatic?.elevationMeters, 20)
        // Different underground levels must not be averaged.
        let closest = try resolve(line(10000, 10000) + line(0, 0, y: 2), point: PlanPoint(x: 5, y: 0.2))
        XCTAssertNil(closest.automatic)
    }
    func testConstantZeroIsExplicitButMissingOneOrBothCodesAreIneligible() throws {
        XCTAssertEqual(try resolve(line(393, 393)).automatic?.elevationMeters, 393)
        XCTAssertEqual(try resolve(line(0, 0)).automatic?.elevationMeters, 0)
        for entity in [line(nil, nil), line(0, nil), line(nil, 0)] {
            XCTAssertTrue(try resolve(entity).candidates.isEmpty)
            XCTAssertEqual(try DXFDocument.parse(DXFFixtures.drawing(entity)).paths.count, 1)
        }
    }
    func testToleranceAndAmbiguityAreExplicitPolicies() throws {
        XCTAssertNotNil(try resolve(line(0, 0), point: PlanPoint(x: 5, y: 25)).automatic)
        XCTAssertTrue(try resolve(line(0, 0), point: PlanPoint(x: 5, y: 25.000001)).candidates.isEmpty)
        XCTAssertTrue(try resolve(line(0, 0), policy: PlanElevationSnapPolicy(searchRadiusMeters: 0.5)).candidates.isEmpty)
        let ambiguous = try resolve(line(100, 100) + line(200, 200, y: 0.05))
        XCTAssertNil(ambiguous.automatic); XCTAssertTrue(ambiguous.candidates.isEmpty)
        XCTAssertNotNil(try resolve(line(100, 100) + line(100.1, 100.1)).automatic)
        let extremes = try resolve(line(100, 100) + line(100.4, 100.4) + line(99.6, 99.6))
        XCTAssertNil(extremes.automatic) // Compare the full range, not just each candidate with the first.
        XCTAssertTrue(try resolve(line(0, 0), policy: PlanElevationSnapPolicy(toleranceMeters: .nan)).candidates.isEmpty)
    }
    func testMillimetersAndUnconfirmedOrConflictingUnits() throws {
        let c = try XCTUnwrap(resolve(line(-20000, 20000, x: 10000), point: PlanPoint(x: 2500, y: 1000), units: .millimeters, insertionUnits: 4).automatic)
        XCTAssertEqual(c.elevationMeters, -10); XCTAssertEqual(c.distanceMeters, 1); XCTAssertEqual(c.metersPerDrawingUnit, 0.001)
        XCTAssertTrue(try resolve(line(0, 0), units: .unknown).candidates.isEmpty)
        XCTAssertTrue(try resolve(line(0, 0), units: .millimeters, insertionUnits: 6).candidates.isEmpty)
        XCTAssertNotNil(try resolve(line(0, 0), units: .meters, insertionUnits: 1).automatic) // Explicit import confirmation.
        XCTAssertNotNil(try resolve(line(0, 0), units: .meters, insertionUnits: 0).automatic)
    }
    func testLwPolylineExplicitElevationAndClosedSegment() throws {
        let elevated = DXFFixtures.lwpolyline + "38\n-12.5\n"
        let data = DXFFixtures.drawing(elevated), document = try DXFDocument.parse(data)
        XCTAssertEqual(document.elevationSegments.count, 3)
        let p = try plan(data)
        let c = try XCTUnwrap(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 10), document: document, plan: p).automatic)
        XCTAssertEqual(c.elevationMeters, -12.5); XCTAssertEqual(c.segment.segmentIndex, 2)
        XCTAssertTrue(try resolve(DXFFixtures.lwpolyline).candidates.isEmpty)
        XCTAssertEqual(try DXFDocument.parse(DXFFixtures.drawing(DXFFixtures.lwpolyline + "38\n0\n")).elevationSegments.count, 3)
        XCTAssertThrowsError(try DXFDocument.parse(DXFFixtures.drawing(elevated + "38\n2\n")))
    }
    func test3DPolylineMissingVertexZDoesNotBecomeZeroReferenceAndVerticalSegmentsAreIgnored() throws {
        let prefix = "0\nPOLYLINE\n70\n8\n0\nVERTEX\n70\n32\n10\n0\n20\n0\n30\n-20\n"
        let suffix = "0\nVERTEX\n70\n32\n10\n10\n20\n0\n30\n20\n0\nSEQEND\n"
        XCTAssertEqual(try resolve(prefix + suffix).automatic?.elevationMeters, -10)
        XCTAssertTrue(try resolve(prefix + suffix.replacingOccurrences(of: "30\n20\n", with: "")).candidates.isEmpty)
        XCTAssertTrue(try resolve(line(0, 100, x: 0), point: PlanPoint(x: 0, y: 0)).candidates.isEmpty)
        // No TEXT or circle approximation may become an elevation segment.
        XCTAssertTrue(try resolve(DXFFixtures.circle + "30\n100\n").candidates.isEmpty)
    }
    func testSaveReopenRevisionManualOverridePlanRevisionAndNoXYMovement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
        let (_, initial) = try P2MappingTests().configured()
        try store.save(initial.journal)
        var w = try MappingWorkflow(store: store)
        let bytes = DXFFixtures.drawing(line(-20, 20))
        let a = try plan(bytes, horizon: XCTUnwrap(w.context.horizonID)), b = try plan(bytes, horizon: XCTUnwrap(w.context.horizonID), version: "B")
        try w.registerPlan(a); try w.registerPlan(b)
        let xy = PlanPoint(x: 2.5, y: 1), document = try DXFDocument.parse(bytes)
        let z = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: document, plan: a).automatic)
        try w.selectPlanPoint(xy, planID: a.id, elevation: z); w.draft.picket = "1"
        XCTAssertEqual(w.draft.x, "2.5"); XCTAssertEqual(w.draft.y, "1"); XCTAssertEqual(w.draft.z, "-10")
        let first = try w.save()
        XCTAssertEqual(first.coordinates?.zOrigin, .planGeometry); XCTAssertEqual(first.coordinates?.zPlanGeometry, z)
        var reopened = try MappingWorkflow(store: store)
        var correction = try reopened.correction(for: first.id)
        XCTAssertEqual(correction.fields.zPlanGeometry, z)
        correction.reason = "Ручная отметка"; correction.fields.z = "-11"
        let revised = try reopened.saveCorrection(correction)
        XCTAssertNil(revised.snapshot.coordinates?.zPlanGeometry); XCTAssertEqual(revised.snapshot.coordinates?.zOrigin, .manualOverride)
        XCTAssertEqual(try store.load().observations.first, first)
        // Merely opening/reading another revision never changes an elevation.
        let before = reopened.draft; _ = reopened.points(on: b); XCTAssertEqual(reopened.draft, before)
        reopened.draft.z = "-12"
        try reopened.selectPlanPoint(xy, planID: b.id)
        XCTAssertEqual(reopened.draft.z, "-12")
        // Every plan selection preserves manual Z, even with historical confirmation flags.
        let zb = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: document, plan: b).automatic)
        try reopened.selectPlanPoint(xy, planID: b.id, elevation: zb)
        XCTAssertEqual(reopened.draft.z, "-12")
        try reopened.selectPlanPoint(xy, planID: b.id, elevation: zb.confirmed())
        XCTAssertEqual(reopened.draft.z, "-12"); XCTAssertEqual(reopened.draft.zOrigin, .manualOverride)
        XCTAssertNil(reopened.draft.zPlanGeometry)
        reopened.draft.z = ""
        try reopened.selectPlanPoint(xy, planID: b.id, elevation: zb)
        XCTAssertEqual(reopened.draft.zPlanGeometry?.planRevision, "B")
        let nextXY = PlanPoint(x: 7.5, y: 1)
        let nextZ = try XCTUnwrap(PlanElevationSnap.resolve(nextXY, document: document, plan: b).automatic)
        try reopened.selectPlanPoint(nextXY, planID: b.id, elevation: nextZ)
        XCTAssertEqual(reopened.draft.z, "10"); XCTAssertEqual(reopened.draft.zPlanGeometry, nextZ)
        // Old revision suggestions cannot be applied to a newly chosen plan/XY.
        let unchanged = reopened.draft
        XCTAssertThrowsError(try reopened.selectPlanPoint(xy, planID: b.id, elevation: z)); XCTAssertEqual(reopened.draft, unchanged)
        XCTAssertThrowsError(try reopened.selectPlanPoint(PlanPoint(x: 3, y: 1), planID: b.id, elevation: zb))
        // A distant plan tap clears stale geometry; the nominal horizon is not point Z.
        try reopened.selectPlanPoint(PlanPoint(x: 100, y: 100), planID: b.id)
        XCTAssertEqual(reopened.draft.z, ""); XCTAssertNil(reopened.draft.zOrigin)
        var noHorizon = MappingDraft(); try noHorizon.selectPlanPoint(xy, plan: a, elevation: z)
        try noHorizon.selectPlanPoint(PlanPoint(x: 100, y: 100), plan: b)
        XCTAssertEqual(noHorizon.z, ""); XCTAssertNil(noHorizon.zOrigin)
    }
    func testTamperedProvenanceAndLegacyOptionalFields() throws {
        let data = DXFFixtures.drawing(line(0, 0)), p = try plan(data)
        let c = try XCTUnwrap(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 1), document: DXFDocument.parse(data), plan: p).automatic)
        try c.validate(plan: p)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        object["distanceMeters"] = 0
        let tampered = try JSONDecoder().decode(PlanGeometryElevation.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try tampered.validate(plan: p))
        let old = MappingCoordinates(x: 1, y: 2, z: -10, crs: "unknown", axes: "unknown", units: "m", source: "manual", provenance: "legacy")
        XCTAssertEqual(try JSONDecoder().decode(MappingCoordinates.self, from: JSONEncoder().encode(old)), old)
        XCTAssertNil(old.zOrigin); XCTAssertNil(old.zPlanGeometry)
    }
}
