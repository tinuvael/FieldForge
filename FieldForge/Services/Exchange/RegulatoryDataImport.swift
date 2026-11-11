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
        if workbook.productionLayout {
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
        let originalBindings = manifest?.bindings ?? []
        let byAnchor = Dictionary(grouping: originalBindings) { Anchor($0.excavation ?? "", $0.picket ?? "") }
        let bindingsByID = Dictionary(uniqueKeysWithValues: originalBindings.map { ($0.target.observationID, $0) })
        let grouped = Dictionary(grouping: workbook.rows) { row -> [String] in
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
        let duplicateNumbers = Set(Dictionary(grouping: workbook.rows.filter { $0.issues.isEmpty }, by: \.values)
            .values.filter { $0.count > 1 }.flatMap { $0.map(\.number) })
        var records: [Record] = []
        for allRows in grouped.values.sorted(by: { $0[0].number < $1[0].number }) {
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
        return preview
    }

    private static func productionPreview(_ workbook: RegulatoryDataWorkbook.Read, source: MappingImportSource,
                                          committed: MappingCommittedSnapshot) -> Preview {
        let reasons = [
            "Data!A3:A4 «Место картирования» (ID) содержит идентификаторы источника. Они сохраняются отдельно от выработки.",
            "Data!B3:B4 «Пикетаж» (PK) может быть пустым. Укажите метаданные координат C:E для всего набора.",
            "Data!AD (GSI) содержит расчётные формулы. Data!O (SD) содержит сводное расстояние между трещинами. Эти поля требуют исходных данных для записи в журнал.",
            "В исходной книге остаются AE:AH (Q′, Q, RMR89, RMR76), AI (номер точки), AJ (примечание), AK:BB (вспомогательные оценки и входы), BI:CP (формулы проверки)."
        ]
        return Preview(source: source, rowsProcessed: workbook.rows.count, workbookBlocked: true,
                       workbookBlockReasons: reasons, worksheetRowsScanned: workbook.worksheetRowCount,
                       productionInput: .init(rows: workbook.rows, workbookSHA256: source.fingerprint),
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
                                source: MappingImportSource, review: Review, current: MappingCommittedSnapshot) throws -> Record {
        let first = rows[0]
        let numbers = rows.map { String($0.number) }.joined(separator: ", ")
        let location = "Data · строки \(numbers.prefix(400))"
        let label = "\(first.values[0]) · \(first.values[1])"
        let existingIDs = Set(suggestions.map(\.id))
        let userCreation = review.createSeparately.contains(key)
        var assignment = review.assignments[key] ?? review.assignment
        assignment.reviewKey = key
        assignment.picketOverride = review.pickets[key] ?? ""
        assignment.faultOrder = false
        assignment.faultMatches = review.faultMatches[key]
        assignment.canonicalFaultOrder = true
        if let receipt, receipt.outcome == .pending, let note = receipt.operation.note,
           let saved = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note) { assignment = saved }
        let selected = choice.flatMap { existingIDs.contains($0) ? $0 : nil } ?? unchanged
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
        let options = unchanged != nil || receipt != nil ? [] : Set(suggestions.map(\.id)).sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            current.observation(id: id).map { Preview.MatchCandidate(id: id, label: contextLabel($0, in: current)) }
        }
        let context = point.map { contextLabel($0, in: current) } ?? label
        let boundID = point.flatMap { binding?.target.observationID == $0.id ? boundKey($0.id) : nil }
        let id = receipt?.operation.sourceRecordID ?? boundID ?? key
        let uncertainCreation = unchanged == nil && (!options.isEmpty || missingOriginals)
        var actions = Actions(canCreateSeparately: uncertainCreation && receipt == nil,
            canSplit: rows.count > 1 && receipt == nil && (point == nil || rows.count > max(1, point?.geology?.tectonicStructures.count ?? 0)), needsPicket: point == nil && first.values[1].isEmpty,
            canFindExisting: unchanged == nil && receipt == nil && !review.findExisting.contains(key))
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
        let workbookSHA256: String
        let sourceRow: Int
        let cells: [String]
        let frame: RegulatorySourceImport.Frame
        var destination: MappingContext
        var explicitlyAssigned: Bool
        var resolution: RegulatorySourceImport.Resolution?
        var savedAt: Date

        var xyz: [Double?] { cells[2...4].map { Double($0) } }
        func sameEvidence(as other: Self) -> Bool {
            cells == other.cells && frame == other.frame
        }
    }

    let id: UUID
    let key: Key
    var versions: [Version]
    var latest: Version? { versions.last }
}

enum RegulatorySourceImport {
    struct Frame: Codable, Equatable, Sendable {
        var crs = ""
        var axes = ""
        var xyUnits = ""
        var verticalDatum = ""

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
    }

    private struct Geometry {
        let plan: MappingPlanReference
        let rule: GeometryRule
        let factor: Double
        let index: PlanElevationIndex

        func matches(_ point: PlanPoint, z: Double) -> Bool {
            index.nearby(point, radius: rule.maximumXYMeters / factor).contains { id in
                guard let sample = index.segments[id].projection(point) else { return false }
                return abs(sample.z * factor - z) <= rule.maximumZMeters
            }
        }
    }

    struct Input: Sendable {
        let rows: [RegulatoryDataWorkbook.Row]
        let workbookSHA256: String
    }

    struct Review: Sendable {
        var projectID: UUID?
        var dataset = ""
        var frame = Frame()
        var frameConfirmed = false
        var ranges: [UUID: ElevationRange] = [:]
        var geometryRules: [UUID: GeometryRule] = [:]
        var assignments: [String: MappingContext] = [:]
    }

    struct Change: Identifiable, Sendable {
        var id: Int { row }
        let sourceID: String
        let row: Int
        let kind: MappingExchangePreview.Classification
        let destination: MappingContext
        let reason: String
    }

    struct Plan: Sendable {
        let generationID: UUID
        let workbookSHA256: String
        let changes: [Change]
        fileprivate let replacements: [UUID: RegulatorySourceObservation]
        fileprivate let ranges: [UUID: ElevationRange]
        fileprivate let projectID: UUID
        fileprivate let geometryRules: [UUID: GeometryRule]

        var canApply: Bool {
            (!replacements.isEmpty || !ranges.isEmpty || !geometryRules.isEmpty) && !changes.contains { $0.kind == .conflict || $0.kind == .invalid }
        }
        func count(_ kind: MappingExchangePreview.Classification) -> Int { changes.filter { $0.kind == kind }.count }
    }

    static func prepare(_ input: Input, review: Review, snapshot: MappingCommittedSnapshot, plans: ManagedPlanStore? = nil,
                        now: Date = Date()) throws -> Plan {
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
        let ranges = snapshot.journal.horizons.compactMap { horizon -> (UUID, ElevationRange)? in
            guard horizon.projectID == projectID,
                  let range = review.ranges[horizon.id] ?? horizon.regulatoryElevationRange,
                  range.datum == review.frame.verticalDatum, range.datum == horizon.elevationDatum else { return nil }
            return (horizon.id, range)
        }
        let savedRules = snapshot.projects[projectID]?.regulatoryGeometryRules ?? [:]
        let rules = savedRules.merging(review.geometryRules) { _, confirmed in confirmed }
        let geometry = try rules.sorted { $0.key.uuidString < $1.key.uuidString }.compactMap { id, rule -> Geometry? in
            try Task.checkCancellation()
            let plan = snapshot.plan(id: id)
            guard rule.valid, rule.frame == review.frame,
                  let plan, !plan.isDeleted, !plan.isArchived, plan.horizonID == rule.horizonID,
                  snapshot.horizons[plan.horizonID]?.projectID == projectID,
                  snapshot.horizons[plan.horizonID]?.elevationDatum == rule.frame.verticalDatum,
                  snapshot.journal.validContext(.init(projectID: projectID, horizonID: plan.horizonID, excavationID: rule.excavationID)),
                  let file = plan.file, file.crs == rule.frame.crs, file.axes == rule.frame.axes,
                  file.units.coordinateUnits == rule.frame.xyUnits,
                  let factor = PlanElevationSnap.metersPerUnit(plan),
                  (rule.maximumXYMeters / factor).isFinite, let plans else {
                if review.geometryRules[id] != nil {
                    throw ExchangeImportError("Проверьте ревизию DXF, координатную систему, оси, единицы и подтверждённый датум.")
                }
                return nil
            }
            let document = try DXFDocument.parse(plans.read(plan))
            guard document.elevationIndex.segmentCount > 0, document.insertionUnits == file.insertionUnits else {
                throw ExchangeImportError("DXF не содержит подтверждённых высотных сегментов.")
            }
            return Geometry(plan: plan, rule: rule, factor: factor, index: document.elevationIndex)
        }
        var changes: [Change] = []
        var replacements: [UUID: RegulatorySourceObservation] = [:]
        var seen = Set<String>()
        for row in input.rows {
            try Task.checkCancellation()
            let sourceID = row.values[0]
            let key = RegulatorySourceObservation.Key(projectID: projectID, dataset: dataset, sourceID: sourceID)
            let existing = byKey[key]
            let id = try existing?.id ?? RegulatoryDataProposal.stableID("regulatory-source/" + MappingImportLedger.fingerprint(key))
            var destination = MappingContext(projectID: projectID)
            var explicit = false
            var resolution: Resolution?
            if let assigned = review.assignments[sourceID] {
                destination = assigned
                explicit = true
            } else if let old = existing?.latest, old.explicitlyAssigned {
                destination = old.destination
                explicit = true
            } else if let z = Double(row.values[4]) {
                let candidates: [Geometry]
                if let x = Double(row.values[2]), let y = Double(row.values[3]) {
                    candidates = geometry.filter { $0.matches(.init(x: x, y: y), z: z) }
                } else { candidates = [] }
                if let first = candidates.first {
                    if candidates.allSatisfy({ $0.plan.horizonID == first.plan.horizonID }) {
                        destination.horizonID = first.plan.horizonID
                        if candidates.allSatisfy({ $0.rule.excavationID == first.rule.excavationID }) {
                            destination.excavationID = first.rule.excavationID
                        }
                        resolution = .geometry(planID: first.plan.id, sha256: first.plan.file?.sha256 ?? "", rule: first.rule)
                    }
                } else {
                    var match: (UUID, ElevationRange)?
                    for candidate in ranges where candidate.1.contains(z) {
                        if match != nil { match = nil; break }
                        match = candidate
                    }
                    if let match {
                        destination.horizonID = match.0
                        resolution = .elevationRange(match.1)
                    }
                }
            }
            let version = RegulatorySourceObservation.Version(workbookSHA256: input.workbookSHA256, sourceRow: row.number,
                cells: row.values, frame: review.frame, destination: destination, explicitlyAssigned: explicit, resolution: resolution, savedAt: now)
            let kind: MappingExchangePreview.Classification
            let reason: String
            if !row.issues.isEmpty || sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                sourceID.utf8.count > 256 || !seen.insert(sourceID).inserted {
                kind = .invalid
                reason = row.issues.isEmpty ? "Требуется уникальный текстовый ID источника." : row.issues.joined(separator: "\n")
            } else if let existing, let old = existing.latest {
                if version.sameEvidence(as: old) && version.destination == old.destination &&
                    version.explicitlyAssigned == old.explicitlyAssigned {
                    kind = .unchanged
                    reason = "Источник уже сохранён."
                } else if !version.sameEvidence(as: old) && existing.versions.dropLast().contains(where: { $0.sameEvidence(as: version) }) {
                    kind = .conflict
                    reason = "Источник совпадает с предыдущей версией наблюдения."
                } else {
                    kind = .correction
                    reason = "Будет добавлена версия с сохранением исходного наблюдения."
                    var revised = existing
                    revised.versions.append(version)
                    replacements[id] = revised
                }
            } else {
                kind = .new
                reason = destination.horizonID == nil ? "Горизонт ожидает назначения." : "Горизонт определён по подтверждённым данным проекта."
                replacements[id] = .init(id: id, key: key, versions: [version])
            }
            changes.append(.init(sourceID: sourceID, row: row.number, kind: kind, destination: destination, reason: reason))
        }
        return Plan(generationID: snapshot.generationID, workbookSHA256: input.workbookSHA256, changes: changes,
                    replacements: replacements,
                    ranges: review.ranges.filter { snapshot.horizons[$0.key]?.regulatoryElevationRange != $0.value },
                    projectID: projectID, geometryRules: review.geometryRules.filter { savedRules[$0.key] != $0.value })
    }

    static func applying(_ plan: Plan, to snapshot: MappingCommittedSnapshot) throws -> MappingJournal {
        try Task.checkCancellation()
        guard plan.canApply, plan.generationID == snapshot.generationID else {
            throw ExchangeImportError("Проверьте книгу снова перед сохранением.")
        }
        var next = snapshot.journal
        let originals = next.regulatorySourceObservations ?? []
        let originalIDs = Set(originals.map(\.id))
        next.regulatorySourceObservations = originals.map { plan.replacements[$0.id] ?? $0 } +
            plan.replacements.values.filter { !originalIDs.contains($0.id) }.sorted { $0.versions[0].sourceRow < $1.versions[0].sourceRow }
        if !plan.geometryRules.isEmpty, let index = next.projects.firstIndex(where: { $0.id == plan.projectID }) {
            next.projects[index].regulatoryGeometryRules = (next.projects[index].regulatoryGeometryRules ?? [:])
                .merging(plan.geometryRules) { _, confirmed in confirmed }
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
            version.savedAt = now
            observations[i].versions.append(version)
        }
        guard found == ids else { throw StorageError.invalidRecord }
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
        }
        var ids = Set(journal.observations.map(\.id))
        var keys = Set<RegulatorySourceObservation.Key>()
        for record in journal.regulatorySourceObservations ?? [] {
            guard ids.insert(record.id).inserted, keys.insert(record.key).inserted, !record.versions.isEmpty,
                  !record.key.dataset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.key.dataset.utf8.count <= 256,
                  !record.key.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.key.sourceID.utf8.count <= 256 else { throw StorageError.invalidRecord }
            for version in record.versions {
                guard version.cells.count == RegulatoryDataWorkbook.columns.count,
                      version.cells[0] == record.key.sourceID,
                      version.cells.allSatisfy({ $0.utf16.count <= 32_767 }),
                      version.destination.projectID == record.key.projectID, context.validContext(version.destination),
                      version.frame.valid, version.savedAt.timeIntervalSinceReferenceDate.isFinite,
                      (5...1_048_576).contains(version.sourceRow),
                      version.workbookSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                      version.cells[2...4].allSatisfy({ $0.isEmpty || RegulatoryDataWorkbook.sourceNumber($0) != nil }) else {
                    throw StorageError.invalidRecord
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
                          version.destination.excavationID == nil || version.destination.excavationID == rule.excavationID else {
                        throw StorageError.invalidRecord
                    }
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
