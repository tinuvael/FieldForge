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
    var displayName: String { elevationMeters.map { ElevationInput.label($0) } ?? name }
}

struct MappingExcavation: Codable, Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    var name: String
    var horizonIDs: Set<UUID>
}

/// One immutable DXF revision belongs to exactly one horizon/project through its parent.
struct MappingPlanReference: Codable, Equatable, Identifiable {
    let id: UUID
    let horizonID: UUID
    let attachmentID: UUID
    let version: String
    var file: ManagedPlanFile? = nil
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
    var zOrigin: ElevationOrigin? = nil
    var zHorizonID: UUID? = nil
    var zHorizonElevation: Double? = nil
    var zDatum: String? = nil
    var planID: UUID? = nil
}

enum ElevationOrigin: String, Codable { case horizonDefault, manualOverride }

enum ElevationInput {
    static func meters(_ text: String) throws -> Double {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[+-]?[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite else {
            throw MappingError.invalid("Введите числовую отметку в метрах, например +393, -120 или 615,5.")
        }
        return number
    }
    static func text(_ number: Double) -> String {
        if number == 0 { return "0" }
        let value = String(number)
        guard let e = value.firstIndex(of: "e"), let exponent = Int(value[value.index(after: e)...]) else {
            return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
        }
        let negative = value.hasPrefix("-")
        let mantissa = String(value[..<e]).replacingOccurrences(of: "-", with: "")
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let digits = parts.joined()
        let position = parts[0].count + exponent
        var expanded: String
        if position <= 0 { expanded = "0." + String(repeating: "0", count: -position) + digits }
        else if position >= digits.count { expanded = digits + String(repeating: "0", count: position - digits.count) }
        else { let split = digits.index(digits.startIndex, offsetBy: position); expanded = String(digits[..<split]) + "." + digits[split...] }
        if expanded.contains(".") {
            while expanded.hasSuffix("0") { expanded.removeLast() }
            if expanded.hasSuffix(".") { expanded.removeLast() }
        }
        return (negative ? "-" : "") + expanded
    }
    static func label(_ number: Double) -> String { "\(number >= 0 ? "+" : "")\(text(number)) м" }
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
    let measurementIDs: [UUID]
    let notes: String
    let geology: MappingGeology?
    var ratings: MappingRatings? = nil
}

struct MappingJournal: Codable, Equatable {
    var schemaVersion = 7
    var projects: [MappingProject] = []
    var horizons: [MappingHorizon] = []
    var excavations: [MappingExcavation] = []
    var plans: [MappingPlanReference] = []
    var observations: [MappingObservation] = []
    var revisions: [MappingObservationRevision] = []
    var photos: [PhotoObservation] = []
    var photoAttachments: [PhotoAttachment] = []
    var photoRevisions: [PhotoMetadataRevision] = []
    var selection = MappingContext()
    var measurements: [Measurement] = []

    init() {}
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, horizons, excavations, plans, observations, selection, measurements, revisions, photos, photoAttachments, photoRevisions
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        projects = try c.decode([MappingProject].self, forKey: .projects)
        horizons = try c.decode([MappingHorizon].self, forKey: .horizons)
        excavations = try c.decode([MappingExcavation].self, forKey: .excavations)
        plans = try c.decode([MappingPlanReference].self, forKey: .plans)
        observations = try c.decode([MappingObservation].self, forKey: .observations)
        // Do not discard history under a damaged/old header: validation rejects nonempty
        // revisions below schema 6. Only genuinely absent legacy tables default to empty.
        revisions = schemaVersion < 6
            ? (try c.decodeIfPresent([MappingObservationRevision].self, forKey: .revisions) ?? [])
            : try c.decode([MappingObservationRevision].self, forKey: .revisions)
        photos = schemaVersion < 7 ? (try c.decodeIfPresent([PhotoObservation].self, forKey: .photos) ?? []) : try c.decode([PhotoObservation].self, forKey: .photos)
        photoAttachments = schemaVersion < 7 ? (try c.decodeIfPresent([PhotoAttachment].self, forKey: .photoAttachments) ?? []) : try c.decode([PhotoAttachment].self, forKey: .photoAttachments)
        photoRevisions = schemaVersion < 7 ? (try c.decodeIfPresent([PhotoMetadataRevision].self, forKey: .photoRevisions) ?? []) : try c.decode([PhotoMetadataRevision].self, forKey: .photoRevisions)
        selection = try c.decode(MappingContext.self, forKey: .selection)
        // Only old schemas may omit the new evidence table. A damaged v3 file fails closed.
        measurements = schemaVersion < 3 ? (try c.decodeIfPresent([Measurement].self, forKey: .measurements) ?? []) : try c.decode([Measurement].self, forKey: .measurements)
    }

    func measurements(for observation: MappingObservation) -> [Measurement] {
        let byID = Dictionary(measurements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return observation.measurementIDs.compactMap { byID[$0] }
    }

    func validate() throws { try validateGraph(includingRevisions: true) }

    func validateGraph(includingRevisions: Bool) throws {
        guard [1, 2, 3, 4, 5, 6, 7].contains(schemaVersion) else { throw StorageError.unsupportedVersion }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(projects.map(\.id)), unique(horizons.map(\.id)),
              unique(excavations.map(\.id)), unique(plans.map(\.id)), unique(observations.map(\.id)),
              projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              horizons.allSatisfy({ h in projects.contains { $0.id == h.projectID } && !h.name.isEmpty &&
                  (h.elevationMeters?.isFinite ?? true) && !h.elevationDatum.isEmpty }),
              excavations.allSatisfy({ e in projects.contains { $0.id == e.projectID } && !e.name.isEmpty &&
                  !e.horizonIDs.isEmpty && e.horizonIDs.allSatisfy { id in horizons.contains { $0.id == id && $0.projectID == e.projectID } } }),
              unique(plans.filter { $0.file != nil }.map(\.attachmentID)),
              plans.allSatisfy({ p in horizons.contains { $0.id == p.horizonID } && !p.version.isEmpty &&
                  (p.file.map { f in !f.originalFilename.isEmpty && !f.crs.isEmpty && !f.axes.isEmpty &&
                      f.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil &&
                      (1...10_000_000).contains(f.byteCount) && f.importedAt.timeIntervalSinceReferenceDate.isFinite &&
                      f.unitDeclaration == "userConfirmedAtImport" } ?? true) }),
              validContext(selection) else { throw StorageError.invalidRecord }
        let geologyIDs = observations.flatMap { observation in
            (observation.geology?.jointSets.map(\.id) ?? []) + (observation.geology?.tectonicStructures.map(\.id) ?? [])
        }
        guard unique(geologyIDs) else { throw StorageError.invalidRecord }
        let linkedIDs = observations.flatMap(\.measurementIDs)
        guard unique(measurements.map(\.id)), unique(linkedIDs),
              Set(linkedIDs) == Set(measurements.map(\.id)),
              measurements.allSatisfy(\.isSavable),
              schemaVersion >= 3 || (measurements.isEmpty && linkedIDs.isEmpty) else { throw StorageError.invalidRecord }
        for o in observations {
            guard schemaVersion >= 4 || o.geology == nil else { throw StorageError.invalidRecord }
            guard schemaVersion >= 5 || o.ratings == nil else { throw StorageError.invalidRecord }
            try o.ratings?.validate()
            try o.geology?.validate(pointMeasurementIDs: o.measurementIDs)
            if includingRevisions, o.geology?.jointSets.contains(where: { $0.revision != 1 }) == true { throw StorageError.invalidRecord }
            guard validContext(MappingContext(projectID: o.projectID, horizonID: o.horizonID, excavationID: o.excavationID)),
                  o.chainageMeters.isFinite, o.chainageMeters >= 0,
                  try PicketInput.meters(o.picket) == o.chainageMeters,
                  !o.chainageOriginAndDirection.isEmpty,
                  o.observedAt.timeIntervalSinceReferenceDate.isFinite,
                  o.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  o.updatedAt == o.createdAt,
                  TimeZone(identifier: o.observedTimeZoneID) != nil,
                  (-18 * 3600...18 * 3600).contains(o.observedUTCOffsetSeconds),
                  unique(o.measurementIDs) else { throw StorageError.invalidRecord }
            if let c = o.coordinates {
                guard ([c.x, c.y, c.z].contains(where: { $0 != nil }) || c.zOrigin == .manualOverride),
                      [c.x, c.y, c.z].allSatisfy({ $0?.isFinite ?? true }),
                      !c.crs.isEmpty, !c.axes.isEmpty, ["m", "mm", "drawing"].contains(c.units), ["manual", "plan", "manualInPlan"].contains(c.source), !c.provenance.isEmpty else {
                    throw StorageError.invalidRecord
                }
                if let planID = c.planID {
                    guard ["plan", "manualInPlan"].contains(c.source), let plan = plans.first(where: { $0.id == planID }),
                          plan.horizonID == o.horizonID, let file = plan.file, (c.source != "plan" || (c.x != nil && c.y != nil)),
                          c.units == file.units.coordinateUnits, c.crs == file.crs, c.axes == file.axes else { throw StorageError.invalidRecord }
                } else if c.source != "manual" || c.units != "m" { throw StorageError.invalidRecord }
                if c.zOrigin == .horizonDefault {
                    guard c.zHorizonID == o.horizonID, let elevation = c.zHorizonElevation,
                          elevation.isFinite, c.z == elevation, c.zDatum?.isEmpty == false else { throw StorageError.invalidRecord }
                } else if c.zHorizonID != nil || c.zHorizonElevation != nil || c.zDatum != nil { throw StorageError.invalidRecord }
            }
        }
        if includingRevisions { try validateRevisions(); try validatePhotos() }
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
    private(set) var measurements: [Measurement] = []
    mutating func addMeasurement(_ reading: Measurement) throws {
        guard reading.isSavable, !measurements.contains(where: { $0.id == reading.id }) else { throw StorageError.invalidRecord }
        measurements.append(reading)
    }
    mutating func removeMeasurement(id: UUID) {
        measurements.removeAll { $0.id == id }
        for index in jointSets.indices { jointSets[index].measurementIDs.removeAll { $0 == id } }
    }
    var bartonQ = BartonQInput()
    var rmr89 = RMR89Input()
    var jointSets: [JointSetDraft] = []
    var tectonicStructures: [TectonicStructureDraft] = []
    var startPicket = "", endPicket = ""
    var observationPosition: ObservationPosition?
    var picket = ""
    var chainageOriginAndDirection = ""
    var observedAtOverride: Date?
    var timeZoneID = TimeZone.current.identifier
    var x = "" { didSet { markManualXYEdit() } }
    var y = "" { didSet { markManualXYEdit() } }
    private(set) var planID: UUID?
    private(set) var xyUnits = "m"
    private(set) var xySource = "manual"
    private mutating func markManualXYEdit() {
        if planID != nil {
            xySource = "manualInPlan"
            if !coordinateProvenance.contains("XY manually overridden") { coordinateProvenance += "; XY manually overridden in selected drawing frame" }
        }
    }
    mutating func selectPlanPoint(_ point: PlanPoint, plan: MappingPlanReference) throws {
        guard let file = plan.file, point.x.isFinite, point.y.isFinite else { throw StorageError.invalidRecord }
        x = String(point.x); y = String(point.y)
        planID = plan.id; xyUnits = file.units.coordinateUnits; xySource = "plan"
        crs = file.crs; axes = file.axes
        coordinateProvenance = "plan \(plan.id.uuidString); revision \(plan.version); SHA-256 \(file.sha256); drawing WCS XY; user selected; accuracy unknown; \(file.unitDeclaration)"
    }
    var z = "" { didSet { zOrigin = .manualOverride; zHorizonID = nil; zHorizonElevation = nil; zDatum = nil } }
    private(set) var zOrigin: ElevationOrigin?
    private(set) var zHorizonID: UUID?
    private(set) var zHorizonElevation: Double?
    private(set) var zDatum: String?
    var crs = "", axes = "", coordinateProvenance = ""
    var notes = ""
    mutating func suggestElevation(_ horizon: MappingHorizon?) {
        guard zOrigin != .manualOverride else { return }
        z = horizon?.elevationMeters.map { ElevationInput.text($0) } ?? ""
        zOrigin = horizon?.elevationMeters == nil ? nil : .horizonDefault
        zHorizonID = zOrigin == nil ? nil : horizon?.id
        zHorizonElevation = horizon?.elevationMeters
        zDatum = zOrigin == nil ? nil : horizon?.elevationDatum
    }
    var hasChanges: Bool {
        ![picket, chainageOriginAndDirection, x, y, crs, axes, coordinateProvenance, notes].allSatisfy(\.isEmpty) ||
            observedAtOverride != nil || zOrigin == .manualOverride || !measurements.isEmpty ||
            bartonQ.hasChanges || rmr89.hasChanges || !jointSets.isEmpty || !tectonicStructures.isEmpty || !startPicket.isEmpty || !endPicket.isEmpty || observationPosition != nil
    }
    func coordinates() throws -> MappingCoordinates? {
        func number(_ text: String) throws -> Double? {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            return try ElevationInput.meters(text)
        }
        let values = try [number(x), number(y), number(z)]
        guard values.contains(where: { $0 != nil }) || zOrigin == .manualOverride else { return nil }
        return MappingCoordinates(x: values[0], y: values[1], z: values[2],
            crs: crs.isEmpty ? "unknown" : crs, axes: axes.isEmpty ? "unknown" : axes,
            units: xyUnits, source: xySource, provenance: coordinateProvenance.isEmpty ? "manual; accuracy unknown" : coordinateProvenance,
            zOrigin: zOrigin, zHorizonID: zHorizonID, zHorizonElevation: zHorizonElevation, zDatum: zDatum, planID: planID)
    }
}


extension MappingDraft {
    /// Rehydrates field values, then restores frozen provenance after edit observers.
    init(observation: MappingObservation, measurements: [Measurement]) {
        self.init()
        self.measurements = measurements
        picket = observation.picket; chainageOriginAndDirection = observation.chainageOriginAndDirection
        observedAtOverride = observation.observedAt; timeZoneID = observation.observedTimeZoneID
        notes = observation.notes
        if let c = observation.coordinates {
            x = c.x.map(ElevationInput.text) ?? ""; y = c.y.map(ElevationInput.text) ?? ""
            z = c.z.map(ElevationInput.text) ?? ""
            planID = c.planID; xyUnits = c.units; xySource = c.source
            crs = c.crs; axes = c.axes; coordinateProvenance = c.provenance
            zOrigin = c.zOrigin; zHorizonID = c.zHorizonID; zHorizonElevation = c.zHorizonElevation; zDatum = c.zDatum
        }
        if let g = observation.geology {
            startPicket = g.start?.text ?? ""; endPicket = g.end?.text ?? ""; observationPosition = g.position
            jointSets = g.jointSets.map(JointSetDraft.init)
            tectonicStructures = g.tectonicStructures.map(TectonicStructureDraft.init)
        }
        bartonQ = observation.ratings?.bartonQ?.input ?? BartonQInput()
        rmr89 = observation.ratings?.rmr89?.input ?? RMR89Input()
    }
}
