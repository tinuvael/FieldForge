import Foundation

enum RegulatoryDataImport {
    typealias Preview = MappingExchangePreview
    typealias Record = Preview.Record
    typealias Row = RegulatoryDataWorkbook.Row

    private struct ContextKey: Hashable {
        let excavation: String
        let picket: String
    }

    private struct Group {
        let key: String
        let rows: [Row]
        let binding: RegulatoryDataManifest.Binding?
        let ambiguous: Bool
    }

    static func prepare(bytes: Data, manifestBytes: Data? = nil, matches: [String: UUID] = [:],
                        committed: MappingCommittedSnapshot, limits: ExchangeLimits = .init()) throws -> Preview {
        let workbook = try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)
        let manifest = try manifestBytes.map { try RegulatoryDataManifest.read($0, documentID: workbook.documentID) }
        let documentID = workbook.documentID ?? manifest?.workbookID
        let source = MappingImportSource(kind: .regulatoryData,
            documentID: documentID?.uuidString ?? ExchangeBaseline.hash(bytes), bytes: bytes)
        let groups = try groups(workbook.rows, manifest: manifest)
        let repeatedRows = Dictionary(grouping: workbook.rows.filter { $0.issues.isEmpty }, by: \.values)
        let duplicateNumbers = Set(repeatedRows.values.filter { $0.count > 1 }.flatMap { $0.map(\.number) })
        let candidates = Dictionary(grouping: committed.effectiveObservations) {
            ContextKey(excavation: committed.excavations[$0.excavationID]?.name ?? "", picket: $0.displayPicket)
        }
        let ledger = (committed.journal.importLedger?.entries ?? []).filter {
            $0.operation.source.kind == .regulatoryData && $0.operation.source.documentID == source.documentID
        }
        let receipts = Dictionary(grouping: ledger, by: \.operation.sourceRecordID)
        var records: [Record] = []
        for group in groups {
            let key = group.key
            let rows = group.rows
            try Task.checkCancellation()
            let context = ContextKey(excavation: rows[0].values[0], picket: rows[0].values[1])
            let previous = receipts[key] ?? []
            // A terminal or pending mutation pins the exact source row group on replay.
            let receipt = previous.last(where: { $0.operation.isMutation && $0.operation.source == source })
            let record = try compare(key: key, rows: rows, candidates: candidates[context] ?? [],
                binding: group.binding, ambiguous: group.ambiguous, hasManifest: manifest != nil,
                requiresMatch: manifest == nil || workbook.documentID == nil, duplicate: rows.contains { duplicateNumbers.contains($0.number) }, chosen: matches[key],
                receipt: receipt, reservation: previous.last(where: \.reservesSource), current: committed)
            records.append(record)
        }
        let collisions = Dictionary(grouping: records.compactMap { record in record.target.map { ($0.observationID, record.id) } }, by: { $0.0 })
        let duplicates = Set(collisions.values.filter { $0.count > 1 }.flatMap { $0.map { $0.1 } })
        records = records.map { record in
            guard duplicates.contains(record.id), record.receipt?.outcome != .applied else { return record }
            return Record(id: record.id, classification: .duplicate,
                reason: "Несколько групп строк назначены одному наблюдению. Сверьте строки и сопоставление.",
                changes: record.changes, proposed: nil, location: record.location, label: record.label,
                receipt: record.receipt, candidates: record.candidates, matchedID: record.matchedID)
        }

        var preview = Preview(workbookID: documentID ?? UUID(), generationID: committed.generationID,
            exportedAt: manifest?.exportedAt ?? .distantPast, projectName: "", metadata: [:], records: records,
            proposalDigest: source.fingerprint)
        preview.source = source
        preview.rowsProcessed = workbook.rows.count
        return preview
    }

    private static func groups(_ rows: [Row], manifest: RegulatoryDataManifest?) throws -> [Group] {
        guard let manifest else {
            let grouped = try Dictionary(grouping: rows) { try RegulatoryDataWorkbook.signature($0.values) }
            return grouped.map { Group(key: $0.key, rows: $0.value, binding: nil, ambiguous: false) }
                .sorted { $0.rows[0].number < $1.rows[0].number }
        }
        let counts = Dictionary(grouping: manifest.bindings, by: \.signature).mapValues(\.count)
        var groups: [Group] = []
        var index = 0
        for binding in manifest.bindings {
            try Task.checkCancellation()
            let start = index
            let endRow = binding.firstRow + binding.rowCount
            while index < rows.count, rows[index].number < endRow { index += 1 }
            let present = Array(rows[start..<index])
            let boundRows = present.isEmpty
                ? [Row(number: binding.firstRow, values: Array(repeating: "", count: RegulatoryDataWorkbook.columns.count),
                       issues: ["Отсутствуют исходные строки Data \(binding.firstRow)–\(endRow - 1)."])]
                : present
            let ambiguous = counts[binding.signature, default: 0] > 1
            let key = ambiguous ? "\(binding.signature)/\(binding.firstRow)" : binding.signature
            groups.append(Group(key: key, rows: boundRows, binding: binding, ambiguous: ambiguous))
        }
        for row in rows[index...] {
            groups.append(Group(key: "unbound/\(row.number)", rows: [row], binding: nil, ambiguous: false))
        }
        return groups
    }

    private static func compare(key: String, rows: [Row], candidates: [MappingObservation],
                                binding: RegulatoryDataManifest.Binding?, ambiguous: Bool, hasManifest: Bool,
                                requiresMatch: Bool, duplicate: Bool, chosen: UUID?,
                                receipt: MappingImportLedger.Entry?, reservation: MappingImportLedger.Entry?,
                                current: MappingCommittedSnapshot) throws -> Record {
        let first = rows[0]
        let numbers = rows.map { String($0.number) }.joined(separator: ", ")
        let location = "Data · строки \(numbers)"
        let label = "\(first.values[0]) · \(first.values[1])"
        let boundPoint = binding.flatMap { current.observation(id: $0.target.observationID) }
        let targets = hasManifest ? (boundPoint.map { [$0] } ?? []) : candidates
        let choices = requiresMatch && receipt == nil ? targets.map {
            Preview.MatchCandidate(id: $0.id, label: contextLabel($0, in: current))
        } : []
        let confirmed = choices.first { $0.id == chosen }?.id
        let selected = receipt?.operation.target.observationID ?? (requiresMatch ? confirmed : boundPoint?.id)
        let point = selected.flatMap { current.observation(id: $0) }
        let context = point.map { contextLabel($0, in: current) } ?? label
        func result(_ classification: Preview.Classification, _ reason: String,
                    changes: [Preview.Change] = [], proposed: MappingObservation? = nil,
                    baseline: MappingImportBaseline? = nil, graph: String? = nil) -> Record {
            Record(id: key, classification: classification, reason: reason, changes: changes, proposed: proposed,
                location: location, label: context, previous: point, baseline: baseline, graphFingerprint: graph,
                correctionReason: "Регламент Data A:AD, строки \(numbers.prefix(1200))", receipt: receipt,
                candidates: choices, matchedID: point?.id)
        }
        if let receipt {
            switch receipt.outcome {
            case .applied: return result(.unchanged, "Эти строки уже импортированы.")
            case .rejected: return result(.conflict, "Предыдущее решение об отклонении сохранено.")
            case .skipped: return result(.unchanged, "Эти строки уже проверены.")
            case .pending: break
            }
        }

        var issues = rows.flatMap(\.issues)
        for row in rows {
            if let issue = validateEditable(row) { issues.append(issue) }
        }
        guard issues.isEmpty else { return result(.invalid, issues.joined(separator: "\n")) }
        guard !duplicate else {
            return result(.duplicate, "Повторяющиеся строки. Однозначное сопоставление структур невозможно.")
        }
        guard !ambiguous else {
            return result(.ambiguous, "Файл сопоставления содержит несколько наблюдений с одинаковыми полями. Выгрузите их отдельно.")
        }
        if hasManifest, binding == nil {
            // The companion declares the source revision and target. Changed context
            // cells must never turn into an inferred match to another observation.
            return result(.invalid, "Строка отсутствует в файле сопоставления.")
        }
        guard let point else {
            if !choices.isEmpty { return result(.ambiguous, "Подтвердите наблюдение по проекту, горизонту, дате и UUID.") }
            return result(.invalid, "Наблюдение отсутствует в журнале. Создание точек из Data не поддерживается.")
        }
        let target = MappingImportTarget(point)
        if let reservation, reservation.operation.target != target ||
            (reservation.outcome == .pending && reservation.operation.source != receipt?.operation.source) {
            return result(.conflict, "Эти строки связаны с другим наблюдением или незавершённым импортом.")
        }
        let baseline = try MappingImportBaseline.capture(target: target, in: current)
        let graph = try MappingExchangeExport.fingerprint(point.id, in: current)
        if let expected = binding,
           expected.target != target || expected.baseline != baseline || expected.graphFingerprint != graph {
            return result(.conflict, "Версия или контекст изменились после выгрузки. Версия в файле: \(expected.baseline.version), в журнале: \(baseline.version).")
        }
        if let pending = receipt?.operation, pending.baseline != baseline || pending.graphFingerprint != graph {
            return result(.conflict, "Журнал изменился после подтверждения. Отклоните незавершённый импорт.")
        }

        let projected = try EnterpriseGeotechnicalWorkbook.prepare(points: [point], journal: current.journal).table.rows
            .map(RegulatoryDataWorkbook.values)
        if let binding, binding.signature != (try RegulatoryDataWorkbook.signature(projected[0])) {
            return result(.conflict, "Поля сопоставления исходной версии не совпадают с файлом сопоставления.")
        }
        if let problem = protectedIssues(rows, projected: projected) {
            return result(.unsupported, problem)
        }
        do {
            let proposals = try rows.map { try proposal($0, previous: point, projected: projected[0], current: current) }
            let proposed = proposals[0]
            guard proposals.allSatisfy({ $0 == proposed }) else {
                return result(.invalid, "Data!F:I: повторяющиеся поля наблюдения расходятся в строках разных структур.")
            }
            guard proposed != point else { return result(.unchanged, "Значения совпадают с журналом.") }
            let newRow = try EnterpriseGeotechnicalWorkbook.prepare(points: [proposed], journal: current.journal).table.rows[0]
            let after = RegulatoryDataWorkbook.values(newRow)
            let changes = RegulatoryDataWorkbook.editable.compactMap { column -> Preview.Change? in
                let before = projected[0][column]
                guard before != after[column] else { return nil }
                let field = MappingXLSXExport.column(column + 1) + " · " + RegulatoryDataWorkbook.columns[column]
                return .init(sheet: "Data", record: key, field: field, before: before, after: after[column], row: first.number)
            }
            return result(.correction, "Сохранённые оценки Q, RMR89, GSI и JCond76 остаются без пересчёта.",
                changes: changes, proposed: proposed, baseline: baseline, graph: graph)
        } catch let error as ExchangeImportError {
            return result(.invalid, error.message)
        }
    }

    private static func validateEditable(_ row: Row) -> String? {
        for column in RegulatoryDataWorkbook.editable {
            let value = row.values[column]
            if value.isEmpty || value == ExchangeObservationProposal.clear { continue }
            switch column {
            case 5:
                if (try? RockLithology(code: value, name: nil).validate()) == nil {
                    return "\(row.location(column)): требуется точный код породы из справочника."
                }
            case 6:
                if !RegulatoryWallAlteration.allCases.contains(where: { String($0.rating) == value }) {
                    return "\(row.location(column)): допустимые баллы A45: 6, 5, 3, 1, 0."
                }
            case 8:
                if !RegulatoryStrengthBand.allCases.contains(where: { String($0.rating) == value }) {
                    return "\(row.location(column)): допустимые баллы A1: 0, 1, 2, 4, 7, 12, 15."
                }
            default: break
            }
        }
        return nil
    }

    private static func protectedIssues(_ rows: [Row], projected: [[String]]) -> String? {
        let columns = RegulatoryDataWorkbook.protected
        let expected = Dictionary(grouping: projected) { values in columns.map { values[$0] } }.mapValues(\.count)
        let actual = Dictionary(grouping: rows) { row in columns.map { row.values[$0] } }.mapValues(\.count)
        guard expected != actual else { return nil }
        var issues = rows.flatMap { row -> [String] in
            if expected[columns.map({ row.values[$0] })] != nil { return [] }
            // All projected rows share the non-fault fields. A fault difference is
            // reported against S:U as a unit because no structure UUID is in Data.
            let differences = RegulatoryDataWorkbook.repeated.filter { row.values[$0] != projected[0][$0] }
            var result = differences.map { "\(row.location($0)) (\(RegulatoryDataWorkbook.columns[$0])): изменение защищённого поля." }
            if !projected.contains(where: { Array($0[18...20]) == Array(row.values[18...20]) }) {
                result.append("\(row.location(18)):\(RegulatoryDataWorkbook.address(20, row.number)): поля разлома отличаются от журнала.")
            }
            return result
        }
        if issues.isEmpty || projected.count != rows.count {
            issues.append("Для наблюдения требуется полный комплект строк разломов из выгрузки.")
        }
        return issues.joined(separator: "\n")
    }

    private static func proposal(_ row: Row, previous: MappingObservation, projected: [String],
                                 current: MappingCommittedSnapshot) throws -> MappingObservation {
        var point = previous
        var categories = previous.ratings?.regulatory ?? RegulatoryFieldCategories()
        let rmr = previous.ratings?.rmr89?.input
        for column in RegulatoryDataWorkbook.editable {
            let value = row.values[column]
            guard !value.isEmpty, value != projected[column] else { continue }
            let clear = value == ExchangeObservationProposal.clear
            switch column {
            case 5:
                if clear { point.rock = nil; continue }
                guard let rock = current.projects[previous.projectID]?.lithologies?.first(where: { $0.code == value }) else {
                    throw ExchangeImportError("\(row.location(column)): код отсутствует в справочнике проекта.")
                }
                point.rock = rock
            case 6:
                if clear, RegulatoryFieldCategories().wallAlterationRating(rmr: rmr) != nil {
                    throw ExchangeImportError("\(row.location(column)): после очистки остаётся категория из RMR89. Оценка защищена.")
                }
                categories.wallAlteration = RegulatoryWallAlteration.allCases.first { String($0.rating) == value }
            case 8:
                if clear, RegulatoryFieldCategories().strengthRating(rmr: rmr) != nil {
                    throw ExchangeImportError("\(row.location(column)): после очистки остаётся полевая категория RMR89. Оценка защищена.")
                }
                categories.strength = RegulatoryStrengthBand.allCases.first { String($0.rating) == value }
            default: break
            }
        }
        if categories != (previous.ratings?.regulatory ?? RegulatoryFieldCategories()) {
            if categories.isEmpty, previous.ratings?.bartonQ == nil, previous.ratings?.rmr89 == nil, previous.ratings?.gsi == nil {
                point.ratings = nil
            } else {
                point.ratings = MappingRatings(bartonQ: previous.ratings?.bartonQ, rmr89: previous.ratings?.rmr89,
                    gsi: previous.ratings?.gsi, regulatory: categories.isEmpty ? nil : categories)
            }
        }
        return point
    }

    private static func contextLabel(_ point: MappingObservation, in current: MappingCommittedSnapshot) -> String {
        [current.projects[point.projectID]?.name, current.horizons[point.horizonID]?.displayName,
         current.excavations[point.excavationID]?.name, point.displayPicket,
         MappingCSVExport.iso(point.observedAt), point.id.uuidString].compactMap { $0 }.joined(separator: " · ")
    }

    /// Storage-side allowlist, independent of workbook parsing and preview.
    static func preservesEvidence(_ proposal: MappingObservation, from point: MappingObservation,
                                  in current: MappingCommittedSnapshot) -> Bool {
        var allowed = point
        if proposal.rock != point.rock {
            if let rock = proposal.rock, current.projects[point.projectID]?.lithologies?.contains(rock) != true { return false }
            allowed.rock = proposal.rock
        }
        if proposal.ratings?.regulatory != point.ratings?.regulatory {
            allowed.ratings = MappingRatings(bartonQ: point.ratings?.bartonQ, rmr89: point.ratings?.rmr89,
                gsi: point.ratings?.gsi, regulatory: proposal.ratings?.regulatory)
            if allowed.ratings == MappingRatings(bartonQ: nil, rmr89: nil) { allowed.ratings = nil }
        }
        return proposal == allowed
    }
}
