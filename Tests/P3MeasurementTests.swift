import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
private typealias OriginalReading = FieldForgeCore.Measurement
#else
@testable import FieldForge
private typealias OriginalReading = FieldForge.Measurement
#endif

@MainActor final class P3MeasurementTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000.123)
    private func manual() throws -> OriginalReading {
        try ManualOrientationInput(dipAngleText: "45,125", dipDirectionText: "360", reference: .gridNorth)
            .observation(notes: "Compass transcription", timestamp: date)
    }
    private func sensor() -> SensorSample {
        var sample = MockSensorProvider.sample(dip: 60, direction: 270, timestamp: date.addingTimeInterval(2))
        sample.source = .coreMotion; sample.referenceFrame = .magneticNorthZVertical
        sample.magneticAccuracy = .high; sample.magneticField.x = 40
        return sample
    }
    func testMixedOriginalsCommitOnlyWithPointAndResetRetainsContextAndNominalZ() async throws {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        let context = w.context
        let session = MeasurementSession(); let raw = sensor(); session.receive(raw)
        XCTAssertTrue(session.hold(now: raw.timestamp))
        let automatic = try XCTUnwrap(session.record(notes: "Screen contact"))
        let manual = try manual()
        try w.draft.addMeasurement(manual); try w.draft.addMeasurement(automatic)
        XCTAssertTrue(store.value.measurements.isEmpty); XCTAssertTrue(store.value.observations.isEmpty)
        XCTAssertEqual(w.draft.measurements.count, 2)
        w.draft.picket = "ПК 0+005"; w.draft.notes = "Point"
        w.draft.observedAtOverride = date.addingTimeInterval(-100); w.draft.x = "12"; w.draft.z = "390"
        let record = try w.save(now: date.addingTimeInterval(10))
        XCTAssertEqual(record.measurementIDs, [manual.id, automatic.id])
        XCTAssertEqual(w.journal.measurements(for: record), [manual, automatic])
        XCTAssertEqual(store.value.measurements[1].sample, raw)
        XCTAssertEqual(store.value.measurements[0].manualInput, manual.manualInput)
        XCTAssertEqual(w.context, context); XCTAssertTrue(w.draft.measurements.isEmpty)
        XCTAssertEqual(w.draft.z, "393"); XCTAssertEqual(w.draft.x, ""); XCTAssertEqual(w.draft.notes, "")
        XCTAssertNil(w.draft.observedAtOverride); XCTAssertFalse(w.draft.hasChanges)
        w.draft.picket = "ПК 0+010"; let second = try w.save(now: date.addingTimeInterval(20))
        XCTAssertTrue(second.measurementIDs.isEmpty); XCTAssertNotEqual(record.id, second.id)
        let reopened = try MappingWorkflow(store: store)
        XCTAssertEqual(reopened.journal.measurements(for: record), [manual, automatic])
        XCTAssertEqual(reopened.journal.measurements.count, 2)
    }
    func testFailureAndInvalidPicketKeepEntireDraftWithoutOrphans() async throws {
        let (store, initial) = try P2MappingTests().configured(); var w = initial
        try w.draft.addMeasurement(manual()); let graph = w.journal
        var draft = w.draft
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft); XCTAssertEqual(w.journal, graph)
        w.draft.picket = "5"; w.draft.notes = "Retain"; draft = w.draft
        store.fail = true
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.draft, draft); XCTAssertEqual(w.journal, graph)
        XCTAssertTrue(store.value.measurements.isEmpty); XCTAssertTrue(store.value.observations.isEmpty)
        store.fail = false; _ = try w.save()
        XCTAssertEqual(store.value.observations.count, 1); XCTAssertEqual(store.value.measurements.count, 1)
    }
    func testMeasurementsAloneAreDirtyAndEveryContextChangeRequiresConfirmation() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let original = w.context; let reading = try manual(); try w.draft.addMeasurement(reading)
        let otherProject = try w.createProject(name: "Other")
        let otherHorizon = try w.createHorizon(elevation: "200")
        let otherExcavation = try w.createExcavation(name: "Other", horizonIDs: [original.horizonID!])
        for next in [MappingContext(projectID: otherProject),
                     MappingContext(projectID: original.projectID, horizonID: otherHorizon),
                     MappingContext(projectID: original.projectID, horizonID: original.horizonID, excavationID: otherExcavation)] {
            try w.requestContext(next); XCTAssertEqual(w.context, original); XCTAssertEqual(w.pendingContext, next)
            w.cancelContextChange(); XCTAssertEqual(w.draft.measurements, [reading])
        }
        try w.requestContext(MappingContext(projectID: otherProject)); try w.confirmDiscard()
        XCTAssertTrue(w.draft.measurements.isEmpty); XCTAssertFalse(w.draft.hasChanges)
    }
    func testDuplicateInvalidAndTamperedOriginalsRejectedAndDraftRemovalIsLocal() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let reading = try manual(); try w.draft.addMeasurement(reading)
        XCTAssertThrowsError(try w.draft.addMeasurement(reading))
        var invalid = Measurement.process(sensor()); invalid.orientation.dipDirection = 30
        XCTAssertThrowsError(try w.draft.addMeasurement(invalid))
        XCTAssertEqual(w.draft.measurements, [reading]); w.draft.removeMeasurement(id: reading.id)
        XCTAssertTrue(w.draft.measurements.isEmpty); XCTAssertTrue(w.journal.measurements.isEmpty)
    }
    func testGraphRejectsOrphansMissingDuplicateAndSharedIDs() async throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        try w.draft.addMeasurement(manual()); w.draft.picket = "5"; _ = try w.save()
        let good = w.journal
        var graph = good; graph.measurements = []; XCTAssertThrowsError(try graph.validate())
        graph = good; graph.measurements.append(good.measurements[0]); XCTAssertThrowsError(try graph.validate())
        graph = good; graph.observations = []; XCTAssertThrowsError(try graph.validate())
        graph = good; graph.measurements[0].quality = .experimental; XCTAssertThrowsError(try graph.validate())
        // A second point may not take ownership of the first point's original UUID.
        try w.draft.addMeasurement(good.measurements[0]); w.draft.picket = "10"
        XCTAssertThrowsError(try w.save()); XCTAssertEqual(w.journal, good)
        XCTAssertEqual(w.draft.measurements, good.measurements)
    }
    func testFileReopenAppendOnlyAndChangedFileFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mapping.json")
        let (memory, initial) = try P2MappingTests().configured(); var w = initial
        try w.draft.addMeasurement(manual()); w.draft.picket = "5"; let point = try w.save()
        let store = FileMappingStore(url: url); try store.save(memory.value)
        var reopened = try MappingWorkflow(store: store)
        XCTAssertEqual(reopened.journal.measurements(for: point), w.journal.measurements)
        var edited = reopened.journal; edited.measurements[0].notes = "Overwrite evidence"
        XCTAssertThrowsError(try store.save(edited))
        try reopened.draft.addMeasurement(Measurement.process(sensor())); reopened.draft.picket = "10"
        let draft = reopened.draft, graph = reopened.journal
        let external = Data("external change".utf8); try external.write(to: url)
        XCTAssertThrowsError(try reopened.save()); XCTAssertEqual(reopened.draft, draft); XCTAssertEqual(reopened.journal, graph)
        XCTAssertEqual(try Data(contentsOf: url), external)
    }
    func testCurrentReopenPreservesPlansMarkersEvidenceAndOriginalBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ManagedPlanStore(root: directory.appendingPathComponent("plans"))
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let plan = try files.stage(data: DXFFixtures.drawing(DXFFixtures.line), filename: "horizon.dxf",
            horizonID: w.context.horizonID!, version: "A", units: .meters, crs: "local", axes: "X north Y east")
        try w.registerPlan(plan); files.complete(plan)
        try w.selectPlanPoint(PlanPoint(x: 123, y: 456), planID: plan.id)
        w.draft.picket = "5"; let oldPoint = try w.save()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w.journal)) as? [String: Any])
        let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let url = directory.appendingPathComponent("mapping.json"); try bytes.write(to: url)
        let store = FileMappingStore(url: url); var reopened = try MappingWorkflow(store: store)
        XCTAssertEqual(reopened.journal.schemaVersion, 7); XCTAssertEqual(reopened.journal.observations, [oldPoint])
        XCTAssertEqual(reopened.journal.plans, [plan]); XCTAssertEqual(try Data(contentsOf: url), bytes)
        // Returning from a plan selection changes XY only and retains the full unsaved evidence.
        let reading = try manual(); try reopened.draft.addMeasurement(reading); reopened.draft.picket = "10"
        try reopened.selectPlanPoint(PlanPoint(x: 125, y: 460), planID: plan.id)
        XCTAssertEqual(reopened.draft.measurements, [reading]); XCTAssertEqual(reopened.draft.picket, "10")
        _ = try reopened.save(); let again = try FileMappingStore(url: url).load()
        XCTAssertEqual(again.measurements, [reading]); XCTAssertEqual(again.observations.first, oldPoint)
        XCTAssertNoThrow(try files.read(plan)); XCTAssertEqual(again.plans, [plan])
    }
    func testCurrentMissingEvidenceTableFailsWithoutReset() async throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MappingJournal())) as? [String: Any])
        json.removeValue(forKey: "measurements")
        XCTAssertThrowsError(try JSONDecoder().decode(MappingJournal.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testAcquisitionHoldBackgroundDismissRetakeAndLateEvents() async throws {
        let provider = MockSensorProvider(); let capture = MeasurementAcquisition(provider: provider)
        capture.setLifecycle(visible: true, foreground: true)
        XCTAssertTrue(provider.isRunning); XCTAssertTrue(capture.session.canHold())
        capture.hold(); let frozen = capture.session.frozen
        XCTAssertNotNil(frozen); XCTAssertFalse(provider.isRunning)
        provider.onEvent?(.sample(sensor())); XCTAssertEqual(capture.session.displayed, frozen)
        capture.setLifecycle(visible: true, foreground: false)
        XCTAssertEqual(capture.session.frozen, frozen); XCTAssertFalse(provider.isRunning)
        capture.setLifecycle(visible: true, foreground: true); XCTAssertFalse(provider.isRunning)
        capture.reset(); XCTAssertTrue(provider.isRunning); XCTAssertFalse(capture.session.isHeld)
        capture.setVisible(false); XCTAssertFalse(provider.isRunning); XCTAssertNil(capture.session.displayed)
        capture.setVisible(true); XCTAssertTrue(capture.session.canHold())
        capture.setLifecycle(visible: true, foreground: false)
        XCTAssertFalse(provider.isRunning); XCTAssertNil(capture.session.live)
        provider.onEvent?(.sample(sensor())); XCTAssertNil(capture.session.live)
        capture.setLifecycle(visible: true, foreground: true)
        XCTAssertTrue(provider.isRunning); XCTAssertNotNil(capture.session.live)
        capture.setVisible(false)
    }
    func testAcquisitionInvalidMovingStaleAndInclinationOnly() async throws {
        let provider = MockSensorProvider(); let capture = MeasurementAcquisition(provider: provider)
        capture.setLifecycle(visible: true, foreground: true)
        for condition in [MockCondition.invalid, .moving, .unavailable] {
            provider.condition = condition; provider.emit(); capture.hold()
            XCTAssertFalse(capture.session.isHeld); XCTAssertFalse(capture.session.canSave)
        }
        provider.condition = .normal; provider.emit()
        capture.expire(now: Date().addingTimeInterval(2)); XCTAssertNil(capture.session.live)
        capture.hold(); XCTAssertFalse(capture.session.isHeld)
        provider.condition = .magneticUnavailable; provider.emit(); capture.hold()
        XCTAssertTrue(capture.session.isHeld); XCTAssertNil(capture.session.frozen?.orientation.dipDirection)
        XCTAssertEqual(capture.session.frozen?.quality, .inclinationOnly)
        XCTAssertFalse(provider.isRunning); capture.setVisible(false)
    }
}
