import SwiftUI
import UniformTypeIdentifiers

/// Read-only Files workflow. All file coordination, decompression and comparison run
/// outside MainActor. The only storage calls admit a snapshot or check its generation.
struct MappingExchangeImportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var picker = false
    @State private var selectedURL: URL?
    @StateObject private var coordinator = MappingExchangePreviewCoordinator()

    var body: some View {
        let state = coordinator.state
        List {
            Section {
                Text("Предварительный просмотр. Данные ещё не импортированы").font(.headline)
                    .accessibilityIdentifier("exchangePreviewReadOnly")
                Button("Выбрать книгу Excel…", systemImage: "doc.badge.plus") { picker = true }
                    .accessibilityIdentifier("exchangeSelectWorkbook")
                if let selectedURL { LabeledContent("Файл", value: selectedURL.lastPathComponent) }
                if state.busy {
                    ProgressView("Проверка книги и сравнение…")
                    let operationID = coordinator.operationID
                    Button("Отменить проверку", role: .cancel) { coordinator.cancel(operationID: operationID) }
                }
                if let message = state.message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            }
            if let preview = state.preview, let publicationID = state.publicationID {
                if state.stale {
                    Section {
                        Text("Предпросмотр устарел: подтверждённый журнал изменился или хранилище недоступно. Требуется повторная проверка.")
                            .foregroundStyle(.orange).accessibilityIdentifier("exchangePreviewStale")
                        Button("Пересоздать предпросмотр") { if let selectedURL { prepare(selectedURL) } }.disabled(state.busy)
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
                            ExchangePreviewRecords(preview: preview, classification: classification, publicationID: publicationID, coordinator: coordinator)
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
            guard coordinator.isActive else { return }
            switch result {
            case .success(let url): selectedURL = url; prepare(url)
            case .failure(let error): coordinator.selectionFailed(error)
            }
        }
        .onAppear { coordinator.activate(generation: mapping.workflow?.committed.generationID) }
        .task(id: coordinator.state.publicationID) {
            guard let id = coordinator.state.publicationID else { return }
            let storage = mapping.storage
            while !Task.isCancelled && coordinator.isActive && coordinator.state.publicationID == id && !coordinator.state.stale {
                await coordinator.refresh(id) { try await storage.exchangePreviewIsCurrent($0) }
                if coordinator.state.publicationID != id || coordinator.state.stale { break }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onChange(of: mapping.workflow?.committed.generationID) { _, generation in
            coordinator.journalChanged(to: generation)
        }
        .onDisappear { coordinator.deactivate() }
    }
    private func prepare(_ url: URL) {
        coordinator.prepare(url, work: .init(storage: mapping.storage))
    }
}

private struct ExchangePreviewRecords: View {
    let preview: MappingExchangePreview
    let classification: MappingExchangePreview.Classification
    let publicationID: UUID
    @ObservedObject var coordinator: MappingExchangePreviewCoordinator
    private var stale: Bool { coordinator.state.publicationID != publicationID || coordinator.state.stale }
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
