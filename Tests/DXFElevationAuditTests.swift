import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class DXFElevationAuditTests: XCTestCase {
    private let line = "0\nLINE\n5\nA1\n10\n1\n20\n2\n30\n3\n11\n11\n21\n2\n31\n7\n"
    private func reference(_ bytes: Data, units: PlanUnits = .meters) throws -> MappingPlanReference {
        MappingPlanReference(id: UUID(), horizonID: UUID(), attachmentID: UUID(), version: "1",
            file: ManagedPlanFile(originalFilename: "synthetic.dxf", sha256: ManagedPlanStore.digest(bytes), byteCount: bytes.count,
                importedAt: Date(), units: units, crs: "unknown", axes: "unknown", unitDeclaration: "userConfirmedAtImport",
                insertionUnits: try DXFDocument.parse(bytes).insertionUnits))
    }
    private func blockDrawing(_ content: String, insert: String, base: String = "10\n1\n20\n2\n30\n3\n", extraBlocks: String = "") -> Data {
        Data(("0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n6\n0\nENDSEC\n0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nA\n70\n0\n" + base + content + "0\nENDBLK\n" + extraBlocks + "0\nENDSEC\n0\nSECTION\n2\nENTITIES\n" + insert + "0\nENDSEC\n0\nEOF\n").utf8)
    }
    func testOrdinaryPolylineUsesHeaderElevationRatherThanVertexDummyZ() throws {
        // Autodesk 2018 POLYLINE: header 30 is the elevation, 2D VERTEX Z is zero.
        for z in [-12.5, 0, 393] {
            let text = "0\nPOLYLINE\n70\n1\n30\n\(z)\n0\nVERTEX\n10\n0\n20\n0\n30\n0\n0\nVERTEX\n10\n10\n20\n0\n30\n0\n0\nVERTEX\n10\n10\n20\n10\n0\nSEQEND\n"
            let data = DXFFixtures.drawing(text), doc = try DXFDocument.parse(data)
            XCTAssertEqual(doc.elevationSegments.count, 3)
            XCTAssertTrue(doc.polylines[0].vertices.allSatisfy { $0.z == z })
            let found = PlanElevationSnap.resolve(PlanPoint(x: 5, y: 1), document: doc, plan: try reference(data))
            XCTAssertEqual(found.automatic?.elevationMeters, z)
            let missing = try DXFDocument.parse(DXFFixtures.drawing(text.replacingOccurrences(of: "30\n\(z)\n", with: "", range: text.range(of: "30\n\(z)\n"))))
            XCTAssertTrue(missing.elevationSegments.isEmpty)
        }
    }
    func testBlockBaseScaleRotationTranslationAndProvenanceWithIndependentControls() throws {
        // Base (1,2,3); scale (2,3,4); rotation +90°; insertion (100,200,10).
        // Local endpoints (1,2,3),(11,2,7) -> WCS (100,200,10),(100,220,26).
        let bytes = blockDrawing(line, insert: "0\nINSERT\n5\nB1\n2\nA\n10\n100\n20\n200\n30\n10\n41\n2\n42\n3\n43\n4\n50\n90\n")
        let doc = try DXFDocument.parse(bytes), segment = try XCTUnwrap(doc.elevationSegments.first)
        XCTAssertEqual(doc.elevationSegments.count, 1)
        XCTAssertEqual(segment.a, DXFVertex(x: 100, y: 200, z: 10))
        XCTAssertEqual(segment.b.x, 100, accuracy: 1e-12); XCTAssertEqual(segment.b.y, 220, accuracy: 1e-12)
        XCTAssertEqual(segment.extractionVersion, DXFDocument.elevationExtractionVersion)
        XCTAssertEqual(segment.b.z, 26); XCTAssertEqual(segment.blockPath, ["A@B1"])
        let point = PlanPoint(x: 101, y: 205)
        let z = try XCTUnwrap(PlanElevationSnap.resolve(point, document: doc, plan: reference(bytes)).automatic)
        XCTAssertEqual(z.elevationMeters, 14, accuracy: 1e-12); XCTAssertEqual(z.distanceMeters, 1, accuracy: 1e-12)
        XCTAssertEqual(z.selectedXY, point); try z.validate(plan: referenceWithIdentity(z, bytes: bytes))
    }
    private func referenceWithIdentity(_ z: PlanGeometryElevation, bytes: Data) throws -> MappingPlanReference {
        let p = try reference(bytes)
        return MappingPlanReference(id: z.planID, horizonID: p.horizonID, attachmentID: p.attachmentID, version: z.planRevision, file: p.file)
    }
    func testNestedBlocksTwoInstancesAndMissingZNeverFabricated() throws {
        let b = "0\nBLOCK\n2\nB\n10\n0\n20\n0\n30\n0\n0\nINSERT\n2\nA\n10\n10\n20\n0\n30\n5\n0\nENDBLK\n"
        let insert = "0\nINSERT\n2\nB\n10\n100\n20\n20\n30\n50\n0\nINSERT\n2\nB\n10\n200\n20\n20\n30\n50\n"
        let doc = try DXFDocument.parse(blockDrawing(line, insert: insert, base: "10\n0\n20\n0\n30\n0\n", extraBlocks: b))
        XCTAssertEqual(doc.elevationSegments.count, 2)
        XCTAssertEqual(doc.elevationSegments[0].a, DXFVertex(x: 111, y: 22, z: 58))
        XCTAssertEqual(doc.elevationSegments[1].a, DXFVertex(x: 211, y: 22, z: 58))
        XCTAssertEqual(doc.elevationSegments[0].blockPath?.count, 2)
        XCTAssertNotEqual(doc.elevationSegments[0].entityOrdinal, doc.elevationSegments[1].entityOrdinal)
        let missing = line.replacingOccurrences(of: "30\n3\n", with: "").replacingOccurrences(of: "31\n7\n", with: "")
        let noZ = try DXFDocument.parse(blockDrawing(missing, insert: "0\nINSERT\n2\nA\n10\n100\n20\n20\n30\n400\n"))
        XCTAssertTrue(noZ.elevationSegments.isEmpty); XCTAssertEqual(noZ.paths.count, 1)
    }
    func testBlockPolylineAndLwPolylineExplicitZeroAndElevation() throws {
        let insert = "0\nINSERT\n2\nA\n10\n100\n20\n200\n30\n10\n43\n2\n"
        for content in ["0\nPOLYLINE\n30\n0\n0\nVERTEX\n10\n0\n20\n0\n30\n0\n0\nVERTEX\n10\n10\n20\n0\n30\n0\n0\nSEQEND\n",
                        "0\nLWPOLYLINE\n90\n2\n38\n0\n10\n0\n20\n0\n10\n10\n20\n0\n"] {
            let doc = try DXFDocument.parse(blockDrawing(content, insert: insert))
            XCTAssertEqual(doc.elevationSegments.count, 1)
            XCTAssertEqual(doc.elevationSegments[0].a.z, 4); XCTAssertEqual(doc.elevationSegments[0].b.z, 4)
        }
    }
    func testUnsupportedBlockArrayCycleOCSAndHiddenGeometryAreDiagnosed() throws {
        let variants = ["70\n2\n", "210\n0\n220\n1\n230\n0\n", "60\n1\n"]
        for variant in variants {
            let bytes = blockDrawing(line, insert: line + "0\nINSERT\n2\nA\n10\n0\n20\n0\n" + variant)
            let doc = try DXFDocument.parse(bytes)
            XCTAssertEqual(doc.elevationSegments.count, 1)
            XCTAssertEqual(doc.elevationExclusions.values.reduce(0,+), 1)
            XCTAssertTrue(doc.elevationExclusions.keys.contains { $0.contains("INSERT") })
        }
        let cycle = "0\nINSERT\n2\na\n10\n0\n20\n0\n"
        let doc = try DXFDocument.parse(blockDrawing(line + cycle, insert: cycle))
        XCTAssertEqual(doc.elevationSegments.count, 1); XCTAssertTrue(doc.warnings.contains { $0.contains("cycle") })
    }
    func testOriginalFilesAuditAndReopenUsesNewParserWithoutReimport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ManagedPlanStore(root: root)
        for control in DXFRealTests.controls {
            let bytes = try DXFRealTests.data(control.level)
            let plan = try files.stage(data: bytes, filename: "\(control.level).dxf", horizonID: UUID(), version: "1", units: .meters, crs: "unknown", axes: "unknown")
            files.complete(plan)
            let oldReference = try JSONDecoder().decode(MappingPlanReference.self, from: JSONEncoder().encode(plan))
            let doc = try DXFDocument.parse(files.read(oldReference))
            XCTAssertEqual(doc.elevationSegments.count, control.level == 400 ? 290 : 614)
            let near = try XCTUnwrap(PlanElevationSnap.resolve(control.first.xy, document: doc, plan: oldReference).automatic)
            XCTAssertEqual(near.elevationMeters, control.first.z)
            let center = PlanElevationSnap.resolve(control.bounds.center, document: doc, plan: oldReference)
            let estimate = try XCTUnwrap(center.automatic)
            try estimate.validate(plan: oldReference)
            XCTAssertEqual(estimate.selectedXY, control.bounds.center)
            XCTAssertEqual(try XCTUnwrap(center.nearestDistanceMeters), control.level == 400 ? 0.7073080051541791 : 8.5, accuracy: 1e-8)
            XCTAssertEqual(estimate.method, PlanGeometryElevation.nearestVersion)
            XCTAssertEqual(try files.read(oldReference), bytes)
        }
    }
    func testDiagnosticsDifferentiateMissingZUnitsAndUnsupportedEntities() throws {
        let bytes = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n11\n10\n21\n0\n")
        let doc = try DXFDocument.parse(bytes), p = try reference(bytes)
        XCTAssertEqual(doc.elevationExclusions.values.reduce(0,+), 1)
        XCTAssertTrue(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 0), document: doc, plan: p).failureReason?.contains("явными") == true)
        let unknown = try reference(bytes, units: .unknown)
        XCTAssertTrue(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 0), document: doc, plan: unknown).failureReason?.contains("не подтверждены") == true)
        let unsupported = try DXFDocument.parse(DXFFixtures.drawing("0\nSPLINE\n" + "0\nLINE\n10\n0\n20\n0\n11\n10\n21\n0\n"))
        XCTAssertTrue(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 0), document: unsupported, plan: p).failureReason?.contains("неподдерживаемые") == true)
    }
}
