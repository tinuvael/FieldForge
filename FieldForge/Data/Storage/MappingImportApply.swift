import Foundation

struct MappingImportRecovery: Equatable, Sendable {
    let operation: MappingImportOperation
    /// Nil means that the same approved source and proposal can be resubmitted.
    let conflict: MappingImportConflict?
}

/// Internal Stage 4a commands. All reads, validations and commits run on the
/// MappingStorageOwner queue. The only durable payload is the existing journal.
enum MappingImportApply {
    enum Checkpoint: Sendable { case beforeIntent, afterIntent, afterCommit }

    static func execute(_ operation: MappingImportOperation, source: MappingImportSource,
                        proposal: MappingObservation?, current: MappingCommittedSnapshot,
                        save: (MappingJournal) throws -> Void,
                        checkpoint: (Checkpoint) throws -> Void) throws -> MappingImportOutcome {
        try operation.validate()
        let existing = current.journal.importLedger?[operation.id]
        if let existing, existing.operation != operation { throw MappingImportConflict.operationIDReused }
        guard source == operation.source else { throw MappingImportConflict.sourceChanged }
        guard try proposal.map({ try MappingImportLedger.fingerprint($0) }) == operation.proposalFingerprint else {
            throw MappingImportConflict.proposalChanged
        }
        if let existing, existing.outcome != .pending { return existing.outcome }

        var next = current.journal
        let outcome: MappingImportOutcome
        switch operation.kind {
        case .skip:
            outcome = .skipped
        case .conflict:
            outcome = .rejected(.previewConflict)
        case .create, .update:
            guard let proposal else { throw StorageError.invalidRecord }
            outcome = try prepare(operation, proposal: proposal, current: current, next: &next)
        }
        if outcome == .applied, existing == nil {
            try checkpoint(.beforeIntent)
            var intent = current.journal
            intent.recordImport(operation, outcome: .pending)
            try save(intent)
            try checkpoint(.afterIntent)
        }
        next.recordImport(operation, outcome: outcome)
        try save(next)
        if outcome == .applied { try checkpoint(.afterCommit) }
        return outcome
    }

    static func rejectPending(_ operation: MappingImportOperation, source: MappingImportSource,
                              current: MappingCommittedSnapshot, save: (MappingJournal) throws -> Void) throws -> MappingImportOutcome {
        guard source == operation.source else { throw MappingImportConflict.sourceChanged }
        guard let entry = current.journal.importLedger?[operation.id], entry.operation == operation else {
            throw MappingImportConflict.operationIDReused
        }
        if entry.outcome != .pending { return entry.outcome }
        let outcome = MappingImportOutcome.rejected(try precondition(for: operation, in: current) ?? .previewConflict)
        var next = current.journal
        next.recordImport(operation, outcome: outcome)
        try save(next)
        return outcome
    }

    static func recovery(in current: MappingCommittedSnapshot) throws -> [MappingImportRecovery] {
        try (current.journal.importLedger?.entries ?? []).filter { $0.outcome == .pending }.map { entry in
            MappingImportRecovery(operation: entry.operation, conflict: try precondition(for: entry.operation, in: current))
        }
    }

    private static func precondition(for operation: MappingImportOperation,
                                     in current: MappingCommittedSnapshot) throws -> MappingImportConflict? {
        let journal = current.journal
        if let duplicate = journal.importLedger?.entries.first(where: { $0.reservesSource(against: operation) }) {
            return .duplicateSourceRecord(operationID: duplicate.operation.id)
        }
        if operation.kind == .create, operation.source.kind == .regulatoryData,
           let note = operation.note, let assignment = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note),
           let chainage = assignment.resolvedChainage,
           let pending = journal.importLedger?.entries.first(where: { entry in
               guard entry.outcome == .pending, entry.operation.id != operation.id,
                     entry.operation.source.kind == .regulatoryData, entry.operation.kind == .create,
                     entry.operation.target.context == operation.target.context,
                     let note = entry.operation.note,
                     let other = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note) else { return false }
               return chainage == other.resolvedChainage
           }) { return .duplicateSourceRecord(operationID: pending.operation.id) }
        guard journal.validContext(operation.target.context) else { return .ownershipChanged }
        let observation = current.observation(id: operation.target.observationID)
        if let observation, MappingImportTarget(observation) != operation.target { return .ownershipChanged }
        guard let baseline = operation.baseline else {
            guard observation == nil else { return .targetExists }
            if let expected = operation.graphFingerprint,
               try MappingExchangeExport.importContextFingerprint(operation.target, in: current) != expected { return .contextChanged }
            return nil
        }
        guard let observation else { return .targetMissing }
        let revision = current.latestRevisions[observation.id]
        let version = revision?.version ?? 1
        guard baseline.revisionID == revision?.id, baseline.version == version else {
            return .revisionChanged(currentID: revision?.id, version: version)
        }
        guard try MappingImportLedger.fingerprint(observation) == baseline.fingerprint else { return .observationChanged }
        if let expected = operation.graphFingerprint,
           try MappingExchangeExport.fingerprint(observation.id, in: current) != expected { return .contextChanged }
        guard !journal.revisions.contains(where: { $0.id == operation.id }) else { return .revisionIDInUse }
        return nil
    }

    private static func prepare(_ operation: MappingImportOperation, proposal: MappingObservation,
                                current: MappingCommittedSnapshot, next: inout MappingJournal) throws -> MappingImportOutcome {
        if let conflict = try precondition(for: operation, in: current) { return .rejected(conflict) }
        guard MappingImportTarget(proposal) == operation.target else { return .rejected(.ownershipChanged) }
        if let correction = operation.correction,
           let point = current.observation(id: operation.target.observationID) {
            if operation.source.kind == .regulatoryData {
                guard operation.graphFingerprint != nil,
                      RegulatoryDataImport.preservesEvidence(proposal, from: point, in: current) else {
                    return .rejected(.protectedEvidence)
                }
            } else {
                let historicalSets = point.geology?.jointSets.filter { !$0.identifier.isRoutine } ?? []
                guard proposal.measurementIDs == point.measurementIDs,
                      proposal.geology?.jointSets.filter({ !$0.identifier.isRoutine }) ?? [] == historicalSets,
                      ExchangeObservationProposal.ratingsAllowed(proposal.ratings, from: point.ratings) else {
                    return .rejected(.protectedEvidence)
                }
                if operation.graphFingerprint != nil,
                   !ExchangeObservationProposal.preservesEvidence(proposal, from: point) { return .rejected(.protectedEvidence) }
            }
            if proposal == point { return .skipped }
            next.appendCorrection(id: operation.id, snapshot: proposal, now: correction.date,
                                  author: correction.author, reason: correction.reason)
        } else {
            guard proposal.measurementIDs.isEmpty,
                  proposal.geology?.jointSets.contains(where: { !$0.identifier.isRoutine }) != true else {
                return .rejected(.protectedEvidence)
            }
            if operation.source.kind == .regulatoryData {
                guard operation.graphFingerprint != nil,
                      RegulatoryDataImport.preservesEvidence(proposal, from: nil, in: current) else {
                    return .rejected(.protectedEvidence)
                }
            }
            next.observations.append(proposal)
        }
        // Validate the final graph (including the receipt on retry) before any new
        // intent is persisted. Rejecting a proposal writes only the diagnostic.
        var candidate = next
        candidate.recordImport(operation, outcome: .applied)
        do { try candidate.validate() }
        catch {
            next = current.journal
            return .rejected(.invalidProposal)
        }
        return .applied
    }
}

private extension MappingJournal {
    mutating func recordImport(_ operation: MappingImportOperation, outcome: MappingImportOutcome) {
        var ledger = importLedger ?? MappingImportLedger()
        ledger.record(operation, outcome: outcome)
        importLedger = ledger
    }
}
