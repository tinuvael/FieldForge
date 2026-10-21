import Foundation

protocol MappingStore {
    func load() throws -> MappingJournal
    func save(_ journal: MappingJournal) throws
}

/// One serialized main-actor owner in the app. Every commit validates the entire graph.
final class FileMappingStore: MappingStore {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("previous") }
    private var loaded = false
    private var blocked = false
    private var loadedBytes: Data?
    init(url: URL) { self.url = url }
    private func bytes() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func load() throws -> MappingJournal {
        do {
            let data = try bytes()
            let value = try data.map { try JSONDecoder().decode(MappingJournal.self, from: $0) } ?? MappingJournal()
            try value.validate()
            loadedBytes = data; loaded = true; blocked = false
            return value
        } catch { blocked = true; throw error }
    }
    func save(_ journal: MappingJournal) throws {
        guard !blocked else { throw StorageError.writesBlocked }
        if !loaded { _ = try load() }
        try journal.validate()
        guard try bytes() == loadedBytes else { throw StorageError.changedFile }
        // Original observations are append-only; names/metadata can be managed separately.
        if let loadedBytes {
            let previous = try JSONDecoder().decode(MappingJournal.self, from: loadedBytes)
            guard previous.photos.allSatisfy({ journal.photos.contains($0) }),
                  previous.photoAttachments.allSatisfy({ journal.photoAttachments.contains($0) }),
                  previous.photoRevisions.allSatisfy({ journal.photoRevisions.contains($0) }),
                  previous.revisions.allSatisfy({ journal.revisions.contains($0) }),
                  previous.observations.allSatisfy({ old in journal.observations.contains(old) }),
                  previous.measurements.allSatisfy({ old in journal.measurements.contains(old) }),
                  previous.plans.allSatisfy({ old in journal.plans.contains(old) }) else {
                throw StorageError.invalidRecord
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(journal)
        guard try JSONDecoder().decode(MappingJournal.self, from: data) == journal else { throw StorageError.invalidRecord }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let loadedBytes { try loadedBytes.write(to: backupURL, options: .atomic) }
        guard try bytes() == loadedBytes else { throw StorageError.changedFile }
        try data.write(to: url, options: .atomic)
        loadedBytes = data
    }
}

/// Platform-independent capture state machine. Commit first, then publish/reset.
struct MappingWorkflow {
    private(set) var journal: MappingJournal
    var draft = MappingDraft()
    private(set) var pendingContext: MappingContext?
    // Volatile drafts retain their original spatial frame until explicitly revisited.
    private(set) var suspendedDrafts: [(context: MappingContext, draft: MappingDraft)] = []
    var retainedDraftIDs: Set<UUID> { Set(suspendedDrafts.map { $0.draft.id } + [draft.id]) }
    private let store: any MappingStore
    init(store: any MappingStore) throws {
        self.store = store; journal = try store.load()
        draft.suggestElevation(selectedHorizon)
    }
    var selectedHorizon: MappingHorizon? { journal.horizons.first { $0.id == context.horizonID } }
    private mutating func resetDraft() { draft = MappingDraft(); draft.suggestElevation(selectedHorizon) }
    var context: MappingContext { journal.selection }
    var horizons: [MappingHorizon] { journal.horizons.filter { $0.projectID == context.projectID } }
    var excavations: [MappingExcavation] {
        guard let horizonID = context.horizonID else { return [] }
        return journal.excavations.filter { $0.projectID == context.projectID && $0.horizonIDs.contains(horizonID) }
    }
    var observations: [MappingObservation] { journal.effectiveObservations.filter { $0.projectID == context.projectID } }
    mutating func commit(_ next: MappingJournal) throws { try store.save(next); journal = next }

    mutating func requestContext(_ next: MappingContext) throws {
        guard !draft.saving else { throw MappingError.invalid("Дождитесь сохранения наблюдения.") }
        guard journal.validContext(next) else { throw StorageError.invalidRecord }
        guard next != context else { return }
        if next.projectID == context.projectID && next.horizonID == context.horizonID {
            var updated = journal; updated.selection = next
            try commit(updated)
            pendingContext = nil
        } else if draft.hasChanges { pendingContext = next } else { try switchPreservingDraft(to: next) }
    }
    private mutating func applyContext(_ next: MappingContext) throws {
        guard !draft.saving else { throw MappingError.invalid("Дождитесь сохранения наблюдения.") }
        var updated = journal; updated.selection = next
        try commit(updated)
        resetDraft(); pendingContext = nil
    }
    mutating func preserveAndSwitch() throws {
        if let pendingContext { try switchPreservingDraft(to: pendingContext) }
    }
    private mutating func switchPreservingDraft(to next: MappingContext) throws {
        guard draft.photoSessions.isEmpty else {
            throw MappingError.invalid("Дождитесь завершения получения фотографий перед сменой проекта или горизонта.")
        }
        let returning = suspendedDrafts.firstIndex { $0.context.projectID == next.projectID && $0.context.horizonID == next.horizonID }
        let restored = returning.map { suspendedDrafts[$0] }
        var updated = journal; updated.selection = restored?.context ?? next
        guard journal.validContext(updated.selection) else { throw StorageError.invalidRecord }
        let oldContext = context, oldDraft = draft
        try commit(updated)
        if let returning { suspendedDrafts.remove(at: returning) }
        if oldDraft.hasChanges { suspendedDrafts.append((oldContext, oldDraft)) }
        if let restored { draft = restored.draft } else { resetDraft() }
        pendingContext = nil
    }
    mutating func confirmDiscard() throws { if let pendingContext { try applyContext(pendingContext) } }
    mutating func cancelContextChange() { pendingContext = nil }

    @discardableResult mutating func createProject(name: String) throws -> UUID {
        let name = try validName(name)
        var next = journal; let id = UUID()
        next.projects.append(MappingProject(id: id, name: name)); try commit(next); return id
    }
    @discardableResult mutating func createHorizon(elevation: String, datum: String = "неизвестно") throws -> UUID {
        guard let p = context.projectID else { throw MappingError.invalid("Сначала выберите проект.") }
        let height = try ElevationInput.meters(elevation)
        var next = journal; let id = UUID()
        next.horizons.append(MappingHorizon(id: id, projectID: p, name: ElevationInput.label(height),
            elevationMeters: height, elevationDatum: try validName(datum)))
        try commit(next); return id
    }
    @discardableResult mutating func createExcavation(name: String, horizonIDs: Set<UUID>) throws -> UUID {
        guard let p = context.projectID else { throw MappingError.invalid("Сначала выберите проект.") }
        var next = journal; let id = UUID()
        next.excavations.append(MappingExcavation(id: id, projectID: p, name: try validName(name), horizonIDs: horizonIDs))
        try commit(next); return id
    }
    mutating func updateProject(id: UUID, name: String) throws {
        var next = journal
        guard let i = next.projects.firstIndex(where: { $0.id == id }) else { throw StorageError.invalidRecord }
        next.projects[i].name = try validName(name); try commit(next)
    }
    mutating func updateHorizon(id: UUID, elevation: String, datum: String) throws {
        var next = journal
        guard let i = next.horizons.firstIndex(where: { $0.id == id }) else { throw StorageError.invalidRecord }
        // Keep legacy names and identities. Historical observations retain their frozen Z and datum.
        next.horizons[i].elevationMeters = try ElevationInput.meters(elevation)
        next.horizons[i].elevationDatum = try validName(datum)
        try commit(next)
        if context.horizonID == id { draft.suggestElevation(selectedHorizon) }
    }
    mutating func updateExcavation(id: UUID, name: String, horizonIDs: Set<UUID>) throws {
        var next = journal
        guard let i = next.excavations.firstIndex(where: { $0.id == id }) else { throw StorageError.invalidRecord }
        next.excavations[i].name = try validName(name); next.excavations[i].horizonIDs = horizonIDs
        try commit(next)
    }
    var plans: [MappingPlanReference] { journal.plans.filter { $0.horizonID == context.horizonID } }
    mutating func registerPlan(_ plan: MappingPlanReference) throws {
        guard journal.horizons.contains(where: { $0.id == plan.horizonID }) else { throw StorageError.invalidRecord }
        if journal.plans.contains(plan) { return }
        var next = journal; next.plans.append(plan); try commit(next)
    }
    mutating func selectPlanPoint(_ point: PlanPoint, planID: UUID) throws {
        guard !draft.saving else { throw MappingError.invalid("Дождитесь сохранения наблюдения.") }
        guard let plan = plans.first(where: { $0.id == planID }),
              journal.horizons.contains(where: { $0.id == plan.horizonID && $0.projectID == context.projectID }) else { throw StorageError.invalidRecord }
        try draft.selectPlanPoint(point, plan: plan)
    }
    func points(on plan: MappingPlanReference, excavationID: UUID? = nil, restrictToSelection: Bool = true) -> [MappingObservation] {
        guard journal.plans.contains(plan), !restrictToSelection || plans.contains(plan) else { return [] }
        // No inferred compatibility between different revisions/CRSs, including manual P1 coordinates.
        return journal.effectiveObservations.filter { $0.horizonID == plan.horizonID && $0.coordinates?.planID == plan.id &&
            $0.coordinates?.x != nil && $0.coordinates?.y != nil && (excavationID == nil || $0.excavationID == excavationID) }
    }
    private func validName(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MappingError.invalid("Название не может быть пустым.") }
        return value
    }
    func draftRecord(now: Date) throws -> MappingObservation {
        guard let p = context.projectID, let h = context.horizonID, let e = context.excavationID else {
            throw MappingError.invalid("Выберите проект, горизонт и выработку.")
        }
        let chainage = try draft.picketConvention.meters(draft.picket)
        let observed = draft.observedAtOverride ?? now
        guard let zone = TimeZone(identifier: draft.timeZoneID) else { throw StorageError.invalidRecord }
        let origin = draft.chainageOriginAndDirection.trimmingCharacters(in: .whitespacesAndNewlines)
        return MappingObservation(id: draft.id, projectID: p, horizonID: h, excavationID: e,
            picket: draft.picket, chainageMeters: chainage,
            chainageOriginAndDirection: origin.isEmpty ? "unknown" : origin,
            observedAt: observed, observedTimeZoneID: zone.identifier,
            observedUTCOffsetSeconds: zone.secondsFromGMT(for: observed), createdAt: now, updatedAt: now,
            coordinates: try draft.coordinates(), measurementIDs: draft.measurements.map(\.id), notes: draft.notes,
            geology: try draft.geology(now: now), ratings: try draft.ratings(now: now), picketConvention: draft.picketConvention)
    }
    @discardableResult mutating func save(now: Date = Date(), preparedPhotos: [PhotoImportOperation] = []) throws -> MappingObservation {
        guard draft.photoSessions.isEmpty else { throw MappingError.invalid("Дождитесь завершения выбора и получения всех фотографий.") }
        guard preparedPhotos == draft.photos else { throw MappingError.invalid("Сначала запишите все фотографии черновика. Повторите сохранение наблюдения.") }
        let record = try draftRecord(now: now)
        var next = journal; next.observations.append(record)
        next.measurements.append(contentsOf: draft.measurements)
        for operation in preparedPhotos {
            try operation.validate()
            let c = operation.photo.context
            guard c.pointID == draft.id, c.pointRevisionID == draft.id, c.pointVersion == 1,
                  c.projectID == record.projectID, c.horizonID == record.horizonID,
                  c.locationBasis == .unknownBeforeFirstSave else { throw StorageError.invalidRecord }
            next.photos.append(operation.photo); next.photoAttachments.append(operation.attachment)
        }
        try commit(next)
        resetDraft(); pendingContext = nil
        return record
    }
}
