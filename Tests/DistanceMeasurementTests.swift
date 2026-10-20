import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class DistanceMeasurementTests: XCTestCase {
    func testIndependentSpatialReferenceDistancesAndPrecision() throws {
        // Axis length; 3-4-12 right triangle; translated/negative endpoints.
        for (a, b, expected) in [
            (Vector3(x: 0, y: 0, z: 0), Vector3(x: 1.247123456, y: 0, z: 0), 1.247123456),
            (Vector3(x: -2, y: 3, z: -5), Vector3(x: 1, y: 7, z: 7), 13),
            (Vector3(x: 2, y: 2, z: 2), Vector3(x: 1, y: 0, z: 0), 3),
            // OpenStax Calculus Vol. 3 (2016), §2.2, Example 2.12.
            (Vector3(x: 3, y: -1, z: 5), Vector3(x: 2, y: 1, z: -1), sqrt(41))
        ] {
            XCTAssertEqual(try XCTUnwrap(DistanceMath.metres(from: a, to: b)), expected, accuracy: 1e-12)
            XCTAssertEqual(DistanceMath.metres(from: a, to: b), DistanceMath.metres(from: b, to: a))
        }
        XCTAssertEqual(DistanceMath.text(1.247123456), "1,247 м")
        // hypot avoids overflow in squaring otherwise representable distances.
        XCTAssertEqual(try XCTUnwrap(DistanceMath.metres(from: .init(x: 0, y: 0, z: 0),
                                                      to: .init(x: 1e200, y: 0, z: 0))), 1e200)
    }
    func testInvalidCoordinatesZeroAndOverflowAreRejected() {
        let origin = Vector3(x: 0, y: 0, z: 0)
        for value in [Double.nan, .infinity, -.infinity] {
            for bad in [Vector3(x: value, y: 1, z: 1), .init(x: 1, y: value, z: 1), .init(x: 1, y: 1, z: value)] {
                XCTAssertNil(DistanceMath.metres(from: origin, to: bad))
                XCTAssertNil(DistanceMath.metres(from: bad, to: origin))
            }
        }
        XCTAssertNil(DistanceMath.metres(from: origin, to: origin))
        XCTAssertNil(DistanceMath.metres(from: .init(x: -Double.greatestFiniteMagnitude, y: 0, z: 0),
                                        to: .init(x: Double.greatestFiniteMagnitude, y: 0, z: 0)))
    }
    func testFrameFreshnessRejectsOldSessionStaleAndInvalidTimes() {
        XCTAssertTrue(DistanceSnapshot.acceptsFrame(timestamp: 11, sessionStartedAt: 10, now: 11.1))
        for (timestamp, start, now) in [(9.9, 10.0, 10.1), (10, 9, 10.5), (11, 10, 10),
                                      (Double.nan, 10, 11), (11, Double.infinity, 11), (11, 10, Double.nan)] {
            XCTAssertFalse(DistanceSnapshot.acceptsFrame(timestamp: timestamp, sessionStartedAt: start, now: now))
        }
    }
    @MainActor func testBriefTrackingLossBetweenPollsInvalidatesFirstPoint() {
        let session = DistanceSessionFixture()
        let controller = DistanceMeasurementController(session: session)
        controller.start(); controller.select()
        controller.trackingLost(.poorTracking)
        // The next poll can already be normal; the event still forces retake.
        controller.refresh(); controller.select()
        XCTAssertTrue(controller.needsRetake); XCTAssertNil(controller.first); XCTAssertNil(controller.metres)
        controller.stop(.closed)
        controller.trackingLost(.poorTracking)
        XCTAssertEqual(controller.status, .closed)
    }
    func testDepthBackProjectionCameraConventions() {
        XCTAssertEqual(DistanceMath.cameraPoint(u: 320, v: 240, depth: 2, fx: 500, fy: 400, cx: 320, cy: 240),
                       Vector3(x: 0, y: 0, z: -2))
        // Known pinhole fixture: 250px right, 100px down, axial depth 2m.
        XCTAssertEqual(DistanceMath.cameraPoint(u: 570, v: 340, depth: 2, fx: 500, fy: 400, cx: 320, cy: 240),
                       Vector3(x: 1, y: -0.5, z: -2))
        for depth in [0, -1, Double.nan, .infinity] {
            XCTAssertNil(DistanceMath.cameraPoint(u: 0, v: 0, depth: depth, fx: 1, fy: 1, cx: 0, cy: 0))
        }
        XCTAssertNil(DistanceMath.cameraPoint(u: .nan, v: 0, depth: 2, fx: 1, fy: 1, cx: 0, cy: 0))
        XCTAssertNil(DistanceMath.cameraPoint(u: 0, v: 0, depth: 2, fx: 0, fy: 1, cx: 0, cy: 0))
        XCTAssertNil(DistanceMath.cameraPoint(u: 0, v: 0, depth: 2, fx: 1, fy: -1, cx: 0, cy: 0))
    }
    @MainActor func testTwoPointStateRetakeAndFreshTapQuery() throws {
        let session = DistanceSessionFixture()
        let controller = DistanceMeasurementController(session: session)
        XCTAssertFalse(controller.canSelect)
        controller.select(); XCTAssertEqual(session.reads, 0)
        controller.start(); controller.start(); XCTAssertEqual(session.starts, 1)
        controller.refresh(); XCTAssertTrue(controller.canSelect)
        controller.select(); XCTAssertNotNil(controller.first); XCTAssertNil(controller.metres)
        session.next = .init(status: .ready, point: .init(position: .init(x: 3, y: 4, z: 12), source: .detectedPlane))
        controller.select()
        XCTAssertEqual(controller.metres, 13); XCTAssertFalse(controller.canSelect)
        XCTAssertEqual(controller.second?.source, .detectedPlane)
        XCTAssertEqual(controller.result?.source, .detectedPlane)
        XCTAssertEqual(controller.result?.metres, 13)
        let reads = session.reads
        controller.select(); XCTAssertEqual(session.reads, reads)
        controller.retake()
        XCTAssertEqual(session.starts, 2); XCTAssertEqual(session.pauses, 1)
        XCTAssertNil(controller.first); XCTAssertNil(controller.second); XCTAssertNil(controller.metres)
        XCTAssertFalse(controller.canSelect); XCTAssertFalse(controller.needsRetake)
    }
    @MainActor func testUnreliableSnapshotsCannotSelectAndTrackingLossRequiresRetake() {
        let session = DistanceSessionFixture()
        let controller = DistanceMeasurementController(session: session)
        controller.start(); controller.refresh()
        // Tap sees the new failure instead of the formerly ready preview.
        session.next = .init(status: .noSurface, point: nil)
        controller.select(); XCTAssertNil(controller.first)
        session.next = .init(status: .ready, point: .init(position: .init(x: .nan, y: 0, z: 0), source: .lidarDepth))
        controller.select(); XCTAssertNil(controller.first); XCTAssertEqual(controller.status, .noSurface)
        for status in [DistanceStatus.starting, .poorTracking, .insufficientFeatures, .excessiveMotion] {
            controller.retake(); session.next = session.origin; controller.select()
            session.next = .init(status: status, point: session.origin.point)
            controller.refresh()
            XCTAssertNil(controller.first); XCTAssertNil(controller.metres); XCTAssertTrue(controller.needsRetake)
            session.next = session.origin; controller.refresh(); controller.select()
            XCTAssertFalse(controller.canSelect); XCTAssertNil(controller.first)
        }
    }
    @MainActor func testMissingSurfacePreservesFirstButNeverCreatesSecondOrZeroDistance() {
        let session = DistanceSessionFixture()
        let controller = DistanceMeasurementController(session: session)
        controller.start(); controller.select()
        session.next = .init(status: .noSurface, point: nil)
        controller.select(); XCTAssertNotNil(controller.first); XCTAssertNil(controller.metres)
        session.next = session.origin
        controller.select(); XCTAssertNil(controller.second); XCTAssertNil(controller.metres)
    }
    @MainActor func testSessionLifecycleClearsPairsAndIgnoresLateSnapshots() {
        for reason in [DistanceStatus.interrupted, .background, .closed, .failed, .cameraDenied, .unsupported] {
            let session = DistanceSessionFixture()
            let controller = DistanceMeasurementController(session: session)
            controller.start(); controller.select()
            session.next = .init(status: .ready, point: .init(position: .init(x: 1, y: 0, z: 0), source: .lidarDepth))
            controller.select(); XCTAssertEqual(controller.metres, 1)
            controller.stop(reason); controller.stop(reason)
            XCTAssertEqual(session.pauses, 1); XCTAssertFalse(controller.running)
            XCTAssertNil(controller.first); XCTAssertNil(controller.second); XCTAssertNil(controller.metres)
            let reads = session.reads
            controller.refresh(); controller.select()
            XCTAssertEqual(session.reads, reads); XCTAssertEqual(controller.status, reason)
            controller.start(); XCTAssertEqual(session.starts, 2); XCTAssertNil(controller.first)
        }
    }
    @MainActor func testCompletedResultInvalidatedByTrackingLoss() {
        let session = DistanceSessionFixture()
        let controller = DistanceMeasurementController(session: session)
        controller.start(); controller.select()
        session.next = .init(status: .ready, point: .init(position: .init(x: 1, y: 0, z: 0), source: .lidarDepth))
        controller.select(); XCTAssertEqual(controller.metres, 1)
        session.next = .init(status: .poorTracking, point: nil)
        controller.refresh(); XCTAssertNil(controller.metres); XCTAssertTrue(controller.needsRetake)
    }
}

@MainActor private final class DistanceSessionFixture: DistanceSession {
    let origin = DistanceSnapshot(status: .ready, point: .init(position: .init(x: 0, y: 0, z: 0), source: .lidarDepth))
    lazy var next = origin
    var starts = 0
    var pauses = 0
    var reads = 0
    func start() { starts += 1 }
    func pause() { pauses += 1 }
    func snapshot() -> DistanceSnapshot { reads += 1; return next }
}
