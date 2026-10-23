import Foundation

struct ReceivedPhoto: Sendable {
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
struct RetainedPhotoImport: Sendable {
    let operation: PhotoImportOperation
    let data: Data
}

extension MappingModel {
    func refreshPhotoRecovery() async {
        var operations = retainedPhotos.mapValues(\.operation)
        do {
            let files = photoStore
            let pending = try await storage.run { try files?.pending() ?? [] }
            // Merge live intents after the suspension so a newly received photo cannot disappear.
            operations = retainedPhotos.mapValues(\.operation)
            for operation in pending { operations[operation.id] = operation }
            photoRecoveryError = nil
        } catch { photoRecoveryError = "Не удалось прочитать операции фото. Файлы не удалены: \(error.localizedDescription)" }
        pendingPhotos = operations.values.sorted { $0.photo.importedAt < $1.photo.importedAt }
    }
    func importPhoto(_ received: ReceivedPhoto, context: PhotoContext) async {
        guard context.locationBasis == .pointRevision else { photoError = "Фото черновика сохраняются только вместе с наблюдением."; return }
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        let operation: PhotoImportOperation
        do {
            operation = try await storage.run {
                try files.makeOperation(data: received.data, filename: received.filename, context: context, source: received.source,
                    representation: received.representation, captureWallTime: received.captureWallTime, captureUTCOffset: received.captureUTCOffset, captureSubseconds: received.captureSubseconds)
            }
        } catch { photoError = "Изображение не принято: \(error.localizedDescription)"; return }
        // Retain before I/O and before the busy guard: another provider may finish during capture.
        retainedPhotos[operation.id] = RetainedPhotoImport(operation: operation, data: received.data)
        guard !photoBusy else {
            await refreshPhotoRecovery(); photoError = "Другая операция фото ещё выполняется. " + liveRetryMessage
            return
        }
        photoBusy = true; photoError = nil
        defer { photoBusy = false }
        do {
            try await finishPhoto(operation, files: files)
            await refreshPhotoRecovery()
        } catch { photoError = "Фото не завершено: \(error.localizedDescription) " + liveRetryMessage }
        await refreshPhotoRecovery()
    }
    func retryPhoto(_ operation: PhotoImportOperation, replacement: Data? = nil) async {
        if operation.photo.context.locationBasis == .unknownBeforeFirstSave,
           workflow?.journal.photos.contains(operation.photo) != true {
            photoError = "Это файлы несохранённого черновика. Они не публикуются отдельно; используйте сохранение исходного черновика. После перезапуска форма не восстанавливается. Файлы сохранены."
            return
        }
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        guard !photoBusy else { photoError = "Другая операция фото ещё выполняется. Дождитесь её завершения и повторите сохранение."; return }
        photoBusy = true; photoError = nil
        defer { photoBusy = false }
        do {
            try await finishPhoto(operation, files: files, replacement: replacement)
            await refreshPhotoRecovery()
        } catch {
            photoError = "Повтор не завершён: \(error.localizedDescription) " +
                (retainedPhotos[operation.id] != nil ? liveRetryMessage :
                    operation.photo.source == .camera ? "Если снимок был только в памяти и байты не записались до завершения приложения, восстановить его после перезапуска невозможно." :
                    "Если дисковая копия отсутствует, выберите тот же исходный файл. UUID сохранены.")
        }
        await refreshPhotoRecovery()
    }
    private var liveRetryMessage: String {
        "Используйте «Повторить сохранение» без повторной съёмки, пока приложение работает. Если байты не удалось записать на диск, завершение приложения потеряет снимок из памяти."
    }
    private func finishPhoto(_ operation: PhotoImportOperation, files: ManagedPhotoStore, replacement: Data? = nil) async throws {
        let retained = retainedPhotos[operation.id]
        try await persist { next in
            if let existing = next.journal.photos.first(where: { $0.id == operation.id }), !files.hasIntent(operation) {
                guard existing == operation.photo, next.journal.photoAttachments.contains(operation.attachment) else { throw StorageError.invalidRecord }
                _ = try files.read(operation.attachment)
                return
            }
            if let retained {
                guard retained.operation == operation else { throw StorageError.invalidRecord }
                try files.stage(retained.data, for: operation)
            } else if let replacement { try files.supply(replacement, for: operation) }
            try files.promote(operation)
            _ = try files.read(operation.attachment)
            try next.registerPhoto(operation)
        }
        retainedPhotos.removeValue(forKey: operation.id)
        // Finalization is outside the commit. An error here means the original and
        // reference ARE committed; the recovery intent remains retryable.
        do { try await storage.run { if files.hasIntent(operation) { try files.complete(operation) } } }
        catch { photoError = "Фото и оригинал сохранены. Повторите завершение операции: \(error.localizedDescription)" }
    }
}
