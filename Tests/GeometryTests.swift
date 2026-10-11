import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class GeometryTests: XCTestCase {
    private func check(_ normal: Vector3, dip: Double, direction: Double?,
                       status: CalculationStatus = .valid, file: StaticString = #filePath, line: UInt = #line) {
        let result = PlaneGeometry.calculate(normal: normal, hasNorthReference: true)
        XCTAssertEqual(result.dipAngle ?? -1, dip, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(result.status, status, file: file, line: line)
        if let direction { XCTAssertEqual(result.dipDirection ?? -1, direction, accuracy: 1e-9, file: file, line: line) }
        else { XCTAssertNil(result.dipDirection, file: file, line: line) }
    }
    func testHorizontal() { check(.init(x: 0, y: 0, z: 1), dip: 0, direction: nil, status: .horizontalAmbiguity) }
    func testVertical() { check(.init(x: 1, y: 0, z: 0), dip: 90, direction: nil, status: .verticalAmbiguity) }
    func testThirtyDegreesNorth() { check(.init(x: 1, y: 0, z: sqrt(3)), dip: 30, direction: 0) }
    func testFortyFiveDegreesEast() { check(.init(x: 0, y: -1, z: 1), dip: 45, direction: 90) }
    func testSixtyDegreesSouth() { check(.init(x: -sqrt(3), y: 0, z: 1), dip: 60, direction: 180) }
    func testWest() { check(.init(x: 0, y: 1, z: 1), dip: 45, direction: 270) }
    func testDiagonalNorthEast() { check(.init(x: 1, y: -1, z: sqrt(2)), dip: 45, direction: 45) }
    func testDiagonalSouthWest() { check(.init(x: -1, y: 1, z: sqrt(2)), dip: 45, direction: 225) }
    func testNearNorthFromBothSides() {
        let westOfNorth = PlaneGeometry.calculate(normal: .init(x: 1, y: 1e-6, z: 1), hasNorthReference: true)
        let eastOfNorth = PlaneGeometry.calculate(normal: .init(x: 1, y: -1e-6, z: 1), hasNorthReference: true)
        XCTAssertEqual(westOfNorth.dipDirection ?? -1, 359.9999427042205, accuracy: 1e-9)
        XCTAssertEqual(eastOfNorth.dipDirection ?? -1, 0.0000572957795, accuracy: 1e-9)
    }
    func testNormalization() {
        XCTAssertEqual(PlaneGeometry.normalizeAzimuth(-1), 359)
        XCTAssertEqual(PlaneGeometry.normalizeAzimuth(360), 0)
        XCTAssertEqual(PlaneGeometry.normalizeAzimuth(721), 1)
        XCTAssertNil(PlaneGeometry.normalizeAzimuth(.nan))
        XCTAssertNil(PlaneGeometry.normalizeAzimuth(.infinity))
    }
    func testReversedNormal() {
        for n in [Vector3(x: 1, y: -1, z: 1), .init(x: 0, y: 0, z: 1), .init(x: 0, y: 1, z: 0)] {
            let a = PlaneGeometry.calculate(normal: n, hasNorthReference: true)
            let b = PlaneGeometry.calculate(normal: n * -1, hasNorthReference: true)
            XCTAssertEqual(a.dipAngle, b.dipAngle)
            XCTAssertEqual(a.dipDirection, b.dipDirection)
            XCTAssertEqual(a.status, b.status)
        }
    }
    func testRotationWithinPlane() {
        // A 45° north-dipping plane. Two screen bases differ by 90° within that same plane.
        let c = sqrt(0.5)
        let a = RotationMatrix(row1: .init(x: c, y: 0, z: -c), row2: .init(x: 0, y: 1, z: 0), row3: .init(x: c, y: 0, z: c))
        let b = RotationMatrix(row1: .init(x: 0, y: 1, z: 0), row2: .init(x: -c, y: 0, z: c), row3: a.row3)
        let r1 = PlaneGeometry.calculate(rotation: a, hasNorthReference: true)
        let r2 = PlaneGeometry.calculate(rotation: b, hasNorthReference: true)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r1.dipAngle ?? -1, 45, accuracy: 1e-9)
        XCTAssertEqual(r1.dipDirection ?? -1, 0, accuracy: 1e-9)
    }
    func testMatrixTransposeConvention() {
        let c = sqrt(0.5)
        let r = RotationMatrix(row1: .init(x: c, y: 0, z: -c), row2: .init(x: 0, y: 1, z: 0), row3: .init(x: c, y: 0, z: c))
        XCTAssertEqual(r.deviceToReference(.screenNormal), r.row3)
        XCTAssertEqual(r.referenceToDevice(.down), Vector3(x: c, y: 0, z: -c))
        XCTAssertEqual(r.deviceToReference(r.referenceToDevice(.down)).z, -1, accuracy: 1e-9)
    }
    func testNearlyHorizontal() {
        let result = PlaneGeometry.calculate(normal: .init(x: 0.001, y: 0, z: 1), hasNorthReference: true)
        XCTAssertEqual(result.status, .horizontalAmbiguity)
        XCTAssertNil(result.dipDirection)
        XCTAssertGreaterThan(result.dipAngle ?? 0, 0)
    }
    func testNearlyVertical() {
        let result = PlaneGeometry.calculate(normal: .init(x: 1, y: 0, z: 0.001), hasNorthReference: true)
        XCTAssertEqual(result.status, .verticalAmbiguity)
        XCTAssertNil(result.dipDirection)
        XCTAssertLessThan(result.dipAngle ?? 90, 90)
    }
    func testOutsideAmbiguityGuard() {
        for n in [Vector3(x: 0.02, y: 0, z: 1), .init(x: 1, y: 0, z: 0.02)] {
            XCTAssertEqual(PlaneGeometry.calculate(normal: n, hasNorthReference: true).status, .valid)
        }
    }
    func testMissingNorthKeepsDip() {
        let result = PlaneGeometry.calculate(normal: .init(x: 1, y: 0, z: 1), hasNorthReference: false)
        XCTAssertEqual(result.dipAngle ?? -1, 45, accuracy: 1e-9)
        XCTAssertNil(result.dipDirection)
        XCTAssertEqual(result.status, .referenceUnavailable)
    }
    func testInvalidNormals() {
        for n in [Vector3(x: 0, y: 0, z: 0), .init(x: .nan, y: 0, z: 1), .init(x: 1, y: .infinity, z: 1)] {
            XCTAssertEqual(PlaneGeometry.calculate(normal: n, hasNorthReference: true), .invalid)
        }
    }
    func testExtremeFiniteScales() {
        for scale in [1e300, 1e-300] { check(.init(x: scale, y: 0, z: scale), dip: 45, direction: 0) }
    }
    func testInvalidMatrices() {
        let scaled = RotationMatrix(row1: .init(x: 2, y: 0, z: 0), row2: .init(x: 0, y: 1, z: 0), row3: .screenNormal)
        let reflected = RotationMatrix(row1: .init(x: -1, y: 0, z: 0), row2: .init(x: 0, y: 1, z: 0), row3: .screenNormal)
        for r in [scaled, reflected] { XCTAssertEqual(PlaneGeometry.calculate(rotation: r, hasNorthReference: true), .invalid) }
    }
}
