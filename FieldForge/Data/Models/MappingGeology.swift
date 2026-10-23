import Foundation

/// User-entered geological descriptions, not classification scores or calculated joint sets.
enum JointSetIdentifier: String, Codable, CaseIterable, Sendable { case J1, J2, J3, J4, J5 }
enum ObservationPosition: String, Codable, CaseIterable, Sendable { case roof, leftWall, rightWall, face, other }
enum TectonicStructureType: String, Codable, CaseIterable, Sendable { case fault, shearZone, fractureZone, other }

enum GeologyInput {
    static func optionalNonnegative(_ text: String, field: String) throws -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let value = try? ElevationInput.meters(text), value >= 0 else {
            throw MappingError.invalid("\(field): введите конечное число ≥ 0 или оставьте поле пустым.")
        }
        return value
    }
    static func optionalPicket(_ text: String, field: String, convention: PicketConvention = .tenMeters) throws -> MappingPicket? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { return MappingPicket(text: text, meters: try convention.meters(text), convention: convention) }
        catch { throw MappingError.invalid("\(field): \(error.localizedDescription)") }
    }
}

struct MappingPicket: Codable, Equatable, Sendable {
    let text: String
    let meters: Double
    var convention: PicketConvention? = nil
    func validate() throws {
        guard meters.isFinite, meters >= 0, (convention ?? .legacyMeters).matches(text, meters: meters) else { throw StorageError.invalidRecord }
    }
}

/// Immutable interpretation snapshot. Evidence UUIDs identify exact immutable originals in this point.
/// ManualOrientationInput preserves interpreted text, north and vertical-side convention.
struct InterpretedJointSet: Codable, Equatable, Identifiable, Sendable {
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

    var spacingProvenance: JointSpacingProvenance? = nil

    func validate(pointMeasurementIDs: [UUID]) throws {
        try spacingProvenance?.validate(spacing: spacingMeters)
        _ = try representative.validated()
        guard revision >= 1, method == "user-interpretation-v1", interpretedAt.timeIntervalSinceReferenceDate.isFinite,
              author.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              Set(measurementIDs).count == measurementIDs.count,
              Set(measurementIDs).isSubset(of: Set(pointMeasurementIDs)),
              [spacingMeters, persistenceMeters, apertureMillimeters].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? true }) else {
            throw StorageError.invalidRecord
        }
    }
}

struct TectonicStructure: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let type: TectonicStructureType
    let orientation: ManualOrientationInput
    let thicknessMeters: Double?
    let picket: MappingPicket?
    let position: String
    let description: String
    func validate() throws {
        _ = try orientation.validatedTectonic()
        try picket?.validate()
        guard thicknessMeters.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw StorageError.invalidRecord }
    }
}

struct MappingGeology: Codable, Equatable, Sendable {
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

struct JointSetDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    let identifier: JointSetIdentifier
    var representative = ManualOrientationInput()
    var measurementIDs: [UUID] = []
    var spacing = "" { didSet { spacingProvenance = .manual } }
    var spacingProvenance: JointSpacingProvenance? = JointSpacingProvenance(source: .estimatedFromRQD,
        method: PriestHudsonSpacing.version, originalRQD: nil, rqdSource: nil, rqdEvidence: nil)
    var persistence = "", aperture = ""
    mutating func resetSpacingEstimate(_ rqd: SpacingRQD) {
        spacing = PriestHudsonSpacing.estimate(rqd: rqd.value).map(ElevationInput.text) ?? ""
        spacingProvenance = .estimate(rqd)
    }
    mutating func updateSpacingEstimate(_ rqd: SpacingRQD) {
        if spacingProvenance?.source == .estimatedFromRQD { resetSpacingEstimate(rqd) }
    }
    var roughness = "", infill = "", notes = "", author = ""
    init(identifier: JointSetIdentifier, id: UUID = UUID()) { self.identifier = identifier; self.id = id }
    /// New manual entry must be positive; untouched legacy spacing keeps its original meaning.
    func validatedSpacing() throws -> Double? {
        let value = try RatingNumber.optional(spacing, name: "SD, м")
        if let value, value < 0 || (value == 0 && spacingProvenance?.source == .manual) {
            throw MappingError.invalid("SD, м: введите значение больше нуля или оставьте поле пустым.")
        }
        return value
    }
    func record(now: Date) throws -> InterpretedJointSet {
        do {
            _ = try representative.validated()
            return InterpretedJointSet(id: id, identifier: identifier, revision: 1, interpretedAt: now,
                author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author,
                method: "user-interpretation-v1", representative: representative, measurementIDs: measurementIDs,
                spacingMeters: try validatedSpacing(),
                persistenceMeters: try GeologyInput.optionalNonnegative(persistence, field: "Протяжённость, м"),
                apertureMillimeters: try GeologyInput.optionalNonnegative(aperture, field: "Раскрытие, мм"),
                roughness: roughness, infill: infill, notes: notes, spacingProvenance: spacingProvenance)
        } catch { throw MappingError.invalid("\(identifier.rawValue): \(error.localizedDescription)") }
    }
}

struct TectonicStructureDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var type = TectonicStructureType.fault
    var orientation = ManualOrientationInput()
    var thickness = "", picket = "", position = "", description = ""
    var picketConvention = PicketConvention.tenMeters
    init(id: UUID = UUID()) { self.id = id }
    func record() throws -> TectonicStructure {
        _ = try orientation.validatedTectonic()
        return TectonicStructure(id: id, type: type, orientation: orientation,
            thicknessMeters: try GeologyInput.optionalNonnegative(thickness, field: "Мощность, м"),
            picket: try GeologyInput.optionalPicket(picket, field: "Пикет структуры", convention: picketConvention), position: position, description: description)
    }
}

extension MappingDraft {
    mutating func addJointSet() {
        guard let identifier = JointSetIdentifier.allCases.first(where: { candidate in !jointSets.contains { $0.identifier == candidate } }) else { return }
        jointSets.append(newJointSet(identifier: identifier))
        jointSets.sort { $0.identifier.rawValue < $1.identifier.rawValue }
    }
    var spacingRQD: SpacingRQD { SpacingRQD(q: bartonQ, rmr: rmr89) }
    func newJointSet(identifier: JointSetIdentifier) -> JointSetDraft {
        var set = JointSetDraft(identifier: identifier); set.resetSpacingEstimate(spacingRQD); return set
    }
    mutating func updateSpacingEstimates() {
        let rqd = spacingRQD
        for index in jointSets.indices { jointSets[index].updateSpacingEstimate(rqd) }
    }
    func geology(now: Date) throws -> MappingGeology? {
        let start = try GeologyInput.optionalPicket(startPicket, field: "Начало интервала", convention: startPicketConvention)
        let end = try GeologyInput.optionalPicket(endPicket, field: "Конец интервала", convention: endPicketConvention)
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


extension JointSetDraft {
    init(_ record: InterpretedJointSet) {
        self.init(identifier: record.identifier, id: record.id)
        representative = record.representative; measurementIDs = record.measurementIDs
        spacing = record.spacingMeters.map(ElevationInput.text) ?? ""
        spacingProvenance = record.spacingProvenance
        persistence = record.persistenceMeters.map(ElevationInput.text) ?? ""
        aperture = record.apertureMillimeters.map(ElevationInput.text) ?? ""
        roughness = record.roughness; infill = record.infill; notes = record.notes; author = record.author ?? ""
    }
    func corrected(previous: InterpretedJointSet?, now: Date) throws -> InterpretedJointSet {
        if let previous, self == JointSetDraft(previous) { return previous }
        let value = try record(now: now)
        return InterpretedJointSet(id: value.id, identifier: value.identifier, revision: (previous?.revision ?? 0) + 1,
            interpretedAt: now, author: value.author, method: value.method, representative: value.representative,
            measurementIDs: value.measurementIDs, spacingMeters: value.spacingMeters, persistenceMeters: value.persistenceMeters,
            apertureMillimeters: value.apertureMillimeters, roughness: value.roughness, infill: value.infill, notes: value.notes, spacingProvenance: value.spacingProvenance)
    }
}
extension TectonicStructureDraft {
    init(_ record: TectonicStructure) {
        self.init(id: record.id)
        type = record.type; orientation = record.orientation
        thickness = record.thicknessMeters.map(ElevationInput.text) ?? ""
        picketConvention = record.picket?.convention ?? .legacyMeters
        picket = record.picket?.text ?? ""; position = record.position; description = record.description
    }
}

/// Adapts an explicit interpretation to the existing validator, without changing the original.
enum JointRepresentativeInput {
    static func make(from reading: Measurement) throws -> ManualOrientationInput {
        guard reading.isSavable, reading.orientation.dipAngle != nil else {
            throw MappingError.invalid("Замер неполный или недостоверный. Повторите фиксацию.")
        }
        guard GeographicReference.manualChoices.contains(reading.reference) else {
            throw MappingError.invalid(reading.reference == .simulatedNorth
                ? "Север DEMO нельзя назначить системе. Можно оставить исходный замер."
                : "Опора на север недоступна. Можно оставить исходный замер.")
        }
        var input = ManualOrientationInput()
        input.dipAngleText = reading.orientation.dipAngle.map(ElevationInput.text) ?? ""
        input.dipDirectionText = reading.orientation.dipDirection.map(ElevationInput.text) ?? ""
        input.reference = reading.reference
        input.usesConventionalDipSide = reading.directionMeaning == .conventionalDipSide
        do { _ = try input.validated() }
        catch {
            throw MappingError.invalid("Ориентация неполная или направление неоднозначно. Оставьте исходный замер; систему задайте явно.")
        }
        return input
    }
    static func issue(for reading: Measurement) -> String? {
        do { _ = try make(from: reading); return nil } catch { return error.localizedDescription }
    }
}
