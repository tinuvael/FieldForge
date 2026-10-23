import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class PlanRevisionManagementTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func configured(_ root: URL) throws -> (FileMappingStore, ManagedPlanStore, MappingWorkflow) {
        let store = FileMappingStore(url: root.appendingPathComponent("mapping.json"))
        let (_, initial) = try P2MappingTests().configured()
        try store.save(initial.journal)
        return (store, ManagedPlanStore(root: root.appendingPathComponent("plans")), try MappingWorkflow(store: store))
    }
    private func plan(_ files: ManagedPlanStore, _ w: MappingWorkflow, version: String = "1", units: PlanUnits = .meters, previous: UUID? = nil) throws -> MappingPlanReference {
        try files.stage(data: DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n30\n300\n11\n10\n21\n0\n31\n400\n"),
            filename: "400.dxf", horizonID: XCTUnwrap(w.context.horizonID), version: version, units: units, crs: "unknown", axes: "unknown",
            frameConfirmation: previous.map { PlanFrameConfirmation(previousPlanID: $0, confirmedAt: Date()) })
    }
    func testTinyPlanXYRoundTripsWithoutExponentInputRejectionOrMovingPoint() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let p = try plan(files, w); try w.registerPlan(p)
        let point = PlanPoint(x: 1.4742791309813122e-7, y: -2.5123e-9)
        try w.selectPlanPoint(point, planID: p.id)
        XCTAssertFalse(w.draft.x.contains("e")); XCTAssertFalse(w.draft.y.contains("e"))
        w.draft.picket = "1"; let saved = try w.save()
        XCTAssertEqual(saved.coordinates?.x, point.x); XCTAssertEqual(saved.coordinates?.y, point.y)
        XCTAssertEqual(try store.load().observations.first, saved)
    }
    func testUnusedDeletionIsPersistedAndOriginalRemainsRecoverable() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let p = try plan(files, w); try w.registerPlan(p); files.complete(p)
        let bytes = try files.read(p)
        try w.managePlan(p.id, action: .delete)
        XCTAssertTrue(w.plans.isEmpty)
        let retired = try XCTUnwrap(store.load().plans.first)
        XCTAssertTrue(retired.matchesImport(p))
        XCTAssertTrue(retired.isDeleted); XCTAssertEqual(retired.id, p.id); XCTAssertEqual(retired.file, p.file)
        XCTAssertEqual(retired.managementHistory?.map(\.action), [.delete])
        XCTAssertEqual(try files.read(retired), bytes); XCTAssertTrue(try files.pending().isEmpty)
        XCTAssertTrue(try MappingWorkflow(store: FileMappingStore(url: store.url)).plans.isEmpty)
        XCTAssertThrowsError(try w.registerPlan(p))
        var removed = w.journal; removed.plans = []
        XCTAssertThrowsError(try store.save(removed))
    }
    func testOriginalAndCorrectionZDependenciesArchiveWithoutLosingAnyHistory() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let a = try plan(files, w), b = try plan(files, w, version: "2")
        try w.registerPlan(a); try w.registerPlan(b); files.complete(a); files.complete(b)
        w.draft.picket = "1"; let original = try w.save()
        var correction = try w.correction(for: original.id); correction.reason = "Уточнение по DXF"
        let doc = try DXFDocument.parse(files.read(b)), xy = PlanPoint(x: 5, y: 0.5)
        let elevation = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: doc, plan: b).automatic)
        try correction.fields.selectPlanPoint(xy, plan: b, elevation: elevation)
        let revision = try w.saveCorrection(correction)
        XCTAssertTrue(w.planDependencies(b.id).contains { $0.contains("История") })
        let evidence = w.journal
        XCTAssertThrowsError(try w.managePlan(b.id, action: .delete))
        let target = try w.createHorizon(elevation: "400")
        XCTAssertThrowsError(try w.managePlan(b.id, action: .move, horizonID: target))
        try w.managePlan(b.id, action: .archive)
        XCTAssertEqual(w.plans.map(\.id), [a.id])
        XCTAssertEqual(w.journal.observations, evidence.observations); XCTAssertEqual(w.journal.revisions, evidence.revisions)
        XCTAssertEqual(try store.load().effectiveObservation(id: original.id), revision.snapshot)
        try w.managePlan(b.id, action: .restore)
        XCTAssertTrue(w.plans.contains { $0.id == b.id })
        XCTAssertEqual(try files.read(b), try files.read(a)); try store.load().validate()
    }
    func testMoveUnusedPlanIsAtomicPreservesIdentityAndRejectsCollision() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let p = try plan(files, w); try w.registerPlan(p); files.complete(p)
        let target = try w.createHorizon(elevation: "400"), bytes = try files.read(p)
        try w.managePlan(p.id, action: .move, horizonID: target)
        XCTAssertTrue(w.plans.isEmpty)
        let moved = try XCTUnwrap(store.load().plans.first)
        XCTAssertEqual(moved.horizonID, target); XCTAssertEqual(moved.attachmentID, p.attachmentID); XCTAssertEqual(moved.file, p.file)
        XCTAssertEqual(moved.managementHistory?.first?.previousHorizonID, p.horizonID)
        XCTAssertEqual(try files.read(moved), bytes)
        let q = try plan(files, w); try w.registerPlan(q)
        let before = w.journal
        XCTAssertThrowsError(try w.managePlan(q.id, action: .move, horizonID: target))
        XCTAssertEqual(w.journal, before); XCTAssertEqual(try store.load(), before)
        // A caller cannot bypass the explicit move history or destroy source metadata.
        var tampered = before; tampered.plans[1].horizonID = target
        XCTAssertThrowsError(try store.save(tampered))
        tampered = before; tampered.plans[0].file = nil
        XCTAssertThrowsError(try store.save(tampered))
    }
    func testCompatibilityAndSuspendedDraftsBlockDeletionAndMove() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (_, files, initial) = try configured(directory); var w = initial
        let a = try plan(files, w), b = try plan(files, w, version: "2", previous: a.id)
        try w.registerPlan(a); try w.registerPlan(b)
        for p in [a,b] {
            XCTAssertFalse(w.planDependencies(p.id).isEmpty)
            XCTAssertThrowsError(try w.managePlan(p.id, action: .delete))
        }
        let isolated = try plan(files, w, version: "3"); try w.registerPlan(isolated)
        try w.selectPlanPoint(PlanPoint(x: 5, y: 0), planID: isolated.id)
        XCTAssertThrowsError(try w.managePlan(isolated.id, action: .delete))
        let other = try w.createHorizon(elevation: "400")
        try w.requestContext(MappingContext(projectID: w.context.projectID, horizonID: other))
        try w.preserveAndSwitch()
        XCTAssertTrue(w.planDependencies(isolated.id).contains { $0.contains("черновика") })
        XCTAssertThrowsError(try w.managePlan(isolated.id, action: .move, horizonID: other))
    }
    func testFailedManagementSaveAndExternalChangeLeaveFilesAndGraphUntouched() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let p = try plan(files, w); try w.registerPlan(p); files.complete(p)
        let before = w.journal, bytes = try files.read(p), backup = try Data(contentsOf: store.backupURL)
        let external = Data("external change".utf8); try external.write(to: store.url)
        XCTAssertThrowsError(try w.managePlan(p.id, action: .delete))
        XCTAssertThrowsError(try w.managePlan(p.id, action: .archive))
        XCTAssertEqual(w.journal, before); XCTAssertEqual(try files.read(p), bytes)
        XCTAssertEqual(try Data(contentsOf: store.url), external); XCTAssertEqual(try Data(contentsOf: store.backupURL), backup)
    }
    func testConfirmUnitsOnExistingUnknownFilePreservesHistoricalXYAndSupportsNewZ() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        let p = try plan(files, w, units: .unknown); try w.registerPlan(p); files.complete(p)
        let doc = try DXFDocument.parse(files.read(p)), xy = PlanPoint(x: 5, y: 1)
        try w.selectPlanPoint(xy, planID: p.id); w.draft.picket = "1"; let original = try w.save()
        XCTAssertEqual(original.coordinates?.units, "drawing")
        let request = try w.planSelectionRequest(p)
        XCTAssertNil(PlanElevationSnap.resolve(xy, document: doc, plan: p).automatic)
        XCTAssertThrowsError(try w.confirmPlanElevationUnits(p.id, units: .millimeters)) // INSUNITS=6.
        try w.confirmPlanElevationUnits(p.id, units: .meters)
        let updated = try XCTUnwrap(w.plans.first)
        let z = try XCTUnwrap(PlanElevationSnap.resolve(xy, document: doc, plan: updated).automatic)
        XCTAssertEqual(z.unitConfirmedAt, updated.elevationUnitConfirmation?.confirmedAt)
        XCTAssertEqual(z.elevationMeters, 350); XCTAssertEqual(z.unitDeclaration, "userConfirmedAtPlanReview")
        try w.selectPlanPoint(xy, request: request, elevation: z)
        w.draft.picket = "2"; let new = try w.save()
        XCTAssertEqual(new.coordinates?.zOrigin, .planGeometry); XCTAssertEqual(new.coordinates?.units, "drawing")
        let export = try MappingCSVExport.prepare(journal: w.journal, selection: MappingExportSelection(
            projectID: new.projectID, firstDay: new.observedAt, lastDay: new.observedAt, timeZoneID: "UTC"))
        let points = try XCTUnwrap(export.tables.first { $0.name == "points" })
        let csv = String(decoding: points.data, as: UTF8.self)
        XCTAssertTrue(csv.contains("userConfirmedAtPlanReview")); XCTAssertTrue(csv.contains("unitConfirmedAt"))
        XCTAssertTrue(csv.contains("extractionVersion"))
        let column = try XCTUnwrap(points.columns.firstIndex(of: "z_plan_geometry_json"))
        let json = try XCTUnwrap(points.rows.compactMap { row -> String? in
            if case .text(let value) = row[column] { return value }; return nil
        }.first { $0.contains("userConfirmedAtPlanReview") })
        XCTAssertEqual(try JSONDecoder().decode(PlanGeometryElevation.self, from: Data(json.utf8)), z)
        XCTAssertEqual(try store.load().observations.first, original); XCTAssertEqual(updated.file, p.file)
        XCTAssertThrowsError(try w.confirmPlanElevationUnits(p.id, units: .meters))
        let reopened = try FileMappingStore(url: store.url).load(); try reopened.validate()
        XCTAssertEqual(reopened.plans.first?.elevationUnitConfirmation?.units, .meters)
    }
    func testImportedUnitsPersistAndAutomaticZUsesResolvedDeclaration() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, files, initial) = try configured(directory); var w = initial
        for (index, header) in [6, 4, 0, 1].enumerated() {
            let declared = PlanUnits.declared(by: header)
            XCTAssertEqual(declared, header == 6 ? .meters : header == 4 ? .millimeters : nil)
            let units = declared ?? .meters // The user confirms headers 0 and 1 at import.
            let bytes = DXFFixtures.drawing("0\nLINE\n10\n0\n20\n0\n30\n1000\n11\n10\n21\n0\n31\n1000\n", units: header)
            let p = try files.stage(data: bytes, filename: "units.dxf", horizonID: XCTUnwrap(w.context.horizonID),
                version: String(index + 1), units: units, crs: "mine grid", axes: "WCS XYZ")
            try w.registerPlan(p)
            let reopened = try XCTUnwrap(store.load().plans.first { $0.id == p.id })
            XCTAssertEqual(reopened, p); XCTAssertEqual(try files.read(p), bytes)
            XCTAssertEqual(p.file?.unitDeclaration, declared == nil ? "userConfirmedAtImport" : "dxfINSUNITS")
            let z = try XCTUnwrap(PlanElevationSnap.resolve(PlanPoint(x: 5, y: 0),
                document: DXFDocument.parse(bytes), plan: reopened).automatic)
            XCTAssertEqual(z.elevationMeters, header == 4 ? 1 : 1000)
            try z.validate(plan: reopened)
        }
        XCTAssertNil(PlanUnits.declared(by: nil))
        let missing = String(decoding: DXFFixtures.drawing(DXFFixtures.line), as: UTF8.self)
            .replacingOccurrences(of: "9\n$INSUNITS\n70\n6\n", with: "")
        XCTAssertNil(try DXFDocument.parse(Data(missing.utf8)).insertionUnits)
    }

    @MainActor func testActiveSelectionFilteringRelaunchAndExplicitReplacement() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (_, files, initial) = try configured(directory); var w = initial
        let a = try plan(files, w), b = try plan(files, w, version: "2")
        try w.registerPlan(a); try w.registerPlan(b)
        let name = "FieldForge.PlanManagementTests." + UUID().uuidString
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name)); defer { prefs.removePersistentDomain(forName: name) }
        let photoStore = ManagedPhotoStore(root: directory.appendingPathComponent("photos"))
        let model = MappingModel(workflow: w, photoStore: photoStore, preferences: prefs)
        XCTAssertEqual(model.activePlan(for: a.horizonID)?.id, a.id)
        model.selectActivePlan(a)
        let c = try plan(files, w, version: "3"); try model.workflow!.registerPlan(c)
        XCTAssertEqual(model.activePlan(for: a.horizonID)?.id, a.id)
        let relaunched = MappingModel(workflow: model.workflow!, photoStore: photoStore, preferences: prefs)
        XCTAssertEqual(relaunched.activePlan(for: a.horizonID)?.id, a.id)
        do { try await model.managePlan(a, action: .delete); XCTFail("Replacement required") } catch { }
        try await model.managePlan(a, action: .delete, replacement: b)
        XCTAssertEqual(model.activePlan(for: a.horizonID)?.id, b.id)
        XCTAssertFalse(model.plans(for: a.horizonID).contains { $0.id == a.id })
        try await model.managePlan(c, action: .archive)
        XCTAssertEqual(model.plans(for: a.horizonID, archived: true).map(\.id), [c.id])
        XCTAssertEqual(model.plans(for: a.horizonID).map(\.id), [b.id])
        let target = try await model.persist { try $0.createHorizon(elevation: "400") }
        try await model.managePlan(b, action: .move, targetHorizonID: target)
        XCTAssertTrue(model.plans(for: a.horizonID).isEmpty)
        XCTAssertEqual(model.plans(for: target).map(\.id), [b.id]); XCTAssertNil(model.activePlan(for: a.horizonID))
        try await model.persist { try $0.managePlan(c.id, action: .restore) }
        XCTAssertEqual(model.plans(for: a.horizonID).map(\.id), [c.id])
        XCTAssertTrue(model.hasUnavailablePlanSelection(for: a.horizonID))
        XCTAssertNil(model.activePlan(for: a.horizonID)) // Explicit missing choice never falls back to C.

    }
}
