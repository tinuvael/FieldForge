import Foundation

/// Copy bounded bytes while coordinated; release access BEFORE parsing/comparison or
/// waiting for storage freshness. No extraction, temporary file or writable handle.
enum MappingExchangeFileRead {
    static func prepare(url: URL, committed: MappingCommittedSnapshot,
                        limits: ExchangeLimits = .init()) async throws -> MappingExchangePreview {
        let reader = ExchangeCoordinatedRead()
        return try await withTaskCancellationHandler(operation: {
            let bytes = try reader.data(url: url, maximum: limits.fileBytes)
            try Task.checkCancellation()
            let archive = try ExchangeArchive(data: bytes, limits: limits)
            let workbook = try ExchangeWorkbook(parts: archive.parts, limits: limits)
            return try MappingExchangePreview.prepare(workbook: workbook, committed: committed)
        }, onCancel: { reader.cancel() })
    }
}

/// Unchecked boundary: data() is called once on one worker; only cancel() crosses
/// threads. NSFileCoordinator.h explicitly permits cancel() from any thread. It may
/// race with an accessor already running, so that accessor still checks cancellation.
final class ExchangeCoordinatedRead: @unchecked Sendable {
    private let coordinator = NSFileCoordinator()
    func cancel() { coordinator.cancel() }

    // Scope hooks are synchronous, nonescaping and used by focused resource tests.
    func data(url: URL, maximum: Int,
              startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
              stopAccess: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) throws -> Data {
        try Task.checkCancellation()
        let access = startAccess(url)
        defer { if access { stopAccess(url) } }
        try Task.checkCancellation()
        var coordinationError: NSError?
        var bytes: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            bytes = Result {
                try Task.checkCancellation()
                let handle = try FileHandle(forReadingFrom: coordinated)
                defer { try? handle.close() }
                guard try handle.seekToEnd() <= maximum else { throw ExchangeImportError("Файл XLSX превышает допустимый размер.") }
                try handle.seek(toOffset: 0)
                let data = try handle.read(upToCount: maximum + 1) ?? Data()
                try Task.checkCancellation()
                guard data.count <= maximum else { throw ExchangeImportError("Размер файла изменился.") }
                return data
            }
        }
        try Task.checkCancellation()
        if let coordinationError { throw coordinationError }
        guard let bytes else { throw ExchangeImportError("Файловый провайдер не предоставил книгу.") }
        return try bytes.get()
    }
}
