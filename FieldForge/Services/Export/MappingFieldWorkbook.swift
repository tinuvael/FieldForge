import Foundation

/// Human-readable sheets frozen at the same instant and with the same selection as
/// the relational export. Local row references join through field_links to exact UUIDs.
enum MappingFieldWorkbook {
    typealias Cell = MappingCSVExport.Cell
    typealias Table = MappingCSVExport.Table
    static func tables(points: [MappingObservation], photos: [PhotoObservation], journal: MappingJournal) throws -> [Table] {
        func text(_ value: String?) -> Cell { value.map(Cell.text) ?? .empty }
        func north(_ value: GeographicReference) -> String {
            switch value {
            case .magneticNorth: return "Магнитный"
            case .trueNorth: return "Истинный"
            case .gridNorth: return "Сетка"
            default: return "Неизвестно"
            }
        }
        let contextColumns = ["Проект", "Горизонт", "Выработка", "Пикет", "Наблюдение"]
        let pointRefs = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.id, "Н-\($0.offset + 1)") })
        func context(_ point: MappingObservation) -> [Cell] {
            [text(journal.projects.first { $0.id == point.projectID }?.name),
             text(journal.horizons.first { $0.id == point.horizonID }?.displayName),
             text(journal.excavations.first { $0.id == point.excavationID }?.name),
             text(point.displayPicket), text(pointRefs[point.id])]
        }
        var observation = Table(name: "Наблюдения", columns: contextColumns + ["Дата", "X", "Y", "Z, м", "Единицы XY"] + JointSetIdentifier.allCases.flatMap { ["\($0.rawValue) азимут, °", "\($0.rawValue) падение, °", "\($0.rawValue) север"] } + ["Q", "Категория по Q · FieldForge", "RMR89 базовый", "Класс RMR89 базовый", "Примечания", "GSI · оценка", "GSI · нижний контур / граница", "GSI · верхний контур / граница", "Метод GSI", "Дата GSI", "GSI X", "GSI Y", "Источник Z", "План Z · ревизия", "Метод Z", "Z · привязка, м", "Z · коэффициент в м", "Z · высотная система"])
        var joints = Table(name: "Системы трещин", columns: contextColumns + ["Система", "Азимут, °", "Падение, °", "Север", "Расстояние, м", "Протяжённость, м", "Раскрытие, мм", "Шероховатость", "Заполнитель", "Примечания"])
        var tectonics = Table(name: "Тектоника", columns: contextColumns + ["Структура", "Тип", "Азимут, °", "Падение, °", "Север", "Мощность, м", "Описание"])
        var ratings = Table(name: "Рейтинги массива", columns: contextColumns + ["Метод", "Дата оценки", "Q", "Класс Q · NGI", "Категория по Q · FieldForge", "RMR89 базовый", "Класс RMR89 базовый", "RQD, %", "Jn", "Jr", "Ja", "Jw", "SRF", "UCS / Is(50) / R0–R6", "Прочность, МПа", "Расстояние, м", "RMR балл прочности", "RMR балл RQD", "RMR балл расстояния", "RMR балл состояния", "RMR балл воды", "Категории RMR", "Пропуски", "RMR с ориентацией"])
        var photoTable = Table(name: "Фотографии", columns: contextColumns + ["Фото", "Название", "Номер", "Имя исходного файла", "Дата съёмки", "Дата импорта", "Описание", "Место съёмки", "Изображение в книге"])
        var links = Table(name: "field_links", columns: ["field_reference", "kind", "record_id", "point_id", "revision_id", "version"])
        for point in points {
            let ref = pointRefs[point.id]!, c = context(point), coordinates = point.coordinates
            let revision = journal.history(for: point.id).last
            links.rows.append([text(ref), text("observation"), text(point.id.uuidString), text(point.id.uuidString), text(revision?.id.uuidString ?? point.id.uuidString), .integer(revision?.version ?? 1)])
            let q = point.ratings?.bartonQ, rmr = point.ratings?.rmr89
            var row = c + [.timestamp(point.observedAt), .number(coordinates?.x), .number(coordinates?.y), .number(coordinates?.z), text(coordinates.map { MappingCoordinateText.xyUnit($0.units) })]
            for identifier in JointSetIdentifier.allCases {
                if let joint = point.geology?.jointSets.first(where: { $0.identifier == identifier }) {
                    let orientation = try joint.representative.validated().orientation
                    row += [.number(orientation.dipDirection), .number(orientation.dipAngle), text(north(joint.representative.reference))]
                } else { row += [.empty, .empty, .empty] }
            }
            row += [.number(q?.evaluation.result?.value), text(q?.evaluation.result.flatMap { FieldQCategory(q: $0.value)?.title }), .integer(rmr?.calculation?.value), text(rmr?.calculation?.rockClass), text(point.notes)]
            let gsi = point.ratings?.gsi
            row += [.number(gsi?.finalValue), .number(gsi?.lower), .number(gsi?.upper), text(gsi?.method), .timestamp(gsi?.assessedAt), .number(gsi?.chartPosition?.x), .number(gsi?.chartPosition?.y)]
            let z = coordinates?.zPlanGeometry
            row += [text(coordinates?.zOrigin?.title), text(z?.planRevision), text(z?.method), .number(z?.distanceMeters), .number(z?.metersPerDrawingUnit), text(z?.verticalDatum ?? coordinates?.zDatum)]
            observation.rows.append(row)
            for joint in point.geology?.jointSets ?? [] {
                let orientation = try joint.representative.validated().orientation
                joints.rows.append(c + [text(joint.identifier.rawValue), .number(orientation.dipDirection), .number(orientation.dipAngle), text(north(joint.representative.reference)), .number(joint.spacingMeters), .number(joint.persistenceMeters), .number(joint.apertureMillimeters), text(joint.roughness), text(joint.infill), text(joint.notes)])
                links.rows.append([text(ref + "/" + joint.identifier.rawValue), text("joint"), text(joint.id.uuidString), text(point.id.uuidString), .empty, .integer(joint.revision)])
            }
            let typeNames: [TectonicStructureType: String] = [.fault: "Разлом", .shearZone: "Зона сдвига", .fractureZone: "Зона трещиноватости", .other: "Другое"]
            for (index, structure) in (point.geology?.tectonicStructures ?? []).enumerated() {
                let orientation = try structure.orientation.validatedTectonic(), name = "Т-\(index + 1)"
                tectonics.rows.append(c + [text(name), text(typeNames[structure.type]), .number(orientation.dipDirection), .number(orientation.dipAngle), text(north(structure.orientation.reference)), .number(structure.thicknessMeters), text(structure.description)])
                links.rows.append([text(ref + "/" + name), text("structure"), text(structure.id.uuidString), text(point.id.uuidString), .empty, .empty])
            }
            func number(_ raw: String) -> Cell { .number(try? RatingNumber.optional(raw, name: "")) }
            if let q {
                let result = q.evaluation.result
                ratings.rows.append(c + [text("Barton Q · " + q.method), .timestamp(q.assessedAt), .number(result?.value), text(result?.rockClass?.title), text(result.flatMap { FieldQCategory(q: $0.value)?.title }), .empty, .empty, number(q.input.rqd), number(q.input.jn.value), number(q.input.jr.value), number(q.input.ja.value), number(q.input.jw.value), number(q.input.srf.value)] + Array(repeating: .empty, count: 9) + [text(q.evaluation.missing.joined(separator: ", ")), .empty])
            }
            if let rmr {
                let calculation = rmr.calculation
                let categories = RMR89Parameter.allCases.compactMap { parameter -> String? in
                    guard let id = rmr.input.basicSelections?[parameter.rawValue], let choice = parameter.choices(test: rmr.input.strengthTest).first(where: { $0.id == id }) else { return nil }
                    return "\(parameter.title): \(choice.title) (\(choice.rating))"
                }.joined(separator: "; ")
                var row = c + [text(rmr.method), .timestamp(rmr.assessedAt), .empty, .empty, .empty, .integer(calculation?.value), text(calculation?.rockClass), number(rmr.input.rqd)] + Array(repeating: Cell.empty, count: 5)
                row += [text(rmr.input.strengthTest == .ucs ? "UCS" : rmr.input.strengthTest == .pointLoadIs50 ? "Is(50)" : rmr.input.fieldStrength.map { $0.grade.rawValue + " · полевая оценка" }), number(rmr.input.strengthMPa), number(rmr.input.spacingMeters)]
                row += ["strength", "rqd", "spacing", "condition", "groundwater"].map { .integer(calculation?.components[$0]) }
                row += [text(categories), text(rmr.missing.joined(separator: ", ")), text("Не рассчитан")]
                ratings.rows.append(row)
            }
        }
        for (index, photo) in photos.enumerated() {
            guard let point = journal.photoPoint(photo.context) else { throw StorageError.invalidRecord }
            let metadata = journal.metadata(for: photo), attachment = journal.photoAttachments.first { $0.id == photo.attachmentID }
            let ref = "Ф-\(index + 1)"
            let location = photo.context.locationBasis == .unknownBeforeFirstSave ? "Неизвестно; связь с наблюдением не задаёт место съёмки" : "Контекст наблюдения, версия \(photo.context.pointVersion)"
            photoTable.rows.append(context(point) + [text(ref), text(metadata.name), text(metadata.number), text(attachment?.originalFilename), .timestamp(photo.capturedAt), .timestamp(photo.importedAt), text(metadata.description), text(location), text("Не включено; оригиналы — отдельный ZIP")])
            links.rows.append([text(ref), text("photo"), text(photo.id.uuidString), text(point.id.uuidString), text(photo.context.pointRevisionID.uuidString), .integer(photo.context.pointVersion)])
        }
        return [observation, joints, tectonics, ratings, photoTable, links]
    }
}
