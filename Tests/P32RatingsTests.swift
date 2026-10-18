import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class P32RatingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000.123456)
    private func q(_ rqd: String = "80") -> BartonQInput {
        var q = BartonQInput(); q.rqd = rqd; q.rqdSource = .coreMeasured; q.rqdEvidence = "Borehole log, run 2"
        q.location = .ordinary; q.contact = .wall; q.assessmentSource = "Acceptance fixture / field assessment"
        q.jn.select("F", parameter: .jn) // 9
        q.jr.select("B", parameter: .jr) // 3
        q.ja.select("C", parameter: .ja) // 2
        q.jw.select("A", parameter: .jw) // 1
        q.srf.select("G", parameter: .srf) // 1
        return q
    }
    private func result(_ input: BartonQInput) throws -> QResult { try XCTUnwrap(input.evaluate().result) }
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }
    func testIndependentHandCalculatedReferenceExamples() throws {
        // Independent rational arithmetic, documented in docs/p3-2b-ratings.md.
        // (80/9)*(3/2)*(1/1) = 40/3.
        let first = try result(q()); XCTAssertEqual(first.value, 40.0 / 3, accuracy: 1e-14); XCTAssertEqual(first.rockClass, .good)
        var second = q("60"); second.jn.select("D", parameter: .jn); second.jr.select("E", parameter: .jr)
        second.ja.select("E", parameter: .ja); second.jw.select("B", parameter: .jw); second.srf.select("C", parameter: .srf)
        // (60/4)*(1.5/4)*(.66/5) = 297/400.
        XCTAssertEqual(try result(second).value, 0.7425, accuracy: 1e-15)
        XCTAssertEqual(try result(second).rockClass, .veryPoor)
        var third = q("5"); third.location = .intersection; third.contact = .noContact
        third.jn.select("J", parameter: .jn); third.jr.select("H", parameter: .jr)
        third.ja.select("P", parameter: .ja); third.ja.value = "20"; third.ja.evidence = "Swelling fraction"
        third.jw.select("F", parameter: .jw); third.jw.value = "0.05"; third.jw.evidence = "Persistent pressure"
        third.srf.select("L", parameter: .srf); third.srf.value = "400"; third.srf.evidence = "Immediate dynamic deformation"
        // (10/60)*(1/20)*(.05/400) = 1/960000, below the plotted scale; no invented class.
        XCTAssertEqual(try result(third).value, 1.0 / 960_000, accuracy: 1e-20)
        XCTAssertNil(try result(third).rockClass)
    }
    func testRQDFloorKeepsOriginalAndDoesNotRoundEngineeringInput() throws {
        for raw in ["0", "0,125", "5", "9.999999999", "10"] {
            let input = q(raw), value = try result(input)
            XCTAssertEqual(value.calculationRQD, 10)
            XCTAssertEqual(value.measuredRQD, Double(raw.replacingOccurrences(of: ",", with: ".")))
            XCTAssertEqual(value.value, 5.0 / 3, accuracy: 1e-15)
            let saved = try BartonQAssessment(input: input, now: now)
            XCTAssertEqual(saved.input.rqd, raw); try saved.validate()
        }
        XCTAssertEqual(try result(q("10.000000001")).calculationRQD, 10.000000001)
        XCTAssertEqual(try result(q("100")).measuredRQD, 100)
        for invalid in ["-0.001", "100.0001", "NaN", "inf", "1e2", "1,2.3"] { XCTAssertThrowsError(try q(invalid).evaluate()) }
    }
    func testMissingParametersNeverUseDefaultsAndZeroDenominatorsAreRejected() throws {
        XCTAssertNil(try BartonQInput().evaluate().result)
        for parameter in QParameter.allCases {
            var input = q(); input[parameter] = QCoefficientInput()
            XCTAssertNil(try input.evaluate().result, parameter.rawValue)
            for bad in ["0", "-1", "NaN", "inf", "1e100"] {
                var invalid = q(); invalid[parameter].value = bad
                XCTAssertThrowsError(try invalid.evaluate(), parameter.rawValue + bad)
            }
        }
        var input = q(); input.rqd = ""; XCTAssertNil(try input.evaluate().result)
        input = q(); input.location = nil; XCTAssertNil(try input.evaluate().result)
        input = q(); input.contact = nil; XCTAssertNil(try input.evaluate().result)
        input = q(); input.rqdSource = nil; XCTAssertNil(try input.evaluate().result)
        input = q(); input.assessmentSource = "  "; XCTAssertNil(try input.evaluate().result)
    }
    func testExactEditionRowsAndManualRangeValidation() throws {
        // Independently transcribed numeric acceptance sheet, appendix pp.53–57.
        let expected: [QParameter: [(String, Double, Double)]] = [
            .jn: [("A",0.5,1),("B",2,2),("C",3,3),("D",4,4),("E",6,6),("F",9,9),("G",12,12),("H",15,15),("J",20,20)],
            .jr: [("A",4,4),("B",3,3),("C",2,2),("D",1.5,1.5),("E",1.5,1.5),("F",1,1),("G",0.5,0.5),("H",1,1)],
            .ja: [("A",0.75,0.75),("B",1,1),("C",2,2),("D",3,3),("E",4,4),("F",4,4),("G",6,6),("H",8,8),("J",8,12),("K",6,6),("L",8,8),("M",8,12),("N",10,10),("O",13,13),("P",13,20)],
            .jw: [("A",1,1),("B",0.66,0.66),("C",0.5,0.5),("D",0.33,0.33),("E",0.1,0.2),("F",0.05,0.1)],
            .srf: [("A",10,10),("B",7.5,7.5),("C",5,5),("D",5,5),("E",2.5,2.5),("F",2.5,2.5),("G",1,1),("H",0.5,2),("H-star",2,5),("J",5,50),("K",50,200),("L",200,400),("M",5,10),("N",10,20),("O",5,10),("P",10,15)]]
        for parameter in QParameter.allCases {
            XCTAssertEqual(QMethod.rows(parameter).map(\.id), expected[parameter]!.map(\.0))
            for (code, min, max) in expected[parameter]! {
                var input = QCoefficientInput(); input.select(code, parameter: parameter)
                if min != max { XCTAssertNil(try input.validated(parameter)) } // No automatic midpoint.
                for allowed in [min, max, (min + max) / 2] {
                    input.value = ElevationInput.text(allowed); XCTAssertEqual(try input.validated(parameter), allowed)
                }
                input.value = ElevationInput.text(min - 0.001); XCTAssertThrowsError(try input.validated(parameter))
                input.value = ElevationInput.text(max + 0.001); XCTAssertThrowsError(try input.validated(parameter))
            }
        }
        var unknown = QCoefficientInput(); unknown.category = "invented"; unknown.value = "1"; XCTAssertThrowsError(try unknown.validated(.jn))
        unknown.category = nil; XCTAssertThrowsError(try unknown.validated(.jn))
    }
    func testValueProvenanceAndRangeRationaleSurviveRoundTrip() throws {
        var input = q()
        XCTAssertEqual(input.jr.origin, .tableSelection)
        input.jr.value = "3,0"; input.jr.evidence = "Engineer confirmed original surface description"
        XCTAssertEqual(input.jr.origin, .manualWithinRow)
        input.jw.select("E", parameter: .jw); input.jw.value = "0,125"
        XCTAssertNil(try input.evaluate().result) // A range requires the assessor's rationale.
        input.jw.evidence = "Inflow decaying with time; field notebook section 4"
        let saved = try BartonQAssessment(input: input, now: now)
        XCTAssertNotNil(saved.evaluation.result)
        let reopened = try JSONDecoder().decode(BartonQAssessment.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(reopened, saved); XCTAssertEqual(reopened.input.jr.value, "3,0")
        XCTAssertEqual(reopened.input.jr.origin, .manualWithinRow); XCTAssertEqual(reopened.input.jw.value, "0,125")
        try reopened.validate()
    }
    func testJnContextMultiplierIsExplicitAndIndependentOfJointSets() throws {
        var input = q(); let ordinary = try result(input)
        input.location = .portal; XCTAssertEqual(try result(input).jn, 18); XCTAssertEqual(try result(input).value, ordinary.value / 2)
        input.location = .intersection; XCTAssertEqual(try result(input).jn, 27); XCTAssertEqual(try result(input).value, ordinary.value / 3)
        var draft = MappingDraft(); for _ in 0..<5 { draft.addJointSet() }
        XCTAssertEqual(draft.bartonQ, BartonQInput()); XCTAssertEqual(draft.rmr89, RMR89Input())
    }
    func testJrJaContactCompatibilityAndCorrections() throws {
        var input = q(); input.contact = .noContact; XCTAssertThrowsError(try input.evaluate())
        input.jr.select("H", parameter: .jr); input.ja.select("N", parameter: .ja)
        XCTAssertEqual(try result(input).jr, 1)
        input.jrAdjustment = .fewExposed; XCTAssertThrowsError(try input.evaluate())
        input = q(); input.ja.select("G", parameter: .ja); XCTAssertThrowsError(try input.evaluate())
        input.contact = .before10cm; XCTAssertNotNil(try input.evaluate().result)
        input = q(); input.jrAdjustment = .spacingOver3m
        XCTAssertNil(try input.evaluate().result)
        input.relevantSpacingMeters = "3"; XCTAssertThrowsError(try input.evaluate())
        input.relevantSpacingMeters = "3.0000001"; XCTAssertNil(try input.evaluate().result)
        input.correctionEvidence = "Span 4m, relevant mean spacing 3.0000001m, engineer decision"
        XCTAssertEqual(try result(input).jr, 4); XCTAssertEqual(try result(input).value, 160.0 / 9, accuracy: 1e-14)
        input.jrAdjustment = .fewExposed; input.relevantSpacingMeters = ""; XCTAssertEqual(try result(input).jr, 4)
    }
    func testSRFCorrectionsRequireCategoryAndEvidence() throws {
        var input = q(); input.srfAdjustment = .adjacentZone; input.srfReductionPercent = "25"
        XCTAssertThrowsError(try input.evaluate()) // G cannot be reduced using the zone note.
        input.srf.select("A", parameter: .srf); XCTAssertNil(try input.evaluate().result)
        input.correctionEvidence = "Adjacent zone influences, does not intersect opening"
        XCTAssertEqual(try result(input).srf, 7.5)
        input.srfReductionPercent = "50"; XCTAssertEqual(try result(input).srf, 5)
        for bad in ["24.999", "50.001", "0"] { input.srfReductionPercent = bad; XCTAssertThrowsError(try input.evaluate()) }
        input.srfReductionPercent = ""; XCTAssertNil(try input.evaluate().result)
        input.srfAdjustment = .shallowCrown; XCTAssertThrowsError(try input.evaluate())
        input.srf.select("F", parameter: .srf); XCTAssertEqual(try result(input).srf, 5)
    }
    func testSeven2025ClassesAndAllBoundaryTransitionsWithoutRounding() {
        let transitions: [(Double, QRockClass, QRockClass)] = [(0.01,.exceptionallyPoor,.extremelyPoor), (0.1,.extremelyPoor,.veryPoor),
            (1,.veryPoor,.poor),(4,.poor,.fair),(10,.fair,.good),(40,.good,.veryGood)]
        for (boundary, lower, upper) in transitions {
            XCTAssertEqual(QRockClass.classify(boundary.nextDown), lower)
            XCTAssertEqual(QRockClass.classify(boundary), upper)
            XCTAssertEqual(QRockClass.classify(boundary.nextUp), upper)
        }
        XCTAssertEqual(QRockClass.classify(0.001), .exceptionallyPoor)
        XCTAssertNil(QRockClass.classify(0.001.nextDown)); XCTAssertNil(QRockClass.classify(1000.0.nextUp))
        for value in [40.0, 100, 400, 1000] { XCTAssertEqual(QRockClass.classify(value), .veryGood) }
        for value in [0.0, -1, Double.nan, Double.infinity] { XCTAssertNil(QRockClass.classify(value)) }
    }
    func testAllCompatibleTableCombinationsProducePositiveFiniteQ() throws {
        for contact in QContact.allCases {
            for ja in QMethod.rows(.ja).filter({ $0.contact == contact }) {
                for jr in QMethod.rows(.jr).filter({ ($0.id == "H") == (contact == .noContact) }) {
                    var input = q(); input.contact = contact
                    input.ja.select(ja.id, parameter: .ja); input.ja.value = ElevationInput.text(ja.maximum); input.ja.evidence = "Acceptance range endpoint"
                    input.jr.select(jr.id, parameter: .jr)
                    let value = try result(input); XCTAssertTrue(value.value.isFinite); XCTAssertGreaterThan(value.value, 0)
                }
            }
        }
    }
    func testRMR89RemainsInputOnlyEvenWithCompleteInputs() throws {
        var input = RMR89Input(); input.strengthTest = .pointLoadIs50; input.strengthMPa = "8,123456789"
        input.strengthEvidence = "Is50 lab report, validity and correction provided by laboratory"
        input.rqd = "0"; input.rqdEvidence = "Raw core log"; input.spacingMeters = "0.3"
        input.persistenceMeters = "2"; input.apertureMillimeters = "0"; input.roughness = "Slightly rough"
        input.infill = "None"; input.weathering = "Slight"; input.groundwater = "Wet"
        input.application = .tunnelsAndMines; input.orientationDescription = "Against drive, 60 degrees, true north"; input.source = "Field notebook"
        var whitespaceWater = input
        whitespaceWater.groundwater = " \n"; whitespaceWater.inflowLitersPerMinutePer10m = "  "; whitespaceWater.waterPressureRatio = "\t"
        XCTAssertTrue(whitespaceWater.missing.contains("Подземные воды"))
        let saved = try RMR89Assessment(input: input, now: now); try saved.validate()
        XCTAssertTrue(saved.missing.isEmpty); XCTAssertEqual(saved.input.rqd, "0") // Q floor must never modify RMR.
        XCTAssertEqual(saved.input.strengthMPa, "8,123456789")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(saved), encoding: .utf8))
        XCTAssertFalse(json.contains("rating")); XCTAssertFalse(json.contains("result")); XCTAssertFalse(json.contains("basicRMR"))
        for key in [\RMR89Input.strengthMPa, \.spacingMeters, \.persistenceMeters, \.apertureMillimeters, \.inflowLitersPerMinutePer10m, \.waterPressureRatio] {
            var invalid = input; invalid[keyPath: key] = "-1"; XCTAssertThrowsError(try invalid.validate())
            invalid[keyPath: key] = "NaN"; XCTAssertThrowsError(try invalid.validate())
        }
    }
    func testSaveTogetherResetRetainsContextAndNominalHorizonZ() throws {
        let (store, initial) = try P2MappingTests().configured(); var workflow = initial
        let context = workflow.context
        workflow.draft.picket = "5"; workflow.draft.bartonQ = q("0,125")
        workflow.draft.rmr89.groundwater = "Damp, field notebook"
        workflow.draft.addJointSet(); workflow.draft.jointSets[0].representative = ManualOrientationInput(dipAngleText: "45", dipDirectionText: "120", reference: .trueNorth)
        let reading = try ManualOrientationInput(dipAngleText: "35", dipDirectionText: "100", reference: .gridNorth).observation(notes: "Original")
        try workflow.draft.addMeasurement(reading)
        let point = try workflow.save(now: now)
        XCTAssertEqual(point.ratings?.bartonQ?.input.rqd, "0,125"); XCTAssertEqual(point.ratings?.bartonQ?.evaluation.result?.calculationRQD, 10)
        XCTAssertEqual(point.geology?.jointSets.count, 1); XCTAssertEqual(point.measurementIDs, [reading.id])
        XCTAssertEqual(workflow.context, context); XCTAssertFalse(workflow.draft.hasChanges)
        XCTAssertEqual(workflow.draft.z, "393"); XCTAssertEqual(workflow.draft.bartonQ, BartonQInput()); XCTAssertEqual(workflow.draft.rmr89, RMR89Input())
        let reopened = try MappingWorkflow(store: store); XCTAssertEqual(reopened.observations, [point])
        workflow.draft.picket = "10"; let second = try workflow.save(now: now)
        XCTAssertNil(second.ratings); XCTAssertNil(second.geology)
    }
    func testWriteAndValidationFailurePreserveWholeDraftAndRetry() throws {
        let (store, initial) = try P2MappingTests().configured(); var workflow = initial
        workflow.draft.picket = "5"; workflow.draft.bartonQ = q(); workflow.draft.rmr89.source = "Partial"
        let draft = workflow.draft, graph = workflow.journal
        store.fail = true; XCTAssertThrowsError(try workflow.save(now: now))
        XCTAssertEqual(workflow.draft, draft); XCTAssertEqual(workflow.journal, graph)
        store.fail = false; workflow.draft.bartonQ.srf.value = "0"
        let bad = workflow.draft; XCTAssertThrowsError(try workflow.save(now: now)); XCTAssertEqual(workflow.draft, bad)
        workflow.draft = draft; XCTAssertNoThrow(try workflow.save(now: now))
    }
    func testPartialRatingsCanBeSavedAndOnlyRatingsGuardContextChange() throws {
        let (store, initial) = try P2MappingTests().configured(); var workflow = initial
        workflow.draft.bartonQ.missingReason = "Water pressure not observed yet"
        let draft = workflow.draft
        try workflow.requestContext(MappingContext()); XCTAssertNotNil(workflow.pendingContext)
        workflow.cancelContextChange(); XCTAssertEqual(workflow.draft, draft)
        workflow.draft.picket = "5"; let point = try workflow.save(now: now)
        XCTAssertNil(point.ratings?.bartonQ?.evaluation.result); XCTAssertFalse(point.ratings!.bartonQ!.evaluation.missing.isEmpty)
        XCTAssertEqual(try MappingWorkflow(store: store).observations, [point])
        workflow.draft.rmr89.application = .tunnelsAndMines
        try workflow.requestContext(MappingContext()); XCTAssertNotNil(workflow.pendingContext)
    }
    func testSchema4MigrationPreservesExactBackupAndHistoricalGeologyEvidenceAndPlans() throws {
        try withDirectory { dir in
            let (_, initial) = try P2MappingTests().configured(); var old = initial
            old.draft.picket = "5"; old.draft.startPicket = "0"; old.draft.endPicket = "10"
            let reading = try ManualOrientationInput(dipAngleText: "35", dipDirectionText: "100", reference: .trueNorth).observation(notes: "Original")
            try old.draft.addMeasurement(reading)
            old.draft.addJointSet()
            old.draft.jointSets[0].representative = ManualOrientationInput(dipAngleText: "55,123456789", dipDirectionText: "360", reference: .gridNorth)
            old.draft.jointSets[0].measurementIDs = [reading.id]
            old.draft.jointSets[0].roughness = "Original field text, not a coefficient"
            var fault = TectonicStructureDraft(); fault.orientation = ManualOrientationInput(dipAngleText: "63,125", reference: .trueNorth)
            fault.description = "Legacy dip-only fault"; old.draft.tectonicStructures = [fault]
            let point = try old.save(now: now)
            var legacy = old.journal; legacy.schemaVersion = 4
            let original = try JSONEncoder().encode(legacy), url = dir.appendingPathComponent("mapping-v1.json")
            try original.write(to: url)
            let store = FileMappingStore(url: url); var reopened = try MappingWorkflow(store: store)
            XCTAssertEqual(reopened.journal.schemaVersion, 5); XCTAssertEqual(reopened.observations, [point])
            XCTAssertEqual(reopened.journal.measurements, [reading]); XCTAssertEqual(reopened.journal.plans, legacy.plans)
            XCTAssertNil(reopened.observations[0].ratings)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("p4-backup")), original)
            reopened.draft.picket = "10"; reopened.draft.bartonQ = q(); let second = try reopened.save(now: now)
            let again = try MappingWorkflow(store: FileMappingStore(url: url)); XCTAssertEqual(again.observations, [point, second])
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("p4-backup")), original)
        }
    }
    func testTamperedResultVersionAndInvalidInputsFailClosedWithoutReset() throws {
        try withDirectory { dir in
            let (_, initial) = try P2MappingTests().configured(); var workflow = initial
            workflow.draft.picket = "5"; workflow.draft.bartonQ = q(); workflow.draft.rmr89.source = "Unverified RMR input"
            _ = try workflow.save(now: now)
            let original = try JSONEncoder().encode(workflow.journal)
            let graph = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            for alteration in ["value", "method", "srf", "rmr"] {
                var changed = graph, observations = changed["observations"] as! [[String: Any]], point = observations[0]
                var ratings = point["ratings"] as! [String: Any], q = ratings["bartonQ"] as! [String: Any]
                if alteration == "value" {
                    var evaluation = q["evaluation"] as! [String: Any], result = evaluation["result"] as! [String: Any]
                    result["value"] = 999; evaluation["result"] = result; q["evaluation"] = evaluation
                } else if alteration == "method" { q["method"] = "Q-1974-unverified" }
                else if alteration == "srf" {
                    var input = q["input"] as! [String: Any], srf = input["srf"] as! [String: Any]
                    srf["value"] = "0"; input["srf"] = srf; q["input"] = input
                } else {
                    var rmr = ratings["rmr89"] as! [String: Any]; rmr["method"] = "RMR14"; ratings["rmr89"] = rmr
                }
                ratings["bartonQ"] = q; point["ratings"] = ratings; observations[0] = point; changed["observations"] = observations
                let bytes = try JSONSerialization.data(withJSONObject: changed), url = dir.appendingPathComponent(alteration + ".json")
                try bytes.write(to: url); let store = FileMappingStore(url: url)
                XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(MappingJournal()))
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }
    func testRatingsAreAppendOnlyAndFailedMigrationLeavesOriginalBytes() throws {
        try withDirectory { dir in
            let (_, initial) = try P2MappingTests().configured(); var workflow = initial
            workflow.draft.picket = "5"; workflow.draft.bartonQ = q(); _ = try workflow.save(now: now)
            let url = dir.appendingPathComponent("ratings.json"), store = FileMappingStore(url: url)
            _ = try store.load(); try store.save(workflow.journal)
            var modified = workflow.journal; modified.observations[0].ratings = nil
            XCTAssertThrowsError(try store.save(modified)); XCTAssertEqual(try store.load(), workflow.journal)
            var legacy = workflow.journal; legacy.observations[0].ratings = nil; legacy.schemaVersion = 4
            let bytes = try JSONEncoder().encode(legacy), legacyURL = dir.appendingPathComponent("legacy.json")
            try bytes.write(to: legacyURL); try Data("Different backup".utf8).write(to: legacyURL.appendingPathExtension("p4-backup"))
            let migration = FileMappingStore(url: legacyURL); XCTAssertThrowsError(try migration.load())
            XCTAssertThrowsError(try migration.save(MappingJournal())); XCTAssertEqual(try Data(contentsOf: legacyURL), bytes)
        }
    }
}
