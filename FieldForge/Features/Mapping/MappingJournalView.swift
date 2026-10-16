import SwiftUI

struct MappingJournalView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var byPicket = false
    private var observations: [MappingObservation] {
        (mapping.workflow?.observations ?? []).sorted {
            if byPicket, $0.chainageMeters != $1.chainageMeters { return $0.chainageMeters < $1.chainageMeters }
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var body: some View {
        List {
            Section {
                Text(mapping.workflow?.journal.projects.first { $0.id == mapping.workflow?.context.projectID }?.name ?? "Выберите проект в картировании")
                    .font(.headline)
                Picker("Сортировка", selection: $byPicket) {
                    Text("По дате").tag(false); Text("По пикету").tag(true)
                }.pickerStyle(.segmented)
            }
            if observations.isEmpty { Text("В выбранном проекте нет наблюдений") }
            ForEach(observations) { record in
                NavigationLink { MappingObservationDetail(record: record) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.picket).font(.headline)
                        Text(MappingDateText.format(record)).font(.subheadline)
                        Text("\(name(horizon: record.horizonID)) · \(name(excavation: record.excavationID))").font(.caption)
                    }.padding(.vertical, 4)
                }
            }
            Section("Независимые измерения") {
                NavigationLink("Неназначенный журнал Phase 1/2", destination: JournalView())
                Text("Исторические измерения не назначаются проекту автоматически.").font(.caption)
            }
        }.navigationTitle("Журнал проекта")
    }
    private func name(horizon: UUID) -> String { mapping.workflow?.journal.horizons.first { $0.id == horizon }?.displayName ?? horizon.uuidString }
    private func name(excavation: UUID) -> String { mapping.workflow?.journal.excavations.first { $0.id == excavation }?.name ?? excavation.uuidString }
}

enum MappingDateText {
    static func format(_ record: MappingObservation) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: record.observedUTCOffsetSeconds)
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss ZZZZZ"
        return formatter.string(from: record.observedAt)
    }
}

struct MappingObservationDetail: View {
    @EnvironmentObject private var mapping: MappingModel
    let record: MappingObservation
    var body: some View {
        List {
            Section("Исходное наблюдение · только просмотр") {
                LabeledContent("Проект", value: mapping.workflow?.journal.projects.first { $0.id == record.projectID }?.name ?? record.projectID.uuidString)
                LabeledContent("Горизонт", value: mapping.workflow?.journal.horizons.first { $0.id == record.horizonID }?.displayName ?? record.horizonID.uuidString)
                LabeledContent("Выработка", value: mapping.workflow?.journal.excavations.first { $0.id == record.excavationID }?.name ?? record.excavationID.uuidString)
                LabeledContent("Пикет", value: record.picket)
                LabeledContent("Метры", value: CSVExporter.number(record.chainageMeters))
                LabeledContent("Начало / направление", value: record.chainageOriginAndDirection == "unknown" ? "Неизвестно" : record.chainageOriginAndDirection)
                LabeledContent("Дата наблюдения", value: MappingDateText.format(record))
                Text(record.observedTimeZoneID)
            }
            Section("Координаты") {
                if let c = record.coordinates {
                    let xyUnit = c.units == "drawing" ? "ед. чертежа" : c.units == "mm" ? "мм" : "м"
                    LabeledContent("X, \(xyUnit)", value: c.x.map { CSVExporter.number($0) } ?? "Неизвестно")
                    LabeledContent("Y, \(xyUnit)", value: c.y.map { CSVExporter.number($0) } ?? "Неизвестно")
                    LabeledContent("Z, м", value: c.z.map { CSVExporter.number($0) } ?? "Неизвестно")
                    LabeledContent("СК", value: c.crs); LabeledContent("Оси / высоты", value: c.axes)
                    Text(c.provenance)
                    LabeledContent("Источник Z", value: c.zOrigin == .horizonDefault ? "По горизонту · не съёмка" : c.zOrigin == .manualOverride ? "Ручное значение" : "Не указан в исходной записи")
                    if let level = c.zHorizonElevation { Text("Исходная отметка: \(ElevationInput.label(level)); система: \(c.zDatum ?? "unknown")") }
                } else { Text("Координаты не заданы") }
            }
            Section("Примечания") { Text(record.notes.isEmpty ? "Нет примечаний" : record.notes) }
            Section("Метаданные") {
                LabeledContent("Создано", value: MeasurementDateText.format(record.createdAt, detailed: true))
                LabeledContent("Обновлено", value: MeasurementDateText.format(record.updatedAt, detailed: true))
                Text(record.id.uuidString).textSelection(.enabled)
                Text("Редактирование исходных наблюдений не реализовано. Контролируемые исправления с историей ревизий запланированы отдельно.")
            }.font(.caption)
        }.navigationTitle(record.picket).navigationBarTitleDisplayMode(.inline)
    }
}
