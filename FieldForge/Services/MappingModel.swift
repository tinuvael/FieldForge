import Foundation
import Combine

@MainActor final class MappingModel: ObservableObject {
    @Published var workflow: MappingWorkflow?
    @Published var error: String?
    @Published var success = false
    // Disposable UI preferences, outside the append-only mapping journal.
    @Published private var activePlanIDs = UserDefaults.standard.dictionary(forKey: "FieldForge.activePlans.v1") as? [String: String] ?? [:]
    func plans(for horizonID: UUID) -> [MappingPlanReference] {
        guard let workflow, workflow.journal.horizons.contains(where: {
            $0.id == horizonID && $0.projectID == workflow.context.projectID
        }) else { return [] }
        return workflow.journal.plans.filter { $0.horizonID == horizonID }
    }
    private func planKey(_ horizonID: UUID) -> String? {
        workflow?.context.projectID.map { "\($0.uuidString)/\(horizonID.uuidString)" }
    }
    func activePlan(for horizonID: UUID) -> MappingPlanReference? {
        let available = plans(for: horizonID)
        if let key = planKey(horizonID), let id = activePlanIDs[key] {
            return available.first { $0.id.uuidString == id }
        }
        // Import order is journal append order; no geometric compatibility is implied.
        return available.last
    }
    func hasExplicitPlan(for horizonID: UUID) -> Bool {
        planKey(horizonID).map { activePlanIDs[$0] != nil } ?? false
    }
    func selectActivePlan(_ plan: MappingPlanReference) {
        guard plans(for: plan.horizonID).contains(plan), let key = planKey(plan.horizonID) else { return }
        activePlanIDs[key] = plan.id.uuidString
        UserDefaults.standard.set(activePlanIDs, forKey: "FieldForge.activePlans.v1")
    }
    private(set) var planStore: ManagedPlanStore?
    private(set) var photoStore: ManagedPhotoStore?
    @Published var photoBusy = false
    @Published var photoError: String?
    @Published var pendingPhotos: [PhotoImportOperation] = []
    @Published var photoRecoveryError: String?
    @Published var retainedPhotos: [UUID: RetainedPhotoImport] = [:]
    init(workflow: MappingWorkflow, photoStore: ManagedPhotoStore) {
        self.workflow = workflow; self.photoStore = photoStore
        refreshPhotoRecovery()
    }
    init() {
        do {
            let directory = try FileMeasurementStore.applicationStore().url.deletingLastPathComponent()
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            #else
            let testing = false
            #endif
            #if DEBUG && targetEnvironment(simulator)
            let namespace = ProcessInfo.processInfo.environment["FIELD_FORGE_TEST_RUN_ID"].flatMap(UUID.init(uuidString:)).map { "-" + $0.uuidString } ?? ""
            #else
            let namespace = ""
            #endif
            planStore = ManagedPlanStore(root: directory.appendingPathComponent(testing ? "ui-testing-plans\(namespace)" : "plans"))
            photoStore = ManagedPhotoStore(root: directory.appendingPathComponent(testing ? "ui-testing-photos\(namespace)" : "photos"))
            workflow = try MappingWorkflow(store: FileMappingStore(url: directory.appendingPathComponent(testing ? "ui-testing-mapping\(namespace).json" : "mapping-v1.json")))
        } catch { self.error = "Не удалось открыть картирование. Запись заблокирована: \(error.localizedDescription)" }
        refreshPhotoRecovery()
    }
    func perform(_ action: (inout MappingWorkflow) throws -> Void) {
        guard workflow != nil else { return }
        let oldID = workflow!.draft.id
        do {
            try action(&workflow!)
            if workflow!.draft.id != oldID {
                // Discard only volatile ownership. Never delete files or a saved original.
                retainedPhotos = retainedPhotos.filter { $0.value.operation.photo.context.pointID != oldID }
                refreshPhotoRecovery()
            }
        } catch { self.error = error.localizedDescription }
    }
}

