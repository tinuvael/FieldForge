import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView("Журнал пуст", systemImage: "book.closed",
                                           description: Text("Зафиксируйте измерение кнопкой HOLD и нажмите «Сохранить»."))
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
                                    if record.sample.source == .simulatorMock {
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
                Text(record.orientation.status.explanation)
                LabeledContent("Источник", value: record.sample.source.title)
            }
            Section("Примечание") { Text(record.notes.isEmpty ? "Нет примечания" : record.notes) }
            Section("Диагностика") {
                LabeledContent("Система", value: record.sample.referenceFrame.rawValue)
                LabeledContent("Калибровка", value: record.sample.magneticAccuracy.title)
                LabeledContent("Магнитное поле, мкТл", value: CSVExporter.number(record.sample.magneticField.length))
                LabeledContent("Ускорение, g", value: CSVExporter.number(record.sample.userAcceleration.length))
                LabeledContent("Вращение, рад/с", value: CSVExporter.number(record.sample.rotationRate.length))
                Text("Нормаль NWU: \(vector(record.orientation.normal))")
                Text("Гравитация: \(vector(record.sample.gravity))")
                Text("Матрица R (по строкам): \(record.sample.rotation.elements.map { CSVExporter.number($0) }.joined(separator: " "))")
                Text("Кватернион XYZW: \([record.sample.quaternion.x, record.sample.quaternion.y, record.sample.quaternion.z, record.sample.quaternion.w].map { CSVExporter.number($0) }.joined(separator: " "))")
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
