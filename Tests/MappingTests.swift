import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class MappingTests: XCTestCase {
    final class MemoryStore: MappingStore {
        var value = MappingJournal()
        var fail = false
        func load() throws -> MappingJournal { value }
        func save(_ journal: MappingJournal) throws {
            if fail { throw StorageError.writesBlocked }
            try journal.validate(); value = journal
        }
    }
    private func configured(_ store: any MappingStore) throws -> MappingWorkflow {
        var w = try MappingWorkflow(store: store)
        let p = try w.createProject(name: "Рудник A")
        try w.requestContext(MappingContext(projectID: p))
        let h = try w.createHorizon(elevation: "200")
        try w.requestContext(MappingContext(projectID: p, horizonID: h))
        let e = try w.createExcavation(name: "Штрек 1", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: p, horizonID: h, excavationID: e))
        return w
    }
    private func withFile(_ check: (FileMappingStore) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try check(FileMappingStore(url: dir.appendingPathComponent("mapping-v1.json")))
    }
    func testTwoIndependentProjectsAndNoLeakage() throws {
        let store = MemoryStore(); var w = try configured(store)
        let original = w.context
        w.draft.picket = "ПК 0+005"; let first = try w.save()
        let other = try w.createProject(name: "Другой рудник")
        try w.requestContext(MappingContext(projectID: other))
        XCTAssertTrue(w.observations.isEmpty); XCTAssertTrue(w.horizons.isEmpty); XCTAssertTrue(w.excavations.isEmpty)
        XCTAssertNil(w.context.horizonID)
        let h = try w.createHorizon(elevation: "-120")
        try w.requestContext(MappingContext(projectID: other, horizonID: h))
        let e = try w.createExcavation(name: "Штрек 1", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: other, horizonID: h, excavationID: e))
        w.draft.picket = "10"; _ = try w.save()
        XCTAssertEqual(w.observations.count, 1); XCTAssertNotEqual(w.observations[0].projectID, first.projectID)
        try w.requestContext(original); XCTAssertEqual(w.observations, [first])
    }
    func testSuccessivePicketsKeepContextResetAllDraftFieldsAndPreserveHistoricalTime() throws {
        var w = try configured(MemoryStore()); let context = w.context
        let historical = Date(timeIntervalSince1970: 946684800.123)
        let now = Date(timeIntervalSince1970: 1800000000)
        w.draft.picket = "ПК 0+005"; w.draft.observedAtOverride = historical
        w.draft.timeZoneID = "Asia/Almaty"; w.draft.x = "123,456789"; w.draft.z = "-5"
        w.draft.crs = "Локальная СК"; w.draft.axes = "X север, Y восток, Z вверх; датум неизвестен"
        w.draft.coordinateProvenance = "Переписано с плана, приблизительно"; w.draft.notes = "Первое"
        w.draft.chainageOriginAndDirection = "От устья к забою"
        let first = try w.save(now: now)
        XCTAssertEqual(first.observedAt, historical); XCTAssertEqual(first.createdAt, now); XCTAssertEqual(first.updatedAt, now)
        XCTAssertEqual(first.chainageMeters, 5); XCTAssertEqual(first.coordinates?.x, 123.456789)
        XCTAssertNil(first.coordinates?.y); XCTAssertEqual(first.coordinates?.z, -5)
        XCTAssertEqual(first.observedTimeZoneID, "Asia/Almaty")
        XCTAssertEqual(w.draft.z, "200"); XCTAssertFalse(w.draft.hasChanges); XCTAssertEqual(w.context, context)
        w.draft.picket = "ПК 0+010"
        let second = try w.save(now: now.addingTimeInterval(60))
        XCTAssertEqual(second.chainageMeters, 10); XCTAssertEqual(second.coordinates?.z, 200); XCTAssertEqual(second.coordinates?.zOrigin, .horizonDefault)
        XCTAssertEqual(second.observedAt, now.addingTimeInterval(60)); XCTAssertEqual(w.context, context)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(w.observations.count, 2)
        XCTAssertEqual(w.observations[0].observedAt, historical)
    }
    func testFailedValidationAndPersistencePreserveEntireDraftAndContext() throws {
        let store = MemoryStore(); var w = try configured(store); let context = w.context
        w.draft.picket = "1+05"; w.draft.notes = "Не терять"; let invalid = w.draft
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, invalid); XCTAssertEqual(w.context, context)
        w.draft.picket = "5"; let valid = w.draft; store.fail = true
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, valid); XCTAssertEqual(w.context, context)
        XCTAssertTrue(w.observations.isEmpty)
        store.fail = false; _ = try w.save(); XCTAssertFalse(w.draft.hasChanges)
    }
    func testDraftSwitchCancelConfirmAndFailedDiscardPersistence() throws {
        let store = MemoryStore(); var w = try configured(store); let original = w.context
        let p = try w.createProject(name: "B"); let next = MappingContext(projectID: p)
        w.draft.notes = "Черновик"; w.draft.observedAtOverride = Date(timeIntervalSince1970: 1)
        let draft = w.draft
        try w.requestContext(next); XCTAssertEqual(w.context, original); XCTAssertEqual(w.pendingContext, next)
        w.cancelContextChange(); XCTAssertEqual(w.draft, draft); XCTAssertNil(w.pendingContext)
        try w.requestContext(next); store.fail = true
        XCTAssertThrowsError(try w.confirmDiscard()); XCTAssertEqual(w.draft, draft); XCTAssertEqual(w.context, original)
        store.fail = false; try w.confirmDiscard()
        XCTAssertEqual(w.context, next); XCTAssertFalse(w.draft.hasChanges); XCTAssertNil(w.pendingContext)
    }
    func testEveryContextLevelGuardsDirtyDraftIncludingDateOnly() throws {
        var w = try configured(MemoryStore()); let original = w.context
        let h = try w.createHorizon(elevation: "615,5")
        let e = try w.createExcavation(name: "E2", horizonIDs: [original.horizonID!])
        for next in [MappingContext(projectID: original.projectID),
                     MappingContext(projectID: original.projectID, horizonID: h),
                     MappingContext(projectID: original.projectID, horizonID: original.horizonID, excavationID: e)] {
            w.draft.observedAtOverride = Date(timeIntervalSince1970: 2)
            try w.requestContext(next); XCTAssertEqual(w.context, original); XCTAssertEqual(w.pendingContext, next)
            w.cancelContextChange(); XCTAssertTrue(w.draft.hasChanges)
        }
    }
    func testMultipleHorizonsOneExcavationAndRename() throws {
        var w = try configured(MemoryStore()); let original = w.context
        let h = try w.createHorizon(elevation: "615,5")
        try w.updateExcavation(id: original.excavationID!, name: "Общая выработка", horizonIDs: [original.horizonID!, h])
        try w.updateProject(id: original.projectID!, name: "Новое название")
        try w.updateHorizon(id: h, elevation: "-100,5", datum: "Неизвестно")
        try w.requestContext(MappingContext(projectID: original.projectID, horizonID: h))
        XCTAssertEqual(w.excavations.map(\.id), [original.excavationID!])
        XCTAssertEqual(w.journal.projects[0].name, "Новое название")
        XCTAssertEqual(w.horizons.last?.elevationMeters, -100.5)
    }
    func testRelaunchRoundTripAndPreviousSnapshotBackup() throws {
        try withFile { store in
            var w = try configured(store); let context = w.context
            w.draft.picket = "5"; let a = try w.save()
            let bytes = try Data(contentsOf: store.url)
            w.draft.picket = "10"; let b = try w.save()
            XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
            let restored = try MappingWorkflow(store: FileMappingStore(url: store.url))
            XCTAssertEqual(restored.context, context); XCTAssertEqual(restored.observations, [a,b])
        }
    }
    func testCorruptAndUnknownVersionBlockWritesPreserveBytes() throws {
        for text in ["broken", "{}", "{\"schemaVersion\":99,\"projects\":[]}"] {
            try withFile { store in
                let data = Data(text.utf8); try data.write(to: store.url)
                XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(MappingJournal()))
                XCTAssertEqual(try Data(contentsOf: store.url), data)
            }
        }
    }
    func testRelationshipAndDuplicateValidation() throws {
        var w = try configured(MemoryStore()); w.draft.picket = "5"; _ = try w.save()
        var graph = w.journal; graph.projects.append(graph.projects[0]); XCTAssertThrowsError(try graph.validate())
        graph = w.journal; graph.horizons.removeAll(); XCTAssertThrowsError(try graph.validate())
        graph = w.journal; graph.excavations.removeAll(); XCTAssertThrowsError(try graph.validate())
        graph = w.journal; graph.observations.append(graph.observations[0]); XCTAssertThrowsError(try graph.validate())
        let other = try w.createProject(name: "B")
        XCTAssertThrowsError(try w.requestContext(MappingContext(projectID: other, horizonID: w.context.horizonID)))
    }
    func testFileChangeAndBackupFailurePreserveDraftAndOriginal() throws {
        try withFile { store in
            var w = try configured(store); w.draft.picket = "5"; let draft = w.draft
            let bytes = try Data(contentsOf: store.url)
            try FileManager.default.removeItem(at: store.backupURL)
            try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: false)
            XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft)
            XCTAssertEqual(try Data(contentsOf: store.url), bytes)
            try FileManager.default.removeItem(at: store.backupURL)
            try Data("external".utf8).write(to: store.url)
            XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft)
            XCTAssertEqual(try Data(contentsOf: store.url), Data("external".utf8))
        }
    }
    func testOriginalObservationsCannotBeRemovedOrChanged() throws {
        try withFile { store in
            var w = try configured(store); w.draft.picket = "5"; _ = try w.save()
            var next = w.journal; next.observations = []
            XCTAssertThrowsError(try store.save(next)); XCTAssertEqual(try store.load(), w.journal)
        }
    }
    func testLegacyPhaseOneAndTwoBytesUnchangedByMapping() throws {
        try withFile { store in
            let legacy = FileMeasurementStore(url: store.url.deletingLastPathComponent().appendingPathComponent("measurements-v1.json"))
            try Phase1Fixtures.journal.write(to: legacy.url)
            var w = try configured(store); w.draft.picket = "5"; _ = try w.save()
            XCTAssertEqual(try Data(contentsOf: legacy.url), Phase1Fixtures.journal)
            let measurements = try legacy.load()
            let phaseTwo = try Data(contentsOf: legacy.url); let backup = try Data(contentsOf: legacy.legacyBackupURL)
            w.draft.picket = "10"; _ = try w.save()
            XCTAssertEqual(try Data(contentsOf: legacy.url), phaseTwo)
            XCTAssertEqual(try Data(contentsOf: legacy.legacyBackupURL), backup)
            XCTAssertEqual(try legacy.load(), measurements)
        }
    }
    func testIncompleteDraftIsNeverSavedAndInvalidCoordinateRetainsFields() throws {
        let store = MemoryStore(); var w = try MappingWorkflow(store: store)
        w.draft.picket = "5"; let draft = w.draft
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft)
        XCTAssertTrue(store.value.observations.isEmpty)
        w = try configured(store); w.draft.picket = "5"; w.draft.z = "nan"
        let invalid = w.draft
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, invalid)
        XCTAssertTrue(store.value.observations.isEmpty)
    }
    func testCorruptGraphLoadRejectsInvalidForeignKeysAndExtremeTimezoneOffset() throws {
        try withFile { store in
            var w = try configured(store); w.draft.picket = "5"; _ = try w.save()
            let data = try Data(contentsOf: store.url)
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var observations = try XCTUnwrap(root["observations"] as? [[String: Any]])
            observations[0]["observedUTCOffsetSeconds"] = Int.min
            root["observations"] = observations
            let invalid = try JSONSerialization.data(withJSONObject: root)
            try invalid.write(to: store.url)
            let reload = FileMappingStore(url: store.url)
            XCTAssertThrowsError(try reload.load()); XCTAssertThrowsError(try reload.save(w.journal))
            XCTAssertEqual(try Data(contentsOf: store.url), invalid)
            root["observations"] = []; root["horizons"] = []
            try JSONSerialization.data(withJSONObject: root).write(to: store.url)
            XCTAssertThrowsError(try FileMappingStore(url: store.url).load())
        }
    }
    func testPicketConventionAndCoordinateValidation() throws {
        for (text, expected) in [("ПК 0+005",5.0),("0+010",10),("ПК 1+005,5",1005.5),("5.125",5.125),("0",0)] {
            XCTAssertEqual(try PicketInput.meters(text), expected)
        }
        for text in ["1+05", "-5", "nan", "1e4", "ПК 1+1000", "", "5 м"] { XCTAssertThrowsError(try PicketInput.meters(text)) }
        var w = try configured(MemoryStore()); w.draft.picket = "5"; w.draft.x = "1"
        let record = try w.save(); XCTAssertEqual(record.coordinates?.z, 200)
        XCTAssertEqual(record.coordinates?.crs, "unknown"); XCTAssertEqual(record.coordinates?.zOrigin, .horizonDefault)
    }
}
