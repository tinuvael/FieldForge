import Foundation

struct MappingImportSource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case exchange, regulatoryData }
    let kind: Kind
    let documentID: String
    let fingerprint: String

    init(kind: Kind, documentID: String, bytes: Data) {
        self.kind = kind
        self.documentID = documentID
        fingerprint = ExchangeBaseline.hash(bytes)
    }
}

struct MappingImportTarget: Codable, Equatable, Sendable {
    let observationID: UUID
    let projectID: UUID
    let horizonID: UUID
    let excavationID: UUID

    init(_ point: MappingObservation) {
        observationID = point.id
        projectID = point.projectID
        horizonID = point.horizonID
        excavationID = point.excavationID
    }

    var context: MappingContext {
        MappingContext(projectID: projectID, horizonID: horizonID, excavationID: excavationID)
    }
}

struct MappingImportBaseline: Codable, Equatable, Sendable {
    let revisionID: UUID?
    let version: Int
    let fingerprint: String

    static func capture(target: MappingImportTarget, in preview: MappingCommittedSnapshot) throws -> Self {
        guard let point = preview.observation(id: target.observationID) else { throw MappingImportConflict.targetMissing }
        guard MappingImportTarget(point) == target else { throw MappingImportConflict.ownershipChanged }
        let revision = preview.latestRevisions[target.observationID]
        return Self(revisionID: revision?.id, version: revision?.version ?? 1,
                    fingerprint: try MappingImportLedger.fingerprint(point))
    }
}

/// Immutable intent. The approved observation is transient; only its digest is persisted.
struct MappingImportOperation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case create, update, skip, conflict }
    struct Correction: Codable, Equatable, Sendable {
        let date: Date
        let author: String?
        let reason: String
    }
    struct SourceRecord: Codable, Hashable, Sendable {
        let kind: MappingImportSource.Kind
        let documentID: String
        let recordID: String
    }
    struct SourceVersion: Hashable {
        let record: SourceRecord
        let fingerprint: String
    }

    let id: UUID
    let source: MappingImportSource
    let sourceRecordID: String
    let target: MappingImportTarget
    let kind: Kind
    let baseline: MappingImportBaseline?
    let proposalFingerprint: String?
    let creationDate: Date?
    let correction: Correction?
    let note: String?

    init(id: UUID = UUID(), source: MappingImportSource, sourceRecordID: String, target: MappingImportTarget,
         kind: Kind, baseline: MappingImportBaseline? = nil, proposal: MappingObservation? = nil,
         correction: Correction? = nil, note: String? = nil) throws {
        self.id = id
        self.source = source
        self.sourceRecordID = sourceRecordID
        self.target = target
        self.kind = kind
        self.baseline = baseline
        proposalFingerprint = try proposal.map { try MappingImportLedger.fingerprint($0) }
        creationDate = kind == .create ? proposal?.createdAt : nil
        self.correction = correction
        self.note = note
        try validate()
    }

    var sourceRecord: SourceRecord {
        SourceRecord(kind: source.kind, documentID: source.documentID, recordID: sourceRecordID)
    }
    var sourceVersion: SourceVersion { SourceVersion(record: sourceRecord, fingerprint: source.fingerprint) }
    var isMutation: Bool { kind == .create || kind == .update }

    func validate() throws {
        func nonblank(_ value: String, limit: Int) -> Bool {
            value.utf8.count <= limit && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func isDigest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard nonblank(source.documentID, limit: 512), nonblank(sourceRecordID, limit: 512),
              isDigest(source.fingerprint), note.map({ nonblank($0, limit: 2048) }) ?? (kind != .conflict),
              isMutation == (proposalFingerprint != nil), proposalFingerprint.map(isDigest) ?? true,
              (kind == .create) == (creationDate != nil), creationDate?.timeIntervalSinceReferenceDate.isFinite ?? true,
              (kind == .update) == (correction != nil),
              kind != .create || baseline == nil, kind != .update || baseline != nil else {
            throw StorageError.invalidRecord
        }
        if let baseline {
            guard baseline.version > 0, baseline.version < Int.max,
                  (baseline.version == 1) == (baseline.revisionID == nil),
                  isDigest(baseline.fingerprint) else { throw StorageError.invalidRecord }
        }
        if let correction {
            guard correction.date.timeIntervalSinceReferenceDate.isFinite,
                  nonblank(correction.reason, limit: 2048),
                  correction.author.map({ nonblank($0, limit: 512) }) ?? true else {
                throw StorageError.invalidRecord
            }
        }
    }
}

enum MappingImportConflict: Error, Codable, Equatable, Sendable {
    case operationIDReused
    case duplicateSourceRecord(operationID: UUID)
    case sourceChanged
    case proposalChanged
    case ownershipChanged
    case targetExists
    case targetMissing
    case revisionChanged(currentID: UUID?, version: Int)
    case observationChanged
    case revisionIDInUse
    case protectedEvidence
    case invalidProposal
    case previewConflict
}

enum MappingImportOutcome: Codable, Equatable, Sendable {
    case pending
    case applied
    case skipped
    case rejected(MappingImportConflict)
}

struct MappingImportLedger: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let operation: MappingImportOperation
        let outcome: MappingImportOutcome

        var reservesSource: Bool { outcome == .pending || outcome == .applied }

        func reservesSource(against other: MappingImportOperation) -> Bool {
            reservesSource && operation.id != other.id && operation.sourceRecord == other.sourceRecord &&
                (operation.sourceVersion == other.sourceVersion || other.kind == .create || operation.target != other.target)
        }
    }

    private static let formatVersion = 1
    private(set) var entries: [Entry] = []

    init() {}
    private enum CodingKeys: String, CodingKey { case version, entries, fingerprint }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .version) == Self.formatVersion else { throw StorageError.invalidRecord }
        entries = try c.decode([Entry].self, forKey: .entries)
        guard try c.decode(String.self, forKey: .fingerprint) == Self.fingerprint(entries) else {
            throw StorageError.invalidRecord
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.formatVersion, forKey: .version)
        try c.encode(entries, forKey: .entries)
        try c.encode(Self.fingerprint(entries), forKey: .fingerprint)
    }

    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        ExchangeBaseline.hash(Data(try MappingExchangeExport.json(value).utf8))
    }

    subscript(id: UUID) -> Entry? { entries.first { $0.operation.id == id } }

    mutating func record(_ operation: MappingImportOperation, outcome: MappingImportOutcome) {
        let entry = Entry(operation: operation, outcome: outcome)
        if let index = entries.firstIndex(where: { $0.operation.id == operation.id }) { entries[index] = entry }
        else { entries.append(entry) }
    }

    func preserves(_ previous: Self) -> Bool {
        guard entries.count >= previous.entries.count,
              entries.dropFirst(previous.entries.count).allSatisfy({ $0.outcome != .applied }) else { return false }
        return zip(previous.entries, entries).allSatisfy { old, next in
            guard old.operation == next.operation else { return false }
            if old.outcome == next.outcome { return true }
            guard old.outcome == .pending else { return false }
            if case .rejected = next.outcome { return true }
            return next.outcome == .applied
        }
    }

    /// Receipts prove the exact applied snapshot still exists, even after later corrections.
    /// Called after graph validation has established unique original and revision UUIDs.
    func validate(in journal: MappingJournal) throws {
        guard !entries.isEmpty else { throw StorageError.invalidRecord }
        let originals = Dictionary(uniqueKeysWithValues: journal.observations.map { ($0.id, $0) })
        let revisions = Dictionary(uniqueKeysWithValues: journal.revisions.map { ($0.id, $0) })
        var operationIDs = Set<UUID>()
        var sourceVersions = Set<MappingImportOperation.SourceVersion>()
        var bindings: [MappingImportOperation.SourceRecord: MappingImportTarget] = [:]
        for entry in entries {
            let op = entry.operation
            try op.validate()
            guard operationIDs.insert(op.id).inserted else { throw StorageError.invalidRecord }
            if entry.reservesSource {
                let target = bindings[op.sourceRecord]
                guard op.isMutation, sourceVersions.insert(op.sourceVersion).inserted,
                      target == nil || (target == op.target && op.kind == .update) else {
                    throw StorageError.invalidRecord
                }
                bindings[op.sourceRecord] = op.target
            }
            switch entry.outcome {
            case .applied:
                guard let original = originals[op.target.observationID], MappingImportTarget(original) == op.target else {
                    throw StorageError.invalidRecord
                }
                var applied = original
                if let date = op.creationDate, original.createdAt != date { throw StorageError.invalidRecord }
                if let baseline = op.baseline, let correction = op.correction {
                    guard let revision = revisions[op.id], revision.observationID == original.id,
                          revision.previousRevisionID == baseline.revisionID, revision.version == baseline.version + 1,
                          revision.correctedAt == correction.date, revision.author == correction.author,
                          revision.reason == correction.reason else { throw StorageError.invalidRecord }
                    let previous = revision.previousRevisionID.flatMap { revisions[$0]?.snapshot } ?? original
                    guard try Self.fingerprint(previous) == baseline.fingerprint else { throw StorageError.invalidRecord }
                    applied = revision.snapshot
                }
                guard try Self.fingerprint(applied) == op.proposalFingerprint else { throw StorageError.invalidRecord }
            case .pending:
                // A partial final commit cannot be produced by the single-file protocol.
                if op.kind == .update, revisions[op.id] != nil { throw StorageError.invalidRecord }
                if op.kind == .create, let original = originals[op.target.observationID],
                   try Self.fingerprint(original) == op.proposalFingerprint { throw StorageError.invalidRecord }
            case .skipped:
                guard op.kind == .skip || op.kind == .update else { throw StorageError.invalidRecord }
            case .rejected:
                break
            }
        }
    }
}
