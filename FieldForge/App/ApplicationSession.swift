import SwiftUI

/// A dataset boundary owns the complete UI/model lifetime. Recovery finishes before
/// either store is constructed. Old models and their FIFO owner are never reused.
@MainActor final class ApplicationSession: ObservableObject {
    @Published private(set) var measurements: AppModel?
    @Published private(set) var mapping: MappingModel?
    @Published private(set) var generation = UUID()
    @Published private(set) var busy = true
    @Published var message: String?
    @Published private(set) var failure: String?
    private var operation: Task<Void, Never>?

    init() { operation = Task { await reopen() } }

    private func reopen() async {
        busy = true
        do {
            let live = try FileMeasurementStore.applicationStore().url.deletingLastPathComponent()
            let opened: (OpenedMeasurements?, String?) = try await Task.detached(priority: .userInitiated) {
                try OfflineRestore.recover(live: live)
                do { return (try AppModel.openJournal(), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            let nextMeasurements = AppModel(opened: opened.0, openingError: opened.1), nextMapping = MappingModel()
            await nextMapping.waitUntilOpened()
            // Opening errors are displayed by the ordinary screens on normal launch.
            // A recovery error above exposes no store at all, including an empty one.
            measurements = nextMeasurements; mapping = nextMapping; generation = UUID(); failure = nil
        } catch {
            measurements = nil; mapping = nil
            failure = "Восстановление прервано. Открытие и запись заблокированы; все файлы сохранены. \(error.localizedDescription)"
        }
        busy = false
    }
    func restore(_ preview: RestorePreview) {
        guard !busy, let mapping, let measurements else { preview.cleanup(); return }
        do {
            guard !mapping.isSaving, !mapping.photoBusy,
                  mapping.workflow?.draft.photoSessions.isEmpty == true else {
                throw BackupError.invalid("Дождитесь завершения сохранения и получения фотографий.")
            }
            let source = try measurements.beginBackup()
            busy = true; measurements.retireForRestore()
            operation = Task {
                defer { preview.cleanup() }
                do {
                    let protection = try await mapping.storage.restore(preview, measurements: source)
                    await reopen()
                    guard self.mapping?.workflow != nil, self.measurements?.errorMessage == nil, failure == nil else {
                        throw BackupError.invalid("Данные активированы, но модель не открыта. Запись заблокирована.")
                    }
                    message = "Восстановление завершено. Все проекты и измерения открыты и проверены. Предыдущая база сохранена целиком в \(protection.deletingLastPathComponent().path) (previous и pre-restore.zip)."
                } catch {
                    let reason = error.localizedDescription
                    await reopen()
                    message = "Восстановление не завершено: \(reason) Незавершённая активация отменена при повторном открытии. Все файлы и защитная копия сохранены; при ошибке восстановления запись заблокирована."
                }
            }
        } catch { preview.cleanup(); message = error.localizedDescription }
    }
}
