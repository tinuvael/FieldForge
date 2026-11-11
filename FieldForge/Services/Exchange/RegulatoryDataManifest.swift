import Foundation

/// Optional companion file, selected separately in Files. Its bindings are checked
/// against local history and the full read-only report projection before use.
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

    let workbookID: UUID
    let exportedAt: Date
    let bindings: [Binding]

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
        guard offset == report.table.rows.count else { throw StorageError.invalidRecord }
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
    }

    private init(workbookID: UUID, exportedAt: Date, bindings: [Binding]) {
        self.workbookID = workbookID; self.exportedAt = exportedAt; self.bindings = bindings
    }

    private struct Header: Codable {
        let workbookID: UUID
        let exportedAt: Date
    }

    func sheet() throws -> MappingCSVExport.Table {
        let header = try MappingExchangeExport.json(Header(workbookID: workbookID, exportedAt: exportedAt))
        var table = MappingCSVExport.Table(name: Self.sheetName, columns: [Self.column], rows: [[.text(header)]])
        for binding in bindings { table.rows.append([.text(try MappingExchangeExport.json(binding))]) }
        return table
    }

    static func read(sheet: ExchangeWorkbook.Sheet, documentID: UUID?, rowLimit: Int) throws -> Self {
        guard sheet.columns == [column], let header = sheet.rows.first?[column],
              sheet.rowNumbers == Array(2..<(sheet.rows.count + 2)) else {
            throw ExchangeImportError("Повреждён скрытый лист идентификаторов FieldForge.")
        }
        let info = try ExchangeBaseline.decode(Header.self, header)
        let bindings = try sheet.rows.dropFirst().map { row in
            try ExchangeBaseline.decode(Binding.self, row[column] ?? "")
        }
        let value = Self(workbookID: info.workbookID, exportedAt: info.exportedAt, bindings: bindings)
        try value.validate(documentID: documentID, rowLimit: rowLimit)
        guard bindings.allSatisfy({ $0.excavation != nil && $0.picket != nil }) else {
            throw ExchangeImportError("В скрытом листе отсутствует контекст исходных строк.")
        }
        return value
    }

}
