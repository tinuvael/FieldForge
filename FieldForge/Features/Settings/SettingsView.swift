import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var export: ExportFile?
    var body: some View {
        Form {
            Section("О прототипе") {
                Text("FieldForge — экспериментальное приложение. Оно ещё не валидировано для профессиональных геологических измерений.")
                    .foregroundStyle(.orange)
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
            Section("Датчики") { Text(model.provider.information) }
            Section("Обслуживание данных") {
                NavigationLink("Резервное копирование", destination: BackupView())
                DisclosureGroup("Дополнительно") {
                    NavigationLink("Независимое измерение", destination: MeasurementView())
                    NavigationLink("Исходный журнал измерений", destination: JournalView())
                }
            }
            Section("Ручной ввод") {
                Text("Магнитный, истинный и сеточный азимуты не пересчитываются.")
                Text("При 0° оставьте азимут пустым. При 90° можно явно задать условную сторону падения. Ручные записи и показания датчиков хранятся в общем журнале.")
            }
            Section("Плоскость измерения") {
                LabeledContent("Активная плоскость", value: "Экран iPhone")
                Text("Расположите плоскость экрана параллельно измеряемой поверхности. Используйте держатель: корпус и блок камер не обеспечивают ровного контакта.")
            }
            Section("Магнитный север") {
                Text("Азимут отсчитывается по часовой стрелке от магнитного севера; поправка на склонение не применяется.")
                Text("При низкой или средней калибровке, отсутствии севера или подозрительном поле азимут скрыт. Высокая калибровка не гарантирует отсутствие магнитных помех.")
                Text("Горизонтальная и вертикальная плоскости в пределах 0,5° не имеют однозначного направления падения в принятом определении. Угол остаётся доступен.")
            }
            Section("Калибровка и помехи") {
                Text("Следуйте системной подсказке движения телефона. Уберите магнитные чехлы и держатели; отойдите от металла, машин, кабелей и электрооборудования.")
                Text("В шахте магнитная опора может быть ненадёжной. Сравнивайте повторные измерения и геологический компас. Калибровка не исправляет внешнее магнитное поле.")
                Text("Не двигайте телефон во время фиксации. Порог движения: 0,05 g или 0,1 рад/с. Эти пороги экспериментальные и не задают точность.")
            }
            Section("Экспорт") {
                Button {
                    do { export = ExportFile(url: try CSVExporter.writeTemporaryFile(model.records)) }
                    catch { model.errorMessage = "Ошибка экспорта: \(error.localizedDescription)" }
                } label: { Label("Экспортировать CSV (\(model.records.count))", systemImage: "square.and.arrow.up") }
                .disabled(model.records.isEmpty).accessibilityIdentifier("exportButton")
                DisclosureGroup("Формат CSV") {
                    Text("UTF-8 с BOM, запятая, десятичная точка, время UTC. Источник и вид севера указаны для каждой записи.").font(.caption)
                }
            }
            DisclosureGroup("Технические сведения") {
                LabeledContent("Режим", value: model.mock == nil ? "Физические датчики" : "Симулятор · DEMO")
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("Алгоритм", value: "screen-plane-nwu-v1")
                Text("Core Motion: 20 Гц. Датчики работают только в автоматическом режиме на активном экране измерения; HOLD и ручной режим останавливают получение данных.")
                Text("Показ 0,1° — формат интерфейса, а не заявленная точность.")
            }
        }.navigationTitle("Настройки")
            .sheet(item: $export, onDismiss: cleanupExport) { file in ShareSheet(url: file.url) }
    }
    private func cleanupExport() {
        // Export cache lives in the sandbox's temporary directory; iOS can reclaim it.
        export = nil
    }
}
private struct ExportFile: Identifiable { let id = UUID(); let url: URL }
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
