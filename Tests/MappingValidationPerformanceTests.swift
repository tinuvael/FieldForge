import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Adversarial coverage for the A3 indexes, using the existing deterministic A2 graph.
@MainActor final class MappingValidationPerformanceTests: XCTestCase {
    private func fixture() throws -> MappingJournal {
        var journal = try MappingStorageBenchmarkTests.fixture(40)
        let photoID = journal.photos[0].id
        let first = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
        journal.photoRevisions = [
            PhotoMetadataRevision(id: first, photoID: photoID, previousRevisionID: nil, version: 2,
                correctedAt: Date(timeIntervalSince1970: 1_700_000_100), reason: "Field annotation", metadata: PhotoMetadata(name: "Reviewed")),
            PhotoMetadataRevision(id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!, photoID: photoID,
                previousRevisionID: first, version: 3, correctedAt: Date(timeIntervalSince1970: 1_700_000_101),
                reason: "Second annotation", metadata: PhotoMetadata(name: "Reviewed again"))
        ]
        try journal.validate()
        return journal
    }

    private func changed(_ journal: MappingJournal, table: String, index: Int = 0,
                         _ edit: (inout [String: Any]) -> Void) throws -> MappingJournal {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        var records = root[table] as! [[String: Any]]
        edit(&records[index]); root[table] = records
        return try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func snapshot(_ journal: MappingJournal, _ edit: (inout [String: Any]) -> Void) throws -> MappingJournal {
        try changed(journal, table: "revisions") { revision in
            var point = revision["snapshot"] as! [String: Any]
            edit(&point); revision["snapshot"] = point
        }
    }

    private func directory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FieldForge-A3-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func rejectDamaged(_ journal: MappingJournal, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try journal.validate(), file: file, line: line)
        try directory { root in
            let url = root.appendingPathComponent("mapping.json"), backup = url.appendingPathExtension("previous")
            let bytes = try JSONEncoder().encode(journal), prior = Data("preserved backup".utf8)
            try bytes.write(to: url); try prior.write(to: backup)
            let store = FileMappingStore(url: url)
            XCTAssertThrowsError(try store.load(), file: file, line: line)
            XCTAssertThrowsError(try store.save(MappingJournal()), file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: url), bytes, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: backup), prior, file: file, line: line)
        }
    }

    func testDuplicateIDsAndBrokenBaseForeignKeysFailClosed() async throws {
        let journal = try fixture()
        let root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as! [String: Any]
        for table in ["projects", "horizons", "excavations", "plans", "observations", "measurements", "revisions", "photos", "photoAttachments", "photoRevisions"] {
            let firstID = (root[table] as! [[String: Any]])[0]["id"]!
            let damaged = try changed(journal, table: table, index: 1) { $0["id"] = firstID }
            try rejectDamaged(damaged)
        }
        for (table, key) in [("horizons", "projectID"), ("excavations", "projectID"), ("plans", "horizonID"),
                             ("observations", "projectID"), ("observations", "horizonID"), ("observations", "excavationID")] {
            try rejectDamaged(changed(journal, table: table) { $0[key] = UUID().uuidString })
        }
        try rejectDamaged(changed(journal, table: "observations") { $0["measurementIDs"] = [UUID().uuidString] })
        try rejectDamaged(changed(journal, table: "excavations") { $0["horizonIDs"] = [UUID().uuidString] })
    }

    func testHistoricalSnapshotChecksAndGeologicalOwnershipArePreserved() async throws {
        let journal = try fixture()
        // These mutate only a historical snapshot; checking originals alone would accept them.
        let invalidFields: [(String, Any)] = [
            ("id", UUID().uuidString), ("projectID", journal.projects[1].id.uuidString),
            ("horizonID", journal.horizons[1].id.uuidString), ("excavationID", journal.excavations[1].id.uuidString),
            ("measurementIDs", []), ("createdAt", 1), ("updatedAt", 1),
            ("chainageMeters", -1), ("picket", "invalid"), ("chainageOriginAndDirection", ""),
            ("observedTimeZoneID", "invalid"), ("observedUTCOffsetSeconds", 100_000)
        ]
        for (key, value) in invalidFields { try rejectDamaged(snapshot(journal) { $0[key] = value }) }
        for (key, value) in [("planID", UUID().uuidString), ("crs", "wrong frame"), ("axes", "wrong axes"),
                             ("units", "mm"), ("source", "manual"), ("provenance", "")] {
            try rejectDamaged(snapshot(journal) {
                var c = $0["coordinates"] as! [String: Any]; c[key] = value; $0["coordinates"] = c
            })
        }
        // Same-point different-kind collision, other-point ownership, and local duplicates.
        let foreign = journal.observations[10].geology!.jointSets[0].id.uuidString
        for collision in [foreign, journal.observations[0].geology!.jointSets[1].id.uuidString] {
            try rejectDamaged(snapshot(journal) {
                var g = $0["geology"] as! [String: Any], sets = g["jointSets"] as! [[String: Any]]
                sets[0]["id"] = collision; g["jointSets"] = sets; $0["geology"] = g
            })
        }
        try rejectDamaged(snapshot(journal) {
            var g = $0["geology"] as! [String: Any]
            g["tectonicStructures"] = [["id": journal.observations[0].geology!.jointSets[0].id.uuidString,
                "type": "fault", "orientation": ["dipAngleText": "", "dipDirectionText": "", "reference": "unknown", "usesConventionalDipSide": false],
                "position": "", "description": ""]]
            $0["geology"] = g
        })
        for alteration in ["result", "method", "input", "rmr"] {
            try rejectDamaged(snapshot(journal) {
                var ratings = $0["ratings"] as! [String: Any], q = ratings["bartonQ"] as! [String: Any]
                switch alteration {
                case "result":
                    var evaluation = q["evaluation"] as! [String: Any], result = evaluation["result"] as! [String: Any]
                    result["value"] = 999; evaluation["result"] = result; q["evaluation"] = evaluation
                case "method": q["method"] = "unverified-method"
                case "input":
                    var input = q["input"] as! [String: Any]; input["rqd"] = "101"; q["input"] = input
                default:
                    var rmr = ratings["rmr89"] as! [String: Any]; rmr["method"] = "unverified-method"; ratings["rmr89"] = rmr
                }
                ratings["bartonQ"] = q; $0["ratings"] = ratings
            })
        }
        try rejectDamaged(snapshot(journal) {
            var g = $0["geology"] as! [String: Any], sets = g["jointSets"] as! [[String: Any]]
            sets[0]["measurementIDs"] = [journal.measurements[2].id.uuidString]
            g["jointSets"] = sets; $0["geology"] = g
        })
        for key in ["revision", "interpretedAt"] {
            try rejectDamaged(snapshot(journal) {
                var g = $0["geology"] as! [String: Any], sets = g["jointSets"] as! [[String: Any]]
                sets[0]["revision"] = 2
                sets[0]["notes"] = "Changed interpretation"
                sets[0][key] = 99
                g["jointSets"] = sets; $0["geology"] = g
            })
        }
    }

    func testBrokenReorderedDivergentObservationAndPhotoChainsAreRejected() async throws {
        let journal = try fixture()
        for table in ["revisions", "photoRevisions"] {
            for (key, value) in [("version", 4 as Any), ("previousRevisionID", UUID().uuidString), ("reason", " ")] {
                try rejectDamaged(changed(journal, table: table) { $0[key] = value })
            }
            try rejectDamaged(changed(journal, table: table) { $0[table == "revisions" ? "observationID" : "photoID"] = UUID().uuidString })
        }
        var damaged = journal; damaged.revisions.swapAt(0, 1); try rejectDamaged(damaged)
        damaged = journal; damaged.photoRevisions.swapAt(0, 1); try rejectDamaged(damaged)
        damaged = journal
        let branch = journal.revisions[0]
        damaged.revisions.append(MappingObservationRevision(id: UUID(), observationID: branch.observationID, version: branch.version,
            previousRevisionID: branch.previousRevisionID, correctedAt: branch.correctedAt, author: nil, reason: "Divergent branch", snapshot: branch.snapshot))
        try rejectDamaged(damaged)
    }

    func testInvalidPhotoAttachmentAndPlanProvenanceAreRejected() async throws {
        let journal = try fixture()
        try rejectDamaged(changed(journal, table: "photos") { $0["attachmentID"] = UUID().uuidString })
        try rejectDamaged(changed(journal, table: "photoAttachments") { $0["sha256"] = "invalid" })
        try rejectDamaged(changed(journal, table: "photoAttachments") { $0["id"] = journal.plans[0].attachmentID.uuidString })
        for (key, value) in [("pointRevisionID", UUID().uuidString as Any), ("pointID", UUID().uuidString),
                             ("pointVersion", 99), ("projectID", journal.projects[1].id.uuidString),
                             ("locationBasis", "unknownBeforeFirstSave")] {
            try rejectDamaged(changed(journal, table: "photos") {
                var c = $0["context"] as! [String: Any]; c[key] = value; $0["context"] = c
            })
        }
        try rejectDamaged(changed(journal, table: "plans") {
            var f = $0["file"] as! [String: Any]; f["unitDeclaration"] = "unknown"; $0["file"] = f
        })
        try rejectDamaged(snapshot(journal) {
            var c = $0["coordinates"] as! [String: Any]; c["zOrigin"] = "planGeometry"; c["z"] = 100; $0["coordinates"] = c
        })
    }

    func testSameUUIDChangedOrRemovedEvidenceIsRejectedWithoutTouchingFiles() async throws {
        let journal = try fixture()
        try directory { root in
            let url = root.appendingPathComponent("mapping.json"), store = FileMappingStore(url: url)
            try store.save(journal); try store.save(journal)
            let bytes = try Data(contentsOf: url), backup = try Data(contentsOf: store.backupURL)
            for (table, key, value) in [("observations", "notes", "Tampered"), ("measurements", "notes", "Tampered"),
                                        ("revisions", "reason", "Tampered"), ("photos", "captureTimeProvenance", "Tampered"),
                                        ("photoAttachments", "representation", "Tampered"), ("photoRevisions", "reason", "Tampered")] {
                let candidate = try changed(journal, table: table) { $0[key] = value }
                try candidate.validate() // Semantically valid; only full-value retention must reject.
                XCTAssertFalse(candidate.preservesEvidence(from: journal), table)
                XCTAssertThrowsError(try store.save(candidate), table)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                XCTAssertEqual(try Data(contentsOf: store.backupURL), backup)
            }
            var removed = journal; removed.photoRevisions.removeLast()
            try removed.validate(); XCTAssertThrowsError(try store.save(removed))
            // Reordering unrelated records was allowed by the old contains-based check.
            var reordered = journal
            reordered.observations.reverse(); reordered.measurements.reverse(); reordered.photos.reverse(); reordered.photoAttachments.reverse()
            reordered.revisions = Array(journal.revisions[2...]) + Array(journal.revisions[..<2])
            try store.save(reordered)
            XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
            XCTAssertEqual(try FileMappingStore(url: url).load(), reordered)
            // Immutable DXF identity is still protected separately from evidence indexes.
            let planChanged = try changed(reordered, table: "plans") {
                var f = $0["file"] as! [String: Any]; f["sha256"] = String(repeating: "c", count: 64); $0["file"] = f
            }
            try planChanged.validate(); XCTAssertThrowsError(try store.save(planChanged))
        }
    }

    func testSchema8RoundTripEffectiveResolutionExternalChangesAndSaveFailure() async throws {
        let journal = try fixture()
        for original in journal.observations {
            let history = journal.revisions.filter { $0.observationID == original.id }
            XCTAssertEqual(journal.history(for: original.id), history)
            XCTAssertEqual(journal.effectiveObservation(id: original.id), history.last?.snapshot ?? original)
        }
        XCTAssertNil(journal.effectiveObservation(id: UUID()))
        XCTAssertEqual(journal.effectiveObservations, journal.observations.map { point in
            journal.revisions.last(where: { $0.observationID == point.id })?.snapshot ?? point
        })
        try directory { root in
            let url = root.appendingPathComponent("mapping.json")
            // Existing noncanonical whitespace/order bytes must be the exact backup.
            let bytes = try JSONEncoder().encode(journal); try bytes.write(to: url)
            let store = FileMappingStore(url: url)
            XCTAssertEqual(try store.load(), journal); try store.save(journal)
            XCTAssertEqual(try Data(contentsOf: store.backupURL), bytes)
            XCTAssertEqual(try FileMappingStore(url: url).load(), journal)
            let saved = try Data(contentsOf: url), backup = try Data(contentsOf: store.backupURL)
            try bytes.write(to: url) // Externally rewritten, semantically identical schema 8.
            XCTAssertThrowsError(try store.save(journal)) {
                guard case StorageError.changedFile = $0 else { return XCTFail("Expected external-change rejection, got \($0)") }
            }
            XCTAssertEqual(try Data(contentsOf: store.backupURL), backup)
            try saved.write(to: url)
            try FileManager.default.removeItem(at: store.backupURL)
            try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: false)
            XCTAssertThrowsError(try store.save(journal))
            XCTAssertEqual(try Data(contentsOf: url), saved)
            try FileManager.default.removeItem(at: store.backupURL)
            try store.save(journal) // Failed save did not publish a new baseline; retry works.
            XCTAssertEqual(try Data(contentsOf: store.backupURL), saved)
            XCTAssertEqual(try FileMappingStore(url: store.backupURL).load(), journal)
        }
    }
}
