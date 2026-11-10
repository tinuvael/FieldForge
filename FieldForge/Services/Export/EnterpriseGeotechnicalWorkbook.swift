import Foundation

/// Data!A:AD reporting projection from the selected effective observations.
struct EnterpriseGeotechnicalWorkbook: Sendable {
    typealias Cell = MappingCSVExport.Cell
    typealias Table = MappingCSVExport.Table

    struct RQDConflict: Identifiable, Sendable {
        let id: UUID
        let excavation: String
        let picket: String
        let q: String
        let rmr: String
    }

    let table: Table
    let rqdConflicts: [RQDConflict]
    let spatialWarnings: [String]
    var requiresReview: Bool { !rqdConflicts.isEmpty || !spatialWarnings.isEmpty }

    private static let joints = JointSetIdentifier.routine
    static let columns = [
        "ID", "PK", "X", "Y", "Z", "ROCK", "A45", "JW", "A1", "UCS", "RQD", "JN", "JR", "JA", "SD", "A43",
        "JCON76", "A42", "F_DIP", "F_AZI", "F_THI", "J_DIP_1", "J_AZI_1", "J_DIP_2", "J_AZI_2",
        "J_DIP_3", "J_AZI_3", "J_DIP_4", "J_AZI_4", "GSI"
    ]
    static let headerRows: [[String]] = [
        ["КАРТИРОВАНИЕ ВЫРАБОТОК"],
        ["Место картирования", "", "", "", "", "Строение", "", "", "Прочность", "", "Структура", "",
         "Свойства трещин", "", "", "", "", "", "", "", "", "Ориентация трещиноватости", "", "", "", "", "", "",
         "", "Рейтинг массива"],
        ["Место картирования", "Пикетаж", "Координаты точек замеров", "", "", "Сокращенная литология",
         "Выветривание стенок трещин", "Обводненность", "Категория прочности пород", "Прочность породы, МПа",
         "Качество породы, %", "Количество систем трещин", "Шероховатость стенок трещин",
         "Сцепление стенок трещин", "Расстояние между трещинами, м", "Раскрытие трещин", "Свойства трещин",
         "Длина трещин", "Угол падения разлома, ° ", "Азимут падения разлома, °", "Мощность разлома, м"]
        + (1...4).flatMap { ["Угол падения \($0) й системы трещин, °", "Азимут падения \($0) й системы трещин, °"] }
        + ["GSI"],
        columns
    ]
    static let merges = ["A1:AD1", "A2:E2", "F2:H2", "I2:J2", "K2:L2", "M2:R2", "S2:U2", "V2:AC2", "C3:E3"]

    static func prepare(points: [MappingObservation], journal: MappingJournal) throws -> Self {
        let excavations = Dictionary(uniqueKeysWithValues: journal.excavations.map { ($0.id, $0.name) })
        var report = Table(name: "Data", columns: columns)
        var rqdConflicts: [RQDConflict] = []
        var spatial = SpatialReferences()
        for point in points {
            try Task.checkCancellation()
            guard let excavation = excavations[point.excavationID] else { throw StorageError.invalidRecord }
            let q = point.ratings?.bartonQ?.input
            let rmr = point.ratings?.rmr89?.input
            let regulatory = point.ratings?.regulatory ?? RegulatoryFieldCategories()
            let rqd = SpacingRQD(q: q ?? BartonQInput(), rmr: rmr ?? RMR89Input())
            let sets = (point.geology?.jointSets ?? []).filter { joints.contains($0.identifier) }
            let coordinates = point.coordinates
            let ucs = rmr?.strengthTest == .ucs ? number(rmr?.strengthMPa) : .empty
            // Valid saved assessments reach this branch when both original RQD inputs disagree.
            if rqd.source == nil, rqd.warning != nil, let q, let rmr {
                rqdConflicts.append(.init(id: point.id, excavation: excavation, picket: point.displayPicket, q: q.rqd, rmr: rmr.rqd))
            }
            if let coordinates { spatial.record(coordinates) }

            let beforeFault: [Cell] = [
                .text(excavation), .text(point.displayPicket),
                .number(coordinates?.x), .number(coordinates?.y), .number(coordinates?.z),
                point.rock.map { .text($0.code) } ?? .empty,
                .integer(regulatory.wallAlterationRating(rmr: rmr)), number(q?.jw.value),
                .integer(regulatory.strengthRating(rmr: rmr)), ucs, .number(rqd.value),
                number(q?.jn.value), number(q?.jr.value), number(q?.ja.value), .number(JointSpacingMean(sets).value),
                .integer(RegulatoryFieldCategories.sharedChoice(.aperture, rmr: rmr)?.rating), .integer(rmr?.jcond76?.rating),
                .integer(RegulatoryFieldCategories.sharedChoice(.persistence, rmr: rmr)?.rating)
            ]
            let jointOrientations: [Cell] = try joints.flatMap { identifier -> [Cell] in
                guard let set = sets.first(where: { $0.identifier == identifier }) else { return [.empty, .empty] }
                let orientation = try set.representative.validated().orientation
                if orientation.dipDirection != nil { spatial.north.insert(set.representative.reference) }
                return [.number(orientation.dipAngle), .number(orientation.dipDirection)]
            }
            let afterFault = jointOrientations + [.number(point.ratings?.gsi?.finalValue)]

            let faults = point.geology?.tectonicStructures ?? []
            if faults.isEmpty {
                report.rows.append(beforeFault + [.empty, .empty, .empty] + afterFault)
            }
            for fault in faults {
                try Task.checkCancellation()
                let orientation = try fault.orientation.validatedTectonic()
                if orientation.dipDirection != nil { spatial.north.insert(fault.orientation.reference) }
                report.rows.append(beforeFault + [
                    .number(orientation.dipAngle), .number(orientation.dipDirection), .number(fault.thicknessMeters)
                ] + afterFault)
            }
        }
        return Self(table: report, rqdConflicts: rqdConflicts, spatialWarnings: spatial.warnings)
    }

    private struct SpatialReferences {
        var units: Set<String?> = []
        var crs: Set<String?> = []
        var axes: Set<String?> = []
        var datum: Set<String?> = []
        var north: Set<GeographicReference> = []

        mutating func record(_ coordinates: MappingCoordinates) {
            if coordinates.x != nil || coordinates.y != nil {
                units.insert(coordinates.units == PlanUnits.unknown.coordinateUnits ? nil : coordinates.units)
                crs.insert(PlanCoordinateCompatibility.known(coordinates.crs))
                axes.insert(PlanCoordinateCompatibility.known(coordinates.axes))
            }
            if coordinates.z != nil {
                datum.insert((coordinates.zPlanGeometry?.verticalDatum ?? coordinates.zDatum).flatMap(PlanCoordinateCompatibility.known))
            }
        }

        var warnings: [String] {
            var result: [String] = []
            for (label, values) in [("Единицы XY", units), ("СК XY", crs), ("Оси XY", axes), ("Высотная система Z", datum)] {
                if values.contains(nil) { result.append("\(label): есть неизвестные значения.") }
                let known = values.compactMap { $0 }.sorted()
                if known.count > 1 { result.append("\(label): разные значения (\(known.joined(separator: ", "))).") }
            }
            if north.contains(.unknown) { result.append("Есть азимуты с неизвестным типом севера.") }
            let labels: [(GeographicReference, String)] = [(.magneticNorth, "магнитный"), (.trueNorth, "истинный"), (.gridNorth, "сеточный")]
            let present = labels.compactMap { north.contains($0.0) ? $0.1 : nil }
            if present.count > 1 { result.append("В азимутах используются разные типы севера: \(present.joined(separator: ", ")).") }
            return result
        }
    }

    private static func number(_ raw: String?) -> Cell {
        .number(raw.flatMap { try? RatingNumber.optional($0, name: "") })
    }

}
