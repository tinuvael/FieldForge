import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Synthetic floor surveys; published projection contract and independent Python
/// controls are documented in docs/underground-survey-z-verification.md.
final class UndergroundSurveyTests: XCTestCase {
    private static let levels = [500, 600, 700]
    private static let hashes = [
        500: "d56489281c73c31c7dc4e7c189fdfc2277baba30635bd721a763856708ae9316",
        600: "5a572b4fdb3d553f26ffbd783ddb8dc9a9886099ce1fb70935558d7e661fffb9",
        700: "fbd43db7146cc757b3229597138ec0d092f527624a7b80252e28e16e6b8055f5"
    ]
    private func resource(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: UndergroundSurveyTests.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent(name))
    }
    private func bytes(_ level: Int) throws -> Data { try resource("underground_survey_\(level).dxf") }
    private struct Control {
        let name: String, point: PlanPoint, z: Double, layer: String, handle: String, index: Int
        let a: DXFVertex, b: DXFVertex, t: Double, distance: Double, projected: PlanPoint, status: String
        init(_ row: String) throws {
            let f = row.components(separatedBy: ",")
            guard f.count == 18 else { throw StorageError.invalidRecord }
            func n(_ i: Int) throws -> Double { try XCTUnwrap(Double(f[i])) }
            name = f[0]; point = try PlanPoint(x: n(1), y: n(2)); z = try n(3)
            layer = f[4]; handle = f[5]; index = try XCTUnwrap(Int(f[6]))
            a = try DXFVertex(x: n(7), y: n(8), z: n(9)); b = try DXFVertex(x: n(10), y: n(11), z: n(12))
            t = try n(13); distance = try n(14); projected = try PlanPoint(x: n(15), y: n(16))
            // Last field is status; no optional/missing values in this controlled fixture schema.
            status = f[17]
        }
    }
    private func controls(_ level: Int) throws -> [Control] {
        try XCTUnwrap(String(data: resource("underground_survey_\(level)_controls.csv"), encoding: .utf8))
            .split(separator: "\n").dropFirst().map { try Control(String($0)) }
    }
    private func reference(_ level: Int, filename: String? = nil, horizon: UUID = UUID()) throws -> MappingPlanReference {
        let data = try bytes(level)
        return MappingPlanReference(id: UUID(), horizonID: horizon, attachmentID: UUID(), version: "synthetic-\(level)",
            file: ManagedPlanFile(originalFilename: filename ?? "underground_survey_\(level).dxf", sha256: ManagedPlanStore.digest(data),
                byteCount: data.count, importedAt: Date(timeIntervalSince1970: 0), units: .meters,
                crs: "synthetic local grid; datum unknown", axes: "X east / Y north / Z up",
                unitDeclaration: "userConfirmedAtImport", insertionUnits: 6))
    }
    func testAllThreeASCII2018StreamsHaveOpen3DWallsExplicitXYZFlagsAndSequenceEnds() throws {
        for (level, expectedCount, expectedVertices) in [(500, 14, 528), (600, 17, 653), (700, 20, 634)] {
            let data = try bytes(level), text = try XCTUnwrap(String(data: data, encoding: .ascii))
            XCTAssertEqual(ManagedPlanStore.digest(data), Self.hashes[level])
            XCTAssertTrue(text.contains("9\n$ACADVER\n1\nAC1032\n")); XCTAssertTrue(text.contains("9\n$INSUNITS\n70\n6\n"))
            // Inspect original records independently of DXFDocument's flag/default handling.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            let values = Array(lines)
            var kind = "", fields: [Int: String] = [:], polylines = 0, vertices = 0, ends = 0
            var inside = false
            func inspect() {
                if kind == "POLYLINE" {
                    XCTAssertFalse(inside); inside = true; polylines += 1
                    XCTAssertEqual(fields[70], "8"); XCTAssertEqual(fields[100], "AcDb3dPolyline")
                } else if kind == "VERTEX" {
                    XCTAssertTrue(inside); vertices += 1; XCTAssertEqual(fields[70], "32")
                    for code in [10, 20, 30] { XCTAssertNotNil(fields[code].flatMap(Double.init)) }
                } else if kind == "SEQEND" { XCTAssertTrue(inside); inside = false; ends += 1 }
            }
            for i in stride(from: 0, to: values.count, by: 2) {
                let code = try XCTUnwrap(Int(values[i])), value = String(values[i+1])
                if code == 0 { inspect(); kind = value; fields = [:] } else { fields[code] = value }
            }
            inspect(); XCTAssertFalse(inside)
            XCTAssertEqual(polylines, expectedCount); XCTAssertEqual(vertices, expectedVertices); XCTAssertEqual(ends, polylines)
            let doc = try DXFDocument.parse(data)
            XCTAssertEqual(doc.polylines.count, expectedCount); XCTAssertEqual(doc.elevationSegments.count, expectedVertices - expectedCount)
            XCTAssertEqual(doc.insertionUnits, 6); XCTAssertTrue(doc.elevationExclusions.isEmpty)
            XCTAssertTrue(doc.polylines.allSatisfy { $0.is3D && !$0.closed && $0.vertices.first != $0.vertices.last })
            for wall in doc.polylines {
                XCTAssertGreaterThan(try XCTUnwrap(wall.vertices.map(\.z).max()) - XCTUnwrap(wall.vertices.map(\.z).min()), 0)
                XCTAssertFalse(wall.vertices.allSatisfy { $0.z == Double(level) })
            }
        }
    }
    func testEveryControlUsesNearestSidewallInterpolatedZAndOriginalTapXY() throws {
        for level in Self.levels {
            let doc = try DXFDocument.parse(bytes(level)), plan = try reference(level), rows = try controls(level)
            XCTAssertEqual(rows.count, 30)
            for c in rows {
                // Historical CSV audits each individual wall projection, not a two-wall floor.
                let segment = try XCTUnwrap(doc.elevationSegments.first { $0.handle == c.handle && $0.segmentIndex == c.index })
                let p = try XCTUnwrap(segment.projection(c.point))
                let hit = PlanGeometryElevation(planID: plan.id, planRevision: plan.version, planSHA256: plan.file!.sha256,
                    segment: segment, selectedXY: c.point, parameter: p.t, distanceMeters: p.distance,
                    elevationMeters: p.z, metersPerDrawingUnit: 1, unitDeclaration: plan.elevationUnitDeclaration,
                    policy: PlanElevationSnapPolicy(toleranceMeters: 20))
                XCTAssertEqual(hit.segment.handle, c.handle, c.name); XCTAssertEqual(hit.segment.segmentIndex, c.index, c.name)
                XCTAssertEqual(hit.segment.a, c.a); XCTAssertEqual(hit.segment.b, c.b)
                XCTAssertEqual(hit.parameter, c.t, accuracy: 1e-9, c.name)
                XCTAssertEqual(hit.distanceMeters, c.distance, accuracy: 1e-8, c.name)
                XCTAssertEqual(hit.elevationMeters, c.z, accuracy: 1e-8, c.name)
                XCTAssertEqual(hit.selectedXY, c.point)
                XCTAssertEqual(c.a.x + hit.parameter * (c.b.x - c.a.x), c.projected.x, accuracy: 1e-8)
                XCTAssertEqual(c.a.y + hit.parameter * (c.b.y - c.a.y), c.projected.y, accuracy: 1e-8)
                let wall = try XCTUnwrap(doc.polylines.first { $0.layer == c.layer })
                XCTAssertEqual(wall.vertices[c.index], hit.segment.a)
                XCTAssertEqual(wall.vertices[c.index+1], hit.segment.b)
                try hit.validate(plan: plan)
                var draft = MappingDraft()
                try draft.selectPlanPoint(c.point, plan: plan, elevation: hit)
                XCTAssertEqual(try ElevationInput.meters(draft.x), c.point.x)
                XCTAssertEqual(try ElevationInput.meters(draft.y), c.point.y)
                XCTAssertEqual(try XCTUnwrap(ElevationInput.meters(draft.z)), c.z, accuracy: 1e-8)
                XCTAssertEqual(draft.zOrigin, .planGeometry)
                XCTAssertEqual(draft.zPlanGeometry?.selectedXY, c.point)
                if c.name.contains("interior") || c.name.contains("ramp_") {
                    XCTAssertGreaterThan(c.t, 0); XCTAssertLessThan(c.t, 1)
                    XCTAssertNotEqual(c.z, c.a.z); XCTAssertNotEqual(c.z, c.b.z)
                }
            }
        }
    }
    func testTwoWallControlsUseIndependentDecimalReferencesOnAllThreeSurveys() throws {
        let text = try XCTUnwrap(String(data: resource("two_wall_elevation_controls.csv"), encoding: .utf8))
        let rows = text.split(separator: "\n").dropFirst().map { $0.split(separator: ",").map(String.init) }
        XCTAssertEqual(rows.count, 45)
        for level in Self.levels {
            let doc = try DXFDocument.parse(bytes(level)), plan = try reference(level)
            var automaticCount = 0
            for f in rows where f[0] == String(level) {
                let xy = PlanPoint(x: Double(f[2])!, y: Double(f[3])!)
                let a = try XCTUnwrap(doc.elevationSegments.first { $0.handle == f[4] && $0.segmentIndex == Int(f[5]) })
                let b = try XCTUnwrap(doc.elevationSegments.first { $0.handle == f[8] && $0.segmentIndex == Int(f[9]) })
                let expected = Double(f[12])!
                let r = PlanElevationSnap.resolve(xy, document: doc, plan: plan)
                let hit: PlanGeometryElevation
                if let automatic = r.automatic {
                    hit = automatic; automaticCount += 1
                } else {
                    // Junction/throat ambiguity remains explicit; the oracle identifies the intended route.
                    XCTAssertTrue(r.requiresChoice || r.candidates.isEmpty)
                    hit = try XCTUnwrap(PlanWallSection.confirmedPair(xy, walls: [a.wallID, b.wallID], document: doc, plan: plan), "\(level): \(f[1])")
                    XCTAssertEqual(hit.confirmedByUser, true)
                }
                XCTAssertTrue(hit.isTwoWall, f[1])
                XCTAssertEqual(hit.elevationMeters, expected, accuracy: 1e-8, "\(level): \(f[1])")
                XCTAssertEqual(Set([hit.segment.handle!, hit.secondWall!.segment.handle!]), Set([f[4], f[8]]), f[1])
                let samples = [(hit.segment.handle!, hit.firstWallElevationMeters, hit.distanceMeters),
                               (hit.secondWall!.segment.handle!, hit.secondWall!.elevationMeters, hit.secondWall!.distanceMeters)]
                for (handle, z, distance) in samples {
                    XCTAssertEqual(z, Double(f[handle == f[4] ? 6 : 10])!, accuracy: 1e-8)
                    XCTAssertEqual(distance, Double(f[handle == f[4] ? 7 : 11])!, accuracy: 1e-8)
                }
                try hit.validate(plan: plan)
                XCTAssertEqual(hit.selectedXY, xy)
                if f[1] == "wide_main_center" {
                    XCTAssertNotNil(r.automatic, "Wide excavation must not require a 2 m snap")
                    XCTAssertGreaterThan(hit.distanceMeters, 2); XCTAssertGreaterThan(hit.secondWall!.distanceMeters, 2)
                }
            }
            print("Two-wall survey \(level): \(automaticCount)/15 automatic; remainder explicitly confirmed")
            XCTAssertGreaterThanOrEqual(automaticCount, 8)
        }
    }
    func testRampGradesChangeAtApproachHaulAndToeWithIndependentSidewallElevations() throws {
        for level in Self.levels {
            let rows = try controls(level)
            for name in ["ramp_down", "ramp_up"] {
                for side in ["left", "right"] {
                    func grade(_ stage: String) throws -> Double {
                        let c = try XCTUnwrap(rows.first { $0.name == "\(name)_\(side)_\(stage)" })
                        return (c.b.z - c.a.z) / hypot(c.b.x - c.a.x, c.b.y - c.a.y)
                    }
                    let haul = try grade("haul")
                    // Individual 2.5 m survey chords include centimetric floor deviations.
                    XCTAssertGreaterThan(abs(haul), 0.095); XCTAssertLessThan(abs(haul), 0.125)
                    XCTAssertLessThan(abs(try grade("approach")), abs(haul))
                    XCTAssertLessThan(abs(try grade("toe")), abs(haul))
                    XCTAssertEqual(haul > 0, name == "ramp_up")
                }
            }
            let doc = try DXFDocument.parse(bytes(level))
            let left = try XCTUnwrap(doc.polylines.first { $0.layer == "RAMP_UP_LEFT" })
            let right = try XCTUnwrap(doc.polylines.first { $0.layer == "RAMP_UP_RIGHT" })
            XCTAssertEqual(left.vertices.count, right.vertices.count)
            for (a, b) in zip(left.vertices, right.vertices) {
                XCTAssertNotEqual(a.x, b.x); XCTAssertNotEqual(a.y, b.y); XCTAssertNotEqual(a.z, b.z)
                XCTAssertLessThan(abs(a.z - b.z), 0.1)
            }
        }
    }
    func testJunctionCornersActuallyConnectWithoutBlockingMouthAndSearchAllWalls() throws {
        for level in Self.levels {
            let doc = try DXFDocument.parse(bytes(level)), rows = try controls(level)
            for branch in doc.polylines.filter({ !$0.layer.hasPrefix("MAIN_") }) {
                let corner = try XCTUnwrap(branch.vertices.first)
                XCTAssertTrue(doc.polylines.filter { $0.layer.hasPrefix("MAIN_") }.contains {
                    $0.vertices.first == corner || $0.vertices.last == corner
                }, branch.layer)
            }
            let samples = rows.filter { $0.name.hasPrefix("junction_") }
            XCTAssertEqual(samples.count, 9)
            XCTAssertGreaterThanOrEqual(Set(samples.map(\.handle)).count, 8)
        }
    }
    func testRenamingAndNominalHorizonDoNotSupplyZAndSavedXYSurvivesReopen() throws {
        for level in Self.levels {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
            let (_, initial) = try P2MappingTests().configured(); try store.save(initial.journal)
            var w = try MappingWorkflow(store: store)
            let files = ManagedPlanStore(root: root.appendingPathComponent("plans"))
            let data = try bytes(level), doc = try DXFDocument.parse(data)
            // +393 is intentionally unrelated to all three fixture Z ranges.
            for filename in ["underground_survey_999.dxf", "no_level.dxf"] {
                let plan = try files.stage(data: data, filename: filename, horizonID: XCTUnwrap(w.context.horizonID),
                    version: "\(level)-\(filename)", units: .meters, crs: "synthetic local grid", axes: "X east / Y north / Z up")
                try w.registerPlan(plan); files.complete(plan)
                let expectedRow = try XCTUnwrap(String(data: resource("two_wall_elevation_controls.csv"), encoding: .utf8)?.split(separator: "\n").first { $0.hasPrefix("\(level),ramp_down_left_haul,") })
                let f = expectedRow.split(separator: ",")
                let expectedZ = Double(f[12])!, xy = PlanPoint(x: Double(f[2])!, y: Double(f[3])!)
                let hit = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: doc, plan: plan).automatic)
                try w.selectPlanPoint(xy, planID: plan.id, elevation: hit); w.draft.picket = "1"
                let record = try w.save()
                XCTAssertEqual(record.coordinates?.x, xy.x); XCTAssertEqual(record.coordinates?.y, xy.y)
                XCTAssertEqual(try XCTUnwrap(record.coordinates?.z), expectedZ, accuracy: 1e-8)
                XCTAssertEqual(record.coordinates?.zOrigin, .planGeometry)
                let reopened = try MappingWorkflow(store: store)
                XCTAssertEqual(reopened.observations.last?.coordinates, record.coordinates)
                XCTAssertEqual(try files.read(plan), data)
                let far = try XCTUnwrap(controls(level).first { $0.name == "at_8m" })
                try w.selectPlanPoint(far.point, planID: plan.id)
                XCTAssertEqual(w.draft.z, ""); XCTAssertNil(w.draft.zOrigin)
                XCTAssertNil(w.draft.zPlanGeometry) // Explicit fallback, never claimed to be DXF Z.
                XCTAssertEqual(try ElevationInput.meters(w.draft.x), far.point.x)
                XCTAssertEqual(try ElevationInput.meters(w.draft.y), far.point.y)
            }
        }
    }
}
