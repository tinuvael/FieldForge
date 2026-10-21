import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class EnterpriseGeotechnicalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func draft(rqd: String = "70", count: Int = 5) -> MappingDraft {
        var draft = MappingDraft(); draft.bartonQ.rqd = rqd
        for _ in 0..<count { draft.addJointSet() }
        for index in draft.jointSets.indices {
            draft.jointSets[index].representative = ManualOrientationInput(dipAngleText: "45", dipDirectionText: "120", reference: .gridNorth)
        }
        return draft
    }
    private func configured(_ store: any MappingStore) throws -> MappingWorkflow {
        var w = try MappingWorkflow(store: store)
        let p = try w.createProject(name: "Проект — Кириллица")
        try w.requestContext(MappingContext(projectID: p))
        let h = try w.createHorizon(elevation: "200")
        try w.requestContext(MappingContext(projectID: p, horizonID: h))
        let e = try w.createExcavation(name: "Штрек", horizonIDs: [h])
        try w.requestContext(MappingContext(projectID: p, horizonID: h, excavationID: e))
        w.draft = draft(count: 3); w.draft.picket = "1+5"; w.draft.observedAtOverride = now
        return w
    }
    private func gsi(_ lower: Double = 35, _ upper: Double = 45, final: Double? = nil) -> GSIAssessment {
        GSIAssessment(selection: GSIChartSelection(structure: .veryBlocky, surface: .fair), lower: lower, upper: upper, finalValue: final, assessedAt: now)
    }
    private func directory(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }
    func testPriestHudsonIndependentFrequencyExamplesAndExtremes() throws {
        // Forward examples independently specified from the published exponential equation.
        for (lambda, rqd) in [(1.0, 99.53211598395555), (10, 73.57588823428847), (20, 40.60058497098381), (50, 4.04276819945128)] {
            XCTAssertEqual(try XCTUnwrap(PriestHudsonSpacing.estimate(rqd: rqd)), 1 / lambda, accuracy: 1e-11)
        }
        XCTAssertEqual(try XCTUnwrap(PriestHudsonSpacing.estimate(rqd: 70)), 0.09, accuracy: 0.002)
        for value in [nil, 0, 100, -1, 101, .infinity, -.infinity, .nan] as [Double?] { XCTAssertNil(PriestHudsonSpacing.estimate(rqd: value)) }
        for rqd in [Double.leastNonzeroMagnitude, 0.00001, 0.1, 10, 50, 99.999, 100.nextDown] {
            let sd = try XCTUnwrap(PriestHudsonSpacing.estimate(rqd: rqd))
            XCTAssertTrue(sd.isFinite && sd > 0)
            let x = 0.1 / sd
            XCTAssertEqual(log1p(x) - x, log(rqd) - log(100), accuracy: 1e-11)
        }
    }
    func testAllSystemsInitialiseThenOnlyAutomaticValuesFollowRQD() throws {
        var d = draft()
        XCTAssertEqual(d.jointSets.map(\.identifier), JointSetIdentifier.allCases)
        let estimate = try XCTUnwrap(PriestHudsonSpacing.estimate(rqd: 70))
        for set in d.jointSets {
            XCTAssertEqual(try set.record(now: now).spacingMeters, estimate)
            XCTAssertEqual(set.spacingProvenance?.source, .estimatedFromRQD)
            XCTAssertEqual(set.spacingProvenance?.rqdSource, .bartonQOriginal)
        }
        let others = Array(d.jointSets.dropFirst()); d.jointSets[0].spacing = "0,20"
        XCTAssertEqual(Array(d.jointSets.dropFirst()), others)
        d.bartonQ.rqd = "80"
        XCTAssertEqual(d.jointSets[0].spacing, "0,20"); XCTAssertEqual(d.jointSets[0].spacingProvenance?.source, .manual)
        for set in d.jointSets.dropFirst() { XCTAssertEqual(try set.record(now: now).spacingMeters, PriestHudsonSpacing.estimate(rqd: 80)) }
        d.jointSets[0].resetSpacingEstimate(d.spacingRQD)
        XCTAssertEqual(d.jointSets[0].spacingProvenance?.source, .estimatedFromRQD)
        XCTAssertEqual(try d.jointSets[0].record(now: now).spacingMeters, PriestHudsonSpacing.estimate(rqd: 80))
    }
    func testRQDSourceFallbackConflictInvalidAndNoQMinimumReplacement() throws {
        var d = draft(rqd: "5", count: 1)
        XCTAssertEqual(try d.jointSets[0].record(now: now).spacingMeters, PriestHudsonSpacing.estimate(rqd: 5))
        XCTAssertNotEqual(PriestHudsonSpacing.estimate(rqd: 5), PriestHudsonSpacing.estimate(rqd: 10))
        d.rmr89.rqd = "70"
        XCTAssertNil(d.spacingRQD.value); XCTAssertNotNil(d.spacingRQD.warning); XCTAssertEqual(d.jointSets[0].spacing, "")
        d.bartonQ.rqd = ""
        XCTAssertEqual(d.spacingRQD.source, .rmr89Fallback)
        XCTAssertEqual(try d.jointSets[0].record(now: now).spacingMeters, PriestHudsonSpacing.estimate(rqd: 70))
        d.bartonQ.rqd = "70"; XCTAssertNil(d.spacingRQD.warning); XCTAssertEqual(d.spacingRQD.source, .bartonQOriginal)
        d.bartonQ.rqd = "nan"; XCTAssertNil(d.spacingRQD.value); XCTAssertNotNil(d.spacingRQD.warning)
        d.jointSets[0].spacing = "0.4"; d.bartonQ.rqd = "100"; XCTAssertEqual(d.jointSets[0].spacing, "0.4")
        for raw in ["", "0", "100", "-2", "101", "infinity", "не число"] {
            let value = draft(rqd: raw, count: 1)
            XCTAssertEqual(value.jointSets[0].spacing, "")
        }
    }
    func testMeanUsesEffectiveValuesAndDoesNotAddMissingOrZero() throws {
        var d = draft(count: 5)
        for (i, raw) in ["0.20", "0.40", "0.09", "", "0"].enumerated() { d.jointSets[i].spacing = raw }
        let mean = JointSpacingMean(try d.jointSets.map { try $0.record(now: now) })
        XCTAssertEqual(try XCTUnwrap(mean.value), 0.23, accuracy: 1e-15); XCTAssertEqual(mean.count, 3)
        XCTAssertFalse(mean.includesEstimates)
        let mixed = JointSpacingMean(try draft(count: 2).jointSets.map { try $0.record(now: now) })
        XCTAssertEqual(mixed.count, 2); XCTAssertTrue(mixed.includesEstimates)
        XCTAssertNil(JointSpacingMean([]).value); XCTAssertEqual(JointSpacingMean([]).count, 0)
    }
    func testLegacySpacingDecodesWithoutReinterpretationAndSurvivesRQDChanges() throws {
        var set = draft(count: 1).jointSets[0]; set.spacing = "0.12345678901234567"
        let encoded = try JSONEncoder().encode(set.record(now: now))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]); object.removeValue(forKey: "spacingProvenance")
        let legacy = try JSONDecoder().decode(InterpretedJointSet.self, from: JSONSerialization.data(withJSONObject: object))
        try legacy.validate(pointMeasurementIDs: [])
        XCTAssertNil(legacy.spacingProvenance)
        var d = draft(count: 0); d.jointSets = [JointSetDraft(legacy)]; d.bartonQ.rqd = "90"
        XCTAssertEqual(try d.jointSets[0].record(now: now).spacingMeters, legacy.spacingMeters)
        XCTAssertNil(d.jointSets[0].spacingProvenance)
        XCTAssertEqual(try d.jointSets[0].corrected(previous: legacy, now: now.addingTimeInterval(1)), legacy)
    }
    func testTamperedSpacingMethodAndCalculatedValueAreRejected() throws {
        let set = try draft(count: 1).jointSets[0].record(now: now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as? [String: Any])
        object["spacingMeters"] = 100
        let bad = try JSONDecoder().decode(InterpretedJointSet.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try bad.validate(pointMeasurementIDs: []))
    }
    func testManualSpacingROCKGSIAndCorrectionsSurviveAtomicFileRelaunch() throws {
        try directory { url in
            let file = url.appendingPathComponent("mapping.json")
            var w = try configured(FileMappingStore(url: file))
            w.draft.jointSets[0].spacing = "0.20"
            let rock = RockLithology(code: "001.20", name: "Порода владельца")
            try w.addLithology(rock, projectID: XCTUnwrap(w.context.projectID)); w.draft.rock = rock; w.draft.gsi = gsi()
            let original = try w.save(now: now)
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let originalBytes = try encoder.encode(original)
            w = try MappingWorkflow(store: FileMappingStore(url: file))
            XCTAssertEqual(w.observations.first, original)
            var correction = try w.correction(for: original.id)
            XCTAssertEqual(correction.fields.jointSets, original.geology?.jointSets.map(JointSetDraft.init))
            correction.reason = "Уточнение RQD и GSI"; correction.fields.bartonQ.rqd = "80"; correction.fields.gsi = gsi(40, 50, final: 43)
            let revision = try w.saveCorrection(correction, now: now.addingTimeInterval(10))
            XCTAssertEqual(revision.snapshot.geology?.jointSets[0].spacingMeters, 0.20)
            XCTAssertEqual(revision.snapshot.geology?.jointSets[0], original.geology?.jointSets[0])
            XCTAssertEqual(revision.snapshot.geology?.jointSets[1].spacingMeters, PriestHudsonSpacing.estimate(rqd: 80))
            XCTAssertEqual(revision.snapshot.ratings?.gsi?.selection, original.ratings?.gsi?.selection)
            XCTAssertEqual(revision.snapshot.ratings?.gsi?.finalValue, 43)
            XCTAssertEqual(try encoder.encode(w.journal.observations[0]), originalBytes)
            let saved = try MappingWorkflow(store: FileMappingStore(url: file))
            XCTAssertEqual(saved.observations, [revision.snapshot]); XCTAssertEqual(saved.journal.history(for: original.id).count, 1)
            XCTAssertEqual(saved.journal.projects.first?.lithologies, [rock])
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("previous").path))
            XCTAssertThrowsError(try w.addLithology(RockLithology(code: rock.code, name: "Другой тип"), projectID: XCTUnwrap(w.context.projectID)))
            var changed = saved.journal; changed.projects[0].lithologies = []
            let store = FileMappingStore(url: file); _ = try store.load()
            XCTAssertThrowsError(try store.save(changed))
            XCTAssertEqual(try MappingWorkflow(store: FileMappingStore(url: file)).observations, saved.observations)
        }
    }
    func testFieldGradesAndLaboratoryRatingsNeverDoubleCount() throws {
        for (grade, rating) in zip(FieldStrengthGrade.allCases, [0, 1, 2, 4, 7, 12, 15]) {
            var input = FinalFieldPolishTests.referenceInput(); input.strengthTest = .fieldEstimate
            input.strengthMPa = ""; input.basicSelections?["strength"] = nil; input.fieldStrength = FieldStrengthAssessment(grade)
            let result = try input.basicEvaluation()
            XCTAssertEqual(result.components["strength"], rating); XCTAssertEqual(result.value, 64 - 12 + rating)
            let assessment = try RMR89Assessment(input: input, now: now); try assessment.validate()
            XCTAssertEqual(assessment.method, RMR89Assessment.fieldStrengthVersion)
            input.strengthMPa = "150"; XCTAssertThrowsError(try input.basicEvaluation())
        }
        var laboratory = FinalFieldPolishTests.referenceInput()
        XCTAssertEqual(try laboratory.basicEvaluation().value, 64)
        laboratory.strengthTest = .ucs; laboratory.strengthMPa = "150"; laboratory.basicSelections?["strength"] = "strength-1"
        XCTAssertEqual(try laboratory.basicEvaluation().value, 64)
    }
    func testJCond76AllPublishedRatingsIndependentOfRMR89Condition() throws {
        var input = FinalFieldPolishTests.referenceInput()
        let baseline = try input.basicEvaluation()
        for (category, rating) in zip(JCond76Category.allCases, [25, 20, 12, 6, 0]) {
            input.jcond76 = JCond76Assessment(category)
            XCTAssertEqual(input.jcond76?.rating, rating); try input.jcond76?.validate()
            XCTAssertEqual(try input.basicEvaluation(), baseline)
            let saved = try RMR89Assessment(input: input, now: now)
            try JSONDecoder().decode(RMR89Assessment.self, from: JSONEncoder().encode(saved)).validate()
        }
    }
    func testGSIUnusableCellsAndNonFiniteOrInventedGeometryAreRejected() throws {
        var invalidCount = 0
        for structure in GSIStructure.allCases {
            for surface in GSISurface.allCases {
                let selection = GSIChartSelection(structure: structure, surface: surface)
                if selection.applicable { try selection.validate() } else { invalidCount += 1; XCTAssertThrowsError(try selection.validate()) }
            }
        }
        XCTAssertEqual(invalidCount, 4)
        try gsi().validate(); XCTAssertThrowsError(try gsi(50, 40).validate()); XCTAssertThrowsError(try gsi(-1, 30).validate())
        XCTAssertThrowsError(try gsi(30, 101).validate()); XCTAssertThrowsError(try gsi(.nan, 50).validate()); XCTAssertThrowsError(try gsi(final: .infinity).validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(gsi().selection)) as? [String: Any]); object["x"] = 0.99
        let tampered = try JSONDecoder().decode(GSIChartSelection.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try tampered.validate())
    }
    func testROCKExactCodeAndLegacyOptionalDecoding() throws {
        try RockLithology(code: "0001.20", name: nil).validate()
        for code in ["", "nan", "-1", "A1", "1,2", "1 2"] { XCTAssertThrowsError(try RockLithology(code: code, name: nil).validate()) }
        let project = try JSONDecoder().decode(MappingProject.self, from: Data("{\"id\":\"11111111-1111-1111-1111-111111111111\",\"name\":\"Проект\"}".utf8))
        XCTAssertNil(project.lithologies)
    }
    func testThreeSheetReportSavedMeanProvenanceHistoryAndLegacyExports() throws {
        var w = try configured(MappingTests.MemoryStore())
        w.draft.jointSets[0].spacing = "0.20"; w.draft.jointSets[1].spacing = "0.40"
        w.draft.gsi = gsi(); w.draft.rmr89 = FinalFieldPolishTests.referenceInput()
        w.draft.rmr89.jcond76 = JCond76Assessment(.roughClosedHard)
        let original = try w.save(now: now)
        var correction = try w.correction(for: original.id); correction.reason = "Примечание"; correction.fields.notes = "Кириллица =1+2"
        _ = try w.saveCorrection(correction, now: now.addingTimeInterval(1))
        let selection = MappingExportSelection(projectID: original.projectID, firstDay: now, lastDay: now, timeZoneID: "Asia/Almaty")
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: selection, includeEnterprise: true)
        let tables = export.enterpriseTables
        XCTAssertEqual(tables.map(\.name), ["Геотех картирование", "Справочники", "Исходные данные"])
        for table in tables { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.columns.count }, table.name) }
        let report = tables[0]; XCTAssertEqual(report.rows.count, 1)
        func cell(_ name: String) throws -> MappingCSVExport.Cell { report.rows[0][try XCTUnwrap(report.columns.firstIndex(of: name))] }
        if case .number(let mean) = try cell("SD среднее, м") { XCTAssertEqual(try XCTUnwrap(mean), (0.2 + 0.4 + PriestHudsonSpacing.estimate(rqd: 70)!) / 3, accuracy: 1e-15) } else { XCTFail() }
        if case .integer(let count) = try cell("Систем в среднем SD") { XCTAssertEqual(count, 3) } else { XCTFail() }
        let source = tables[2].rows.flatMap { row -> [String] in row.compactMap { if case .text(let text) = $0 { return text }; return nil } }
        XCTAssertTrue(source.contains("manual")); XCTAssertTrue(source.contains("estimatedFromRQD")); XCTAssertTrue(source.contains("Исправление")); XCTAssertTrue(source.contains("/ratings/gsi/selection/x")); XCTAssertTrue(source.contains("/snapshot/ratings/gsi/selection/x"))
        for format in [MappingExportFormat.xlsx, .csv, .enterpriseGeotechnical] {
            let files = try MappingExportFiles.write(export, format: format)
            XCTAssertTrue(files.urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }); files.cleanup()
        }
        if let fixture = ProcessInfo.processInfo.environment["FF_ENTERPRISE_FIXTURE_DIR"] {
            let path = URL(fileURLWithPath: fixture); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let workbook = path.appendingPathComponent("FieldForge-Geotechnical.xlsx")
            if FileManager.default.fileExists(atPath: workbook.path) { try FileManager.default.removeItem(at: workbook) }
            try MappingXLSXExport.write(export, to: workbook, enterprise: true)
            try JSONSerialization.data(withJSONObject: ["mean": JointSpacingMean(w.observations[0].geology!.jointSets).value!, "rows": 1, "estimated_sd": String(w.observations[0].geology!.jointSets[2].spacingMeters!)]).write(to: path.appendingPathComponent("expected.json"))
        }
    }
    func testStagedSystemAcceptanceUsesCurrentRQDButKeepsManualOverride() throws {
        var w = try configured(MappingTests.MemoryStore())
        let auto = w.draft.newJointSet(identifier: .J4), request = w.editorRequest(w.draft.newJointSet(identifier: .J4))
        var staged = request.initial
        staged.representative = w.draft.jointSets[0].representative
        w.draft.bartonQ.rqd = "90"
        try w.acceptJointSet(staged, originals: [], request: request)
        XCTAssertEqual(try w.draft.jointSets.last?.record(now: now).spacingMeters, PriestHudsonSpacing.estimate(rqd: 90))
        var manual = w.draft.jointSets[0]; let manualRequest = w.editorRequest(manual)
        manual.spacing = "0.2"; w.draft.bartonQ.rqd = "80"
        try w.acceptJointSet(manual, originals: [], request: manualRequest)
        XCTAssertEqual(w.draft.jointSets[0].spacing, "0.2")
        XCTAssertEqual(auto.spacingProvenance?.source, .estimatedFromRQD)
    }
    func testLegacyCurrentSchemaFileRoundTripCorrectionAndAuditOrigin() throws {
        try directory { url in
            var seed = try configured(MappingTests.MemoryStore()); seed.draft.jointSets[0].spacing = "0.37"
            _ = try seed.save(now: now)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(seed.journal)) as? [String: Any])
            var points = try XCTUnwrap(json["observations"] as? [[String: Any]])
            var geology = try XCTUnwrap(points[0]["geology"] as? [String: Any])
            var sets = try XCTUnwrap(geology["jointSets"] as? [[String: Any]])
            for index in sets.indices { sets[index].removeValue(forKey: "spacingProvenance") }
            geology["jointSets"] = sets; points[0]["geology"] = geology; json["observations"] = points
            let file = url.appendingPathComponent("legacy-current.json")
            let bytes = try JSONSerialization.data(withJSONObject: json); try bytes.write(to: file)
            var w = try MappingWorkflow(store: FileMappingStore(url: file))
            let original = try XCTUnwrap(w.observations.first)
            var correction = try w.correction(for: original.id); correction.reason = "RQD"; correction.fields.bartonQ.rqd = "90"
            let result = try w.saveCorrection(correction, now: now.addingTimeInterval(1))
            XCTAssertEqual(result.snapshot.geology?.jointSets, original.geology?.jointSets)
            XCTAssertNil(result.snapshot.geology?.jointSets[0].spacingProvenance)
            XCTAssertEqual(result.snapshot.geology?.jointSets[0].spacingMeters, 0.37)
            let tables = try EnterpriseGeotechnicalWorkbook.tables(points: w.observations, journal: w.journal)
            XCTAssertTrue(tables[2].rows.contains { row in row.contains { if case .text("unknownLegacy") = $0 { return true }; return false } })
            XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("previous")), bytes)
        }
    }
    func testCorruptNewAssessmentsRefuseWritesAndPreserveExistingBytes() throws {
        func tamper<T: Codable>(_ value: T, key: String, replacement: Any) throws -> T {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            object[key] = replacement
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertThrowsError(try tamper(FieldStrengthAssessment(.R4), key: "rating", replacement: 15).validate())
        XCTAssertThrowsError(try tamper(JCond76Assessment(.slightlyRoughSoft), key: "rating", replacement: 20).validate())
        XCTAssertThrowsError(try tamper(JCond76Assessment(.slightlyRoughSoft), key: "method", replacement: "unknown").validate())
        XCTAssertThrowsError(try tamper(gsi(), key: "method", replacement: "unknown").validate())
        try directory { url in
            let file = url.appendingPathComponent("mapping.json")
            var w = try configured(FileMappingStore(url: file)); w.draft.gsi = gsi()
            let original = try w.save(now: now), before = try Data(contentsOf: file)
            var correction = try w.correction(for: original.id); correction.reason = "Неверная оценка"; correction.fields.gsi = gsi(70, 20)
            XCTAssertThrowsError(try w.saveCorrection(correction, now: now.addingTimeInterval(1)))
            XCTAssertEqual(try Data(contentsOf: file), before)
            XCTAssertEqual(w.observations, [original])
        }
    }
    func testEmptyLegacyObservationsRemainExportableAndNoMissingValueBecomesZero() throws {
        var w = try configured(MappingTests.MemoryStore()); w.draft = MappingDraft(); w.draft.picket = "0"
        let point = try w.save(now: now)
        let tables = try EnterpriseGeotechnicalWorkbook.tables(points: [point], journal: w.journal)
        let report = tables[0]
        if case .number(let mean) = report.rows[0][try XCTUnwrap(report.columns.firstIndex(of: "SD среднее, м"))] { XCTAssertNil(mean) } else { XCTFail() }
        let files = try MappingExportFiles.write(MappingCSVExport.prepare(journal: w.journal, selection: MappingExportSelection(projectID: point.projectID, firstDay: now, lastDay: now, timeZoneID: "UTC"), includeEnterprise: true), format: .enterpriseGeotechnical)
        XCTAssertEqual(files.urls.count, 1); files.cleanup()
    }
}
