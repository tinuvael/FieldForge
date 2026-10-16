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
            guard previous.observations.allSatisfy({ old in journal.observations.contains(old) }) else {
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
    init(store: any MappingStore) throws { self.store = store; journal = try store.load() }
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
        draft = MappingDraft(); pendingContext = nil
    }
    mutating func confirmDiscard() throws { if let pendingContext { try applyContext(pendingContext) } }
    mutating func cancelContextChange() { pendingContext = nil }

    @discardableResult mutating func createProject(name: String) throws -> UUID {
        let name = try validName(name)
        var next = journal; let id = UUID()
        next.projects.append(MappingProject(id: id, name: name)); try commit(next); return id
    }
    @discardableResult mutating func createHorizon(name: String, elevation: String = "", datum: String = "неизвестно") throws -> UUID {
        guard let p = context.projectID else { throw MappingError.invalid("Сначала выберите проект.") }
        let name = try validName(name)
        var height: Double?
        if !elevation.isEmpty {
            guard let value = Double(elevation.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
                throw MappingError.invalid("Высотная отметка должна быть конечным числом в метрах.")
            }
            height = value
        }
        var next = journal; let id = UUID()
        next.horizons.append(MappingHorizon(id: id, projectID: p, name: name, elevationMeters: height, elevationDatum: try validName(datum)))
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
    mutating func updateHorizon(id: UUID, name: String, elevation: String, datum: String) throws {
        var next = journal
        guard let i = next.horizons.firstIndex(where: { $0.id == id }) else { throw StorageError.invalidRecord }
        let value = elevation.isEmpty ? nil : Double(elevation.replacingOccurrences(of: ",", with: "."))
        guard elevation.isEmpty || value?.isFinite == true else { throw MappingError.invalid("Некорректная высотная отметка.") }
        next.horizons[i].name = try validName(name); next.horizons[i].elevationMeters = value
        next.horizons[i].elevationDatum = try validName(datum); try commit(next)
    }
    mutating func updateExcavation(id: UUID, name: String, horizonIDs: Set<UUID>) throws {
        var next = journal
        guard let i = next.excavations.firstIndex(where: { $0.id == id }) else { throw StorageError.invalidRecord }
        next.excavations[i].name = try validName(name); next.excavations[i].horizonIDs = horizonIDs
        try commit(next)
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
            coordinates: try draft.coordinates(), measurementIDs: [], notes: draft.notes)
        var next = journal; next.observations.append(record)
        try commit(next)
        draft = MappingDraft(); pendingContext = nil
        return record
    }
}
