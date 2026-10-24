import Foundation

/// Application readiness is a separate boundary from file/store validation.
/// The app supplies model construction and publication; storage remains UI-free.
/// Shared with deterministic model-readiness/rollback fault-injection tests.
@MainActor enum RestoreSessionFinalizer {
    struct Failure: LocalizedError {
        let reason: String
        let recoveryError: String?
        var errorDescription: String? {
            if let recoveryError {
                return "Восстановление не завершено: \(reason) Автоматический откат не завершён: \(recoveryError). Открытие и запись заблокированы; оба набора данных и защитная копия сохранены."
            }
            return "Восстановление отменено: \(reason) Предыдущая база возвращена; входящие файлы и защитная копия сохранены для проверки."
        }
    }
    static func finish<Models>(
        _ pending: OfflineRestore.PendingActivation,
        reopen: () async throws -> Models,
        discard: () async -> Void,
        publish: (Models) async throws -> Void,
        checkpoint: @escaping @Sendable (OfflineRestore.Checkpoint) throws -> Void = { _ in },
        recoveryCheckpoint: @escaping @Sendable (OfflineRestore.RecoveryCheckpoint) throws -> Void = { _ in }
    ) async throws {
        do {
            let models = try await reopen()
            try await Task.detached(priority: .userInitiated) {
                try OfflineRestore.finalize(pending, checkpoint: checkpoint)
            }.value
            // Publication is last. The production closure enables candidate writers
            // and publishes both models in one MainActor turn after its final await.
            try await publish(models)
        } catch {
            let reason = error.localizedDescription
            await discard() // retire/drain candidate mapping and disable measurement models first
            do {
                try await Task.detached(priority: .userInitiated) {
                    try OfflineRestore.rollback(pending, checkpoint: recoveryCheckpoint)
                }.value
            } catch {
                throw Failure(reason: reason, recoveryError: error.localizedDescription)
            }
            throw Failure(reason: reason, recoveryError: nil)
        }
    }
}
