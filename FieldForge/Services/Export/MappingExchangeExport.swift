import Foundation
import CryptoKit

/// Export-only exchange contract. No importer, persistence mutation or attachment IO.
struct MappingExchangeExport: Sendable {
    static let version = "FieldForge-Exchange/1"
    static let fingerprintVersion = "FieldForge-Exchange-Base/1"
    typealias Table = MappingCSVExport.Table
    typealias Cell = MappingCSVExport.Cell
    let id: UUID
    let snapshotAt: Date
    let tables: [Table]

    /// Canonical schema-8 JSON: sorted keys, unescaped slashes, reference-epoch Date doubles.
    /// Array order is significant; unordered excavation horizon membership is sorted explicitly.
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    private struct ExcavationRecord: Encodable {
        let id: UUID
        let projectID: UUID
        let name: String
        let horizonIDs: [UUID]
        init(_ e: MappingExcavation) {
            id = e.id; projectID = e.projectID; name = e.name
            horizonIDs = e.horizonIDs.sorted { $0.uuidString < $1.uuidString }
        }
    }
    private struct Base: Encodable {
        let format: String
        let original: MappingObservation
        let revisions: [MappingObservationRevision]
        let measurements: [Measurement]
        let project: MappingProject
        let horizon: MappingHorizon
        let excavation: ExcavationRecord
        let plans: [MappingPlanReference]
    }
    static func fingerprint(_ pointID: UUID, in snapshot: MappingCommittedSnapshot) throws -> String {
        let j = snapshot.journal
        guard let original = j.observations.first(where: { $0.id == pointID }),
              let project = snapshot.projects[original.projectID], let horizon = snapshot.horizons[original.horizonID],
              let excavation = snapshot.excavations[original.excavationID] else { throw StorageError.invalidRecord }
        let horizonIDs = Set(j.horizons.filter { $0.projectID == original.projectID }.map(\.id))
        let base = Base(format: fingerprintVersion, original: original,
            revisions: j.history(for: pointID), measurements: snapshot.measurements(for: original),
            project: project, horizon: horizon, excavation: ExcavationRecord(excavation),
            plans: j.plans.filter { horizonIDs.contains($0.horizonID) }.sorted { $0.id.uuidString < $1.id.uuidString })
        return SHA256.hash(data: Data(try json(base).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func prepare(committed: MappingCommittedSnapshot, selection: MappingExportSelection,
                        now: Date = Date(), id: UUID = UUID()) throws -> Self {
        try Task.checkCancellation()
        let journal = committed.journal
        try journal.validate()
        // Reuse normalized report projection, selection and relationship rules; never its rounded field sheets.
        let report = try MappingCSVExport.prepare(journal: journal, selection: selection, now: now, id: id)
        guard let pointsTable = report.tables.first(where: { $0.name == "points" }) else { throw StorageError.invalidRecord }
        let pointIDs = Set(pointsTable.rows.compactMap { row -> UUID? in
            guard case .text(let value) = row[0] else { return nil }; return UUID(uuidString: value)
        })
        let points = committed.observations(projectID: selection.projectID).filter { pointIDs.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let horizons = journal.horizons.filter { $0.projectID == selection.projectID }.sorted { $0.id.uuidString < $1.id.uuidString }
        let horizonIDs = Set(horizons.map(\.id))
        let excavations = journal.excavations.filter { $0.projectID == selection.projectID }.sorted { $0.id.uuidString < $1.id.uuidString }
        let plans = journal.plans.filter { horizonIDs.contains($0.horizonID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        func text(_ value: String?) -> Cell { value.map(Cell.text) ?? .empty }
        func encoded<T: Encodable>(_ value: T?) throws -> Cell { try value.map { .text(try json($0)) } ?? .empty }
        let bounds = try selection.bounds()
        let scope: [String: String?] = ["project_id": selection.projectID.uuidString,
            "horizon_id": selection.horizonID?.uuidString, "excavation_id": selection.excavationID?.uuidString,
            "start_inclusive_reference_seconds": String(bounds.start.timeIntervalSinceReferenceDate),
            "end_exclusive_reference_seconds": String(bounds.end.timeIntervalSinceReferenceDate),
            "timezone": selection.timeZoneID, "calendar": "gregorian", "policy": "effective_observed_at"]
        var metadata = Table(name: "Формат", columns: ["key", "value"])
        for (key, value) in [
            ("format", version), ("mapping_schema", String(MappingJournal.currentSchemaVersion)),
            ("workbook_id", id.uuidString), ("exported_at_utc", MappingCSVExport.iso(now)),
            ("exported_at_reference_seconds", String(now.timeIntervalSinceReferenceDate)),
            ("fingerprint_algorithm", fingerprintVersion), ("selection_json", try json(scope)),
            ("workflow", "B2a: только экспорт. Импорт появится в B2b. Сначала сохраните резервную копию ZIP."),
            ("editing", "Редактируйте points, joint_sets, tectonic_structures и входы assessments как предложения. source_records и базовые UUID/версии/отпечатки не редактировать."),
            ("new_records", "Будущий B2b: record_action=new, уникальный client_record_id (UUID), point_id/original_id/revision_id/version/base_fingerprint пустые. Родительские UUID обязательны."),
            ("precision", "Все значения — текст. Десятичная точка; пусто = null, не 0. *_reference_seconds — точное время от 2001-01-01 UTC. Не преобразовывайте ячейки в числа/даты."),
            ("evidence", "source_records: полный сохранённый JSON выбранных записей и истории, UTF-8 части по порядку chunk_index. Изменять запрещено. Это не резервная копия: нет байтов фото/DXF и независимого журнала."),
            ("units", "XY: xy_units/crs/axes; Z, chainage, spacing, persistence, thickness: м; aperture: мм; orientation: градусы. Север не преобразован."),
            ("limitations", "Нет недоступных исходных метаданных, точности времени сверх Date, автоматической подземной позиции и пересчёта рейтингов. Сохранённые личные строки/диагностика могут присутствовать.")
        ] { metadata.rows.append([.text(key), .text(value)]) }
        let guide = Table(name: "Колонки", columns: ["sheet", "columns", "description_ru", "policy"], rows: [
            ["points", "picket / chainage_m / chainage_origin_direction", "Пикет / метры от начала / начало и направление отсчёта; текст и число должны согласоваться", "Предложение исправления"],
            ["points", "observed_at_utc / observed_at_reference_seconds / observed_zone / observed_offset_seconds", "Полевая дата UTC / точные секунды от 2001-01-01 / часовой пояс / исходное смещение в секундах", "Предложение; точные секунды обязательны"],
            ["points", "x / y / z_m / xy_units / crs / axes / coordinate_source / coordinate_provenance / z_origin", "Координаты и их происхождение; неизвестное оставить пустым. Z — метры. Подземный GPS не предполагается", "Только явные ручные предложения; плановые источники сохранить"],
            ["points", "interval_start_text / interval_start_m / interval_end_text / interval_end_m / position", "Интервал и место: roof, leftWall, rightWall, face, other", "Предложение исправления"],
            ["points", "notes / rock_json", "Примечание / сохранённая литология", "Предложение исправления"],
            ["points", "point_id / original_id / revision_id / version / base_fingerprint", "UUID наблюдения / оригинала / актуальной версии, номер и отпечаток базы", "Не изменять"],
            ["points", "record_action / client_record_id", "existing — существующая запись; new — новая, с уникальным клиентским UUID", "Новая запись: базовые идентификаторы и отпечаток пустые"],
            ["points", "correction_reason / correction_author", "Причина исправления / автор", "Причина обязательна для исправления"],
            ["joint_sets", "original_direction_text / original_dip_text / north / representative_json", "Представительная ориентация J1–J5: исходный текст азимута и падения, север, условная сторона", "Предложение интерпретации; не исходный замер"],
            ["joint_sets", "spacing_m / persistence_m / aperture_mm / roughness / infill / notes", "Расстояние (м) / протяжённость (м) / раскрытие (мм) / шероховатость / заполнитель / примечание", "Предложение; сохранять происхождение spacing_provenance_json"],
            ["tectonic_structures", "type / original_direction_text / original_dip_text / thickness_m / position / description", "Тип / исходная ориентация / мощность (м) / положение / описание структуры", "Предложение; неполные ориентации допустимы"],
            ["assessments", "kind / method / input_json", "Система оценки / версия методики / полный сохранённый ввод Q, RMR89 или GSI", "Только предложения входов; результаты и метод не менять"],
            ["measurements / interpretation_evidence / source_records", "Все столбцы", "Исходные измерения, связи доказательств, полные записи и история", "Не изменять"],
            ["projects / horizons / excavations / photos / photo_attachments / photo_point_contexts", "Все столбцы", "Контекст, справочники и фотографии; файлы оригиналов не включены", "Не изменять"]
        ].map { $0.map(Cell.text) })
        var tables = [metadata, guide]
        tables.append(Table(name: "projects", columns: ["project_id", "name", "lithologies_json"], rows: try journal.projects.filter { $0.id == selection.projectID }.map {
            [.text($0.id.uuidString), .text($0.name), try encoded($0.lithologies)]
        }))
        tables.append(Table(name: "horizons", columns: ["horizon_id", "project_id", "name", "elevation_m", "elevation_datum"], rows: horizons.map {
            [.text($0.id.uuidString), .text($0.projectID.uuidString), .text($0.name), text($0.elevationMeters.map { String($0) }), .text($0.elevationDatum)]
        }))
        tables.append(Table(name: "excavations", columns: ["excavation_id", "project_id", "name"], rows: excavations.map {
            [.text($0.id.uuidString), .text($0.projectID.uuidString), .text($0.name)]
        }))
        tables.append(Table(name: "excavation_horizons", columns: ["excavation_id", "horizon_id"], rows: excavations.flatMap { e in
            e.horizonIDs.sorted { $0.uuidString < $1.uuidString }.map { [.text(e.id.uuidString), .text($0.uuidString)] }
        }))
        var pointRows: [[Cell]] = []
        let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        for row in pointsTable.rows {
            guard case .text(let value) = row[0], let pointID = UUID(uuidString: value), let p = byID[pointID] else { throw StorageError.invalidRecord }
            pointRows.append(row + [.text("existing"), .empty, .text(p.id.uuidString),
                .text(try fingerprint(p.id, in: committed)), try encoded(p.picketConvention), try encoded(p.rock),
                try encoded(p.measurementIDs), .text(String(p.updatedAt.timeIntervalSinceReferenceDate)),
                .text(p.coordinates == nil ? "false" : "true"), .text(p.geology == nil ? "false" : "true"), .empty, .empty])
        }
        tables.append(Table(name: "points", columns: pointsTable.columns + ["record_action", "client_record_id", "original_id", "base_fingerprint", "picket_convention_json", "rock_json", "measurement_ids_json", "updated_at_reference_seconds", "has_coordinates", "has_geology", "correction_reason", "correction_author"], rows: pointRows))
        let contextNames = Set(["projects", "horizons", "excavations", "excavation_horizons", "points", "plans"])
        for table in report.tables where !contextNames.contains(table.name) {
            var output = table
            if table.name == "joint_sets" {
                let sets = Dictionary(uniqueKeysWithValues: points.flatMap { $0.geology?.jointSets ?? [] }.map { ($0.id.uuidString, $0) })
                let rows = try table.rows.map { row in
                    guard case .text(let id) = row[0], let set = sets[id] else { throw StorageError.invalidRecord }
                    return row + [try encoded(set.representative), try encoded(set.spacingProvenance)]
                }
                output = Table(name: table.name, columns: table.columns + ["representative_json", "spacing_provenance_json"], rows: rows)
            }
            tables.append(output)
        }
        // Chunk complete typed records instead of silently dropping fields absent from reporting
        // projections or exceeding Excel's 32767 UTF-16-unit cell limit.
        var records = Table(name: "source_records", columns: ["kind", "record_id", "point_id", "version", "chunk_index", "chunk_count", "sha256", "json_chunk"])
        func record<T: Encodable>(_ kind: String, _ recordID: UUID, point: UUID? = nil, version: Int = 1, _ value: T) throws {
            try Task.checkCancellation()
            let bytes = Data(try json(value).utf8)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            // Split Unicode scalars, never surrogate pairs; chunk size <= 16000 UTF-16 units.
            var chunks: [String] = [], chunk = "", count = 0
            for scalar in String(decoding: bytes, as: UTF8.self).unicodeScalars {
                let length = scalar.value > 0xFFFF ? 2 : 1
                if count + length > 16000 { chunks.append(chunk); chunk = ""; count = 0 }
                chunk.unicodeScalars.append(scalar); count += length
            }
            if !chunk.isEmpty { chunks.append(chunk) }
            for (index, chunk) in chunks.enumerated() {
                records.rows.append([.text(kind), .text(recordID.uuidString), text(point?.uuidString), .text(String(version)),
                    .text(String(index)), .text(String(chunks.count)), .text(hash), .text(chunk)])
            }
        }
        for p in journal.projects.filter({ $0.id == selection.projectID }) { try record("project", p.id, p) }
        for h in horizons { try record("horizon", h.id, h) }
        for e in excavations { try record("excavation", e.id, ExcavationRecord(e)) }
        for plan in plans { try record("plan", plan.id, plan) }
        for p in points {
            guard let original = journal.observations.first(where: { $0.id == p.id }) else { throw StorageError.invalidRecord }
            try record("original", p.id, point: p.id, original)
            for r in journal.history(for: p.id) { try record("revision", r.id, point: p.id, version: r.version, r) }
            for m in committed.measurements(for: original) { try record("measurement", m.id, point: p.id, m) }
        }
        let photos = journal.photos.filter { pointIDs.contains($0.context.pointID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        let photoIDs = Set(photos.map(\.id)), attachmentIDs = Set(photos.map(\.attachmentID))
        for p in photos { try record("photo", p.id, point: p.context.pointID, p) }
        for a in journal.photoAttachments.filter({ attachmentIDs.contains($0.id) }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) { try record("photo_attachment", a.id, a) }
        for r in journal.photoRevisions.filter({ photoIDs.contains($0.photoID) }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) { try record("photo_revision", r.id, version: r.version, r) }
        tables.append(records)
        // All authoritative numbers and dates stay text, including values below Excel precision.
        tables = try tables.map { table in
            Table(name: table.name, columns: table.columns, rows: try table.rows.map { row in try row.map { cell in
                switch cell {
                case .number(let n):
                    guard let n else { return .empty }
                    guard n.isFinite else { throw StorageError.invalidRecord }; return .text(String(n))
                case .integer(let n): return text(n.map(String.init))
                case .timestamp(let d): return text(d.map(MappingCSVExport.iso))
                default: return cell
                }
            } })
        }
        return Self(id: id, snapshotAt: now, tables: tables)
    }

    func write(parent: URL = FileManager.default.temporaryDirectory) throws -> MappingExportFiles {
        try Task.checkCancellation()
        let directory = parent.appendingPathComponent("FieldForge-Exchange-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let url = directory.appendingPathComponent("FieldForge Exchange.xlsx")
            try MappingXLSXExport.writeExchange(tables, to: url, id: id, at: snapshotAt)
            try Task.checkCancellation()
            return MappingExportFiles(directory: directory, urls: [url])
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
