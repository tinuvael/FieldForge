import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
private typealias GeologicalOriginal = FieldForgeCore.Measurement
#else
@testable import FieldForge
private typealias GeologicalOriginal = FieldForge.Measurement
#endif

final class P32GeologyTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000.123456)
    private func original(_ reference: GeographicReference = .magneticNorth) throws -> GeologicalOriginal {
        try ManualOrientationInput(dipAngleText: "41.123456789", dipDirectionText: "359.25", reference: reference)
            .observation(notes: "Original", timestamp: date)
    }
    private func set(_ identifier: JointSetIdentifier = .J1) -> JointSetDraft {
        var value = JointSetDraft(identifier: identifier)
        value.representative = ManualOrientationInput(dipAngleText: "46,123456789", dipDirectionText: "360", reference: .gridNorth)
        value.spacing = "0,25"; value.persistence = "12.125"; value.aperture = "0.0123456789"
        value.roughness = "Undulating"; value.infill = "Clay"; value.notes = "Interpretation"; value.author = "Engineer"
        return value
    }
    private func structure() -> TectonicStructureDraft {
        var value = TectonicStructureDraft()
        value.orientation = ManualOrientationInput(dipAngleText: "65", dipDirectionText: "120", reference: .trueNorth)
        value.thickness = "0,5"; value.picket = "ПК 0+007"; value.position = "Left side"; value.description = "Fault trace"
        return value
    }
    private func directory(_ body: (URL) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path)
    }
    func testFiveSetsMultipleEvidenceReferencesAndTectonicsCommitTogether() throws {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        let first = try original(), second = try original(.trueNorth)
        try w.draft.addMeasurement(first); try w.draft.addMeasurement(second)
        w.draft.picket = "ПК 0+005"; w.draft.startPicket = "5"; w.draft.endPicket = "10,125"; w.draft.observationPosition = .roof
        w.draft.jointSets = JointSetIdentifier.allCases.map { set($0) }
        w.draft.jointSets[0].measurementIDs = [first.id, second.id]
        w.draft.jointSets[1].measurementIDs = [first.id] // Evidence may support several interpretations at the same point.
        w.draft.tectonicStructures = [structure(), structure()]
        w.draft.tectonicStructures[1].type = .shearZone
        XCTAssertTrue(store.value.observations.isEmpty); XCTAssertTrue(store.value.measurements.isEmpty)
        let point = try w.save(now: date)
        let geology = try XCTUnwrap(point.geology)
        XCTAssertEqual(geology.jointSets.map(\.identifier), JointSetIdentifier.allCases)
        XCTAssertEqual(geology.jointSets[0].measurementIDs, [first.id, second.id])
        XCTAssertEqual(geology.jointSets[0].representative.reference, .gridNorth)
        XCTAssertEqual(geology.jointSets[0].representative.dipAngleText, "46,123456789")
        XCTAssertEqual(try geology.jointSets[0].representative.validated().orientation.dipDirection, 0)
        XCTAssertEqual(geology.jointSets[0].spacingMeters, 0.25)
        XCTAssertEqual(geology.jointSets[0].apertureMillimeters, 0.0123456789)
        XCTAssertEqual(geology.jointSets[0].interpretedAt, date); XCTAssertEqual(geology.jointSets[0].revision, 1)
        XCTAssertEqual(geology.tectonicStructures.count, 2); XCTAssertEqual(geology.tectonicStructures[1].type, .shearZone)
        XCTAssertEqual(geology.tectonicStructures[0].picket?.meters, 7)
        XCTAssertEqual(geology.start?.meters, 5); XCTAssertEqual(geology.end?.meters, 10.125); XCTAssertEqual(geology.position, .roof)
        XCTAssertEqual(w.journal.measurements(for: point), [first, second])
        XCTAssertEqual(try MappingWorkflow(store: store).observations, [point])
    }
    func testReadingsNeverBecomeSetsAndRepresentativesStartBlank() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        for _ in 0..<5 { try w.draft.addMeasurement(original()) }
        XCTAssertTrue(w.draft.jointSets.isEmpty)
        for _ in 0..<6 { w.draft.addJointSet() }
        XCTAssertEqual(w.draft.jointSets.count, 5)
        XCTAssertTrue(w.draft.jointSets.allSatisfy { $0.representative.dipAngleText.isEmpty && $0.measurementIDs.isEmpty })
        w.draft.jointSets.remove(at: 1); w.draft.addJointSet()
        XCTAssertEqual(w.draft.jointSets.map(\.identifier), JointSetIdentifier.allCases)
        w.draft.picket = "5"; XCTAssertThrowsError(try w.save()) // No invented representative.
    }
    func testInvalidNumericFieldsRejectWithoutChangingDraftOrGraph() throws {
        let (_, initial) = try P2MappingTests().configured()
        let fields: [WritableKeyPath<JointSetDraft, String>] = [\.spacing, \.persistence, \.aperture]
        for field in fields {
            for invalid in ["-0.1", "NaN", "inf", "1e6", "one", "1,2.3"] {
                var w = initial; w.draft.picket = "5"; w.draft.jointSets = [set()]
                w.draft.jointSets[0][keyPath: field] = invalid
                let draft = w.draft, graph = w.journal
                XCTAssertThrowsError(try w.save(), invalid); XCTAssertEqual(w.draft, draft); XCTAssertEqual(w.journal, graph)
            }
        }
        for invalid in ["-1", "inf", "NaN", "1.2.3"] {
            var w = initial; w.draft.picket = "5"; w.draft.tectonicStructures = [structure()]
            w.draft.tectonicStructures[0].thickness = invalid
            XCTAssertThrowsError(try w.save())
        }
    }
    func testOrientationValidationNorthAndDegenerateConventionsApplyToSetsAndStructures() throws {
        let invalid = [ManualOrientationInput(dipAngleText: "91", dipDirectionText: "30"),
                       ManualOrientationInput(dipAngleText: "NaN", dipDirectionText: "30"),
                       ManualOrientationInput(dipAngleText: "45", dipDirectionText: "361"),
                       ManualOrientationInput(dipAngleText: "45", dipDirectionText: ""),
                       ManualOrientationInput(dipAngleText: "0", dipDirectionText: "30"),
                       ManualOrientationInput(dipAngleText: "90", dipDirectionText: "30"),
                       ManualOrientationInput(dipAngleText: "45", dipDirectionText: "30", reference: .simulatedNorth)]
        for input in invalid {
            var joint = set(); joint.representative = input; XCTAssertThrowsError(try joint.record(now: date))
            var tectonic = structure(); tectonic.orientation = input
            if input.dipAngleText == "45" && input.dipDirectionText.isEmpty {
                XCTAssertNoThrow(try tectonic.record()) // Tectonic partials differ from representative sets/originals.
            } else { XCTAssertThrowsError(try tectonic.record()) }
        }
        for reference in GeographicReference.manualChoices {
            var joint = set(); joint.representative.reference = reference
            XCTAssertEqual(try joint.record(now: date).representative.reference, reference)
        }
        for input in [ManualOrientationInput(dipAngleText: "0", dipDirectionText: ""),
                      ManualOrientationInput(dipAngleText: "90", dipDirectionText: ""),
                      ManualOrientationInput(dipAngleText: "90", dipDirectionText: "180", usesConventionalDipSide: true)] {
            var joint = set(); joint.representative = input; XCTAssertNoThrow(try joint.record(now: date))
            var tectonic = structure(); tectonic.orientation = input; XCTAssertNoThrow(try tectonic.record())
        }
    }
    func testTectonicAnglesMayBeMissingIndependentlyWithoutSynthesizingValues() throws {
        for reference in GeographicReference.manualChoices {
            for (dip, direction, expectedDip, expectedDirection) in [
                ("", "", nil as Double?, nil as Double?), (" \n", "\t", nil, nil),
                ("0", "", 0, nil), ("90", "", 90, nil), ("45,123456789", "", 45.123456789, nil),
                ("", "0", nil, 0), ("", "360", nil, 360), ("", "120,123456789", nil, 120.123456789),
                ("65", "120", 65, 120)
            ] {
                var draft = structure()
                draft.orientation = ManualOrientationInput(dipAngleText: dip, dipDirectionText: direction, reference: reference)
                let record = try draft.record(), values = try record.orientation.validatedTectonic()
                XCTAssertEqual(values.dipAngle, expectedDip); XCTAssertEqual(values.dipDirection, expectedDirection)
                XCTAssertEqual(record.orientation, draft.orientation) // Exact text/north retained, including 360°.
                XCTAssertEqual(record.thicknessMeters, 0.5); XCTAssertEqual(record.picket?.meters, 7)
                XCTAssertEqual(record.position, draft.position); XCTAssertEqual(record.description, draft.description)
                XCTAssertNoThrow(try record.validate())
            }
        }
        // These permissive rules must never leak into measured originals or J1–J5 representatives.
        for input in [ManualOrientationInput(), ManualOrientationInput(dipAngleText: "45"),
                      ManualOrientationInput(dipDirectionText: "120")] {
            XCTAssertThrowsError(try input.observation())
            var joint = set(); joint.representative = input; XCTAssertThrowsError(try joint.record(now: date))
        }
    }
    func testInvalidPartialTectonicAnglesRetainDraftGraphAndOriginals() throws {
        let (_, initial) = try P2MappingTests().configured()
        var invalid: [ManualOrientationInput] = []
        for value in ["-1", "90.01", "NaN", "inf", "one", "1,2.3"] {
            invalid.append(ManualOrientationInput(dipAngleText: value))
        }
        for value in ["-1", "360.01", "NaN", "inf", "one", "1,2.3"] {
            invalid.append(ManualOrientationInput(dipDirectionText: value))
        }
        invalid += [ManualOrientationInput(reference: .simulatedNorth), ManualOrientationInput(reference: .unavailable),
                    ManualOrientationInput(usesConventionalDipSide: true),
                    ManualOrientationInput(dipAngleText: "90", usesConventionalDipSide: true)]
        for input in invalid {
            var w = initial; w.draft.picket = "5"; try w.draft.addMeasurement(original())
            var draft = structure(); draft.orientation = input; w.draft.tectonicStructures = [draft]
            let before = w.draft, journal = w.journal
            XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, before); XCTAssertEqual(w.journal, journal)
        }
    }
    func testUnknownAndPartialTectonicsRetainAllFieldsOnWriteFailureThenReset() throws {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        w.draft.picket = "5"; try w.draft.addMeasurement(original())
        for input in [ManualOrientationInput(), ManualOrientationInput(dipAngleText: "45"), ManualOrientationInput(dipDirectionText: "120", reference: .gridNorth)] {
            var value = structure(); value.orientation = input; w.draft.tectonicStructures.append(value)
        }
        let before = w.draft, journal = w.journal
        store.fail = true; XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, before); XCTAssertEqual(w.journal, journal)
        store.fail = false; let point = try w.save(now: date)
        XCTAssertEqual(point.geology?.tectonicStructures.map(\.orientation), before.tectonicStructures.map(\.orientation))
        XCTAssertEqual(w.journal.measurements, before.measurements)
        XCTAssertTrue(w.draft.tectonicStructures.isEmpty); XCTAssertFalse(w.draft.hasChanges)
    }
    @MainActor func testSchema4CompleteTectonicFixtureAndPartialRecordsReopenWithoutMigration() async throws {
        // Literal wire format emitted by the previous PR #17 model, not a newly encoded stand-in.
        let legacyBytes = Data("""
        {"id":"8BE4947A-61A3-4288-98C2-1CC17CDB73F8","type":"fault",
         "orientation":{"dipAngleText":"65","dipDirectionText":"120","reference":"trueNorth","usesConventionalDipSide":false},
         "thicknessMeters":0.5,"picket":{"text":"ПК 0+007","meters":7},"position":"Left side","description":"Fault trace"}
        """.utf8)
        let legacy = try JSONDecoder().decode(TectonicStructure.self, from: legacyBytes)
        try legacy.validate(); XCTAssertEqual(legacy.orientation.reference, .trueNorth)
        try directory { dir in
            let (_, initial) = try P2MappingTests().configured(); var w = initial
            try w.draft.addMeasurement(original())
            var sample = MockSensorProvider.sample(dip: 60, direction: 270, timestamp: date)
            sample.source = .coreMotion; sample.referenceFrame = .magneticNorthZVertical
            sample.magneticAccuracy = .high; sample.magneticField.x = 40
            let sensor = GeologicalOriginal.process(sample); try w.draft.addMeasurement(sensor)
            w.draft.picket = "5"; w.draft.tectonicStructures = [structure()]
            _ = try w.save(now: date)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w.journal)) as? [String: Any])
            var points = try XCTUnwrap(json["observations"] as? [[String: Any]])
            var geology = try XCTUnwrap(points[0]["geology"] as? [String: Any])
            geology["tectonicStructures"] = [try JSONSerialization.jsonObject(with: legacyBytes)]
            points[0]["geology"] = geology; json["observations"] = points
            let bytes = try JSONSerialization.data(withJSONObject: json), url = dir.appendingPathComponent("mapping.json")
            try bytes.write(to: url)
            var reopened = try MappingWorkflow(store: FileMappingStore(url: url))
            let oldJournal = reopened.journal
            XCTAssertEqual(oldJournal.schemaVersion, 6)
            XCTAssertEqual(oldJournal.observations[0].geology?.tectonicStructures, [legacy])
            XCTAssertEqual(try Data(contentsOf: url), bytes) // Opening the current schema with legacy-shaped tectonic records does not rewrite it.
            reopened.draft.picket = "10"
            for input in [ManualOrientationInput(), ManualOrientationInput(dipAngleText: "45,25", reference: .trueNorth),
                          ManualOrientationInput(dipDirectionText: "360", reference: .gridNorth)] {
                var value = structure(); value.orientation = input; value.type = .fractureZone
                reopened.draft.tectonicStructures.append(value)
            }
            let newPoint = try reopened.save(now: date)
            let again = try FileMappingStore(url: url).load()
            XCTAssertEqual(again.schemaVersion, 6); XCTAssertEqual(again.observations, oldJournal.observations + [newPoint])
            XCTAssertEqual(again.measurements, oldJournal.measurements)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["mapping.json", "mapping.json.previous"])
        }
    }
    func testOptionalFieldsRemainMissingAndTectonicsHaveNoCountLimit() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        w.draft.picket = "5"; w.draft.addJointSet(); w.draft.jointSets[0].representative = set().representative
        var tectonic = structure(); tectonic.thickness = ""; tectonic.picket = ""; tectonic.position = ""; tectonic.description = ""
        w.draft.tectonicStructures = (0..<40).map { _ in
            var new = TectonicStructureDraft(); new.orientation = tectonic.orientation; return new
        }
        let geology = try XCTUnwrap(w.save().geology)
        XCTAssertEqual(geology.tectonicStructures.count, 40)
        XCTAssertTrue(geology.tectonicStructures.allSatisfy { $0.thicknessMeters == nil && $0.picket == nil })
        XCTAssertNil(geology.jointSets[0].spacingMeters); XCTAssertNil(geology.jointSets[0].persistenceMeters)
        XCTAssertNil(geology.jointSets[0].apertureMillimeters); XCTAssertNil(geology.jointSets[0].author)
        XCTAssertNil(geology.start); XCTAssertNil(geology.end); XCTAssertNil(geology.position)
    }
    func testIntervalsAreOptionalIndependentAndValidated() throws {
        let (_, initial) = try P2MappingTests().configured()
        for (start, end, valid) in [("", "", true), ("5", "", true), ("", "10", true), ("5", "5", true),
                                    ("5", "10", true), ("10", "5", false), ("-1", "", false), ("", "NaN", false)] {
            var w = initial; w.draft.picket = "5"; w.draft.startPicket = start; w.draft.endPicket = end
            if valid { XCTAssertNoThrow(try w.save()) } else { XCTAssertThrowsError(try w.save()) }
        }
        for position in ObservationPosition.allCases {
            var w = initial; w.draft.picket = "5"; w.draft.observationPosition = position
            XCTAssertEqual(try w.save().geology?.position, position)
        }
        var tectonic = structure(); tectonic.picket = "1+05"; XCTAssertThrowsError(try tectonic.record())
    }
    func testMissingForeignDuplicateEvidenceAndDuplicateSetsRejected() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        try w.draft.addMeasurement(original()); w.draft.picket = "5"; let old = try w.save()
        w.draft.picket = "10"; w.draft.jointSets = [set()]
        w.draft.jointSets[0].measurementIDs = old.measurementIDs
        XCTAssertThrowsError(try w.save())
        let reading = try original(); try w.draft.addMeasurement(reading)
        w.draft.jointSets[0].measurementIDs = [reading.id, reading.id]; XCTAssertThrowsError(try w.save())
        w.draft.jointSets[0].measurementIDs = [UUID()]; XCTAssertThrowsError(try w.save())
        w.draft.jointSets = [set(), set()]; XCTAssertThrowsError(try w.save())
        w.draft.jointSets = JointSetIdentifier.allCases.map { set($0) } + [set()]; XCTAssertThrowsError(try w.save())
        w.draft.jointSets = [set()]; let tectonic = structure()
        w.draft.tectonicStructures = [tectonic, tectonic]; XCTAssertThrowsError(try w.save())
    }
    func testGeologicalUUIDsCannotBeReusedAcrossPoints() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let joint = set(), tectonic = structure()
        w.draft.picket = "5"; w.draft.jointSets = [joint]; _ = try w.save()
        w.draft.picket = "10"; w.draft.jointSets = [joint]; XCTAssertThrowsError(try w.save())
        w.draft.jointSets = []; w.draft.tectonicStructures = [tectonic]; _ = try w.save()
        w.draft.picket = "15"; w.draft.tectonicStructures = [tectonic]; XCTAssertThrowsError(try w.save())
    }
    func testDraftOriginalRemovalUnlinksOnlyAffectedEvidence() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let a = try original(), b = try original()
        try w.draft.addMeasurement(a); try w.draft.addMeasurement(b)
        var joint = set(); joint.measurementIDs = [a.id, b.id]; w.draft.jointSets = [joint]
        w.draft.removeMeasurement(id: a.id)
        XCTAssertEqual(w.draft.jointSets[0].measurementIDs, [b.id]); XCTAssertEqual(w.draft.measurements, [b])
        w.draft.picket = "5"; XCTAssertNoThrow(try w.save())
    }
    func testFailureKeepsCompleteDraftRetryResetsAndNextPointIsIndependent() throws {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        let context = w.context; try w.draft.addMeasurement(original())
        w.draft.picket = "5"; w.draft.startPicket = "5"; w.draft.endPicket = "10"; w.draft.observationPosition = .leftWall
        w.draft.jointSets = [set()]; w.draft.jointSets[0].measurementIDs = w.draft.measurements.map(\.id)
        w.draft.tectonicStructures = [structure(), structure()]; w.draft.notes = "Retain"; w.draft.z = "390"
        let draft = w.draft, journal = w.journal
        store.fail = true; XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft); XCTAssertEqual(w.journal, journal)
        XCTAssertTrue(store.value.measurements.isEmpty); XCTAssertTrue(store.value.observations.isEmpty)
        store.fail = false; let first = try w.save(now: date)
        var empty = MappingDraft(); empty.suggestElevation(w.selectedHorizon)
        XCTAssertEqual(w.draft, empty); XCTAssertEqual(w.context, context); XCTAssertFalse(w.draft.hasChanges)
        w.draft.picket = "10"; let second = try w.save(now: date.addingTimeInterval(1))
        XCTAssertNil(second.geology); XCTAssertTrue(second.measurementIDs.isEmpty); XCTAssertNotEqual(first.id, second.id)
    }
    func testGeologicalDraftsAloneGuardContextChanges() throws {
        let (_, initial) = try P2MappingTests().configured()
        for kind in 0..<5 {
            var w = initial
            switch kind {
            case 0: w.draft.jointSets = [set()]
            case 1: w.draft.tectonicStructures = [structure()]
            case 2: w.draft.startPicket = "5"
            case 3: w.draft.endPicket = "10"
            default: w.draft.observationPosition = .face
            }
            XCTAssertTrue(w.draft.hasChanges); let before = w.draft
            try w.requestContext(MappingContext()); XCTAssertNotNil(w.pendingContext)
            w.cancelContextChange(); XCTAssertEqual(w.draft, before)
            try w.requestContext(MappingContext()); try w.confirmDiscard(); XCTAssertFalse(w.draft.hasChanges)
        }
    }
    func testDiskReopenAppendOnlyAndExternalFailurePreserveEverything() throws {
        try directory { dir in
            let (memory, initial) = try P2MappingTests().configured(); var w = initial
            w.draft.picket = "5"; w.draft.jointSets = [set(.J1), set(.J3)]; w.draft.tectonicStructures = [structure(), structure()]
            w.draft.startPicket = "5"; w.draft.endPicket = "10"; w.draft.observationPosition = .rightWall
            let point = try w.save(now: date)
            let url = dir.appendingPathComponent("mapping.json"), store = FileMappingStore(url: dir.appendingPathComponent("mapping.json"))
            try store.save(memory.value)
            var reopened = try MappingWorkflow(store: store); XCTAssertEqual(reopened.observations, [point])
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened.journal)) as? [String: Any])
            var observations = try XCTUnwrap(json["observations"] as? [[String: Any]])
            observations[0].removeValue(forKey: "geology"); json["observations"] = observations
            let tampered = try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try store.save(tampered))
            reopened.draft.picket = "10"; reopened.draft.jointSets = [set()]
            let draft = reopened.draft, journal = reopened.journal
            let external = Data("external change".utf8); try external.write(to: url)
            XCTAssertThrowsError(try reopened.save()); XCTAssertEqual(reopened.draft, draft); XCTAssertEqual(reopened.journal, journal)
            XCTAssertEqual(try Data(contentsOf: url), external)
        }
    }
    func testP31UpgradeIsLosslessPreservingEvidenceDXFAndBackupBytes() throws {
        try directory { dir in
            let (_, initial) = try P2MappingTests().configured(); var w = initial
            let files = ManagedPlanStore(root: dir.appendingPathComponent("plans"))
            let plan = try files.stage(data: DXFFixtures.drawing(DXFFixtures.line), filename: "plan.dxf",
                horizonID: w.context.horizonID!, version: "A", units: .meters, crs: "local", axes: "X north Y east")
            try w.registerPlan(plan); files.complete(plan)
            try w.selectPlanPoint(PlanPoint(x: 123, y: 456), planID: plan.id)
            try w.draft.addMeasurement(original()); w.draft.picket = "5"; let old = try w.save(now: date)
            var graph = w.journal; graph.schemaVersion = 3
            let bytes = try JSONEncoder().encode(graph), url = dir.appendingPathComponent("mapping.json")
            try bytes.write(to: url)
            let store = FileMappingStore(url: url); var reopened = try MappingWorkflow(store: store)
            XCTAssertEqual(reopened.journal.schemaVersion, 6); XCTAssertEqual(reopened.observations, [old])
            XCTAssertEqual(reopened.journal.measurements, graph.measurements); XCTAssertEqual(reopened.journal.plans, [plan])
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("p3-backup")), bytes)
            XCTAssertNoThrow(try files.read(plan))
            reopened.draft.picket = "10"; reopened.draft.jointSets = [set()]
            try reopened.selectPlanPoint(PlanPoint(x: 125, y: 460), planID: plan.id)
            XCTAssertEqual(reopened.draft.jointSets.count, 1)
            _ = try reopened.save(); let again = try FileMappingStore(url: url).load()
            XCTAssertEqual(again.observations.first, old); XCTAssertEqual(again.observations.count, 2)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("p3-backup")), bytes)
            XCTAssertNoThrow(try files.read(plan))
        }
    }
    func testP31ConflictingBackupAndCorruptionFailClosedWithoutReset() throws {
        try directory { dir in
            var graph = MappingJournal(); graph.schemaVersion = 3
            let bytes = try JSONEncoder().encode(graph), url = dir.appendingPathComponent("mapping.json")
            try bytes.write(to: url); try Data("conflict".utf8).write(to: url.appendingPathExtension("p3-backup"))
            let store = FileMappingStore(url: url)
            XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(MappingJournal()))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        try directory { dir in
            let (_, initial) = try P2MappingTests().configured(); var w = initial
            w.draft.picket = "5"; w.draft.jointSets = [set()]; _ = try w.save()
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w.journal)) as? [String: Any])
            var observations = try XCTUnwrap(json["observations"] as? [[String: Any]])
            var geology = try XCTUnwrap(observations[0]["geology"] as? [String: Any])
            geology["jointSets"] = [["invalid": true]]; observations[0]["geology"] = geology; json["observations"] = observations
            let bytes = try JSONSerialization.data(withJSONObject: json), url = dir.appendingPathComponent("mapping.json")
            try bytes.write(to: url); let store = FileMappingStore(url: url)
            XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(MappingJournal()))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
}
