import Foundation

/// One immutable journal generation and its disposable read indexes. Construct on
/// the storage queue after load/commit; never encode indexes or update them in place.
/// Retaining this value freezes committed evidence independently of capture drafts.
final class MappingCommittedSnapshot: Sendable {
    /// Ephemeral generation identity; never persisted or encoded.
    let generationID = UUID()
    let journal: MappingJournal
    let effectiveObservations: [MappingObservation]
    let latestRevisions: [UUID: MappingObservationRevision]
    let projects: [UUID: MappingProject]
    let horizons: [UUID: MappingHorizon]
    let excavations: [UUID: MappingExcavation]
    private let observationOffsets: [UUID: Int]
    private let projectOffsets: [UUID: [Int]]
    private let horizonOffsets: [UUID: [Int]]
    private let measurementsByID: [UUID: Measurement]
    private let plansByID: [UUID: MappingPlanReference]
    let sourceByID: [UUID: RegulatorySourceObservation]
    private let sourcesByProject: [UUID: [RegulatorySourceObservation]]
    private let sourcesByHorizon: [UUID: [RegulatorySourceObservation]]

    init(_ journal: MappingJournal) {
        self.journal = journal
        let latest = Dictionary(journal.revisions.map { ($0.observationID, $0) }, uniquingKeysWith: { _, last in last })
        latestRevisions = latest
        let effective = journal.observations.map { latest[$0.id]?.snapshot ?? $0 }
        effectiveObservations = effective
        observationOffsets = Dictionary(effective.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        projectOffsets = Dictionary(grouping: effective.indices, by: { effective[$0].projectID })
        horizonOffsets = Dictionary(grouping: effective.indices, by: { effective[$0].horizonID })
        projects = Dictionary(journal.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        horizons = Dictionary(journal.horizons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        excavations = Dictionary(journal.excavations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        measurementsByID = Dictionary(journal.measurements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sources = journal.regulatorySourceObservations ?? []
        sourceByID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sourcesByProject = Dictionary(grouping: sources, by: { $0.key.projectID })
        sourcesByHorizon = Dictionary(grouping: sources.filter { $0.latest?.destination.horizonID != nil },
                                      by: { $0.latest!.destination.horizonID! })
        plansByID = Dictionary(journal.plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func plan(id: UUID) -> MappingPlanReference? { plansByID[id] }
    func observation(id: UUID) -> MappingObservation? { observationOffsets[id].map { effectiveObservations[$0] } }
    func observationCount(projectID: UUID?) -> Int { projectID.flatMap { projectOffsets[$0]?.count } ?? 0 }
    func observations(projectID: UUID?) -> [MappingObservation] {
        guard let projectID else { return [] }
        return (projectOffsets[projectID] ?? []).map { effectiveObservations[$0] }
    }
    func observations(context: MappingContext) -> [MappingObservation] {
        guard let projectID = context.projectID, let horizonID = context.horizonID,
              let excavationID = context.excavationID else { return [] }
        return (horizonOffsets[horizonID] ?? []).map { effectiveObservations[$0] }.filter {
            $0.projectID == projectID && $0.excavationID == excavationID
        }
    }
    func measurements(for observation: MappingObservation) -> [Measurement] {
        observation.measurementIDs.compactMap { measurementsByID[$0] }
    }
    func points(on plan: MappingPlanReference, excavationID: UUID?) -> [MappingObservation] {
        guard plansByID[plan.id] == plan, let horizon = horizons[plan.horizonID] else { return [] }
        // Compatibility still uses the authoritative rules, once per source revision
        // encountered in this query, rather than once per point or a persisted cache.
        var compatibility: [UUID: Bool] = [:]
        return (horizonOffsets[plan.horizonID] ?? []).map { effectiveObservations[$0] }.filter { point in
            guard point.projectID == horizon.projectID,
                  point.coordinates?.x != nil, point.coordinates?.y != nil,
                  excavationID == nil || point.excavationID == excavationID,
                  let sourceID = point.coordinates?.planID, let source = plansByID[sourceID] else { return false }
            if let result = compatibility[sourceID] { return result }
            let result = PlanCoordinateCompatibility.compatible(source, plan, plans: journal.plans)
            compatibility[sourceID] = result
            return result
        }
    }

    func journalObservations(projectID: UUID?) -> [JournalObservation] {
        guard let projectID else { return [] }
        return observations(projectID: projectID).map(JournalObservation.native) +
            (sourcesByProject[projectID] ?? []).map(JournalObservation.source)
    }

    func journalPoints(on plan: MappingPlanReference, excavationID: UUID?) -> [JournalObservation] {
        points(on: plan, excavationID: excavationID).map(JournalObservation.native) +
            sourcePoints(on: plan, excavationID: excavationID).map(JournalObservation.source)
    }

    func sourcePoints(on plan: MappingPlanReference, excavationID: UUID? = nil) -> [RegulatorySourceObservation] {
        guard plansByID[plan.id] == plan, !plan.isDeleted, !plan.isArchived else { return [] }
        return (sourcesByHorizon[plan.horizonID] ?? []).filter { record in
            (excavationID == nil || record.latest?.destination.excavationID == excavationID) && sourceDisplayIssue(record, on: plan) == nil
        }
    }

    func sourceDisplayIssue(_ record: RegulatorySourceObservation, on plan: MappingPlanReference? = nil) -> String? {
        guard let version = record.latest, version.xyz[0] != nil, version.xyz[1] != nil else { return "Недостаточно координат X/Y." }
        guard let horizon = version.destination.horizonID else { return "Назначьте горизонт для показа точки на плане." }
        let selected = plan.map { [$0] } ?? journal.plans.filter { $0.horizonID == horizon && !$0.isDeleted && !$0.isArchived }
        if selected.isEmpty { return "На горизонте нет действующего плана DXF." }
        let dataset = projects[record.key.projectID]?.regulatoryDatasets?[record.key.dataset]
        let frame = dataset.map { version.frame.canUse($0.frame) ? $0.frame : version.frame } ?? version.frame
        for candidate in selected where candidate.horizonID == horizon && !candidate.isDeleted && !candidate.isArchived {
            if dataset?.plans[candidate.id]?.supportsXY(candidate, frame: frame) == true { return nil }
            // Existing recorded DXF matches already carry a scoped confirmation for this point.
            if case .geometry(let id, let hash, let rule) = version.resolution, id == candidate.id,
               RegulatorySourceImport.PlanAssociation(horizonID: horizon, sha256: hash, frame: rule.frame,
                   confirmedAt: version.savedAt).supportsXY(candidate, frame: version.frame) { return nil }
        }
        return "Подтвердите совпадение СК набора Excel и ревизии DXF."
    }

}

/// A read projection of either kind of mapping evidence. Writes continue through
/// the corresponding revision editor and the stored UUID remains the identity.
enum JournalObservation: Identifiable, Sendable {
    case native(MappingObservation)
    case source(RegulatorySourceObservation)

    var id: UUID {
        switch self { case .native(let record): record.id; case .source(let record): record.id }
    }
    var context: MappingContext {
        switch self {
        case .native(let record): .init(projectID: record.projectID, horizonID: record.horizonID, excavationID: record.excavationID)
        case .source(let record): record.latest?.destination ?? .init(projectID: record.key.projectID)
        }
    }
    var coordinates: MappingCoordinates? {
        switch self {
        case .native(let record): return record.coordinates
        case .source(let record):
            guard let version = record.latest else { return nil }
            let xyz = version.xyz
            return .init(x: xyz[0], y: xyz[1], z: xyz[2], crs: version.frame.crs, axes: version.frame.axes,
                         units: version.frame.xyUnits, source: "regulatoryExcel", provenance: record.key.dataset,
                         zDatum: version.frame.verticalDatum)
        }
    }
    var displayPicket: String {
        switch self {
        case .native(let record): return record.displayPicket
        case .source(let record):
            if let picket = record.latest?.cells[1], !picket.isEmpty { return picket }
            return record.key.sourceID
        }
    }
    var observedAt: Date? {
        if case .native(let record) = self { return record.observedAt }
        return nil
    }
    var journalDate: Date {
        switch self {
        case .native(let record): record.observedAt
        case .source(let record): record.versions.first?.savedAt ?? .distantPast
        }
    }
    var dataset: String? {
        if case .source(let record) = self { return record.key.dataset }
        return nil
    }
    var horizonStatus: HorizonStatus {
        guard case .source(let record) = self else { return .confirmed }
        guard let version = record.latest, version.destination.horizonID != nil else {
            return record.latest?.matchingIssue?.isAmbiguous == true ? .ambiguous : .unresolved
        }
        return version.resolution == nil ? .confirmed : .automatic
    }

    enum HorizonStatus: String, CaseIterable, Identifiable {
        case confirmed, automatic, unresolved, ambiguous
        var id: Self { self }
        var title: String {
            switch self {
            case .confirmed: "Подтверждён вручную"
            case .automatic: "Определён автоматически"
            case .unresolved: "Не определён"
            case .ambiguous: "Несколько вариантов"
            }
        }
    }
}
