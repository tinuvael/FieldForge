import Foundation

/// Original observations remain in `observations`. Version 1 is that original;
/// corrections are an append-only chain starting at version 2. Field time is in snapshot.
struct MappingObservationRevision: Codable, Equatable, Identifiable {
    let id: UUID
    let observationID: UUID
    let version: Int
    let previousRevisionID: UUID?
    let correctedAt: Date
    let author: String?
    let reason: String
    let snapshot: MappingObservation
}

extension MappingJournal {
    func history(for observationID: UUID) -> [MappingObservationRevision] {
        revisions.filter { $0.observationID == observationID }
    }
    func effectiveObservation(id: UUID) -> MappingObservation? {
        revisions.last { $0.observationID == id }?.snapshot ?? observations.first { $0.id == id }
    }
    var effectiveObservations: [MappingObservation] {
        let latest = Dictionary(revisions.map { ($0.observationID, $0.snapshot) }, uniquingKeysWith: { _, last in last })
        return observations.map { latest[$0.id] ?? $0 }
    }
    func validateRevisions() throws {
        // Standalone diagnostics also validate the authoritative base once. The full
        // validator passes its existing context and does not repeat this work.
        if !revisions.isEmpty { try validateGraph(includingRevisions: false) }
        try validateRevisions(context: MappingValidationContext(self))
    }

    func validateRevisions(context: MappingValidationContext) throws {
        let originals = Dictionary(observations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(revisions.map(\.id)).count == revisions.count else {
            throw StorageError.invalidRecord
        }
        var latest: [UUID: MappingObservationRevision] = [:]
        var latestSets = Dictionary(observations.flatMap { $0.geology?.jointSets ?? [] }.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        // A geological UUID may recur in this point's history, never in another point/kind.
        var owners: [UUID: String] = [:]
        for snapshot in observations + revisions.map(\.snapshot) {
            for set in snapshot.geology?.jointSets ?? [] {
                let owner = "\(snapshot.id)/joint/\(set.identifier.rawValue)"
                if let old = owners[set.id], old != owner { throw StorageError.invalidRecord }
                owners[set.id] = owner
            }
            for fault in snapshot.geology?.tectonicStructures ?? [] {
                let owner = "\(snapshot.id)/tectonic"
                if let old = owners[fault.id], old != owner { throw StorageError.invalidRecord }
                owners[fault.id] = owner
            }
        }
        for revision in revisions {
            guard let original = originals[revision.observationID] else { throw StorageError.invalidRecord }
            let previous = latest[original.id]
            let snapshot = revision.snapshot
            guard revision.version == (previous?.version ?? 1) + 1,
                  revision.previousRevisionID == previous?.id,
                  revision.correctedAt.timeIntervalSinceReferenceDate.isFinite,
                  !revision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  revision.author.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
                  snapshot.id == original.id, snapshot.projectID == original.projectID,
                  snapshot.horizonID == original.horizonID, snapshot.excavationID == original.excavationID,
                  snapshot.measurementIDs == original.measurementIDs,
                  snapshot.createdAt == original.createdAt, snapshot.updatedAt == original.updatedAt else { throw StorageError.invalidRecord }
            // Evidence IDs and immutable context match the original. Global geological
            // ownership above plus per-snapshot uniqueness replace the old whole-graph
            // substitution, including UUID collisions between points and record kinds.
            try validateObservation(snapshot, context: context)
            for set in snapshot.geology?.jointSets ?? [] {
                if let old = latestSets[set.id] {
                    guard set == old || (old.revision < Int.max && set.revision == old.revision + 1 && set.interpretedAt == revision.correctedAt) else {
                        throw StorageError.invalidRecord
                    }
                } else if set.revision != 1 || set.interpretedAt != revision.correctedAt { throw StorageError.invalidRecord }
                latestSets[set.id] = set
            }
            latest[original.id] = revision
        }
    }
}

struct MappingCorrectionDraft: Equatable {
    let baseline: MappingObservation
    let previousRevisionID: UUID?
    let initial: MappingDraft
    var fields: MappingDraft
    var reason = ""
    var author = ""
    var hasChanges: Bool { fields != initial || !reason.isEmpty || !author.isEmpty }
    init(observation: MappingObservation, previousRevisionID: UUID?, measurements: [Measurement]) {
        baseline = observation; self.previousRevisionID = previousRevisionID
        initial = MappingDraft(observation: observation, measurements: measurements); fields = initial
    }

    func snapshot(now: Date) throws -> MappingObservation {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MappingError.invalid("Укажите причину исправления.")
        }
        guard fields.measurements == initial.measurements else {
            throw MappingError.invalid("Исходные замеры и их принадлежность точке изменять нельзя.")
        }
        let old = baseline
        let date = fields.observedAtOverride ?? old.observedAt
        guard let zone = TimeZone(identifier: fields.timeZoneID) else { throw StorageError.invalidRecord }
        var geology = try fields.geology(now: now)
        if let g = geology {
            geology = MappingGeology(start: g.start, end: g.end, position: g.position,
                jointSets: try fields.jointSets.map { draft in
                    try draft.corrected(previous: old.geology?.jointSets.first { $0.id == draft.id }, now: now)
                }, tectonicStructures: g.tectonicStructures)
        }
        let q = fields.bartonQ == initial.bartonQ ? old.ratings?.bartonQ :
            (try fields.bartonQ.hasChanges ? BartonQAssessment(input: fields.bartonQ, now: now) : nil)
        let rmr = fields.rmr89 == initial.rmr89 ? old.ratings?.rmr89 :
            (try fields.rmr89.hasChanges ? RMR89Assessment(input: fields.rmr89, now: now) : nil)
        let geologyUnchanged = fields.startPicket == initial.startPicket && fields.endPicket == initial.endPicket &&
            fields.jointSets == initial.jointSets && fields.tectonicStructures == initial.tectonicStructures &&
            fields.observationPosition == initial.observationPosition
        let ratings = q == nil && rmr == nil && fields.gsi == nil ? nil : MappingRatings(bartonQ: q, rmr89: rmr, gsi: fields.gsi)
        // Preserve exact historic offset (including historic zone rules) unless field date/zone changes.
        let unchangedTime = date == old.observedAt && fields.timeZoneID == old.observedTimeZoneID
        let origin = fields.chainageOriginAndDirection.trimmingCharacters(in: .whitespacesAndNewlines)
        return MappingObservation(id: old.id, projectID: old.projectID, horizonID: old.horizonID, excavationID: old.excavationID,
            picket: fields.picket == initial.picket ? old.picket : try fields.picketConvention.storedText(fields.picket),
            chainageMeters: fields.picket == initial.picket ? old.chainageMeters : try fields.picketConvention.meters(fields.picket),
            chainageOriginAndDirection: origin.isEmpty ? "unknown" : fields.chainageOriginAndDirection,
            observedAt: date, observedTimeZoneID: fields.timeZoneID,
            observedUTCOffsetSeconds: unchangedTime ? old.observedUTCOffsetSeconds : zone.secondsFromGMT(for: date),
            createdAt: old.createdAt, updatedAt: old.updatedAt,
            coordinates: fields == initial ? old.coordinates : try correctedCoordinates(),
            measurementIDs: old.measurementIDs, notes: fields.notes,
            geology: geologyUnchanged ? old.geology : geology,
            ratings: fields.bartonQ == initial.bartonQ && fields.rmr89 == initial.rmr89 && fields.gsi == initial.gsi ? old.ratings : ratings,
            picketConvention: old.picketConvention, rock: fields.rock)
    }
    private func correctedCoordinates() throws -> MappingCoordinates? {
        // A no-op edit must not invent provenance on legacy or unknown locations.
        if try fields.coordinates() == initial.coordinates() { return baseline.coordinates }
        return try fields.coordinates()
    }
}

extension MappingWorkflow {
    func correction(for id: UUID) throws -> MappingCorrectionDraft {
        guard let point = journal.effectiveObservation(id: id) else { throw StorageError.invalidRecord }
        return MappingCorrectionDraft(observation: point, previousRevisionID: journal.history(for: id).last?.id,
                                      measurements: journal.measurements(for: point))
    }
    @discardableResult mutating func saveCorrection(_ draft: MappingCorrectionDraft, now: Date = Date()) throws -> MappingObservationRevision {
        guard let current = journal.effectiveObservation(id: draft.baseline.id), current == draft.baseline,
              journal.history(for: current.id).last?.id == draft.previousRevisionID else {
            throw MappingError.invalid("Наблюдение уже изменено. Откройте актуальную версию перед исправлением.")
        }
        guard draft.initial == MappingDraft(observation: current, measurements: journal.measurements(for: current)) else {
            throw StorageError.invalidRecord
        }
        let snapshot = try draft.snapshot(now: now)
        let revision = MappingObservationRevision(id: UUID(), observationID: current.id,
            version: (journal.history(for: current.id).last?.version ?? 1) + 1, previousRevisionID: draft.previousRevisionID,
            correctedAt: now, author: draft.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.author,
            reason: draft.reason, snapshot: snapshot)
        var next = journal; next.revisions.append(revision)
        try next.validate()
        try commit(next)
        return revision
    }
}
