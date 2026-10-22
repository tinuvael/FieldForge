import XCTest
#if canImport(Darwin)
import Darwin
#endif
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class PlanElevationIndexTests: XCTestCase {
    private func segment(_ id: Int, _ a: (Double, Double, Double), _ b: (Double, Double, Double), wall: Int? = nil) -> DXFElevationSegment {
        DXFElevationSegment(a: DXFVertex(x: a.0, y: a.1, z: a.2), b: DXFVertex(x: b.0, y: b.1, z: b.2),
            entityType: "LINE", handle: String(id), entityOrdinal: wall ?? id, segmentIndex: wall == nil ? 0 : id)
    }
    private var local: [DXFElevationSegment] {
        [segment(0, (0, 0, 100), (100, 0, 120)), segment(1, (0, 10, 110), (100, 10, 150))]
    }
    private func document(_ segments: [DXFElevationSegment]) -> DXFDocument {
        DXFDocument(paths: [], polylines: [], points: [], labels: [],
            bounds: PlanBounds(minX: 0, minY: 0, maxX: 100, maxY: 10), insertionUnits: 6, warnings: [], elevationSegments: segments)
    }
    private var plan: MappingPlanReference {
        MappingPlanReference(id: UUID(), horizonID: UUID(), attachmentID: UUID(), version: "1",
            file: ManagedPlanFile(originalFilename: "stress.dxf", sha256: String(repeating: "a", count: 64), byteCount: 1,
                importedAt: Date(), units: .meters, crs: "local", axes: "XYZ", unitDeclaration: "userConfirmedAtImport", insertionUnits: 6))
    }
    private func residentBytes() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info(), count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
        #else
        return 0
        #endif
    }
    private func stress(_ count: Int) throws {
        let p = PlanPoint(x: 25, y: 2), plan = plan
        let baseline = try XCTUnwrap(PlanElevationSnap.resolve(p, document: document(local), plan: plan).automatic)
        var segments = local
        segments.reserveCapacity(count)
        // Every remote segment is an independent wall, on both sides of the tap.
        for i in 2..<count {
            let x = 100000 + Double(i % 1000) * 4, y = Double(i / 1000) * 4 + 100000
            segments.append(segment(i, (x, i.isMultiple(of: 2) ? y : -y, 700), (x + 2, i.isMultiple(of: 2) ? y : -y, 701)))
        }
        let before = residentBytes(), start = Date()
        let doc = document(segments), buildSeconds = Date().timeIntervalSince(start)
        let residentDelta = residentBytes() > before ? residentBytes() - before : 0
        let index = doc.elevationIndex, copy = doc
        XCTAssertTrue(copy.elevationIndex === index) // Document copies/taps never rebuild.
        XCTAssertEqual(index.segmentCount, count)
        var metrics = PlanElevationIndex.QueryMetrics()
        let hits = index.nearby(p, radius: 20, metrics: &metrics)
        XCTAssertEqual(hits, [0, 1]); XCTAssertLessThan(metrics.projectedSegments, 64)
        let tapStart = Date()
        for _ in 0..<20 {
            let z = try XCTUnwrap(PlanElevationSnap.resolve(p, document: doc, plan: plan).automatic)
            XCTAssertEqual(z, baseline)
            XCTAssertEqual(z.elevationMeters, 108, accuracy: 1e-12) // 105 + (120-105)*2/10.
            XCTAssertEqual(z.selectedXY, p)
        }
        let tapSeconds = Date().timeIntervalSince(tapStart) / 20
        XCTAssertLessThan(tapSeconds, 0.1)
        XCTAssertLessThan(buildSeconds, 30)
        XCTAssertLessThan(index.storageBytes, count * 256)
        if before > 0 { XCTAssertLessThan(residentDelta, 160 * 1024 * 1024) }
        print("BVH stress segments=\(count) build_s=\(buildSeconds) tap_ms=\(tapSeconds * 1000) index_payload_bytes=\(index.storageBytes) resident_delta_bytes=\(residentDelta) query_projections=\(metrics.projectedSegments)")
        // Both stress sizes also retain local crossing/overpass ambiguity.
        let competing = document(segments + [segment(count, (20, -100, 200), (20, 100, 200)),
            segment(count + 1, (30, -100, 210), (30, 100, 210))])
        XCTAssertNil(PlanElevationSnap.resolve(p, document: competing, plan: plan).automatic)
        let confirmed = try XCTUnwrap(PlanWallSection.confirmedPair(p, walls: local.map(\.wallID), document: competing, plan: plan))
        XCTAssertEqual(confirmed.elevationMeters, 108); XCTAssertEqual(confirmed.selectedXY, p)

    }
    func testTenThousandSegmentsIgnoreDistantIndependentWalls() throws { try stress(10_000) }
    func testHundredThousandSegmentsIgnoreDistantIndependentWalls() throws { try stress(100_000) }
    func testNearbyCrossingAndAdjacentUnnamedDrivesRemainAmbiguousWithRemoteNoise() throws {
        var segments = local + [segment(2, (20, -100, 200), (20, 100, 200)), segment(3, (30, -100, 210), (30, 100, 210))]
        for i in 4..<10_000 { segments.append(segment(i, (Double(i), 10000, 0), (Double(i) + 1, 10000, 0))) }
        let p = PlanPoint(x: 25, y: 2), doc = document(segments)
        let ambiguous = PlanElevationSnap.resolve(p, document: doc, plan: plan)
        XCTAssertNil(ambiguous.automatic)
        let confirmed = try XCTUnwrap(PlanWallSection.confirmedPair(p, walls: local.map(\.wallID), document: doc, plan: plan))
        XCTAssertEqual(confirmed.elevationMeters, 108); XCTAssertEqual(confirmed.selectedXY, p)
        let adjacent = document(local + [segment(4, (0, 20, 200), (100, 20, 200)), segment(5, (0, 30, 210), (100, 30, 210))])
        XCTAssertTrue(PlanElevationSnap.resolve(PlanPoint(x: 25, y: 15), document: adjacent, plan: plan).requiresChoice)
    }
    func testExpansionFindsOppositeWallBeyondInitialNeighborhoodAndHandlesLongCrossingBounds() throws {
        let p = PlanPoint(x: 25, y: 1), doc = document(local)
        // Initial disk radius=2 contains only the near wall; the other is 9 m away.
        let z = try XCTUnwrap(PlanElevationSnap.resolve(p, document: doc, plan: plan).automatic)
        XCTAssertEqual(z.elevationMeters, 106.5); XCTAssertEqual(z.secondWall?.distanceMeters, 9)
        let long = segment(2, (-1000000, 2, 300), (1000000, 2, 500))
        let index = document(local + [long]).elevationIndex
        XCTAssertTrue(index.nearby(p, radius: 1).contains(2)) // Neither vertex is near the tap.
        XCTAssertEqual(index.nearby(long.a.xy, radius: 0), [2])
    }
    func testNearestAndDiskOrderingMatchIndependentBruteForceIncludingTiesAndInvalidSegments() {
        var segments = local
        for i in 2..<300 {
            segments.append(segment(i, (Double((i * 37) % 103), Double((i * 17) % 97), 0),
                (Double((i * 13) % 103), Double((i * 29) % 97), 10)))
        }
        segments.append(segment(300, (0, 0, 0), (0, 0, 5))) // XY-degenerate exclusion.
        segments.append(segment(301, (.nan, 0, 0), (1, 1, 1)))
        let index = document(segments).elevationIndex
        for p in [PlanPoint(x: 25, y: 5), PlanPoint(x: -10, y: 13), PlanPoint(x: 102, y: 93)] {
            let ordered = segments.indices.compactMap { id -> (Int, Double)? in
                guard let q = segments[id].projection(p) else { return nil }; return (id, q.distance)
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            var metrics = PlanElevationIndex.QueryMetrics()
            XCTAssertEqual(index.nearest(p, metrics: &metrics), ordered.first?.0)
            XCTAssertEqual(index.nearby(p, radius: 12), ordered.filter { $0.1 <= 12 }.map(\.0))
        }
        let tied = document([segment(10, (0, 0, 0), (10, 0, 0)), segment(2, (0, 10, 0), (10, 10, 0))]).elevationIndex
        XCTAssertEqual(tied.nearby(PlanPoint(x: 5, y: 5), radius: 5), [1, 0])
        XCTAssertNil(tied.nearest(PlanPoint(x: .nan, y: 0), wallID: "10:"))
        XCTAssertNil(PlanWallSection.confirmedPair(PlanPoint(x: .nan, y: 0), walls: local.map(\.wallID), document: document(local), plan: plan))
    }
    func testImportBuildsIndexOnceForOneHundredThousandDXFSegments() throws {
        var entities = "0\nLINE\n10\n0\n20\n0\n30\n100\n11\n100\n21\n0\n31\n120\n0\nLINE\n10\n0\n20\n10\n30\n110\n11\n100\n21\n10\n31\n150\n"
        for i in 2..<100_000 {
            entities += "0\nLINE\n10\n\(100000 + i)\n20\n100000\n30\n700\n11\n\(100001 + i)\n21\n100000\n31\n701\n"
        }
        let bytes = DXFFixtures.drawing(entities, units: 6), start = Date()
        XCTAssertLessThan(bytes.count, 10_000_000)
        let doc = try DXFDocument.parse(bytes)
        XCTAssertEqual(doc.elevationIndex.segmentCount, 100_000)
        let z = try XCTUnwrap(PlanElevationSnap.resolve(PlanPoint(x: 25, y: 2), document: doc, plan: plan).automatic)
        XCTAssertEqual(z.elevationMeters, 108)
        print("100000-segment DXF import bytes=\(bytes.count) seconds=\(Date().timeIntervalSince(start))")
    }
}
