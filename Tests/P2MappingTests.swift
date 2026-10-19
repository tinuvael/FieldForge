import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class P2MappingTests: XCTestCase {
    func configured() throws -> (MappingTests.MemoryStore, MappingWorkflow) {
        let store = MappingTests.MemoryStore(); var w = try MappingWorkflow(store: store)
        let p = try w.createProject(name: "P2")
        try w.requestContext(MappingContext(projectID: p))
        let h = try w.createHorizon(elevation: "+393")
        try w.requestContext(MappingContext(projectID: p, horizonID: h))
        let e = try w.createExcavation(name: "E", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: p, horizonID: h, excavationID: e))
        return (store, w)
    }
    func testSignedDecimalElevationAndNumericLabels() throws {
        for (input, value, label) in [("393",393.0,"+393 м"),("+615",615,"+615 м"),("-120",-120,"-120 м"),
                                       ("+12,125",12.125,"+12.125 м"),(" -0.25 ",-0.25,"-0.25 м"),("0",0,"+0 м"),("0.0000001",0.0000001,"+0.0000001 м")] {
            XCTAssertEqual(try ElevationInput.meters(input), value)
            XCTAssertEqual(ElevationInput.label(value), label)
        }
        for value in [1e-20, -1e20, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(try ElevationInput.meters(ElevationInput.text(value)), value)
        }
        for input in ["", "nan", "inf", "1e4", "393 м", "--3", "1,2.3", "1\n2"] { XCTAssertThrowsError(try ElevationInput.meters(input)) }
    }
    func testAutomaticElevationIsCleanAndContextSwitchRefreshesIt() throws {
        let (_, initial) = try configured(); var w = initial
        XCTAssertEqual(w.draft.z, "393"); XCTAssertEqual(w.draft.zOrigin, .horizonDefault)
        XCTAssertFalse(w.draft.hasChanges)
        let next = try w.createHorizon(elevation: "-120.5")
        try w.requestContext(MappingContext(projectID: w.context.projectID, horizonID: next))
        XCTAssertNil(w.pendingContext); XCTAssertEqual(w.context.horizonID, next)
        XCTAssertEqual(w.draft.z, "-120.5"); XCTAssertFalse(w.draft.hasChanges)
    }
    func testManualOverrideAndDeliberateClearSurviveSuggestionsAndFailedSaves() throws {
        let (store, initial) = try configured(); var w = initial
        for z in ["390,125", ""] {
            w.draft.z = z; w.draft.picket = "5"; w.draft.notes = "retain"; w.draft.observedAtOverride = Date(timeIntervalSince1970: 10)
            try w.updateHorizon(id: w.context.horizonID!, elevation: "615", datum: "unknown")
            XCTAssertEqual(w.draft.z, z); XCTAssertEqual(w.draft.zOrigin, .manualOverride)
            XCTAssertTrue(w.draft.hasChanges)
            let before = w.draft; let graph = w.journal
            store.fail = true; XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, before); XCTAssertEqual(w.journal, graph)
            store.fail = false
            let saved = try w.save(now: Date(timeIntervalSince1970: 100))
            XCTAssertEqual(saved.coordinates?.zOrigin, .manualOverride)
            XCTAssertEqual(saved.coordinates?.z, z.isEmpty ? nil : 390.125)
            XCTAssertEqual(w.draft.z, "615"); XCTAssertEqual(w.draft.zOrigin, .horizonDefault)
            XCTAssertEqual(w.draft.picket, ""); XCTAssertEqual(w.draft.x, ""); XCTAssertEqual(w.draft.notes, "")
            XCTAssertNil(w.draft.observedAtOverride); XCTAssertFalse(w.draft.hasChanges)
        }
    }
    func testLegacyNamesAreNotParsedAndSettingLevelPreservesEvidence() throws {
        let (store, initial) = try configured(); var graph = initial.journal
        graph.horizons[0].name = "Горизонт +999"; graph.horizons[0].elevationMeters = nil
        store.value = graph; var w = try MappingWorkflow(store: store)
        XCTAssertEqual(w.draft.z, ""); XCTAssertNil(w.draft.zOrigin); XCTAssertFalse(w.draft.hasChanges)
        w.draft.picket = "5"; let observation = try w.save()
        XCTAssertNil(observation.coordinates)
        let id = w.context.horizonID!
        try w.updateHorizon(id: id, elevation: "-120.25", datum: "owner-entered datum")
        XCTAssertEqual(w.journal.horizons[0].id, id); XCTAssertEqual(w.journal.horizons[0].name, "Горизонт +999")
        XCTAssertEqual(w.draft.z, "-120.25"); XCTAssertEqual(w.observations, [observation])
    }
    func testHorizonSourceSnapshotDoesNotChangeWithLaterMetadata() throws {
        let (_, initial) = try configured(); var w = initial
        w.draft.picket = "5"; let original = try w.save()
        try w.updateHorizon(id: w.context.horizonID!, elevation: "615", datum: "new datum")
        XCTAssertEqual(w.observations[0], original)
        XCTAssertEqual(original.coordinates?.zHorizonElevation, 393)
        XCTAssertEqual(original.coordinates?.zHorizonID, w.context.horizonID)
        XCTAssertEqual(w.draft.z, "615")
    }
    func testCurrentLiteralPreservesBytesIDsUnknownLocationMetadataAndReopensWithoutRewrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileMappingStore(url: dir.appendingPathComponent("mapping-v1.json"))
        let bytes = CurrentMappingFixture.data; try bytes.write(to: store.url)
        let original = try JSONDecoder().decode(MappingJournal.self, from: bytes)
        try original.validate()
        let historicalBackup = store.url.appendingPathExtension("p1-backup")
        let historicalBytes = Data("existing unrelated experimental backup".utf8)
        try historicalBytes.write(to: historicalBackup)
        let opened = try store.load()
        XCTAssertEqual(opened, original); XCTAssertEqual(opened.schemaVersion, 8)
        XCTAssertNil(opened.observations[0].coordinates?.zOrigin)
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertEqual(try FileMappingStore(url: store.url).load(), original)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["mapping-v1.json", "mapping-v1.json.p1-backup"])
        var w = try MappingWorkflow(store: store)
        XCTAssertEqual(w.draft.z, ""); w.draft.picket = "10"; _ = try w.save()
        XCTAssertEqual(w.observations[0], original.observations[0])
        XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
        XCTAssertEqual(try Data(contentsOf: historicalBackup), historicalBytes)
    }

    func testOldExperimentalSchemasRefuseWritesWithoutChangingAnyFiles() throws {
        for version in 1...7 {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = FileMappingStore(url: dir.appendingPathComponent("mapping-v1.json"))
            // A header alone must produce the schema message, not try old decoding defaults.
            let bytes = Data("{\"schemaVersion\":\(version)}".utf8)
            try bytes.write(to: store.url)
            let protected = Data("existing backup / received image / DXF bytes".utf8)
            let names = ["mapping-v1.json.previous", "mapping-v1.json.p1-backup", "image", "plan.dxf"]
            for name in names { try protected.write(to: dir.appendingPathComponent(name)) }
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("Несовместимая экспериментальная база"))
            }
            XCTAssertThrowsError(try store.save(MappingJournal()))
            XCTAssertEqual(try Data(contentsOf: store.url), bytes)
            for name in names { XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(name)), protected) }
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), Set(names + ["mapping-v1.json"]))
        }
    }

}

/// Independently authored current wire format; unknown elevation is valid, not inferred from its label.
enum CurrentMappingFixture {
    static let data = Data(#"""
    {"schemaVersion":8,"measurements":[],"revisions":[],"photos":[],"photoAttachments":[],"photoRevisions":[],"projects":[{"id":"00000000-0000-0000-0000-000000000001","name":"Old project"}],
    "horizons":[{"id":"00000000-0000-0000-0000-000000000002","projectID":"00000000-0000-0000-0000-000000000001","name":"+999 legacy","elevationDatum":"unknown"}],
    "excavations":[{"id":"00000000-0000-0000-0000-000000000003","projectID":"00000000-0000-0000-0000-000000000001","name":"E","horizonIDs":["00000000-0000-0000-0000-000000000002"]}],"plans":[],
    "selection":{"projectID":"00000000-0000-0000-0000-000000000001","horizonID":"00000000-0000-0000-0000-000000000002","excavationID":"00000000-0000-0000-0000-000000000003"},
    "observations":[{"id":"00000000-0000-0000-0000-000000000004","projectID":"00000000-0000-0000-0000-000000000001","horizonID":"00000000-0000-0000-0000-000000000002","excavationID":"00000000-0000-0000-0000-000000000003","picket":"ПК 0+005","chainageMeters":5,"chainageOriginAndDirection":"old origin / increasing direction","observedAt":123.125,"observedTimeZoneID":"UTC","observedUTCOffsetSeconds":0,"createdAt":234.25,"updatedAt":234.25,"coordinates":{"x":123456.789123456,"y":-22.875,"z":-120.125,"crs":"old local grid","axes":"old axes/datum","units":"m","source":"manual","provenance":"old survey transcription; limitations"},"measurementIDs":[],"notes":"Original evidence"}]}
    """#.utf8)
}
