import Foundation
import Combine

@MainActor final class MappingModel: ObservableObject {
    @Published var workflow: MappingWorkflow?
    @Published var error: String?
    @Published var success = false
    @Published var selectedTab = 0
    @Published private(set) var loading = false
    @Published private(set) var savingState: MappingSavingState = .idle
    let storage = MappingStorageOwner()
    private var opening: Task<Void, Never>?
    var isSaving: Bool { savingState.isSaving }

    /// Admission is synchronous on MainActor. Conflicting requests fail explicitly;
    /// callers retain their input and can retry. No UI snapshot publishes before commit.
    @discardableResult
    func persist<Value>(_ action: @escaping @Sendable (inout MappingWorkflow) throws -> Value) async throws -> Value {
        guard !isSaving else { throw MappingError.invalid("Дождитесь завершения сохранения и повторите действие.") }
        guard let snapshot = workflow else { throw StorageError.writesBlocked }
        guard snapshot.draft.photoSessions.isEmpty else {
            throw MappingError.invalid("Дождитесь завершения получения фотографий и повторите действие.")
        }
        let operationID = UUID(), oldID = snapshot.draft.id
        savingState = .saving(operationID)
        workflow!.draft.saving = true
        do {
            let (committed, value) = try await storage.transaction(snapshot: snapshot, action)
            // Never check Task.isCancelled here: disk outcome must be reconciled.
            workflow = committed
            savingState = .committed(operationID)
            error = nil
            if committed.draft.id != oldID {
                retainedPhotos = retainedPhotos.filter {
                    let pointID = $0.value.operation.photo.context.pointID
                    return pointID != oldID || committed.retainedDraftIDs.contains(pointID)
                }
            }
            return value
        } catch {
            workflow!.draft.saving = false
            savingState = .failed(operationID, error.localizedDescription)
            self.error = error.localizedDescription
            throw error
        }
    }
    func beginCoordinateSelection() throws -> MappingPlanSelectionRequest? {
        guard let workflow, let horizonID = workflow.context.horizonID else { throw StorageError.invalidRecord }
        guard let plan = activePlan(for: horizonID) else { selectedTab = 1; return nil }
        return try workflow.planSelectionRequest(plan)
    }
    // Disposable UI preferences, outside the append-only mapping journal.
    private let preferences: UserDefaults
    @Published private var activePlanIDs: [String: String]
    func plans(for horizonID: UUID, archived: Bool = false) -> [MappingPlanReference] {
        guard let workflow, workflow.journal.horizons.contains(where: {
            $0.id == horizonID && $0.projectID == workflow.context.projectID
        }) else { return [] }
        return workflow.journal.plans.filter { $0.horizonID == horizonID && !$0.isDeleted && $0.isArchived == archived }
    }
    private func planKey(_ horizonID: UUID) -> String? {
        workflow?.context.projectID.map { "\($0.uuidString)/\(horizonID.uuidString)" }
    }
    func activePlan(for horizonID: UUID) -> MappingPlanReference? {
        let available = plans(for: horizonID)
        if let key = planKey(horizonID), let id = activePlanIDs[key],
           let selected = available.first(where: { $0.id.uuidString == id }) {
            return selected
        }
        if let key = planKey(horizonID), activePlanIDs[key] != nil { return nil }
        // Import order is journal append order; no geometric compatibility is implied.
        return available.first
    }
    func hasExplicitPlan(for horizonID: UUID) -> Bool {
        guard let key = planKey(horizonID), let id = activePlanIDs[key] else { return false }
        return plans(for: horizonID).contains { $0.id.uuidString == id }
    }
    func hasUnavailablePlanSelection(for horizonID: UUID) -> Bool {
        guard let key = planKey(horizonID), activePlanIDs[key] != nil else { return false }
        return !hasExplicitPlan(for: horizonID)
    }
    func selectActivePlan(_ plan: MappingPlanReference) {
        guard plans(for: plan.horizonID).contains(plan), let key = planKey(plan.horizonID) else { return }
        activePlanIDs[key] = plan.id.uuidString
        preferences.set(activePlanIDs, forKey: "FieldForge.activePlans.v1")
    }
    func selectActivePlanIfUnset(_ plan: MappingPlanReference) {
        guard let key = planKey(plan.horizonID), activePlanIDs[key] == nil else { return }
        selectActivePlan(plan)
    }
    func managePlan(_ plan: MappingPlanReference, action: PlanManagementChange.Action, targetHorizonID: UUID? = nil,
                    replacement: MappingPlanReference? = nil) async throws {
        guard workflow != nil else { throw StorageError.writesBlocked }
        let wasActive = activePlan(for: plan.horizonID)?.id == plan.id
        if wasActive && action != .restore {
            let alternatives = plans(for: plan.horizonID).filter { $0.id != plan.id }
            guard alternatives.isEmpty || replacement.map({ alternatives.contains($0) }) == true else {
                throw MappingError.invalid("Выберите новую активную ревизию.")
            }
        }
        try await persist { try $0.managePlan(plan.id, action: action, horizonID: targetHorizonID) }
        if wasActive && action != .restore {
            if let replacement { selectActivePlan(replacement) }
            else if let key = planKey(plan.horizonID) {
                // Keep a deliberate empty choice; never silently fall back to another import.
                activePlanIDs[key] = plan.id.uuidString
                preferences.set(activePlanIDs, forKey: "FieldForge.activePlans.v1")
            }
        }
    }
    func registerPlan(_ plan: MappingPlanReference) async throws {
        guard let files = planStore else { throw StorageError.writesBlocked }
        try await persist { next in
            _ = try DXFDocument.parse(files.read(plan))
            if let existing = next.journal.plans.first(where: { $0.matchesImport(plan) }) {
                guard existing.id == plan.id else { throw StorageError.invalidRecord }
            } else { try next.registerPlan(plan) }
        }
        await storageCompletePlan(plan, files: files)
    }
    private func storageCompletePlan(_ plan: MappingPlanReference, files: ManagedPlanStore) async {
        _ = try? await storage.run { files.complete(plan) }
    }
    func pendingPlans() async throws -> [MappingPlanReference] {
        guard let files = planStore else { return [] }
        let journal = workflow?.journal
        return try await storage.run {
            let items = try files.pending()
            for plan in items where journal?.plans.contains(where: { $0.matchesImport(plan) }) == true { files.complete(plan) }
            return items
        }
    }
    private(set) var planStore: ManagedPlanStore?
    private(set) var photoStore: ManagedPhotoStore?
    @Published var photoBusy = false
    @Published var photoError: String?
    @Published var pendingPhotos: [PhotoImportOperation] = []
    @Published var photoRecoveryError: String?
    @Published var retainedPhotos: [UUID: RetainedPhotoImport] = [:]
    init(workflow: MappingWorkflow, photoStore: ManagedPhotoStore, planStore: ManagedPlanStore? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        activePlanIDs = preferences.dictionary(forKey: "FieldForge.activePlans.v1") as? [String: String] ?? [:]
        self.workflow = workflow; self.photoStore = photoStore; self.planStore = planStore
        Task { await refreshPhotoRecovery() }
    }
    init() {
        preferences = .standard
        activePlanIDs = preferences.dictionary(forKey: "FieldForge.activePlans.v1") as? [String: String] ?? [:]
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
            let store = FileMappingStore(url: directory.appendingPathComponent(testing ? "ui-testing-mapping\(namespace).json" : "mapping-v1.json"))
            loading = true
            opening = Task { [self] in
                defer { loading = false }
                do { workflow = try await storage.open(store: store) }
                catch { self.error = "Не удалось открыть картирование. Запись заблокирована: \(error.localizedDescription)" }
                await refreshPhotoRecovery()
            }
        } catch { self.error = "Не удалось открыть картирование. Запись заблокирована: \(error.localizedDescription)" }
    }
    /// Volatile callbacks must propagate refusal so their editor stays open.
    func performThrowing(_ action: (inout MappingWorkflow) throws -> Void) throws {
        guard workflow != nil else { throw StorageError.writesBlocked }
        guard !isSaving else { throw MappingError.invalid("Дождитесь завершения сохранения и повторите действие.") }
        try action(&workflow!)
    }
    /// Volatile edits only. Durable commands use awaited persist(_:).
    func perform(_ action: (inout MappingWorkflow) throws -> Void) {
        guard workflow != nil else { return }
        do { try performThrowing(action) }
        catch { self.error = error.localizedDescription }
    }
}
