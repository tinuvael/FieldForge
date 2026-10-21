import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class MappingCSVExportTests: XCTestCase {
    func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func selection(_ point: MappingObservation, _ first: String, _ last: String? = nil, zone: String = "UTC") -> MappingExportSelection {
        MappingExportSelection(projectID: point.projectID, firstDay: instant(first), lastDay: instant(last ?? first), timeZoneID: zone)
    }
    func rows(_ export: MappingCSVExport, _ name: String) throws -> [[String: String]] {
        let table = try XCTUnwrap(export.tables.first { $0.name == name })
        let parsed = parse(table.data)
        XCTAssertEqual(parsed.first, table.columns)
        XCTAssertEqual(parsed.count, table.rows.count + 1)
        return parsed.dropFirst().map { row in
            XCTAssertEqual(row.count, table.columns.count)
            return Dictionary(uniqueKeysWithValues: zip(table.columns, row))
        }
    }
    /// Independent CSV reader exercises quoted commas, CRLF and embedded newlines.
    func parse(_ data: Data) -> [[String]] {
        let chars = Array(String(decoding: data, as: UTF8.self).dropFirst())
        var output: [[String]] = [], row: [String] = [], field = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append(c); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\r\n" || c == "\n") && !quoted { row.append(field); output.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        return output
    }
    func testTwoProjectsTwoPeriodsAndOptionalScopes() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let day = instant("2023-11-14T12:00:00Z")
        w.draft.picket = "15"; w.draft.observedAtOverride = instant("2023-11-15T12:00:00Z")
        let later = try w.save()
        let project = try w.createProject(name: "Другой проект")
        try w.requestContext(MappingContext(projectID: project))
        let h = try w.createHorizon(elevation: "100")
        try w.requestContext(MappingContext(projectID: project, horizonID: h))
        let e = try w.createExcavation(name: "Другая выработка", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: project, horizonID: h, excavationID: e))
        w.draft.picket = "25"; w.draft.observedAtOverride = day; let other = try w.save()
        let a = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        let b = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-15T12:00:00Z"))
        let c = try MappingCSVExport.prepare(journal: w.journal, selection: selection(other, "2023-11-14T12:00:00Z"))
        XCTAssertEqual(try rows(a, "points").map { $0["point_id"] }, [p.id.uuidString])
        XCTAssertEqual(try rows(b, "points").map { $0["point_id"] }, [later.id.uuidString])
        XCTAssertEqual(try rows(c, "points").map { $0["point_id"] }, [other.id.uuidString])
        XCTAssertEqual(try rows(a, "projects").map { $0["project_id"] }, [p.projectID.uuidString])
        var scoped = selection(p, "2023-11-14T12:00:00Z"); scoped.horizonID = p.horizonID; scoped.excavationID = p.excavationID
        XCTAssertEqual(try MappingCSVExport.prepare(journal: w.journal, selection: scoped).pointCount, 1)
        scoped.horizonID = h
        XCTAssertThrowsError(try MappingCSVExport.prepare(journal: w.journal, selection: scoped))
    }
    func testCalendarDSTOffsetChangesEmptyInvalidAndExactBoundaries() async throws {
        let (_, initial, p) = try P33RevisionTests().seed()
        for (date, zone, hours) in [("2024-03-10T12:00:00Z", "America/New_York", 23.0), ("2024-11-03T12:00:00Z", "America/New_York", 25.0), ("2024-02-29T12:00:00Z", "Asia/Almaty", 25.0)] {
            let s = selection(p, date, zone: zone), b = try s.bounds()
            XCTAssertEqual(b.end.timeIntervalSince(b.start), hours * 3600)
            var w = initial
            var correction = try w.correction(for: p.id); correction.reason = "Boundary"; correction.fields.timeZoneID = zone
            for (instant, expected) in [(b.start.addingTimeInterval(-0.001), 0), (b.start, 1), (b.end.addingTimeInterval(-0.001), 1), (b.end, 0)] {
                correction = try w.correction(for: p.id); correction.reason = "Boundary"; correction.fields.timeZoneID = zone
                correction.fields.observedAtOverride = instant; _ = try w.saveCorrection(correction)
                XCTAssertEqual(try MappingCSVExport.prepare(journal: w.journal, selection: s).pointCount, expected)
            }
        }
        XCTAssertEqual(try MappingCSVExport.prepare(journal: initial.journal, selection: selection(p, "2000-01-01T12:00:00Z")).pointCount, 0)
        XCTAssertThrowsError(try selection(p, "2024-03-11T12:00:00Z", "2024-03-10T12:00:00Z").bounds())
        XCTAssertThrowsError(try selection(p, "2024-03-10T12:00:00Z", zone: "invalid").bounds())
    }
    func testCorrectionSelectionEffectiveIdentityEvidenceAndStoredRatings() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        var correction = try w.correction(for: p.id); correction.reason = "Field date, picket and location"
        correction.fields.observedAtOverride = instant("2023-11-15T12:00:00Z"); correction.fields.picket = "25,125"
        correction.fields.x = "123.12345678912345"; correction.fields.y = "-42"
        let r = try w.saveCorrection(correction)
        let old = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        XCTAssertEqual(old.pointCount, 0)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-15T12:00:00Z"))
        let point = try XCTUnwrap(rows(export, "points").first)
        XCTAssertEqual(point["revision_id"], r.id.uuidString); XCTAssertEqual(point["version"], "2")
        XCTAssertEqual(point["interval_start_m"].flatMap(Double.init), p.geology?.start?.meters)
        XCTAssertEqual(point["interval_end_m"].flatMap(Double.init), p.geology?.end?.meters)
        XCTAssertEqual(point["position"], "roof"); XCTAssertEqual(point["observed_zone"], "Asia/Almaty")
        XCTAssertEqual(point["observed_offset_seconds"], String(r.snapshot.observedUTCOffsetSeconds))
        XCTAssertEqual(point["picket"], "25,125"); XCTAssertEqual(point["x"].flatMap(Double.init), r.snapshot.coordinates?.x)
        XCTAssertEqual(point["observed_at_reference_seconds"].flatMap(Double.init), r.snapshot.observedAt.timeIntervalSinceReferenceDate)
        XCTAssertEqual(try rows(export, "measurements").count, 2) // originals from previous field day
        let measurementIDs = Set(try rows(export, "measurements").compactMap { $0["measurement_id"] })
        let setIDs = Set(try rows(export, "joint_sets").compactMap { $0["joint_set_id"] })
        for link in try rows(export, "interpretation_evidence") {
            XCTAssertTrue(measurementIDs.contains(link["measurement_id"]!)); XCTAssertTrue(setIDs.contains(link["joint_set_id"]!))
        }
        let ratings = try rows(export, "assessments")
        XCTAssertEqual(ratings.count, 2)
        XCTAssertEqual(ratings.first?["stored_q"].flatMap(Double.init), p.ratings?.bartonQ?.evaluation.result?.value)
        XCTAssertEqual(ratings.last?["stored_q"], ""); XCTAssertEqual(ratings.last?["kind"], "RMR89-input-only")
        XCTAssertEqual(w.journal.observations, [p]); XCTAssertEqual(w.journal.measurements, initial.journal.measurements)
    }
    func testIncompletePointRatingsAndPartialFaultExportWithoutCoordinatesOrMeasurements() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        w.draft.picket = "5"; w.draft.z = ""; w.draft.observedAtOverride = instant("2024-01-01T00:00:00Z")
        w.draft.bartonQ.missingReason = "Не завершено"; w.draft.rmr89.source = "Полевой журнал"
        var fault = TectonicStructureDraft(); fault.orientation.dipAngleText = "45,123456789"; w.draft.tectonicStructures = [fault]
        let p = try w.save()
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2024-01-01T12:00:00Z"))
        XCTAssertEqual(export.pointCount, 1); XCTAssertEqual(try rows(export, "measurements").count, 0)
        XCTAssertEqual(try rows(export, "points").first?["x"], ""); XCTAssertEqual(try rows(export, "points").first?["z_m"], "")
        XCTAssertEqual(try rows(export, "tectonic_structures").first?["dip_direction_deg"], "")
        XCTAssertEqual(try rows(export, "assessments").count, 2)
        XCTAssertTrue(try rows(export, "assessments").allSatisfy { $0["stored_q"] == "" })
    }
    func testPhotoHistoricalContextEffectiveMetadataAndUnknownDraftCaptureLocation() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let context = try w.journal.photoContext(for: p.id)
        for basis in [PhotoLocationBasis.pointRevision, .unknownBeforeFirstSave] {
            var c = context; c.locationBasis = basis
            let attachment = PhotoAttachment(id: UUID(), originalFilename: "фото.jpg", sha256: String(repeating: "a", count: 64), byteCount: 500,
                format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 1, orientation: 1, representation: "received bytes unchanged")
            let photo = PhotoObservation(id: UUID(), attachmentID: attachment.id, context: c, source: .files,
                importedAt: instant("2025-01-01T00:00:00Z"), capturedAt: basis == .pointRevision ? instant("2020-01-01T07:00:00Z") : nil, captureTimeText: "2020:01:01 12:00:00",
                captureTimeProvenance: "EXIF wall time; offset unknown", metadata: PhotoMetadata(name: "Исходное"))
            try w.registerPhoto(PhotoImportOperation(version: 2, photo: photo, attachment: attachment))
            try w.correctPhoto(photo.id, baselineRevisionID: nil, metadata: PhotoMetadata(name: "Актуальное", description: "Описание"), reason: "Register correction")
        }
        var correction = try w.correction(for: p.id); correction.reason = "Move current point"; correction.fields.picket = "35"
        correction.fields.x = "999"; correction.fields.y = "123"
        _ = try w.saveCorrection(correction)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        let photos = try rows(export, "photos"), contexts = try rows(export, "photo_point_contexts")
        XCTAssertEqual(photos.count, 2); XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?["picket"], p.picket); XCTAssertEqual(contexts.first?["x"], "")
        XCTAssertEqual(try rows(export, "points").first?["x"], "999.0")
        XCTAssertTrue(photos.allSatisfy { $0["name"] == "Актуальное" && $0["imported_at_utc"] == "2025-01-01T00:00:00.000Z" })
        XCTAssertEqual(Set(photos.compactMap { $0["capture_location_basis"] }), ["pointRevision", "unknownBeforeFirstSave"])
        XCTAssertEqual(photos.first { $0["capture_location_basis"] == "pointRevision" }?["captured_at_utc"], "2020-01-01T07:00:00.000Z")
        XCTAssertEqual(photos.first { $0["capture_location_basis"] == "unknownBeforeFirstSave" }?["captured_at_utc"], "")
        XCTAssertEqual(try rows(export, "photo_attachments").count, 2) // no originals exist on disk
        XCTAssertTrue(photos.allSatisfy { $0["original_integrity"] == "notChecked; originalsNotIncluded" })
    }
    func testRussianEscapingFormulaNullAndRoundTripPrecision() async throws {
        let number = -123.12345678912345
        let texts = ["Русский, \"кавычки\"\r\nвторая строка", "=1+1", " \t@SUM(A1)", "\u{0001}-1", "+1", "-1", "'literal", "\ttext", "45,1234567891234567", ""]
        let table = MappingCSVExport.Table(name: "fixture", columns: ["text", "number", "null"], rows: texts.map { [.text($0), .number(number), .number(nil)] })
        XCTAssertEqual(Array(table.data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let parsed = parse(table.data)
        XCTAssertEqual(parsed.count, texts.count + 1)
        XCTAssertEqual(parsed[1][0], texts[0]); XCTAssertEqual(parsed[9][0], texts[8])
        for row in parsed.dropFirst() { XCTAssertEqual(row.count, 3); XCTAssertEqual(Double(row[1]), number); XCTAssertEqual(row[2], "") }
        for i in 1...7 { XCTAssertEqual(parsed[i + 1][0], "'" + texts[i]) }
    }
    func testPreviewFilesAndManifestRemainFrozenAfterJournalAndContextChange() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        var correction = try w.correction(for: p.id); correction.reason = "Later edit"; correction.fields.observedAtOverride = instant("2025-01-01T00:00:00Z")
        _ = try w.saveCorrection(correction); try w.requestContext(MappingContext())
        let files = try MappingExportFiles.write(export, format: .csv); defer { files.cleanup() }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: files.urls.last!)) as? [String: Any])
        let counts = try XCTUnwrap(manifest["tables"] as? [String: [String: Any]])
        for table in export.tables {
            let actual = try Data(contentsOf: files.directory.appendingPathComponent(table.name + ".csv"))
            XCTAssertEqual(actual, table.data); XCTAssertEqual(parse(actual).count - 1, table.rows.count)
            XCTAssertEqual(counts[table.name + ".csv"]?["rows"] as? Int, table.rows.count)
        }
        XCTAssertEqual(export.pointCount, 1); XCTAssertEqual(manifest["project_id"] as? String, p.projectID.uuidString)
        XCTAssertEqual(try rows(export, "points").first?["picket"], p.picket)
    }
    func testCancellationAndPartialWriteFailurePreserveJournalOriginalsAndActiveDraft() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        w.draft.picket = "Unfinished draft"; w.draft.photoSessions.insert(UUID())
        try w.draft.addMeasurement(ManualOrientationInput(dipAngleText: "30", dipDirectionText: "50").observation())
        let before = w.journal, draft = w.draft
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let originals = root.appendingPathComponent("original.jpg"), database = root.appendingPathComponent("mapping.json")
        let bytes = Data("source evidence".utf8); try bytes.write(to: originals); try bytes.write(to: database)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        enum Failure: Error { case disk }
        var count = 0
        XCTAssertThrowsError(try MappingExportFiles.write(export, parent: root, format: .csv, write: { data, url in
            count += 1; if count == 3 { throw Failure.disk }; try data.write(to: url)
        }))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MappingExportFiles.write(export, parent: root, format: .csv)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let prepare = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MappingCSVExport.prepare(journal: before, selection: export.selection)
        }
        do { _ = try await prepare.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["original.jpg", "mapping.json"])
        XCTAssertEqual(try Data(contentsOf: originals), bytes); XCTAssertEqual(try Data(contentsOf: database), bytes)
        XCTAssertEqual(w.journal, before); XCTAssertEqual(w.draft, draft)
        let success = try MappingExportFiles.write(export, parent: root, format: .csv); XCTAssertTrue(FileManager.default.fileExists(atPath: success.directory.path))
        success.cleanup(); XCTAssertFalse(FileManager.default.fileExists(atPath: success.directory.path))
    }
    func testIndependentHorizonAndExcavationFiltersWithinProject() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let h = try w.createHorizon(elevation: "200")
        try w.requestContext(MappingContext(projectID: p.projectID, horizonID: h))
        let e = try w.createExcavation(name: "Second", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: p.projectID, horizonID: h, excavationID: e))
        w.draft.picket = "15"; w.draft.observedAtOverride = p.observedAt
        let other = try w.save()
        var s = selection(p, "2023-11-14T12:00:00Z")
        XCTAssertEqual(try MappingCSVExport.prepare(journal: w.journal, selection: s).pointCount, 2)
        s.horizonID = h
        XCTAssertEqual(try rows(MappingCSVExport.prepare(journal: w.journal, selection: s), "points").first?["point_id"], other.id.uuidString)
        s.horizonID = nil; s.excavationID = p.excavationID
        let originalScope = try MappingCSVExport.prepare(journal: w.journal, selection: s)
        XCTAssertEqual(originalScope.pointCount, 1)
        XCTAssertEqual(try rows(originalScope, "points").first?["point_id"], p.id.uuidString)
    }
    func testReferencedPlanParentRowsAndCancellationAfterPartialWrite() async throws {
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let plans = ManagedPlanStore(root: root.appendingPathComponent("plans"))
        let plan = try plans.stage(data: DXFRealTests.data(200), filename: "survey.dxf", horizonID: p.horizonID,
            version: "survey-A", units: .millimeters, crs: "Mine grid", axes: "X north, Y east")
        try w.registerPlan(plan)
        var correction = try w.correction(for: p.id); correction.reason = "Plan position"
        try correction.fields.selectPlanPoint(PlanPoint(x: 123.12345678912345, y: -456), plan: plan)
        _ = try w.saveCorrection(correction)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        let point = try XCTUnwrap(rows(export, "points").first), planRow = try XCTUnwrap(rows(export, "plans").first)
        XCTAssertEqual(point["plan_id"], plan.id.uuidString); XCTAssertEqual(point["xy_units"], "mm")
        XCTAssertEqual(point["crs"], "Mine grid"); XCTAssertEqual(planRow["version"], "survey-A")
        XCTAssertEqual(planRow["horizon_id"], point["horizon_id"])
        XCTAssertEqual(try rows(export, "horizons").first?["horizon_id"], point["horizon_id"])
        XCTAssertEqual(try rows(export, "excavations").first?["excavation_id"], point["excavation_id"])
        XCTAssertEqual(try rows(export, "excavation_horizons").first?["horizon_id"], point["horizon_id"])
        let originalBytes = try Data(contentsOf: plans.fileURL(plan))
        let task = Task.detached {
            var writes = 0
            return try MappingExportFiles.write(export, parent: root, format: .csv, write: { data, url in
                try data.write(to: url); writes += 1
                if writes == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation after partial write") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["plans"])
        XCTAssertEqual(try Data(contentsOf: plans.fileURL(plan)), originalBytes)
        var unsupported = w.journal; unsupported.schemaVersion = MappingJournal.currentSchemaVersion - 1
        XCTAssertThrowsError(try MappingCSVExport.prepare(journal: unsupported, selection: export.selection))
    }
    func testRepresentativeSpreadsheetFixtureWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["P51_EXPORT_FIXTURE_DIR"] else { return }
        let (_, initial, p) = try P33RevisionTests().seed(); var w = initial
        var correction = try w.correction(for: p.id); correction.reason = "Representative analysis fixture"
        correction.fields.notes = "Русский, \"кавычки\"\nвторая строка"; correction.fields.x = "-123.12345678912345"
        correction.fields.y = "10"; _ = try w.saveCorrection(correction)
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection(p, "2023-11-14T12:00:00Z"))
        let root = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for table in export.tables { try table.data.write(to: root.appendingPathComponent(table.name + ".csv")) }
        try export.manifest.write(to: root.appendingPathComponent("manifest.json"))
    }
}
