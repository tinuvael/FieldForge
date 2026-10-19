import Foundation
import Combine

@MainActor final class MappingModel: ObservableObject {
    @Published var workflow: MappingWorkflow?
    @Published var error: String?
    @Published var success = false
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

