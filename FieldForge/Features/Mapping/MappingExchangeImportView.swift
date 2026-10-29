import SwiftUI
import UniformTypeIdentifiers

/// Read-only Files workflow. All file coordination, decompression and comparison run
/// outside MainActor. The only storage calls admit a snapshot or check its generation.
struct MappingExchangeImportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var picker = false
    @State private var selectedURL: URL?
    @State private var preview: MappingExchangePreview?
    @State private var stale = false
    @State private var busy = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Text("Предварительный просмотр. Данные ещё не импортированы").font(.headline)
                    .accessibilityIdentifier("exchangePreviewReadOnly")
                Button("Выбрать книгу Excel…", systemImage: "doc.badge.plus") { picker = true }
                    .disabled(busy).accessibilityIdentifier("exchangeSelectWorkbook")
                if let selectedURL { LabeledContent("Файл", value: selectedURL.lastPathComponent) }
                if busy {
                    ProgressView("Проверка книги и сравнение…")
                    Button("Отменить проверку", role: .cancel) { operation?.cancel() }
                }
                if let message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            }
            if let preview {
                if stale {
                    Section {
                        Text("Предпросмотр устарел: подтверждённый журнал изменился или хранилище недоступно. Требуется повторная проверка.")
                            .foregroundStyle(.orange).accessibilityIdentifier("exchangePreviewStale")
                        Button("Пересоздать предпросмотр") { if let selectedURL { prepare(selectedURL) } }.disabled(busy)
                    }
                }
                Section("Книга обмена") {
                    LabeledContent("Формат", value: MappingExchangeExport.version)
                    LabeledContent("Проект", value: preview.projectName)
                    LabeledContent("Выгружено (UTC)", value: MappingCSVExport.iso(preview.exportedAt))
                    DisclosureGroup("Идентичность и отбор") {
                        Text("Книга: \(preview.workbookID.uuidString)")
                        Text("Поколение журнала: \(preview.generationID.uuidString)")
                        Text(preview.metadata["selection_json"] ?? "").textSelection(.enabled)
                    }.font(.caption)
                }
                Section("Результат проверки") {
                    ForEach(MappingExchangePreview.Classification.allCases, id: \.self) { classification in
                        NavigationLink {
                            ExchangePreviewRecords(preview: preview, classification: classification, stale: $stale)
                        } label: { LabeledContent(classification.title, value: String(preview.count(classification))) }
                    }
                    if preview.hasBlockingRecords { Text("Есть блокирующие ошибки. Исправьте книгу или создайте новую выгрузку.").foregroundStyle(.orange) }
                }
            }
            Section("Ограничения") {
                Text("Это только проверка. Применение изменений появится в B2c. Книга, журнал, история, фото, DXF и резервные копии не изменяются.")
                Text("SHA-256 проверяет целостность и совпадение с базой; он не подтверждает доверенное авторство.")
                Text("Числа и даты должны оставаться текстом. Формулы и преобразования Excel в числовые или датированные ячейки отклоняются: утраченную точность восстановить нельзя.")
            }.font(.caption)
        }
        .navigationTitle("Проверка Excel Exchange")
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            switch result {
            case .success(let url): selectedURL = url; prepare(url)
            case .failure(let error): message = "Выбор файла: \(error.localizedDescription)"
            }
        }
        .task(id: preview?.generationID) {
            guard let generation = preview?.generationID else { return }
            while !Task.isCancelled && !stale {
                do { stale = try await !mapping.storage.exchangePreviewIsCurrent(generation) }
                catch { stale = true }
                if stale { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: mapping.workflow?.committed.generationID) { _, generation in
            if let preview, generation != preview.generationID { stale = true }
        }
        .onDisappear { operation?.cancel() }
    }
    private func prepare(_ url: URL) {
        operation?.cancel(); preview = nil; message = nil; stale = false; busy = true
        let storage = mapping.storage
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let committed = try await storage.exchangeSnapshot()
                try Task.checkCancellation()
                let worker = Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var coordinationError: NSError?
                    var parsed: Result<MappingExchangePreview, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
                        parsed = Result { try MappingExchangePreview.prepare(url: coordinated, committed: committed) }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let parsed else { throw ExchangeImportError("Файловый провайдер не предоставил книгу.") }
                    return try parsed.get()
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                preview = result
                do { stale = try await !storage.exchangePreviewIsCurrent(result.generationID) }
                catch { stale = true }
            } catch is CancellationError { message = "Проверка отменена. Данные не изменены." }
            catch { message = "Книга отклонена: \(error.localizedDescription)" }
        }
    }
}

private struct ExchangePreviewRecords: View {
    let preview: MappingExchangePreview
    let classification: MappingExchangePreview.Classification
    @Binding var stale: Bool
    var body: some View {
        List {
            Text("Предварительный просмотр. Данные ещё не импортированы").font(.headline)
            if stale { Text("Предпросмотр устарел. Вернитесь и пересоздайте его.").foregroundStyle(.orange) }
            ForEach(preview.records.filter { $0.classification == classification }) { record in
                NavigationLink {
                    List {
                        Text("Предварительный просмотр. Данные ещё не импортированы").font(.headline)
                        if stale { Text("Предпросмотр устарел.").foregroundStyle(.orange) }
                        Text(record.id).font(.caption).textSelection(.enabled)
                        Text(record.reason)
                        ForEach(record.changes) { change in
                            Section("\(change.sheet) · \(change.field)") {
                                LabeledContent("Было") { Text(change.before.isEmpty ? "∅ (пусто)" : change.before).textSelection(.enabled) }
                                LabeledContent("Предложено") { Text(change.after.isEmpty ? "∅ (пусто)" : change.after).textSelection(.enabled) }
                            }
                        }
                    }.navigationTitle("Изменения полей")
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.id).font(.caption).lineLimit(2)
                        Text(record.reason)
                    }
                }
            }
        }.navigationTitle(classification.title)
    }
}
