import SwiftUI
import UIKit

/// The preview owns all table values. Changing controls invalidates it; live mapping
/// context is never consulted by the file writer or activity controller.
struct MappingExportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var committed: MappingCommittedSnapshot
    private var journal: MappingJournal { committed.journal }
    @State private var projectID: UUID?
    @State private var horizonID: UUID?
    @State private var excavationID: UUID?
    @State private var firstDay = Date()
    @State private var lastDay = Date()
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var format: MappingExportFormat = .xlsx
    @State private var showTechnicalSheets = false
    @State private var preview: MappingCSVExport?
    @State private var photoPreview: PhotoPackageExport?
    @State private var confirmIncomplete = false
    @State private var files: MappingExportFiles?
    @State private var sharing = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?

    init(committed: MappingCommittedSnapshot, projectID: UUID?) {
        _committed = State(initialValue: committed)
        _projectID = State(initialValue: projectID ?? committed.journal.projects.first?.id)
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
                DatePicker("Дата от", selection: $firstDay, displayedComponents: .date)
                    .accessibilityIdentifier("mappingExportFirstDay")
                DatePicker("Дата до включительно", selection: $lastDay, displayedComponents: .date)
                    .accessibilityIdentifier("mappingExportLastDay")
            }.disabled(busy || sharing)
            Section {
                Picker("Выгрузка", selection: $format) {
                    Text("Полная книга Excel").tag(MappingExportFormat.xlsx)
                    Text("Excel Exchange · обмен").tag(MappingExportFormat.exchange)
                    Text("Геотехническое картирование — регламент").tag(MappingExportFormat.enterpriseGeotechnical)
                    Text("CSV · технический").tag(MappingExportFormat.csv)
                    Text("Фотографии + Excel").tag(MappingExportFormat.photoPackage)
                }.accessibilityIdentifier("mappingExportKind")
                DisclosureGroup("Дополнительные параметры") {
                    NavigationLink {
                        ExportTimeZoneSelection(selection: $timeZoneID)
                    } label: { LabeledContent("Часовой пояс", value: timeZoneID) }
                        .accessibilityIdentifier("mappingExportTimeZone")
                    Picker("Формат файла", selection: $format) {
                        ForEach(MappingExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("mappingExportFormat")
                    if format != .enterpriseGeotechnical {
                        Toggle("Показывать технические листы Excel", isOn: $showTechnicalSheets)
                    }
                    Text("Отбор по дате наблюдения актуальной версии точки в поясе \(timeZoneID), включая весь последний день.").font(.caption)
                }
            }.disabled(busy || sharing)
            Section {
                Text(format == .exchange ? "Обмен: подтверждённый снимок после ранее принятых сохранений. Импорт пока недоступен." : "Подтверждённый снимок журнала при открытии выгрузки. Незавершённые сохранения не включены.").font(.caption).foregroundStyle(.secondary)
                Text("Наблюдений: \(selectedCount)").accessibilityIdentifier("mappingExportPointCount")
                if format == .enterpriseGeotechnical, let report = preview?.enterpriseReport, report.requiresReview {
                    regulatoryWarnings(report)
                }
                Button(exportButtonTitle) {
                    if format == .exchange { shareExchange() }
                    else if let preview { shareOrConfirm(preview) } else { prepare(shareWhenReady: true) }
                }.disabled(busy || sharing || selection == nil).accessibilityIdentifier("mappingExportShare")
                if busy {
                    ProgressView("Подготовка выгрузки…")
                    Button("Отменить подготовку", role: .cancel) { operation?.cancel() }
                        .accessibilityIdentifier("mappingExportCancel")
                }
                if let message = errorMessage { Text(message).foregroundStyle(.red).accessibilityIdentifier("mappingExportError") }
            }
            if photoPreview != nil {
                Section("Снимок выгрузки") {
                    if let photoPreview {
                        Text("Связанных фотографий: \(photoPreview.items.count)")
                        Text("Оригиналов доступно: \(photoPreview.availableCount)")
                        Text("Отсутствуют / повреждены / не завершены: \(photoPreview.unavailableCount)")
                        Text("Размер оригиналов: \(ByteCountFormatter.string(fromByteCount: Int64(photoPreview.availableBytes), countStyle: .file))")
                        if photoPreview.unavailableCount > 0 {
                            Text("Внимание: полный фотоархив недоступен. Неполный пакет требует подтверждения.").foregroundStyle(.orange)
                            DisclosureGroup("Недоступные оригиналы") {
                                ForEach(photoPreview.items.filter { !$0.check.available }, id: \.photo.id) { item in
                                    Text("\(item.photo.id.uuidString): \(item.check.error ?? item.check.status)").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("Одна книга Excel; оригиналы фото — отдельный ZIP. Выгрузка не является полной резервной копией.").font(.caption)
                DisclosureGroup("Состав и ограничения") {
                    if format == .exchange {
                        Text("FieldForge Exchange.xlsx: связанные таблицы точек, J1–J5, тектоники и оценок; UUID, базовые версии и отпечатки, полные исходные записи и история. Числа и даты сохранены текстом без округления. Пусто означает отсутствие значения.")
                        Text("B2a: только экспорт. Можно подготовить предложения на компьютере, но загрузить их обратно в этой версии нельзя. Не меняйте базовые UUID, версии, отпечатки и source_records. Оригиналы фото и DXF не включены; сохраняйте отдельную резервную копию ZIP.")
                    } else if format == .enterpriseGeotechnical {
                        Text("Лист Data (A–AD). Для актуального наблюдения формируется строка на каждую тектоническую структуру. Если структур нет, формируется одна строка с пустыми полями разлома. SD — среднее положительных сохранённых расстояний J1–J4.")
                        Text("При расхождении RQD в Q и RMR поле RQD остаётся пустым. Координаты и азимуты выгружаются в исходных единицах и системах отсчёта. История, сведения о системе координат и типе севера доступны в журнале и Excel Exchange.")
                    } else if format == .photoPackage {
                        Text("ZIP: оригиналы, FieldForge-Mapping.xlsx с реестром photo_register и manifest.json. Файлы проверяются по размеру и SHA-256. Путь и статус каждого оригинала указаны в реестре.")
                        Text("Оригиналы сохраняют все исходные байты, включая личные EXIF/GPS и сведения об авторе. Передавайте архив только доверенным получателям. Неизвестное место и время съёмки остаются неизвестными.")
                    } else {
                    Text(format == .csv ? "Связанные CSV и manifest.json передаются вместе через меню iOS, в том числе «Сохранить в Файлы»." : "Одна книга Excel: пять полевых листов, сводка и скрытые технические листы. Закреплённые заголовки и фильтры. Передача через меню iOS, в том числе «Сохранить в Файлы».")
                    Text("Только метаданные фотографий. Оригиналы изображений не включены; их наличие и целостность не проверяются. Неизвестное место съёмки остаётся неизвестным.")
                    }
                    if format == .enterpriseGeotechnical {
                        Text("Числа выгружаются без предварительного округления. Excel использует до 15 значащих цифр. Отсутствующие значения — пустые ячейки.")
                    } else if format != .exchange {
                    Text("Выгрузка для анализа, не полная резервная копия. Оценки сохранены без пересчёта; базовый RMR — при наличии рассчитанной оценки.")
                    Text(format == .csv ? "UTF-8 с BOM, запятая, CRLF. Excel может ограничивать числа 15 значащими цифрами. Исходный десятичный текст сохранён там, где он есть. Текст, похожий на формулу, защищён апострофом." : "Полевые листы содержат числа; Excel использует до 15 значащих цифр. На технических листах более точные значения сохраняются точным текстом. Отсутствующие значения — пустые ячейки. Пользовательские строки — текст, формулы не создаются.")
                    }
                }.font(.caption)
            }
        }
        .environment(\.timeZone, zone).environment(\.calendar, calendar)
        .navigationTitle("Выгрузка")
        .onChange(of: projectID) { _, _ in horizonID = nil; excavationID = nil }
        .onChange(of: horizonID) { _, _ in excavationID = nil }
        .onChange(of: timeZoneID) { old, _ in
            // A zone change keeps the chosen calendar labels, rather than shifting the day.
            var oldCalendar = Calendar(identifier: .gregorian)
            oldCalendar.timeZone = TimeZone(identifier: old) ?? .gmt
            let newCalendar = calendar
            func rebase(_ date: Date) -> Date {
                let parts = oldCalendar.dateComponents([.year, .month, .day], from: date)
                return newCalendar.date(from: parts) ?? date
            }
            firstDay = rebase(firstDay); lastDay = rebase(lastDay)
        }
        .onChange(of: selection) { _, _ in preview = nil; photoPreview = nil; errorMessage = nil }
        .onChange(of: format) { _, _ in preview = nil; photoPreview = nil; errorMessage = nil }
        .alert("Создать неполный фотоархив?", isPresented: $confirmIncomplete) {
            Button("Отмена", role: .cancel) { }
            Button("Экспортировать INCOMPLETE") { if let preview { share(preview, allowIncomplete: true) } }
        } message: {
            Text("Недоступных оригиналов: \(photoPreview?.unavailableCount ?? 0). Они останутся в Excel и manifest.json с UUID и причиной. Пакет будет помечен INCOMPLETE.")
        }
        .onDisappear { if !sharing { operation?.cancel() } }
        .sheet(isPresented: $sharing, onDismiss: { files = nil }) {
            if let files { MappingExportShareSheet(files: files) }
        }
    }
    private var exportButtonTitle: String {
        switch format {
        case .enterpriseGeotechnical:
            return preview?.enterpriseReport?.requiresReview == true
                ? "Экспортировать с предупреждениями" : "Экспортировать по регламенту"
        case .exchange: return "Экспортировать Excel Exchange"
        case .xlsx: return "Экспортировать Excel"
        case .csv: return "Экспортировать CSV"
        case .photoPackage: return "Экспортировать фотографии ZIP"
        }
    }
    @ViewBuilder private func regulatoryWarnings(_ report: EnterpriseGeotechnicalWorkbook) -> some View {
        if !report.rqdConflicts.isEmpty {
            Text("Расхождение RQD в Q и RMR89. Наблюдений: \(report.rqdConflicts.count). В их строках RQD будет пустым.")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("mappingRegulatoryRQDWarning")
            DisclosureGroup("Наблюдения с расхождением RQD") {
                ForEach(report.rqdConflicts) { conflict in
                    Text(verbatim: "\(conflict.excavation), \(conflict.picket) · Q: \(conflict.q) %, RMR89: \(conflict.rmr) %\nUUID: \(conflict.id.uuidString)")
                }
            }
            Text("Сверьте значения с источником. Исправьте наблюдения в журнале и заново откройте выгрузку.")
        }
        if !report.spatialWarnings.isEmpty {
            Text("Проверьте пространственную привязку")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("mappingRegulatorySpatialWarning")
            ForEach(report.spatialWarnings, id: \.self) { Text(verbatim: $0) }
            Text("Лист Data не содержит единиц XY, СК, осей, высотной системы или типа севера. Сузьте отбор до совместимых записей или используйте полную книгу Excel для проверки привязки. При продолжении значения останутся в исходных системах.")
        }
    }
    private var selectedCount: Int {
        guard let selection, let bounds = try? selection.bounds() else { return 0 }
        return committed.observations(projectID: selection.projectID).filter {
            $0.projectID == selection.projectID && (horizonID == nil || $0.horizonID == horizonID) &&
            (excavationID == nil || $0.excavationID == excavationID) && $0.observedAt >= bounds.start && $0.observedAt < bounds.end
        }.count
    }
    private func shareExchange() {
        guard !busy, !sharing, let selection else { return }
        let storage = mapping.storage
        busy = true; errorMessage = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let snapshot = try await storage.exchangeSnapshot()
                committed = snapshot
                try Task.checkCancellation()
                let worker = Task.detached(priority: .userInitiated) {
                    try MappingExchangeExport.prepare(committed: snapshot, selection: selection).write()
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                files = result; sharing = true
            } catch is CancellationError { }
            catch { errorMessage = "Не удалось создать Excel Exchange: \(error.localizedDescription)" }
        }
    }
    private func shareOrConfirm(_ snapshot: MappingCSVExport) {
        if format == .photoPackage && (photoPreview?.unavailableCount ?? 0) > 0 { confirmIncomplete = true }
        else { share(snapshot) }
    }
    private func prepare(shareWhenReady: Bool = false) {
        guard !busy, !sharing, let selection else { return }
        let photoRoot = mapping.photoStore?.root
        let wantsPhotos = format == .photoPackage
        let wantsEnterprise = format == .enterpriseGeotechnical
        let journal = journal // value snapshot, taken before asynchronous work
        busy = true; errorMessage = nil; preview = nil; photoPreview = nil
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                let snapshot = try MappingCSVExport.prepare(journal: journal, selection: selection, includeEnterprise: wantsEnterprise)
                var photos: PhotoPackageExport?
                if wantsPhotos {
                    guard let photoRoot else { throw MappingError.invalid("Хранилище фотографий недоступно.") }
                    photos = try PhotoPackageExport.prepare(snapshot: snapshot, journal: journal, store: ManagedPhotoStore(root: photoRoot))
                }
                return (snapshot, photos)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                busy = false
                try Task.checkCancellation(); preview = result.0; photoPreview = result.1
                if shareWhenReady, result.0.enterpriseReport?.requiresReview != true { shareOrConfirm(result.0) }
            } catch is CancellationError { busy = false }
            catch { busy = false; errorMessage = "Ошибка выгрузки: \(error.localizedDescription)" }
        }
    }
    private func share(_ preview: MappingCSVExport, allowIncomplete: Bool = false) {
        guard !busy, !sharing else { return }
        let format = format
        let showTechnicalSheets = showTechnicalSheets
        let photos = photoPreview
        busy = true; errorMessage = nil
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                if format == .photoPackage {
                    guard let photos else { throw MappingError.invalid("Обновите предпросмотр фотографий.") }
                    return try photos.write(allowIncomplete: allowIncomplete)
                }
                return try MappingExportFiles.write(preview, format: format, showTechnicalSheets: showTechnicalSheets)
            }
            defer { busy = false }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                if Task.isCancelled { return }
                files = result; sharing = true
            } catch is CancellationError { }
            catch let missing as PhotoPackageConfirmationRequired {
                photoPreview = missing.export; confirmIncomplete = true
            }
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
