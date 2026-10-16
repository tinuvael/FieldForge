import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class MigrationTests: XCTestCase {
    private func withJournal(_ bytes: Data, check: (FileMeasurementStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileMeasurementStore(url: directory.appendingPathComponent("measurements-v1.json"))
        try bytes.write(to: store.url)
        try check(store)
    }
    private func json(_ bytes: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    private func editedFixture(_ edit: (inout [[String: Any]]) -> Void) throws -> Data {
        var root = try json(Phase1Fixtures.journal)
        var records = try XCTUnwrap(root["measurements"] as? [[String: Any]])
        edit(&records); root["measurements"] = records
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
    @MainActor func testSensorValidationAllowsOnlyFloatingPointNoiseWithoutRewritingEvidence() async throws {
        let sample = MockSensorProvider.sample(dip: 45, direction: 90, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        let original = Measurement.process(sample)
        var noisy = original
        noisy.orientation.dipAngle = original.orientation.dipAngle!.nextUp
        XCTAssertTrue(noisy.isSavable)
        let encoded = try JSONEncoder().encode(noisy)
        XCTAssertEqual(try JSONDecoder().decode(Measurement.self, from: encoded), noisy)
        noisy.orientation.dipAngle! += 1e-8
        XCTAssertFalse(noisy.isSavable)
        noisy = original; noisy.orientation.normal!.x += 1e-8
        XCTAssertFalse(noisy.isSavable)
        noisy = original; noisy.orientation.status = .verticalAmbiguity
        XCTAssertFalse(noisy.isSavable)
    }
    func testLegacyMigrationPreservesEveryOriginalFieldAndBackupBytes() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            let records = try store.load()
            XCTAssertEqual(records.count, 3)
            XCTAssertEqual(records.map(\.id.uuidString), ["33333333-3333-3333-3333-333333333333",
                "22222222-2222-2222-2222-222222222222", "11111111-1111-1111-1111-111111111111"])
            let physical = try XCTUnwrap(records.last)
            XCTAssertEqual(physical.timestamp, Date(timeIntervalSince1970: 1_700_000_000.125))
            XCTAssertEqual(physical.source, .iPhoneSensor)
            XCTAssertEqual(physical.sample?.uptime, 12345.678901234)
            XCTAssertEqual(physical.sample?.magneticField.x, 30.123456789012345)
            XCTAssertEqual(physical.sample?.magneticAccuracy, .high)
            XCTAssertEqual(physical.orientation.dipDirection, 90)
            XCTAssertEqual(physical.notes, "Компас ещё не проверен; забой 3\nИсходная запись \"A\"")
            XCTAssertEqual(records.first?.reference, .unavailable)
            XCTAssertNil(records.first?.orientation.dipDirection)
            XCTAssertEqual(records[1].source, .simulatorMock)
            XCTAssertTrue(records.allSatisfy(\.isSavable))
            XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), Phase1Fixtures.journal)
            let legacy = try json(Phase1Fixtures.journal)
            let current = try json(Data(contentsOf: store.url))
            XCTAssertEqual(current["schemaVersion"] as? Int, 2)
            let oldRows = try XCTUnwrap(legacy["measurements"] as? [[String: Any]])
            let newRows = try XCTUnwrap(current["measurements"] as? [[String: Any]])
            for (old, new) in zip(oldRows, newRows) {
                for (key, value) in old {
                    XCTAssertEqual(NSDictionary(dictionary: [key: value]),
                                   NSDictionary(dictionary: [key: try XCTUnwrap(new[key])]), key)
                }
            }
            XCTAssertEqual(try FileMeasurementStore(url: store.url).load(), records)
        }
    }
    func testMigrationIsIdempotentAndDoesNotRewriteVersionTwo() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            let records = try store.load()
            let migratedBytes = try Data(contentsOf: store.url)
            XCTAssertEqual(try store.load(), records)
            XCTAssertEqual(try Data(contentsOf: store.url), migratedBytes)
            XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), Phase1Fixtures.journal)
        }
    }
    func testExistingIdenticalBackupAllowsRetry() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            try Phase1Fixtures.journal.write(to: store.legacyBackupURL)
            XCTAssertEqual(try store.load().count, 3)
        }
    }
    func testBackupConflictStopsMigrationWithoutChangingEitherFile() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            let other = Data("another backup".utf8)
            try other.write(to: store.legacyBackupURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(try Data(contentsOf: store.url), Phase1Fixtures.journal)
            XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), other)
        }
    }
    func testBackupCreationFailurePreservesLegacyFile() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            try FileManager.default.createDirectory(at: store.legacyBackupURL, withIntermediateDirectories: true)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), Phase1Fixtures.journal)
        }
    }
    func testInvalidLegacyOrientationBlocksMigrationAndWrites() throws {
        let invalid = try editedFixture { rows in
            var orientation = rows[0]["orientation"] as! [String: Any]
            orientation["dipAngle"] = 91; rows[0]["orientation"] = orientation
        }
        try withJournal(invalid) { store in
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(try Data(contentsOf: store.url), invalid)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
        }
    }
    func testMissingLegacyDiagnosticsAreNotTreatedAsManual() throws {
        let invalid = try editedFixture { $0[0].removeValue(forKey: "sample") }
        try withJournal(invalid) { store in
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), invalid)
        }
    }
    func testDuplicateLegacyIDsPreventMigration() throws {
        let invalid = try editedFixture { $0.append($0[0]) }
        try withJournal(invalid) { store in
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), invalid)
        }
    }
    func testCorruptUnknownAndMissingSchemaBlockSaveEvenBeforeExplicitLoad() throws {
        for text in ["broken", "{\"measurements\":[]}", "{\"schemaVersion\":999}",
                     "{\"schemaVersion\":2,\"measurements\":[{}]}"] {
            let bytes = Data(text.utf8)
            try withJournal(bytes) { store in
                XCTAssertThrowsError(try store.save([]))
                XCTAssertEqual(try Data(contentsOf: store.url), bytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
            }
        }
    }
    func testVersionTwoMissingProvenanceIsRejected() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            _ = try store.load()
            var root = try json(Data(contentsOf: store.url))
            var rows = root["measurements"] as! [[String: Any]]
            rows[0].removeValue(forKey: "source"); root["measurements"] = rows
            let bytes = try JSONSerialization.data(withJSONObject: root)
            try bytes.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        }
    }
    func testConcurrentFileChangeDoesNotGetOverwritten() throws {
        try withJournal(Phase1Fixtures.journal) { store in
            let records = try store.load()
            let second = FileMeasurementStore(url: store.url)
            _ = try second.load(); try second.save([])
            let changedBytes = try Data(contentsOf: store.url)
            XCTAssertThrowsError(try store.save(records))
            XCTAssertEqual(try Data(contentsOf: store.url), changedBytes)
        }
    }
    func testEmptyLegacyJournalMigrates() throws {
        let bytes = Data("{\"schemaVersion\":1,\"measurements\":[]}".utf8)
        try withJournal(bytes) { store in
            XCTAssertEqual(try store.load(), [])
            XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), bytes)
            XCTAssertEqual(try json(Data(contentsOf: store.url))["schemaVersion"] as? Int, 2)
        }
    }
}
