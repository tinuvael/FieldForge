import Foundation

/// Transient B2b result. It deliberately has no apply/save method and owns no storage/URLs.
struct MappingExchangePreview: Sendable {
    enum Classification: String, CaseIterable, Sendable {
        case new, unchanged, correction, duplicate, conflict, invalid, unsupported
        var title: String {
            switch self {
            case .new: return "Новые"; case .unchanged: return "Без изменений"; case .correction: return "Исправления"
            case .duplicate: return "Дубликаты"; case .conflict: return "Конфликты"; case .invalid: return "Некорректные"; case .unsupported: return "Неподдерживаемые"
            }
        }
    }
    struct Change: Identifiable, Sendable {
        let sheet: String; let record: String; let field: String; let before: String; let after: String
        var id: String { sheet + "/" + record + "/" + field }
    }
    struct Record: Identifiable, Sendable {
        let id: String; let classification: Classification; let reason: String; let changes: [Change]
        /// Validated proposal values only; new timestamps/UUIDs and correction metadata
        /// here are preview placeholders. B2c must create admission-time values afresh.
        let proposed: MappingObservation?
    }
    let workbookID: UUID
    let generationID: UUID
    let exportedAt: Date
    let projectName: String
    let metadata: [String: String]
    let records: [Record]
    let proposalDigest: String
    var hasBlockingRecords: Bool { records.contains { [.conflict, .invalid, .unsupported].contains($0.classification) } }
    func count(_ classification: Classification) -> Int { records.filter { $0.classification == classification }.count }
    func isStale(comparedTo snapshot: MappingCommittedSnapshot) -> Bool { generationID != snapshot.generationID }

    static func prepare(url: URL, committed: MappingCommittedSnapshot, limits: ExchangeLimits = .init()) throws -> Self {
        try prepare(workbook: ExchangeWorkbook(url: url, limits: limits), committed: committed)
    }
    static func prepare(workbook: ExchangeWorkbook, committed: MappingCommittedSnapshot) throws -> Self {
        try Task.checkCancellation()
        let baseline = try ExchangeBaseline(workbook)
        return try ExchangeComparison(workbook: workbook, baseline: baseline, current: committed).result()
    }
}

struct ExchangeProposalFailure: Error { let classification: MappingExchangePreview.Classification; let reason: String }
private struct ExchangeComparison {
    typealias Row = ExchangeWorkbook.Row
    typealias Record = MappingExchangePreview.Record
    typealias Change = MappingExchangePreview.Change
    let workbook: ExchangeWorkbook; let baseline: ExchangeBaseline; let current: MappingCommittedSnapshot
    func unsupported(_ s: String) -> ExchangeProposalFailure { .init(classification: .unsupported, reason: s) }
    func invalid(_ s: String) -> ExchangeProposalFailure { .init(classification: .invalid, reason: s) }
    func conflict(_ s: String) -> ExchangeProposalFailure { .init(classification: .conflict, reason: s) }
    static let identities: [String: [String]] = [
        "projects": ["project_id"], "horizons": ["horizon_id"], "excavations": ["excavation_id"],
        "excavation_horizons": ["excavation_id", "horizon_id"], "points": ["point_id"],
        "measurements": ["measurement_id"], "joint_sets": ["joint_set_id"],
        "interpretation_evidence": ["joint_set_id", "joint_set_revision", "point_id", "measurement_id"],
        "tectonic_structures": ["structure_id"], "assessments": ["point_id", "kind"],
        "photo_point_contexts": ["revision_id"], "photos": ["photo_id"], "photo_attachments": ["attachment_id"],
        "source_records": ["kind", "record_id", "chunk_index"], "Формат": ["key"], "Колонки": ["sheet", "columns"]]
    func identity(_ r: Row, sheet: String) -> String {
        if sheet == "points", r["record_action"] == "new" { return "new/" + (r["client_record_id"] ?? "") }
        return (Self.identities[sheet] ?? []).map { r[$0] ?? "" }.joined(separator: "/")
    }
    func changes(_ row: Row, from old: Row, sheet: String) -> [Change] {
        row.keys.sorted().compactMap { key in
            let before = old[key] ?? "", after = row[key] ?? ""
            return before == after ? nil : Change(sheet: sheet, record: identity(row, sheet: sheet), field: key, before: before, after: after)
        }
    }
    func result() throws -> MappingExchangePreview {
        try current.journal.validate()
        var output: [Record] = [], clean: [String: [Row]] = [:], ambiguousPoints = Set<String>()
        for name in workbook.sheets.keys.sorted() {
            let groups = Dictionary(grouping: workbook.sheets[name]!.rows, by: { identity($0, sheet: name) })
            var rows: [Row] = []
            for id in groups.keys.sorted() {
                let group = groups[id]!, first = group[0]
                if group.contains(where: { $0 != first }) {
                    output.append(Record(id: "ambiguous/\(name)/\(id)", classification: .invalid, reason: "\(name): один UUID/ключ содержит разные строки.", changes: [], proposed: nil))
                    if name == "points" { ambiguousPoints.insert(id) }
                    else { for row in group { if let point = row["point_id"] { ambiguousPoints.insert(point) } } }
                } else {
                    rows.append(first)
                    if group.count > 1 { output.append(Record(id: "duplicate/\(name)/\(id)", classification: .duplicate, reason: "\(name): \(group.count) одинаковых строк; один логический объект.", changes: [], proposed: nil)) }
                }
            }
            clean[name] = rows
        }
        let editable: Set<String> = ["points", "joint_sets", "tectonic_structures", "assessments"]
        for name in baseline.tables.keys.sorted() where !editable.contains(name) && name != "source_records" && name != "Колонки" {
            let originals = baseline.tables[name]!.rows
            let incoming = clean[name] ?? []
            let oldByID = Dictionary(originals.map { (identity($0, sheet: name), $0) }, uniquingKeysWith: { first, _ in first })
            let newByID = Dictionary(incoming.map { (identity($0, sheet: name), $0) }, uniquingKeysWith: { first, _ in first })
            for id in Set(oldByID.keys).union(newByID.keys).sorted() {
                let old = oldByID[id] ?? [:], row = newByID[id] ?? [:]
                if row != old {
                    output.append(Record(id: "protected/\(name)/\(id)", classification: .unsupported,
                        reason: "\(name): исходные измерения, метаданные, связи и вложения изменять или удалять нельзя.",
                        changes: changes(row.isEmpty ? old.mapValues { _ in "" } : row, from: old, sheet: name), proposed: nil))
                }
            }
        }
        // Source hashes are not authentication: compare immutable local evidence as well.
        let localOriginals = Dictionary(current.journal.observations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localMeasurements = Dictionary(current.journal.measurements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for m in baseline.snapshot.journal.measurements where localMeasurements[m.id] != m {
            output.append(Record(id: "evidence/\(m.id)", classification: .unsupported, reason: "Исходный замер книги не совпадает с неизменяемым локальным доказательством.", changes: [], proposed: nil))
        }
        for p in baseline.snapshot.journal.photos where !current.journal.photos.contains(p) {
            output.append(Record(id: "photo/\(p.id)", classification: .unsupported, reason: "Исходная фотография/контекст отличается от локального.", changes: [], proposed: nil))
        }
        for a in baseline.snapshot.journal.photoAttachments where !current.journal.photoAttachments.contains(a) {
            output.append(Record(id: "attachment/\(a.id)", classification: .unsupported, reason: "Метаданные вложения отличаются от локальных.", changes: [], proposed: nil))
        }
        for r in baseline.snapshot.journal.photoRevisions where !current.journal.photoRevisions.contains(r) {
            output.append(Record(id: "photo-revision/\(r.id)", classification: .unsupported, reason: "История фотографии отличается от локальной.", changes: [], proposed: nil))
        }
        let bases = Dictionary(uniqueKeysWithValues: baseline.tables["points"]!.rows.map { ($0["point_id"]!, $0) })
        let pointRows = clean["points"] ?? []
        let pointIDs = Set(pointRows.map { identity($0, sheet: "points") })
        for id in bases.keys.sorted() where !pointIDs.contains(id) && !ambiguousPoints.contains(id) {
            output.append(Record(id: id, classification: .unsupported, reason: "Строка точки удалена. Удаление наблюдений через Excel не поддерживается.", changes: [], proposed: nil))
        }
        let children = ["joint_sets", "tectonic_structures", "assessments"]
        var childRows: [String: [String: [Row]]] = [:]
        for sheet in children { childRows[sheet] = Dictionary(grouping: clean[sheet] ?? [], by: { $0["point_id"] ?? "" }) }
        let validOwners = Set(pointRows.map { $0["record_action"] == "new" ? $0["client_record_id"] ?? "" : $0["point_id"] ?? "" })
        for sheet in children {
            for owner in (childRows[sheet] ?? [:]).keys.sorted() where !validOwners.contains(owner) {
                output.append(Record(id: "orphan/\(sheet)/\(owner)", classification: .invalid, reason: "\(sheet): родительская точка отсутствует или UUID неверен.", changes: [], proposed: nil))
            }
        }
        let journal = current.journal
        let identityCollections: [[UUID]] = [journal.projects.map(\.id), journal.horizons.map(\.id), journal.excavations.map(\.id),
            journal.plans.map(\.id), journal.observations.map(\.id), journal.revisions.map(\.id), journal.measurements.map(\.id),
            journal.photos.map(\.id), journal.photoAttachments.map(\.id), journal.photoRevisions.map(\.id)]
        var allIDs = Set(identityCollections.joined())
        for p in current.journal.observations + current.journal.revisions.map(\.snapshot) {
            allIDs.formUnion((p.geology?.jointSets.map(\.id) ?? []) + (p.geology?.tectonicStructures.map(\.id) ?? []))
        }
        var proposals: [UUID: Int] = [:]
        for row in pointRows where row["record_action"] == "new" { if let id = row["client_record_id"].flatMap(UUID.init(uuidString:)) { proposals[id, default: 0] += 1 } }
        // Every proposed UUID participates, including children and case-variant client IDs.
        for sheet in ["joint_sets", "tectonic_structures"] {
            let key = sheet == "joint_sets" ? "joint_set_id" : "structure_id"
            let existing = Set(baseline.tables[sheet]!.rows.compactMap { $0[key].flatMap(UUID.init(uuidString:)) })
            for row in clean[sheet] ?? [] {
                if let id = row[key].flatMap(UUID.init(uuidString:)), !existing.contains(id) { proposals[id, default: 0] += 1 }
            }
        }
        for row in pointRows {
            try Task.checkCancellation()
            let token = identity(row, sheet: "points"), isNew = row["record_action"] == "new"
            let owner = isNew ? row["client_record_id"] ?? "" : row["point_id"] ?? ""
            if ambiguousPoints.contains(owner) || ambiguousPoints.contains(token) { continue }
            let oldRow = bases[owner] ?? [:]
            var deltas = changes(row, from: oldRow, sheet: "points")
            do {
                guard let id = UUID(uuidString: owner) else { throw invalid("Неверный UUID точки/client_record_id.") }
                let old = baseline.snapshot.observation(id: id)
                if isNew {
                    guard old == nil, !allIDs.contains(id), proposals[id] == 1 else { throw conflict("client_record_id повторён или совпадает с существующим UUID.") }
                    for key in ["point_id", "original_id", "revision_id", "version", "base_fingerprint", "created_at_utc", "created_at_reference_seconds", "updated_at_reference_seconds", "corrected_at_utc", "corrected_at_reference_seconds"] {
                        guard row[key, default: ""].isEmpty else { throw invalid("Новая точка: \(key) должен быть пустым.") }
                    }
                    guard ["", "[]"].contains(row["measurement_ids_json", default: ""]) else { throw unsupported("Новые исходные измерения не поддерживаются.") }
                } else {
                    guard row["record_action"] == "existing", let old, let base = bases[owner] else { throw invalid("Нет исходного объекта. Новые строки требуют record_action=new.") }
                    guard localOriginals[id] == baseline.snapshot.journal.observations.first(where: { $0.id == id }) else { throw unsupported("Неизменяемый оригинал отличается от локального либо отсутствует.") }
                    guard current.observation(id: id) != nil else { throw conflict("Локальная точка отсутствует.") }
                    let history = baseline.snapshot.journal.history(for: id), localHistory = current.journal.history(for: id)
                    guard history == localHistory, try MappingExchangeExport.fingerprint(id, in: current) == base["base_fingerprint"] else { throw conflict("Базовая версия, история, родители или план изменились локально. Нужна новая выгрузка.") }
                    guard try MappingExchangeExport.fingerprint(old.id, in: baseline.snapshot) == row["base_fingerprint"] else { throw invalid("Базовый отпечаток не совпадает с исходными записями.") }
                    let allowed = Set(["picket", "chainage_m", "chainage_origin_direction", "observed_at_utc", "observed_at_reference_seconds", "observed_zone", "observed_offset_seconds", "interval_start_text", "interval_start_m", "interval_end_text", "interval_end_m", "position", "x", "y", "z_m", "xy_units", "crs", "axes", "coordinate_source", "coordinate_provenance", "z_origin", "z_horizon_id", "z_horizon_elevation_m", "z_datum", "plan_id", "z_plan_geometry_json", "notes", "rock_json", "has_coordinates", "has_geology", "correction_reason", "correction_author"])
                    for d in deltas where !allowed.contains(d.field) { throw unsupported("points.\(d.field): идентичность, родители, исходные данные и базовая метаинформация неизменяемы.") }
                }
                var child: [String: [Row]] = [:]
                for sheet in children {
                    let incoming = childRows[sheet]?[owner] ?? []
                    child[sheet] = incoming
                    let originals = baseline.tables[sheet]!.rows.filter { $0["point_id"] == owner }
                    let byID = Dictionary(uniqueKeysWithValues: originals.map { (identity($0, sheet: sheet), $0) })
                    let ids = Set(incoming.map { identity($0, sheet: sheet) })
                    guard Set(byID.keys).isSubset(of: ids) else { throw unsupported("\(sheet): удалена дочерняя строка; удаление не поддерживается.") }
                    for r in incoming {
                        let key = identity(r, sheet: sheet), base = byID[key] ?? [:]
                        if base.isEmpty && sheet != "assessments" {
                            let field = sheet == "joint_sets" ? "joint_set_id" : "structure_id"
                            guard let childID = r[field].flatMap(UUID.init(uuidString:)), !allIDs.contains(childID), proposals[childID] == 1 else { throw conflict("\(sheet): неверный, повторный или занятый UUID новой записи.") }
                        }
                        deltas += changes(r, from: base, sheet: sheet)
                    }
                }
                let candidate = try ExchangeObservationProposal.make(row: row, old: old, baseRow: oldRow, child: child, baseline: baseline, current: current)
                let actualChanges = deltas.filter { !["correction_reason", "correction_author"].contains($0.field) }
                if !isNew && !actualChanges.isEmpty && row["correction_reason", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw invalid("Укажите correction_reason — причину исправления.") }
                output.append(Record(id: token, classification: isNew ? .new : actualChanges.isEmpty ? .unchanged : .correction,
                    reason: isNew ? "Новая точка: только предложение; UUID и время принятия назначаются в B2c." : actualChanges.isEmpty ? "Совпадает с подтверждённой базой." : "Допустимое предложение исправления; оригинал и история сохранены.", changes: deltas, proposed: candidate))
            } catch let failure as ExchangeProposalFailure {
                output.append(Record(id: token, classification: failure.classification, reason: failure.reason, changes: deltas, proposed: nil))
            } catch {
                output.append(Record(id: token, classification: .invalid, reason: "Некорректные поля: \(error.localizedDescription)", changes: deltas, proposed: nil))
            }
        }
        let normalized = try workbook.sheets.keys.sorted().map { name in
            name + ":" + (try (clean[name] ?? []).map { try MappingExchangeExport.json($0) }.sorted().joined(separator: "\n"))
        }.joined(separator: "\n")
        return MappingExchangePreview(workbookID: baseline.workbookID, generationID: current.generationID, exportedAt: baseline.exportedAt,
            projectName: baseline.snapshot.journal.projects[0].name, metadata: baseline.metadata,
            records: output.sorted { $0.id < $1.id }, proposalDigest: ExchangeBaseline.hash(Data(normalized.utf8)))
    }
}
