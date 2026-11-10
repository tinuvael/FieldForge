import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class EnterpriseGeotechnicalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func draft(rqd: String = "70", count: Int = 4) -> MappingDraft {
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
        XCTAssertEqual(d.jointSets.map(\.identifier), [.J1, .J2, .J3, .J4])
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
    func testManualSpacingRejectsZeroNegativeNonFiniteAndAcceptsMissingOrPositive() throws {
        var set = draft(count: 1).jointSets[0]
        for raw in ["0", "0,0", "-0", "-0,01", "-1", "nan", "inf", "1e309"] {
            set.spacing = raw
            XCTAssertThrowsError(try set.validatedSpacing(), raw)
            XCTAssertThrowsError(try set.record(now: now), raw)
        }
        for raw in ["", " "] {
            set.spacing = raw; XCTAssertNil(try set.record(now: now).spacingMeters)
        }
        for (raw, expected) in [("0,01", 0.01), ("0.2", 0.2), ("0.000000000001", 1e-12)] {
            set.spacing = raw; XCTAssertEqual(try set.record(now: now).spacingMeters, expected)
        }
        set.spacing = "0"; set.spacingProvenance = nil
        let legacy = try set.record(now: now); try legacy.validate(pointMeasurementIDs: [])
        XCTAssertEqual(legacy.spacingMeters, 0)
        XCTAssertEqual(try JointSetDraft(legacy).record(now: now).spacingMeters, 0)
        var editedLegacy = JointSetDraft(legacy); editedLegacy.spacing = "0"
        XCTAssertThrowsError(try editedLegacy.record(now: now))
    }
    func testInvalidManualSpacingCannotSaveOrCorrectAndPreservesExistingFiles() throws {
        try directory { url in
            let file = url.appendingPathComponent("mapping.json")
            var w = try configured(FileMappingStore(url: file))
            let before = try Data(contentsOf: file)
            let backup = file.appendingPathExtension("previous"), previous = try Data(contentsOf: backup)
            for raw in ["0", "-0.1"] {
                w.draft.jointSets[0].spacing = raw
                XCTAssertThrowsError(try w.save(now: now))
                XCTAssertEqual(try Data(contentsOf: file), before)
                XCTAssertEqual(try Data(contentsOf: backup), previous)
                XCTAssertEqual(w.draft.jointSets[0].spacing, raw)
            }
            w.draft.jointSets[0].spacing = "0.2"; let original = try w.save(now: now)
            let saved = try Data(contentsOf: file), savedBackup = try Data(contentsOf: backup)
            for raw in ["0", "-0.1"] {
                var correction = try w.correction(for: original.id)
                correction.reason = "Проверка SD"; correction.fields.jointSets[0].spacing = raw
                XCTAssertThrowsError(try w.saveCorrection(correction, now: now.addingTimeInterval(1)))
                XCTAssertEqual(try Data(contentsOf: file), saved)
                XCTAssertEqual(try Data(contentsOf: backup), savedBackup)
            }
            XCTAssertEqual(w.observations, [original]); XCTAssertTrue(w.journal.revisions.isEmpty)
        }
    }
    func testGSIFinalMustBeWithinInclusiveAssessmentInterval() throws {
        for value in [35.0, 40, 45] {
            let value = gsi(final: value); try value.validate()
            let decoded = try JSONDecoder().decode(GSIAssessment.self, from: JSONEncoder().encode(value))
            try decoded.validate(); XCTAssertEqual(decoded, value)
        }
        try gsi().validate(); try gsi(40, 40, final: 40).validate()
        for value in [Double(35).nextDown, Double(45).nextUp, 0, 100, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try gsi(final: value).validate())
        }
        for value in [39.0, 41] { XCTAssertThrowsError(try gsi(40, 40, final: value).validate()) }
    }
    func testOutOfRangeGSICorrectionDoesNotChangeSelectionOrHistory() throws {
        try directory { url in
            let file = url.appendingPathComponent("mapping.json")
            var w = try configured(FileMappingStore(url: file)); w.draft.gsi = gsi(final: 40)
            let original = try w.save(now: now), bytes = try Data(contentsOf: file)
            for final in [34.0, 46] {
                var correction = try w.correction(for: original.id)
                correction.reason = "Проверка GSI"; correction.fields.gsi = gsi(final: final)
                XCTAssertThrowsError(try w.saveCorrection(correction, now: now.addingTimeInterval(1)))
                XCTAssertEqual(try Data(contentsOf: file), bytes)
                XCTAssertEqual(w.observations, [original]); XCTAssertTrue(w.journal.revisions.isEmpty)
            }
            var valid = try w.correction(for: original.id); valid.reason = "Уточнение GSI"; valid.fields.gsi = gsi(final: 45)
            let revised = try w.saveCorrection(valid, now: now.addingTimeInterval(1))
            XCTAssertEqual(revised.snapshot.ratings?.gsi?.selection, original.ratings?.gsi?.selection)
            XCTAssertEqual(revised.snapshot.ratings?.gsi?.lower, 35); XCTAssertEqual(revised.snapshot.ratings?.gsi?.upper, 45)
            XCTAssertEqual(revised.snapshot.ratings?.gsi?.finalValue, 45)
            XCTAssertEqual(w.journal.observations, [original])
            XCTAssertEqual(try MappingWorkflow(store: FileMappingStore(url: file)).observations, [revised.snapshot])
        }
    }
    func testMeanUsesEffectiveValuesAndDoesNotAddMissingOrZero() throws {
        var d = draft()
        for (i, raw) in ["0.20", "0.40", "0.09", ""].enumerated() { d.jointSets[i].spacing = raw }
        // Zero is only representable here as untouched legacy evidence, never new manual input.
        var historical = JointSetDraft(identifier: .J5)
        historical.representative = d.jointSets[0].representative
        historical.spacing = "0"; historical.spacingProvenance = nil
        d.jointSets.append(historical)
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
            XCTAssertEqual(assessment.method, RMR89Assessment.verifiedVersion)
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
    func testRegulatoryEffectiveRowsAndLegacyReports() throws {
        var w = try configured(MappingTests.MemoryStore())
        func draftID(_ value: Int) -> UUID { UUID(uuidString: "00000000-0000-4000-8000-00000000000\(value)")! }
        let rock = RockLithology(code: "0001.20", name: nil)
        try w.addLithology(rock, projectID: XCTUnwrap(w.context.projectID))
        w.draft = MappingDraft(id: draftID(1))
        w.draft.picket = "1+5"; w.draft.observedAtOverride = now
        w.draft.rock = rock
        w.draft.x = "99"; w.draft.y = "0"; w.draft.z = "-14.125"
        w.draft.crs = "synthetic"; w.draft.axes = "X north, Y east"; w.draft.coordinateProvenance = "synthetic manual input"
        w.draft.bartonQ.rqd = "5"
        w.draft.bartonQ.jw.select("C", parameter: .jw)
        w.draft.bartonQ.jn.select("F", parameter: .jn)
        w.draft.bartonQ.jr.select("B", parameter: .jr)
        w.draft.bartonQ.ja.select("C", parameter: .ja)
        w.draft.rmr89.rqd = "5.0"; w.draft.rmr89.strengthTest = .ucs; w.draft.rmr89.strengthMPa = "140"
        w.draft.rmr89.basicSelections = ["persistence": "persistence-1", "aperture": "aperture-3", "weathering": "weathering-2"]
        w.draft.rmr89.jcond76 = JCond76Assessment(.roughClosedHard)
        w.draft.gsi = gsi(final: 41.25)
        for (identifier, dip, azimuth, spacing) in [
            (JointSetIdentifier.J1, "11", "101", "0.25"), (.J2, "22", "0", "0"),
            (.J3, "33", "303", "0.50"), (.J4, "0", "", ""), (.J5, "55", "155", "100")
        ] {
            var set = JointSetDraft(identifier: identifier)
            set.representative = .init(dipAngleText: dip, dipDirectionText: azimuth, reference: .magneticNorth)
            set.spacing = spacing
            if identifier == .J2 { set.spacingProvenance = nil } // legacy stored zero
            w.draft.jointSets.append(set)
        }
        var first = TectonicStructureDraft()
        first.orientation = .init(dipAngleText: "32.125", dipDirectionText: "0", reference: .trueNorth)
        first.thickness = "0"
        var second = TectonicStructureDraft()
        second.orientation = .init(dipDirectionText: "270", reference: .gridNorth)
        second.thickness = "0.875"
        w.draft.tectonicStructures = [first]
        let original = try w.seedHistoricalJointSetPoint(now: now)

        var correction = try w.correction(for: original.id)
        correction.reason = "Уточнение координат и тектоники"
        correction.fields.x = "1234567.123456789"
        correction.fields.rmr89.strengthMPa = "152.125"
        correction.fields.tectonicStructures.append(second)
        let revision = try w.saveCorrection(correction, now: now.addingTimeInterval(1))

        w.draft = MappingDraft(id: draftID(2))
        w.draft.picket = "2+5"; w.draft.observedAtOverride = now
        w.draft.rmr89.strengthTest = .pointLoadIs50; w.draft.rmr89.strengthMPa = "8"
        w.draft.rmr89.rqd = "80"; w.draft.bartonQ.rqd = "90"
        w.draft.rmr89.basicSelections = ["weathering": "weathering-4"]
        w.draft.gsi = gsi()
        var single = TectonicStructureDraft(); single.orientation.dipAngleText = "48"
        w.draft.tectonicStructures = [single]
        let oneFault = try w.save(now: now)

        w.draft = MappingDraft(id: draftID(3))
        w.draft.picket = "3+5"; w.draft.observedAtOverride = now
        w.draft.rmr89.strengthTest = .fieldEstimate
        w.draft.rmr89.fieldStrength = FieldStrengthAssessment(.R0)
        w.draft.rmr89.rqd = "0"
        var historicalJ5 = JointSetDraft(identifier: .J5)
        historicalJ5.representative = .init(dipAngleText: "55", dipDirectionText: "155")
        historicalJ5.spacing = "100"
        w.draft.jointSets = [historicalJ5]
        let noFault = try w.seedHistoricalJointSetPoint(now: now)

        let journal = w.journal
        let selection = MappingExportSelection(projectID: original.projectID, firstDay: now, lastDay: now, timeZoneID: "UTC")
        let exportID = draftID(9)
        let export = try MappingCSVExport.prepare(journal: journal, selection: selection, now: now, id: exportID, includeEnterprise: true)
        let plain = try MappingCSVExport.prepare(journal: journal, selection: selection, now: now, id: exportID)
        let regulatory = try XCTUnwrap(export.enterpriseReport)
        let report = regulatory.table
        XCTAssertTrue(regulatory.requiresReview)
        XCTAssertEqual(regulatory.rqdConflicts.map(\.id), [oneFault.id])
        XCTAssertEqual(regulatory.rqdConflicts.first?.picket, oneFault.displayPicket)
        XCTAssertEqual(regulatory.rqdConflicts.first?.q, "90")
        XCTAssertEqual(regulatory.rqdConflicts.first?.rmr, "80")
        XCTAssertEqual(regulatory.spatialWarnings, [
            "Высотная система Z: есть неизвестные значения.",
            "В азимутах используются разные типы севера: магнитный, истинный, сеточный."
        ])
        // J5 and a dip without an azimuth do not contribute a north reference.
        XCTAssertFalse(try EnterpriseGeotechnicalWorkbook.prepare(points: [noFault], journal: journal).requiresReview)
        XCTAssertEqual(report.name, "Data")
        XCTAssertEqual(report.columns.joined(separator: " "), "ID PK X Y Z ROCK A45 JW A1 UCS RQD JN JR JA SD A43 JCON76 A42 F_DIP F_AZI F_THI J_DIP_1 J_AZI_1 J_DIP_2 J_AZI_2 J_DIP_3 J_AZI_3 J_DIP_4 J_AZI_4 GSI")
        XCTAssertEqual(report.rows.count, 4)
        typealias Cell = MappingCSVExport.Cell
        let leading: [Cell] = [.text("Штрек"), .text(revision.snapshot.displayPicket), .number(1234567.123456789), .number(0),
            .number(-14.125), .text("0001.20"), .integer(3), .number(0.5), .empty, .number(152.125), .number(5),
            .number(9), .number(3), .number(2), .number(0.375), .integer(1), .integer(25), .integer(4)]
        let trailing: [Cell] = [.number(11), .number(101), .number(22), .number(0), .number(33), .number(303), .number(0), .empty, .number(41.25)]
        var singleRow = [Cell](repeating: .empty, count: 30)
        singleRow[0] = .text("Штрек"); singleRow[1] = .text(oneFault.displayPicket); singleRow[18] = .number(48)
        var noFaultRow = [Cell](repeating: .empty, count: 30)
        noFaultRow[0] = .text("Штрек"); noFaultRow[1] = .text(noFault.displayPicket)
        noFaultRow[8] = .integer(0); noFaultRow[10] = .number(0)
        let expected = [
            leading + [.number(32.125), .number(0), .number(0)] + trailing,
            leading + [.empty, .number(270), .number(0.875)] + trailing,
            singleRow, noFaultRow
        ]
        XCTAssertEqual(report.rows.map { $0.map(\.csv) }, expected.map { $0.map(\.csv) })
        XCTAssertEqual(export.pointCount, 3)
        XCTAssertEqual(export.tables.map(\.data), plain.tables.map(\.data))
        XCTAssertEqual(export.fieldTables.map(\.data), plain.fieldTables.map(\.data))
        XCTAssertEqual(export.manifest, plain.manifest)
        let jointTable = try XCTUnwrap(export.tables.first { $0.name == "joint_sets" })
        XCTAssertEqual(jointTable.rows.filter { $0.contains { $0.csv == Cell.text("J5").csv } }.count, 2)
        XCTAssertEqual(w.journal.observations, [original, oneFault, noFault])
        XCTAssertEqual(w.journal.history(for: original.id), [revision])
        XCTAssertEqual(revision.snapshot.geology?.jointSets.last, original.geology?.jointSets.last)

        let files = try MappingExportFiles.write(export, format: .enterpriseGeotechnical)
        defer { files.cleanup() }
        let workbook = try XCTUnwrap(files.urls.first)
        if let fixture = ProcessInfo.processInfo.environment["FF_ENTERPRISE_FIXTURE_DIR"] {
            let path = URL(fileURLWithPath: fixture)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try Data(contentsOf: workbook).write(to: path.appendingPathComponent(workbook.lastPathComponent))
        }
    }
    func testRegulatorySpatialWarningsPreserveCoordinatesAndAzimuths() throws {
        try directory { root in
            var w = try configured(MappingTests.MemoryStore())
            let plans = ManagedPlanStore(root: root)
            let dxf = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n11\n10\n21\n0\n")
            let horizonID = try XCTUnwrap(w.context.horizonID)
            w.draft = MappingDraft()
            w.draft.picket = "1"; w.draft.observedAtOverride = now
            w.draft.x = "0"; w.draft.y = "21"; w.draft.crs = "Grid A"; w.draft.axes = "X north"
            let manual = try w.save(now: now)

            let millimeters = try plans.stage(data: dxf, filename: "mm.dxf", horizonID: horizonID,
                version: "mm", units: .millimeters, crs: "Grid B", axes: "X east")
            try w.registerPlan(millimeters)
            try w.selectPlanPoint(.init(x: 1000, y: 2000), planID: millimeters.id)
            w.draft.picket = "2"; w.draft.observedAtOverride = now
            let metricPlan = try w.save(now: now)

            let drawing = try plans.stage(data: dxf, filename: "drawing.dxf", horizonID: horizonID,
                version: "drawing", units: .unknown, crs: "local", axes: "не указано")
            try w.registerPlan(drawing)
            try w.selectPlanPoint(.init(x: 15, y: 25), planID: drawing.id)
            w.draft.picket = "3"; w.draft.observedAtOverride = now
            var fault = TectonicStructureDraft()
            fault.orientation = .init(dipDirectionText: "33", reference: .unknown)
            w.draft.tectonicStructures = [fault]
            let unknownPlan = try w.save(now: now)

            let regulatory = try EnterpriseGeotechnicalWorkbook.prepare(points: w.observations, journal: w.journal)
            XCTAssertTrue(regulatory.requiresReview)
            XCTAssertEqual(regulatory.spatialWarnings, [
                "Единицы XY: есть неизвестные значения.", "Единицы XY: разные значения (m, mm).",
                "СК XY: есть неизвестные значения.", "СК XY: разные значения (grid a, grid b).",
                "Оси XY: есть неизвестные значения.", "Оси XY: разные значения (x east, x north).",
                "Есть азимуты с неизвестным типом севера."
            ])
            let rows = Dictionary(uniqueKeysWithValues: regulatory.table.rows.map { ($0[1].csv, $0) })
            for (point, x, y) in [(manual, 0.0, 21.0), (metricPlan, 1000, 2000), (unknownPlan, 15, 25)] {
                let row = try XCTUnwrap(rows[MappingCSVExport.Cell.text(point.displayPicket).csv])
                XCTAssertEqual(row[2].csv, MappingCSVExport.Cell.number(x).csv)
                XCTAssertEqual(row[3].csv, MappingCSVExport.Cell.number(y).csv)
            }
            let unknownRow = try XCTUnwrap(rows[MappingCSVExport.Cell.text(unknownPlan.displayPicket).csv])
            XCTAssertEqual(unknownRow[19].csv, MappingCSVExport.Cell.number(33).csv)
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
        let report = try EnterpriseGeotechnicalWorkbook.prepare(points: [point], journal: w.journal).table
        if case .number(let mean) = report.rows[0][14] { XCTAssertNil(mean) } else { XCTFail("Missing SD") }
        for key in ["A1", "A42", "A43", "A45"] {
            let index = try XCTUnwrap(report.columns.firstIndex(of: key))
            XCTAssertEqual(report.rows[0][index].csv, MappingCSVExport.Cell.empty.csv, key)
        }
        let files = try MappingExportFiles.write(MappingCSVExport.prepare(journal: w.journal, selection: MappingExportSelection(projectID: point.projectID, firstDay: now, lastDay: now, timeZoneID: "UTC"), includeEnterprise: true), format: .enterpriseGeotechnical)
        XCTAssertEqual(files.urls.count, 1); files.cleanup()
    }

    func testRegulatoryCategorySelectionsProjectApprovedScoresWithStableIDs() throws {
        var w = try configured(MappingTests.MemoryStore())
        let strength: [RegulatoryStrengthBand] = [.below1, .from1To5, .from5To25, .from25To50, .from50To100, .from100To250, .above250]
        let wall: [RegulatoryWallAlteration] = [.unweathered, .slightlyWeathered, .moderatelyWeathered, .highlyWeathered, .crushed]
        let strengthScores = [0, 1, 2, 4, 7, 12, 15], wallScores = [6, 5, 3, 1, 0]
        let persistenceScores = [6, 4, 2, 1, 0], apertureScores = [6, 5, 4, 1, 0]
        for index in strength.indices {
            w.draft.picket = "\(index)"
            w.draft.regulatory = .init(strength: strength[index], wallAlteration: wall[index % 5])
            w.draft.rmr89.basicSelections = ["persistence": "persistence-\(index % 5)", "aperture": "aperture-\(index % 5)"]
            let point = try w.save(now: now)
            let report = try EnterpriseGeotechnicalWorkbook.prepare(points: [point], journal: w.journal).table
            for (key, expected) in [("A1", strengthScores[index]), ("A45", wallScores[index % 5]),
                                    ("A42", persistenceScores[index % 5]), ("A43", apertureScores[index % 5])] {
                let column = try XCTUnwrap(report.columns.firstIndex(of: key))
                if case .integer(let score) = report.rows[0][column] { XCTAssertEqual(score, expected, key) }
                else { XCTFail("\(key) must be numeric, including zero") }
            }
            XCTAssertEqual(point.ratings?.rmr89?.input.basicSelections, ["persistence": "persistence-\(index % 5)", "aperture": "aperture-\(index % 5)"])
            XCTAssertNil(point.ratings?.rmr89?.input.basicSelections?["weathering"])
            XCTAssertNil(point.ratings?.rmr89?.input.strengthTest)
        }
    }

    func testIndependentRegulatoryCorrectionKeepsStoredRMR89GSIAndLaboratoryStrength() throws {
        try directory { url in
            let store = FileMappingStore(url: url.appendingPathComponent("mapping.json"))
            var w = try configured(store)
            w.draft.rmr89 = FinalFieldPolishTests.referenceInput() // Independent published 64-point example.
            w.draft.gsi = gsi(final: 41.25)
            let original = try w.save(now: now)
            XCTAssertNil(original.ratings?.regulatory)
            XCTAssertEqual(original.ratings?.rmr89?.calculation?.value, 64)
            let before = try EnterpriseGeotechnicalWorkbook.prepare(points: [original], journal: w.journal).table.rows[0]
            XCTAssertEqual(before[8].csv, MappingCSVExport.Cell.empty.csv, "Is(50) must not populate A1")

            var edit = try w.correction(for: original.id)
            edit.reason = "Record field categories"
            edit.fields.regulatory = .init(strength: .below1, wallAlteration: .crushed)
            edit.fields.bartonQ.contact = .wall
            edit.fields.bartonQ.jr.select("B", parameter: .jr)
            edit.fields.bartonQ.ja.select("C", parameter: .ja)
            let revised = try w.saveCorrection(edit, now: now.addingTimeInterval(1)).snapshot
            let persisted = try MappingWorkflow(store: FileMappingStore(url: store.url)).journal
            XCTAssertEqual(persisted.schemaVersion, 8)
            XCTAssertEqual(persisted.observations.first, original)
            XCTAssertEqual(persisted.effectiveObservation(id: original.id), revised)
            XCTAssertEqual(revised.ratings?.regulatory, edit.fields.regulatory)
            XCTAssertEqual(revised.ratings?.rmr89, original.ratings?.rmr89)
            XCTAssertEqual(revised.ratings?.bartonQ?.input.jr, edit.fields.bartonQ.jr)
            XCTAssertEqual(revised.ratings?.bartonQ?.input.ja, edit.fields.bartonQ.ja)
            XCTAssertEqual(revised.ratings?.gsi, original.ratings?.gsi)
            let after = try EnterpriseGeotechnicalWorkbook.prepare(points: [revised], journal: persisted).table.rows[0]
            for column in [6, 8] {
                if case .integer(0?) = after[column] {} else { XCTFail("Explicit zero must be numeric") }
            }
            if case .empty = after[9] {} else { XCTFail("Is(50) must not populate UCS") }
        }
    }
}
