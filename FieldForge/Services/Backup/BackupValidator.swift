import Foundation
import CryptoKit

struct BackupValidation: Sendable {
    let manifest: BackupManifest?
    let report: BackupReport
}

/// Reusable for B1b: validates bytes in place and never extracts or activates data.
/// Invalid archives become a structured report; cancellation remains cancellation.
enum BackupValidator {
    static func verify(_ url: URL, cancellation: BackupCancellation = BackupCancellation()) throws -> BackupValidation {
        do { return try inspect(url, cancellation: cancellation) }
        catch is CancellationError { throw CancellationError() }
        catch { return BackupValidation(manifest: nil, report: .init(problems: [.init(path: "archive", reason: error.localizedDescription)])) }
    }
    private static func inspect(_ url: URL, cancellation: BackupCancellation) throws -> BackupValidation {
        let initialAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let reader = try BackupArchiveReader(url: url, cancellation: cancellation)
        let timestamp = ISO8601DateFormatter(); timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: reader.data("manifest.json", maximum: 16 * 1024 * 1024))
        guard manifest.formatVersion == BackupManifest.version,
              manifest.mappingSchemaVersion == MappingJournal.currentSchemaVersion,
              timestamp.date(from: manifest.createdAtUTC) != nil,
              manifest.createdAtUTC.hasSuffix("Z"),
              manifest.completenessStatus == (manifest.report.complete ? "complete" : "incomplete"), manifest.projectCount >= 0, manifest.observationCount >= 0 else {
            throw BackupError.invalid("Неподдерживаемая версия или структура манифеста.")
        }
        let paths = manifest.files.map(\.path)
        guard Set(paths).count == paths.count, paths.allSatisfy(BackupArchiveReader.safePath), !paths.contains("manifest.json"),
              Set(paths + ["manifest.json"]) == Set(reader.entries.map(\.path)), paths.contains(OfflineBackup.mappingPath),
              paths.contains(OfflineBackup.measurementPath) == manifest.independentJournalPresent,
              paths.allSatisfy(allowedPath),
              Set(manifest.measurementIDs).count == manifest.measurementIDs.count else { throw BackupError.invalid("Состав архива не совпадает с манифестом.") }
        let files = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        var problems: [BackupReport.Problem] = []
        for entry in reader.entries {
            try cancellation.check()
            guard let file = files[entry.path] else { continue } // manifest has already passed CRC via data().
            guard file.byteCount >= 0, file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw BackupError.invalid("Некорректные размер или SHA-256: \(file.path)")
            }
            var hash = SHA256()
            try reader.stream(entry) { hash.update(data: $0) }
            let sha = hash.finalize().map { String(format: "%02x", $0) }.joined()
            if entry.size != file.byteCount || sha != file.sha256 {
                problems.append(.init(path: file.path, reason: "Размер или SHA-256 записи ZIP не совпадает с манифестом."))
            }
        }
        let journal = try JSONDecoder().decode(MappingJournal.self, from: reader.data(OfflineBackup.mappingPath))
        try journal.validate()
        let attachments = try BackupManifest.attachments(in: journal)
        guard manifest.projectCount == journal.projects.count, manifest.observationCount == journal.observations.count,
              manifest.attachments == attachments else { throw BackupError.invalid("UUID-связи или счётчики не совпадают с графом.") }
        let pending = paths.filter { $0.hasPrefix("photos/operations/") || $0.hasPrefix("plans/operations/") }.sorted()
        guard pending == manifest.pendingOperationPaths else { throw BackupError.invalid("Список незавершённых операций не совпадает.") }
        let independent = try OfflineBackup.independentRecords(present: manifest.independentJournalPresent) {
            try reader.data(OfflineBackup.measurementPath)
        }
        guard manifest.measurementIDs == independent.0.map(\.id) else { throw BackupError.invalid("UUID независимых измерений не совпадают.") }
        problems += OfflineBackup.report(journal: journal, files: manifest.files, attachments: attachments,
                                         pending: pending, independentProblems: independent.1 + (try OfflineBackup.operationProblems(pending: pending, journal: journal) {
                                             try reader.data($0, maximum: 16 * 1024 * 1024)
                                         })).problems
        let report = BackupReport(problems: problems.sorted { ($0.path, $0.reason) < ($1.path, $1.reason) })
        let finalAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        for key in [FileAttributeKey.size, .modificationDate, .systemFileNumber] {
            guard (initialAttributes[key] as? NSObject) == (finalAttributes[key] as? NSObject) else { throw StorageError.changedFile }
        }
        guard report == manifest.report else {
            return BackupValidation(manifest: manifest, report: .init(problems: report.problems + [.init(path: "manifest.json", reason: "Заявленная полнота не совпадает с результатом проверки.")]))
        }
        return BackupValidation(manifest: manifest, report: report)
    }
    private static func allowedPath(_ path: String) -> Bool {
        path == OfflineBackup.mappingPath || path == OfflineBackup.measurementPath ||
        path.hasPrefix("mapping/recovery/") || path.hasPrefix("measurements/recovery/") ||
        path.hasPrefix("photos/") || path.hasPrefix("plans/")
    }
}
