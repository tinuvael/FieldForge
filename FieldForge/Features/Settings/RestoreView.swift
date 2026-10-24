import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @EnvironmentObject private var session: ApplicationSession
    @State private var selecting = false
    @State private var preview: RestorePreview?
    @State private var verifying = false
    @State private var confirming = false
    @State private var error: String?
    @State private var cancellation: BackupCancellation?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text("Восстановление полностью заменяет базу: все проекты, наблюдения, измерения, фотографии и планы. Это не объединение данных и не синхронизация Excel.")
                Text("Существующая база будет заменена. Перед заменой приложение сохранит проверенный ZIP и весь прежний каталог в Application Support/FieldForge-Restore. Копия останется после восстановления.")
                Text("Несохранённые черновики и открытые редакторы будут закрыты. Сохраните нужные изменения до подтверждения.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Выбрать архив ZIP") { selecting = true }.disabled(verifying)
                if verifying {
                    ProgressView("Копирование, проверка и подготовка оригиналов…")
                    Button("Отменить", role: .cancel) { cancellation?.cancel(); worker?.cancel() }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let preview {
                Section("Содержимое проверенного архива") {
                    let manifest = preview.manifest
                    LabeledContent("Создан (UTC)", value: manifest.createdAtUTC)
                    LabeledContent("Формат архива", value: "\(manifest.formatVersion)")
                    LabeledContent("Схема картирования", value: "\(manifest.mappingSchemaVersion)")
                    LabeledContent("Проекты", value: "\(manifest.projectCount)")
                    LabeledContent("Наблюдения", value: "\(manifest.observationCount)")
                    LabeledContent("Независимые измерения", value: "\(manifest.measurementIDs.count)")
                    LabeledContent("Фотографии", value: "\(manifest.attachments.filter { $0.kind == "photo" }.count)")
                    LabeledContent("Планы DXF", value: "\(manifest.attachments.filter { $0.kind == "dxf" }.count)")
                    LabeledContent("Размер ZIP", value: ByteCountFormatter.string(fromByteCount: Int64(preview.byteCount), countStyle: .file))
                    Label("Архив и подготовленные файлы полностью проверены", systemImage: "checkmark.shield")
                    Button("Восстановить всю базу", role: .destructive) { confirming = true }
                }
            }
        }
        .navigationTitle("Восстановление")
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): inspect(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .confirmationDialog("Заменить всю существующую базу?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Заменить базу и сохранить предыдущую", role: .destructive) {
                if let selected = preview { preview = nil; session.restore(selected) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Объединения не будет. Черновики и редакторы закроются. Прежняя база останется в FieldForge-Restore. После начала замены отмена недоступна; при сбое приложение восстановит согласованное состояние.")
        }
        .onDisappear { cancellation?.cancel(); worker?.cancel(); preview?.cleanup(); preview = nil }
    }
    private func inspect(_ url: URL) {
        preview?.cleanup(); preview = nil; error = nil; verifying = true
        let token = BackupCancellation(); cancellation = token
        worker = Task { @MainActor in
            defer { verifying = false; cancellation = nil; worker = nil }
            do {
                let result = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        // Only this first copy reads the provider-managed URL. Parsing,
                        // extraction, preview and activation use the private copy.
                        return try OfflineRestore.prepare(url, cancellation: token)
                    }.value
                } onCancel: { token.cancel() }
                if Task.isCancelled { result.cleanup(); throw CancellationError() }
                preview = result
            } catch is CancellationError { error = "Проверка отменена. Существующая база не изменена." }
            catch { self.error = "Архив не принят: \(error.localizedDescription) Существующая база не изменена." }
        }
    }
}
