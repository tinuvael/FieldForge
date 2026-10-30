import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class MappingExchangeFileReadTests: XCTestCase {
    func testScopesBalancedOnSuccessFailureAndCoordinationCancellationWithoutChangingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExchangeRead-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("input.xlsx"), original = Data("unchanged synthetic input".utf8)
        try original.write(to: url)
        var active = 0, starts = 0, stops = 0
        let start: (URL) -> Bool = { _ in active += 1; starts += 1; return true }
        let stop: (URL) -> Void = { _ in active -= 1; stops += 1 }
        XCTAssertEqual(try ExchangeCoordinatedRead().data(url: url, maximum: 100, startAccess: start, stopAccess: stop), original)
        XCTAssertEqual(active, 0)
        XCTAssertThrowsError(try ExchangeCoordinatedRead().data(url: url, maximum: 1, startAccess: start, stopAccess: stop))
        XCTAssertEqual(active, 0)
        let cancelled = ExchangeCoordinatedRead()
        XCTAssertThrowsError(try cancelled.data(url: url, maximum: 100, startAccess: { url in cancelled.cancel(); return start(url) }, stopAccess: stop))
        XCTAssertEqual(active, 0); XCTAssertEqual(starts, 3); XCTAssertEqual(stops, 3)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.xlsx"])
    }
    func testNoUnbalancedStopWhenSecurityScopeWasNotAcquired() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExchangeRead-\(UUID()).xlsx")
        try Data([1, 2, 3]).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try ExchangeCoordinatedRead().data(url: url, maximum: 10, startAccess: { _ in false }, stopAccess: { _ in XCTFail("No acquired scope to release") })
        XCTAssertEqual(bytes, Data([1, 2, 3]))
    }
    func testProductionReadOnlyFilePipelineAndCancellation() async throws {
        var journal = MappingJournal()
        let project = MappingProject(id: UUID(), name: "Synthetic Files")
        journal.projects = [project]
        let snapshot = MappingCommittedSnapshot(journal), date = Date(timeIntervalSinceReferenceDate: 721234567)
        let export = try MappingExchangeExport.prepare(committed: snapshot, selection: .init(projectID: project.id, firstDay: date, lastDay: date, timeZoneID: "UTC"))
        let files = try export.write(); defer { files.cleanup() }
        let url = files.urls[0], before = try Data(contentsOf: url)
        let parsed = Task.detached { try await MappingExchangeFileRead.prepare(url: url, committed: snapshot) }
        let preview = try await parsed.value
        XCTAssertEqual(preview.projectName, "Synthetic Files")
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MappingExchangeFileRead.prepare(url: url, committed: snapshot)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled read") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.directory.path), [url.lastPathComponent])
    }
}
