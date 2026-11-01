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
        for key in row.keys where row[key, default: ""] != base[key, default: ""] && !allowed.contains(key) {
            throw unsupported("\(sheet).\(key): поле неизменяемое/расчётное или модификация не поддерживается.")
        }
    }
    static func make(row: Row, old: MappingObservation?, baseRow: Row, child: [String: [Row]], baseline: ExchangeBaseline, current: MappingCommittedSnapshot) throws -> MappingObservation {
        let isNew = old == nil
        if !isNew {
            for field in ["x", "y", "z_m", "chainage_m", "interval_start_m", "interval_end_m", "observed_at_reference_seconds"] {
                let before = baseRow[field, default: ""], after = row[field, default: ""]
                if before != after, let original = Double(before), let edited = Double(after), original != edited {
                    let excel = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), original)
                    if Double(excel) == edited { throw bad("\(field): значение совпадает с потерей точности Excel до 15 значащих цифр. Восстановите исходный текст или выполните исправление в приложении.") }
                }
            }
        }
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
        let sets = try setRows.map { try joint($0, baseline: baseline, point: old, pointID: id) }
        let structures = try structureRows.map { try tectonic($0, baseline: baseline, point: old, pointID: id, convention: convention) }
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
        let ratings = try assessments(child["assessments"] ?? [], baseline: baseline, point: old, pointID: id)
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
    static func joint(_ row: Row, baseline: ExchangeBaseline, point: MappingObservation?, pointID: UUID) throws -> InterpretedJointSet {
        let id = try uuid(row, "joint_set_id"), old = point?.geology?.jointSets.first { $0.id == id }
        let base = baseRow(row, sheet: "joint_sets", baseline: baseline, key: "joint_set_id")
        if !base.isEmpty {
            try protected(row, base: base, allowed: ["author", "original_direction_text", "original_dip_text", "north", "representative_json", "spacing_m", "persistence_m", "aperture_mm", "roughness", "infill", "notes", "spacing_provenance_json", "dip_direction_deg", "dip_angle_deg", "direction_meaning"], sheet: "joint_sets")
            if row == base, let old { return old }
        } else {
            guard ["", "1"].contains(row["revision", default: ""]), row["interpreted_at_utc", default: ""].isEmpty, row["interpreted_at_reference_seconds", default: ""].isEmpty else { throw bad("Новая система: версия 1, время интерпретации назначается при принятии.") }
        }
        guard let identifier = row["identifier"].flatMap(JointSetIdentifier.init(rawValue:)), row["method"] == "user-interpretation-v1" else { throw bad("Неверная система J1–J5 или метод интерпретации.") }
        let representative = try object(ManualOrientationInput.self, row["representative_json", default: ""])
        let validated = try representative.validated()
        guard row["original_direction_text"] == representative.dipDirectionText, row["original_dip_text"] == representative.dipAngleText, row["north"] == representative.reference.rawValue,
              row["direction_meaning"] == validated.meaning.rawValue,
              try number(row["dip_direction_deg", default: ""], field: "joint dip direction") == validated.orientation.dipDirection,
              try number(row["dip_angle_deg", default: ""], field: "joint dip") == validated.orientation.dipAngle else { throw bad("Система: исходные строки, JSON и производные ориентации не согласованы.") }
        let provenance: JointSpacingProvenance? = row["spacing_provenance_json", default: ""].isEmpty ? nil : try object(JointSpacingProvenance.self, row["spacing_provenance_json"]!)
        if row["spacing_m"] != base["spacing_m"], provenance?.source != .manual { throw unsupported("Изменение SD требует явного ручного spacing_provenance_json; оценка по RQD не подменяется.") }
        let spacing = try number(row["spacing_m", default: ""], field: "spacing_m")
        if provenance?.source == .manual, let spacing, spacing <= 0 { throw bad("Ручное SD должно быть больше нуля.") }
        let set = InterpretedJointSet(id: id, identifier: identifier, revision: old?.revision ?? 1, interpretedAt: old?.interpretedAt ?? baseline.exportedAt,
            author: row["author", default: ""].isEmpty ? nil : row["author"], method: "user-interpretation-v1", representative: representative,
            measurementIDs: old?.measurementIDs ?? [], spacingMeters: spacing,
            persistenceMeters: try number(row["persistence_m", default: ""], field: "persistence_m"), apertureMillimeters: try number(row["aperture_mm", default: ""], field: "aperture_mm"),
            roughness: row["roughness", default: ""], infill: row["infill", default: ""], notes: row["notes", default: ""], spacingProvenance: provenance)
        try set.validate(pointMeasurementIDs: point?.measurementIDs ?? []); return set
    }
    static func tectonic(_ row: Row, baseline: ExchangeBaseline, point: MappingObservation?, pointID: UUID, convention: PicketConvention?) throws -> TectonicStructure {
        let id = try uuid(row, "structure_id"), base = baseRow(row, sheet: "tectonic_structures", baseline: baseline, key: "structure_id")
        let old = point?.geology?.tectonicStructures.first { $0.id == id }
        if !base.isEmpty {
            try protected(row, base: base, allowed: Set(row.keys).subtracting(["structure_id", "point_id"]), sheet: "tectonic_structures")
            if row == base, let old { return old }
        }
        guard let type = row["type"].flatMap(TectonicStructureType.init(rawValue:)), let north = row["north"].flatMap(GeographicReference.init(rawValue:)), ["true", "false"].contains(row["conventional_dip_side"] ?? "") else { throw bad("Неверные тип/север/условная сторона структуры.") }
        let input = ManualOrientationInput(dipAngleText: row["original_dip_text", default: ""], dipDirectionText: row["original_direction_text", default: ""], reference: north, usesConventionalDipSide: row["conventional_dip_side"] == "true")
        let orientation = try input.validatedTectonic()
        guard try number(row["dip_direction_deg", default: ""], field: "tectonic direction") == orientation.dipDirection,
              try number(row["dip_angle_deg", default: ""], field: "tectonic dip") == orientation.dipAngle else { throw bad("Структура: исходная и нормализованная ориентации не согласованы.") }
        let picket: MappingPicket?
        if row["picket_text"] == base["picket_text"], row["chainage_m"] == base["chainage_m"], let old { picket = old.picket }
        else if row["picket_text", default: ""].isEmpty, row["chainage_m", default: ""].isEmpty { picket = nil }
        else {
            let policy: PicketConvention?
            if let previous = old?.picket { policy = previous.convention } else { policy = convention }
            picket = MappingPicket(text: row["picket_text", default: ""], meters: try number(row["chainage_m", default: ""], field: "tectonic chainage", required: true)!, convention: policy)
        }
        let value = TectonicStructure(id: id, type: type, orientation: input, thicknessMeters: try number(row["thickness_m", default: ""], field: "thickness_m"), picket: picket, position: row["position", default: ""], description: row["description", default: ""])
        try value.validate(); return value
    }
    static func assessments(_ rows: [Row], baseline: ExchangeBaseline, point: MappingObservation?, pointID: UUID) throws -> MappingRatings? {
        var q = point?.ratings?.bartonQ, rmr = point?.ratings?.rmr89, gsi = point?.ratings?.gsi
        var seen = Set<String>()
        for row in rows {
            let kind = row["kind", default: ""], family = kind.hasPrefix("RMR89") ? "RMR89" : kind
            guard ["Q", "RMR89", "GSI"].contains(family), seen.insert(family).inserted else { throw bad("Неизвестная или повторная система оценки.") }
            let base = baseline.tables["assessments"]!.rows.first { $0["point_id"] == row["point_id"] && $0["kind"] == kind } ?? [:]
            if row == base { continue }
            let convenience: [String: String]
            switch family {
            case "Q": convenience = ["rqd_text": "rqd", "jn_text": "jn", "jr_text": "jr", "ja_text": "ja", "jw_text": "jw", "srf_text": "srf"]
            case "RMR89": convenience = ["rqd_text": "rqd", "rmr_strength_test": "strengthTest", "rmr_strength_mpa_text": "strengthMPa", "rmr_strength_evidence": "strengthEvidence", "rmr_rqd_evidence": "rqdEvidence", "rmr_spacing_m_text": "spacingMeters", "rmr_persistence_m_text": "persistenceMeters", "rmr_aperture_mm_text": "apertureMillimeters", "rmr_roughness": "roughness", "rmr_infill": "infill", "rmr_weathering": "weathering", "rmr_groundwater": "groundwater", "rmr_inflow_l_min_per_10m_text": "inflowLitersPerMinutePer10m", "rmr_water_pressure_ratio_text": "waterPressureRatio", "rmr_application": "application", "rmr_orientation_description": "orientationDescription", "rmr_source": "source", "rmr_assessor": "assessor", "rmr_missing_reason": "missingReason"]
            default: convenience = [:]
            }
            if !base.isEmpty {
                try protected(row, base: base, allowed: Set(convenience.keys).union(["input_json"]), sheet: "assessments")
            } else {
                let allowed = Set(convenience.keys).union(["point_id", "kind", "method", "input_json"])
                try protected(row, base: [:], allowed: allowed, sheet: "new assessment")
                if family == "RMR89", point?.ratings?.rmr89 != nil { throw unsupported("Нельзя менять kind или метод существующей оценки RMR.") }
            }
            let json = row["input_json", default: ""]
            try ExchangeJSON.validate(json)
            let inputObject = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
            for (column, property) in convenience {
                let value: String
                if family == "Q", property != "rqd" { value = (inputObject[property] as? [String: Any])?["value"] as? String ?? "" }
                else { value = inputObject[property] as? String ?? "" }
                guard row[column, default: ""] == value else { throw bad("assessments.\(column) не совпадает с input_json.") }
            }
            if family == "Q" {
                let input = try object(BartonQInput.self, json)
                if let old = q {
                    let evaluation = try old.method == QMethod.version ? input.evaluate() : input.fieldEvaluation()
                    q = try patched(old, fields: ["input": MappingExchangeExport.json(input), "evaluation": MappingExchangeExport.json(evaluation)])
                } else { q = try BartonQAssessment(input: input, now: baseline.exportedAt) }
                guard q?.method == row["method"] else { throw unsupported("Метод Q не поддерживается или изменён.") }
                try q?.validate()
            } else if family == "RMR89" {
                let input = try object(RMR89Input.self, json), old = rmr
                let revised = try RMR89Assessment(input: input, now: old?.assessedAt ?? baseline.exportedAt)
                guard revised.method == row["method"], old == nil || revised.method == old?.method,
                      kind == (revised.calculation == nil ? "RMR89-input-only" : "RMR89-basic") else { throw unsupported("Метод/kind RMR нельзя переопределить.") }
                rmr = revised; try rmr?.validate()
            } else {
                let input = try object(GSIAssessment.self, json)
                guard input.method == row["method"] else { throw unsupported("Метод GSI изменён.") }
                if let old = gsi {
                    guard input.method == old.method, input.assessedAt == old.assessedAt, input.finalValue == old.finalValue else { throw unsupported("Метод, время и сохранённый результат GSI неизменяемы.") }
                }
                try input.validate(); gsi = input
            }
        }
        guard q != nil || rmr != nil || gsi != nil else { return nil }
        return MappingRatings(bartonQ: q, rmr89: rmr, gsi: gsi)
    }
    static func patched<T: Codable>(_ old: T, fields: [String: String]) throws -> T {
        var obj = try JSONSerialization.jsonObject(with: Data(MappingExchangeExport.json(old).utf8)) as! [String: Any]
        for (key, value) in fields { obj[key] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .fragmentsAllowed]))
    }
}
