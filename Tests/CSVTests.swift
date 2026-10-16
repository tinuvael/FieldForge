import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class CSVTests: XCTestCase {
    func testEncodingColumnsNumericFormatAndUTC() async throws {
        let sample = MockSensorProvider.sample(dip: 45, direction: 90, timestamp: Date(timeIntervalSince1970: 0))
        let record = Measurement.process(sample, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let data = CSVExporter.data([record])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("1970-01-01T00:00:00.000Z"))
        let fields = text.components(separatedBy: "\r\n")[1].components(separatedBy: "\",\"")
        XCTAssertEqual(try XCTUnwrap(Double(fields[2])), 90, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Double(fields[3])), 45, accuracy: 1e-12)
        XCTAssertEqual(Double(fields[3]), record.orientation.dipAngle)
        XCTAssertTrue(text.contains("simulatorMock"))
        XCTAssertEqual(text.components(separatedBy: "\r\n").count, 3)
        XCTAssertEqual(CSVExporter.columns.count, 28)
    }
    func testEscapesCommasQuotesAndNewlines() async {
        XCTAssertEqual(CSVExporter.escape("a,\"b\"\r\nc"), "\"a,\"\"b\"\"\r\nc\"")
        XCTAssertEqual(CSVExporter.escape("русский"), "\"русский\"")
    }
    func testFormulaTextSanitized() async {
        for note in ["=1+1", "+1", "-1", "@SUM(A1)", "\t=1"] {
            XCTAssertTrue(CSVExporter.escape(note).hasPrefix("\"'"))
        }
    }
    func testUndefinedValuesAreEmpty() async throws {
        let m = Measurement.process(MockSensorProvider.sample(dip: 0, direction: 0, timestamp: Date(timeIntervalSince1970: 0)))
        let text = try XCTUnwrap(String(data: CSVExporter.data([m]), encoding: .utf8))
        XCTAssertTrue(text.contains("\"\",\"0.0\""))
        XCTAssertFalse(text.contains("nan"))
        XCTAssertEqual(CSVExporter.number(.infinity), "")
    }
    func testSignedDiagnosticsRemainNumbers() async throws {
        let m = Measurement.process(MockSensorProvider.sample(dip: 45, direction: 0, timestamp: Date(timeIntervalSince1970: 0)))
        let text = try XCTUnwrap(String(data: CSVExporter.data([m]), encoding: .utf8))
        let row = text.components(separatedBy: "\r\n")[1]
        let gravityZ = row.components(separatedBy: "\",\"")[18]
        XCTAssertEqual(try XCTUnwrap(Double(gravityZ)), -sqrt(0.5), accuracy: 1e-15)
        XCTAssertFalse(gravityZ.contains("'"))
    }
    func testTemporaryExport() async throws {
        let url = try CSVExporter.writeTemporaryFile([])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Data(contentsOf: url), CSVExporter.data([]))
        XCTAssertEqual(url.pathExtension, "csv")
    }
}
