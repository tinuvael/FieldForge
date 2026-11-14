import Foundation

enum RegulatoryDataImport {
    typealias Preview = MappingExchangePreview
    typealias Record = Preview.Record
    typealias Row = RegulatoryDataWorkbook.Row

    struct Review: Sendable {
        var documentID: String?
        var matches: [String: UUID] = [:]
        var assignment = RegulatoryDataProposal.Assignment()
        var assignments: [String: RegulatoryDataProposal.Assignment] = [:]
        var findExisting = Set<String>()
        var acknowledgeDerived = Set<String>()
        var preservePrecision = Set<String>()
        var rockCodes: [RockKey: String] = [:]
        var createSeparately = Set<String>()
        var groupFaults = Set<String>()
        var splitFaults = Set<String>()
        var takeExcelChanges: [String: String] = [:]
        var faultMatches: [String: [String: UUID]] = [:]
        var pickets: [String: String] = [:]
    }

    struct RockKey: Hashable, Sendable {
        let projectID: UUID
        let numericValue: String
    }

    struct Actions: Sendable {
        var canCreateSeparately = false
        var canGroup = false
        var canSplit = false
        var canResolveConflict = false
        var faultMatches: [RegulatoryDataProposal.FaultMatch] = []
        var needsPicket = false
        var canFindExisting = false
        var canAcknowledgeDerived = false
        var canPreservePrecision = false
        var rockKey: RockKey?
        var rockChoices: [RockLithology] = []
    }

    private struct Anchor: Hashable {
        let excavation: String
        let picket: String
        init(_ values: [String]) { excavation = values[0]; picket = values[1] }
        init(_ excavation: String, _ picket: String) { self.excavation = excavation; self.picket = picket }
    }

    private struct ChainageKey: Hashable {
        let excavation: String
        let convention: PicketConvention
        let metres: Double
    }

    static func reviewDocumentID(_ source: MappingImportSource) -> String {
        UUID(uuidString: source.documentID)?.uuidString ?? "legacy-regulatory-data"
    }

    static func prepare(bytes: Data, matches: [String: UUID] = [:], review: Review = .init(), committed: MappingCommittedSnapshot,
                        limits: ExchangeLimits = .init()) throws -> Preview {
        let workbook = try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)
        let manifest = workbook.manifest
        let documentID = workbook.documentID ?? manifest?.workbookID
        let source = MappingImportSource(kind: .regulatoryData,
            documentID: documentID?.uuidString ?? ExchangeBaseline.hash(bytes), bytes: bytes)
        var boundInput: RegulatorySourceImport.Input?
        var rows = workbook.rows
        let originalBindings = manifest?.bindings ?? []
        var mixedGroups: [UUID: [Row]]?
        if let bindings = manifest?.sourceBindings, !bindings.isEmpty {
            let byRow = Dictionary(uniqueKeysWithValues: bindings.map { ($0.row, $0) })
            let selected = rows.filter { byRow[$0.number] != nil }
            let sourceIDs = Set(bindings.map(\.sourceID))
            let nativeRowCount = originalBindings.reduce(0) { $0 + $1.rowCount }
            rows.removeAll { byRow[$0.number] != nil }
            guard selected.count == bindings.count, sourceIDs.count == bindings.count,
                  selected.allSatisfy({ byRow[$0.number]?.sourceID == $0.values[0] }),
                  rows.count == nativeRowCount,
                  rows.allSatisfy({ (5..<(5 + nativeRowCount)).contains($0.number) }) else {
                throw ExchangeImportError("Неоднозначные строки Data. Сверьте ID и исходный порядок строк со скрытым листом или выгрузите книгу заново.")
            }
            let first = bindings[0]
            boundInput = .init(rows: selected, workbookSHA256: source.fingerprint,
                               suggestedProjectID: first.projectID, suggestedDataset: first.dataset,
                               suggestedFrame: first.frame, bindings: bindings, exportedAt: manifest?.exportedAt)
            if rows.isEmpty { return productionPreview(workbook, source: source, committed: committed, input: boundInput) }
            let sourceAnchors = Set(selected.map { Anchor($0.values) })
            var groups: [UUID: [Row]] = [:]
            for binding in originalBindings {
                let start = binding.firstRow - 5
                let group = Array(rows[start..<(start + binding.rowCount)])
                let anchor = Anchor(binding.excavation ?? "", binding.picket ?? "")
                guard group.allSatisfy({ Anchor($0.values) == anchor }),
                      !sourceAnchors.contains(anchor),
                      group.allSatisfy({ row in
                          RegulatoryDataWorkbook.common.allSatisfy { row.values[$0] == group[0].values[$0] }
                      }) else {
                    throw ExchangeImportError("Data!A\(binding.firstRow): проверьте ID, PK, порядок и общие поля группы обычного наблюдения. При совпадении ID и PK выгрузите типы строк отдельно.")
                }
                groups[binding.target.observationID] = group
            }
            mixedGroups = groups
        } else if workbook.productionLayout {
            return productionPreview(workbook, source: source, committed: committed)
        }
        let scope = reviewDocumentID(source)
        var review = review.documentID == nil || review.documentID == scope ? review : Review()
        review.matches.merge(matches) { _, explicit in explicit }
        let candidates = Dictionary(grouping: committed.effectiveObservations) {
            Anchor(committed.excavations[$0.excavationID]?.name ?? "", $0.displayPicket)
        }
        let chainageCandidates = Dictionary(grouping: committed.effectiveObservations) {
            ChainageKey(excavation: committed.excavations[$0.excavationID]?.name ?? "",
                convention: $0.picketConvention ?? .legacyMeters, metres: $0.chainageMeters)
        }
        let byAnchor = Dictionary(grouping: originalBindings) { Anchor($0.excavation ?? "", $0.picket ?? "") }
        let bindingsByID = Dictionary(uniqueKeysWithValues: originalBindings.map { ($0.target.observationID, $0) })
        let grouped = Dictionary(grouping: rows) { row -> [String] in
            // A missing A or B provides no common observation key.
            let common = RegulatoryDataWorkbook.common.map { row.values[$0] } + [row.numericRock ? "numeric-rock" : "text-rock"]
            return row.values[0].isEmpty || row.values[1].isEmpty ? common + [String(row.number)] : common
        }
        let groupsByAnchor = Dictionary(grouping: grouped.values) { Anchor($0[0].values) }.mapValues(\.count)
        let missingBindings = originalBindings.filter { binding in
            let anchor = Anchor(binding.excavation ?? "", binding.picket ?? "")
            return groupsByAnchor[anchor, default: 0] < byAnchor[anchor, default: []].count
        }
        var byRow: [Int: RegulatoryDataManifest.Binding] = [:]
        for binding in missingBindings {
            for row in binding.firstRow..<(binding.firstRow + binding.rowCount) { byRow[row] = binding }
        }
        let archived = Dictionary(uniqueKeysWithValues: committed.journal.revisions.map { ($0.id, $0) })
        let originals = Dictionary(uniqueKeysWithValues: committed.journal.observations.map { ($0.id, $0) })
        var originalProjections: [UUID: (point: MappingObservation, rows: [[String]])] = [:]
        for binding in originalBindings {
            try Task.checkCancellation()
            guard let point = try original(binding, originals: originals, archived: archived) else { continue }
            let rows = try projected(point, current: committed)
            guard binding.excavation == rows[0][0], binding.picket == rows[0][1],
                  try RegulatoryDataWorkbook.legacySignature(rows[0]) == binding.signature else { continue }
            originalProjections[point.id] = (point, rows)
        }
        let ledger = (committed.journal.importLedger?.entries ?? []).filter {
            $0.operation.source.kind == .regulatoryData && $0.operation.source.documentID == source.documentID
        }
        let receipts = Dictionary(grouping: ledger, by: \.operation.sourceRecordID)
        var exactReceipts: [String: MappingImportLedger.Entry] = [:]
        for entry in ledger where entry.operation.isMutation && entry.operation.source == source {
            if let note = entry.operation.note,
               let saved = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note),
               let key = saved.reviewKey { exactReceipts[key] = entry }
        }
        let duplicateNumbers = Set(Dictionary(grouping: rows.filter { $0.issues.isEmpty }, by: \.values)
            .values.filter { $0.count > 1 }.flatMap { $0.map(\.number) })
        var records: [Record] = []
        if let mixedGroups {
            let repeatedAnchors = Set(byAnchor.filter { $0.value.count > 1 }.keys)
            for binding in originalBindings {
                try Task.checkCancellation()
                let id = binding.target.observationID
                guard let rows = mixedGroups[id], let projection = originalProjections[id],
                      let point = committed.observation(id: id), projection.rows.count == rows.count else {
                    throw ExchangeImportError("Data!A\(binding.firstRow): UUID или исходная версия обычного наблюдения не найдены. Выгрузите книгу из этого журнала.")
                }
                let key = try rowKey(rows)
                let unchanged = !rows.contains(where: \.numericRock) &&
                    projection.rows.sorted(by: lexicographic) == rows.map(\.values).sorted(by: lexicographic)
                if !unchanged && repeatedAnchors.contains(Anchor(rows[0].values)) {
                    throw ExchangeImportError("Data!A\(binding.firstRow): несколько обычных наблюдений имеют один ID и PK. Выгрузите изменяемое наблюдение отдельно.")
                }
                let prior = receipts[boundKey(id)] ?? []
                let receipt = exactReceipts[key] ?? prior.last { $0.operation.isMutation && $0.operation.source == source }
                guard receipt == nil || receipt?.operation.target.observationID == id else {
                    throw ExchangeImportError("Data!A\(binding.firstRow): история импорта не соответствует UUID обычного наблюдения.")
                }
                let record = try compare(key: key, rows: rows, suggestions: [point], binding: binding,
                    originalProjection: projection, unchanged: unchanged ? id : nil, choice: nil,
                    missingOriginals: false, duplicate: false, receipt: receipt, previous: prior,
                    source: source, review: review, current: committed, fixedTarget: id)
                records.append(record)
            }
        }
        let legacyGroups = mixedGroups == nil ? grouped.values.sorted(by: { $0[0].number < $1[0].number }) : []
        for allRows in legacyGroups {
            try Task.checkCancellation()
            let groupKey = try rowKey(allRows)
            let priorSplit = try allRows.count > 1 && allRows.contains { row in
                try receipts[rowKey([row])]?.contains(where: { $0.reservesSource && $0.operation.source == source }) == true
            }
            let shouldSplit = (review.splitFaults.contains(groupKey) || priorSplit) &&
                !allRows.contains { duplicateNumbers.contains($0.number) }
            let groups: [[Row]]
            if shouldSplit {
                let anchor = Anchor(allRows[0].values)
                let originals = (byAnchor[anchor] ?? []).compactMap { binding in
                    originalProjections[binding.target.observationID]?.rows
                }
                groups = split(allRows, originals: originals)
            } else { groups = [allRows] }
            for rows in groups {
                let first = rows[0]
                let anchor = Anchor(first.values)
                let key = try rowKey(rows)
                let legacy = try RegulatoryDataWorkbook.legacySignature(first.values)
                let anchorBindings = byAnchor[anchor] ?? []
                let rowValues = rows.map(\.values).sorted(by: lexicographic)
                // Exact archival matches can only report unchanged. All changed
                // records require confirmation of a target, even at the old slot.
                let exact = anchorBindings.filter { binding in
                    !first.numericRock && originalProjections[binding.target.observationID]?.rows.sorted(by: lexicographic) == rowValues
                }
                let unchanged = exact.count == 1 ? exact.first : nil
                let hints = anchorBindings.isEmpty ? [byRow[first.number]].compactMap { $0 } : []
                let possibleBindings = anchorBindings + hints
                let assignment = review.assignments[key] ?? review.assignment
                var suggested = (candidates[anchor] ?? []) + possibleBindings.compactMap { committed.observation(id: $0.target.observationID) }
                for convention in [PicketConvention.tenMeters, .legacyMeters] {
                    if let metres = try? convention.meters(anchor.picket) {
                        suggested += chainageCandidates[ChainageKey(excavation: anchor.excavation, convention: convention, metres: metres)] ?? []
                    }
                }
                let choice = review.matches[key]
                if review.findExisting.contains(key) {
                    if let choice, let selected = committed.observation(id: choice) { suggested.append(selected) }
                    suggested += committed.effectiveObservations.filter {
                        (assignment.projectID == nil || assignment.projectID == $0.projectID) &&
                        (assignment.horizonID == nil || assignment.horizonID == $0.horizonID) &&
                        (assignment.excavationID == nil || assignment.excavationID == $0.excavationID)
                    }
                }
                let selectedBinding = choice.flatMap { bindingsByID[$0] } ?? unchanged
                let ids = [selectedBinding.map { boundKey($0.target.observationID) }, Optional(key), Optional(legacy)].compactMap { $0 }
                let receipt = exactReceipts[key] ?? ids.lazy.compactMap { id in
                    receipts[id]?.last { $0.operation.isMutation && $0.operation.source == source && $0.operation.note == nil }
                }.first
                let binding = receipt.flatMap { bindingsByID[$0.operation.target.observationID] } ?? selectedBinding
                let record = try compare(key: key, rows: rows, suggestions: suggested, binding: binding,
                    originalProjection: binding.flatMap { originalProjections[$0.target.observationID] },
                    unchanged: unchanged?.target.observationID, choice: choice, missingOriginals: !missingBindings.isEmpty,
                    duplicate: rows.contains { duplicateNumbers.contains($0.number) },
                    receipt: receipt, previous: ids.flatMap { receipts[$0] ?? [] }, source: source,
                    review: review, current: committed)
                records.append(record)
            }
        }
        let collisions = Dictionary(grouping: records.compactMap { record in record.target.map { ($0.observationID, record.id) } }, by: { $0.0 })
        let duplicates = Set(collisions.filter { $0.value.count > 1 }.keys)
        records = records.map { record in
            guard let target = record.target, duplicates.contains(target.observationID),
                  record.receipt?.outcome != .applied else { return record }
            return Record(id: record.reviewID ?? record.id, classification: .duplicate,
                reason: "Несколько групп строк назначены одному наблюдению. Сверьте строки и сопоставление.",
                changes: record.changes, proposed: nil, location: record.location, label: record.label,
                receipt: record.receipt, candidates: record.candidates, matchedID: record.matchedID,
                reviewID: record.reviewID, regulatoryActions: record.regulatoryActions)
        }
        var preview = Preview(workbookID: documentID ?? UUID(), generationID: committed.generationID,
            exportedAt: manifest?.exportedAt ?? .distantPast, projectName: "", metadata: [:], records: records,
            proposalDigest: source.fingerprint)
        preview.source = source
        preview.rowsProcessed = workbook.rows.count
        preview.productionInput = boundInput
        return preview
    }

    private static func productionPreview(_ workbook: RegulatoryDataWorkbook.Read, source: MappingImportSource,
                                          committed: MappingCommittedSnapshot,
                                          input: RegulatorySourceImport.Input? = nil) -> Preview {
        let reasons = input == nil ? [
            "Data!A3:A4 «Место картирования» (ID) содержит идентификаторы источника. Они сохраняются отдельно от выработки.",
            "Data!B3:B4 «Пикетаж» (PK) может быть пустым. Укажите метаданные координат C:E для всего набора.",
            "Data!AD (GSI) содержит расчётные формулы. Data!O (SD) содержит сводное расстояние между трещинами. Эти поля требуют исходных данных для записи в журнал.",
            "В исходной книге остаются AE:AH (Q′, Q, RMR89, RMR76), AI (номер точки), AJ (примечание), AK:BB (вспомогательные оценки и входы), BI:CP (формулы проверки)."
        ] : ["Исходные строки сопоставляются с UUID и версиями журнала по листу _FieldForge."]
        return Preview(source: source, rowsProcessed: workbook.rows.count, workbookBlocked: true,
                       workbookBlockReasons: reasons, worksheetRowsScanned: workbook.worksheetRowCount,
                       productionInput: input ?? .init(rows: workbook.rows, workbookSHA256: source.fingerprint),
                       workbookID: workbook.documentID ?? UUID(), generationID: committed.generationID,
                       exportedAt: .distantPast, projectName: "", metadata: [:], records: [],
                       proposalDigest: source.fingerprint)
    }

    private static func rowKey(_ rows: [Row]) throws -> String {
        try RegulatoryDataWorkbook.identity(rows)
    }
    private static func boundKey(_ id: UUID) -> String { "point/\(id.uuidString)" }

    private static func compare(key: String, rows: [Row], suggestions: [MappingObservation],
                                binding: RegulatoryDataManifest.Binding?,
                                originalProjection: (point: MappingObservation, rows: [[String]])?,
                                unchanged: UUID?, choice: UUID?, missingOriginals: Bool, duplicate: Bool,
                                receipt: MappingImportLedger.Entry?, previous: [MappingImportLedger.Entry],
                                source: MappingImportSource, review: Review, current: MappingCommittedSnapshot,
                                fixedTarget: UUID? = nil) throws -> Record {
        let first = rows[0]
        let numbers = rows.map { String($0.number) }.joined(separator: ", ")
        let location = "Data · строки \(numbers.prefix(400))"
        let label = "\(first.values[0]) · \(first.values[1])"
        let existingIDs = Set(suggestions.map(\.id))
        let userCreation = fixedTarget == nil && review.createSeparately.contains(key)
        var assignment = review.assignments[key] ?? review.assignment
        assignment.reviewKey = key
        assignment.picketOverride = review.pickets[key] ?? ""
        assignment.faultOrder = false
        assignment.faultMatches = review.faultMatches[key]
        assignment.canonicalFaultOrder = true
        if let receipt, receipt.outcome == .pending, let note = receipt.operation.note,
           let saved = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note) { assignment = saved }
        let selected = fixedTarget ?? choice.flatMap { existingIDs.contains($0) ? $0 : nil } ?? unchanged
        let currentID = receipt?.operation.target.observationID ?? (userCreation ? nil : selected)
        let point = currentID.flatMap { current.observation(id: $0) }
        let retryAfterConflict: Bool
        if let receipt, case .rejected(let conflict) = receipt.outcome, receipt.operation.kind == .update {
            switch conflict {
            case .revisionChanged, .observationChanged, .contextChanged: retryAfterConflict = true
            default: retryAfterConflict = false
            }
        } else { retryAfterConflict = false }
        let activeReceipt = retryAfterConflict ? nil : receipt
        let options = fixedTarget != nil || unchanged != nil || receipt != nil ? [] : Set(suggestions.map(\.id)).sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            current.observation(id: id).map { Preview.MatchCandidate(id: id, label: contextLabel($0, in: current)) }
        }
        let context = point.map { contextLabel($0, in: current) } ?? label
        let boundID = point.flatMap { binding?.target.observationID == $0.id ? boundKey($0.id) : nil }
        let id = receipt?.operation.sourceRecordID ?? boundID ?? key
        let uncertainCreation = fixedTarget == nil && unchanged == nil && (!options.isEmpty || missingOriginals)
        var actions = Actions(canCreateSeparately: uncertainCreation && receipt == nil,
            canSplit: fixedTarget == nil && rows.count > 1 && receipt == nil && (point == nil || rows.count > max(1, point?.geology?.tectonicStructures.count ?? 0)), needsPicket: point == nil && first.values[1].isEmpty,
            canFindExisting: fixedTarget == nil && unchanged == nil && receipt == nil && !review.findExisting.contains(key))
        func result(_ classification: Preview.Classification, _ reason: String,
                    changes: [Preview.Change] = [], proposed: MappingObservation? = nil,
                    baseline: MappingImportBaseline? = nil, graph: String? = nil) -> Record {
            Record(id: id, classification: classification, reason: reason, changes: changes, proposed: proposed,
                location: location, label: proposed.map { contextLabel($0, in: current) } ?? context,
                previous: point, baseline: baseline, graphFingerprint: graph,
                correctionReason: "Регламент Data A:AD, строки \(numbers.prefix(500))",
                receipt: activeReceipt, candidates: options, matchedID: point?.id, reviewID: key, regulatoryActions: actions,
                importNote: try? MappingExchangeExport.json(assignment))
        }
        if let receipt = activeReceipt {
            switch receipt.outcome {
            case .applied: return result(.unchanged, "Эти строки уже импортированы.")
            case .rejected: return result(.conflict, "Предыдущее решение об отклонении сохранено.")
            case .skipped: return result(.unchanged, "Эти строки уже проверены.")
            case .pending: break
            }
        }
        let issues = rows.flatMap(\.issues)
        guard issues.isEmpty else { return result(.invalid, issues.joined(separator: "\n")) }
        guard !duplicate else { return result(.duplicate, "Повторяющиеся строки. Сверьте исходные данные.") }
        if let unchanged, point?.id == unchanged, choice == nil, receipt == nil {
            return result(.unchanged, "Строки совпадают с исходной выгрузкой. Текущая версия журнала сохранена.")
        }
        if let pending = previous.last(where: { $0.outcome == .pending }), pending.operation.source != source {
            return result(.conflict, "Для этой группы есть незавершённый импорт. Откройте исходный файл.")
        }
        if point == nil && uncertainCreation && !userCreation && receipt == nil {
            return result(.ambiguous, "Подтвердите существующее наблюдение или создание отдельной записи.")
        }
        let savedFaultRows = point.map { max(1, $0.geology?.tectonicStructures.count ?? 0) } ?? 1
        if rows.count > savedFaultRows && !review.groupFaults.contains(key) && receipt == nil {
            actions.canGroup = true
            return result(.ambiguous, "Подтвердите, что эти строки описывают разломы одного наблюдения, или разделите их.")
        }

        do {
            let old: MappingObservation?
            var baseRows: [[String]]
            if let point {
                if let binding, binding.target.observationID == point.id {
                    guard let originalProjection else {
                        return result(.conflict, "Скрытый лист не соответствует исходной версии журнала.")
                    }
                    old = originalProjection.point
                    baseRows = originalProjection.rows
                } else {
                    old = point
                    baseRows = try projected(point, current: current)
                }
            } else {
                old = nil
                baseRows = [Array(repeating: "", count: RegulatoryDataWorkbook.columns.count)]
            }
            let target: MappingObservation
            if let point { target = point }
            else {
                let draft = try RegulatoryDataProposal.makeNew(id: UUID(), row: first, assignment: assignment, in: current)
                assignment.resolvedChainage = draft.chainageMeters
                let identity = try creationIdentity(rows, point: draft)
                let targetID = RegulatoryDataProposal.stableID(identity)
                if current.observation(id: targetID) != nil { return result(.duplicate, "Такое наблюдение уже импортировано.") }
                target = try RegulatoryDataProposal.makeNew(id: targetID, row: first, assignment: assignment, in: current)
                if receipt?.operation.kind == .create, receipt?.operation.target != MappingImportTarget(target) {
                    return result(.conflict, "Назначение незавершённой записи изменилось.")
                }
            }
            let baseline = try point.map { try MappingImportBaseline.capture(target: MappingImportTarget($0), in: current) }
            let graph = try point.map { try MappingExchangeExport.fingerprint($0.id, in: current) } ??
                MappingExchangeExport.importContextFingerprint(MappingImportTarget(target), in: current)
            if let pending = activeReceipt?.operation, pending.baseline != baseline || pending.graphFingerprint != graph {
                return result(.conflict, "Журнал изменился после подтверждения. Отклоните незавершённый импорт.")
            }
            if first.numericRock {
                let raw = first.values[5]
                let rockKey = RockKey(projectID: target.projectID, numericValue: raw)
                let options = (current.projects[target.projectID]?.lithologies ?? []).filter { Double($0.code) == Double(raw) }
                guard !options.isEmpty else {
                    return result(.invalid, "\(first.location(5)): для числового значения нет соответствующего текстового кода в справочнике проекта.")
                }
                actions.rockKey = rockKey
                actions.rockChoices = options
                let code = assignment.resolvedRockCode ?? review.rockCodes[rockKey]
                guard options.contains(where: { $0.code == code }) else {
                    return result(.ambiguous, "\(first.location(5)): подтвердите точный код породы для числового значения Excel.")
                }
                assignment.resolvedRockCode = code
            }
            let derived = [14, 29].filter { !first.values[$0].isEmpty && first.values[$0] != baseRows[0][$0] }
            let rounded = RegulatoryDataWorkbook.common.filter { column in
                column >= 2 && column != 5 && column != 14 && column != 29 &&
                    suspectedExcelRounding(saved: baseRows[0][column], incoming: first.values[column])
            }
            if !rounded.isEmpty {
                let locations = rounded.map(first.location).joined(separator: ", ")
                guard review.preservePrecision.contains(key) || assignment.preservePrecision == true else {
                    actions.canPreservePrecision = true
                    return result(.unsupported, locations + ": Excel округлил исходные числа. Сохраните точные значения журнала.")
                }
                assignment.preservePrecision = true
            }
            if !derived.isEmpty {
                let description = derived.map { first.location($0) + " " + RegulatoryDataWorkbook.columns[$0] }.joined(separator: ", ")
                guard review.acknowledgeDerived.contains(key) || assignment.acknowledgeDerived == true else {
                    actions.canAcknowledgeDerived = true
                    return result(.unsupported, description + ": расчётные поля. Для SD нужны исходные расстояния, для GSI — сохранённая оценка.")
                }
                assignment.acknowledgeDerived = true
            }
            let acceptedRows = rows.map { row in
                var values = row.values
                for column in derived + rounded { values[column] = "" }
                if row.numericRock, let code = assignment.resolvedRockCode { values[5] = code }
                return Row(number: row.number, values: values, issues: row.issues)
            }
            var faultRows: [UUID: Int] = [:]
            let proposed = try RegulatoryDataProposal.make(rows: acceptedRows, point: target, exported: old, exportedRows: baseRows,
                assignment: assignment, in: current, faultRows: &faultRows)
            let local = try point.map { try projected($0, current: current) } ?? baseRows
            let changes = try differences(key: id, rows: rows, before: local, proposed: proposed, previous: point, current: current, faultRows: faultRows)
            if proposed == point { return result(.unchanged, "Значения совпадают с журналом.") }
            let staleExport = binding.map { $0.target.observationID == point?.id &&
                ($0.baseline != baseline || $0.graphFingerprint != graph) } ?? false
            if (staleExport || retryAfterConflict), activeReceipt == nil, review.takeExcelChanges[key] != graph {
                actions.canResolveConflict = true
                return result(.conflict, "Журнал изменился после выгрузки. Сверьте текущие значения и подтвердите только правки Excel.",
                    changes: changes, baseline: baseline, graph: graph)
            }
            if point == nil, try duplicateObservation(proposed, current: current) {
                return result(.duplicate, "На этом горизонте уже есть наблюдение с теми же данными. Сопоставьте его с журналом.")
            }
            let spatial = spatialMessage(proposed)
            let retained = (derived.isEmpty ? "" : " Подтверждено сохранение расчётных значений журнала (SD/GSI).") +
                (rounded.isEmpty ? "" : " Сохранены точные числа журнала.")
            let status = point == nil ? "Новое наблюдение из Data." : "Исправление существующего наблюдения."
            return result(point == nil ? .new : .correction, status + spatial + retained, changes: changes,
                          proposed: proposed, baseline: baseline, graph: graph)
        } catch let required as RegulatoryDataProposal.FaultMatchingRequired {
            actions.faultMatches = required.matches
            return result(.ambiguous, "Data!S:U: сопоставьте каждую изменённую строку с сохранённым разломом. Оставшиеся строки добавятся как новые.")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return result(.invalid, error.localizedDescription)
        }
    }

    private static func lexicographic(_ a: [String], _ b: [String]) -> Bool { a.lexicographicallyPrecedes(b) }

    /// Retain a saved multi-row group only when all its fault values are present
    /// uniquely. Worksheet positions never decide which faults stay together.
    private static func split(_ rows: [Row], originals: [[[String]]]) -> [[Row]] {
        let byFault = Dictionary(grouping: rows) { Array($0.values[RegulatoryDataWorkbook.fault]) }
        let candidates = originals.compactMap { original -> [Row]? in
            guard original.count > 1 else { return nil }
            let matches = original.compactMap { values -> Row? in
                let rows = byFault[Array(values[RegulatoryDataWorkbook.fault])] ?? []
                return rows.count == 1 ? rows[0] : nil
            }
            guard matches.count == original.count, Set(matches.map(\.number)).count == original.count else { return nil }
            return matches.sorted { $0.number < $1.number }
        }
        let useCount = Dictionary(grouping: candidates.flatMap { $0 }, by: \.number).mapValues(\.count)
        let retained = candidates.filter { $0.allSatisfy { useCount[$0.number] == 1 } }
        let used = Set(retained.flatMap { $0.map(\.number) })
        return (retained + rows.filter { !used.contains($0.number) }.map { [$0] }).sorted { $0[0].number < $1[0].number }
    }

    private static func original(_ binding: RegulatoryDataManifest.Binding, originals: [UUID: MappingObservation],
                                 archived: [UUID: MappingObservationRevision]) throws -> MappingObservation? {
        let snapshot: MappingObservation?
        if let revision = binding.baseline.revisionID {
            let entry = archived[revision]
            snapshot = entry?.version == binding.baseline.version ? entry?.snapshot : nil
        } else {
            snapshot = binding.baseline.version == 1 ? originals[binding.target.observationID] : nil
        }
        guard let snapshot, MappingImportTarget(snapshot) == binding.target,
              try MappingImportLedger.fingerprint(snapshot) == binding.baseline.fingerprint else { return nil }
        return snapshot
    }

    private static func projected(_ point: MappingObservation, current: MappingCommittedSnapshot) throws -> [[String]] {
        try EnterpriseGeotechnicalWorkbook.prepare(points: [point], journal: current.journal).table.rows
            .map(RegulatoryDataWorkbook.values)
    }

    private static func creationIdentity(_ rows: [Row], point: MappingObservation) throws -> String {
        // B may be written in different valid forms. Scope replay to the declared
        // parent UUIDs and canonical chainage, with the complete row payload.
        let cells = rows.map { Array($0.values.dropFirst(2)) }.sorted { $0.lexicographicallyPrecedes($1) }
        let digest = try MappingImportLedger.fingerprint(cells)
        return "\(point.projectID)/\(point.horizonID)/\(point.excavationID)/\(point.chainageMeters)/\(digest)"
    }

    private static func duplicateObservation(_ point: MappingObservation, current: MappingCommittedSnapshot) throws -> Bool {
        let proposal = try projected(point, current: current).map { Array($0.dropFirst(2)) }
        for local in current.observations(context: MappingImportTarget(point).context) where local.chainageMeters == point.chainageMeters {
            let saved = try projected(local, current: current).map { Array($0.dropFirst(2)) }
            if saved.sorted(by: { $0.lexicographicallyPrecedes($1) }) == proposal.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                return true
            }
        }
        return false
    }

    private static func differences(key: String, rows: [Row], before: [[String]], proposed: MappingObservation,
                                    previous: MappingObservation?, current: MappingCommittedSnapshot, faultRows: [UUID: Int]) throws -> [Preview.Change] {
        let after = try projected(proposed, current: current)
        var changes: [Preview.Change] = []
        let structures = proposed.geology?.tectonicStructures ?? []
        for index in 0..<max(before.count, after.count) {
            let number = rows.indices.contains(index) ? rows[index].number : rows[0].number
            for column in RegulatoryDataWorkbook.columns.indices {
                if index > 0 && !RegulatoryDataWorkbook.fault.contains(column) { continue }
                let old = before.indices.contains(index) ? before[index][column] : ""
                let new = after.indices.contains(index) ? after[index][column] : ""
                guard old != new else { continue }
                let field = MappingXLSXExport.column(column + 1) + " · " + RegulatoryDataWorkbook.columns[column]
                let faultRow = RegulatoryDataWorkbook.fault.contains(column) && structures.indices.contains(index)
                    ? faultRows[structures[index].id] : nil
                changes.append(.init(sheet: "Data", record: key + "/\(index)", field: field, before: old, after: new, row: faultRow ?? number))
            }
        }
        let qBefore = previous?.ratings?.bartonQ?.evaluation.result?.value
        let qAfter = proposed.ratings?.bartonQ?.evaluation.result?.value
        if qBefore != qAfter {
            changes.append(.init(sheet: "Data", record: key, field: "Barton Q", before: qBefore.map(ElevationInput.text) ?? "",
                after: qAfter.map(ElevationInput.text) ?? ""))
        }
        for (label, old, new) in [
            ("RMR89 · базовый", previous?.ratings?.rmr89?.calculation?.value, proposed.ratings?.rmr89?.calculation?.value),
            ("RMR89 · с поправкой", previous?.ratings?.rmr89?.calculation?.adjustedValue, proposed.ratings?.rmr89?.calculation?.adjustedValue)
        ] where old != new {
            changes.append(.init(sheet: "Data", record: key, field: label, before: old.map(String.init) ?? "", after: new.map(String.init) ?? ""))
        }
        return changes
    }

    private static func suspectedExcelRounding(saved: String, incoming: String) -> Bool {
        guard let baseline = Double(saved), let proposed = Double(incoming), baseline != proposed,
              (try? MappingXLSXExport.numericText(baseline).isText) == true else { return false }
        let rounded = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), baseline)
        return Double(rounded) == proposed
    }

    private static func spatialMessage(_ point: MappingObservation) -> String {
        guard let c = point.coordinates, c.x != nil, c.y != nil else { return " Для отображения на плане необходимы X и Y." }
        if c.source == "regulatoryExcel" { return " Для отображения на плане подтвердите систему XY и привяжите точку к DXF." }
        return ""
    }

    private static func contextLabel(_ point: MappingObservation, in current: MappingCommittedSnapshot) -> String {
        [current.projects[point.projectID]?.name, current.horizons[point.horizonID]?.displayName,
         current.excavations[point.excavationID]?.name, point.displayPicket,
         MappingCSVExport.iso(point.observedAt), point.id.uuidString].compactMap { $0 }.joined(separator: " · ")
    }

    /// Final storage admission still protects evidence and all fields without a Data mapping.
    static func preservesEvidence(_ proposal: MappingObservation, from point: MappingObservation?,
                                  in current: MappingCommittedSnapshot) -> Bool {
        guard proposal.ratings?.gsi == point?.ratings?.gsi,
              proposal.measurementIDs == (point?.measurementIDs ?? []),
              proposal.geology?.start == point?.geology?.start, proposal.geology?.end == point?.geology?.end,
              proposal.geology?.position == point?.geology?.position else { return false }
        if proposal.rock != point?.rock, let rock = proposal.rock,
           current.projects[proposal.projectID]?.lithologies?.contains(rock) != true { return false }
        let oldSets = point?.geology?.jointSets ?? []
        let newSets = proposal.geology?.jointSets ?? []
        guard oldSets.filter({ !$0.identifier.isRoutine }) == newSets.filter({ !$0.identifier.isRoutine }) else { return false }
        for before in oldSets {
            guard let after = newSets.first(where: { $0.id == before.id }), after.identifier == before.identifier,
                  after.author == before.author, after.method == before.method, after.measurementIDs == before.measurementIDs,
                  after.spacingMeters == before.spacingMeters, after.spacingProvenance == before.spacingProvenance,
                  after.persistenceMeters == before.persistenceMeters, after.apertureMillimeters == before.apertureMillimeters,
                  after.roughness == before.roughness, after.infill == before.infill, after.notes == before.notes else { return false }
        }
        for after in newSets where !oldSets.contains(where: { $0.id == after.id }) {
            guard after.measurementIDs.isEmpty, after.spacingMeters == nil, after.persistenceMeters == nil,
                  after.apertureMillimeters == nil, after.spacingProvenance == nil else { return false }
        }
        for before in point?.geology?.tectonicStructures ?? [] {
            guard let after = proposal.geology?.tectonicStructures.first(where: { $0.id == before.id }),
                  after.type == before.type, after.picket == before.picket,
                  after.position == before.position, after.description == before.description else { return false }
        }
        guard let point else { return true }
        return proposal.createdAt == point.createdAt && proposal.updatedAt == point.updatedAt &&
            proposal.observedAt == point.observedAt && proposal.observedTimeZoneID == point.observedTimeZoneID &&
            proposal.observedUTCOffsetSeconds == point.observedUTCOffsetSeconds && proposal.notes == point.notes &&
            proposal.chainageOriginAndDirection == point.chainageOriginAndDirection && proposal.picketConvention == point.picketConvention
    }
}

/// Source-backed observations live in the mapping journal. Location is optional
/// and versioned independently of source identity and field evidence.
struct RegulatorySourceObservation: Codable, Equatable, Identifiable, Sendable {
    struct Key: Codable, Hashable, Sendable {
        let projectID: UUID
        let dataset: String
        let sourceID: String
    }

    struct Version: Codable, Equatable, Sendable {
        enum Origin: String, Codable, Sendable { case sourceImport, localEdit, workbookEdit, assignment }

        let workbookSHA256: String
        let sourceRow: Int
        var cells: [String]
        var acceptedCells: [String]? = nil
        var importedCells: [String]? = nil
        var origin: Origin? = nil
        var sourceBaseline: [String] { acceptedCells ?? cells }
        var frame: RegulatorySourceImport.Frame
        var destination: MappingContext
        var explicitlyAssigned: Bool
        var resolution: RegulatorySourceImport.Resolution?
        var savedAt: Date

        var north: GeographicReference? = nil
        var matchingIssue: RegulatorySourceImport.MatchingIssue? = nil
        var geometryEvidence: RegulatorySourceImport.GeometryEvidence? = nil
        var excavationManuallyAssigned: Bool? = nil

        var xyz: [Double?] { cells[2...4].map(RegulatoryDataWorkbook.sourceNumber) }
        var northReference: GeographicReference { north ?? .unknown }
        var hasLocalEdits: Bool { cells.indices.contains(where: isLocallyEdited) }

        func isLocallyEdited(_ column: Int) -> Bool {
            !Self.equal(cells[column], sourceBaseline[column], column: column)
        }

        static func equal(_ lhs: String, _ rhs: String, column: Int) -> Bool {
            if lhs == rhs { return true }
            guard column >= 2, column != 5,
                  let left = RegulatoryDataWorkbook.sourceNumber(lhs),
                  let right = RegulatoryDataWorkbook.sourceNumber(rhs), left == right else { return false }
            let locale = Locale(identifier: "en_US_POSIX")
            guard let exactLeft = Decimal(string: lhs, locale: locale),
                  let exactRight = Decimal(string: rhs, locale: locale) else { return false }
            return exactLeft == exactRight
        }
    }

    let id: UUID
    let key: Key
    var versions: [Version]
    var latest: Version? { versions.last }
}

enum RegulatorySourceImport {
    struct Frame: Codable, Hashable, Sendable {
        var crs = ""
        var axes = ""
        var xyUnits = ""
        var verticalDatum = ""

        /// Complete previously unknown metadata without reinterpreting declared axes, units or datum.
        func canUse(_ confirmed: Frame) -> Bool {
            [(crs, confirmed.crs), (axes, confirmed.axes), (verticalDatum, confirmed.verticalDatum)]
                .allSatisfy { old, new in PlanCoordinateCompatibility.known(old).map { $0 == PlanCoordinateCompatibility.known(new) } ?? true }
                && (xyUnits.isEmpty || xyUnits == confirmed.xyUnits)
        }

        var valid: Bool {
            [crs, axes, verticalDatum].allSatisfy { $0.utf8.count <= 256 } &&
                ["", "m", "mm", "drawing"].contains(xyUnits)
        }
    }

    struct ElevationRange: Codable, Equatable, Sendable {
        let minimum: Double
        let maximum: Double
        let datum: String

        var valid: Bool {
            minimum.isFinite && maximum.isFinite && minimum <= maximum &&
                PlanCoordinateCompatibility.known(datum) != nil && datum.utf8.count <= 256
        }

        func contains(_ z: Double) -> Bool { minimum <= z && z <= maximum }
    }

    struct GeometryRule: Codable, Equatable, Sendable {
        let horizonID: UUID
        let excavationID: UUID?
        let frame: Frame
        let maximumXYMeters: Double
        let maximumZMeters: Double

        var valid: Bool {
            frame.valid && [frame.crs, frame.axes, frame.verticalDatum].allSatisfy { PlanCoordinateCompatibility.known($0) != nil } &&
                ["m", "mm"].contains(frame.xyUnits) &&
                [maximumXYMeters, maximumZMeters].allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }

    enum Resolution: Codable, Equatable, Sendable {
        case elevationRange(ElevationRange)
        case geometry(planID: UUID, sha256: String, rule: GeometryRule)
        case retained
    }

    struct DatasetSettings: Codable, Equatable, Sendable {
        var frame: Frame
        var north: GeographicReference?
        var plans: [UUID: PlanAssociation] = [:]
    }

    /// Confirmation is scoped to a source dataset and one immutable DXF revision.
    /// XY display can be confirmed independently of vertical matching.
    struct PlanAssociation: Codable, Equatable, Sendable {
        let horizonID: UUID
        let sha256: String
        let frame: Frame
        let confirmedAt: Date
        var geometry: GeometryRule? = nil

        func supportsXY(_ plan: MappingPlanReference, frame: Frame) -> Bool {
            guard !plan.isDeleted, !plan.isArchived, let file = plan.file, sha256 == file.sha256,
                  horizonID == plan.horizonID, let crs = PlanCoordinateCompatibility.known(self.frame.crs),
                  let axes = PlanCoordinateCompatibility.known(self.frame.axes) else { return false }
            return crs == PlanCoordinateCompatibility.known(frame.crs) && crs == PlanCoordinateCompatibility.known(file.crs)
                && axes == PlanCoordinateCompatibility.known(frame.axes) && axes == PlanCoordinateCompatibility.known(file.axes)
                && self.frame.xyUnits == frame.xyUnits && frame.xyUnits == file.units.coordinateUnits
                && ["m", "mm"].contains(frame.xyUnits) && PlanElevationSnap.metersPerUnit(file) != nil
        }
    }

    enum MatchingIssue: String, Codable, Equatable, Sendable {
        case missingElevation, unknownDatum, noVerifiedSources, noMatch, ambiguousGeometry, ambiguousRanges, unavailableGeometry

        var isAmbiguous: Bool { self == .ambiguousGeometry || self == .ambiguousRanges }
        var title: String {
            switch self {
            case .missingElevation: return "В источнике отсутствует отметка Z."
            case .unknownDatum: return "Вертикальный датум набора неизвестен."
            case .noVerifiedSources: return "Нет подтверждённого DXF или диапазонов в датуме набора."
            case .noMatch: return "Точка вне подтверждённых допусков DXF и диапазонов отметок."
            case .ambiguousGeometry: return "В допуски DXF попадают несколько горизонтов."
            case .ambiguousRanges: return "Отметка входит в диапазоны нескольких горизонтов."
            case .unavailableGeometry: return "Проверьте исходный DXF и актуальность подтверждения его геометрии."
            }
        }
    }

    struct GeometryEvidence: Codable, Equatable, Sendable {
        let segment: DXFElevationSegment
        let projectedZMeters: Double
        let xyDistanceMeters: Double
        let zDifferenceMeters: Double
    }

    private struct Geometry {
        let plan: MappingPlanReference
        let rule: GeometryRule
        let factor: Double
        let index: PlanElevationIndex

        func match(_ point: PlanPoint, z: Double) -> GeometryEvidence? {
            for id in index.nearby(point, radius: rule.maximumXYMeters / factor) {
                let segment = index.segments[id]
                guard let sample = segment.projection(point) else { continue }
                let projectedZ = sample.z * factor
                let distance = sample.distance * factor
                let difference = abs(projectedZ - z)
                if distance <= rule.maximumXYMeters && difference <= rule.maximumZMeters {
                    return .init(segment: segment, projectedZMeters: projectedZ,
                                 xyDistanceMeters: distance, zDifferenceMeters: difference)
                }
            }
            return nil
        }
    }

    private struct Matcher {
        let geometry: [Geometry]
        let unavailableGeometry: Bool
        let ranges: [(UUID, ElevationRange)]
        let frame: Frame

        func resolve(_ version: inout RegulatorySourceObservation.Version) {
            guard version.destination.horizonID == nil, !version.explicitlyAssigned else { return }
            guard let z = version.xyz[2] else { version.matchingIssue = .missingElevation; return }
            guard PlanCoordinateCompatibility.known(frame.verticalDatum) != nil else { version.matchingIssue = .unknownDatum; return }
            if let x = version.xyz[0], let y = version.xyz[1] {
                let point = PlanPoint(x: x, y: y)
                let matches = geometry.compactMap { entry in entry.match(point, z: z).map { (entry, $0) } }
                if Set(matches.map { $0.0.plan.horizonID }).count > 1 {
                    version.matchingIssue = .ambiguousGeometry
                    return
                }
                if unavailableGeometry {
                    version.matchingIssue = .unavailableGeometry
                    return
                }
                if let (first, sample) = matches.first {
                    version.destination.horizonID = first.plan.horizonID
                    if matches.allSatisfy({ $0.0.rule.excavationID == first.rule.excavationID }) {
                        version.destination.excavationID = first.rule.excavationID
                    }
                    version.resolution = .geometry(planID: first.plan.id, sha256: first.plan.file!.sha256, rule: first.rule)
                    version.geometryEvidence = sample
                    version.matchingIssue = nil
                    return
                }
            }
            let contained = ranges.filter { $0.1.contains(z) }
            if contained.count == 1, let (id, range) = contained.first {
                version.destination.horizonID = id
                version.resolution = .elevationRange(range)
                version.matchingIssue = nil
            } else {
                version.matchingIssue = contained.count > 1 ? .ambiguousRanges :
                    (geometry.isEmpty && ranges.isEmpty ? .noVerifiedSources : .noMatch)
            }
        }
    }

    private static func matcher(projectID: UUID, frame: Frame, associations: [UUID: PlanAssociation],
                                ranges reviewedRanges: [UUID: ElevationRange], snapshot: MappingCommittedSnapshot,
                                plans: ManagedPlanStore?) throws -> Matcher {
        let ranges = snapshot.journal.horizons.compactMap { horizon -> (UUID, ElevationRange)? in
            guard horizon.projectID == projectID,
                  let range = reviewedRanges[horizon.id] ?? horizon.regulatoryElevationRange,
                  range.datum == frame.verticalDatum, range.datum == horizon.elevationDatum else { return nil }
            return (horizon.id, range)
        }
        var unavailable = false
        let geometry = try associations.sorted { $0.key.uuidString < $1.key.uuidString }.compactMap { id, association -> Geometry? in
            try Task.checkCancellation()
            guard let rule = association.geometry, rule.frame == frame,
                  let plan = snapshot.plan(id: id), !plan.isDeleted, !plan.isArchived else { return nil }
            guard association.supportsXY(plan, frame: frame),
                  snapshot.horizons[plan.horizonID]?.projectID == projectID,
                  snapshot.horizons[plan.horizonID]?.elevationDatum == frame.verticalDatum,
                  snapshot.journal.validContext(.init(projectID: projectID, horizonID: plan.horizonID, excavationID: rule.excavationID)),
                  let factor = PlanElevationSnap.metersPerUnit(plan), (rule.maximumXYMeters / factor).isFinite,
                  let plans else {
                unavailable = true
                return nil
            }
            do {
                let document = try DXFDocument.parse(plans.read(plan))
                guard document.insertionUnits == plan.file?.insertionUnits, document.elevationIndex.segmentCount > 0 else {
                    unavailable = true
                    return nil
                }
                return Geometry(plan: plan, rule: rule, factor: factor, index: document.elevationIndex)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unavailable = true
                return nil
            }
        }
        return Matcher(geometry: geometry, unavailableGeometry: unavailable, ranges: ranges, frame: frame)
    }

    struct Input: Sendable {
        let rows: [RegulatoryDataWorkbook.Row]
        let workbookSHA256: String
        var suggestedProjectID: UUID? = nil
        var suggestedDataset: String? = nil
        var suggestedFrame: Frame? = nil
        var bindings: [RegulatoryDataManifest.SourceBinding] = []
        var exportedAt: Date? = nil
    }

    struct Review: Sendable {
        var projectID: UUID?
        var dataset = ""
        var frame = Frame()
        var frameConfirmed = false
        var ranges: [UUID: ElevationRange] = [:]
        var geometryRules: [UUID: GeometryRule] = [:]
        var displayPlans: Set<UUID> = []
        var north: GeographicReference? = nil
        var assignments: [String: MappingContext] = [:]
        var resolutions: [FieldConflict: Choice] = [:]
    }

    enum Choice: String, CaseIterable, Sendable { case keepLocal, acceptExcel }

    struct FieldConflict: Hashable, Sendable {
        let observationID: UUID
        let column: Int
        let baseline: String
        let local: String
        let incoming: String
    }

    struct Change: Identifiable, Sendable {
        var id: Int { row }
        let sourceID: String
        let row: Int
        let kind: MappingExchangePreview.Classification
        let destination: MappingContext
        let reason: String
        var conflicts: [FieldConflict] = []
        var matchingIssue: MatchingIssue? = nil
        var automatic = false
    }

    struct Plan: Sendable {
        let generationID: UUID
        let workbookSHA256: String
        let changes: [Change]
        fileprivate let replacements: [UUID: RegulatorySourceObservation]
        fileprivate let ranges: [UUID: ElevationRange]
        fileprivate let projectID: UUID
        fileprivate let dataset: String
        fileprivate let settings: DatasetSettings?
        fileprivate var duplicateSourceIDs = false

        var blocked: Bool { (duplicateSourceIDs && changes.allSatisfy { $0.kind == .invalid }) || changes.contains { $0.kind == .conflict } }
        var canApply: Bool { !blocked && (!replacements.isEmpty || !ranges.isEmpty || settings != nil) }
        func count(_ kind: MappingExchangePreview.Classification) -> Int { changes.filter { $0.kind == kind }.count }
    }

    static func prepare(_ input: Input, review: Review, snapshot: MappingCommittedSnapshot, plans: ManagedPlanStore? = nil,
                        now: Date = Date()) throws -> Plan {
        if !input.bindings.isEmpty {
            return try prepareBound(input, review: review, snapshot: snapshot, now: now)
        }
        let dataset = review.dataset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let projectID = review.projectID, snapshot.projects[projectID] != nil,
              !dataset.isEmpty, dataset.utf8.count <= 256, review.frameConfirmed, review.frame.valid else {
            throw ExchangeImportError("Выберите проект, укажите постоянное имя набора данных и подтвердите метаданные координат.")
        }
        guard review.assignments.values.allSatisfy({ $0.projectID == projectID && snapshot.journal.validContext($0) }) else {
            throw ExchangeImportError("Контекст выбранных наблюдений не соответствует проекту.")
        }
        for (id, range) in review.ranges {
            guard let horizon = snapshot.horizons[id], horizon.projectID == projectID, range.valid,
                  range.datum == horizon.elevationDatum, range.datum == review.frame.verticalDatum else {
                throw ExchangeImportError("Проверьте границы отметок и совпадение вертикальных датумов.")
            }
        }
        let byKey = Dictionary(uniqueKeysWithValues: (snapshot.journal.regulatorySourceObservations ?? []).map { ($0.key, $0) })
        let previousSettings = snapshot.projects[projectID]?.regulatoryDatasets?[dataset]
        guard review.north.map(GeographicReference.manualChoices.contains) ?? true else { throw StorageError.invalidRecord }
        let frame = review.frame == Frame() ? previousSettings?.frame ?? review.frame : review.frame
        var settings = DatasetSettings(frame: frame, north: review.north ?? previousSettings?.north,
                                       plans: previousSettings?.plans ?? [:])
        for id in review.displayPlans.union(review.geometryRules.keys) {
            guard let plan = snapshot.plan(id: id), let file = plan.file,
                  snapshot.horizons[plan.horizonID]?.projectID == projectID else {
                throw ExchangeImportError("Выберите действующую ревизию DXF этого проекта.")
            }
            let rule = review.geometryRules[id]
            let association = PlanAssociation(horizonID: plan.horizonID, sha256: file.sha256, frame: review.frame,
                                              confirmedAt: now, geometry: rule)
            guard association.supportsXY(plan, frame: review.frame),
                  rule.map({ $0.valid && $0.frame == review.frame && $0.horizonID == plan.horizonID
                     && snapshot.horizons[plan.horizonID]?.elevationDatum == $0.frame.verticalDatum
                     && snapshot.journal.validContext(.init(projectID: projectID, horizonID: plan.horizonID, excavationID: $0.excavationID)) }) ?? true else {
                throw ExchangeImportError("Проверьте систему координат, оси, единицы и датум DXF.")
            }
            if settings.plans[id]?.frame != association.frame || settings.plans[id]?.geometry != rule ||
                settings.plans[id]?.horizonID != association.horizonID || settings.plans[id]?.sha256 != association.sha256 {
                settings.plans[id] = association
            }
        }
        let matcher = try matcher(projectID: projectID, frame: frame, associations: settings.plans,
                                  ranges: review.ranges, snapshot: snapshot, plans: plans)
        let counts = Dictionary(grouping: input.rows, by: { $0.values[0] }).mapValues(\.count)
        let duplicateSourceIDs = counts.values.contains { $0 > 1 }
        var changes: [Change] = []
        var replacements: [UUID: RegulatorySourceObservation] = [:]
        for row in input.rows {
            try Task.checkCancellation()
            let sourceID = row.values[0]
            let key = RegulatorySourceObservation.Key(projectID: projectID, dataset: dataset, sourceID: sourceID)
            let existing = byKey[key]
            guard row.issues.isEmpty, !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  sourceID.utf8.count <= 256, counts[sourceID] == 1 else {
                changes.append(.init(sourceID: sourceID, row: row.number, kind: .invalid,
                    destination: existing?.latest?.destination ?? .init(projectID: projectID),
                    reason: row.issues.isEmpty ? "Требуется уникальный текстовый ID источника." : row.issues.joined(separator: "\n")))
                continue
            }
            let id = try existing?.id ?? RegulatoryDataProposal.stableID("regulatory-source/" + MappingImportLedger.fingerprint(key))
            let old = existing?.latest
            let assigned = review.assignments[sourceID]
            var version = RegulatorySourceObservation.Version(workbookSHA256: input.workbookSHA256, sourceRow: row.number,
                cells: row.values, frame: old.map { $0.frame.canUse(frame) ? frame : $0.frame } ?? frame, destination: assigned ?? old?.destination ?? .init(projectID: projectID),
                explicitlyAssigned: assigned != nil || old?.explicitlyAssigned == true,
                resolution: assigned == nil ? old?.resolution : nil, savedAt: now)
            version.excavationManuallyAssigned = assigned == nil ? old?.excavationManuallyAssigned : nil
            version.north = old == nil ? settings.north : old?.north
            version.geometryEvidence = assigned == nil ? old?.geometryEvidence : nil
            if let existing, let old {
                let result = try reconcile(existing, incoming: version, comparison: old.sourceBaseline,
                    exported: false, resolutions: review.resolutions, matcher: matcher)
                if let revision = result.record { replacements[id] = revision }
                changes.append(result.change)
                continue
            }
            version.origin = .sourceImport
            if row.values.contains(ExchangeObservationProposal.clear) {
                version.importedCells = row.values
                for column in RegulatoryDataWorkbook.editable where version.cells[column] == ExchangeObservationProposal.clear {
                    version.cells[column] = ""
                }
            }
            matcher.resolve(&version)
            replacements[id] = .init(id: id, key: key, versions: [version])
            changes.append(change(sourceID: sourceID, row: row.number, kind: .new, version: version))
        }
        let saveSettings = previousSettings != settings && (previousSettings != nil ||
            review.frame != Frame() || settings.north != nil || !settings.plans.isEmpty)
        return Plan(generationID: snapshot.generationID, workbookSHA256: input.workbookSHA256, changes: changes,
                    replacements: replacements, ranges: review.ranges.filter { snapshot.horizons[$0.key]?.regulatoryElevationRange != $0.value },
                    projectID: projectID, dataset: dataset, settings: saveSettings ? settings : nil, duplicateSourceIDs: duplicateSourceIDs)
    }

    private static func change(sourceID: String, row: Int, kind: MappingExchangePreview.Classification,
                               version: RegulatorySourceObservation.Version) -> Change {
        let reason = version.matchingIssue?.title ?? (version.destination.horizonID == nil
            ? "Горизонт ожидает назначения." : version.explicitlyAssigned ? "Горизонт назначен вручную." : "Горизонт определён по подтверждённым данным проекта.")
        return .init(sourceID: sourceID, row: row, kind: kind, destination: version.destination,
                     reason: reason, matchingIssue: version.matchingIssue, automatic: version.resolution != nil)
    }

    private static func prepareBound(_ input: Input, review: Review, snapshot: MappingCommittedSnapshot, now: Date) throws -> Plan {
        let records = Dictionary(uniqueKeysWithValues: (snapshot.journal.regulatorySourceObservations ?? []).map { ($0.id, $0) })
        let rows = Dictionary(uniqueKeysWithValues: input.rows.map { ($0.number, $0) })
        let sharedSourceAnchors = Set(Dictionary(grouping: input.rows) { Array($0.values[0...4]) }
            .filter { $0.value.count > 1 }.keys)
        var changes: [Change] = []
        var replacements: [UUID: RegulatorySourceObservation] = [:]
        for binding in input.bindings {
            try Task.checkCancellation()
            guard let row = rows[binding.row], let record = records[binding.sourceObservationID], let old = record.latest,
                  record.key == .init(projectID: binding.projectID, dataset: binding.dataset, sourceID: binding.sourceID),
                  row.values[0] == record.key.sourceID else {
                throw ExchangeImportError("Data!A\(binding.row): исходный UUID или ID не соответствует журналу. Выгрузите книгу из этого журнала.")
            }
            let candidates: [RegulatorySourceObservation.Version]
            if let revision = binding.revision, record.versions.indices.contains(revision) {
                candidates = [record.versions[revision]]
            } else if binding.revision == nil, let exportedAt = input.exportedAt {
                candidates = record.versions.filter {
                    $0.savedAt <= exportedAt && $0.frame == binding.frame && $0.destination == binding.destination &&
                        $0.explicitlyAssigned == binding.explicitlyAssigned
                }
            } else { candidates = [] }
            guard let base = candidates.first, base.frame == binding.frame, base.destination == binding.destination,
                  base.explicitlyAssigned == binding.explicitlyAssigned,
                  binding.north == nil || base.north == binding.north,
                  candidates.allSatisfy({ $0.cells == base.cells }),
                  try binding.fingerprint.map({ try MappingImportLedger.fingerprint(base) == $0 }) ?? true else {
                throw ExchangeImportError("Data!A\(binding.row): исходную версию Excel нельзя определить. Выгрузите книгу заново.")
            }
            guard row.issues.isEmpty else {
                changes.append(.init(sourceID: record.key.sourceID, row: row.number, kind: .invalid,
                                     destination: old.destination, reason: row.issues.joined(separator: "\n")))
                continue
            }
            if sharedSourceAnchors.contains(Array(row.values[0...4])),
               row.values.indices.contains(where: { !row.values[$0].isEmpty &&
                   !RegulatorySourceObservation.Version.equal(row.values[$0], base.cells[$0], column: $0) }) {
                throw ExchangeImportError("Data!A\(binding.row): несколько исходных записей имеют одинаковые ID, PK и XYZ. Выгрузите изменяемые записи отдельно.")
            }
            var incoming = RegulatorySourceObservation.Version(workbookSHA256: input.workbookSHA256, sourceRow: row.number,
                cells: row.values, frame: old.frame, destination: old.destination, explicitlyAssigned: old.explicitlyAssigned,
                resolution: old.resolution, savedAt: now)
            incoming.excavationManuallyAssigned = old.excavationManuallyAssigned
            incoming.north = old.north
            incoming.matchingIssue = old.matchingIssue
            incoming.geometryEvidence = old.geometryEvidence
            let result = try reconcile(record, incoming: incoming, comparison: base.cells, exported: true,
                                       resolutions: review.resolutions)
            if let record = result.record { replacements[record.id] = record }
            changes.append(result.change)
        }
        return Plan(generationID: snapshot.generationID, workbookSHA256: input.workbookSHA256, changes: changes,
                    replacements: replacements, ranges: [:], projectID: input.bindings[0].projectID, dataset: "", settings: nil)
    }

    private static func reconcile(_ record: RegulatorySourceObservation, incoming: RegulatorySourceObservation.Version,
                                  comparison: [String], exported: Bool, resolutions: [FieldConflict: Choice],
                                  matcher: Matcher? = nil) throws -> (change: Change, record: RegulatorySourceObservation?) {
        guard let old = record.latest else { throw StorageError.invalidRecord }
        typealias Version = RegulatorySourceObservation.Version
        if exported && record.versions.contains(where: {
            $0.origin == .workbookEdit && $0.workbookSHA256 == incoming.workbookSHA256
        }) {
            return (change(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .unchanged, version: old), nil)
        }
        var next = incoming
        var retainedConflict = false
        var effective = old.cells
        var source = old.sourceBaseline
        var conflicts: [FieldConflict] = []
        let olderSource = !exported && record.versions.dropLast().contains { version in
            comparison.indices.allSatisfy { Version.equal(version.sourceBaseline[$0], incoming.cells[$0], column: $0) }
        }
        for column in comparison.indices {
            let raw = incoming.cells[column]
            // A blank worksheet cell leaves saved evidence intact. #CLEAR is explicit.
            if raw.isEmpty && (!exported || editableFields.contains(column)) { continue }
            let value = raw == ExchangeObservationProposal.clear ? "" : raw
            let base = comparison[column], local = old.cells[column]
            if Version.equal(value, base, column: column) { continue }
            if exported && !editableFields.contains(column) {
                return (.init(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .invalid,
                              destination: old.destination, reason: "Data!\(RegulatoryDataWorkbook.address(column, incoming.sourceRow)): поле исходных данных защищено."), nil)
            }
            let same = Version.equal(local, value, column: column)
            if !same && (olderSource || !Version.equal(local, base, column: column)) {
                let conflict = FieldConflict(observationID: record.id, column: column, baseline: base, local: local, incoming: value)
                guard let choice = resolutions[conflict] else { conflicts.append(conflict); continue }
                if choice == .acceptExcel { effective[column] = value }
                else { retainedConflict = true }
            } else if !same { effective[column] = value }
            // A generated workbook is another local editing surface. Its untouched
            // cells and its edits do not replace the independent production baseline.
            if !exported { source[column] = value }
        }
        let location = next.destination
        if !conflicts.isEmpty {
            return (.init(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .conflict,
                          destination: location, reason: "Выберите значение для каждого конфликта.", conflicts: conflicts), nil)
        }
        if exported {
            do {
                try validateEdits(effective, previous: old.cells, row: incoming.sourceRow)
            } catch {
                return (.init(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .invalid,
                              destination: location, reason: error.localizedDescription), nil)
            }
        }
        next.cells = effective
        if let matcher {
            if next.frame == matcher.frame { matcher.resolve(&next) }
            else if next.destination.horizonID == nil && !next.explicitlyAssigned { next.matchingIssue = .noVerifiedSources }
        }
        switch next.resolution {
        case .elevationRange(let range) where next.frame.verticalDatum != range.datum ||
            Double(effective[4]).map(range.contains) != true:
            next.resolution = .retained
        case .geometry where old.resolution != nil && (next.frame != old.frame || effective[2...4] != old.cells[2...4]):
            next.resolution = .retained
            next.geometryEvidence = nil
        default: break
        }
        if !(exported && retainedConflict) && effective == old.cells && source == old.sourceBaseline && next.frame == old.frame &&
            next.destination == old.destination && next.explicitlyAssigned == old.explicitlyAssigned &&
            next.resolution == old.resolution && next.matchingIssue == old.matchingIssue {
            return (change(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .unchanged, version: old), nil)
        }
        next.acceptedCells = source
        next.origin = exported ? .workbookEdit : .sourceImport
        next.importedCells = incoming.cells == effective ? nil : incoming.cells
        var revised = record
        revised.versions.append(next)
        return (change(sourceID: record.key.sourceID, row: incoming.sourceRow, kind: .correction, version: next), revised)
    }

    static let editableFields = [5, 6, 7, 8, 9, 10, 11, 12, 13] + Array(15...28)

    private static func validateEdits(_ cells: [String], previous: [String], row: Int) throws {
        for column in editableFields where cells[column] != previous[column] && !cells[column].isEmpty {
            let raw = cells[column]
            let field = "Data!\(RegulatoryDataWorkbook.address(column, row))"
            if column == 5 {
                try RockLithology(code: raw, name: nil).validate()
            } else {
                try RegulatoryDataProposal.validateSourceValue(raw, column: column, field: field)
            }
        }
    }

    static func editing(_ record: RegulatorySourceObservation, fields: [String], journal: MappingJournal,
                        north: GeographicReference? = nil, now: Date = Date()) throws -> MappingJournal {
        var next = journal
        guard let index = next.regulatorySourceObservations?.firstIndex(where: { $0.id == record.id }),
              var stored = next.regulatorySourceObservations?[index], stored == record, var version = stored.latest,
              fields.count == version.cells.count,
              fields.indices.allSatisfy({ editableFields.contains($0) || fields[$0] == version.cells[$0] }) else {
            throw ExchangeImportError("Наблюдение изменилось. Откройте редактор снова.")
        }
        var edited = version.cells
        for column in editableFields where !RegulatorySourceObservation.Version.equal(fields[column], version.cells[column], column: column) {
            edited[column] = fields[column]
        }
        guard north.map(GeographicReference.manualChoices.contains) ?? true else { throw StorageError.invalidRecord }
        guard edited != version.cells || (north != nil && north != version.north) else { return journal }
        try validateEdits(edited, previous: version.cells, row: version.sourceRow)
        version.acceptedCells = version.sourceBaseline
        version.cells = edited
        version.importedCells = nil
        if let north { version.north = north }
        version.origin = .localEdit
        version.savedAt = now
        stored.versions.append(version)
        next.regulatorySourceObservations?[index] = stored
        return next
    }

    static func applying(_ plan: Plan, to snapshot: MappingCommittedSnapshot) throws -> MappingJournal {
        try Task.checkCancellation()
        guard !plan.blocked, plan.generationID == snapshot.generationID else {
            throw ExchangeImportError("Проверьте книгу снова перед сохранением.")
        }
        var next = snapshot.journal
        if !plan.canApply { return next }
        let originals = next.regulatorySourceObservations ?? []
        let originalIDs = Set(originals.map(\.id))
        next.regulatorySourceObservations = originals.map { plan.replacements[$0.id] ?? $0 } +
            plan.replacements.values.filter { !originalIDs.contains($0.id) }.sorted { $0.versions[0].sourceRow < $1.versions[0].sourceRow }
        if let settings = plan.settings, let index = next.projects.firstIndex(where: { $0.id == plan.projectID }) {
            var datasets = next.projects[index].regulatoryDatasets ?? [:]
            datasets[plan.dataset] = settings
            next.projects[index].regulatoryDatasets = datasets
        }
        for i in next.horizons.indices {
            if let range = plan.ranges[next.horizons[i].id] { next.horizons[i].regulatoryElevationRange = range }
        }
        return next
    }

    static func assigning(_ ids: Set<UUID>, destination: MappingContext, journal: MappingJournal, now: Date = Date()) throws -> MappingJournal {
        guard !ids.isEmpty, journal.validContext(destination), destination.projectID != nil else { throw StorageError.invalidRecord }
        var next = journal
        var observations = journal.regulatorySourceObservations ?? []
        var found = Set<UUID>()
        for i in observations.indices where ids.contains(observations[i].id) {
            guard observations[i].key.projectID == destination.projectID, var version = observations[i].latest else {
                throw StorageError.invalidRecord
            }
            found.insert(observations[i].id)
            if version.destination == destination && version.explicitlyAssigned { continue }
            version.destination = destination
            version.explicitlyAssigned = true
            version.resolution = nil
            version.matchingIssue = nil
            version.geometryEvidence = nil
            version.excavationManuallyAssigned = nil
            version.importedCells = nil
            version.origin = .assignment
            version.savedAt = now
            observations[i].versions.append(version)
        }
        guard found == ids else { throw StorageError.invalidRecord }
        next.regulatorySourceObservations = observations
        return next
    }

    static func assigningExcavation(_ excavationID: UUID?, ids: Set<UUID>, projectID: UUID,
                                    journal: MappingJournal, now: Date = Date()) throws -> MappingJournal {
        var next = journal
        var observations = journal.regulatorySourceObservations ?? []
        var found = Set<UUID>()
        for i in observations.indices where ids.contains(observations[i].id) {
            guard var version = observations[i].latest, version.destination.projectID == projectID,
                  version.destination.horizonID != nil else { throw StorageError.invalidRecord }
            found.insert(observations[i].id)
            guard version.destination.excavationID != excavationID else { continue }
            version.destination.excavationID = excavationID
            guard journal.validContext(version.destination) else { throw StorageError.invalidRecord }
            version.excavationManuallyAssigned = true
            version.importedCells = nil
            version.origin = .assignment
            version.savedAt = now
            observations[i].versions.append(version)
        }
        guard !ids.isEmpty, found == ids else { throw StorageError.invalidRecord }
        next.regulatorySourceObservations = observations
        return next
    }

    static func rematching(projectID: UUID, dataset: String?, snapshot: MappingCommittedSnapshot,
                           plans: ManagedPlanStore?, now: Date = Date()) throws -> MappingJournal {
        var next = snapshot.journal
        guard let project = snapshot.projects[projectID], var observations = next.regulatorySourceObservations else { return next }
        var matchers: [String: Matcher] = [:]
        for i in observations.indices {
            try Task.checkCancellation()
            let key = observations[i].key
            guard key.projectID == projectID, dataset == nil || dataset == key.dataset,
                  let old = observations[i].latest, old.destination.horizonID == nil, !old.explicitlyAssigned else { continue }
            var version = old
            let settings = project.regulatoryDatasets?[key.dataset]
            if let frame = settings?.frame, old.frame.canUse(frame) { version.frame = frame }
            let match: Matcher
            if let cached = matchers[key.dataset], cached.frame == version.frame {
                match = cached
            } else {
                match = try matcher(projectID: projectID, frame: version.frame, associations: settings?.plans ?? [:],
                                    ranges: [:], snapshot: snapshot, plans: plans)
                matchers[key.dataset] = match
            }
            match.resolve(&version)
            guard version != old else { continue }
            version.savedAt = now
            version.origin = .assignment
            version.importedCells = nil
            observations[i].versions.append(version)
        }
        next.regulatorySourceObservations = observations
        return next
    }

    static func validate(journal: MappingJournal, context: MappingValidationContext) throws {
        for horizon in journal.horizons {
            if let range = horizon.regulatoryElevationRange, !range.valid || range.datum != horizon.elevationDatum {
                throw StorageError.invalidRecord
            }
        }
        for project in journal.projects {
            guard (project.regulatoryGeometryRules ?? [:]).values.allSatisfy(\.valid) else { throw StorageError.invalidRecord }
            for (name, dataset) in project.regulatoryDatasets ?? [:] {
                guard !name.isEmpty, name.utf8.count <= 256, dataset.frame.valid,
                      dataset.north.map(GeographicReference.manualChoices.contains) ?? true else { throw StorageError.invalidRecord }
                for (planID, association) in dataset.plans {
                    guard association.frame.valid, association.confirmedAt.timeIntervalSinceReferenceDate.isFinite,
                          let plan = context.plans[planID], plan.file?.sha256 == association.sha256,
                          plan.horizonID == association.horizonID,
                          context.horizons[association.horizonID]?.projectID == project.id,
                          association.geometry.map({ $0.valid && $0.frame == association.frame &&
                              $0.horizonID == association.horizonID &&
                              context.validContext(.init(projectID: project.id, horizonID: association.horizonID, excavationID: $0.excavationID)) }) ?? true else {
                        throw StorageError.invalidRecord
                    }
                }
            }
        }
        var ids = Set(journal.observations.map(\.id))
        var keys = Set<RegulatorySourceObservation.Key>()
        for record in journal.regulatorySourceObservations ?? [] {
            guard ids.insert(record.id).inserted, keys.insert(record.key).inserted, !record.versions.isEmpty,
                  !record.key.dataset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.key.dataset.utf8.count <= 256,
                  !record.key.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.key.sourceID.utf8.count <= 256 else { throw StorageError.invalidRecord }
            for (index, version) in record.versions.enumerated() {
                guard version.cells.count == RegulatoryDataWorkbook.columns.count,
                      version.cells[0] == record.key.sourceID,
                      version.sourceBaseline.count == version.cells.count,
                      version.sourceBaseline[0] == record.key.sourceID,
                      version.sourceBaseline.allSatisfy({ $0.utf16.count <= 32_767 }),
                      version.sourceBaseline[2...4].allSatisfy({ $0.isEmpty || RegulatoryDataWorkbook.sourceNumber($0) != nil }),
                      version.importedCells.map({ $0.count == version.cells.count && $0[0] == record.key.sourceID &&
                          $0.allSatisfy { $0.utf16.count <= 32_767 } }) ?? true,
                      version.cells.allSatisfy({ $0.utf16.count <= 32_767 }),
                      version.destination.projectID == record.key.projectID, context.validContext(version.destination),
                      version.north.map(GeographicReference.manualChoices.contains) ?? true,
                      version.matchingIssue == nil || version.destination.horizonID == nil,
                      version.frame.valid, version.savedAt.timeIntervalSinceReferenceDate.isFinite,
                      (5...1_048_576).contains(version.sourceRow),
                      version.workbookSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                      version.cells[2...4].allSatisfy({ $0.isEmpty || RegulatoryDataWorkbook.sourceNumber($0) != nil }),
                      version.sourceBaseline[2...4].allSatisfy({ $0.isEmpty || RegulatoryDataWorkbook.sourceNumber($0) != nil }) else {
                    throw StorageError.invalidRecord
                }
                if version.geometryEvidence != nil {
                    guard case .geometry = version.resolution else { throw StorageError.invalidRecord }
                }
                switch version.resolution {
                case .elevationRange(let range):
                    guard !version.explicitlyAssigned, version.destination.horizonID != nil, range.valid,
                          range.datum == version.frame.verticalDatum,
                          let z = version.xyz[2], range.contains(z) else { throw StorageError.invalidRecord }
                case .geometry(let planID, let sha256, let rule):
                    guard !version.explicitlyAssigned, rule.valid, rule.frame == version.frame,
                          rule.horizonID == version.destination.horizonID,
                          let plan = context.plans[planID], plan.horizonID == rule.horizonID,
                          plan.file?.sha256 == sha256,
                          version.excavationManuallyAssigned == true || version.destination.excavationID == nil ||
                              version.destination.excavationID == rule.excavationID else {
                        throw StorageError.invalidRecord
                    }
                    if let evidence = version.geometryEvidence {
                        guard let x = version.xyz[0], let y = version.xyz[1], let z = version.xyz[2],
                              let unit = PlanElevationSnap.metersPerUnit(plan),
                              let projection = evidence.segment.projection(.init(x: x, y: y)),
                              evidence.projectedZMeters == projection.z * unit,
                              evidence.xyDistanceMeters == projection.distance * unit,
                              evidence.zDifferenceMeters == abs(evidence.projectedZMeters - z),
                              evidence.xyDistanceMeters <= rule.maximumXYMeters, evidence.zDifferenceMeters <= rule.maximumZMeters else {
                            throw StorageError.invalidRecord
                        }
                    }
                case .retained:
                    guard !version.explicitlyAssigned, version.destination.horizonID != nil, index > 0,
                          record.versions[index - 1].destination.horizonID == version.destination.horizonID,
                          version.excavationManuallyAssigned == true || record.versions[index - 1].destination == version.destination,
                          record.versions[index - 1].resolution != nil else { throw StorageError.invalidRecord }
                case nil:
                    guard version.explicitlyAssigned || version.destination.horizonID == nil else { throw StorageError.invalidRecord }
                }
            }
        }
    }

    static func preserves(previous: MappingJournal, in current: MappingJournal) -> Bool {
        let currentByID = Dictionary(uniqueKeysWithValues: (current.regulatorySourceObservations ?? []).map { ($0.id, $0) })
        return (previous.regulatorySourceObservations ?? []).allSatisfy { old in
            guard let record = currentByID[old.id], old.key == record.key else { return false }
            return record.versions.starts(with: old.versions)
        }
    }
}
