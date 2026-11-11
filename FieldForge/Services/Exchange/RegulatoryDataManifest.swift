import Foundation

/// Optional companion file, selected separately in Files. Its bindings are checked
/// against local history and the full read-only report projection before use.
struct RegulatoryDataManifest: Codable, Sendable {
    struct Binding: Codable, Sendable {
        let signature: String
        let firstRow: Int
        let rowCount: Int
        let target: MappingImportTarget
        let baseline: MappingImportBaseline
        let graphFingerprint: String
    }

    private let format: String
    let workbookID: UUID
    let exportedAt: Date
    let bindings: [Binding]

    init(export: MappingCSVExport, committed: MappingCommittedSnapshot) throws {
        guard let report = export.enterpriseReport else { throw StorageError.invalidRecord }
        format = "FieldForge-Regulatory-Data/1"
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
            bindings.append(Binding(signature: try RegulatoryDataWorkbook.signature(row), firstRow: offset + 5,
                rowCount: count, target: target,
                baseline: try .capture(target: target, in: committed),
                graphFingerprint: try MappingExchangeExport.fingerprint(id, in: committed)))
            offset += count
        }
        guard offset == report.table.rows.count else { throw StorageError.invalidRecord }
        self.bindings = bindings
    }

    static func read(_ bytes: Data, documentID: UUID?) throws -> Self {
        let error = ExchangeImportError("Файл сопоставления Data недействителен или относится к другой книге.")
        guard let value = try? JSONDecoder().decode(Self.self, from: bytes),
              value.format == "FieldForge-Regulatory-Data/1",
              value.exportedAt.timeIntervalSinceReferenceDate.isFinite,
              documentID == nil || documentID == value.workbookID,
              Set(value.bindings.map(\.target.observationID)).count == value.bindings.count else { throw error }
        var next = 5
        for binding in value.bindings {
            guard binding.firstRow == next, binding.rowCount > 0, binding.rowCount <= 1_048_577 - next else { throw error }
            next += binding.rowCount
        }
        return value
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
