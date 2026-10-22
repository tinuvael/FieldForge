import Foundation

/// Changed field names; history links open complete, exact before/after snapshots.
enum MappingObservationDifference {
    static func fields(before: MappingObservation, after: MappingObservation) -> [String] {
        var result: [String] = []
        func changed<T: Equatable>(_ name: String, _ a: T, _ b: T) { if a != b { result.append(name) } }
        changed("Пикет: \(before.picket) → \(after.picket)", before.picket, after.picket)
        changed("Начало / направление пикетажа", before.chainageOriginAndDirection, after.chainageOriginAndDirection)
        changed("Полевая дата и время", before.observedAt, after.observedAt)
        changed("Часовой пояс наблюдения", before.observedTimeZoneID, after.observedTimeZoneID)
        changed("Смещение UTC наблюдения", before.observedUTCOffsetSeconds, after.observedUTCOffsetSeconds)
        func number(_ n: Double?) -> String { n.map(ElevationInput.text) ?? "неизвестно" }
        let a = before.coordinates, b = after.coordinates
        for (label, old, new) in [("X", a?.x, b?.x), ("Y", a?.y, b?.y), ("Z, м", a?.z, b?.z)] {
            changed("\(label): \(number(old)) → \(number(new))", old, new)
        }
        changed("СК", a?.crs, b?.crs); changed("Оси", a?.axes, b?.axes); changed("Единицы XY", a?.units, b?.units)
        changed("Источник координат", a?.source, b?.source); changed("Происхождение координат", a?.provenance, b?.provenance)
        changed("Версия плана (UUID)", a?.planID, b?.planID); changed("Источник Z", a?.zOrigin, b?.zOrigin)
        changed("Исходный горизонт Z", a?.zHorizonID, b?.zHorizonID)
        changed("Исходная отметка горизонта Z", a?.zHorizonElevation, b?.zHorizonElevation)
        changed("Высотная система", a?.zDatum, b?.zDatum)
        changed("Источник геометрии Z", a?.zPlanGeometry, b?.zPlanGeometry)
        changed("Начало интервала", before.geology?.start, after.geology?.start)
        changed("Конец интервала", before.geology?.end, after.geology?.end)
        changed("Положение наблюдения", before.geology?.position, after.geology?.position)
        for identifier in JointSetIdentifier.allCases {
            let old = before.geology?.jointSets.first { $0.identifier == identifier }
            let new = after.geology?.jointSets.first { $0.identifier == identifier }
            let label = identifier.rawValue
            if old == nil || new == nil { changed("\(label) · добавлена / удалена интерпретация", old, new); continue }
            changed("\(label) · идентификатор интерпретации", old?.id, new?.id)
            changed("\(label) · ориентация и север", old?.representative, new?.representative)
            changed("\(label) · ссылки на исходные замеры", old?.measurementIDs, new?.measurementIDs)
            changed("\(label) · расстояние", old?.spacingMeters, new?.spacingMeters)
            changed("\(label) · источник SD", old?.spacingProvenance, new?.spacingProvenance)
            changed("\(label) · протяжённость", old?.persistenceMeters, new?.persistenceMeters)
            changed("\(label) · раскрытие", old?.apertureMillimeters, new?.apertureMillimeters)
            changed("\(label) · шероховатость", old?.roughness, new?.roughness)
            changed("\(label) · заполнитель", old?.infill, new?.infill)
            changed("\(label) · примечания", old?.notes, new?.notes)
            changed("\(label) · автор интерпретации", old?.author, new?.author)
        }
        let oldFaults = before.geology?.tectonicStructures ?? [], newFaults = after.geology?.tectonicStructures ?? []
        for (index, old) in oldFaults.enumerated() {
            let label = "Тектоника №\(index + 1)"
            guard let new = newFaults.first(where: { $0.id == old.id }) else { result.append("\(label) · удалена из новой версии"); continue }
            changed("\(label) · тип", old.type, new.type); changed("\(label) · ориентация и север", old.orientation, new.orientation)
            changed("\(label) · мощность: \(number(old.thicknessMeters)) → \(number(new.thicknessMeters)) м", old.thicknessMeters, new.thicknessMeters)
            changed("\(label) · пикет", old.picket, new.picket); changed("\(label) · положение", old.position, new.position)
            changed("\(label) · описание", old.description, new.description)
        }
        if newFaults.contains(where: { new in !oldFaults.contains { $0.id == new.id } }) { result.append("Добавлены тектонические структуры") }
        changed("Barton Q · исходные данные и оценка NGI 2025", before.ratings?.bartonQ, after.ratings?.bartonQ)
        changed("RMR89 · исходные данные и базовая оценка", before.ratings?.rmr89, after.ratings?.rmr89)
        changed("GSI · геологическая оценка", before.ratings?.gsi, after.ratings?.gsi)
        changed("ROCK · код и название", before.rock, after.rock)
        changed("Примечания", before.notes, after.notes)
        return result.isEmpty ? ["Полевые значения не изменены"] : result
    }
}
