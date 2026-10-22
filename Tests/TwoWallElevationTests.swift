import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class TwoWallElevationTests: XCTestCase {
    private func wall(_ vertices: [(Double, Double, Double)], layer: String = "0") -> String {
        "0\nPOLYLINE\n8\n\(layer)\n70\n8\n" + vertices.map {
            "0\nVERTEX\n70\n32\n10\n\($0.0)\n20\n\($0.1)\n30\n\($0.2)\n"
        }.joined() + "0\nSEQEND\n"
    }
    private func source(_ entities: String) throws -> (DXFDocument, MappingPlanReference) {
        let data = DXFFixtures.drawing(entities, units: 6)
        let plan = MappingPlanReference(id: UUID(), horizonID: UUID(), attachmentID: UUID(), version: "1",
            file: ManagedPlanFile(originalFilename: "700.dxf", sha256: ManagedPlanStore.digest(data), byteCount: data.count,
                importedAt: Date(), units: .meters, crs: "local", axes: "XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: 6))
        return (try DXFDocument.parse(data), plan)
    }
    private var ramp: String {
        wall([(0, 0, 100), (100, 0, 120)]) + wall([(0, 10, 110), (100, 10, 150)])
    }
    private func result(_ entities: String, _ x: Double, _ y: Double) throws -> PlanElevationResolution {
        let (doc, plan) = try source(entities)
        return PlanElevationSnap.resolve(PlanPoint(x: x, y: y), document: doc, plan: plan)
    }
    func testStraightCenterLeftRightAndOnBothWallsWithIndependentRampReferences() throws {
        // x=25: Z1=105, Z2=120. Across 10 m, z=105+1.5*y.
        for (y, expected) in [(0.0, 105.0), (2, 108), (5, 112.5), (8, 117), (10, 120)] {
            let hit = try XCTUnwrap(result(ramp, 25, y).automatic)
            XCTAssertEqual(hit.isTwoWall, y > 0 && y < 10)
            XCTAssertEqual(hit.elevationMeters, expected, accuracy: 1e-12)
            if hit.isTwoWall {
                XCTAssertEqual(Set([hit.firstWallElevationMeters, try XCTUnwrap(hit.secondWall?.elevationMeters)]), Set([105, 120]))
            }
            XCTAssertEqual(hit.selectedXY, PlanPoint(x: 25, y: y))
        }
    }
    func testCurvedOpenWallsUnequalVertexSpacing() throws {
        let a = wall([(0, 0, 0), (10, 0, 10), (20, 10, 20)])
        let b = wall([(0, 4, 12), (8, 4, 20), (12, 8, 24), (18, 14, 30)])
        // P=(15,9): Q1=(17,7), Q2=(14,10); distances 2√2, √2.
        // Z1=17, Z2=26; z=(17+2*26)/3=23.
        let hit = try XCTUnwrap(result(a + b, 15, 9).automatic)
        XCTAssertEqual(hit.elevationMeters, 23, accuracy: 1e-12)
        XCTAssertEqual(hit.parameter, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(hit.secondWall?.parameter), 0.7, accuracy: 1e-12)
    }
    func testWidthBeyondTwoAndFiveMeterLimitsAndNoDistantAutomaticAcceptance() throws {
        let wide = wall([(0, 0, 10), (100, 0, 30)]) + wall([(0, 20, 20), (100, 20, 40)])
        let hit = try XCTUnwrap(result(wide, 50, 10).automatic)
        XCTAssertEqual(hit.elevationMeters, 25); XCTAssertEqual(hit.distanceMeters, 10)
        XCTAssertEqual(hit.secondWall?.distanceMeters, 10)
        let short = wall([(0, 0, 10), (10, 0, 10)]) + wall([(0, 1000, 30), (10, 1000, 30)])
        let distant = try result(short, 5, 500)
        XCTAssertNil(distant.automatic); XCTAssertTrue(distant.requiresChoice)
        XCTAssertEqual(distant.candidates.first?.elevationMeters, 20)
        XCTAssertNil(try result(wide, 500, 10).automatic) // Beyond the open dead end.
    }
    func testVeryDistantLongWallsNeedConfirmationAndMillimeterSectionsUseMetricReviewGuard() throws {
        let huge = wall([(0, 0, 10), (10000, 0, 10)]) + wall([(0, 1000, 30), (10000, 1000, 30)])
        let r = try result(huge, 5000, 500)
        XCTAssertNil(r.automatic); XCTAssertTrue(r.requiresChoice)
        XCTAssertEqual(r.candidates.first?.elevationMeters, 20)
        // Millimetre drawing: a 20 m section, at 25 m chainage, z1=105,z2=120.
        let text = wall([(0, 0, 100000), (100000, 0, 120000)]) + wall([(0, 20000, 110000), (100000, 20000, 150000)])
        let bytes = DXFFixtures.drawing(text, units: 4), doc = try DXFDocument.parse(bytes)
        let plan = MappingPlanReference(id: UUID(), horizonID: UUID(), attachmentID: UUID(), version: "1",
            file: ManagedPlanFile(originalFilename: "500.dxf", sha256: ManagedPlanStore.digest(bytes), byteCount: bytes.count,
                importedAt: Date(), units: .millimeters, crs: "local", axes: "XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: 4))
        let hit = try XCTUnwrap(PlanElevationSnap.resolve(PlanPoint(x: 25000, y: 4000), document: doc, plan: plan).automatic)
        XCTAssertEqual(hit.elevationMeters, 108); XCTAssertEqual(hit.distanceMeters, 4)
        XCTAssertEqual(hit.secondWall?.distanceMeters, 16); try hit.validate(plan: plan)
        XCTAssertEqual(hit.selectedXY, PlanPoint(x: 25000, y: 4000))
    }
    func testCoincidentWallLevelsBelowOldHalfMeterThresholdStillRequireChoice() throws {
        let walls = wall([(0, 0, 100), (100, 0, 100)]) + wall([(0, 0, 100.1), (100, 0, 100.1)])
        let r = try result(walls, 50, 0)
        XCTAssertTrue(r.requiresChoice); XCTAssertNil(r.automatic)
        XCTAssertEqual(r.candidates.map(\.elevationMeters), [100, 100.1])
    }
    func testVariableWidthUsesActualDistancesAndIndependentWallProjection() throws {
        let a = wall([(0, 0, 0), (100, 0, 0)])
        let b = wall([(0, 10, 10), (100, 20, 30)])
        // Projection of (50,5) on B: t=4950/10100=99/202, z=2000/101.
        // d1=5, d2=100/sqrt(101); no vertex-to-vertex matching.
        let hit = try XCTUnwrap(result(a + b, 50, 5).automatic)
        let z2 = 2000.0 / 101, d2 = 100.0 / sqrt(101.0)
        XCTAssertEqual(hit.elevationMeters, z2 * 5 / (5 + d2), accuracy: 1e-12)
    }
    private var junction: String {
        wall([(-50, 0, 100), (50, 0, 100)], layer: "MAIN_RIGHT") +
        wall([(-50, 10, 100), (-5, 10, 100)], layer: "MAIN_LEFT_1") +
        wall([(5, 10, 100), (50, 10, 100)], layer: "MAIN_LEFT_2") +
        wall([(-5, 10, 100), (-5, 60, 110)], layer: "ACCESS_LEFT") +
        wall([(5, 10, 102), (5, 60, 112)], layer: "ACCESS_RIGHT")
    }
    func testAccessDriveAndTJunctionRequireLocalSectionOrConfirmation() throws {
        // y=35: walls Z=105 and107, midway gives106.
        let access = try XCTUnwrap(result(junction, 0, 35).automatic)
        XCTAssertEqual(access.elevationMeters, 106, accuracy: 1e-12)
        XCTAssertEqual(access.segment.layer, "ACCESS_LEFT")
        let mouth = try result(junction, 0, 10)
        XCTAssertNil(mouth.automatic)
        let (doc, plan) = try source(junction)
        let walls = doc.elevationSegments.filter { $0.layer?.hasPrefix("ACCESS_") == true }.map(\.wallID)
        let confirmed = try XCTUnwrap(PlanWallSection.confirmedPair(PlanPoint(x: 0, y: 10), walls: walls, document: doc, plan: plan))
        XCTAssertEqual(confirmed.elevationMeters, 101); XCTAssertEqual(confirmed.confirmedByUser, true)
        XCTAssertNil(try result(junction, 0, 80).automatic)
    }
    func testParallelExcavationsAndRockGapDoNotCrossPairAutomatically() throws {
        let rails = wall([(0, 0, 100), (100, 0, 100)], layer: "A_LEFT") + wall([(0, 10, 110), (100, 10, 110)], layer: "A_RIGHT") +
            wall([(0, 20, 200), (100, 20, 200)], layer: "B_LEFT") + wall([(0, 30, 210), (100, 30, 210)], layer: "B_RIGHT")
        XCTAssertEqual(try result(rails, 50, 5).automatic?.elevationMeters, 105)
        XCTAssertEqual(try result(rails, 50, 25).automatic?.elevationMeters, 205)
        XCTAssertNil(try result(rails, 50, 15).automatic) // Rock gap, different named corridors.
        let unlabeled = rails.replacingOccurrences(of: "A_LEFT", with: "0").replacingOccurrences(of: "A_RIGHT", with: "0")
            .replacingOccurrences(of: "B_LEFT", with: "0").replacingOccurrences(of: "B_RIGHT", with: "0")
        XCTAssertNil(try result(unlabeled, 50, 15).automatic) // Topology cannot be inferred from four bare rails.
    }
    func testOverlappingLevelsAndCrossingDrivesNeverSelectNearestLevelSilently() throws {
        let lower = wall([(0, 0, 100), (100, 0, 100)]) + wall([(0, 10, 110), (100, 10, 110)])
        let upper = wall([(0, 0, 200), (100, 0, 200)]) + wall([(0, 10, 210), (100, 10, 210)])
        XCTAssertNil(try result(lower + upper, 50, 5).automatic)
        let cross = wall([(45, -50, 200), (45, 50, 200)]) + wall([(55, -50, 210), (55, 50, 210)])
        XCTAssertNil(try result(lower + cross, 50, 5).automatic)
        let (doc, plan) = try source(lower + upper)
        let chosen = try XCTUnwrap(PlanWallSection.confirmedPair(PlanPoint(x: 50, y: 5), walls: Array(doc.elevationSegments.prefix(2).map(\.wallID)), document: doc, plan: plan))
        XCTAssertEqual(chosen.elevationMeters, 105); try chosen.validate(plan: plan)
    }
    func testSingleWallIsExplicitEstimateAndInvalidOrMissingZNeverInventsElevation() throws {
        let single = try XCTUnwrap(result(wall([(0, 0, 0), (100, 0, 20)]), 25, 1).automatic)
        XCTAssertFalse(single.isTwoWall); XCTAssertEqual(single.elevationMeters, 5)
        XCTAssertTrue(single.sourceLabel.contains("1 стена")); XCTAssertTrue(single.sourceLabel.contains("≈"))
        XCTAssertNil(try result(wall([(0, 0, 0), (100, 0, 20)]), 25, 50).automatic)
        let invalid = "0\nLINE\n10\n0\n20\n0\n11\n100\n21\n0\n"
        XCTAssertTrue(try result(invalid, 25, 1).candidates.isEmpty)
        XCTAssertThrowsError(try source(wall([(0, 0, .nan), (100, 0, 20)])))
        let (doc, plan) = try source(ramp)
        XCTAssertNil(PlanWallSection.confirmedPair(PlanPoint(x: 25, y: -20), walls: doc.elevationSegments.map(\.wallID), document: doc, plan: plan))
    }
    func testTwoWallSaveReopenManualCorrectionAndTamperedProvenance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
        let (_, initial) = try P2MappingTests().configured(); try store.save(initial.journal)
        var w = try MappingWorkflow(store: store)
        let (doc, sourcePlan) = try source(ramp)
        let plan = MappingPlanReference(id: sourcePlan.id, horizonID: try XCTUnwrap(w.context.horizonID), attachmentID: sourcePlan.attachmentID, version: "1", file: sourcePlan.file)
        try w.registerPlan(plan)
        let xy = PlanPoint(x: 25, y: 2)
        let z = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: doc, plan: plan).automatic)
        try w.selectPlanPoint(xy, planID: plan.id, elevation: z); w.draft.picket = "1"
        let record = try w.save()
        var reopened = try MappingWorkflow(store: store)
        XCTAssertEqual(reopened.observations.last?.coordinates?.z, 108)
        XCTAssertEqual(reopened.observations.last?.coordinates?.x, 25); XCTAssertEqual(reopened.observations.last?.coordinates?.y, 2)
        XCTAssertEqual(reopened.observations.last?.coordinates?.zPlanGeometry, z)
        var correction = try reopened.correction(for: record.id)
        correction.reason = "Ручная Z"; correction.fields.z = "109"
        let revised = try reopened.saveCorrection(correction)
        XCTAssertEqual(revised.snapshot.coordinates?.z, 109); XCTAssertNil(revised.snapshot.coordinates?.zPlanGeometry)
        XCTAssertEqual(try store.load().observations.last?.coordinates?.z, 108)
        try reopened.selectPlanPoint(PlanPoint(x: 500, y: 500), planID: plan.id)
        XCTAssertEqual(reopened.draft.z, ""); XCTAssertNil(reopened.draft.zOrigin) // Never use +393 nominal horizon.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(z)) as? [String: Any])
        json["elevationMeters"] = 105
        var bad = try JSONDecoder().decode(PlanGeometryElevation.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try bad.validate(plan: plan))
        bad = z; bad.secondWall = nil; XCTAssertThrowsError(try bad.validate(plan: plan))
    }
}
