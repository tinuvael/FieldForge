import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class ManualMeasurementTests: XCTestCase {
    private func input(_ dip: String = "45", _ direction: String = "360",
                       north: GeographicReference = .unknown, convention: Bool = false) -> ManualOrientationInput {
        ManualOrientationInput(dipAngleText: dip, dipDirectionText: direction,
                               reference: north, usesConventionalDipSide: convention)
    }
    func testManualObservationHasNoSensorSampleAndRetainsOriginalEntry() throws {
        let record = try input("45,25", "360").observation(notes: "Забой")
        XCTAssertNil(record.sample)
        XCTAssertNil(record.orientation.normal)
        XCTAssertEqual(record.source, .manualCompass)
        XCTAssertEqual(record.quality, .manualUnverified)
        XCTAssertEqual(record.orientation.dipDirection, 0)
        XCTAssertEqual(record.orientation.dipAngle, 45.25)
        XCTAssertEqual(record.manualInput?.dipDirectionText, "360")
        XCTAssertEqual(record.manualInput?.dipAngleText, "45,25")
        XCTAssertEqual(record.notes, "Забой")
        XCTAssertTrue(record.isSavable)
    }
    func testDipBoundsAndMalformedNumbers() {
        for text in ["", "-1", "90.001", "nan", "inf", "∞", "45°", "1,2,3", "text"] {
            XCTAssertThrowsError(try input(text).observation(), text)
        }
        XCTAssertNoThrow(try input("0", "").observation())
        XCTAssertNoThrow(try input("90", "").observation())
    }
    func testDirectionBoundsAndMalformedNumbers() {
        for text in ["-0.1", "360.1", "nan", "inf", "abc", "1.2.3"] {
            XCTAssertThrowsError(try input("30", text).observation(), text)
        }
        XCTAssertNoThrow(try input("30", "0").observation())
        XCTAssertNoThrow(try input("30", "359,999").observation())
        XCTAssertNoThrow(try input("30", "360").observation())
    }
    func testHorizontalDirectionIsUndefined() throws {
        let record = try input("0", "   ").observation()
        XCTAssertNil(record.orientation.dipDirection)
        XCTAssertEqual(record.orientation.status, .horizontalAmbiguity)
        XCTAssertEqual(record.directionMeaning, .undefined)
        XCTAssertTrue(record.isSavable)
        XCTAssertThrowsError(try input("0", "0").observation())
    }
    func testInclinedPlaneRequiresDirection() {
        XCTAssertThrowsError(try input("45", "").observation())
    }
    func testVerticalDirectionRequiresExplicitConvention() throws {
        let undefined = try input("90", "").observation()
        XCTAssertNil(undefined.orientation.dipDirection)
        XCTAssertEqual(undefined.directionMeaning, .undefined)
        XCTAssertTrue(undefined.isSavable)
        XCTAssertThrowsError(try input("90", "180").observation())
        let conventional = try input("90", "180", convention: true).observation()
        XCTAssertEqual(conventional.orientation.dipDirection, 180)
        XCTAssertEqual(conventional.orientation.status, .verticalAmbiguity)
        XCTAssertEqual(conventional.directionMeaning, .conventionalDipSide)
        XCTAssertTrue(conventional.isSavable)
    }
    func testConventionCannotBeAppliedToInclinedOrDirectionlessPlane() {
        XCTAssertThrowsError(try input("45", "180", convention: true).observation())
        XCTAssertThrowsError(try input("90", "", convention: true).observation())
    }
    func testManualAnglesDoNotUseSensorSingularityGuard() throws {
        for dip in ["0.2", "89.8"] {
            let record = try input(dip, "123.45678901234567").observation()
            XCTAssertEqual(record.orientation.status, .valid)
            XCTAssertEqual(record.directionMeaning, .downhill)
            XCTAssertEqual(record.orientation.dipDirection, 123.45678901234567)
        }
    }
    func testAllManualNorthReferencesPreservedWithoutConversion() throws {
        for north in GeographicReference.manualChoices {
            let record = try input("35", "123.45678901234567", north: north).observation()
            XCTAssertEqual(record.reference, north)
            XCTAssertEqual(record.orientation.dipDirection, 123.45678901234567)
            XCTAssertTrue(record.isSavable)
        }
        for north in [GeographicReference.simulatedNorth, .unavailable] {
            XCTAssertThrowsError(try input(north: north).observation())
        }
    }
    func testTamperedManualMetadataRejected() throws {
        let original = try input().observation()
        var record = original; record.source = .iPhoneSensor
        XCTAssertFalse(record.isSavable)
        record = original; record.reference = .trueNorth
        XCTAssertFalse(record.isSavable)
        record = original; record.quality = .experimental
        XCTAssertFalse(record.isSavable)
        record = original; record.orientation.dipAngle = 46
        XCTAssertFalse(record.isSavable)
        record = original; record.directionMeaning = .conventionalDipSide
        XCTAssertFalse(record.isSavable)
        record = original; record.manualInput = nil
        XCTAssertFalse(record.isSavable)
        record = original; record.timestamp = Date(timeIntervalSince1970: .infinity)
        XCTAssertFalse(record.isSavable)
    }
    @MainActor func testSensorAndManualProvenanceCannotBeInterchanged() async throws {
        let sample = MockSensorProvider.sample(dip: 45, direction: 90, timestamp: Date())
        let mock = Measurement.process(sample)
        XCTAssertEqual(mock.source, .simulatorMock)
        XCTAssertNotNil(mock.sample)
        var manual = try input().observation(); manual.sample = sample
        XCTAssertFalse(manual.isSavable)
        var sensor = mock; sensor.source = .manualCompass
        XCTAssertFalse(sensor.isSavable)
        sensor = mock; sensor.sample = nil
        XCTAssertFalse(sensor.isSavable)
        sensor = mock; sensor.manualInput = input()
        XCTAssertFalse(sensor.isSavable)
        sensor = mock; sensor.source = .externalInstrument
        XCTAssertFalse(sensor.isSavable)
    }
    func testMixedPersistenceAndDuplicateRejection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Phase1Fixtures.journal.write(to: url)
        let store = FileMeasurementStore(url: url)
        let migrated = try store.load()
        let manual = try input(north: .gridNorth).observation(notes: "Ручная запись")
        try store.save([manual] + migrated)
        let loaded = try FileMeasurementStore(url: url).load()
        XCTAssertEqual(loaded.count, 4)
        XCTAssertEqual(loaded.first, manual)
        XCTAssertEqual(Set(loaded.map(\.source)), [.manualCompass, .iPhoneSensor, .simulatorMock])
        XCTAssertThrowsError(try store.save(loaded + [manual]))
        XCTAssertEqual(try store.load(), loaded)
        XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), Phase1Fixtures.journal)
    }
    func testManualJSONRoundTripRetainsPrecisionAndMeaning() throws {
        let manual = try input("90", "360", north: .trueNorth, convention: true).observation()
        XCTAssertEqual(try JSONDecoder().decode(Measurement.self, from: JSONEncoder().encode(manual)), manual)
    }
    func testMixedCSVHasProvenanceNorthConventionAndEmptyDiagnostics() throws {
        let manual = try input("90", "360", north: .gridNorth, convention: true).observation(notes: "=1+1")
        // Decode a sensor fixture through migration, never fabricate a sample for manual data.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FileMeasurementStore(url: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: store.legacyBackupURL)
        }
        try Phase1Fixtures.journal.write(to: url)
        let sensor = try XCTUnwrap(store.load().first { $0.source == .iPhoneSensor && $0.reference == .magneticNorth })
        let text = String(decoding: CSVExporter.data([manual, sensor]), as: UTF8.self)
        let rows = text.components(separatedBy: "\r\n")
        let fields = rows[1].components(separatedBy: "\",\"")
        XCTAssertEqual(fields.count, CSVExporter.columns.count)
        XCTAssertEqual(fields[4], "gridNorth")
        for index in [5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] {
            XCTAssertEqual(fields[index], "", "Manual diagnostic column \(index)")
        }
        XCTAssertEqual(fields[23], "'=1+1")
        XCTAssertEqual(fields[24], "manualCompass")
        XCTAssertEqual(fields[25], "conventionalDipSide")
        XCTAssertEqual(fields[26], "360")
        XCTAssertTrue(rows[2].contains("magneticNorth"))
        XCTAssertTrue(rows[2].contains("iPhoneSensor"))
        XCTAssertTrue(rows[2].contains("coreMotion"))
    }
    func testCSVPreservesDoublePrecision() {
        for value in [0.12345678901234567, 359.99999999999994, 1e-12, -0.7071067811865476] {
            XCTAssertEqual(Double(CSVExporter.engineeringNumber(value)), value)
        }
    }
}
