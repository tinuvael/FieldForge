import Foundation

/// Typed cells from the operational Data sheet. The export projection supplies
/// the header contract and the exact baseline values for comparison.
enum RegulatoryDataWorkbook {
    static let columns = EnterpriseGeotechnicalWorkbook.columns
    static let editable = Array(1...13) + Array(15...28)
    static let protected = [0, 14, 29]
    static let common = columns.indices.filter { !(18...20).contains($0) }
    static let fault = 18...20

    struct Row: Sendable {
        let number: Int
        let values: [String]
        let issues: [String]
        var numericRock = false

        func location(_ column: Int) -> String { "Data!\(RegulatoryDataWorkbook.address(column, number))" }
    }

    // These labels distinguish source observation IDs from the writable A:AD report.
    private static let productionMarkers = [
        "AI3": "№ точки наблюдения", "AJ3": "Примечание", "AE4": "Q'", "AH4": "RMR76",
        "BI1": "Ошибки в пополнении БД по картированию выработок", "CP3": "Проверка угла и азимута 4 системы"
    ]

    static let productionMerges = Set(EnterpriseGeotechnicalWorkbook.merges.filter { $0 != "A1:AD1" } + [
        "A1:AJ1", "AD2:AH2", "BI1:CP1", "BV2:CD2", "BJ2:BL2", "BM2:BO2", "BP2:BT2"
    ])

    static func matchesProductionLayout(_ rows: [Int: [Int: ExchangeWorkbook.DataCell]], extraColumns: Set<Int>) -> Bool {
        let ranges = [("AE1", "BB1"), ("BI1", "BT1"), ("BV1", "CD1"), ("CF1", "CP1")]
        let populated = ranges.compactMap { start, end -> ClosedRange<Int>? in
            guard let first = ExchangeWorkbook.address(start)?.0, let last = ExchangeWorkbook.address(end)?.0 else { return nil }
            return first...last
        }
        return extraColumns.allSatisfy { column in populated.contains { $0.contains(column) } } && productionMarkers.allSatisfy { marker in
            guard let (column, row) = ExchangeWorkbook.address(marker.key) else { return false }
            return rows[row]?[column] == .text(marker.value)
        }
    }

    struct Read: Sendable {
        let productionLayout: Bool
        let worksheetRowCount: Int
        let documentID: UUID?
        let rows: [Row]
        let manifest: RegulatoryDataManifest?

        init(bytes: Data, limits: ExchangeLimits) throws {
            let archive = try ExchangeArchive(data: bytes, limits: limits, regulatory: true)
            let workbook = try ExchangeWorkbook(regulatoryArchive: archive, limits: limits)
            let productionLayout = workbook.productionLayout
            self.productionLayout = productionLayout
            worksheetRowCount = workbook.dataSheetRowCount
            documentID = workbook.documentID
            let parsedManifest = try workbook.sheets[RegulatoryDataManifest.sheetName].map {
                try RegulatoryDataManifest.read(sheet: $0, documentID: workbook.documentID, rowLimit: limits.rows)
            }
            manifest = parsedManifest
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
                if !productionLayout, data[number]?.keys.contains(where: { $0 >= columns.count }) == true {
                    headerIssues.append("строка \(number): данные за пределами A:AD")
                }
            }
            guard headerIssues.isEmpty else {
                throw ExchangeImportError("Data!A1:AD4: отсутствующие или несовместимые заголовки регламента. " + headerIssues.joined(separator: "; "))
            }
            rows = try data.keys.filter { $0 > 4 }.sorted().compactMap { number -> Row? in
                try Task.checkCancellation()
                let cells = data[number] ?? [:]
                let sourceBoundRow = parsedManifest?.sourceBindings?.contains { $0.row == number } == true
                // Empty and all-dash report placeholders do not represent observations.
                if cells.allSatisfy({ $0.key < columns.count && $0.value == .text("-") }) { return nil }
                var issues: [String] = []
                var numericRock = false
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
                    case .text(let raw) where (productionLayout || sourceBoundRow) && (2...4).contains(column),
                         .number(let raw) where (productionLayout || sourceBoundRow) && (2...4).contains(column),
                         .number(let raw) where productionLayout && (!isText || column == 5):
                        // Retain Excel's exact decimal spelling as source evidence.
                        // Spatial comparisons use the finite numeric interpretation.
                        if RegulatoryDataWorkbook.sourceNumber(raw) != nil {
                            values[column] = raw
                            numericRock = numericRock || column == 5
                        } else {
                            issues.append("\(location): требуется конечное десятичное число.")
                        }
                    case .number(let raw) where !isText || column == 5:
                        do {
                            guard let value = try ExchangeObservationProposal.number(raw, field: location, required: true),
                                  value == 0 || abs(value) >= Double.leastNormalMagnitude else {
                                throw ExchangeImportError("Значение вне числового диапазона Excel.")
                            }
                            values[column] = decimal(value)
                            if column == 5 { numericRock = true }
                        } catch {
                            issues.append("\(location): невозможно прочитать число без потери точности.")
                        }
                    case .invalid(let reason) where productionLayout && column == 29 && reason == ExchangeWorkbook.unsupportedFormula:
                        break
                    case .invalid(let reason): issues.append("\(location): \(reason)")
                    default:
                        issues.append("\(location): \(isText ? "требуется текстовая ячейка, включая ведущие нули" : "требуется числовая ячейка Excel").")
                    }
                }
                return Row(number: number, values: values, issues: issues, numericRock: numericRock)
            }
        }
    }

    static func sourceNumber(_ raw: String) -> Double? {
        guard raw.utf8.count <= 128,
              raw.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Double(raw), number.isFinite else { return nil }
        if number == 0 {
            let mantissa = raw.prefix { $0 != "e" && $0 != "E" }
            guard !mantissa.utf8.contains(where: { (49...57).contains($0) }) else { return nil }
        }
        return number
    }

    static func address(_ column: Int, _ row: Int) -> String { MappingXLSXExport.column(column + 1) + String(row) }

    static func values(_ row: [MappingCSVExport.Cell]) -> [String] {
        row.map {
            switch $0 {
            case .text(let value): value
            case .rawNumber(let value): value
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

    static func identity(_ rows: [Row]) throws -> String {
        try MappingImportLedger.fingerprint(rows.map { $0.values + [$0.numericRock ? "numeric-rock" : "text-rock"] }.sorted { $0.lexicographicallyPrecedes($1) })
    }

    static func legacySignature(_ row: [String]) throws -> String {
        let oldProtected = columns.indices.filter { ![5, 6, 8].contains($0) && !fault.contains($0) }
        return try MappingImportLedger.fingerprint(oldProtected.map { row[$0] })
    }
}
