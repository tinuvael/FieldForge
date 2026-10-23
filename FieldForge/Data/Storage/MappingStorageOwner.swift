import Foundation

/// The only application executor for mapping persistence and attachment mutations.
/// FIFO queue blocks are deliberately synchronous: no actor reentrancy or suspension
/// between attachment preparation, validation, backup and atomic journal replacement.
/// Cancellation after admission does not cancel a block or its result delivery.
final class MappingStorageOwner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tinuvael.FieldForge.mapping-storage", qos: .userInitiated)
    private var committed: MappingJournal?

    func run<Value>(_ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                continuation.resume(with: Result { try body() })
            }
        }
    }

    func open(store: any MappingStore) async throws -> MappingWorkflow {
        try await run {
            let workflow = try MappingWorkflow(store: store)
            self.committed = workflow.journal
            return workflow
        }
    }

    /// Inputs capture volatile draft/context intent; mutations always start from the
    /// latest committed graph. Callers must await and reconcile every accepted result.
    func transaction<Value>(snapshot: MappingWorkflow,
                            _ action: @escaping @Sendable (inout MappingWorkflow) throws -> Value) async throws -> (MappingWorkflow, Value) {
        try await run {
            let base = self.committed ?? snapshot.journal
            let buffer = MappingTransactionBuffer(base)
            let file = snapshot.persistenceStore
            var next = snapshot
            next.prepareTransaction(journal: base, store: buffer)
            let value = try action(&next)
            // Workflow commits are buffered until the entire synchronous command
            // succeeds. Even a command that throws after commit() cannot leave disk
            // ahead of the published result. Exactly one atomic save per command.
            if buffer.changed { try file.save(next.journal) }
            next.prepareTransaction(journal: next.journal, store: file)
            self.committed = next.journal
            return (next, value)
        }
    }
}

/// Operation identity belongs to the UI coordinator, not the on-disk schema.
enum MappingSavingState: Equatable {
    case idle
    case saving(UUID)
    case committed(UUID)
    case failed(UUID, String)
    var isSaving: Bool { if case .saving = self { return true }; return false }
}

/// Queue-confined command buffer; authoritative validation remains in FileMappingStore.
private final class MappingTransactionBuffer: MappingStore {
    private var journal: MappingJournal
    private(set) var changed = false
    init(_ journal: MappingJournal) { self.journal = journal }
    func load() throws -> MappingJournal { journal }
    func save(_ next: MappingJournal) throws { journal = next; changed = true }
}
