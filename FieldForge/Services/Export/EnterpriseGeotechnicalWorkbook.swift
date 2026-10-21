import Foundation
import CoreFoundation

/// Saved effective observations only; no rating recalculation and no access to attachment bytes.
/// All historical revisions of selected observations are retained as scalar source records.
enum EnterpriseGeotechnicalWorkbook {
    typealias Cell = MappingCSVExport.Cell
    typealias Table = MappingCSVExport.Table
    static let version = "FieldForge-Enterprise-Geotechnical-XLSX/1"
    static func tables(points: [MappingObservation], journal: MappingJournal, projectID: UUID? = nil) throws -> [Table] {
        func t(_ value: String?) -> Cell { value.map(Cell.text) ?? .empty }
        func n(_ raw: String?) -> Cell { .number(raw.flatMap { try? RatingNumber.optional($0, name: "") }) }
        func north(_ reference: GeographicReference) -> String {
            switch reference { case .magneticNorth: return "Магнитный"; case .trueNorth: return "Истинный"; case .gridNorth: return "Сетка"; default: return "Неизвестно" }
        }
        func context(_ point: MappingObservation) -> [Cell] {
            [t(journal.projects.first { $0.id == point.projectID }?.name),
             t(journal.horizons.first { $0.id == point.horizonID }?.displayName),
             t(journal.excavations.first { $0.id == point.excavationID }?.name), .timestamp(point.observedAt), t(point.displayPicket)]
        }
        let faultCount = points.map { $0.geology?.tectonicStructures.count ?? 0 }.max() ?? 0
        var columns = ["Проект", "Горизонт", "Выработка", "Дата", "Пикет", "X", "Y", "Z, м", "Единицы XY", "СК", "Оси", "Источник координат", "ROCK · код", "ROCK · название", "RQD исходное, %", "Источник RQD для SD", "RQD · замечание", "Jn · исходный NGI 2025", "Jr · исходный NGI 2025", "Ja · исходный NGI 2025", "Jw · исходный NGI 2025", "SRF · исходный NGI 2025", "Q · NGI 2025", "RMR89 базовый", "Класс RMR89 базовый", "Полевая прочность R0–R6", "A1 · полевая прочность, балл", "Метод прочности RMR89", "Лабораторная прочность, МПа", "JCond76, балл", "GSI · нижняя граница", "GSI · верхняя граница", "GSI · уточнённый", "SD среднее, м", "Систем в среднем SD", "SD содержит оценки по RQD", "A42 · протяжённость, балл", "A43 · раскрытие, балл", "A45 · изменённость стенок, балл"]
        columns += JointSetIdentifier.allCases.flatMap { ["\($0.rawValue) азимут, °", "\($0.rawValue) падение, °", "\($0.rawValue) север", "\($0.rawValue) SD, м", "\($0.rawValue) источник SD"] }
        if faultCount > 0 {
            for i in 1...faultCount { columns += ["Тектоника \(i) · тип", "Тектоника \(i) · азимут, °", "Тектоника \(i) · падение, °", "Тектоника \(i) · север", "Тектоника \(i) · мощность, м", "Тектоника \(i) · описание"] }
        }
        columns += ["Описание Q", "RMR · прочность, источник", "RMR · состояние трещин", "Примечания", "UUID наблюдения", "UUID ревизии", "Версия наблюдения", "Метод Q", "Метод RMR89", "Метод GSI", "Дата GSI", "Jn · в расчёте Q", "Jr · в расчёте Q", "Ja · в расчёте Q", "Jw · в расчёте Q", "SRF · в расчёте Q"]
        var report = Table(name: "Геотех картирование", columns: columns)
        for point in points {
            try Task.checkCancellation()
            let q = point.ratings?.bartonQ, rmr = point.ratings?.rmr89, gsi = point.ratings?.gsi
            let rqd = SpacingRQD(q: q?.input ?? BartonQInput(), rmr: rmr?.input ?? RMR89Input())
            let sets = point.geology?.jointSets ?? [], mean = JointSpacingMean(sets)
            let c = point.coordinates, revision = journal.history(for: point.id).last
            // A42/A43 share exact published definitions with the explicitly selected RMR89 bands.
            // A45's last enterprise class is "crushed", not RMR89's "decomposed": no mapping for it.
            func enterprise(_ parameter: RMR89Parameter) -> Int? {
                guard let input = rmr?.input, let id = input.basicSelections?[parameter.rawValue],
                      parameter != .weathering || id != "weathering-4" else { return nil }
                return parameter.choices(test: input.strengthTest).first { $0.id == id }?.rating
            }
            var row = context(point)
            row += [.number(c?.x), .number(c?.y), .number(c?.z), t(c?.units), t(c?.crs), t(c?.axes), t(c?.source), t(point.rock?.code), t(point.rock?.name)]
            // Preserve Q's original RQD even when conflict prevents an SD estimate.
            row += [n(q?.input.rqd.isEmpty == false ? q?.input.rqd : rmr?.input.rqd), t(rqd.source.map { $0 == .bartonQOriginal ? "Barton Q · исходное" : "RMR89 · исходное (резерв)" }), t(rqd.warning)]
            row += [n(q?.input.jn.value), n(q?.input.jr.value), n(q?.input.ja.value), n(q?.input.jw.value), n(q?.input.srf.value), .number(q?.evaluation.result?.value)]
            row += [.integer(rmr?.calculation?.value), t(rmr?.calculation?.rockClass), t(rmr?.input.fieldStrength?.grade.rawValue), .integer(rmr?.input.fieldStrength?.rating), t(rmr?.input.strengthTest?.title), n(rmr?.input.strengthMPa), .integer(rmr?.input.jcond76?.rating)]
            row += [.number(gsi?.lower), .number(gsi?.upper), .number(gsi?.finalValue), .number(mean.value), .integer(mean.count), t(mean.includesEstimates ? "Да" : "Нет"), .integer(enterprise(.persistence)), .integer(enterprise(.aperture)), .integer(enterprise(.weathering))]
            for identifier in JointSetIdentifier.allCases {
                if let set = sets.first(where: { $0.identifier == identifier }) {
                    let orientation = try set.representative.validated().orientation
                    row += [.number(orientation.dipDirection), .number(orientation.dipAngle), t(north(set.representative.reference)), .number(set.spacingMeters), t((set.spacingProvenance?.source ?? .unknownLegacy).title)]
                } else { row += Array(repeating: .empty, count: 5) }
            }
            let faults = point.geology?.tectonicStructures ?? []
            for index in 0..<faultCount {
                if index < faults.count {
                    let fault = faults[index], orientation = try fault.orientation.validatedTectonic()
                    let names: [TectonicStructureType: String] = [.fault: "Разлом", .shearZone: "Зона сдвига", .fractureZone: "Зона трещиноватости", .other: "Другое"]
                    row += [t(names[fault.type]), .number(orientation.dipDirection), .number(orientation.dipAngle), t(north(fault.orientation.reference)), .number(fault.thicknessMeters), t(fault.description)]
                } else { row += Array(repeating: .empty, count: 6) }
            }
            row += [t(q?.input.geologicalDescription), t(rmr?.input.strengthEvidence), t(rmr.map { [$0.input.roughness, $0.input.infill, $0.input.weathering].joined(separator: "; ") }), t(point.notes), t(point.id.uuidString), t(revision?.id.uuidString ?? point.id.uuidString), .integer(revision?.version ?? 1)]
            let qResult = q?.evaluation.result
            row += [t(q?.method), t(rmr?.method), t(gsi?.method), .timestamp(gsi?.assessedAt), .number(qResult?.jn), .number(qResult?.jr), .number(qResult?.ja), .number(qResult?.jw), .number(qResult?.srf)]
            report.rows.append(row)
        }
        var references = Table(name: "Справочники", columns: ["Параметр", "Код / категория", "Описание / диапазон", "Балл", "Метод / версия / источник"])
        func reference(_ parameter: String, _ code: String, _ description: String, _ rating: Int?, _ method: String) {
            references.rows.append([t(parameter), t(code), t(description), .integer(rating), t(method)])
        }
        reference("Книга", version, "Одна актуальная версия наблюдения в строке первого листа. Выгрузка для анализа; не полная резервная копия. Исходные числа и история — на третьем листе.", nil, "FieldForge")
        reference("Исходные данные", "скалярные записи", "UUID записи + путь поля однозначно определяют исходное значение. Даты в исходных записях — секунды с 2001-01-01 UTC; полная точность чисел сохранена текстом. Отсутствующие необязательные поля опущены. Пути и значения перечислений — стабильные машинные коды.", nil, version)
        for grade in FieldStrengthGrade.allCases { reference("R0–R6 / A1", grade.rawValue, grade.interval + " МПа (оценочный интервал); " + grade.recognition, grade.rating, FieldStrengthGrade.version + "; регламент, приложение 6, таблица 6") }
        for category in JCond76Category.allCases { reference("JCond76", category.rawValue, category.title, category.rating, JCond76Category.version + "; Hoek, Carter & Diederichs (2013), Table 2; https://www.rocscience.com/assets/resources/learning/hoek/Quantification-of-the-GSI-Chart-2013.pdf") }
        for category in GSIStructure.allCases { reference("GSI · структура", category.rawValue, category.title + ": " + category.detail, nil, GSIAssessment.reference + "; " + GSIAssessment.version) }
        for category in GSISurface.allCases { reference("GSI · поверхность", category.rawValue, category.title + ": " + category.detail, nil, GSIAssessment.reference) }
        reference("GSI", "неприменимость", "Массивный × плохое / очень плохое; слоистый/рассланцованный × очень хорошее / хорошее. Числовые контуры не оцифрованы: интервал явно выбирает инженер. " + GSIAssessment.limitation, nil, GSIAssessment.version)
        for source in [JointSpacingSource.estimatedFromRQD, .manual, .unknownLegacy] { reference("SD · источник", source.rawValue, source.title, nil, source == .estimatedFromRQD ? PriestHudsonSpacing.version : "joint-spacing-entry-v1; отсутствующие метаданные = unknownLegacy") }
        reference("SD среднее, м", "среднее арифметическое", "Только положительные конечные SD сохранённых J1–J5. Пустые значения исключаются. Число использованных систем указано отдельно. Смесь оценок и ручного ввода не считается измеренным средним.", nil, version)
        reference("Оценка SD", "RQD = 100 exp(−0.1λ)(1+0.1λ); SD = 1/λ", "Бисекция для 0<RQD<100; без подстановки RQD=10%. Требуется отрицательно-экспоненциальное распределение. RQD не определяет истинное расстояние отдельной системы. При расхождении Q/RMR оценка недоступна.", nil, PriestHudsonSpacing.version + "; Priest & Hudson (1976), DOI 10.1016/0148-9062(76)90818-4; Brady & Brown (2004), 3.3–3.4")
        for (parameter, label) in [(RMR89Parameter.persistence, "A42"), (.aperture, "A43"), (.weathering, "A45")] {
            for choice in parameter.choices(test: nil) where parameter != .weathering || choice.id != "weathering-4" {
                reference(label, choice.id, choice.title, choice.rating, "Регламент, приложение 6, таблицы 3–4; явная категория RMR89")
            }
        }
        reference("A45", "0", "Раздробленные стенки. Не приравнивается автоматически к категории RMR89 «Разложившиеся»; без точных исходных данных поле пустое.", 0, "Регламент, приложение 6, таблица 4")
        reference("Barton Q", "NGI 2025", "Число Q и входные коэффициенты из сохранённой оценки; метод не изменён.", nil, QMethod.reference)
        reference("RMR89", "базовый", "Сохранённый расчёт; JCond76 в сумму не входит. Полевая категория не подменяется точным UCS; Is(50) не переводится в UCS.", nil, RMR89Assessment.reference)
        for rock in journal.projects.first(where: { $0.id == (projectID ?? points.first?.projectID) })?.lithologies ?? [] {
            reference("ROCK", rock.code, rock.name ?? "Без названия", nil, "Справочник проекта · код сохраняется точно")
        }
        return [report, references, try sources(points: points, journal: journal)]
    }

    private static func sources(points: [MappingObservation], journal: MappingJournal) throws -> Table {
        var table = Table(name: "Исходные данные", columns: ["Тип записи", "UUID записи", "UUID наблюдения", "UUID ревизии наблюдения", "Версия наблюдения", "Проект", "Горизонт", "Выработка", "Пикет", "Дата наблюдения UTC", "Путь поля", "Тип значения", "Число", "Текст / полная точность числа"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func append<T: Encodable>(_ record: T, kind: String, id: UUID, point: MappingObservation, revision: UUID, version: Int) throws {
            let object = try JSONSerialization.jsonObject(with: encoder.encode(record), options: [.fragmentsAllowed])
            let header: [Cell] = [.text(kind), .text(id.uuidString), .text(point.id.uuidString), .text(revision.uuidString), .integer(version),
                .text(journal.projects.first { $0.id == point.projectID }?.name ?? ""), .text(journal.horizons.first { $0.id == point.horizonID }?.displayName ?? ""), .text(journal.excavations.first { $0.id == point.excavationID }?.name ?? ""), .text(point.displayPicket), .timestamp(point.observedAt)]
            func leaf(_ path: String, _ type: String, _ numeric: Cell, _ text: String) {
                // Long user text is split losslessly into stable chunks; never truncate an Excel cell.
                let characters = Array(text), chunks = max(1, Int(ceil(Double(characters.count) / 1000)))
                for i in 0..<chunks {
                    let value = String(characters[(i * 1000)..<min(characters.count, (i + 1) * 1000)])
                    table.rows.append(header + [.text(path + (chunks > 1 ? "/часть/\(i + 1)" : "")), .text(type), numeric, .text(value)])
                }
            }
            func flatten(_ value: Any, path: String) throws {
                try Task.checkCancellation()
                if let dictionary = value as? [String: Any] {
                    for key in dictionary.keys.sorted() { try flatten(dictionary[key]!, path: path + "/" + key) }
                } else if let array = value as? [Any] {
                    if array.isEmpty { leaf(path, "Пустой массив", .empty, "[]") }
                    for (i, item) in array.enumerated() { try flatten(item, path: path + "/\(i)") }
                } else if let number = value as? NSNumber {
                    if CFGetTypeID(number) == CFBooleanGetTypeID() { leaf(path, "Логическое", .empty, number.boolValue ? "true" : "false") }
                    else { leaf(path, "Число", .number(number.doubleValue), number.stringValue) }
                } else if let string = value as? String { leaf(path, "Текст", .empty, string) }
                else { leaf(path, "Отсутствует", .empty, "") }
            }
            try flatten(object, path: "")
            if kind == "Наблюдение" || kind == "Исправление" {
                for joint in point.geology?.jointSets ?? [] {
                    leaf("/SD/\(joint.identifier.rawValue)/source", "Текст", .empty, (joint.spacingProvenance?.source ?? .unknownLegacy).rawValue)
                }
                let rqd = SpacingRQD(q: point.ratings?.bartonQ?.input ?? BartonQInput(), rmr: point.ratings?.rmr89?.input ?? RMR89Input())
                leaf("/SD/RQD/source", "Текст", .empty, rqd.source?.rawValue ?? "unavailable")
                leaf("/SD/RQD/warning", "Текст", .empty, rqd.warning ?? "")
            }
        }
        let selected = Set(points.map(\.id))
        for original in journal.observations.filter({ selected.contains($0.id) }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try append(original, kind: "Наблюдение", id: original.id, point: original, revision: original.id, version: 1)
            for correction in journal.history(for: original.id) {
                try append(correction, kind: "Исправление", id: correction.id, point: correction.snapshot, revision: correction.id, version: correction.version)
            }
            for measurement in journal.measurements(for: original) {
                try append(measurement, kind: "Замер", id: measurement.id, point: original, revision: original.id, version: 1)
            }
            for photo in journal.photos.filter({ $0.context.pointID == original.id }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                guard let photoPoint = journal.photoPoint(photo.context) else { throw StorageError.invalidRecord }
                try append(photo, kind: "Фото", id: photo.id, point: photoPoint, revision: photo.context.pointRevisionID, version: photo.context.pointVersion)
                for correction in journal.photoRevisions.filter({ $0.photoID == photo.id }) {
                    try append(correction, kind: "Исправление фото", id: correction.id, point: photoPoint, revision: photo.context.pointRevisionID, version: photo.context.pointVersion)
                }
                if let attachment = journal.photoAttachments.first(where: { $0.id == photo.attachmentID }) {
                    try append(attachment, kind: "Вложение фото · наличие не проверено", id: attachment.id, point: photoPoint, revision: photo.context.pointRevisionID, version: photo.context.pointVersion)
                }
            }
        }
        return table
    }
}
