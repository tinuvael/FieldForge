import Foundation

/// Read-only snapshots retain original representative text/conventions and all interpretation provenance.
struct WedgeJoint: Equatable, Identifiable {
    enum Origin: Equatable { case draft(JointSetDraft), saved(InterpretedJointSet) }
    let origin: Origin
    var id: UUID {
        switch origin { case .draft(let value): return value.id; case .saved(let value): return value.id }
    }
    var identifier: JointSetIdentifier {
        switch origin { case .draft(let value): return value.identifier; case .saved(let value): return value.identifier }
    }
    var input: ManualOrientationInput {
        switch origin { case .draft(let value): return value.representative; case .saved(let value): return value.representative }
    }
    var orientationValid: Bool { WedgePlaneGeometry.normal(input: input, axis: 0) != nil }
}

struct WedgeMappingSource: Equatable, Identifiable {
    let context: MappingContext
    let pointID: UUID // Draft UUID is explicitly unsaved, never a persisted revision.
    let revisionID: UUID?
    let version: Int?
    let title: String
    let joints: [WedgeJoint]
    var id: UUID { pointID }
    var validJoints: [WedgeJoint] { joints.filter(\.orientationValid) }
    var initialSelection: Set<UUID> { validJoints.count == 3 ? Set(validJoints.map(\.id)) : [] }

    static func available(in workflow: MappingWorkflow) -> [Self] {
        let c = workflow.context
        guard c.projectID != nil, c.horizonID != nil, c.excavationID != nil else { return [] }
        let draft = Self(context: c, pointID: workflow.draft.id, revisionID: nil, version: nil,
                         title: "Текущий черновик · не сохранён",
                         joints: workflow.draft.jointSets.map { WedgeJoint(origin: .draft($0)) })
        return [draft] + workflow.committed.observations(context: c).map { observation in
            let revision = workflow.committed.latestRevisions[observation.id]
            return Self(context: c, pointID: observation.id, revisionID: revision?.id, version: revision?.version ?? 1,
                        title: "\(observation.displayPicket) · версия \(revision?.version ?? 1) · \(observation.id.uuidString.prefix(8))",
                        joints: (observation.geology?.jointSets ?? []).map { WedgeJoint(origin: .saved($0)) })
        }
    }
    func selectedJoints(_ selection: Set<UUID>, axisNorth: GeographicReference) throws -> [WedgeJoint] {
        guard validJoints.count >= 3 else {
            throw MappingError.invalid("Для построения необходимы три системы трещин. Найдено: \(validJoints.count) из 3.")
        }
        let selected = joints.filter { selection.contains($0.id) }
        guard selection.count == 3, selected.count == 3, selected.allSatisfy(\.orientationValid) else {
            throw MappingError.invalid("Выберите ровно три полные системы трещин.")
        }
        guard [.magneticNorth, .trueNorth, .gridNorth].contains(axisNorth),
              selected.allSatisfy({ $0.input.reference == axisNorth }) else {
            throw MappingError.invalid("Север оси и трёх систем должен совпадать и быть известен. Преобразование магнитного, истинного и сеточного севера не выполняется.")
        }
        return selected
    }
}

struct WedgeAxisCapture {
    let azimuth: Double
    let sample: SensorSample // Original timestamp, rotation, field and quality, transient only.
    let method = "phone-top-edge-horizontal-projection-v1"
}

struct WedgeDimensionInput {
    var text = ""
    private(set) var measurement: DistanceResult?
    private(set) var manuallyEdited = false
    mutating func edit(_ value: String) { text = value; manuallyEdited = true }
    mutating func accept(_ result: DistanceResult?) {
        guard let result, result.metres.isFinite, result.metres > 0 else { return }
        measurement = result; text = String(result.metres); manuallyEdited = false
    }
}
