import Foundation
import CryptoKit

/// Fully reconstructed, validated export graph, never a persistence store or replacement journal.
struct ExchangeBaseline: Sendable {
    typealias Row = ExchangeWorkbook.Row
    let workbookID: UUID
    let exportedAt: Date
    let selection: MappingExportSelection
    let snapshot: MappingCommittedSnapshot
    let tables: [String: ExchangeWorkbook.Sheet]
    let metadata: [String: String]

    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func rows(_ table: MappingCSVExport.Table) -> [Row] {
        table.rows.map { row in Dictionary(uniqueKeysWithValues: zip(table.columns, row.map { if case .text(let t) = $0 { return t }; return "" })) }
    }
    init(_ workbook: ExchangeWorkbook) throws {
        func bad(_ s: String) -> ExchangeImportError { ExchangeImportError(s) }
        guard let format = workbook.sheets["Формат"], Set(format.columns) == Set(["key", "value"]), let records = workbook.sheets["source_records"],
              Set(records.columns) == Set(["kind", "record_id", "point_id", "version", "chunk_index", "chunk_count", "sha256", "json_chunk"]) else { throw bad("Отсутствует формат или исходные записи.") }
        var meta: [String: String] = [:]
        for row in format.rows {
            let key = row["key"] ?? ""
            guard !key.isEmpty, meta[key] == nil else { throw bad("Повтор метаданных книги.") }; meta[key] = row["value"] ?? ""
        }
        guard meta["format"] == MappingExchangeExport.version, meta["mapping_schema"] == "8",
              meta["fingerprint_algorithm"] == MappingExchangeExport.fingerprintVersion,
              let id = meta["workbook_id"].flatMap(UUID.init(uuidString:)),
              let seconds = meta["exported_at_reference_seconds"].flatMap(Double.init), seconds.isFinite,
              seconds >= -63_113_904_000, seconds <= 252_423_993_599,
              meta["exported_at_utc"] == MappingCSVExport.iso(Date(timeIntervalSinceReferenceDate: seconds)),
              let scopeJSON = meta["selection_json"] else { throw bad("Неподдерживаемые или повреждённые метаданные обмена.") }
        struct Scope: Decodable {
            let project_id: UUID; let horizon_id: UUID?; let excavation_id: UUID?
            let start_inclusive_reference_seconds: String; let end_exclusive_reference_seconds: String
            let timezone: String; let calendar: String; let policy: String
        }
        let scope = try Self.decode(Scope.self, scopeJSON)
        guard scope.calendar == "gregorian", scope.policy == "effective_observed_at",
              let start = Double(scope.start_inclusive_reference_seconds), let end = Double(scope.end_exclusive_reference_seconds),
              start.isFinite, end.isFinite, start < end, start >= -63_113_904_000, end <= 252_423_993_600 else { throw bad("Некорректный отбор книги.") }
        let selection = MappingExportSelection(projectID: scope.project_id, horizonID: scope.horizon_id, excavationID: scope.excavation_id,
            firstDay: Date(timeIntervalSinceReferenceDate: start), lastDay: Date(timeIntervalSinceReferenceDate: end - 1), timeZoneID: scope.timezone)
        let bounds = try selection.bounds()
        guard bounds.start.timeIntervalSinceReferenceDate == start, bounds.end.timeIntervalSinceReferenceDate == end else { throw bad("Границы отбора не совпадают с календарными датами.") }
        var journal = MappingJournal()
        let groups = Dictionary(grouping: records.rows, by: { ($0["kind"] ?? "") + "/" + ($0["record_id"] ?? "") })
        for key in groups.keys.sorted() {
            try Task.checkCancellation()
            let chunks = groups[key]!
            guard let first = chunks.first, let recordID = first["record_id"].flatMap(UUID.init(uuidString:)),
                  let version = first["version"].flatMap(Int.init), version >= 1,
                  let count = first["chunk_count"].flatMap(Int.init), count > 0, count <= 10_000,
                  let hash = first["sha256"], hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { throw bad("Некорректная идентичность source_records.") }
            var pieces: [Int: String] = [:]
            for row in chunks {
                guard row["record_id"] == first["record_id"], row["point_id"] == first["point_id"], row["version"] == first["version"],
                      row["sha256"] == hash, row["chunk_count"] == first["chunk_count"],
                      let index = row["chunk_index"].flatMap(Int.init), (0..<count).contains(index), let text = row["json_chunk"], text.utf16.count <= 16_000 else { throw bad("Повреждённые части исходной записи.") }
                if let old = pieces[index], old != text { throw bad("Противоречащие части исходной записи.") }; pieces[index] = text
            }
            guard pieces.count == count else { throw bad("Отсутствует часть исходной записи.") }
            let json = (0..<count).map { pieces[$0]! }.joined()
            guard Self.hash(Data(json.utf8)) == hash else { throw bad("SHA-256 исходной записи не совпадает. Это проверка целостности, не авторства.") }
            func record<T: Decodable & Identifiable>(_ t: T.Type) throws -> T where T.ID == UUID {
                let value = try Self.decode(t, json)
                guard value.id == recordID else { throw bad("UUID JSON и source_records расходятся.") }; return value
            }
            switch first["kind"] {
            case "project": journal.projects.append(try record(MappingProject.self))
            case "horizon": journal.horizons.append(try record(MappingHorizon.self))
            case "excavation": journal.excavations.append(try record(MappingExcavation.self))
            case "plan": journal.plans.append(try record(MappingPlanReference.self))
            case "original": journal.observations.append(try record(MappingObservation.self))
            case "revision": journal.revisions.append(try record(MappingObservationRevision.self))
            case "measurement": journal.measurements.append(try record(Measurement.self))
            case "photo": journal.photos.append(try record(PhotoObservation.self))
            case "photo_attachment": journal.photoAttachments.append(try record(PhotoAttachment.self))
            case "photo_revision": journal.photoRevisions.append(try record(PhotoMetadataRevision.self))
            default: throw bad("Неизвестный вид исходной записи.")
            }
        }
        journal.revisions.sort { $0.version == $1.version ? $0.id.uuidString < $1.id.uuidString : $0.version < $1.version }
        journal.photoRevisions.sort { $0.version == $1.version ? $0.id.uuidString < $1.id.uuidString : $0.version < $1.version }
        try journal.validate()
        guard journal.projects.count == 1, journal.projects[0].id == selection.projectID,
              journal.horizons.allSatisfy({ $0.projectID == selection.projectID }), journal.excavations.allSatisfy({ $0.projectID == selection.projectID }) else { throw bad("Книга должна содержать один согласованный проект.") }
        let snapshot = MappingCommittedSnapshot(journal), date = Date(timeIntervalSinceReferenceDate: seconds)
        let projected = try MappingExchangeExport.prepare(committed: snapshot, selection: selection, now: date, id: id)
        let tables = Dictionary(uniqueKeysWithValues: projected.tables.map { ($0.name, ExchangeWorkbook.Sheet(columns: $0.columns, rows: Self.rows($0))) })
        guard Set(workbook.sheets.keys) == Set(tables.keys) else { throw bad("Отсутствуют обязательные листы или добавлены неизвестные листы.") }
        for (name, sheet) in tables {
            guard Set(workbook.sheets[name]!.columns) == Set(sheet.columns) else { throw bad("\(name): неверные обязательные колонки.") }
        }
        // Reprojection verifies kind/point/version metadata, canonical raw JSON, full graph
        // closure, complete chunks and hashes. Codable cannot silently discard unknown keys.
        func tokens(_ rows: [Row]) throws -> Set<String> { Set(try rows.map { try MappingExchangeExport.json($0) }) }
        guard try tokens(records.rows) == tokens(tables["source_records"]!.rows) else { throw bad("Исходный граф неполон или его JSON/метаданные не соответствуют контракту v1.") }
        self.workbookID = id; exportedAt = date; self.selection = selection; self.snapshot = snapshot; self.tables = tables; metadata = meta
    }
    /// Bound JSON nesting before Foundation decoding. Escaped braces never affect depth.
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ExchangeJSON.validate(json)
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
