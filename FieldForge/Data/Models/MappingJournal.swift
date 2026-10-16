import Foundation

struct MappingProject: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
}

struct MappingHorizon: Codable, Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    var name: String
    var elevationMeters: Double?
    var elevationDatum: String
}

struct MappingExcavation: Codable, Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    var name: String
    var horizonIDs: Set<UUID>
}

/// Reserved plan metadata relationship; no plan importer or viewer in P1.
struct MappingPlanReference: Codable, Equatable, Identifiable {
    let id: UUID
    let horizonID: UUID
    let attachmentID: UUID
    let version: String
}

struct MappingContext: Codable, Equatable {
    var projectID: UUID?
    var horizonID: UUID?
    var excavationID: UUID?
}

struct MappingCoordinates: Codable, Equatable {
    let x: Double?
    let y: Double?
    let z: Double?
    let crs: String
    let axes: String
    let units: String
    let source: String
    let provenance: String
}

struct MappingObservation: Codable, Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    let horizonID: UUID
    let excavationID: UUID
    let picket: String
    let chainageMeters: Double
    let chainageOriginAndDirection: String
    let observedAt: Date
    let observedTimeZoneID: String
    let observedUTCOffsetSeconds: Int
    let createdAt: Date
    let updatedAt: Date
    let coordinates: MappingCoordinates?
    // Original measurement linking/capture is deferred to Issue #8.
    let measurementIDs: [UUID]
    let notes: String
}

struct MappingJournal: Codable, Equatable {
    var schemaVersion = 1
    var projects: [MappingProject] = []
    var horizons: [MappingHorizon] = []
    var excavations: [MappingExcavation] = []
    var plans: [MappingPlanReference] = []
    var observations: [MappingObservation] = []
    var selection = MappingContext()

    func validate() throws {
        guard schemaVersion == 1 else { throw StorageError.unsupportedVersion }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(projects.map(\.id)), unique(horizons.map(\.id)),
              unique(excavations.map(\.id)), unique(plans.map(\.id)), unique(observations.map(\.id)),
              projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              horizons.allSatisfy({ h in projects.contains { $0.id == h.projectID } && !h.name.isEmpty &&
                  (h.elevationMeters?.isFinite ?? true) && !h.elevationDatum.isEmpty }),
              excavations.allSatisfy({ e in projects.contains { $0.id == e.projectID } && !e.name.isEmpty &&
                  !e.horizonIDs.isEmpty && e.horizonIDs.allSatisfy { id in horizons.contains { $0.id == id && $0.projectID == e.projectID } } }),
              plans.allSatisfy({ p in horizons.contains { $0.id == p.horizonID } && !p.version.isEmpty }),
              validContext(selection) else { throw StorageError.invalidRecord }
        for o in observations {
            guard validContext(MappingContext(projectID: o.projectID, horizonID: o.horizonID, excavationID: o.excavationID)),
                  o.chainageMeters.isFinite, o.chainageMeters >= 0,
                  try PicketInput.meters(o.picket) == o.chainageMeters,
                  !o.chainageOriginAndDirection.isEmpty,
                  o.observedAt.timeIntervalSinceReferenceDate.isFinite,
                  o.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  o.updatedAt == o.createdAt,
                  TimeZone(identifier: o.observedTimeZoneID) != nil,
                  (-18 * 3600...18 * 3600).contains(o.observedUTCOffsetSeconds),
                  o.measurementIDs.isEmpty else { throw StorageError.invalidRecord }
            if let c = o.coordinates {
                guard [c.x, c.y, c.z].contains(where: { $0 != nil }),
                      [c.x, c.y, c.z].allSatisfy({ $0?.isFinite ?? true }),
                      !c.crs.isEmpty, !c.axes.isEmpty, c.units == "m", c.source == "manual", !c.provenance.isEmpty else {
                    throw StorageError.invalidRecord
                }
            }
        }
    }

    func validContext(_ c: MappingContext) -> Bool {
        guard let p = c.projectID else { return c.horizonID == nil && c.excavationID == nil }
        guard projects.contains(where: { $0.id == p }) else { return false }
        guard let h = c.horizonID else { return c.excavationID == nil }
        guard horizons.contains(where: { $0.id == h && $0.projectID == p }) else { return false }
        guard let e = c.excavationID else { return true }
        return excavations.contains { $0.id == e && $0.projectID == p && $0.horizonIDs.contains(h) }
    }
}

enum MappingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

enum PicketInput {
    /// P1 explicitly uses kilometer+meter notation, NOT 100 m survey pickets.
    static func meters(_ text: String) throws -> Double {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"^(?:ПК\s*)?([0-9]+)\+([0-9]{3}(?:[.,][0-9]+)?)$"#, options: [.regularExpression, .caseInsensitive]) {
            let cleaned = String(value[range]).replacingOccurrences(of: "ПК", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            let parts = cleaned.split(separator: "+")
            if let km = Double(parts[0]), let m = Double(parts[1].replacingOccurrences(of: ",", with: ".")), m < 1000 {
                let result = km * 1000 + m
                if result.isFinite { return result }
            }
        } else if value.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
                  let meters = Double(value.replacingOccurrences(of: ",", with: ".")), meters.isFinite { return meters }
        throw MappingError.invalid("Введите метры (5 или 5,5) либо ПК км+метры: ПК 0+005. Формат 1+05 неоднозначен.")
    }
}

struct MappingDraft: Equatable {
    var picket = ""
    var chainageOriginAndDirection = ""
    var observedAtOverride: Date?
    var timeZoneID = TimeZone.current.identifier
    var x = "", y = "", z = ""
    var crs = "", axes = "", coordinateProvenance = ""
    var notes = ""
    var hasChanges: Bool {
        ![picket, chainageOriginAndDirection, x, y, z, crs, axes, coordinateProvenance, notes].allSatisfy(\.isEmpty) || observedAtOverride != nil
    }
    func coordinates() throws -> MappingCoordinates? {
        func number(_ text: String) throws -> Double? {
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            guard text.range(of: #"^-?[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
                throw MappingError.invalid("Координаты должны быть конечными числами; неизвестные значения оставьте пустыми.")
            }
            return value
        }
        let values = try [number(x), number(y), number(z)]
        guard values.contains(where: { $0 != nil }) else {
            if !crs.isEmpty || !axes.isEmpty || !coordinateProvenance.isEmpty { throw MappingError.invalid("Введите хотя бы одну координату или очистите её метаданные.") }
            return nil
        }
        guard !crs.trimmingCharacters(in: .whitespaces).isEmpty,
              !axes.trimmingCharacters(in: .whitespaces).isEmpty,
              !coordinateProvenance.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MappingError.invalid("Укажите СК, оси и источник координат. Если неизвестно — напишите «неизвестно».")
        }
        return MappingCoordinates(x: values[0], y: values[1], z: values[2], crs: crs, axes: axes,
                                  units: "m", source: "manual", provenance: coordinateProvenance)
    }
}
