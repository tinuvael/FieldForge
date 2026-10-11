import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MeasurementTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func sample() -> SensorSample { MockSensorProvider.sample(dip: 45, direction: 90, timestamp: date) }

    func testHoldFreezesWholeObservation() async {
        let session = MeasurementSession()
        session.receive(sample())
        XCTAssertTrue(session.hold(now: date))
        let held = session.displayed
        session.receive(MockSensorProvider.sample(dip: 60, direction: 180, timestamp: date.addingTimeInterval(1)))
        XCTAssertEqual(session.displayed, held)
        XCTAssertTrue(session.canSave)
        XCTAssertEqual(session.record(notes: "test")?.notes, "test")
        session.markSaved()
        XCTAssertFalse(session.canSave)
        XCTAssertNil(session.record(notes: "again"))
        session.resume()
        XCTAssertFalse(session.isHeld)
        XCTAssertNil(session.displayed)
    }
    func testCannotSaveLiveOrUnavailable() async {
        let s = MeasurementSession()
        XCTAssertFalse(s.hold(now: date)); XCTAssertFalse(s.canSave)
        s.receive(sample()); XCTAssertFalse(s.canSave)
        s.invalidateLive(); XCTAssertNil(s.displayed)
    }
    func testStaleAndFutureSamplesCannotHold() async {
        let s = MeasurementSession(); s.receive(sample())
        XCTAssertFalse(s.hold(now: date.addingTimeInterval(2)))
        XCTAssertFalse(s.hold(now: date.addingTimeInterval(-1)))
    }
    func testMovementCannotSave() async {
        var value = sample(); value.userAcceleration.x = 0.2
        let s = MeasurementSession(); s.receive(value)
        XCTAssertEqual(s.displayed?.quality, .uncertain)
        XCTAssertFalse(s.hold(now: date))
    }
    func testHighRotationCannotSave() async {
        var value = sample(); value.rotationRate.y = 0.2
        XCTAssertFalse(Measurement.process(value).isSavable)
    }
    func testLowMagneticAccuracyHidesAzimuth() async {
        for accuracy in [MagneticAccuracy.low, .medium, .uncalibrated] {
            var value = sample(); value.source = .coreMotion; value.referenceFrame = .magneticNorthZVertical
            value.magneticField = .init(x: 30, y: 0, z: 0); value.magneticAccuracy = accuracy
            let m = Measurement.process(value)
            XCTAssertNil(m.orientation.dipDirection); XCTAssertEqual(m.quality, .inclinationOnly)
            XCTAssertTrue(m.isSavable)
        }
    }
    func testMagneticFieldGuard() async {
        var value = sample(); value.source = .coreMotion; value.referenceFrame = .magneticNorthZVertical
        value.magneticAccuracy = .high
        for strength in [0.0, 5, 150] {
            value.magneticField = .init(x: strength, y: 0, z: 0)
            XCTAssertNil(Measurement.process(value).orientation.dipDirection)
        }
        value.magneticField.x = 40
        XCTAssertEqual(Measurement.process(value).reference, .magneticNorth)
        XCTAssertEqual(Measurement.process(value).orientation.dipDirection ?? -1, 90, accuracy: 1e-9)
    }
    func testGravityMatrixMismatchIsInvalid() async {
        var value = sample(); value.gravity = .down
        XCTAssertEqual(Measurement.process(value).quality, .invalid)
    }
    func testNonFiniteDiagnostics() async {
        var value = sample(); value.userAcceleration.x = .nan
        XCTAssertFalse(Measurement.process(value).isSavable)
        value = sample(); value.quaternion.w = .infinity
        XCTAssertFalse(Measurement.process(value).isSavable)
    }
    func testTamperedDataRejected() async {
        var m = Measurement.process(sample()); m.orientation.dipDirection = 300
        XCTAssertFalse(m.isSavable)
        m = Measurement.process(sample()); m.orientation.dipAngle = -1
        XCTAssertFalse(m.isSavable)
        m = Measurement.process(sample()); m.quality = .invalid
        XCTAssertFalse(m.isSavable)
        m = Measurement.process(sample()); m.reference = .magneticNorth
        XCTAssertFalse(m.isSavable)
    }
    func testAmbiguousObservationsCanSaveInclination() async {
        for dip in [0.0, 90] {
            let m = Measurement.process(MockSensorProvider.sample(dip: dip, direction: 0, timestamp: date))
            XCTAssertNil(m.orientation.dipDirection); XCTAssertEqual(m.quality, .inclinationOnly); XCTAssertTrue(m.isSavable)
        }
    }
    func testPersistenceRoundTripAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let store = FileMeasurementStore(url: url)
        XCTAssertEqual(try store.load(), [])
        let m = Measurement.process(sample())
        try store.save([m])
        XCTAssertEqual(try FileMeasurementStore(url: url).load(), [m])
        try store.save([]); XCTAssertEqual(try store.load(), [])
    }
    func testCorruptFilePreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try FileMeasurementStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testUnsupportedSchemaPreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("{\"schemaVersion\":2,\"measurements\":[]}".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try FileMeasurementStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testStoreRejectsInvalidAndDuplicateRecords() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FileMeasurementStore(url: url)
        var m = Measurement.process(sample()); m.orientation.dipAngle = 91
        XCTAssertThrowsError(try store.save([m]))
        m = Measurement.process(sample())
        XCTAssertThrowsError(try store.save([m, m]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testMockLifecycleAndStates() async {
        let mock = MockSensorProvider(); var events: [SensorEvent] = []
        mock.onEvent = { events.append($0) }
        mock.emit(); XCTAssertTrue(events.isEmpty)
        mock.start(); XCTAssertEqual(events.count, 1)
        if case .sample(let value) = events[0] {
            XCTAssertEqual(value.source, .simulatorMock)
            XCTAssertTrue(value.hasFiniteDiagnostics)
            XCTAssertEqual(Measurement.process(value).orientation.dipAngle ?? -1, 45, accuracy: 1e-9)
        } else { XCTFail("Expected mock sample") }
        mock.condition = .unavailable; mock.emit()
        if case .unavailable = events[1] {} else { XCTFail("Expected unavailable state") }
        mock.stop(); mock.emit(); XCTAssertEqual(events.count, 2)
        XCTAssertFalse(mock.isRunning)
    }
    func testMockQuaternionMatchesMatrix() async {
        let value = sample(), q = value.quaternion
        // Independent standard quaternion-to-DCM expansion.
        XCTAssertEqual(value.rotation.row3.x, 2 * (q.x * q.z - q.w * q.y), accuracy: 1e-9)
        XCTAssertEqual(value.rotation.row3.y, 2 * (q.y * q.z + q.w * q.x), accuracy: 1e-9)
        XCTAssertEqual(value.rotation.row3.z, 1 - 2 * (q.x * q.x + q.y * q.y), accuracy: 1e-9)
    }
}
