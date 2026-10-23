import Foundation

/// One immutable journal generation and its disposable read indexes. Construct on
/// the storage queue after load/commit; never encode indexes or update them in place.
/// Retaining this value freezes committed evidence independently of capture drafts.
final class MappingCommittedSnapshot: Sendable {
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
        plansByID = Dictionary(journal.plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

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
}
