import Foundation

/// Converts only the documented editable columns to detached values. Original evidence
/// and nil/empty distinctions are retained by reusing untouched baseline objects.
enum ExchangeObservationProposal {
    typealias Row = ExchangeWorkbook.Row
    static func bad(_ text: String) -> ExchangeImportError { .init(text) }
    static func unsupported(_ text: String) -> ExchangeProposalFailure { .init(classification: .unsupported, reason: text) }
    static func number(_ text: String, field: String, required: Bool = false) throws -> Double? {
        if text.isEmpty && !required { return nil }
        guard text.utf8.count <= 128, text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite,
              normalizedDecimal(text) == normalizedDecimal(String(value)) else {
            throw bad("\(field): требуется точный десятичный текст без потери значащих цифр (не дата и не число Excel).")
        }
        return value
    }
    private static func normalizedDecimal(_ text: String) -> String {
        let parts = text.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2, let power = parts.count == 2 ? Int(parts[1]) : 0 else { return "invalid" }
        let negative = parts[0].hasPrefix("-")
        let mantissa = parts[0].filter { $0 != "+" && $0 != "-" }
        let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(mantissa.filter { $0 != "." })
        var exponent = power - (fraction.count == 2 ? fraction[1].count : 0)
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0" }
        while digits.last == "0" { digits.removeLast(); exponent += 1 }
        return (negative ? "-" : "") + String(digits) + "e" + String(exponent)
    }
    static func uuid(_ row: Row, _ key: String) throws -> UUID {
        guard let s = row[key], let id = UUID(uuidString: s) else { throw bad("\(key): неверный UUID.") }; return id
    }
    static func object<T: Codable>(_ type: T.Type, _ value: String) throws -> T {
        let decoded = try ExchangeBaseline.decode(type, value)
        // JSON input may have whitespace/reordered keys, but may not introduce unknown data.
        let raw = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        let encoded = try JSONSerialization.jsonObject(with: Data(MappingExchangeExport.json(decoded).utf8), options: [.fragmentsAllowed])
        guard NSDictionary(dictionary: ["value": raw]).isEqual(to: ["value": encoded]) else { throw bad("JSON содержит неизвестные поля или неоднозначные значения.") }
        return decoded
    }
    static func bool(_ row: Row, _ key: String) throws -> Bool {
        guard ["true", "false"].contains(row[key] ?? "") else { throw bad("\(key): требуется true/false.") }; return row[key] == "true"
    }
    static func protected(_ row: Row, base: Row, allowed: Set<String>, sheet: String) throws {
        for key in row.keys.sorted() where row[key, default: ""] != base[key, default: ""] && !allowed.contains(key) {
            throw unsupported("\(sheet).\(key): поле неизменяемое/расчётное или модификация не поддерживается.")
        }
    }
    static func make(row: Row, old: MappingObservation?, baseRow: Row, child: [String: [Row]], baseline: ExchangeBaseline, current: MappingCommittedSnapshot) throws -> MappingObservation {
        let isNew = old == nil
        let id = try uuid(row, isNew ? "client_record_id" : "point_id")
        let project = try uuid(row, "project_id"), horizon = try uuid(row, "horizon_id"), excavation = try uuid(row, "excavation_id")
        guard project == baseline.selection.projectID,
              current.journal.validContext(.init(projectID: project, horizonID: horizon, excavationID: excavation)) else { throw bad("Неверные родители точки или принадлежность проекту/горизонту.") }
        if isNew {
            guard current.projects[project] == baseline.snapshot.projects[project], current.horizons[horizon] == baseline.snapshot.horizons[horizon], current.excavations[excavation] == baseline.snapshot.excavations[excavation] else { throw ExchangeProposalFailure(classification: .conflict, reason: "Родительский контекст новой точки изменился; нужна новая выгрузка.") }
        }
        let convention: PicketConvention?
        if let old { convention = old.picketConvention }
        else { convention = try object(PicketConvention.self, row["picket_convention_json", default: ""]) }
        let picket = row["picket", default: ""], chainage = try number(row["chainage_m", default: ""], field: "chainage_m", required: true)!
        guard (convention ?? .legacyMeters).matches(picket, meters: chainage) else { throw bad("Пикет и chainage_m не согласованы с исходной системой отсчёта.") }
        let seconds = try number(row["observed_at_reference_seconds", default: ""], field: "observed_at_reference_seconds", required: true)!
        guard seconds >= -63_113_904_000, seconds <= 252_423_993_599 else { throw bad("Дата вне поддерживаемого диапазона.") }
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        guard row["observed_at_utc"] == MappingCSVExport.iso(date), let zone = row["observed_zone"].flatMap(TimeZone.init(identifier:)),
              let offset = row["observed_offset_seconds"].flatMap(Int.init), (-64800...64800).contains(offset) else { throw bad("Точная дата, ISO-время, пояс или смещение не согласованы.") }
        if old == nil || old?.observedAt != date || old?.observedTimeZoneID != zone.identifier || old?.observedUTCOffsetSeconds != offset {
            guard offset == zone.secondsFromGMT(for: date) else { throw bad("UTC-смещение не соответствует выбранной дате и поясу.") }
        }
        let coordinateFields: Set<String> = ["has_coordinates", "x", "y", "z_m", "xy_units", "crs", "axes", "coordinate_source", "coordinate_provenance", "z_origin", "z_horizon_id", "z_horizon_elevation_m", "z_datum", "plan_id", "z_plan_geometry_json"]
        let coordinates: MappingCoordinates?
        if !isNew && coordinateFields.allSatisfy({ row[$0] == baseRow[$0] }) { coordinates = old?.coordinates }
        else if try bool(row, "has_coordinates") {
            guard row["coordinate_source"] == "manual", row["xy_units"] == "m",
                  ["", "manualOverride"].contains(row["z_origin"] ?? ""),
                  ["z_horizon_id", "z_horizon_elevation_m", "z_datum", "plan_id", "z_plan_geometry_json"].allSatisfy({ row[$0, default: ""].isEmpty }) else { throw unsupported("Координаты: допускается только явный ручной источник без плана/расчётного Z. Старое происхождение сохраняется при других правках.") }
            let x = try number(row["x", default: ""], field: "x"), y = try number(row["y", default: ""], field: "y"), z = try number(row["z_m", default: ""], field: "z_m")
            guard z == nil || row["z_origin"] == "manualOverride" else { throw bad("Ручной Z требует z_origin=manualOverride.") }
            coordinates = MappingCoordinates(x: x, y: y, z: z, crs: row["crs", default: ""], axes: row["axes", default: ""], units: "m", source: "manual", provenance: row["coordinate_provenance", default: ""], zOrigin: row["z_origin"] == "manualOverride" ? .manualOverride : nil)
        } else {
            guard coordinateFields.subtracting(["has_coordinates"]).allSatisfy({ row[$0, default: ""].isEmpty }) else { throw bad("has_coordinates=false требует пустых координатных полей.") }; coordinates = nil
        }
        let oldGeology = old?.geology
        func boundary(_ prefix: String, previous: MappingPicket?) throws -> MappingPicket? {
            let text = row["interval_\(prefix)_text", default: ""], numeric = row["interval_\(prefix)_m", default: ""]
            if !isNew && text == baseRow["interval_\(prefix)_text"] && numeric == baseRow["interval_\(prefix)_m"] { return previous }
            guard !text.isEmpty || !numeric.isEmpty else { return nil }
            let value = try number(numeric, field: "interval_\(prefix)_m", required: true)!
            // Interval conventions are not projected separately: retain the old convention;
            // new boundaries explicitly follow the point's declared convention.
            let policy: PicketConvention?
            if let previous { policy = previous.convention } else { policy = convention }
            let p = MappingPicket(text: text, meters: value, convention: policy)
            try p.validate(); return p
        }
        func ordered(_ rows: [Row], key: String, originalIDs: [UUID]) -> [Row] {
            let offsets = Dictionary(uniqueKeysWithValues: originalIDs.enumerated().map { ($0.element.uuidString, $0.offset) })
            return rows.sorted {
                let a = offsets[$0[key] ?? ""] ?? Int.max, b = offsets[$1[key] ?? ""] ?? Int.max
                return a == b ? $0[key, default: ""] < $1[key, default: ""] : a < b
            }
        }
        let setRows = ordered(child["joint_sets"] ?? [], key: "joint_set_id", originalIDs: oldGeology?.jointSets.map(\.id) ?? [])
        let structureRows = ordered(child["tectonic_structures"] ?? [], key: "structure_id", originalIDs: oldGeology?.tectonicStructures.map(\.id) ?? [])
        let sets = try setRows.map { try joint($0, baseline: baseline, point: old) }
        let structures = try structureRows.map { try tectonic($0, baseline: baseline, point: old) }
        let geology: MappingGeology?
        if try bool(row, "has_geology") {
            let position: ObservationPosition?
            if row["position", default: ""].isEmpty { position = nil }
            else { guard let p = ObservationPosition(rawValue: row["position"]!) else { throw bad("Неизвестное положение наблюдения.") }; position = p }
            geology = MappingGeology(start: try boundary("start", previous: oldGeology?.start), end: try boundary("end", previous: oldGeology?.end), position: position, jointSets: sets, tectonicStructures: structures)
        } else {
            guard sets.isEmpty, structures.isEmpty, ["interval_start_text", "interval_start_m", "interval_end_text", "interval_end_m", "position"].allSatisfy({ row[$0, default: ""].isEmpty }) else { throw bad("has_geology=false противоречит геологическим данным.") }; geology = nil
        }
        let rock: RockLithology?
        if !isNew && row["rock_json"] == baseRow["rock_json"] { rock = old?.rock }
        else if row["rock_json", default: ""].isEmpty { rock = nil }
        else { rock = try object(RockLithology.self, row["rock_json"]!) }
        let ratings = try assessments(child["assessments"] ?? [], baseline: baseline, point: old)
        let candidate = MappingObservation(id: id, projectID: project, horizonID: horizon, excavationID: excavation,
            picket: picket, chainageMeters: chainage, chainageOriginAndDirection: row["chainage_origin_direction", default: ""], observedAt: date,
            observedTimeZoneID: row["observed_zone"]!, observedUTCOffsetSeconds: offset,
            createdAt: old?.createdAt ?? baseline.exportedAt, updatedAt: old?.updatedAt ?? baseline.exportedAt,
            coordinates: coordinates, measurementIDs: old?.measurementIDs ?? [], notes: row["notes", default: ""], geology: geology, ratings: ratings, picketConvention: convention, rock: rock)
        try current.journal.validateObservation(candidate, context: MappingValidationContext(current.journal))
        return candidate
    }
    static func baseRow(_ row: Row, sheet: String, baseline: ExchangeBaseline, key: String) -> Row {
        baseline.tables[sheet]!.rows.first { $0[key] == row[key] && $0["point_id"] == row["point_id"] } ?? [:]
    }
    static let pointFields: Set<String> = [
        "notes", "rock_json", "has_geology", "position", "interval_start_text", "interval_start_m",
        "interval_end_text", "interval_end_m", "correction_reason", "correction_author"
    ]
    static let jointFields: Set<String> = ["spacing_m", "persistence_m", "aperture_mm", "roughness", "infill", "notes"]
    static let tectonicFields: Set<String> = ["type", "thickness_m", "position", "description"]
    static let clear = "#CLEAR"

    static func joint(_ row: Row, baseline: ExchangeBaseline, point: MappingObservation?) throws -> InterpretedJointSet {
        let id = try uuid(row, "joint_set_id")
        let base = baseRow(row, sheet: "joint_sets", baseline: baseline, key: "joint_set_id")
        guard let old = point?.geology?.jointSets.first(where: { $0.id == id }) else {
            throw unsupported("joint_sets: добавление систем через Excel не поддерживается.")
        }
        if row == base { return old }
        guard old.identifier.isRoutine else { throw unsupported("joint_sets: историческая система J5 доступна только для просмотра.") }
        try protected(row, base: base, allowed: jointFields, sheet: "joint_sets")
        let spacing = try number(row["spacing_m", default: ""], field: "joint_sets.spacing_m")
        if row["spacing_m"] != base["spacing_m"] {
            guard old.spacingProvenance?.source == .manual else {
                throw unsupported("joint_sets.spacing_m: можно изменить только ранее введённое вручную расстояние.")
            }
            guard let spacing, spacing > 0 else { throw bad("joint_sets.spacing_m: требуется число больше нуля.") }
        }
        return InterpretedJointSet(id: old.id, identifier: old.identifier, revision: old.revision,
            interpretedAt: old.interpretedAt, author: old.author, method: old.method, representative: old.representative,
            measurementIDs: old.measurementIDs, spacingMeters: spacing,
            persistenceMeters: try nonnegative(row, "persistence_m", sheet: "joint_sets"),
            apertureMillimeters: try nonnegative(row, "aperture_mm", sheet: "joint_sets"),
            roughness: row["roughness", default: ""], infill: row["infill", default: ""],
            notes: row["notes", default: ""], spacingProvenance: old.spacingProvenance)
    }

    static func tectonic(_ row: Row, baseline: ExchangeBaseline, point: MappingObservation?) throws -> TectonicStructure {
        let id = try uuid(row, "structure_id")
        let base = baseRow(row, sheet: "tectonic_structures", baseline: baseline, key: "structure_id")
        guard let old = point?.geology?.tectonicStructures.first(where: { $0.id == id }) else {
            throw unsupported("tectonic_structures: добавление структур через Excel не поддерживается.")
        }
        if row == base { return old }
        try protected(row, base: base, allowed: tectonicFields, sheet: "tectonic_structures")
        guard let type = row["type"].flatMap(TectonicStructureType.init(rawValue:)) else {
            throw bad("tectonic_structures.type: неизвестный тип структуры.")
        }
        return TectonicStructure(id: old.id, type: type, orientation: old.orientation,
            thicknessMeters: try nonnegative(row, "thickness_m", sheet: "tectonic_structures"),
            picket: old.picket, position: row["position", default: ""], description: row["description", default: ""])
    }

    private static func nonnegative(_ row: Row, _ column: String, sheet: String) throws -> Double? {
        let value = try number(row[column, default: ""], field: "\(sheet).\(column)")
        guard value.map({ $0 >= 0 }) ?? true else { throw bad("\(sheet).\(column): требуется число не меньше нуля.") }
        return value
    }

    /// An omitted Excel cell is an untouched existing value. A literal #CLEAR
    /// explicitly clears a supported value, including one of the duplicate input columns.
    static func editing(_ row: Row, base: Row, fields: Set<String>, clearable: Set<String>) -> Row {
        guard !base.isEmpty else { return row }
        var result = row
        for field in fields.sorted() {
            guard row[field] != base[field] else { continue }
            let clearsLiteral = base[field] == clear && row[field] == clear + "!"
            if clearable.contains(field), row[field] == clear || clearsLiteral { result[field] = "" }
            else if row[field] == "" { result[field] = base[field] }
        }
        return result
    }

    static let qColumns = ["rqd_text": "rqd", "jn_text": "jn", "jr_text": "jr", "ja_text": "ja", "jw_text": "jw", "srf_text": "srf"]
    static let rmrColumns = ["rqd_text": "rqd", "rmr_spacing_m_text": "spacingMeters"]
    static let rmrSelections: Set<String> = ["rqd", "spacing"]
    static func assessmentFields(_ kind: String) -> Set<String> {
        if kind == "Q" { return Set(qColumns.keys).union(["input_json"]) }
        if kind == "RMR89-basic" { return Set(rmrColumns.keys).union(["input_json"]) }
        return ["input_json"]
    }

    private static func assessmentInput(_ row: Row, base: Row, columns: [String: String], coefficients: Bool) throws -> String {
        let json = row["input_json", default: ""]
        try ExchangeJSON.validate(json)
        guard var input = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw bad("assessments.input_json: требуется объект с входными данными.")
        }
        for (column, property) in columns.sorted(by: { $0.key < $1.key }) {
            let value = row[column, default: ""], before = base[column, default: ""]
            let nested = coefficients && property != "rqd"
            var coefficient = input[property] as? [String: Any] ?? [:]
            let projected = (nested ? coefficient["value"] : input[property]) as? String
            guard projected == before || projected == value else {
                throw bad("assessments.\(column) не совпадает с input_json.")
            }
            if value != before {
                if nested { coefficient["value"] = value; input[property] = coefficient }
                else { input[property] = value }
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), as: UTF8.self)
    }

    static func assessments(_ rows: [Row], baseline: ExchangeBaseline, point: MappingObservation?) throws -> MappingRatings? {
        guard !rows.isEmpty else { return point?.ratings }
        var ratings = point?.ratings
        for row in rows {
            let kind = row["kind", default: ""]
            let base = baseline.tables["assessments"]!.rows.first { $0["point_id"] == row["point_id"] && $0["kind"] == kind } ?? [:]
            if row == base { continue }
            guard !base.isEmpty, let old = ratings else { throw unsupported("assessments: добавление или замена методики не поддерживается.") }
            try protected(row, base: base, allowed: assessmentFields(kind), sheet: "assessments")
            do {
                switch kind {
                case "Q":
                    guard let q = old.bartonQ else { throw StorageError.invalidRecord }
                    let json = try assessmentInput(row, base: base, columns: qColumns, coefficients: true)
                    let input = try object(BartonQInput.self, json)
                    guard qInputAllowed(input, from: q.input) else {
                        throw unsupported("assessments.input_json: источники, обоснования, поправки и контекст Q доступны только для просмотра.")
                    }
                    try validateQSelections(input, from: q.input)
                    let revised = input == q.input ? q : try BartonQAssessment(input: input, now: q.assessedAt, method: q.method)
                    ratings = MappingRatings(bartonQ: revised, rmr89: old.rmr89, gsi: old.gsi, regulatory: old.regulatory)
                case "RMR89-basic":
                    guard let rmr = old.rmr89, rmr.method == RMR89Assessment.verifiedVersion else {
                        throw unsupported("assessments.input_json: историческая методика RMR89 доступна только для просмотра.")
                    }
                    let json = try assessmentInput(row, base: base, columns: rmrColumns, coefficients: false)
                    let input = try object(RMR89Input.self, json)
                    guard rmrInputAllowed(input, from: rmr.input) else {
                        throw unsupported("assessments.input_json: у RMR89 можно изменить только RQD, расстояние и соответствующие категории.")
                    }
                    let revised = input == rmr.input ? rmr : try RMR89Assessment(input: input, now: rmr.assessedAt, method: rmr.method)
                    ratings = MappingRatings(bartonQ: old.bartonQ, rmr89: revised, gsi: old.gsi, regulatory: old.regulatory)
                case "GSI":
                    guard let gsi = old.gsi, gsi.method == GSIAssessment.version else {
                        throw unsupported("assessments.input_json: графическая оценка GSI доступна только для просмотра.")
                    }
                    let input = try object(GSIAssessment.self, row["input_json", default: ""])
                    guard gsiInputAllowed(input, from: gsi) else {
                        throw unsupported("assessments.input_json: у GSI можно изменить только границы явно заданного интервала.")
                    }
                    try input.validate()
                    ratings = MappingRatings(bartonQ: old.bartonQ, rmr89: old.rmr89, gsi: input, regulatory: old.regulatory)
                default:
                    throw unsupported("assessments.input_json: оценка доступна только для просмотра.")
                }
            } catch let failure as ExchangeProposalFailure { throw failure }
            catch { throw bad("assessments.input_json (\(kind)): \(error.localizedDescription)") }
        }
        return ratings
    }

    private static func validateQSelections(_ input: BartonQInput, from old: BartonQInput) throws {
        for parameter in QParameter.allCases where input[parameter] != old[parameter] {
            let coefficient = input[parameter]
            _ = try coefficient.validated(parameter)
            if coefficient.origin == .tableSelection {
                var selected = QCoefficientInput()
                selected.select(coefficient.category, parameter: parameter)
                guard selected.origin == .tableSelection,
                      try RatingNumber.optional(selected.value, name: parameter.rawValue) ==
                          RatingNumber.optional(coefficient.value, name: parameter.rawValue) else {
                    throw bad("assessments.input_json.\(parameter.rawValue): значение не соответствует выбранной строке NGI.")
                }
            }
        }
    }

    static func qInputAllowed(_ input: BartonQInput, from old: BartonQInput) -> Bool {
        var allowed = old
        allowed.rqd = input.rqd
        for parameter in QParameter.allCases {
            guard input[parameter].evidence == old[parameter].evidence,
                  input[parameter].category == old[parameter].category || old[parameter].evidence.isEmpty else { return false }
            allowed[parameter] = input[parameter]
        }
        return allowed == input
    }

    static func rmrInputAllowed(_ input: RMR89Input, from old: RMR89Input) -> Bool {
        var allowed = old
        allowed.rqd = input.rqd
        allowed.spacingMeters = input.spacingMeters
        allowed.basicSelections = input.basicSelections
        if old.basicSelections != input.basicSelections, (old.basicSelections ?? [:]) == (input.basicSelections ?? [:]) {
            return false
        }
        return allowed == input &&
            (old.basicSelections ?? [:]).filter { !rmrSelections.contains($0.key) } ==
            (input.basicSelections ?? [:]).filter { !rmrSelections.contains($0.key) }
    }

    static func gsiInputAllowed(_ input: GSIAssessment, from old: GSIAssessment) -> Bool {
        input == GSIAssessment(selection: old.selection, lower: input.lower, upper: input.upper,
                               finalValue: old.finalValue, assessedAt: old.assessedAt)
    }

    static func ratingsAllowed(_ proposal: MappingRatings?, from old: MappingRatings?) -> Bool {
        if proposal == old { return true }
        guard let proposal, let old, proposal.regulatory == old.regulatory else { return false }
        if proposal.bartonQ != old.bartonQ {
            guard let revised = proposal.bartonQ, let previous = old.bartonQ,
                  revised.method == previous.method, revised.revision == previous.revision,
                  revised.assessedAt == previous.assessedAt,
                  qInputAllowed(revised.input, from: previous.input),
                  (try? validateQSelections(revised.input, from: previous.input)) != nil else { return false }
        }
        if proposal.rmr89 != old.rmr89 {
            guard let revised = proposal.rmr89, let previous = old.rmr89,
                  revised.method == RMR89Assessment.verifiedVersion, revised.method == previous.method,
                  revised.revision == previous.revision, revised.assessedAt == previous.assessedAt,
                  rmrInputAllowed(revised.input, from: previous.input) else { return false }
        }
        if proposal.gsi != old.gsi {
            guard let revised = proposal.gsi, let previous = old.gsi, previous.method == GSIAssessment.version,
                  gsiInputAllowed(revised, from: previous) else { return false }
        }
        return true
    }

    static func preservesEvidence(_ proposal: MappingObservation, from old: MappingObservation) -> Bool {
        guard proposal.coordinates == old.coordinates, proposal.picketConvention == old.picketConvention,
              proposal.picket == old.picket, proposal.chainageMeters == old.chainageMeters,
              proposal.chainageOriginAndDirection == old.chainageOriginAndDirection,
              proposal.observedAt == old.observedAt, proposal.observedTimeZoneID == old.observedTimeZoneID,
              proposal.observedUTCOffsetSeconds == old.observedUTCOffsetSeconds,
              old.geology == nil || proposal.geology != nil else { return false }
        let originalSets = old.geology?.jointSets ?? [], revisedSets = proposal.geology?.jointSets ?? []
        let originalFaults = old.geology?.tectonicStructures ?? [], revisedFaults = proposal.geology?.tectonicStructures ?? []
        guard originalSets.map(\.id) == revisedSets.map(\.id), originalFaults.map(\.id) == revisedFaults.map(\.id) else { return false }
        return zip(originalSets, revisedSets).allSatisfy { before, after in
            before.identifier == after.identifier && before.measurementIDs == after.measurementIDs &&
                before.author == after.author && before.method == after.method && before.representative == after.representative &&
                before.spacingProvenance == after.spacingProvenance &&
                (before.spacingMeters == after.spacingMeters ||
                    (before.spacingProvenance?.source == .manual && (after.spacingMeters ?? 0) > 0))
        } && zip(originalFaults, revisedFaults).allSatisfy { before, after in
            before.orientation == after.orientation && before.picket == after.picket
        }
    }

}
