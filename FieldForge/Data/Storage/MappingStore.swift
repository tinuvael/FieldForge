import Foundation

protocol MappingStore {
    func load() throws -> MappingJournal
    func save(_ journal: MappingJournal) throws
}

/// One serialized main-actor owner in the app. Every commit validates the entire graph.
final class FileMappingStore: MappingStore {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("previous") }
    var migrationBackupURL: URL { url.appendingPathExtension("p1-backup") }
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
            var data = try bytes()
            var value = try data.map { try JSONDecoder().decode(MappingJournal.self, from: $0) } ?? MappingJournal()
            try value.validate()
            if value.schemaVersion < 4, let original = data {
                let migrationBackupURL = url.appendingPathExtension("p\(value.schemaVersion)-backup")
                value.schemaVersion = 4
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                let migrated = try encoder.encode(value)
                guard try JSONDecoder().decode(MappingJournal.self, from: migrated) == value else { throw StorageError.invalidRecord }
                if FileManager.default.fileExists(atPath: migrationBackupURL.path) {
                    guard try Data(contentsOf: migrationBackupURL) == original else { throw StorageError.invalidRecord }
                } else {
                    try original.write(to: migrationBackupURL, options: .withoutOverwriting)
                }
                guard try Data(contentsOf: migrationBackupURL) == original, try bytes() == original else { throw StorageError.changedFile }
                try migrated.write(to: url, options: .atomic)
                data = migrated
            }
            loadedBytes = data; loaded = true; blocked = false
            return value
        } catch { blocked = true; throw error }
    }
    func save(_ journal: MappingJournal) throws {
        guard !blocked else { throw StorageError.writesBlocked }
        if !loaded { _ = try load() }
        guard journal.schemaVersion == 4 else { throw StorageError.unsupportedVersion }
        try journal.validate()
        guard try bytes() == loadedBytes else { throw StorageError.changedFile }
        // Original observations are append-only; names/metadata can be managed separately.
        if let loadedBytes {
            let previous = try JSONDecoder().decode(MappingJournal.self, from: loadedBytes)
            guard previous.observations.allSatisfy({ old in journal.observations.contains(old) }),
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
    var observations: [MappingObservation] { journal.observations.filter { $0.projectID == context.projectID } }
    private mutating func commit(_ next: MappingJournal) throws { try store.save(next); journal = next }

    mutating func requestContext(_ next: MappingContext) throws {
        guard journal.validContext(next) else { throw StorageError.invalidRecord }
        guard next != context else { return }
        if draft.hasChanges { pendingContext = next } else { try applyContext(next) }
    }
    private mutating func applyContext(_ next: MappingContext) throws {
        var updated = journal; updated.selection = next
        try commit(updated)
        resetDraft(); pendingContext = nil
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
        guard let plan = plans.first(where: { $0.id == planID }),
              journal.horizons.contains(where: { $0.id == plan.horizonID && $0.projectID == context.projectID }) else { throw StorageError.invalidRecord }
        try draft.selectPlanPoint(point, plan: plan)
    }
    func points(on plan: MappingPlanReference, excavationID: UUID? = nil) -> [MappingObservation] {
        guard plans.contains(plan) else { return [] }
        // No inferred compatibility between different revisions/CRSs, including manual P1 coordinates.
        return observations.filter { $0.horizonID == plan.horizonID && $0.coordinates?.planID == plan.id &&
            $0.coordinates?.x != nil && $0.coordinates?.y != nil && (excavationID == nil || $0.excavationID == excavationID) }
    }
    private func validName(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MappingError.invalid("Название не может быть пустым.") }
        return value
    }
    @discardableResult mutating func save(now: Date = Date()) throws -> MappingObservation {
        guard let p = context.projectID, let h = context.horizonID, let e = context.excavationID else {
            throw MappingError.invalid("Выберите проект, горизонт и выработку.")
        }
        let chainage = try PicketInput.meters(draft.picket)
        let observed = draft.observedAtOverride ?? now
        guard let zone = TimeZone(identifier: draft.timeZoneID) else { throw StorageError.invalidRecord }
        let origin = draft.chainageOriginAndDirection.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = MappingObservation(id: UUID(), projectID: p, horizonID: h, excavationID: e,
            picket: draft.picket, chainageMeters: chainage,
            chainageOriginAndDirection: origin.isEmpty ? "unknown" : origin,
            observedAt: observed, observedTimeZoneID: zone.identifier,
            observedUTCOffsetSeconds: zone.secondsFromGMT(for: observed), createdAt: now, updatedAt: now,
            coordinates: try draft.coordinates(), measurementIDs: draft.measurements.map(\.id), notes: draft.notes,
            geology: try draft.geology(now: now))
        var next = journal; next.observations.append(record)
        next.measurements.append(contentsOf: draft.measurements)
        try commit(next)
        resetDraft(); pendingContext = nil
        return record
    }
}
