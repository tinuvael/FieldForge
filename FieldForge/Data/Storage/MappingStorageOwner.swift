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
    private var committed: MappingCommittedSnapshot?
    private var retired = false
    private var suspended: Bool

    init(store: (any MappingStore)? = nil, committed: MappingCommittedSnapshot? = nil, suspended: Bool = false) {
        self.store = store; self.committed = committed; self.suspended = suspended
    }

    func run<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await enqueue(body)
    }
    private func enqueue<Value: Sendable>(allowSuspended: Bool = false, _ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                continuation.resume(with: Result {
                    guard !self.retired, allowSuspended || !self.suspended else { throw StorageError.writesBlocked }; return try body()
                })
            }
        }
    }

    func open(makeStore: @escaping @Sendable () -> any MappingStore) async throws -> MappingWorkflow.Snapshot {
        try await enqueue(allowSuspended: true) {
            guard self.store == nil else { throw StorageError.writesBlocked }
            let store = makeStore()
            let workflow = try MappingWorkflow(store: store)
            self.store = store
            self.committed = workflow.committed
            return workflow.snapshot
        }
    }

    /// Drain accepted work before moving a root; old callbacks stay rejected.
    func retire() async {
        await withCheckedContinuation { continuation in
            queue.async { self.retired = true; continuation.resume() }
        }
    }
    func enableAfterRestore() async throws {
        try await enqueue(allowSuspended: true) { self.suspended = false }
    }

    /// A read queued after admitted writes retains exactly one committed generation.
    /// Export projection/ZIP work happens after releasing the storage queue.
    func exchangeSnapshot() async throws -> MappingCommittedSnapshot {
        try await run {
            guard let committed = self.committed else { throw StorageError.writesBlocked }
            return committed
        }
    }

    /// Queue reservation covers generation selection, source checks and all durable
    /// attachment/recovery copying. Hashing/ZIP verification subsequently use staging.
    func captureBackup(measurements: MeasurementBackupSource, photos: URL, plans: URL,
                       cancellation: BackupCancellation, applicationVersion: String? = nil,
                       parent: URL = FileManager.default.temporaryDirectory,
                       didStageFile: @escaping @Sendable (String) throws -> Void = { _ in }) async throws -> BackupStaging {
        try await run {
            guard let file = self.store as? FileMappingStore, let committed = self.committed else { throw StorageError.writesBlocked }
            let bytes = try file.backupBytes(for: committed.journal)
            let sources = BackupSources(mapping: file.url, measurements: measurements.url, photos: photos, plans: plans)
            return try OfflineBackup.capture(journal: committed.journal, mappingBytes: bytes, sources: sources,
                measurements: measurements, cancellation: cancellation, applicationVersion: applicationVersion, parent: parent, didStageFile: didStageFile)
        }
    }

    /// Retires this owner permanently. All queued and future callbacks bound to
    /// pre-restore editors are rejected, including generic attachment work.
    func restore(_ preview: RestorePreview, measurements: MeasurementBackupSource,
                 checkpoint: @escaping @Sendable (OfflineRestore.Checkpoint) throws -> Void = { _ in }) async throws -> OfflineRestore.PendingActivation {
        try await run {
            self.retired = true
            FileMeasurementStore.fileAccess.lock(); defer { FileMeasurementStore.fileAccess.unlock() }
            guard let file = self.store as? FileMappingStore, let committed = self.committed,
                  file.url.lastPathComponent == OfflineRestore.mappingName else { throw StorageError.writesBlocked }
            let bytes = try file.backupBytes(for: committed.journal)
            FileMeasurementStore.invalidateWriters(at: measurements.url)
            return try OfflineRestore.activate(preview, live: file.url.deletingLastPathComponent(),
                journal: committed.journal, mappingBytes: bytes, measurements: measurements, checkpoint: checkpoint)
        }
    }

    /// Inputs capture volatile draft/context intent; mutations always start from the
    /// latest committed graph. Callers must await and reconcile every accepted result.
    func transaction<Value: Sendable>(snapshot: MappingWorkflow.Snapshot,
                            _ action: @escaping @Sendable (inout MappingWorkflow) throws -> Value) async throws -> (MappingWorkflow.Snapshot, Value) {
        try await run {
            let base = self.committed ?? snapshot.committed
            let buffer = MappingTransactionBuffer(base.journal)
            guard let file = self.store else { throw StorageError.writesBlocked }
            var next = MappingWorkflow(snapshot: snapshot, store: buffer)
            next.prepareTransaction(committed: base, store: buffer)
            let value = try action(&next)
            // Workflow commits are buffered until the entire synchronous command
            // succeeds. Even a command that throws after commit() cannot leave disk
            // ahead of the published result. Exactly one atomic save per command.
            if buffer.changed { try file.save(next.journal) }
            self.committed = next.committed
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
