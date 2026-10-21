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
    var frameConfirmation: PlanFrameConfirmation? = nil
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
    var picketConvention: PicketConvention? = nil
}

struct MappingJournal: Codable, Equatable {
    static let currentSchemaVersion = 8
    var schemaVersion = currentSchemaVersion
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
        guard schemaVersion == Self.currentSchemaVersion else { throw MappingDatabaseError.incompatibleVersion(schemaVersion) }
        projects = try c.decode([MappingProject].self, forKey: .projects)
        horizons = try c.decode([MappingHorizon].self, forKey: .horizons)
        excavations = try c.decode([MappingExcavation].self, forKey: .excavations)
        plans = try c.decode([MappingPlanReference].self, forKey: .plans)
        observations = try c.decode([MappingObservation].self, forKey: .observations)
        revisions = try c.decode([MappingObservationRevision].self, forKey: .revisions)
        photos = try c.decode([PhotoObservation].self, forKey: .photos)
        photoAttachments = try c.decode([PhotoAttachment].self, forKey: .photoAttachments)
        photoRevisions = try c.decode([PhotoMetadataRevision].self, forKey: .photoRevisions)
        selection = try c.decode(MappingContext.self, forKey: .selection)
        measurements = try c.decode([Measurement].self, forKey: .measurements)
    }

    func measurements(for observation: MappingObservation) -> [Measurement] {
        let byID = Dictionary(measurements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return observation.measurementIDs.compactMap { byID[$0] }
    }

    func validate() throws { try validateGraph(includingRevisions: true) }

    func validateGraph(includingRevisions: Bool) throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw MappingDatabaseError.incompatibleVersion(schemaVersion) }
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
        try PlanCoordinateCompatibility.validate(plans)
        let geologyIDs = observations.flatMap { observation in
            (observation.geology?.jointSets.map(\.id) ?? []) + (observation.geology?.tectonicStructures.map(\.id) ?? [])
        }
        guard unique(geologyIDs) else { throw StorageError.invalidRecord }
        let linkedIDs = observations.flatMap(\.measurementIDs)
        guard unique(measurements.map(\.id)), unique(linkedIDs),
              Set(linkedIDs) == Set(measurements.map(\.id)),
              measurements.allSatisfy(\.isSavable) else { throw StorageError.invalidRecord }
        for o in observations {
            try o.ratings?.validate()
            try o.geology?.validate(pointMeasurementIDs: o.measurementIDs)
            if includingRevisions, o.geology?.jointSets.contains(where: { $0.revision != 1 }) == true { throw StorageError.invalidRecord }
            guard validContext(MappingContext(projectID: o.projectID, horizonID: o.horizonID, excavationID: o.excavationID)),
                  o.chainageMeters.isFinite, o.chainageMeters >= 0,
                  (o.picketConvention ?? .legacyMeters).matches(o.picket, meters: o.chainageMeters),
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

/// Missing tags in schema-8 records retain the original kilometre/metre interpretation.
enum PicketConvention: String, Codable {
    case legacyMeters, tenMeters
    func meters(_ text: String) throws -> Double {
        switch self {
        case .legacyMeters: return try PicketInput.meters(text)
        case .tenMeters: return try FieldPicketInput.meters(text)
        }
    }
}

enum FieldPicketInput {
    /// Decimal arithmetic avoids binary multiplication/subtraction artifacts in canonical labels.
    private static func decimalMeters(_ text: String) throws -> Decimal {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^ПК\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: "+")
        let plus = value.range(of: #"^[0-9]+\+[0-9](?:\.[0-9]+)?$"#, options: .regularExpression) != nil
        let plain = value.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
        guard (plus || plain), value.filter(\.isNumber).count <= 28,
              let first = Decimal(string: String(parts[0]), locale: Locale(identifier: "en_US_POSIX")) else {
            throw MappingError.invalid("Введите пикет: 12,18 или 12+1,8. Один пикет — 10 м; остаток после + меньше 10 м, без ведущих нулей.")
        }
        var result = first * 10
        if plus {
            guard let offset = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")) else { throw StorageError.invalidRecord }
            result += offset
        }
        guard result >= 0, result < Decimal(1_000_000_000_000_000) else { throw StorageError.invalidRecord }
        return result
    }
    static func meters(_ text: String) throws -> Double {
        let value = try decimalMeters(text)
        guard let result = Double(NSDecimalNumber(decimal: value).stringValue), result.isFinite else { throw StorageError.invalidRecord }
        return result
    }
    private static func normalizedDecimal(_ meters: Decimal) -> String {
        var pickets = meters / 10, whole = Decimal()
        NSDecimalRound(&whole, &pickets, 0, .down)
        let offset = meters - whole * 10
        func text(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",") }
        return "ПК " + text(whole) + (offset == 0 ? "" : "+" + text(offset))
    }
    static func canonical(_ text: String) throws -> String { normalizedDecimal(try decimalMeters(text)) }
    static func normalized(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0,
              let decimal = Decimal(string: ElevationInput.text(meters), locale: Locale(identifier: "en_US_POSIX")) else { return "—" }
        return normalizedDecimal(decimal)
    }
    static func confirmation(_ text: String) -> String? {
        guard let canonical = try? canonical(text), let value = try? decimalMeters(text) else { return nil }
        return "\(canonical) · \(NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",")) м"
    }
    fileprivate static func previousFloatingMeters(_ text: String) throws -> Double {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^ПК\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        let result: Double?
        if value.range(of: #"^[0-9]+\+[0-9](?:[.,][0-9]+)?$"#, options: .regularExpression) != nil {
            let parts = value.split(separator: "+")
            result = Double(parts[0]).flatMap { whole in
                Double(parts[1].replacingOccurrences(of: ",", with: ".")).map { whole * 10 + $0 }
            }
        } else if value.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil {
            result = Double(value.replacingOccurrences(of: ",", with: ".")).map { $0 * 10 }
        } else { result = nil }
        guard let result, result.isFinite, result >= 0, result < 1e15 else {
            throw MappingError.invalid("Введите пикет: 12, 1,7 или 12+9. Один пикет — 10 м; остаток после + от 0 до <10 м, например 12+9,5. Без ведущих нулей в остатке.")
        }
        return result
    }
}

extension PicketConvention {
    /// Accept the exact previous binary result as well, without rewriting old evidence.
    func matches(_ text: String, meters value: Double) -> Bool {
        if (try? meters(text)) == value { return true }
        return self == .tenMeters && (try? FieldPicketInput.previousFloatingMeters(text)) == value
    }
    func storedText(_ text: String) throws -> String {
        self == .tenMeters ? try FieldPicketInput.canonical(text) : text
    }
}

extension MappingObservation {
    var displayPicket: String {
        picketConvention == .tenMeters ? (try? FieldPicketInput.canonical(picket)) ?? picket : picket
    }
}

struct MappingDraft: Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
    var photoSessions: Set<UUID> = []
    var photos: [PhotoImportOperation] = []
    var saving = false
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
    var picketConvention = PicketConvention.tenMeters
    var startPicketConvention = PicketConvention.tenMeters
    var endPicketConvention = PicketConvention.tenMeters
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
        !photos.isEmpty || !photoSessions.isEmpty || ![picket, chainageOriginAndDirection, x, y, crs, axes, coordinateProvenance, notes].allSatisfy(\.isEmpty) ||
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
        self.init(id: observation.id)
        self.measurements = measurements
        picketConvention = observation.picketConvention ?? .legacyMeters
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
            startPicketConvention = g.start?.convention ?? .legacyMeters
            endPicketConvention = g.end?.convention ?? .legacyMeters
            startPicket = g.start?.text ?? ""; endPicket = g.end?.text ?? ""; observationPosition = g.position
            jointSets = g.jointSets.map(JointSetDraft.init)
            tectonicStructures = g.tectonicStructures.map(TectonicStructureDraft.init)
        }
        bartonQ = observation.ratings?.bartonQ?.input ?? BartonQInput()
        rmr89 = observation.ratings?.rmr89?.input ?? RMR89Input()
    }
}

/// Pre-MVP mapping databases are experimental; there is deliberately no upgrade or reset path.
enum MappingDatabaseError: LocalizedError {
    case incompatibleVersion(Int)
    var errorDescription: String? {
        switch self {
        case .incompatibleVersion(let version):
            return "Несовместимая экспериментальная база картирования: схема \(version), поддерживается только \(MappingJournal.currentSchemaVersion). Автоматическая миграция и сброс не выполняются. Файл, вложения и резервные копии сохранены."
        }
    }
}
