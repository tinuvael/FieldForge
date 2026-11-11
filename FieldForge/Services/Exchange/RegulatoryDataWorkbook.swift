import Foundation

/// Typed cells from the established single-sheet report. The export projection
/// supplies the headers and read-only baseline values for comparison.
enum RegulatoryDataWorkbook {
    static let columns = EnterpriseGeotechnicalWorkbook.columns
    static let editable = [5, 6, 8]
    static let protected = columns.indices.filter { !editable.contains($0) }
    static let repeated = protected.filter { !(18...20).contains($0) }

    struct Row: Sendable {
        let number: Int
        let values: [String]
        let issues: [String]

        func location(_ column: Int) -> String { "Data!\(RegulatoryDataWorkbook.address(column, number))" }
    }

    struct Read: Sendable {
        let documentID: UUID?
        let rows: [Row]

        init(bytes: Data, limits: ExchangeLimits) throws {
            let archive = try ExchangeArchive(data: bytes, limits: limits)
            let workbook = try ExchangeWorkbook(parts: archive.parts, limits: limits, regulatory: true)
            documentID = workbook.documentID
            let data = workbook.dataRows
            var headerIssues: [String] = []
            for (offset, header) in EnterpriseGeotechnicalWorkbook.headerRows.enumerated() {
                let number = offset + 1
                for column in columns.indices {
                    let expected = header.indices.contains(column) ? header[column] : ""
                    let cell = data[number]?[column]
                    if cell != (expected.isEmpty ? nil : .text(expected)) {
                        headerIssues.append("\(address(column, number)): \(expected.isEmpty ? "требуется пустая ячейка" : "ожидается «\(expected)»")")
                    }
                }
                if data[number]?.keys.contains(where: { $0 >= columns.count }) == true {
                    headerIssues.append("строка \(number): данные за пределами A:AD")
                }
            }
            guard headerIssues.isEmpty else {
                throw ExchangeImportError("Data: отсутствующие, повторные или переставленные заголовки. " + headerIssues.joined(separator: "; "))
            }
            rows = try data.keys.filter { $0 > 4 }.sorted().compactMap { number in
                try Task.checkCancellation()
                let cells = data[number] ?? [:]
                // Empty and all-dash report placeholders do not represent observations.
                if cells.allSatisfy({ $0.key < columns.count && $0.value == .text("-") }) { return nil }
                var issues: [String] = []
                var values = Array(repeating: "", count: columns.count)
                for (column, cell) in cells.sorted(by: { $0.key < $1.key }) {
                    let location = "Data!\(address(column, number))"
                    guard columns.indices.contains(column) else {
                        issues.append("\(location): данные за пределами A:AD."); continue
                    }
                    let isText = [0, 1, 5].contains(column)
                    switch cell {
                    case .text("-"): break
                    case .text(let value) where isText || editable.contains(column) && value == ExchangeObservationProposal.clear:
                        values[column] = value
                    case .number(let raw) where !isText:
                        do {
                            guard let value = try ExchangeObservationProposal.number(raw, field: location, required: true),
                                  value == 0 || abs(value) >= Double.leastNormalMagnitude else {
                                throw ExchangeImportError("Значение вне числового диапазона Excel.")
                            }
                            values[column] = decimal(value)
                        } catch {
                            issues.append("\(location): невозможно прочитать число без потери точности.")
                        }
                    case .invalid(let reason): issues.append("\(location): \(reason)")
                    default:
                        issues.append("\(location): \(isText ? "требуется текстовая ячейка, включая ведущие нули" : "требуется числовая ячейка Excel").")
                    }
                }
                if values[0].isEmpty || values[1].isEmpty {
                    issues.append("Data!A\(number):B\(number): укажите выработку и пикет для сопоставления.")
                }
                return Row(number: number, values: values, issues: issues)
            }
        }
    }

    static func address(_ column: Int, _ row: Int) -> String { MappingXLSXExport.column(column + 1) + String(row) }

    static func values(_ row: [MappingCSVExport.Cell]) -> [String] {
        row.map {
            switch $0 {
            case .text(let value): value
            case .number(let value): value.map(decimal) ?? ""
            case .integer(let value): value.map(String.init) ?? ""
            case .empty, .timestamp: ""
            }
        }
    }

    private static func decimal(_ value: Double) -> String {
        if value == 0 { return "0" }
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func signature(_ row: [String]) throws -> String {
        try MappingImportLedger.fingerprint(repeated.map { row[$0] })
    }
}
