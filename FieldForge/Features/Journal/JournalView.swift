import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView("Журнал пуст", systemImage: "book.closed",
                                           description: Text("Сохраните ручную запись или зафиксируйте показания датчиков кнопкой HOLD."))
                } else {
                    List {
                        ForEach(model.records) { record in
                            NavigationLink {
                                MeasurementDetailView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(MeasurementDateText.format(record.timestamp)).font(.headline)
                                    Text("Азимут \(AngleText.format(record.orientation.dipDirection, azimuth: true)) · угол \(AngleText.format(record.orientation.dipAngle))")
                                        .monospacedDigit()
                                    Text("\(record.reference.title) · \(record.quality.title)").font(.caption)
                                        .foregroundStyle(record.quality.color)
                                    Text(record.source.title).font(.caption)
                                    if record.directionMeaning == .conventionalDipSide {
                                        Text("Условная сторона падения").font(.caption)
                                    }
                                    if record.source == .simulatorMock {
                                        Text("DEMO · Синтетическая запись").font(.caption.weight(.bold)).foregroundStyle(.orange)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }.onDelete(perform: model.delete)
                    }
                }
            }.navigationTitle("Журнал").toolbar { if !model.records.isEmpty { EditButton().accessibilityLabel("Править журнал") } }
        }
    }
}

struct MeasurementDetailView: View {
    let record: Measurement
    var body: some View {
        List {
            Section("Измерение") {
                LabeledContent("Время", value: MeasurementDateText.format(record.timestamp, detailed: true))
                LabeledContent("Азимут падения", value: AngleText.format(record.orientation.dipDirection, azimuth: true))
                LabeledContent("Угол падения", value: AngleText.format(record.orientation.dipAngle))
                LabeledContent("Опора", value: record.reference.title)
                LabeledContent("Качество", value: record.quality.title)
                Text(record.explanation)
                LabeledContent("Источник", value: record.source.title)
            }
            Section("Примечание") { Text(record.notes.isEmpty ? "Нет примечания" : record.notes) }
            if let input = record.manualInput {
                Section("Исходный ручной ввод") {
                    LabeledContent("Азимут", value: input.dipDirectionText.isEmpty ? "Не определён" : input.dipDirectionText)
                    LabeledContent("Угол", value: input.dipAngleText)
                    Text("Сенсорная диагностика отсутствует.")
                }
            }
            if let sample = record.sample {
                Section("Диагностика") {
                    LabeledContent("Система", value: sample.referenceFrame.rawValue)
                    LabeledContent("Калибровка", value: sample.magneticAccuracy.title)
                    LabeledContent("Магнитное поле, мкТл", value: CSVExporter.number(sample.magneticField.length))
                    LabeledContent("Ускорение, g", value: CSVExporter.number(sample.userAcceleration.length))
                    LabeledContent("Вращение, рад/с", value: CSVExporter.number(sample.rotationRate.length))
                    Text("Нормаль NWU: \(vector(record.orientation.normal))")
                    Text("Гравитация: \(vector(sample.gravity))")
                    Text("Матрица R (по строкам): \(sample.rotation.elements.map { CSVExporter.number($0) }.joined(separator: " "))")
                    Text("Кватернион XYZW: \([sample.quaternion.x, sample.quaternion.y, sample.quaternion.z, sample.quaternion.w].map { CSVExporter.number($0) }.joined(separator: " "))")
                }.font(.caption).monospacedDigit()
            }
            Section("Метаданные") {
                Text("Алгоритм: \(record.algorithmVersion)")
                Text(record.id.uuidString).textSelection(.enabled)
            }.font(.caption).monospacedDigit()
        }.navigationTitle("Запись").navigationBarTitleDisplayMode(.inline)
    }
    private func vector(_ v: Vector3?) -> String {
        guard let v else { return "—" }
        return [v.x, v.y, v.z].map { CSVExporter.number($0) }.joined(separator: "; ")
    }
}
