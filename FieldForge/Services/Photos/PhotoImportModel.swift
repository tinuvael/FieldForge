import Foundation

struct ReceivedPhoto {
    let data: Data
    let filename: String?
    let source: PhotoSource
    let representation: String
    var captureWallTime: String? = nil
    var captureUTCOffset: String? = nil
    var captureSubseconds: String? = nil
}

/// Volatile fallback owned by the shared model, not by a dismissed picker or observation card.
/// It cannot survive process termination unless staging/original bytes were actually written.
struct RetainedPhotoImport {
    let operation: PhotoImportOperation
    let data: Data
}

extension MappingModel {
    func refreshPhotoRecovery() {
        var operations = retainedPhotos.mapValues(\.operation)
        do {
            for operation in try photoStore?.pending() ?? [] { operations[operation.id] = operation }
            photoRecoveryError = nil
        } catch { photoRecoveryError = "Не удалось прочитать операции фото. Файлы не удалены: \(error.localizedDescription)" }
        pendingPhotos = operations.values.sorted { $0.photo.importedAt < $1.photo.importedAt }
    }
    func importPhoto(_ received: ReceivedPhoto, context: PhotoContext) async {
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        let operation: PhotoImportOperation
        do {
            operation = try await Task.detached(priority: .userInitiated) {
                try files.makeOperation(data: received.data, filename: received.filename, context: context, source: received.source,
                    representation: received.representation, captureWallTime: received.captureWallTime, captureUTCOffset: received.captureUTCOffset, captureSubseconds: received.captureSubseconds)
            }.value
        } catch { photoError = "Изображение не принято: \(error.localizedDescription)"; return }
        // Retain before I/O and before the busy guard: another provider may finish during capture.
        retainedPhotos[operation.id] = RetainedPhotoImport(operation: operation, data: received.data)
        guard !photoBusy else {
            refreshPhotoRecovery(); photoError = "Другая операция фото ещё выполняется. " + liveRetryMessage
            return
        }
        photoBusy = true; photoError = nil
        defer { photoBusy = false; refreshPhotoRecovery() }
        do {
            try await Task.detached { try files.stage(received.data, for: operation) }.value
            try await finishPhoto(operation, files: files)
        } catch { photoError = "Фото не завершено: \(error.localizedDescription) " + liveRetryMessage }
    }
    func retryPhoto(_ operation: PhotoImportOperation, replacement: Data? = nil) async {
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        guard !photoBusy else { photoError = "Другая операция фото ещё выполняется. Дождитесь её завершения и повторите сохранение."; return }
        photoBusy = true; photoError = nil
        defer { photoBusy = false; refreshPhotoRecovery() }
        do {
            if let retained = retainedPhotos[operation.id] {
                guard retained.operation == operation else { throw StorageError.invalidRecord }
                try await Task.detached { try files.stage(retained.data, for: operation) }.value
            } else if let replacement { try await Task.detached { try files.supply(replacement, for: operation) }.value }
            try await finishPhoto(operation, files: files)
        } catch {
            photoError = "Повтор не завершён: \(error.localizedDescription) " +
                (retainedPhotos[operation.id] != nil ? liveRetryMessage :
                    operation.photo.source == .camera ? "Если снимок был только в памяти и байты не записались до завершения приложения, восстановить его после перезапуска невозможно." :
                    "Если дисковая копия отсутствует, выберите тот же исходный файл. UUID сохранены.")
        }
    }
    private var liveRetryMessage: String {
        "Используйте «Повторить сохранение» без повторной съёмки, пока приложение работает. Если байты не удалось записать на диск, завершение приложения потеряет снимок из памяти."
    }
    private func finishPhoto(_ operation: PhotoImportOperation, files: ManagedPhotoStore) async throws {
        // A queued/repeated tap after successful completion is a verified no-op, not a new import.
        if let existing = workflow?.journal.photos.first(where: { $0.id == operation.id }), !files.hasIntent(operation) {
            guard existing == operation.photo, workflow?.journal.photoAttachments.contains(operation.attachment) == true else { throw StorageError.invalidRecord }
            _ = try await Task.detached { try files.read(operation.attachment) }.value
            retainedPhotos.removeValue(forKey: operation.id)
            return
        }
        try await Task.detached { try files.promote(operation) }.value
        // A verified original + persisted intent now suffice for process-restart recovery.
        retainedPhotos.removeValue(forKey: operation.id)
        guard workflow != nil else { throw StorageError.writesBlocked }
        try workflow!.registerPhoto(operation)
        // A thumbnail failure leaves the committed original visible with a retryable warning.
        try await Task.detached { try files.complete(operation) }.value
    }
}
