import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
private typealias OriginalReading = FieldForgeCore.Measurement
#else
@testable import FieldForge
private typealias OriginalReading = FieldForge.Measurement
#endif

@MainActor final class ThirdIPhoneReviewTests: XCTestCase {
    private func reading(dip: Double = 48.123456789, direction: Double = 132.412345678) throws -> OriginalReading {
        var sample = MockSensorProvider.sample(dip: dip, direction: direction, timestamp: Date())
        sample.source = .coreMotion; sample.referenceFrame = .magneticNorthZVertical
        sample.magneticAccuracy = .high; sample.magneticField.x = 40
        let reading = OriginalReading.process(sample)
        XCTAssertTrue(reading.isSavable)
        return reading
    }
    func testMeasuredJ1ThroughJ5AcceptSaveAndReopenImmutableOriginals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (memory, _) = try P2MappingTests().configured()
        let store = FileMappingStore(url: directory.appendingPathComponent("mapping.json"))
        try store.save(memory.value)
        var workflow = try MappingWorkflow(store: store)
        workflow.draft.picket = "12,18"
        var readings: [OriginalReading] = []
        for identifier in JointSetIdentifier.allCases {
            let request = workflow.editorRequest(JointSetDraft(identifier: identifier))
            let original = try reading(); readings.append(original)
            var staged = request.initial
            staged.representative = try JointRepresentativeInput.make(from: original)
            staged.measurementIDs = [original.id]
            // A nested sensor presentation can redraw the parent; its request is unchanged.
            workflow.draft.notes = "Preserve edits while presented"
            try workflow.acceptJointSet(staged, originals: [original], request: request)
            XCTAssertEqual(workflow.draft.id, request.draftID)
            XCTAssertEqual(workflow.draft.jointSets.last?.representative, staged.representative)
        }
        let saved = try workflow.save()
        XCTAssertEqual(saved.picket, "ПК 12+1,8"); XCTAssertEqual(saved.chainageMeters, 121.8)
        let reopened = try MappingWorkflow(store: FileMappingStore(url: store.url))
        XCTAssertEqual(reopened.journal.measurements(for: saved), readings)
        let sets = try XCTUnwrap(reopened.observations.first?.geology?.jointSets)
        XCTAssertEqual(sets.map(\.identifier), JointSetIdentifier.allCases)
        for (set, original) in zip(sets, readings) {
            XCTAssertEqual(set.measurementIDs, [original.id])
            XCTAssertEqual(try set.representative.validated().orientation.dipAngle, original.orientation.dipAngle)
            XCTAssertEqual(try set.representative.validated().orientation.dipDirection, original.orientation.dipDirection)
            XCTAssertNotNil(original.sample)
        }
    }
    func testEditorCancellationRetakeAndAtomicFailures() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let request = w.editorRequest(JointSetDraft(identifier: .J1)), original = try reading()
        var accepted = request.initial
        accepted.representative = try JointRepresentativeInput.make(from: original); accepted.measurementIDs = [original.id]
        try w.acceptJointSet(accepted, originals: [original], request: request)
        let baseline = w.draft
        let editing = w.editorRequest(accepted)
        var local = editing.initial
        local.representative = try JointRepresentativeInput.make(from: reading(dip: 60, direction: 200))
        // Cancel/retake remains local and never replaces an accepted orientation.
        XCTAssertEqual(w.draft, baseline)
        var invalid = local; invalid.measurementIDs.append(UUID())
        let extra = try reading()
        XCTAssertThrowsError(try w.acceptJointSet(invalid, originals: [extra], request: editing))
        XCTAssertEqual(w.draft, baseline)
        XCTAssertThrowsError(try w.acceptJointSet(local, originals: [original], request: editing))
        XCTAssertEqual(w.draft, baseline)
        var duplicate = JointSetDraft(identifier: .J1); duplicate.representative = accepted.representative
        XCTAssertThrowsError(try w.acceptJointSet(duplicate, originals: [], request: w.editorRequest(duplicate)))
        XCTAssertEqual(w.draft, baseline)
        w.draft.saving = true
        XCTAssertThrowsError(try w.acceptJointSet(local, originals: [], request: editing))
        w.draft.saving = false
        let other = try w.createProject(name: "Other")
        try w.requestContext(MappingContext(projectID: other))
        XCTAssertThrowsError(try w.acceptJointSet(local, originals: [], request: editing))
        w.cancelContextChange(); w.draft.picket = "1"; _ = try w.save()
        let next = w.draft
        XCTAssertThrowsError(try w.acceptJointSet(local, originals: [extra], request: editing))
        XCTAssertEqual(w.draft, next)
    }
    func testInvalidRepresentativeKeepsOnlyExplicitlyAcceptedIndependentEvidence() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let demo = OriginalReading.process(MockSensorProvider.sample(dip: 48, direction: 132, timestamp: Date()))
        XCTAssertTrue(demo.isSavable)
        XCTAssertThrowsError(try JointRepresentativeInput.make(from: demo))
        let request = w.editorRequest(JointSetDraft(identifier: .J1))
        XCTAssertTrue(w.draft.measurements.isEmpty)
        try w.acceptJointSet(nil, originals: [demo], request: request)
        XCTAssertEqual(w.draft.measurements, [demo]); XCTAssertTrue(w.draft.jointSets.isEmpty)
        w.draft.picket = "1"; let saved = try w.save()
        XCTAssertEqual(w.journal.measurements(for: saved), [demo])
    }
    func testCompatibilityRejectsDanglingAndCyclicDeclarations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, w) = try P2MappingTests().configured()
        var first = try plan(directory, w, version: "1")
        let second = try plan(directory, w, version: "2", previous: first)
        first.frameConfirmation = PlanFrameConfirmation(previousPlanID: second.id, confirmedAt: Date())
        XCTAssertThrowsError(try PlanCoordinateCompatibility.validate([first,second]))
        first.frameConfirmation = PlanFrameConfirmation(previousPlanID: UUID(), confirmedAt: Date())
        XCTAssertThrowsError(try PlanCoordinateCompatibility.validate([first]))
    }
    func testTectonicOwnershipAndHistoricalPositionPreserved() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        var structure = TectonicStructureDraft(); structure.thickness = "0,7"
        structure.picketConvention = .legacyMeters; structure.picket = "ПК 0+007"; structure.position = "Historical trace"
        let request = w.editorRequest(structure)
        try w.acceptTectonic(structure, request: request)
        let before = w.draft
        var invalid = structure; invalid.thickness = "-1"
        XCTAssertThrowsError(try w.acceptTectonic(invalid, request: request)); XCTAssertEqual(w.draft, before)
        w.draft.picket = "1"; let saved = try w.save()
        XCTAssertEqual(saved.geology?.tectonicStructures.first?.picket?.meters, 7)
        XCTAssertEqual(saved.geology?.tectonicStructures.first?.position, structure.position)
        XCTAssertThrowsError(try w.acceptTectonic(structure, request: request))
    }
    func testDecimalPicketsCanonicalAndPreviousBinaryValueSurvivesNotesCorrection() async throws {
        for (text, meters, label) in [("1",10.0,"ПК 1"),("1,7",17,"ПК 1+7"),("12+9",129,"ПК 12+9"),
            ("12,18",121.8,"ПК 12+1,8"),("12.18",121.8,"ПК 12+1,8"),("12+1,8",121.8,"ПК 12+1,8"),
            ("0,01",0.1,"ПК 0+0,1"),("12+0",120,"ПК 12"),("0,000001",0.00001,"ПК 0+0,00001")] {
            XCTAssertEqual(try FieldPicketInput.meters(text), meters)
            XCTAssertEqual(try FieldPicketInput.canonical(text), label)
            XCTAssertEqual(try FieldPicketInput.meters(label), meters)
        }
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        w.draft.picket = "12,18"; _ = try w.save()
        // Decode an actual pre-normalization spelling and binary product.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w.journal)) as? [String: Any])
        var points = try XCTUnwrap(json["observations"] as? [[String: Any]])
        points[0]["picket"] = "12,18"; points[0]["chainageMeters"] = 12.18 * 10
        json["observations"] = points
        store.value = try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: json))
        try store.value.validate(); w = try MappingWorkflow(store: store)
        let original = try XCTUnwrap(w.observations.first)
        XCTAssertEqual(original.displayPicket, "ПК 12+1,8")
        var edit = try w.correction(for: original.id)
        edit.fields.notes = "Only notes"; edit.reason = "Field correction"
        let revision = try w.saveCorrection(edit)
        XCTAssertEqual(revision.snapshot.chainageMeters, original.chainageMeters)
        XCTAssertEqual(revision.snapshot.picket, original.picket)
        XCTAssertEqual(w.journal.observations, [original])
    }
    func testFieldQBoundariesRemainSeparateFromNGIClasses() async throws {
        for (q, expected) in [(0.0,FieldQCategory.veryUnstable),(0.001,FieldQCategory.veryUnstable),(0.999999,.veryUnstable),(1,.unstable),
            (3.999999,.unstable),(4,.medium),(10,.medium),(10.000001,.stable),(1001,.stable)] {
            XCTAssertEqual(FieldQCategory(q: q), expected)
        }
        XCTAssertNil(FieldQCategory(q: .nan)); XCTAssertNil(FieldQCategory(q: .infinity))
        XCTAssertEqual(EngineeringDisplay.orientationInput(132.412345678), "132,4")
        XCTAssertEqual(EngineeringDisplay.orientationInput(0.012345), "0")
        XCTAssertEqual(EngineeringDisplay.angle(0.012345), "0°")
        XCTAssertEqual(EngineeringDisplay.angle(359.9999, azimuth: true), "0°")
    }
    private func plan(_ directory: URL, _ workflow: MappingWorkflow, version: String, units: PlanUnits = .meters,
                      crs: String = "unknown", axes: String = "unknown", previous: MappingPlanReference? = nil) throws -> MappingPlanReference {
        try ManagedPlanStore(root: directory).stage(data: DXFFixtures.drawing(DXFFixtures.line), filename: "revision.dxf",
            horizonID: workflow.context.horizonID!, version: version, units: units, crs: crs, axes: axes,
            frameConfirmation: previous.map { PlanFrameConfirmation(previousPlanID: $0.id, confirmedAt: Date()) })
    }
    func testConfirmedCrossRevisionOverlayIsBidirectionalAndPreservesSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let first = try plan(directory, w, version: "1"); try w.registerPlan(first)
        try w.selectPlanPoint(PlanPoint(x: 123.456789, y: 789.123456), planID: first.id)
        w.draft.picket = "12,18"; let point = try w.save()
        let unknown = try plan(directory, w, version: "2"); try w.registerPlan(unknown)
        XCTAssertTrue(w.points(on: unknown).isEmpty)
        let second = try plan(directory, w, version: "3", previous: first); try w.registerPlan(second)
        XCTAssertEqual(w.points(on: second), [point]); XCTAssertEqual(w.points(on: first), [point])
        let excavation = try w.createExcavation(name: "Second", horizonIDs: [w.context.horizonID!])
        var context = w.context; context.excavationID = excavation; try w.requestContext(context)
        try w.selectPlanPoint(PlanPoint(x: 124, y: 790), planID: second.id); w.draft.picket = "13"
        let next = try w.save()
        XCTAssertEqual(Set(w.points(on: first).map(\.id)), Set([point.id,next.id]))
        XCTAssertEqual(w.journal.observations.first?.coordinates?.planID, first.id)
        let url = directory.appendingPathComponent("mapping.json")
        try FileMappingStore(url: url).save(w.journal)
        let reopened = try MappingWorkflow(store: FileMappingStore(url: url))
        XCTAssertEqual(Set(reopened.points(on: second).map(\.id)), Set([point.id,next.id]))
        XCTAssertEqual(try ManagedPlanStore(root: directory).read(first), DXFFixtures.drawing(DXFFixtures.line))
    }
    func testQualifiedMetadataAndIncompatibleFrames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let first = try plan(directory, w, version: "1", crs: "Mine frame A", axes: "X north Y east")
        try w.registerPlan(first)
        try w.selectPlanPoint(PlanPoint(x: 1, y: 2), planID: first.id); w.draft.picket = "1"; let saved = try w.save()
        let qualified = try plan(directory, w, version: "2", crs: "Mine frame A", axes: "X north Y east")
        try w.registerPlan(qualified); XCTAssertEqual(w.points(on: qualified), [saved])
        for (index, tuple) in [(PlanUnits.millimeters,"Mine frame A","X north Y east"),(.meters,"Mine frame B","X north Y east"),
            (.meters,"Mine frame A","X east Y north"),(.unknown,"Mine frame A","X north Y east")].enumerated() {
            let (units, crs, axes) = tuple
            let bad = try plan(directory,w,version:"bad-\(index)",units:units,crs:crs,axes:axes,previous:first)
            let before = w.journal
            XCTAssertThrowsError(try w.registerPlan(bad)); XCTAssertEqual(w.journal,before)
            var unlinked = bad; unlinked.frameConfirmation = nil
            try w.registerPlan(unlinked); XCTAssertTrue(w.points(on: unlinked).isEmpty)
        }
        let unknown = try plan(directory,w,version:"3",previous:first); try w.registerPlan(unknown)
        let contradiction = try plan(directory,w,version:"4",crs:"Mine frame B",previous:unknown)
        XCTAssertThrowsError(try w.registerPlan(contradiction))
        var otherHorizon = qualified
        otherHorizon = MappingPlanReference(id: UUID(), horizonID: UUID(), attachmentID: UUID(), version: "5", file: qualified.file,
            frameConfirmation: PlanFrameConfirmation(previousPlanID: first.id, confirmedAt: Date()))
        XCTAssertThrowsError(try PlanCoordinateCompatibility.validate(w.journal.plans + [otherHorizon]))
    }
    func testDirectActivePlanSelectionPreservesDraftAndRejectsStaleCallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let photoStore = ManagedPhotoStore(root: directory.appendingPathComponent("photos"))
        let preferencesName = "FieldForge.ThirdReview." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let model = MappingModel(workflow: w, photoStore: photoStore, preferences: preferences)
        model.workflow!.draft.picket = "12,18"; model.workflow!.draft.notes = "Keep"
        let before = model.workflow!.draft
        XCTAssertNil(try model.beginCoordinateSelection()); XCTAssertEqual(model.selectedTab,1)
        XCTAssertEqual(model.workflow!.draft,before)
        let first = try plan(directory,w,version:"1"), second = try plan(directory,w,version:"2")
        try w.registerPlan(first); try w.registerPlan(second); model.workflow = w
        model.selectActivePlan(first)
        let request = try XCTUnwrap(model.beginCoordinateSelection())
        XCTAssertEqual(request.plan.id,first.id)
        model.workflow!.draft.picket = "12,18"; model.workflow!.draft.notes = "Keep"
        let id = model.workflow!.draft.id
        try model.workflow!.selectPlanPoint(PlanPoint(x: 12.123456789, y: 34.987654321), request: request)
        XCTAssertEqual(model.workflow!.draft.id,id); XCTAssertEqual(model.workflow!.draft.notes,"Keep")
        XCTAssertEqual(model.workflow!.draft.picket,"12,18"); XCTAssertEqual(model.workflow!.draft.x,"12.123456789")
        _ = try model.workflow!.save()
        let next = model.workflow!.draft
        XCTAssertThrowsError(try model.workflow!.selectPlanPoint(PlanPoint(x:1,y:2),request:request))
        XCTAssertEqual(model.workflow!.draft,next)
    }
}
