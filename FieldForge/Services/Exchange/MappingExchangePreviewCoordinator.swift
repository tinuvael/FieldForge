import Foundation
import Combine

/// Screen-local admission/publication only. Cancellation requests stop work; UUIDs
/// revoke permission to publish even if a dependency ignores cooperative cancellation.
@MainActor final class MappingExchangePreviewCoordinator: ObservableObject {
    struct State {
        var preview: MappingExchangePreview?
        var publicationID: UUID?
        var message: String?
        var stale = false
        var busy = false
    }
    struct Operation {
        let id: UUID
        let task: Task<Void, Never>
    }
    struct Work: Sendable {
        let snapshot: @Sendable () async throws -> MappingCommittedSnapshot
        let read: @Sendable (URL, MappingCommittedSnapshot) async throws -> MappingExchangePreview
        let isCurrent: @Sendable (UUID) async throws -> Bool

        init(storage: MappingStorageOwner) {
            snapshot = { try await storage.exchangeSnapshot() }
            read = { try await MappingExchangeFileRead.prepare(url: $0, committed: $1) }
            isCurrent = { try await storage.exchangePreviewIsCurrent($0) }
        }
        init(snapshot: @escaping @Sendable () async throws -> MappingCommittedSnapshot,
             read: @escaping @Sendable (URL, MappingCommittedSnapshot) async throws -> MappingExchangePreview,
             isCurrent: @escaping @Sendable (UUID) async throws -> Bool) {
            self.snapshot = snapshot; self.read = read; self.isCurrent = isCurrent
        }
    }
    @Published private(set) var state = State()
    private(set) var isActive = false
    private(set) var operationID: UUID?
    private var operation: Task<Void, Never>?
    private var observedGeneration: UUID?
    private var appearanceID = UUID()

    func activate(generation: UUID?) {
        appearanceID = UUID()
        isActive = true
        journalChanged(to: generation)
    }
    func deactivate() {
        appearanceID = UUID()
        isActive = false
        revokeOperation()
        state.busy = false
    }
    private func revokeOperation() {
        operationID = nil // Revoke before cancellation handlers can resume old work.
        let old = operation; operation = nil; old?.cancel()
    }
    func cancel(operationID id: UUID?) {
        guard isActive, let id, operationID == id else { return }
        revokeOperation()
        state = State(message: "Проверка отменена. Данные не изменены.")
    }
    func selectionFailed(_ error: Error) {
        guard isActive else { return }
        revokeOperation()
        state = State(message: "Выбор файла: \(error.localizedDescription)")
    }
    private func owns(_ id: UUID) -> Bool { isActive && operationID == id }

    @discardableResult
    func prepare(_ url: URL, work: Work) -> Operation? {
        guard isActive else { return nil }
        revokeOperation()
        let id = UUID()
        operationID = id
        state = State(busy: true)
        let task = Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            defer {
                if self.owns(id) {
                    self.state.busy = false
                    self.operation = nil; self.operationID = nil
                }
            }
            do {
                let committed = try await work.snapshot()
                guard self.owns(id), !Task.isCancelled else { return }
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try await work.read(url, committed)
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard self.owns(id), !Task.isCancelled else { return }
                let current: Bool
                do { current = try await work.isCurrent(result.generationID) }
                catch { current = false } // Retired/unavailable storage fails closed.
                guard self.owns(id), !Task.isCancelled else { return }
                // One publication: no apparently current preview while freshness is pending.
                // Also retain journal notifications received while that read was suspended.
                self.state = State(preview: result, publicationID: id,
                    stale: !current || self.observedGeneration != result.generationID)
            } catch {
                guard self.owns(id), !Task.isCancelled else { return }
                self.state = State(message: error is CancellationError
                    ? "Проверка отменена. Данные не изменены."
                    : "Книга отклонена: \(error.localizedDescription)")
            }
        }
        operation = task
        return Operation(id: id, task: task)
    }

    func journalChanged(to generation: UUID?) {
        guard isActive else { return }
        observedGeneration = generation
        if let preview = state.preview, generation != preview.generationID { state.stale = true }
    }
    private func canRefresh(_ id: UUID) -> Bool {
        isActive && state.publicationID == id && !state.stale && !state.busy
    }
    /// A cancelled/late monitor must not update a newer publication, including another
    /// preview of the same journal generation. Staleness is monotonic per publication.
    func refresh(_ id: UUID, isCurrent: @Sendable (UUID) async throws -> Bool) async {
        guard canRefresh(id), let preview = state.preview else { return }
        let appearance = appearanceID
        let current: Bool
        do { current = try await isCurrent(preview.generationID) }
        catch { current = false }
        guard !Task.isCancelled, appearanceID == appearance, canRefresh(id) else { return }
        if !current || observedGeneration != preview.generationID { state.stale = true }
    }
}
