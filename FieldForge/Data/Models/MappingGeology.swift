import Foundation

/// User-entered geological descriptions, not classification scores or calculated joint sets.
enum JointSetIdentifier: String, Codable, CaseIterable { case J1, J2, J3, J4, J5 }
enum ObservationPosition: String, Codable, CaseIterable { case roof, leftWall, rightWall, face, other }
enum TectonicStructureType: String, Codable, CaseIterable { case fault, shearZone, fractureZone, other }

enum GeologyInput {
    static func optionalNonnegative(_ text: String, field: String) throws -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let value = try? ElevationInput.meters(text), value >= 0 else {
            throw MappingError.invalid("\(field): введите конечное число ≥ 0 или оставьте поле пустым.")
        }
        return value
    }
    static func optionalPicket(_ text: String, field: String) throws -> MappingPicket? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { return MappingPicket(text: text, meters: try PicketInput.meters(text)) }
        catch { throw MappingError.invalid("\(field): \(error.localizedDescription)") }
    }
}

struct MappingPicket: Codable, Equatable {
    let text: String
    let meters: Double
    func validate() throws {
        guard meters.isFinite, meters >= 0, try PicketInput.meters(text) == meters else { throw StorageError.invalidRecord }
    }
}

/// Immutable revision 1. Evidence UUIDs identify exact immutable originals in this point.
/// ManualOrientationInput preserves interpreted text, north and vertical-side convention.
struct InterpretedJointSet: Codable, Equatable, Identifiable {
    let id: UUID
    let identifier: JointSetIdentifier
    let revision: Int
    let interpretedAt: Date
    let author: String?
    let method: String
    let representative: ManualOrientationInput
    let measurementIDs: [UUID]
    let spacingMeters: Double?
    let persistenceMeters: Double?
    let apertureMillimeters: Double?
    let roughness: String
    let infill: String
    let notes: String

    func validate(pointMeasurementIDs: [UUID]) throws {
        _ = try representative.validated()
        guard revision == 1, method == "user-interpretation-v1", interpretedAt.timeIntervalSinceReferenceDate.isFinite,
              author.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              Set(measurementIDs).count == measurementIDs.count,
              Set(measurementIDs).isSubset(of: Set(pointMeasurementIDs)),
              [spacingMeters, persistenceMeters, apertureMillimeters].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? true }) else {
            throw StorageError.invalidRecord
        }
    }
}

struct TectonicStructure: Codable, Equatable, Identifiable {
    let id: UUID
    let type: TectonicStructureType
    let orientation: ManualOrientationInput
    let thicknessMeters: Double?
    let picket: MappingPicket?
    let position: String
    let description: String
    func validate() throws {
        _ = try orientation.validated()
        try picket?.validate()
        guard thicknessMeters.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw StorageError.invalidRecord }
    }
}

struct MappingGeology: Codable, Equatable {
    let start: MappingPicket?
    let end: MappingPicket?
    let position: ObservationPosition?
    let jointSets: [InterpretedJointSet]
    let tectonicStructures: [TectonicStructure]
    func validate(pointMeasurementIDs: [UUID]) throws {
        try start?.validate(); try end?.validate()
        if let start, let end, end.meters < start.meters { throw MappingError.invalid("Конец интервала должен быть не раньше начала.") }
        guard jointSets.count <= 5, Set(jointSets.map(\.identifier)).count == jointSets.count,
              Set(jointSets.map(\.id)).count == jointSets.count,
              Set(tectonicStructures.map(\.id)).count == tectonicStructures.count else { throw StorageError.invalidRecord }
        for set in jointSets { try set.validate(pointMeasurementIDs: pointMeasurementIDs) }
        for structure in tectonicStructures { try structure.validate() }
    }
}

struct JointSetDraft: Equatable, Identifiable {
    let id: UUID
    let identifier: JointSetIdentifier
    var representative = ManualOrientationInput()
    var measurementIDs: [UUID] = []
    var spacing = "", persistence = "", aperture = ""
    var roughness = "", infill = "", notes = "", author = ""
    init(identifier: JointSetIdentifier, id: UUID = UUID()) { self.identifier = identifier; self.id = id }
    func record(now: Date) throws -> InterpretedJointSet {
        do {
            _ = try representative.validated()
            return InterpretedJointSet(id: id, identifier: identifier, revision: 1, interpretedAt: now,
                author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author,
                method: "user-interpretation-v1", representative: representative, measurementIDs: measurementIDs,
                spacingMeters: try GeologyInput.optionalNonnegative(spacing, field: "Расстояние, м"),
                persistenceMeters: try GeologyInput.optionalNonnegative(persistence, field: "Протяжённость, м"),
                apertureMillimeters: try GeologyInput.optionalNonnegative(aperture, field: "Раскрытие, мм"),
                roughness: roughness, infill: infill, notes: notes)
        } catch { throw MappingError.invalid("\(identifier.rawValue): \(error.localizedDescription)") }
    }
}

struct TectonicStructureDraft: Equatable, Identifiable {
    let id: UUID
    var type = TectonicStructureType.fault
    var orientation = ManualOrientationInput()
    var thickness = "", picket = "", position = "", description = ""
    init(id: UUID = UUID()) { self.id = id }
    func record() throws -> TectonicStructure {
        _ = try orientation.validated()
        return TectonicStructure(id: id, type: type, orientation: orientation,
            thicknessMeters: try GeologyInput.optionalNonnegative(thickness, field: "Мощность, м"),
            picket: try GeologyInput.optionalPicket(picket, field: "Пикет структуры"), position: position, description: description)
    }
}

extension MappingDraft {
    mutating func addJointSet() {
        guard let identifier = JointSetIdentifier.allCases.first(where: { candidate in !jointSets.contains { $0.identifier == candidate } }) else { return }
        jointSets.append(JointSetDraft(identifier: identifier))
        jointSets.sort { $0.identifier.rawValue < $1.identifier.rawValue }
    }
    func geology(now: Date) throws -> MappingGeology? {
        let start = try GeologyInput.optionalPicket(startPicket, field: "Начало интервала")
        let end = try GeologyInput.optionalPicket(endPicket, field: "Конец интервала")
        guard start != nil || end != nil || observationPosition != nil || !jointSets.isEmpty || !tectonicStructures.isEmpty else { return nil }
        let structures = try tectonicStructures.enumerated().map { index, draft in
            do { return try draft.record() }
            catch { throw MappingError.invalid("Тектоника №\(index + 1): \(error.localizedDescription)") }
        }
        let value = MappingGeology(start: start, end: end, position: observationPosition,
            jointSets: try jointSets.map { try $0.record(now: now) }, tectonicStructures: structures)
        try value.validate(pointMeasurementIDs: measurements.map(\.id))
        return value
    }
}
