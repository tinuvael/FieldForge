import Foundation

/// Hidden worksheet identity. Bindings reference archived journal snapshots.
/// Row numbers provide hints for review when the original anchor is missing.
struct RegulatoryDataManifest: Codable, Sendable {
    static let sheetName = "_FieldForge"
    private static let column = "FieldForge-Regulatory-Data/2"
    struct Binding: Codable, Sendable {
        let signature: String
        var excavation: String? = nil
        var picket: String? = nil
        let firstRow: Int
        let rowCount: Int
        let target: MappingImportTarget
        let baseline: MappingImportBaseline
        let graphFingerprint: String
    }

    struct SourceBinding: Codable, Sendable {
        let sourceObservationID: UUID
        let projectID: UUID
        let dataset: String
        let sourceID: String
        let row: Int
        let frame: RegulatorySourceImport.Frame
        let destination: MappingContext
        let explicitlyAssigned: Bool
        var revision: Int? = nil
        var fingerprint: String? = nil
    }

    let workbookID: UUID
    let exportedAt: Date
    let bindings: [Binding]
    var sourceBindings: [SourceBinding]? = nil

    init(export: MappingCSVExport, committed: MappingCommittedSnapshot) throws {
        guard let report = export.enterpriseReport else { throw StorageError.invalidRecord }
        workbookID = export.id
        exportedAt = export.snapshotAt
        var bindings: [Binding] = []
        var offset = 0
        for id in report.observationIDs {
            try Task.checkCancellation()
            guard let point = committed.observation(id: id), report.table.rows.indices.contains(offset) else {
                throw StorageError.invalidRecord
            }
            let target = MappingImportTarget(point)
            let row = RegulatoryDataWorkbook.values(report.table.rows[offset])
            let count = max(1, point.geology?.tectonicStructures.count ?? 0)
            bindings.append(Binding(signature: try RegulatoryDataWorkbook.legacySignature(row),
                excavation: row[0], picket: row[1], firstRow: offset + 5,
                rowCount: count, target: target,
                baseline: try .capture(target: target, in: committed),
                graphFingerprint: try MappingExchangeExport.fingerprint(id, in: committed)))
            offset += count
        }
        // Source-backed rows follow the mapped field rows and intentionally have
        // no native MappingObservation baseline; their stable source identity is
        // preserved in Data!A and the journal's source-history table.
        guard offset <= report.table.rows.count else { throw StorageError.invalidRecord }
        sourceBindings = report.sourceRows.map { row in
            SourceBinding(sourceObservationID: row.id, projectID: row.key.projectID, dataset: row.key.dataset,
                sourceID: row.key.sourceID, row: row.firstRow, frame: row.frame,
                destination: row.destination, explicitlyAssigned: row.explicitlyAssigned,
                revision: row.revision, fingerprint: row.fingerprint)
        }
        self.bindings = bindings
    }

    private func validate(documentID: UUID?, rowLimit: Int) throws {
        let error = ExchangeImportError("Сведения сопоставления Data недействительны или относятся к другой книге.")
        guard exportedAt.timeIntervalSinceReferenceDate.isFinite,
              documentID == nil || documentID == workbookID,
              Set(bindings.map(\.target.observationID)).count == bindings.count else { throw error }
        var next = 5
        for binding in bindings {
            guard binding.firstRow == next, binding.rowCount > 0, binding.rowCount <= rowLimit + 5 - next else { throw error }
            next += binding.rowCount
        }
        var sourceIDs = Set(bindings.map(\.target.observationID))
        var sourceRows = Set<Int>(), sourceKeys = Set<RegulatorySourceObservation.Key>()
        for source in sourceBindings ?? [] {
            let key = RegulatorySourceObservation.Key(projectID: source.projectID, dataset: source.dataset, sourceID: source.sourceID)
            guard sourceIDs.insert(source.sourceObservationID).inserted, sourceRows.insert(source.row).inserted,
                  sourceKeys.insert(key).inserted, source.row == next, source.row <= rowLimit + 4,
                  !source.dataset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.dataset.utf8.count <= 256, !source.sourceID.isEmpty, source.sourceID.utf8.count <= 256,
                  source.frame.valid, source.destination.projectID == source.projectID,
                  (source.revision == nil) == (source.fingerprint == nil),
                  source.revision.map({ $0 >= 0 }) ?? true,
                  source.fingerprint.map({ $0.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil }) ?? true else { throw error }
            next += 1
        }
    }

    private init(workbookID: UUID, exportedAt: Date, bindings: [Binding], sourceBindings: [SourceBinding]?) {
        self.workbookID = workbookID; self.exportedAt = exportedAt; self.bindings = bindings; self.sourceBindings = sourceBindings
    }

    private struct Header: Codable {
        let workbookID: UUID
        let exportedAt: Date
    }

    func sheet() throws -> MappingCSVExport.Table {
        let header = try MappingExchangeExport.json(Header(workbookID: workbookID, exportedAt: exportedAt))
        var table = MappingCSVExport.Table(name: Self.sheetName, columns: [Self.column], rows: [[.text(header)]])
        for binding in bindings { table.rows.append([.text(try MappingExchangeExport.json(binding))]) }
        for binding in sourceBindings ?? [] { table.rows.append([.text(try MappingExchangeExport.json(binding))]) }
        return table
    }

    static func read(sheet: ExchangeWorkbook.Sheet, documentID: UUID?, rowLimit: Int) throws -> Self {
        guard sheet.columns == [column], let header = sheet.rows.first?[column],
              sheet.rowNumbers == Array(2..<(sheet.rows.count + 2)) else {
            throw ExchangeImportError("Повреждён скрытый лист идентификаторов FieldForge.")
        }
        let info = try ExchangeBaseline.decode(Header.self, header)
        var bindings: [Binding] = [], sourceBindings: [SourceBinding] = []
        for row in sheet.rows.dropFirst() {
            let raw = row[column] ?? ""
            let native = try? ExchangeBaseline.decode(Binding.self, raw)
            let source = try? ExchangeBaseline.decode(SourceBinding.self, raw)
            switch (native, source) {
            case (let binding?, nil) where sourceBindings.isEmpty: bindings.append(binding)
            case (nil, let binding?): sourceBindings.append(binding)
            default: throw ExchangeImportError("Скрытый лист содержит неизвестную или неоднозначную запись идентификатора.")
            }
        }
        let value = Self(workbookID: info.workbookID, exportedAt: info.exportedAt, bindings: bindings,
                         sourceBindings: sourceBindings.isEmpty ? nil : sourceBindings)
        try value.validate(documentID: documentID, rowLimit: rowLimit)
        guard bindings.allSatisfy({ $0.excavation != nil && $0.picket != nil }) else {
            throw ExchangeImportError("В скрытом листе отсутствует контекст исходных строк.")
        }
        return value
    }

}
