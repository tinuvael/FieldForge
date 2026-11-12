import Foundation

/// Build a detached observation from Data cells. Empty cells preserve the local
/// value, including when an exported base is older than the journal.
enum RegulatoryDataProposal {
    typealias Row = RegulatoryDataWorkbook.Row
    static let clear = ExchangeObservationProposal.clear
    static let provenance = "Regulatory Excel Data A:AD"

    struct Assignment: Codable, Equatable, Sendable {
        var projectID: UUID?
        var horizonID: UUID?
        var excavationID: UUID?
        var observedAt: Date?
        var zoneID = TimeZone.current.identifier
        var convention: PicketConvention?
        var chainageOrigin = ""
        var planID: UUID?
        var north = GeographicReference.unknown
        var verticalSide = false
        var picketOverride = ""
        // Previously approved, exact-byte pending operations may carry this flag.
        var faultOrder = false
        var faultMatches: [String: UUID]?
        var canonicalFaultOrder: Bool?
        var resolvedChainage: Double?
        var acknowledgeDerived: Bool?
        var preservePrecision: Bool?
        var reviewKey: String?
        var resolvedRockCode: String?
    }

    struct FaultMatch: Identifiable, Sendable {
        let id: String
        let row: Int
        let values: String
        let choices: [MappingExchangePreview.MatchCandidate]
    }

    struct FaultMatchingRequired: Error {
        let matches: [FaultMatch]
    }

    static func makeNew(id: UUID, row: Row, assignment: Assignment, in current: MappingCommittedSnapshot) throws -> MappingObservation {
        guard let project = assignment.projectID, let horizon = assignment.horizonID,
              current.horizons[horizon]?.projectID == project,
              let date = assignment.observedAt, date.timeIntervalSinceReferenceDate.isFinite,
              let zone = TimeZone(identifier: assignment.zoneID), let convention = assignment.convention,
              !assignment.chainageOrigin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              assignment.chainageOrigin.utf8.count <= 512 else {
            throw ExchangeImportError("Задайте проект, горизонт, дату, систему и начало отсчёта пикетажа для новых наблюдений.")
        }
        let named = current.journal.excavations.filter {
            $0.projectID == project && $0.horizonIDs.contains(horizon) && $0.name == row.values[0]
        }
        let excavation = assignment.excavationID.flatMap { current.excavations[$0] } ?? (named.count == 1 ? named.first : nil)
        guard let excavation, excavation.projectID == project, excavation.horizonIDs.contains(horizon),
              row.values[0].isEmpty || excavation.name == row.values[0] else {
            throw ExchangeImportError("\(row.location(0)): выберите существующую выработку на указанном горизонте.")
        }
        let picket = row.values[1].isEmpty ? assignment.picketOverride : row.values[1]
        let chainage = try parsePicket(picket, convention: convention, row: row)
        return MappingObservation(id: id, projectID: project, horizonID: horizon, excavationID: excavation.id,
            picket: try convention.storedText(picket), chainageMeters: chainage, chainageOriginAndDirection: assignment.chainageOrigin,
            observedAt: date, observedTimeZoneID: zone.identifier, observedUTCOffsetSeconds: zone.secondsFromGMT(for: date),
            createdAt: date, updatedAt: date, coordinates: nil, measurementIDs: [], notes: "Источник наблюдения: \(provenance).",
            geology: nil, picketConvention: convention)
    }

    static func make(rows: [Row], point: MappingObservation, exported: MappingObservation?, exportedRows: [[String]],
                     assignment: Assignment, in current: MappingCommittedSnapshot, faultRows: inout [UUID: Int]) throws -> MappingObservation {
        let row = rows[0]
        let base = exportedRows[0]
        let old = exported == nil ? nil : point
        var patch = row.values
        for i in patch.indices where patch[i] == base[i] { patch[i] = "" }
        for column in RegulatoryDataWorkbook.protected where !patch[column].isEmpty {
            if old == nil && column == 0 { continue }
            let message = switch column {
            case 0: "Принадлежность существующего наблюдения сохраняется. Укажите исходную выработку."
            case 14: "SD — среднее сохранённых расстояний J1–J4. Исходные расстояния нельзя восстановить из среднего."
            default: "Для GSI необходима исходная оценка с методом и положением на диаграмме."
            }
            throw cellError(row, column, message)
        }
        let convention = point.picketConvention ?? .legacyMeters
        let picket = patch[1].isEmpty ? point.picket : try convention.storedText(patch[1])
        let chainage = patch[1].isEmpty ? point.chainageMeters : try parsePicket(patch[1], convention: convention, row: row)
        let coords = try coordinates(patch, point: point, assignment: assignment, in: current)
        var rock = point.rock
        if !patch[5].isEmpty {
            if patch[5] == clear { rock = nil }
            else {
                guard let found = current.projects[point.projectID]?.lithologies?.first(where: { $0.code == patch[5] }) else {
                    throw cellError(row, 5, "Точный текстовый код должен существовать в справочнике проекта.")
                }
                rock = found
            }
        }
        let ratings = try assessments(patch, row: row, point: point)
        let geology = try geology(rows, patch: patch, point: point, exported: exported, exportedRows: exportedRows,
                                  assignment: assignment, revision: current.latestRevisions[point.id]?.version ?? 1, faultRows: &faultRows)
        let proposal = MappingObservation(id: point.id, projectID: point.projectID, horizonID: point.horizonID, excavationID: point.excavationID,
            picket: picket, chainageMeters: chainage, chainageOriginAndDirection: point.chainageOriginAndDirection,
            observedAt: point.observedAt, observedTimeZoneID: point.observedTimeZoneID, observedUTCOffsetSeconds: point.observedUTCOffsetSeconds,
            createdAt: point.createdAt, updatedAt: point.updatedAt, coordinates: coords, measurementIDs: point.measurementIDs,
            notes: point.notes, geology: geology, ratings: ratings, picketConvention: point.picketConvention, rock: rock)
        try current.journal.validateObservation(proposal, context: MappingValidationContext(current.journal))
        return proposal
    }

    private static func parsePicket(_ text: String, convention: PicketConvention, row: Row) throws -> Double {
        do { return try convention.meters(text) }
        catch { throw cellError(row, 1, error.localizedDescription) }
    }

    static func coordinates(_ patch: [String], point: MappingObservation, assignment: Assignment,
                            in current: MappingCommittedSnapshot) throws -> MappingCoordinates? {
        let old = point.coordinates
        let xyEdit = !patch[2].isEmpty || !patch[3].isEmpty
        let zEdit = !patch[4].isEmpty
        guard xyEdit || zEdit else { return old }
        if xyEdit, !zEdit, old?.zOrigin == .planGeometry {
            throw ExchangeImportError("Data!C:E: при изменении XY укажите или явно очистите Z, ранее рассчитанную из DXF.")
        }
        func value(_ i: Int, _ previous: Double?) -> Double? {
            patch[i].isEmpty ? previous : Double(patch[i])
        }
        let x = value(2, old?.x), y = value(3, old?.y), z = value(4, old?.z)
        guard x != nil || y != nil || z != nil else { return nil }
        let existingPlan = old?.planID.flatMap { current.plan(id: $0) }
        let chosenPlan = xyEdit && existingPlan == nil ? assignment.planID.flatMap { current.plan(id: $0) } : nil
        if xyEdit && existingPlan == nil && assignment.planID != nil && chosenPlan == nil { throw StorageError.invalidRecord }
        if let chosenPlan, chosenPlan.horizonID != point.horizonID || chosenPlan.isDeleted || chosenPlan.file?.units == .unknown || chosenPlan.file == nil {
            throw ExchangeImportError("Data!C:D: выберите DXF текущего горизонта с подтверждёнными единицами.")
        }
        let plan = existingPlan ?? chosenPlan
        let file = plan?.file
        let source = plan == nil ? (xyEdit || old == nil ? "regulatoryExcel" : old?.source ?? "regulatoryExcel")
            : (xyEdit ? "manualInPlan" : old?.source ?? "manualInPlan")
        let origin = zEdit ? (z == nil ? nil : ElevationOrigin.manualOverride) : old?.zOrigin
        let priorProvenance = !xyEdit ? old?.provenance : nil
        let frame = plan.map { "user-confirmed drawing frame \($0.id.uuidString), revision \($0.version)" } ?? "XY frame unconfirmed"
        let provenance = priorProvenance ?? "\(Self.provenance); \(frame); accuracy unknown"
        return MappingCoordinates(x: x, y: y, z: z, crs: file?.crs ?? old?.crs ?? "unknown",
            axes: file?.axes ?? old?.axes ?? "unknown", units: file?.units.coordinateUnits ?? old?.units ?? "drawing",
            source: source, provenance: provenance, zOrigin: origin, zHorizonID: zEdit ? nil : old?.zHorizonID,
            zHorizonElevation: zEdit ? nil : old?.zHorizonElevation, zDatum: zEdit ? nil : old?.zDatum,
            planID: plan?.id, zPlanGeometry: zEdit ? nil : old?.zPlanGeometry)
    }

    /// Source records retain literal inputs. Use the same field tables and
    /// numerical constraints without selecting a classification or north datum.
    static func validateSourceValue(_ raw: String, column: Int, field: String) throws {
        guard let value = RegulatoryDataWorkbook.sourceNumber(raw) else {
            throw ExchangeImportError("\(field): требуется конечное десятичное число.")
        }
        let valid: Bool
        switch column {
        case 6: valid = RegulatoryWallAlteration.allCases.contains { Double($0.rating) == value }
        case 8: valid = RegulatoryStrengthBand.allCases.contains { Double($0.rating) == value }
        case 7, 11, 12, 13:
            let parameter: QParameter = switch column { case 7: .jw; case 11: .jn; case 12: .jr; default: .ja }
            valid = QMethod.rows(parameter).contains { ($0.minimum...$0.maximum).contains(value) }
        case 9, 20: valid = value >= 0
        case 10: valid = (0...100).contains(value)
        case 15, 17:
            let parameter: RMR89Parameter = column == 15 ? .aperture : .persistence
            valid = parameter.choices(test: nil).contains { Double($0.rating) == value }
        case 16: valid = JCond76Category.allCases.contains { Double($0.rating) == value }
        case 18, 21, 23, 25, 27: valid = ManualOrientationInput.dipAngleRange.contains(value)
        case 19, 22, 24, 26, 28: valid = ManualOrientationInput.dipDirectionRange.contains(value)
        default: valid = false
        }
        guard valid else { throw ExchangeImportError("\(field): значение вне допустимых пределов или категории.") }
    }

    private static func assessments(_ patch: [String], row: Row, point: MappingObservation) throws -> MappingRatings? {
        let previous = point.ratings
        var categories = previous?.regulatory ?? RegulatoryFieldCategories()
        var q = previous?.bartonQ?.input ?? BartonQInput()
        var r = previous?.rmr89?.input ?? RMR89Input()
        for (index, parameter) in [(7, QParameter.jw), (11, .jn), (12, .jr), (13, .ja)] where !patch[index].isEmpty {
            let value = patch[index]
            if value == clear { q[parameter] = QCoefficientInput(); continue }
            guard let number = Double(value) else { throw cellError(row, index, "Требуется числовой коэффициент.") }
            let candidates = QMethod.rows(parameter).filter { option in
                guard (option.minimum...option.maximum).contains(number) else { return false }
                if let contact = q.contact {
                    if parameter == .ja { return option.contact == contact }
                    if parameter == .jr { return (option.id == "H") == (contact == .noContact) }
                }
                return true
            }
            guard let choice = candidates.first(where: { $0.id == q[parameter].category }) ?? (candidates.count == 1 ? candidates.first : nil) else {
                throw cellError(row, index, "Коэффициент не определяет однозначную категорию NGI. Уточните категорию в журнале.")
            }
            var input = QCoefficientInput()
            input.select(choice.id, parameter: parameter)
            if choice.minimum != choice.maximum { input.value = ElevationInput.text(number) }
            input.evidence = provenance
            q[parameter] = input
        }
        if !patch[9].isEmpty {
            guard r.strengthTest == nil || r.strengthTest == .ucs else {
                throw cellError(row, 9, "Сохранён другой метод испытания. Уточните оценку UCS в журнале.")
            }
            r.strengthTest = patch[9] == clear ? r.strengthTest : .ucs
            r.strengthMPa = patch[9] == clear ? "" : ElevationInput.text(Double(patch[9])!)
            r.strengthEvidence = r.strengthMPa.isEmpty ? "" : provenance
        }
        if !patch[10].isEmpty {
            let value = patch[10] == clear ? "" : ElevationInput.text(Double(patch[10])!)
            guard q.rqd.isEmpty || r.rqd.isEmpty else {
                throw cellError(row, 10, "Сохранены два источника RQD. Уточните Q и RMR89 отдельно в журнале.")
            }
            if !r.rqd.isEmpty {
                r.rqd = value; r.rqdEvidence = value.isEmpty ? "" : provenance
            } else {
                q.rqd = value; q.rqdSource = value.isEmpty ? nil : .externalReport
                q.rqdEvidence = value.isEmpty ? "" : provenance
            }
        }
        for (index, parameter) in [(15, RMR89Parameter.aperture), (17, .persistence)] where !patch[index].isEmpty {
            var selections = r.basicSelections ?? [:]
            if patch[index] == clear { selections.removeValue(forKey: parameter.rawValue) }
            else {
                guard let choice = parameter.choices(test: r.strengthTest).first(where: { String($0.rating) == patch[index] }) else {
                    throw cellError(row, index, "Неизвестный балл категории RMR89.")
                }
                selections[parameter.rawValue] = choice.id
            }
            r.basicSelections = selections.isEmpty && r.basicSelections == nil ? nil : selections
        }
        if !patch[16].isEmpty {
            if patch[16] == clear { r.jcond76 = nil }
            else {
                guard let category = JCond76Category.allCases.first(where: { String($0.rating) == patch[16] }) else {
                    throw cellError(row, 16, "Неизвестный балл исторической категории JCond76.")
                }
                r.jcond76 = JCond76Assessment(category)
            }
        }
        if !patch[6].isEmpty {
            if patch[6] == clear {
                guard RegulatoryFieldCategories().wallAlterationRating(rmr: r) == nil else {
                    throw cellError(row, 6, "После очистки остаётся категория из RMR89.")
                }
                categories.wallAlteration = nil
            } else {
                guard let choice = RegulatoryWallAlteration.allCases.first(where: { String($0.rating) == patch[6] }) else {
                    throw cellError(row, 6, "Допустимые баллы A45: 6, 5, 3, 1, 0.")
                }
                categories.wallAlteration = choice
            }
        }
        if !patch[8].isEmpty {
            if patch[8] == clear {
                guard RegulatoryFieldCategories().strengthRating(rmr: r) == nil else {
                    throw cellError(row, 8, "После очистки остаётся полевая категория RMR89.")
                }
                categories.strength = nil
            } else {
                guard let choice = RegulatoryStrengthBand.allCases.first(where: { String($0.rating) == patch[8] }) else {
                    throw cellError(row, 8, "Допустимые баллы A1: 0, 1, 2, 4, 7, 12, 15.")
                }
                categories.strength = choice
            }
        }
        let nextQ: BartonQAssessment?
        if q == (previous?.bartonQ?.input ?? BartonQInput()) { nextQ = previous?.bartonQ }
        else {
            if q.assessmentSource.isEmpty { q.assessmentSource = provenance }
            do { nextQ = try BartonQAssessment(input: q, now: point.observedAt, method: previous?.bartonQ?.method ?? QMethod.fieldVersion) }
            catch { throw ExchangeImportError("Data, строка \(row.number) · Q: \(error.localizedDescription)") }
        }
        let nextRMR: RMR89Assessment?
        if r == (previous?.rmr89?.input ?? RMR89Input()) { nextRMR = previous?.rmr89 }
        else {
            if r.source.isEmpty { r.source = provenance }
            let method = previous?.rmr89?.method
            do {
                nextRMR = try RMR89Assessment(input: r, now: point.observedAt,
                    method: method == RMR89Assessment.version && r.basicSelections != nil ? RMR89Assessment.verifiedVersion : method)
            } catch { throw ExchangeImportError("Data, строка \(row.number) · RMR89: \(error.localizedDescription)") }
        }
        let regulatory = categories == (previous?.regulatory ?? RegulatoryFieldCategories()) ? previous?.regulatory
            : (categories.isEmpty ? nil : categories)
        if nextQ == nil, nextRMR == nil, previous?.gsi == nil, regulatory == nil {
            return previous == MappingRatings(bartonQ: nil, rmr89: nil) ? previous : nil
        }
        return MappingRatings(bartonQ: nextQ, rmr89: nextRMR, gsi: previous?.gsi, regulatory: regulatory)
    }

    private static func geology(_ rows: [Row], patch: [String], point: MappingObservation, exported: MappingObservation?,
                                exportedRows: [[String]], assignment: Assignment, revision: Int,
                                faultRows: inout [UUID: Int]) throws -> MappingGeology? {
        let prior = point.geology
        var sets = prior?.jointSets ?? []
        for (offset, identifier) in JointSetIdentifier.routine.enumerated() {
            let dip = 21 + offset * 2
            if patch[dip].isEmpty && patch[dip + 1].isEmpty { continue }
            let index = sets.firstIndex(where: { $0.identifier == identifier })
            let old = index.map { sets[$0] }
            let orientation = orientation(patch[dip], patch[dip + 1], previous: old?.representative, assignment: assignment)
            do { _ = try orientation.validated() }
            catch { throw cellError(rows[0], dip, error.localizedDescription) }
            let id = old?.id ?? stableID("\(point.id)/\(identifier.rawValue)/\(revision)")
            let set = InterpretedJointSet(id: id, identifier: identifier, revision: old?.revision ?? 1,
                interpretedAt: old?.interpretedAt ?? point.observedAt, author: old?.author, method: "user-interpretation-v1",
                representative: orientation, measurementIDs: old?.measurementIDs ?? [], spacingMeters: old?.spacingMeters,
                persistenceMeters: old?.persistenceMeters, apertureMillimeters: old?.apertureMillimeters,
                roughness: old?.roughness ?? "", infill: old?.infill ?? "", notes: old?.notes ?? provenance,
                spacingProvenance: old?.spacingProvenance)
            if let index { sets[index] = set } else { sets.append(set) }
        }
        let faults = try faults(rows, prior: prior?.tectonicStructures ?? [], baseline: exported?.geology?.tectonicStructures ?? [],
                               exportedRows: exportedRows, assignment: assignment, point: point, faultRows: &faultRows)
        guard prior != nil || !sets.isEmpty || !faults.isEmpty else { return nil }
        return MappingGeology(start: prior?.start, end: prior?.end, position: prior?.position, jointSets: sets, tectonicStructures: faults)
    }

    private static func faults(_ rows: [Row], prior: [TectonicStructure], baseline: [TectonicStructure],
                               exportedRows: [[String]], assignment: Assignment, point: MappingObservation,
                               faultRows: inout [UUID: Int]) throws -> [TectonicStructure] {
        let range = RegulatoryDataWorkbook.fault
        let base = Array(exportedRows.prefix(baseline.count)).map { Array($0[range]) }
        let input = rows.map { Array($0.values[range]) }
        if baseline.isEmpty && input.allSatisfy({ $0.allSatisfy(\.isEmpty) }) { return prior }
        if Dictionary(grouping: input, by: { $0 }).mapValues(\.count) ==
            Dictionary(grouping: base, by: { $0 }).mapValues(\.count) { return prior }
        if input.count == base.count, input.allSatisfy({ $0.allSatisfy(\.isEmpty) }) { return prior }
        guard prior == baseline else {
            throw ExchangeImportError("Data!S:U: структуры изменились в журнале. Для правки этих полей нужна новая выгрузка.")
        }
        var available = Set(baseline.indices)
        var matches: [Int: Int] = [:]
        for (index, value) in input.enumerated() {
            let exact = available.filter { base[$0] == value }
            if exact.count == 1, let match = exact.first {
                matches[index] = match; available.remove(match)
            }
        }
        let unmatched = rows.indices.filter { matches[$0] == nil }
        guard available.count <= unmatched.count else {
            throw ExchangeImportError("Data!S:U: отсутствуют сохранённые строки разломов. Удаление структур через Excel недоступно.")
        }
        if !available.isEmpty {
            if assignment.faultOrder {
                for (row, old) in zip(unmatched, available.sorted()) { matches[row] = old }
            } else {
                let candidates = available.sorted().map { index -> MappingExchangePreview.MatchCandidate in
                    let fault = baseline[index]
                    let values = faultValuesLabel(base[index])
                    let description = fault.description.isEmpty ? "" : " · " + fault.description
                    return .init(id: fault.id, label: values + description + " · " + fault.id.uuidString)
                }
                let requests = unmatched.map { index in
                    FaultMatch(id: faultKey(input[index]), row: rows[index].number,
                        values: faultValuesLabel(input[index]), choices: candidates)
                }
                let known = Dictionary(uniqueKeysWithValues: available.map { (baseline[$0].id, $0) })
                var used = Set<Int>()
                for (index, request) in zip(unmatched, requests) {
                    guard let chosen = assignment.faultMatches?[request.id], let old = known[chosen] else { continue }
                    guard used.insert(old).inserted else { throw FaultMatchingRequired(matches: requests) }
                    matches[index] = old
                }
                guard used == available else { throw FaultMatchingRequired(matches: requests) }
            }
        }
        var result = prior
        let order = assignment.canonicalFaultOrder == true
            ? input.indices.sorted { input[$0].lexicographicallyPrecedes(input[$1]) } : Array(input.indices)
        for index in order {
            let values = input[index]
            let oldIndex = matches[index]
            let old = oldIndex.map { baseline[$0] }
            if old == nil && values.allSatisfy({ $0.isEmpty || $0 == clear }) { continue }
            let previous = oldIndex.map { base[$0] } ?? ["", "", ""]
            let patch = zip(values, previous).map { $0 == $1 ? "" : $0 }
            if let old { faultRows[old.id] = rows[index].number }
            if patch.allSatisfy(\.isEmpty) { continue }
            let orientation = orientation(patch[0], patch[1], previous: old?.orientation, assignment: assignment)
            let thickness = patch[2].isEmpty ? old?.thicknessMeters : Double(patch[2])
            do { _ = try orientation.validatedTectonic() }
            catch { throw cellError(rows[index], 18, error.localizedDescription) }
            if let thickness, thickness < 0 { throw cellError(rows[index], 20, "Мощность в метрах должна быть неотрицательной.") }
            let id = old?.id ?? stableID("\(point.id)/fault/\(values.joined(separator: "|"))")
            let fault = TectonicStructure(id: id, type: old?.type ?? .fault, orientation: orientation,
                thicknessMeters: thickness, picket: old?.picket, position: old?.position ?? "", description: old?.description ?? provenance)
            faultRows[id] = rows[index].number
            if let oldIndex { result[oldIndex] = fault } else { result.append(fault) }
        }
        return result
    }

    private static func faultKey(_ values: [String]) -> String { values.joined(separator: "|") }

    private static func faultValuesLabel(_ values: [String]) -> String {
        zip(["F_DIP", "F_AZI", "F_THI"], values).map { "\($0) \($1.isEmpty ? "—" : $1)" }.joined(separator: " · ")
    }

    private static func orientation(_ dip: String, _ azimuth: String, previous: ManualOrientationInput?,
                                    assignment: Assignment) -> ManualOrientationInput {
        var result = previous ?? ManualOrientationInput(reference: assignment.north)
        if !dip.isEmpty { result.dipAngleText = dip == clear ? "" : dip }
        if !azimuth.isEmpty { result.dipDirectionText = azimuth == clear ? "" : azimuth }
        if Double(result.dipAngleText.replacingOccurrences(of: ",", with: ".")) == 90, !result.dipDirectionText.isEmpty {
            result.usesConventionalDipSide = (previous?.usesConventionalDipSide == true && azimuth.isEmpty) || assignment.verticalSide
        } else { result.usesConventionalDipSide = false }
        return result
    }

    static func stableID(_ key: String) -> UUID {
        let hash = ExchangeBaseline.hash(Data(key.utf8))
        let hex = Array(hash.prefix(32))
        let parts = [String(hex[0..<8]), String(hex[8..<12]), "8" + String(hex[13..<16]),
                     "a" + String(hex[17..<20]), String(hex[20..<32])]
        return UUID(uuidString: parts.joined(separator: "-"))!
    }

    private static func cellError(_ row: Row, _ column: Int, _ reason: String) -> ExchangeImportError {
        ExchangeImportError("\(row.location(column)) (\(RegulatoryDataWorkbook.columns[column])): \(reason)")
    }
}
