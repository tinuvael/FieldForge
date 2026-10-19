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

extension MappingModel {
    func refreshPhotoRecovery() {
        do { pendingPhotos = try photoStore?.pending() ?? []; photoRecoveryError = nil }
        catch { photoRecoveryError = "Не удалось прочитать операции фото. Файлы сохранены: \(error.localizedDescription)" }
    }
    func importPhoto(_ received: ReceivedPhoto, context: PhotoContext) async {
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        guard !photoBusy else { photoError = "Другая операция фото ещё выполняется. Повторите выбор после её завершения."; return }
        photoBusy = true
        defer { photoBusy = false; refreshPhotoRecovery() }
        do {
            let operation = try await Task.detached(priority: .userInitiated) {
                try files.begin(data: received.data, filename: received.filename, context: context, source: received.source,
                    representation: received.representation, captureWallTime: received.captureWallTime, captureUTCOffset: received.captureUTCOffset, captureSubseconds: received.captureSubseconds)
            }.value
            try await finishPhoto(operation, files: files)
        } catch { self.photoError = "Фото не завершено: \(error.localizedDescription) Если операция сохранена, используйте повтор ниже." }
    }
    func retryPhoto(_ operation: PhotoImportOperation, replacement: Data? = nil) async {
        guard let files = photoStore, workflow != nil else { photoError = "Хранилище фото недоступно."; return }
        guard !photoBusy else { photoError = "Другая операция фото ещё выполняется. Повторите выбор после её завершения."; return }
        photoBusy = true
        defer { photoBusy = false; refreshPhotoRecovery() }
        do {
            if let replacement { try await Task.detached { try files.supply(replacement, for: operation) }.value }
            try await finishPhoto(operation, files: files)
        } catch { self.photoError = "Повтор не завершён: \(error.localizedDescription) При отсутствии временной копии выберите тот же исходный файл. UUID сохранены." }
    }
    private func finishPhoto(_ operation: PhotoImportOperation, files: ManagedPhotoStore) async throws {
        try await Task.detached { try files.promote(operation) }.value
        guard workflow != nil else { throw StorageError.writesBlocked }
        try workflow!.registerPhoto(operation)
        // A thumbnail failure leaves the committed original visible with a retryable warning.
        try await Task.detached { try files.complete(operation) }.value
    }
}
