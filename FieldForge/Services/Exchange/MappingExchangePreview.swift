import Foundation

/// Transient comparison and the typed input to an explicitly approved import.
struct MappingExchangePreview: Sendable {
    enum Classification: String, CaseIterable, Sendable {
        case new, unchanged, correction, duplicate, conflict, invalid, unsupported, ambiguous
        var title: String {
            switch self {
            case .new: return "Новые"; case .unchanged: return "Без изменений"; case .correction: return "Исправления"
            case .ambiguous: return "Требуют сопоставления"
            case .duplicate: return "Дубликаты"; case .conflict: return "Конфликты"; case .invalid: return "Некорректные"; case .unsupported: return "Неподдерживаемые"
            }
        }
    }
    struct Change: Identifiable, Sendable {
        let sheet: String; let record: String; let field: String; let before: String; let after: String
        var row: Int? = nil
        var id: String { sheet + "/" + record + "/" + field }
    }
    struct MatchCandidate: Identifiable, Sendable {
        let id: UUID
        let label: String
    }
    struct Record: Identifiable, Sendable {
        let id: String; let classification: Classification; let reason: String; let changes: [Change]
        let proposed: MappingObservation?
        var location = ""
        var label = ""
        var previous: MappingObservation?
        var baseline: MappingImportBaseline?
        var graphFingerprint: String?
        var correctionReason = ""
        var correctionAuthor: String?
        var receipt: MappingImportLedger.Entry?
        var candidates: [MatchCandidate] = []
        var matchedID: UUID?
        var reviewID: String?
        var regulatoryActions: RegulatoryDataImport.Actions?
        var importNote: String?
        var target: MappingImportTarget? { (proposed ?? previous).map(MappingImportTarget.init) }
        var canRejectPending: Bool { receipt?.outcome == .pending }
        var canRejectConflict: Bool { classification == .conflict && receipt == nil && target != nil }
        var canApply: Bool {
            [.new, .correction].contains(classification) && proposed != nil && (receipt == nil || receipt?.outcome == .pending)
        }
    }
    var source: MappingImportSource? = nil
    var rowsProcessed = 0
    var workbookBlocked = false
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
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limits.fileBytes + 1) ?? Data()
        return try prepare(data: bytes, committed: committed, limits: limits)
    }
    static func prepare(data: Data, committed: MappingCommittedSnapshot, limits: ExchangeLimits = .init()) throws -> Self {
        var archive = try ExchangeArchive(data: data, limits: limits)
        return try prepare(workbook: ExchangeWorkbook(parts: archive.readAll(), limits: limits), committed: committed, bytes: data)
    }
    static func prepare(workbook: ExchangeWorkbook, committed: MappingCommittedSnapshot, bytes: Data? = nil) throws -> Self {
        try Task.checkCancellation()
        let baseline = try ExchangeBaseline(workbook)
        let source = bytes.map { MappingImportSource(kind: .exchange, documentID: baseline.workbookID.uuidString, bytes: $0) }
        return try ExchangeComparison(workbook: workbook, baseline: baseline, current: committed, source: source).result()
    }

}

struct ExchangeProposalFailure: Error { let classification: MappingExchangePreview.Classification; let reason: String }
private struct ExchangeComparison {
    typealias Row = ExchangeWorkbook.Row
    typealias Record = MappingExchangePreview.Record
    typealias Change = MappingExchangePreview.Change
    let workbook: ExchangeWorkbook; let baseline: ExchangeBaseline; let current: MappingCommittedSnapshot
    let source: MappingImportSource?
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
    func uuidKey(_ value: String) -> String { UUID(uuidString: value)?.uuidString ?? value }
    func identity(_ r: Row, sheet: String) -> String {
        if sheet == "points", r["record_action"] == "new" { return "new/" + uuidKey(r["client_record_id"] ?? "") }
        return (Self.identities[sheet] ?? []).map { key in
            let value = r[key] ?? ""
            return key.hasSuffix("_id") ? uuidKey(value) : value
        }.joined(separator: "/")
    }
    func changes(_ row: Row, from old: Row, sheet: String, number: Int? = nil) -> [Change] {
        row.keys.sorted().compactMap { key in
            let before = old[key] ?? "", after = row[key] ?? ""
            return before == after ? nil : Change(sheet: sheet, record: identity(row, sheet: sheet), field: key, before: before, after: after, row: number)
        }
    }
    func result() throws -> MappingExchangePreview {
        try current.journal.validate()
        var output: [Record] = [], clean: [String: [Row]] = [:], ambiguousPoints = Set<String>()
        var rowNumbers: [String: [String: Int]] = [:]
        var workbookBlocked = false
        func location(_ sheet: String, _ key: String) -> String {
            rowNumbers[sheet]?[key].map { "\(sheet) · строка \($0)" } ?? sheet
        }
        for name in workbook.sheets.keys.sorted() {
            let sheet = workbook.sheets[name]!
            let groups = Dictionary(grouping: zip(sheet.rows, sheet.rowNumbers), by: { identity($0.0, sheet: name) })
            var rows: [Row] = []
            for id in groups.keys.sorted() {
                let group = groups[id]!, (first, number) = group[0]
                rowNumbers[name, default: [:]][id] = number
                let positions = group.map { String($0.1) }.joined(separator: ", ")
                if group.contains(where: { $0.0 != first }) {
                    output.append(Record(id: "ambiguous/\(name)/\(id)", classification: .invalid,
                        reason: "Один идентификатор использован в разных строках.", changes: [], proposed: nil,
                        location: "\(name) · строки \(positions)"))
                    if name == "points" { ambiguousPoints.insert(id) }
                    else if ["joint_sets", "tectonic_structures", "assessments"].contains(name) {
                        for (row, _) in group { ambiguousPoints.insert(uuidKey(row["point_id"] ?? "")) }
                    } else { workbookBlocked = true }
                } else {
                    rows.append(first)
                    if group.count > 1 {
                        output.append(Record(id: "duplicate/\(name)/\(id)", classification: .duplicate,
                            reason: "Одинаковые строки учтены как одна запись.", changes: [], proposed: nil,
                            location: "\(name) · строки \(positions)"))
                    }
                }
            }
            clean[name] = rows
        }
        let editable: Set<String> = ["points", "joint_sets", "tectonic_structures", "assessments"]
        for name in baseline.tables.keys.sorted() where !editable.contains(name) && name != "source_records" && name != "Колонки" && name != "Формат" {
            let originals = baseline.tables[name]!.rows
            let incoming = clean[name] ?? []
            let oldByID = Dictionary(originals.map { (identity($0, sheet: name), $0) }, uniquingKeysWith: { first, _ in first })
            let newByID = Dictionary(incoming.map { (identity($0, sheet: name), $0) }, uniquingKeysWith: { first, _ in first })
            for id in Set(oldByID.keys).union(newByID.keys).sorted() {
                let old = oldByID[id] ?? [:], row = newByID[id] ?? [:]
                if row != old {
                    workbookBlocked = true
                    output.append(Record(id: "protected/\(name)/\(id)", classification: .unsupported,
                        reason: "\(name): исходные измерения, метаданные, связи и вложения изменять или удалять нельзя.",
                        changes: changes(row.isEmpty ? old.mapValues { _ in "" } : row, from: old, sheet: name, number: rowNumbers[name]?[id]), proposed: nil, location: location(name, id)))
                }
            }
        }
        // Source hashes are not authentication: compare immutable local evidence as well.
        let localOriginals = Dictionary(current.journal.observations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localMeasurements = Dictionary(current.journal.measurements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for m in baseline.snapshot.journal.measurements where localMeasurements[m.id] != m {
            workbookBlocked = true
            output.append(Record(id: "evidence/\(m.id)", classification: .unsupported, reason: "Исходный замер книги не совпадает с неизменяемым локальным доказательством.", changes: [], proposed: nil))
        }
        for p in baseline.snapshot.journal.photos where !current.journal.photos.contains(p) {
            workbookBlocked = true
            output.append(Record(id: "photo/\(p.id)", classification: .unsupported, reason: "Исходная фотография/контекст отличается от локального.", changes: [], proposed: nil))
        }
        for a in baseline.snapshot.journal.photoAttachments where !current.journal.photoAttachments.contains(a) {
            workbookBlocked = true
            output.append(Record(id: "attachment/\(a.id)", classification: .unsupported, reason: "Метаданные вложения отличаются от локальных.", changes: [], proposed: nil))
        }
        for r in baseline.snapshot.journal.photoRevisions where !current.journal.photoRevisions.contains(r) {
            workbookBlocked = true
            output.append(Record(id: "photo-revision/\(r.id)", classification: .unsupported, reason: "История фотографии отличается от локальной.", changes: [], proposed: nil))
        }
        let bases = Dictionary(uniqueKeysWithValues: baseline.tables["points"]!.rows.map { ($0["point_id"]!, $0) })
        let pointRows = clean["points"] ?? []
        let pointIDs = Set(pointRows.map { identity($0, sheet: "points") })
        for id in bases.keys.sorted() where !pointIDs.contains(id) && !ambiguousPoints.contains(id) {
            output.append(Record(id: id, classification: .unsupported, reason: "Строка точки удалена. Удаление наблюдений через Excel не поддерживается.", changes: [], proposed: nil, location: "points", label: baseline.snapshot.observation(id: UUID(uuidString: id)!)?.picket ?? ""))
        }
        let children = ["joint_sets", "tectonic_structures", "assessments"]
        var childRows: [String: [String: [Row]]] = [:]
        for sheet in children { childRows[sheet] = Dictionary(grouping: clean[sheet] ?? [], by: { uuidKey($0["point_id"] ?? "") }) }
        let validOwners = Set(pointRows.map { uuidKey($0[$0["record_action"] == "new" ? "client_record_id" : "point_id"] ?? "") })
            .union(ambiguousPoints.map { $0.hasPrefix("new/") ? String($0.dropFirst(4)) : $0 })
        for sheet in children {
            for owner in (childRows[sheet] ?? [:]).keys.sorted() where !validOwners.contains(owner) {
                output.append(Record(id: "orphan/\(sheet)/\(owner)", classification: .invalid, reason: "Родительская точка отсутствует или её идентификатор неверен.", changes: [], proposed: nil,
                    location: (childRows[sheet]?[owner]?.first).map { location(sheet, identity($0, sheet: sheet)) } ?? sheet))
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
        let sourceEntries = (journal.importLedger?.entries ?? []).filter { $0.operation.source == source }
        let mutationReceipts = Dictionary(sourceEntries.filter { $0.operation.isMutation }.map { ($0.operation.sourceRecordID, $0) },
                                          uniquingKeysWith: { _, last in last })
        let originalsByPoint = Dictionary(uniqueKeysWithValues: children.map { sheet in
            (sheet, Dictionary(grouping: baseline.tables[sheet]!.rows, by: { $0["point_id"] ?? "" }))
        })
        for raw in pointRows {
            try Task.checkCancellation()
            let token = identity(raw, sheet: "points"), isNew = raw["record_action"] == "new"
            let owner = uuidKey(raw[isNew ? "client_record_id" : "point_id"] ?? "")
            if ambiguousPoints.contains(owner) || ambiguousPoints.contains(token) { continue }
            let id = UUID(uuidString: owner)
            let old = id.flatMap { baseline.snapshot.observation(id: $0) }
            let oldRow = bases[owner] ?? [:]
            let receipt = mutationReceipts[token]
            let excavationID = old?.excavationID ?? raw["excavation_id"].flatMap(UUID.init(uuidString:))
            let excavation = excavationID.flatMap { baseline.snapshot.excavations[$0]?.name } ?? ""
            let label = [old?.picket ?? raw["picket"] ?? "", excavation].filter { !$0.isEmpty }.joined(separator: " · ")
            let pointLocation = location("points", token)
            let row = ExchangeObservationProposal.editing(raw, base: oldRow, fields: ExchangeObservationProposal.pointFields,
                clearable: ExchangeObservationProposal.pointFields.subtracting(["has_geology", "correction_reason"]))
            var deltas = changes(row, from: oldRow, sheet: "points", number: rowNumbers["points"]?[token])
            var child: [String: [Row]] = [:]
            var missingChild = ""
            for sheet in children {
                let originals = originalsByPoint[sheet]?[owner] ?? []
                let byID = Dictionary(uniqueKeysWithValues: originals.map { (identity($0, sheet: sheet), $0) })
                let incoming = childRows[sheet]?[owner] ?? []
                if !Set(byID.keys).isSubset(of: Set(incoming.map { identity($0, sheet: sheet) })) { missingChild = sheet }
                child[sheet] = incoming.map { rawChild in
                    let key = identity(rawChild, sheet: sheet), base = byID[key] ?? [:]
                    let editable: Set<String>
                    let clearable: Set<String>
                    switch sheet {
                    case "joint_sets":
                        editable = ExchangeObservationProposal.jointFields; clearable = editable.subtracting(["spacing_m"])
                    case "tectonic_structures":
                        editable = ExchangeObservationProposal.tectonicFields; clearable = editable.subtracting(["type"])
                    default:
                        editable = ExchangeObservationProposal.assessmentFields(rawChild["kind"] ?? "")
                        clearable = editable.subtracting(["input_json"])
                    }
                    let normalized = ExchangeObservationProposal.editing(rawChild, base: base, fields: editable, clearable: clearable)
                    deltas += changes(normalized, from: base, sheet: sheet, number: rowNumbers[sheet]?[key])
                    return normalized
                }
            }
            let actualChanges = deltas.filter { !["correction_reason", "correction_author"].contains($0.field) }
            var previous = old
            var captured: MappingImportBaseline?
            var graph: String?
            do {
                guard let id else { throw invalid("points: неверный point_id или client_record_id.") }
                if let receipt, receipt.outcome == .applied {
                    output.append(Record(id: token, classification: .unchanged, reason: "Эта строка уже импортирована.", changes: [],
                        proposed: nil, location: pointLocation, label: label, receipt: receipt))
                    continue
                }
                if let receipt, case .rejected = receipt.outcome {
                    throw conflict("Строка этой книги уже отклонена. Для нового предложения выгрузите книгу снова.")
                }
                guard missingChild.isEmpty else { throw unsupported("\(missingChild): удалена дочерняя строка. Удаление строк запрещено.") }
                if isNew {
                    previous = current.observation(id: id)
                    guard old == nil, !allIDs.contains(id) else { throw conflict("client_record_id: идентификатор уже используется.") }
                    for key in ["point_id", "original_id", "revision_id", "version", "base_fingerprint", "created_at_utc", "created_at_reference_seconds", "updated_at_reference_seconds", "corrected_at_utc", "corrected_at_reference_seconds", "correction_reason", "correction_author"] {
                        guard row[key, default: ""].isEmpty else { throw invalid("points.\(key): для новой точки оставьте это поле пустым.") }
                    }
                    guard ["", "[]"].contains(row["measurement_ids_json", default: ""]) else { throw unsupported("points.measurement_ids_json: исходные измерения добавляются в приложении.") }
                    guard child.values.allSatisfy(\.isEmpty) else { throw unsupported("Для новой точки добавляйте системы, структуры и оценки в приложении.") }
                } else {
                    guard row["record_action"] == "existing", let old, !oldRow.isEmpty else { throw invalid("points.record_action: для новой точки используйте new и client_record_id.") }
                    guard localOriginals[id] == baseline.snapshot.journal.observations.first(where: { $0.id == id }) else { throw conflict("Неизменяемый оригинал отличается от локального либо отсутствует.") }
                    try ExchangeObservationProposal.protected(row, base: oldRow, allowed: ExchangeObservationProposal.pointFields, sheet: "points")
                    if old.geology != nil, row["has_geology"] == "false" { throw unsupported("points.has_geology: удаление геологических данных запрещено.") }
                    let target = MappingImportTarget(old)
                    guard current.observation(id: id) != nil else { throw conflict("Локальная точка отсутствует.") }
                    let localGraph = try MappingExchangeExport.fingerprint(id, in: current)
                    guard localGraph == oldRow["base_fingerprint"] else { throw conflict("Версия точки, контекст или план изменились после выгрузки. Нужна новая выгрузка.") }
                    graph = localGraph
                    captured = try .capture(target: target, in: current)
                }
                let candidate = !isNew && actualChanges.isEmpty ? old! : try ExchangeObservationProposal.make(
                    row: row, old: old, baseRow: oldRow, child: child, baseline: baseline, current: current)
                if isNew {
                    let target = MappingImportTarget(candidate)
                    graph = try MappingExchangeExport.importContextFingerprint(target, in: baseline.snapshot)
                    guard try MappingExchangeExport.importContextFingerprint(target, in: current) == graph else {
                        previous = candidate
                        throw conflict("Контекст новой точки или план изменились после выгрузки.")
                    }
                }
                let reason = row["correction_reason", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                let author = row["correction_author", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                let unchanged = candidate == old
                if !isNew && !unchanged {
                    guard !reason.isEmpty, reason.utf8.count <= 2048 else { throw invalid("points.correction_reason: укажите причину исправления (до 2048 байт).") }
                    guard author.utf8.count <= 512 else { throw invalid("points.correction_author: слишком длинное имя автора.") }
                }
                output.append(Record(id: token, classification: isNew ? .new : unchanged ? .unchanged : .correction,
                    reason: receipt?.outcome == .pending ? "Предыдущий импорт прерван. Выберите строку, чтобы продолжить." :
                        isNew ? "Новая точка журнала." : unchanged ? "Нет изменений для сохранения." : "Будет создана новая версия точки.",
                    changes: deltas, proposed: candidate, location: pointLocation, label: label, previous: previous,
                    baseline: captured, graphFingerprint: graph, correctionReason: reason, correctionAuthor: author.isEmpty ? nil : author,
                    receipt: receipt))
            } catch let failure as ExchangeProposalFailure {
                output.append(Record(id: token, classification: failure.classification, reason: failure.reason, changes: deltas,
                    proposed: nil, location: pointLocation, label: label, previous: previous, receipt: receipt))
            } catch {
                output.append(Record(id: token, classification: .invalid, reason: "Некорректное поле: \(error.localizedDescription)",
                    changes: deltas, proposed: nil, location: pointLocation, label: label, previous: previous, receipt: receipt))
            }
        }
        let normalized = try workbook.sheets.keys.sorted().map { name in
            name + ":" + (try (clean[name] ?? []).map { try MappingExchangeExport.json($0) }.sorted().joined(separator: "\n"))
        }.joined(separator: "\n")
        return MappingExchangePreview(source: source, rowsProcessed: workbook.sheets["points"]?.rows.count ?? 0,
            workbookBlocked: workbookBlocked, workbookID: baseline.workbookID, generationID: current.generationID, exportedAt: baseline.exportedAt,
            projectName: baseline.snapshot.journal.projects[0].name, metadata: baseline.metadata,
            records: output.sorted { $0.id < $1.id }, proposalDigest: ExchangeBaseline.hash(Data(normalized.utf8)))
    }
}

extension MappingExchangePreview.Record {
    struct DisplayChange: Identifiable {
        let id: String
        let title: String
        let before: String
        let after: String
    }

    private static let columnLabels = [
        "notes": "Примечание", "position": "Положение", "interval_start_text": "Начало интервала",
        "interval_start_m": "Начало интервала, м", "interval_end_text": "Конец интервала", "interval_end_m": "Конец интервала, м",
        "has_geology": "Геологические данные", "correction_reason": "Причина исправления", "correction_author": "Автор исправления",
        "spacing_m": "Расстояние, м", "persistence_m": "Протяжённость, м", "aperture_mm": "Раскрытие, мм",
        "roughness": "Шероховатость", "infill": "Заполнитель", "description": "Описание",
        "type": "Тип структуры", "thickness_m": "Мощность, м", "picket": "Пикет",
        "chainage_m": "Расстояние по выработке, м", "chainage_origin_direction": "Начало и направление отсчёта",
        "observed_at_utc": "Время наблюдения (UTC)", "observed_at_reference_seconds": "Точное время (с от 01.01.2001 UTC)",
        "observed_zone": "Часовой пояс наблюдения", "observed_offset_seconds": "Смещение от UTC, с",
        "has_coordinates": "Координаты заданы", "x": "X", "y": "Y", "z_m": "Z, м", "xy_units": "Единицы X и Y",
        "crs": "Система координат", "axes": "Оси координат", "coordinate_source": "Способ задания координат",
        "coordinate_provenance": "Происхождение координат", "z_origin": "Источник отметки Z",
        "project_id": "UUID проекта", "horizon_id": "UUID горизонта", "excavation_id": "UUID выработки",
        "client_record_id": "UUID новой точки", "record_action": "Действие со строкой",
        "rqd_text": "RQD, %", "rmr_spacing_m_text": "RMR89 · Расстояние, м",
        "jn_text": "Q · Jn", "jr_text": "Q · Jr", "ja_text": "Q · Ja", "jw_text": "Q · Jw", "srf_text": "Q · SRF"
    ]

    var visibleChanges: [DisplayChange] {
        changes.flatMap { change -> [DisplayChange] in
            let location = change.row.map { " · \(change.sheet), строка \($0)" } ?? ""
            func display(_ title: String, before: String, after: String) -> [DisplayChange] {
                [.init(id: change.id, title: title + location, before: before, after: after)]
            }
            if let label = Self.columnLabels[change.field] {
                let title = change.field == "rqd_text" && change.sheet == "assessments"
                    ? (change.record.hasSuffix("/Q") ? "Q" : "RMR89") + " · " + label : label
                return display(title, before: Self.columnValue(change.before, for: change), after: Self.columnValue(change.after, for: change))
            }
            let isProposal = classification == .new || classification == .correction
            guard isProposal || classification == .conflict else { return [] }
            switch change.field {
            case "rock_json", "input_json":
                return structuredChanges(change, location: location)
            case "picket_convention_json":
                func convention(_ raw: String) -> String {
                    switch try? ExchangeObservationProposal.object(PicketConvention.self, raw) {
                    case .legacyMeters: "Километры + метры"
                    case .tenMeters: "Пикет 10 м"
                    case nil: raw
                    }
                }
                return display("Система отсчёта пикетов", before: convention(change.before), after: convention(change.after))
            default:
                return isProposal || change.sheet == "Data" ? display(change.field, before: change.before, after: change.after) : []
            }
        }
    }

    private static func columnValue(_ value: String, for change: MappingExchangePreview.Change) -> String {
        switch change.field {
        case "has_geology", "has_coordinates":
            return ["true": "Да", "false": "Нет"][value] ?? value
        case "position" where change.sheet == "points":
            return ["roof": "Кровля", "leftWall": "Левая стенка", "rightWall": "Правая стенка",
                    "face": "Забой", "other": "Другое"][value] ?? value
        case "type" where change.sheet == "tectonic_structures":
            return ["fault": "Разлом", "shearZone": "Зона сдвига", "fractureZone": "Зона трещиноватости",
                    "other": "Другое"][value] ?? value
        case "coordinate_source": return value == "manual" ? "Вручную" : value
        case "z_origin": return ElevationOrigin(rawValue: value)?.fieldLabel ?? value
        case "record_action": return value == "new" ? "Создать наблюдение" : value
        default: return value
        }
    }

    private func structuredChanges(_ change: MappingExchangePreview.Change, location: String) -> [DisplayChange] {
        let isRock = change.field == "rock_json"
        let kind = change.record.split(separator: "/").last.map(String.init) ?? ""
        var paths: [(key: String, title: String, column: String?)] = []
        if isRock {
            paths = [("code", "Код породы", nil), ("name", "Название породы", nil)]
        } else {
            switch kind {
            case "Q":
                paths = [("rqd", "Q · RQD, %", "rqd_text")]
                paths += QParameter.allCases.flatMap { parameter in
                    let key = parameter.rawValue
                    let label = Self.columnLabels[key + "_text"] ?? key
                    return [("\(key).value", label, key + "_text"), ("\(key).category", "\(label) · Категория", nil),
                            ("\(key).origin", "\(label) · Способ выбора", nil)]
                }
            case "RMR89-basic":
                paths = [("rqd", "RMR89 · RQD, %", "rqd_text"), ("spacingMeters", "RMR89 · Расстояние, м", "rmr_spacing_m_text"),
                         ("basicSelections.rqd", "RMR89 · Категория RQD", nil),
                         ("basicSelections.spacing", "RMR89 · Категория расстояния", nil)]
            case "GSI":
                paths = [("lower", "GSI · Нижняя граница", nil), ("upper", "GSI · Верхняя граница", nil)]
            default: break
            }
        }
        let title = isRock ? "Данные о породе (JSON)" : "Входные данные оценки (JSON)"
        let fallback = DisplayChange(id: change.id, title: title + location, before: change.before, after: change.after)
        guard !paths.isEmpty, var before = Self.jsonObject(change.before), var after = Self.jsonObject(change.after) else {
            return [fallback]
        }
        var result: [DisplayChange] = []
        var needsFallback = false
        for (key, label, column) in paths {
            let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
            let old = Self.remove(parts, from: &before)
            let new = Self.remove(parts, from: &after)
            guard let a = Self.scalar(old), let b = Self.scalar(new) else {
                needsFallback = true
                continue
            }
            if a == b { continue }
            if let column, changes.contains(where: {
                $0.sheet == change.sheet && $0.record == change.record && $0.field == column && $0.before == a && $0.after == b
            }) { continue }
            result.append(.init(id: change.id + "/" + key, title: label + location,
                before: Self.jsonValue(a, key: key), after: Self.jsonValue(b, key: key)))
        }
        // Compare the unexpanded portion even when some known fields were shown.
        let remainingBefore = try? JSONSerialization.data(withJSONObject: before, options: [.sortedKeys])
        let remainingAfter = try? JSONSerialization.data(withJSONObject: after, options: [.sortedKeys])
        if needsFallback || remainingBefore != remainingAfter { result.append(fallback) }
        return result
    }

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        if raw.isEmpty { return [:] }
        guard (try? ExchangeJSON.validate(raw)) != nil else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    private static func remove(_ path: [String], from fields: inout [String: Any]) -> Any? {
        if path.count == 1 { return fields.removeValue(forKey: path[0]) }
        guard var group = fields[path[0]] as? [String: Any], let value = group.removeValue(forKey: path[1]) else { return nil }
        fields[path[0]] = group.isEmpty ? nil : group
        return value
    }

    private static func scalar(_ value: Any?) -> String? {
        guard let value else { return "" }
        if let text = value as? String { return text }
        return (value as? NSNumber)?.stringValue
    }

    private static func jsonValue(_ value: String, key: String) -> String {
        if key.hasSuffix(".origin"), let origin = QValueOrigin(rawValue: value) {
            return origin == .tableSelection ? "Выбрана табличная величина" : "Ручной ввод в пределах строки"
        }
        if key.hasPrefix("basicSelections."), let parameter = RMR89Parameter(rawValue: String(key.dropFirst("basicSelections.".count))),
           let choice = parameter.choices(test: nil).first(where: { $0.id == value }) {
            return "\(choice.title) (\(choice.rating) балл.)"
        }
        if key.hasSuffix(".category"), let parameter = QParameter(rawValue: String(key.dropLast(".category".count))),
           let row = QMethod.rows(parameter).first(where: { $0.id == value }) {
            return "\(value) · \(row.description)"
        }
        return value
    }
}
