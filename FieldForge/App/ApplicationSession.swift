import SwiftUI

/// Recovery precedes store construction. A provisional model pair is never exposed
/// to views; only a usable pair may finalize and publish a new dataset lifetime.
@MainActor final class ApplicationSession: ObservableObject {
    @Published private(set) var measurements: AppModel?
    @Published private(set) var mapping: MappingModel?
    @Published private(set) var generation = UUID()
    @Published private(set) var busy = true
    @Published var message: String?
    @Published private(set) var failure: String?
    private var operation: Task<Void, Never>?
    private struct Models {
        let measurements: AppModel
        let mapping: MappingModel
    }
    private var candidate: Models?

    init() { operation = Task { await reopen() } }

    private func loadModels(restoring: Bool) async throws -> Models {
        let opened: (OpenedMeasurements?, String?) = await Task.detached(priority: .userInitiated) {
            do { return (try AppModel.openJournal(), nil) }
            catch { return (nil, error.localizedDescription) }
        }.value
        let models = Models(measurements: AppModel(opened: opened.0, openingError: opened.1, restoring: restoring),
                            mapping: MappingModel(restoring: restoring))
        if restoring { candidate = models } // retain partial initialization for retirement on any error
        await models.mapping.waitUntilOpened()
        if restoring {
            guard models.mapping.readyForRestore else {
                throw BackupError.invalid("Модель картирования не открыта: \(models.mapping.error ?? "хранилище недоступно")")
            }
            guard models.measurements.readyForRestore else {
                throw BackupError.invalid("Модель независимых измерений не открыта: \(models.measurements.errorMessage ?? "хранилище недоступно")")
            }
        }
        return models
    }
    private func publish(_ models: Models) {
        measurements = models.measurements; mapping = models.mapping
        generation = UUID(); failure = nil; candidate = nil
    }
    private func enableAndPublish(_ models: Models) async throws {
        try await models.mapping.storage.enableAfterRestore()
        models.measurements.enableAfterRestore()
        publish(models)
    }
    private func discardCandidate() async {
        guard let candidate else { return }
        candidate.measurements.retireForRestore()
        await candidate.mapping.storage.retire() // FIFO drain before any directory rollback
        self.candidate = nil
    }
    private func block(_ reason: String) {
        measurements = nil; mapping = nil
        failure = "\(reason) Открытие и запись заблокированы; все файлы сохранены."
    }
    private func reopen() async {
        busy = true; defer { busy = false }
        do {
            let live = try FileMeasurementStore.applicationStore().url.deletingLastPathComponent()
            try await Task.detached(priority: .userInitiated) { try OfflineRestore.recover(live: live) }.value
            publish(try await loadModels(restoring: false))
        } catch { block(error.localizedDescription) }
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
                defer { preview.cleanup(); busy = false }
                do {
                    let pending = try await mapping.storage.restore(preview, measurements: source)
                    // Do not run startup recovery here: this intent must remain
                    // provisional throughout real application-model construction.
                    try await RestoreSessionFinalizer.finish(pending, reopen: {
                        try await self.loadModels(restoring: true)
                    }, discard: {
                        await self.discardCandidate()
                    }, publish: { models in
                        try await self.enableAndPublish(models)
                    })
                    message = "Восстановление завершено. Все проекты и измерения открыты и проверены. Предыдущая база сохранена целиком в \(pending.protection.deletingLastPathComponent().path) (previous и pre-restore.zip)."
                } catch {
                    await discardCandidate()
                    await mapping.storage.retire()
                    if let failed = error as? RestoreSessionFinalizer.Failure, failed.recoveryError != nil {
                        // Never retry ordinary reopen into an unresolved/ambiguous root.
                        block(failed.localizedDescription); message = failed.localizedDescription
                        return
                    }
                    do {
                        let live = source.url.deletingLastPathComponent()
                        try await Task.detached(priority: .userInitiated) { try OfflineRestore.recover(live: live) }.value
                        let previous = try await loadModels(restoring: true)
                        try await enableAndPublish(previous)
                        message = "Восстановление не завершено: \(error.localizedDescription) Предыдущая база открыта. Входящие файлы и защитная копия сохранены для проверки."
                    } catch {
                        await discardCandidate()
                        block("Не удалось безопасно открыть предыдущую базу: \(error.localizedDescription)")
                        message = failure
                    }
                }
            }
        } catch { preview.cleanup(); message = error.localizedDescription }
    }
}
