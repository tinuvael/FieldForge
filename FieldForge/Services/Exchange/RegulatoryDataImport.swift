import Foundation

enum RegulatoryDataImport {
    typealias Preview = MappingExchangePreview
    typealias Record = Preview.Record
    typealias Row = RegulatoryDataWorkbook.Row

    struct Review: Sendable {
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
        var faultOrder = Set<String>()
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
        var canConfirmFaultOrder = false
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

    static func prepare(bytes: Data, matches: [String: UUID] = [:], review: Review = .init(), committed: MappingCommittedSnapshot,
                        limits: ExchangeLimits = .init()) throws -> Preview {
        let workbook = try RegulatoryDataWorkbook.Read(bytes: bytes, limits: limits)
        let manifest = workbook.manifest
        let documentID = workbook.documentID ?? manifest?.workbookID
        let source = MappingImportSource(kind: .regulatoryData,
            documentID: documentID?.uuidString ?? ExchangeBaseline.hash(bytes), bytes: bytes)
        var review = review
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
        var byRow: [Int: RegulatoryDataManifest.Binding] = [:]
        for binding in originalBindings {
            for row in binding.firstRow..<(binding.firstRow + binding.rowCount) { byRow[row] = binding }
        }
        let ledger = (committed.journal.importLedger?.entries ?? []).filter {
            $0.operation.source.kind == .regulatoryData && $0.operation.source.documentID == source.documentID
        }
        let receipts = Dictionary(grouping: ledger, by: \.operation.sourceRecordID)
        let duplicateNumbers = Set(Dictionary(grouping: workbook.rows.filter { $0.issues.isEmpty }, by: \.values)
            .values.filter { $0.count > 1 }.flatMap { $0.map(\.number) })
        let grouped = Dictionary(grouping: workbook.rows) { row -> [String] in
            // A missing A or B provides no common observation key.
            let common = RegulatoryDataWorkbook.common.map { row.values[$0] } + [row.numericRock ? "numeric-rock" : "text-rock"]
            return row.values[0].isEmpty || row.values[1].isEmpty ? common + [String(row.number)] : common
        }
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
                let original = Dictionary(grouping: allRows.filter { row in
                    guard let binding = byRow[row.number] else { return false }
                    return Anchor(binding.excavation ?? "", binding.picket ?? "") == anchor
                }, by: { byRow[$0.number]?.target.observationID })
                let retainedRows = Set(original.values.flatMap { $0.map(\.number) })
                groups = (Array(original.values) + allRows.filter { !retainedRows.contains($0.number) }.map { [$0] })
                    .sorted { $0[0].number < $1[0].number }
            } else { groups = [allRows] }
            for rows in groups {
                let first = rows[0]
                let anchor = Anchor(first.values)
                let key = try rowKey(rows)
                let legacy = try RegulatoryDataWorkbook.legacySignature(first.values)
                let bindingAtRow = byRow[first.number]
                let anchorBindings = byAnchor[anchor] ?? []
                let compatible = anchorBindings.filter { $0.signature == legacy }
                // A binding provides identity. The declared row positions or an exact
                // original projection corroborate it. Other candidates need a choice.
                let aligned = anchorBindings.filter { $0.firstRow == first.number }
                let bound = (aligned.count == 1 && (anchorBindings.count == 1 ||
                    compatible.count == 1 && compatible.first?.target == aligned.first?.target)) ? aligned.first : nil
                let possibleBindings = (anchorBindings + [bindingAtRow].compactMap { $0 })
                let bindingByID = Dictionary(possibleBindings.map { ($0.target.observationID, $0) },
                    uniquingKeysWith: { first, _ in first })
                let assignment = review.assignments[key] ?? review.assignment
                var suggested = (candidates[anchor] ?? []) + bindingByID.keys.compactMap { committed.observation(id: $0) }
                for convention in [PicketConvention.tenMeters, .legacyMeters] {
                    if let metres = try? convention.meters(anchor.picket) {
                        suggested += chainageCandidates[ChainageKey(excavation: anchor.excavation, convention: convention, metres: metres)] ?? []
                    }
                }
                if review.findExisting.contains(key) {
                    suggested += committed.effectiveObservations.filter {
                        (assignment.projectID == nil || assignment.projectID == $0.projectID) &&
                        (assignment.horizonID == nil || assignment.horizonID == $0.horizonID) &&
                        (assignment.excavationID == nil || assignment.excavationID == $0.excavationID)
                    }
                }
                let choice = review.matches[key]
                let matchedBinding = choice.flatMap { bindingByID[$0] } ?? bound
                let boundIDs = bindingByID.keys.map(boundKey)
                let ids = [matchedBinding.map { boundKey($0.target.observationID) }, Optional(key), Optional(legacy)].compactMap { $0 }
                let receipt = (ids + boundIDs.filter { !ids.contains($0) }).lazy.compactMap { id in
                    receipts[id]?.last { entry in
                        guard entry.operation.isMutation, entry.operation.source == source else { return false }
                        if let note = entry.operation.note,
                           let saved = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note) {
                            return saved.reviewKey == key
                        }
                        return ids.contains(id)
                    }
                }.first
                let record = try compare(key: key, rows: rows, suggestions: suggested,
                    binding: receipt.flatMap { bindingByID[$0.operation.target.observationID] } ?? matchedBinding, automatic: workbook.documentID != nil && bound != nil,
                    choice: choice, duplicate: rows.contains { duplicateNumbers.contains($0.number) },
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

    private static func rowKey(_ rows: [Row]) throws -> String {
        try RegulatoryDataWorkbook.identity(rows)
    }
    private static func boundKey(_ id: UUID) -> String { "point/\(id.uuidString)" }

    private static func compare(key: String, rows: [Row], suggestions: [MappingObservation],
                                binding: RegulatoryDataManifest.Binding?, automatic: Bool, choice: UUID?, duplicate: Bool,
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
        assignment.faultOrder = review.faultOrder.contains(key)
        if let note = receipt?.operation.note,
           let saved = try? ExchangeBaseline.decode(RegulatoryDataProposal.Assignment.self, note) { assignment = saved }
        let selected = choice.flatMap { existingIDs.contains($0) ? $0 : nil } ?? (automatic ? binding?.target.observationID : nil)
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
        let options = (automatic && !review.findExisting.contains(key)) || receipt != nil ? [] : Set(suggestions.map(\.id)).sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            current.observation(id: id).map { Preview.MatchCandidate(id: id, label: contextLabel($0, in: current)) }
        }
        let context = point.map { contextLabel($0, in: current) } ?? label
        let boundID = point.flatMap { binding?.target.observationID == $0.id ? boundKey($0.id) : nil }
        let id = receipt?.operation.sourceRecordID ?? boundID ?? key
        var actions = Actions(canCreateSeparately: !options.isEmpty && receipt == nil,
            canSplit: rows.count > 1 && receipt == nil && (point == nil || rows.count > max(1, point?.geology?.tectonicStructures.count ?? 0)), needsPicket: point == nil && first.values[1].isEmpty,
            canFindExisting: !automatic && receipt == nil && options.isEmpty)
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
        if let pending = previous.last(where: { $0.outcome == .pending }), pending.operation.source != source {
            return result(.conflict, "Для этой группы есть незавершённый импорт. Откройте исходный файл.")
        }
        if point == nil && !options.isEmpty && !userCreation && receipt == nil {
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
                    guard let original = try original(binding, current: current) else {
                        return result(.conflict, "Исходная версия из книги отсутствует в журнале.")
                    }
                    old = original
                    baseRows = try projected(original, current: current)
                    guard binding.excavation == baseRows[0][0], binding.picket == baseRows[0][1],
                          try RegulatoryDataWorkbook.legacySignature(baseRows[0]) == binding.signature else {
                        return result(.conflict, "Скрытый лист не соответствует исходной проекции журнала.")
                    }
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
            actions.canConfirmFaultOrder = point != nil && rows.count > 1
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
            let proposed = try RegulatoryDataProposal.make(rows: acceptedRows, point: target, exported: old, exportedRows: baseRows,
                assignment: assignment, in: current)
            let local = try point.map { try projected($0, current: current) } ?? baseRows
            let changes = try differences(key: id, rows: rows, before: local, proposed: proposed, previous: point, current: current)
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return result(.invalid, error.localizedDescription)
        }
    }

    private static func original(_ binding: RegulatoryDataManifest.Binding, current: MappingCommittedSnapshot) throws -> MappingObservation? {
        let snapshot: MappingObservation?
        if let revision = binding.baseline.revisionID {
            snapshot = current.journal.revisions.first { $0.id == revision && $0.version == binding.baseline.version }?.snapshot
        } else {
            snapshot = binding.baseline.version == 1 ? current.journal.observations.first { $0.id == binding.target.observationID } : nil
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
                                    previous: MappingObservation?, current: MappingCommittedSnapshot) throws -> [Preview.Change] {
        let after = try projected(proposed, current: current)
        var changes: [Preview.Change] = []
        for index in 0..<max(before.count, after.count) {
            let number = rows.indices.contains(index) ? rows[index].number : rows[0].number
            for column in RegulatoryDataWorkbook.columns.indices {
                if index > 0 && !RegulatoryDataWorkbook.fault.contains(column) { continue }
                let old = before.indices.contains(index) ? before[index][column] : ""
                let new = after.indices.contains(index) ? after[index][column] : ""
                guard old != new else { continue }
                let field = MappingXLSXExport.column(column + 1) + " · " + RegulatoryDataWorkbook.columns[column]
                changes.append(.init(sheet: "Data", record: key + "/\(index)", field: field, before: old, after: new, row: number))
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
