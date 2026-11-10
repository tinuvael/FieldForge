import Foundation

/// Data!A:AD reporting projection from the selected effective observations.
enum EnterpriseGeotechnicalWorkbook {
    typealias Cell = MappingCSVExport.Cell
    typealias Table = MappingCSVExport.Table

    private static let joints: [JointSetIdentifier] = [.J1, .J2, .J3, .J4]
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

    static func table(points: [MappingObservation], journal: MappingJournal) throws -> Table {
        let excavations = Dictionary(uniqueKeysWithValues: journal.excavations.map { ($0.id, $0.name) })
        var report = Table(name: "Data", columns: columns)
        for point in points {
            try Task.checkCancellation()
            guard let excavation = excavations[point.excavationID] else { throw StorageError.invalidRecord }
            let q = point.ratings?.bartonQ?.input
            let rmr = point.ratings?.rmr89?.input
            let rqd = SpacingRQD(q: q ?? BartonQInput(), rmr: rmr ?? RMR89Input())
            let sets = (point.geology?.jointSets ?? []).filter { joints.contains($0.identifier) }
            let coordinates = point.coordinates
            let ucs = rmr?.strengthTest == .ucs ? number(rmr?.strengthMPa) : .empty

            let beforeFault: [Cell] = [
                .text(excavation), .text(point.displayPicket),
                .number(coordinates?.x), .number(coordinates?.y), .number(coordinates?.z),
                point.rock.map { .text($0.code) } ?? .empty,
                .integer(categoryRating(.weathering, rmr)), number(q?.jw.value),
                .integer(rmr?.fieldStrength?.rating), ucs, .number(rqd.value),
                number(q?.jn.value), number(q?.jr.value), number(q?.ja.value), .number(JointSpacingMean(sets).value),
                .integer(categoryRating(.aperture, rmr)), .integer(rmr?.jcond76?.rating),
                .integer(categoryRating(.persistence, rmr))
            ]
            let jointOrientations: [Cell] = try joints.flatMap { identifier -> [Cell] in
                guard let set = sets.first(where: { $0.identifier == identifier }) else { return [.empty, .empty] }
                let orientation = try set.representative.validated().orientation
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
                report.rows.append(beforeFault + [
                    .number(orientation.dipAngle), .number(orientation.dipDirection), .number(fault.thicknessMeters)
                ] + afterFault)
            }
        }
        return report
    }

    private static func number(_ raw: String?) -> Cell {
        .number(raw.flatMap { try? RatingNumber.optional($0, name: "") })
    }

    private static func categoryRating(_ parameter: RMR89Parameter, _ rmr: RMR89Input?) -> Int? {
        // The enterprise A45 zero denotes crushed walls. RMR89's last category denotes decomposed walls.
        guard let rmr, let id = rmr.basicSelections?[parameter.rawValue],
              parameter != .weathering || id != "weathering-4" else { return nil }
        return parameter.choices(test: rmr.strengthTest).first { $0.id == id }?.rating
    }
}
