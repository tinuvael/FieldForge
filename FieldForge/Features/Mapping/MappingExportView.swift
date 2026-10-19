import SwiftUI
import UIKit

/// The preview owns all table values. Changing controls invalidates it; live mapping
/// context is never consulted by the file writer or activity controller.
struct MappingExportView: View {
    @State private var journal: MappingJournal
    @State private var projectID: UUID?
    @State private var horizonID: UUID?
    @State private var excavationID: UUID?
    @State private var firstDay = Date()
    @State private var lastDay = Date()
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var preview: MappingCSVExport?
    @State private var files: MappingExportFiles?
    @State private var sharing = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?

    init(journal: MappingJournal, projectID: UUID?) {
        _journal = State(initialValue: journal)
        _projectID = State(initialValue: projectID ?? journal.projects.first?.id)
    }
    private var selection: MappingExportSelection? {
        projectID.map { MappingExportSelection(projectID: $0, horizonID: horizonID, excavationID: excavationID,
            firstDay: firstDay, lastDay: lastDay, timeZoneID: timeZoneID) }
    }
    private var zone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c }
    var body: some View {
        Form {
            Section("Отбор по полевой дате") {
                Picker("Проект", selection: $projectID) {
                    ForEach(journal.projects) { Text($0.name).tag(Optional($0.id)) }
                }.accessibilityIdentifier("mappingExportProject")
                Picker("Горизонт", selection: $horizonID) {
                    Text("Все горизонты").tag(UUID?.none)
                    ForEach(journal.horizons.filter { $0.projectID == projectID }) { Text($0.displayName).tag(Optional($0.id)) }
                }
                Picker("Выработка", selection: $excavationID) {
                    Text("Все выработки").tag(UUID?.none)
                    ForEach(journal.excavations.filter { $0.projectID == projectID && (horizonID == nil || $0.horizonIDs.contains(horizonID!)) }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                NavigationLink {
                    ExportTimeZoneSelection(selection: $timeZoneID)
                } label: { LabeledContent("Часовой пояс", value: timeZoneID) }
                    .accessibilityIdentifier("mappingExportTimeZone")
                DatePicker("Дата от", selection: $firstDay, displayedComponents: .date)
                    .accessibilityIdentifier("mappingExportFirstDay")
                DatePicker("Дата до включительно", selection: $lastDay, displayedComponents: .date)
                    .accessibilityIdentifier("mappingExportLastDay")
                Text("Григорианский календарь · \(timeZoneID). Отбор по дате наблюдения актуальной версии точки, включая весь последний день.")
                    .font(.caption)
            }.disabled(busy || sharing)
            Section {
                Button("Предпросмотр") { prepare() }
                    .disabled(busy || selection == nil).accessibilityIdentifier("mappingExportPreview")
                if busy {
                    ProgressView("Подготовка выгрузки…")
                    Button("Отменить подготовку", role: .cancel) { operation?.cancel() }
                        .accessibilityIdentifier("mappingExportCancel")
                }
                if let message = errorMessage { Text(message).foregroundStyle(.red).accessibilityIdentifier("mappingExportError") }
            }
            if let preview {
                Section("Снимок выгрузки") {
                    Text("Точек: \(preview.pointCount)").accessibilityIdentifier("mappingExportPointCount")
                    Text("Снимок: \(MappingCSVExport.iso(preview.snapshotAt))").font(.caption)
                    Text("Снимок зафиксирован. Для обновления данных откройте «Выгрузку» заново.").font(.caption)
                    DisclosureGroup("Связанные таблицы") {
                        ForEach(preview.tables, id: \.name) { table in
                            LabeledContent(table.name + ".csv", value: String(table.rows.count))
                        }
                    }
                    Button { share(preview) } label: { Label("Сохранить / поделиться CSV", systemImage: "square.and.arrow.up") }
                        .disabled(busy || sharing).accessibilityIdentifier("mappingExportShare")
                }
            }
            Section("Состав и ограничения") {
                Text("Связанные CSV и manifest.json передаются вместе через меню iOS, в том числе «Сохранить в Файлы».")
                Text("Только метаданные фотографий. Оригиналы изображений не включены; их наличие и целостность не проверяются. Неизвестное место съёмки остаётся неизвестным.")
                Text("Выгрузка для анализа, не полная резервная копия. Оценки сохранены без пересчёта; RMR — только исходные данные.")
                Text("UTF-8 с BOM, запятая, CRLF. Excel может ограничивать числа 15 значащими цифрами. Исходный десятичный текст сохранён там, где он есть. Текст, похожий на формулу, защищён апострофом.")
            }.font(.caption)
        }
        .environment(\.timeZone, zone).environment(\.calendar, calendar)
        .navigationTitle("Выгрузка")
        .onChange(of: projectID) { _, _ in horizonID = nil; excavationID = nil }
        .onChange(of: horizonID) { _, _ in excavationID = nil }
        .onChange(of: timeZoneID) { old, _ in
            // A zone change keeps the chosen calendar labels, rather than shifting the day.
            var oldCalendar = Calendar(identifier: .gregorian)
            oldCalendar.timeZone = TimeZone(identifier: old) ?? .gmt
            func rebase(_ date: Date) -> Date {
                let parts = oldCalendar.dateComponents([.year, .month, .day], from: date)
                return calendar.date(from: parts) ?? date
            }
            firstDay = rebase(firstDay); lastDay = rebase(lastDay)
        }
        .onChange(of: selection) { _, _ in preview = nil; errorMessage = nil }
        .onDisappear { if !sharing { operation?.cancel() } }
        .sheet(isPresented: $sharing, onDismiss: { files?.cleanup(); files = nil }) {
            if let files { MappingExportShareSheet(files: files) }
        }
    }
    private func prepare() {
        guard let selection else { return }
        let journal = journal // value snapshot, taken before asynchronous work
        busy = true; errorMessage = nil; preview = nil
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) { try MappingCSVExport.prepare(journal: journal, selection: selection) }
            defer { busy = false }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); preview = result
            } catch is CancellationError { /* A cancelled preview has no files or source side effects. */ }
            catch { errorMessage = "Ошибка выгрузки: \(error.localizedDescription)" }
        }
    }
    private func share(_ preview: MappingCSVExport) {
        busy = true; errorMessage = nil
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) { try MappingExportFiles.write(preview) }
            defer { busy = false }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                if Task.isCancelled { result.cleanup(); return }
                files = result; sharing = true
            } catch is CancellationError { }
            catch { errorMessage = "Не удалось создать файлы: \(error.localizedDescription)" }
        }
    }
}

private struct ExportTimeZoneSelection: View {
    @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List(TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { id in
            Button { selection = id; dismiss() } label: {
                HStack { Text(id); Spacer(); if selection == id { Image(systemName: "checkmark") } }
            }
        }.navigationTitle("Часовой пояс").searchable(text: $search, prompt: "Город или пояс")
    }
}

private struct MappingExportShareSheet: UIViewControllerRepresentable {
    // Strong ownership keeps URLs alive until the native sharing presentation is dismissed.
    let files: MappingExportFiles
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files.urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
