import SwiftUI

struct MappingGeologyDetail: View {
    let geology: MappingGeology
    let measurements: [Measurement]
    var body: some View {
        Section("Интервал и положение") {
            LabeledContent("Начало", value: geology.start.map { "\($0.text) · \(CSVExporter.number($0.meters)) м" } ?? "Не указано")
            LabeledContent("Конец", value: geology.end.map { "\($0.text) · \(CSVExporter.number($0.meters)) м" } ?? "Не указано")
            LabeledContent("Положение", value: geology.position?.title ?? "Не указано")
        }
        Section("Системы трещин · интерпретации: \(geology.jointSets.count)") {
            ForEach(geology.jointSets) { set in
                DisclosureGroup("\(set.identifier.rawValue) · интерпретация") {
                    GeologicalOrientationDetail(input: set.representative)
                    number("Расстояние между трещинами, м", set.spacingMeters)
                    number("Протяжённость, м", set.persistenceMeters)
                    number("Раскрытие, мм", set.apertureMillimeters)
                    LabeledContent("Шероховатость", value: set.roughness.isEmpty ? "Не указана" : set.roughness)
                    LabeledContent("Заполнитель", value: set.infill.isEmpty ? "Не указан" : set.infill)
                    LabeledContent("Полевые примечания", value: set.notes.isEmpty ? "Нет" : set.notes)
                    LabeledContent("Автор", value: set.author ?? "Не указан")
                    LabeledContent("Интерпретировано", value: MeasurementDateText.format(set.interpretedAt, detailed: true))
                    Text("Ревизия \(set.revision) · \(set.method)").font(.caption)
                    Text("Исходные замеры: \(set.measurementIDs.count)").font(.subheadline)
                    ForEach(set.measurementIDs, id: \.self) { id in
                        if let reading = measurements.first(where: { $0.id == id }) {
                            NavigationLink { MeasurementDetailView(record: reading) } label: { MeasurementSummary(reading: reading) }
                                .accessibilityIdentifier("jointSource-\(set.identifier.rawValue)-\(id.uuidString)")
                        }
                    }
                    Text(set.id.uuidString).font(.caption).textSelection(.enabled)
                }.accessibilityIdentifier("savedJointSet-\(set.identifier.rawValue)")
            }
            if geology.jointSets.isEmpty { Text("Интерпретации не добавлены") }
        }
        Section("Тектоника: \(geology.tectonicStructures.count)") {
            ForEach(Array(geology.tectonicStructures.enumerated()), id: \.element.id) { index, structure in
                DisclosureGroup("№\(index + 1) · \(structure.type.title)") {
                    GeologicalOrientationDetail(input: structure.orientation)
                    number("Мощность, м", structure.thicknessMeters)
                    LabeledContent("Пикет структуры", value: structure.picket.map { "\($0.text) · \(CSVExporter.number($0.meters)) м" } ?? "Не указан")
                    LabeledContent("Положение структуры", value: structure.position.isEmpty ? "Не указано" : structure.position)
                    LabeledContent("Описание", value: structure.description.isEmpty ? "Нет" : structure.description)
                    Text(structure.id.uuidString).font(.caption).textSelection(.enabled)
                }.accessibilityIdentifier("savedTectonic-\(index + 1)")
            }
            if geology.tectonicStructures.isEmpty { Text("Структуры не добавлены") }
        }
    }
    private func number(_ title: String, _ value: Double?) -> some View {
        LabeledContent(title, value: value.map { CSVExporter.number($0) } ?? "Не указано")
    }
}

private struct GeologicalOrientationDetail: View {
    let input: ManualOrientationInput
    var body: some View {
        // Preserve the user's full precision and original 360°/decimal-comma spelling.
        LabeledContent("Угол падения, °", value: input.dipAngleText)
        LabeledContent("Азимут падения, °", value: input.dipDirectionText.isEmpty ? "Не определён" : input.dipDirectionText)
        LabeledContent("Вид севера", value: input.reference.title)
        if let value = try? input.validated() { Text(value.meaning.title).font(.caption) }
    }
}

extension DipDirectionMeaning {
    var title: String {
        switch self {
        case .downhill: return "Направление вниз по падению"
        case .undefined: return "Направление не определено"
        case .conventionalDipSide: return "Условная сторона вертикальной плоскости"
        }
    }
}
