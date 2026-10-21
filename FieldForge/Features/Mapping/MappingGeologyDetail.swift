import SwiftUI

struct MappingGeologyDetail: View {
    let geology: MappingGeology
    let measurements: [Measurement]
    var body: some View {
        Section("Интервал и положение") {
            LabeledContent("Начало", value: geology.start.map { "\($0.text) · \(EngineeringDisplay.number($0.meters)) м" } ?? "Не указано")
            LabeledContent("Конец", value: geology.end.map { "\($0.text) · \(EngineeringDisplay.number($0.meters)) м" } ?? "Не указано")
            LabeledContent("Положение", value: geology.position?.title ?? "Не указано")
        }
        Section("Системы трещин · интерпретации: \(geology.jointSets.count)") {
            ForEach(geology.jointSets) { set in
                DisclosureGroup("\(set.identifier.rawValue) · интерпретация") {
                    GeologicalOrientationDetail(input: set.representative)
                    number("SD, м", set.spacingMeters)
                    Text((set.spacingProvenance?.source ?? .unknownLegacy).title).font(.caption).foregroundStyle(.secondary)
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
                }
            }
            if geology.jointSets.isEmpty { Text("Интерпретации не добавлены") }
        }
        Section("Тектоника: \(geology.tectonicStructures.count)") {
            ForEach(Array(geology.tectonicStructures.enumerated()), id: \.element.id) { index, structure in
                DisclosureGroup("№\(index + 1) · \(structure.type.title)") {
                    GeologicalOrientationDetail(input: structure.orientation, permitsPartial: true)
                    number("Мощность, м", structure.thicknessMeters)
                    LabeledContent("Пикет структуры", value: structure.picket.map { "\($0.text) · \(EngineeringDisplay.number($0.meters)) м" } ?? "Не указан")
                    LabeledContent("Положение структуры", value: structure.position.isEmpty ? "Не указано" : structure.position)
                    LabeledContent("Описание", value: structure.description.isEmpty ? "Нет" : structure.description)
                    Text(structure.id.uuidString).font(.caption).textSelection(.enabled)
                }
            }
            if geology.tectonicStructures.isEmpty { Text("Структуры не добавлены") }
        }
    }
    private func number(_ title: String, _ value: Double?) -> some View {
        LabeledContent(title, value: value.map { EngineeringDisplay.number($0) } ?? "Не указано")
    }
}

private struct GeologicalOrientationDetail: View {
    let input: ManualOrientationInput
    var permitsPartial = false
    var body: some View {
        if permitsPartial { TectonicOrientationStatus(input: input) }
        // Preserve the user's full precision and original 360°/decimal-comma spelling.
        LabeledContent("Угол падения, °", value: input.dipAngleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Не определён" : input.dipAngleText)
        LabeledContent("Азимут падения, °", value: input.dipDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Не определён" : input.dipDirectionText)
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
