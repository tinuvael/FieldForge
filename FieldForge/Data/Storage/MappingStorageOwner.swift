import Foundation

/// The only application executor for mapping persistence and attachment mutations.
/// FIFO queue blocks are deliberately synchronous: no actor reentrancy or suspension
/// between attachment preparation, validation, backup and atomic journal replacement.
/// Cancellation after admission does not cancel a block or its result delivery.
/// Unchecked invariant: store/committed are private, touched only by non-suspending
/// blocks on this one queue (apart from initialization before publication). No store
/// or transaction buffer escapes; inputs/results and run closures are Sendable.
/// A default actor's reentrant executor does not express the FIFO queue contract.
final class MappingStorageOwner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tinuvael.FieldForge.mapping-storage", qos: .userInitiated)
    // All mutable state below is accessed only inside a synchronous queue block.
    // A store passed at initialization is handed off before any block is submitted.
    private var store: (any MappingStore)?
    private var committed: MappingJournal?

    init(store: (any MappingStore)? = nil) { self.store = store }

    func run<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                continuation.resume(with: Result { try body() })
            }
        }
    }

    func open(makeStore: @escaping @Sendable () -> any MappingStore) async throws -> MappingWorkflow.Snapshot {
        try await run {
            guard self.store == nil else { throw StorageError.writesBlocked }
            let store = makeStore()
            let workflow = try MappingWorkflow(store: store)
            self.store = store
            self.committed = workflow.journal
            return workflow.snapshot
        }
    }

    /// Inputs capture volatile draft/context intent; mutations always start from the
    /// latest committed graph. Callers must await and reconcile every accepted result.
    func transaction<Value: Sendable>(snapshot: MappingWorkflow.Snapshot,
                            _ action: @escaping @Sendable (inout MappingWorkflow) throws -> Value) async throws -> (MappingWorkflow.Snapshot, Value) {
        try await run {
            let base = self.committed ?? snapshot.journal
            let buffer = MappingTransactionBuffer(base)
            guard let file = self.store else { throw StorageError.writesBlocked }
            var next = MappingWorkflow(snapshot: snapshot, store: buffer)
            next.prepareTransaction(journal: base, store: buffer)
            let value = try action(&next)
            // Workflow commits are buffered until the entire synchronous command
            // succeeds. Even a command that throws after commit() cannot leave disk
            // ahead of the published result. Exactly one atomic save per command.
            if buffer.changed { try file.save(next.journal) }
            self.committed = next.journal
            return (next.snapshot, value)
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
