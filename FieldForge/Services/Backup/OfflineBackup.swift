import Foundation
import CryptoKit

struct MeasurementBackupSource: Sendable {
    let url: URL
    let expectedBytes: Data?
}

enum OfflineBackup {
    static let mappingPath = "mapping/current.json"
    static let measurementPath = "measurements/current.json"

    /// Runs synchronously on MappingStorageOwner, with independent-journal writes
    /// excluded by its existing file-access lock. Never creates/repairs source files.
    static func capture(journal: MappingJournal, mappingBytes: Data?, sources: BackupSources,
                        measurements: MeasurementBackupSource, cancellation: BackupCancellation,
                        applicationVersion: String? = nil, parent: URL = FileManager.default.temporaryDirectory,
                        didStageFile: @Sendable (String) throws -> Void = { _ in }) throws -> BackupStaging {
        FileMeasurementStore.fileAccess.lock(); defer { FileMeasurementStore.fileAccess.unlock() }
        try cancellation.check()
        try journal.validate()
        guard sources.measurements == measurements.url else { throw StorageError.invalidRecord }
        let fm = FileManager.default
        let directory = parent.appendingPathComponent("FieldForge-Backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let inputs = try inventory(sources)
            guard try optionalBytes(sources.mapping) == mappingBytes,
                  try optionalBytes(sources.measurements) == measurements.expectedBytes else { throw StorageError.changedFile }
            var files: [BackupManifest.File] = []
            for (path, source) in inputs.sorted(by: { $0.key < $1.key }) {
                try cancellation.check()
                let target = directory.appendingPathComponent(path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                files.append(try copy(source, to: target, path: path, cancellation: cancellation))
                try didStageFile(path)
            }
            // A never-created fresh mapping graph is explicitly serialized only into staging.
            if mappingBytes == nil {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let bytes = try encoder.encode(journal)
                try fm.createDirectory(at: directory.appendingPathComponent("mapping"), withIntermediateDirectories: true)
                try bytes.write(to: directory.appendingPathComponent(mappingPath))
                files.append(.init(path: mappingPath, byteCount: bytes.count, sha256: ManagedPhotoStore.digest(bytes)))
            }
            // Re-enumerate AND rehash every source, catching additions/deletions, atomic
            // replacements and changes to same-size files during preparation.
            guard try inventory(sources) == inputs else { throw StorageError.changedFile }
            for file in files {
                guard let input = inputs[file.path] else { continue }
                let check = try digest(input, cancellation: cancellation)
                guard file.byteCount == check.0, file.sha256 == check.1 else { throw StorageError.changedFile }
            }
            guard try optionalBytes(sources.mapping) == mappingBytes,
                  try optionalBytes(sources.measurements) == measurements.expectedBytes else { throw StorageError.changedFile }
            // Bind staged JSON bytes back to the exact committed generation, not a UI draft.
            guard try JSONDecoder().decode(MappingJournal.self, from: Data(contentsOf: directory.appendingPathComponent(mappingPath))) == journal else {
                throw StorageError.changedFile
            }
            let attachments = try BackupManifest.attachments(in: journal)
            let pending = files.map(\.path).filter { $0.hasPrefix("photos/operations/") || $0.hasPrefix("plans/operations/") }.sorted()
            let independent = try independentRecords(present: measurements.expectedBytes != nil) {
                try Data(contentsOf: directory.appendingPathComponent(measurementPath))
            }
            let report = report(journal: journal, files: files, attachments: attachments, pending: pending,
                                independentProblems: independent.1 + (try operationProblems(pending: pending, journal: journal) {
                                    try Data(contentsOf: directory.appendingPathComponent($0))
                                }))
            let manifest = BackupManifest(formatVersion: BackupManifest.version, mappingSchemaVersion: MappingJournal.currentSchemaVersion,
                applicationVersion: applicationVersion, createdAtUTC: MappingCSVExport.iso(Date()),
                projectCount: journal.projects.count, observationCount: journal.observations.count,
                measurementIDs: independent.0.map(\.id), independentJournalPresent: measurements.expectedBytes != nil,
                files: files.sorted { $0.path < $1.path }, attachments: attachments, pendingOperationPaths: pending, completenessStatus: report.complete ? "complete" : "incomplete", report: report)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
            try cancellation.check()
            return BackupStaging(directory: directory, manifest: manifest)
        } catch { try? fm.removeItem(at: directory); throw error }
    }

    static func package(_ staging: BackupStaging, cancellation: BackupCancellation,
                        verifying: @Sendable () -> Void = {}) throws -> VerifiedBackup {
        defer { staging.cleanup() }
        let fm = FileManager.default
        // Keep final output independently owned until the native share sheet dismisses.
        let output = staging.directory.deletingLastPathComponent().appendingPathComponent("FieldForge-Backup-Share-\(UUID().uuidString)")
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            try cancellation.check()
            let bytes = staging.manifest.files.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
            guard bytes < Int64(UInt32.max) - 16_000_000, staging.manifest.files.count < 65_534 else {
                throw BackupError.invalid("Полный архив превышает ограничения ZIP32 (около 4 ГБ или 65 534 файлов). Резервная копия не создана.")
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd-HHmm"
            let zip = output.appendingPathComponent("FieldForge-Backup-\(formatter.string(from: Date())).zip")
            let archive = try XLSXArchive(url: zip, append: { data, handle in
                try cancellation.check(); try handle.write(contentsOf: data)
            })
            defer { archive.close() }
            for path in staging.manifest.files.map(\.path) + ["manifest.json"] {
                try cancellation.check()
                let handle = try FileHandle(forReadingFrom: staging.directory.appendingPathComponent(path))
                defer { try? handle.close() }
                try archive.bytes(path) { emit in
                    while true {
                        try cancellation.check()
                        let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
                        if chunk.isEmpty { break }; try emit(chunk)
                    }
                }
            }
            try archive.finish(); archive.close()
            verifying()
            let validation = try BackupValidator.verify(zip, cancellation: cancellation)
            guard validation.manifest == staging.manifest, validation.report == staging.manifest.report else {
                throw BackupError.invalid("Проверка созданного архива не пройдена: \(validation.report.problems.map(\.reason).joined(separator: "; "))")
            }
            try cancellation.check()
            let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return VerifiedBackup(files: MappingExportFiles(directory: output, urls: [zip]), manifest: staging.manifest,
                                  report: validation.report, byteCount: size)
        } catch { try? fm.removeItem(at: output); throw error }
    }

    private static func optionalBytes(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    /// Include every durable managed file, even orphans/recovery files. Only the
    /// explicitly disposable thumbnail directory is excluded. Fail on links/special files.
    static func inventory(_ sources: BackupSources) throws -> [String: URL] {
        let fm = FileManager.default
        var result: [String: URL] = [:]
        func add(_ url: URL, _ path: String, root: URL) throws {
            guard BackupArchiveReader.safePath(path), result[path] == nil else { throw StorageError.invalidRecord }
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw BackupError.invalid("Недопустимый исходный файл: \(path)")
            }
            result[path] = url
        }
        for (url, prefix, mainPath) in [(sources.mapping, "mapping", mappingPath), (sources.measurements, "measurements", measurementPath)] {
            let parent = url.deletingLastPathComponent()
            if fm.fileExists(atPath: parent.path) {
                for file in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                    where file.lastPathComponent == url.lastPathComponent || file.lastPathComponent.hasPrefix(url.lastPathComponent + ".") {
                    try add(file, file.lastPathComponent == url.lastPathComponent ? mainPath : prefix + "/recovery/" + file.lastPathComponent, root: parent)
                }
            }
        }
        func walk(_ root: URL, _ directory: URL, _ relative: String) throws {
            if !fm.fileExists(atPath: directory.path) { return }
            let info = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard info.isSymbolicLink != true, info.isDirectory == true else { throw BackupError.invalid("Недопустимый каталог: \(relative)") }
            for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                if relative == "photos" && file.lastPathComponent == "thumbnails" { continue }
                let child = relative + "/" + file.lastPathComponent
                let properties = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard properties.isSymbolicLink != true else { throw BackupError.invalid("Символическая ссылка: \(child)") }
                if properties.isDirectory == true { try walk(root, file, child) }
                else { try add(file, child, root: root) }
            }
        }
        try walk(sources.photos, sources.photos, "photos"); try walk(sources.plans, sources.plans, "plans")
        return result
    }
    private static func copy(_ source: URL, to target: URL, path: String, cancellation: BackupCancellation) throws -> BackupManifest.File {
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteFileExists) }
        let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
        let result = try digest(source, cancellation: cancellation) { try output.write(contentsOf: $0) }
        try output.synchronize()
        return .init(path: path, byteCount: result.0, sha256: result.1)
    }
    static func digest(_ url: URL, cancellation: BackupCancellation, emit: (Data) throws -> Void = { _ in }) throws -> (Int, String) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let start = try FileManager.default.attributesOfItem(atPath: url.path)
        var hash = SHA256(), count = 0
        while true {
            try cancellation.check()
            let data = try handle.read(upToCount: 256 * 1024) ?? Data()
            if data.isEmpty { break }
            count += data.count
            guard count < Int(UInt32.max) else { throw BackupError.invalid("Исходный файл превышает ограничение ZIP32.") }
            hash.update(data: data); try emit(data)
        }
        let end = try FileManager.default.attributesOfItem(atPath: url.path)
        for key in [FileAttributeKey.size, .modificationDate, .systemFileNumber] {
            guard (start[key] as? NSObject) == (end[key] as? NSObject) else { throw StorageError.changedFile }
        }
        return (count, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    static func independentRecords(present: Bool, read: () throws -> Data) throws -> ([Measurement], [BackupReport.Problem]) {
        guard present else { return ([], []) }
        do { return (try FileMeasurementStore.inspectBackup(read()), []) }
        catch { return ([], [.init(path: measurementPath, reason: "Независимый журнал повреждён или не поддерживается: \(error.localizedDescription)")]) }
    }
    static func operationProblems(pending: [String], journal: MappingJournal, read: (String) throws -> Data) throws -> [BackupReport.Problem] {
        var problems: [BackupReport.Problem] = []
        for path in pending {
            do {
                if path.hasPrefix("photos/") {
                    let op = try JSONDecoder().decode(PhotoImportOperation.self, from: read(path))
                    try op.validate()
                    guard path == "photos/operations/\(op.id.uuidString).json",
                          journal.projects.contains(where: { $0.id == op.photo.context.projectID }),
                          journal.horizons.contains(where: { $0.id == op.photo.context.horizonID }) else { throw StorageError.invalidRecord }
                } else {
                    let plan = try JSONDecoder().decode(MappingPlanReference.self, from: read(path))
                    guard path == "plans/operations/\(plan.id.uuidString).json", plan.file != nil,
                          journal.horizons.contains(where: { $0.id == plan.horizonID }) else { throw StorageError.invalidRecord }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { problems.append(.init(path: path, reason: "Манифест операции повреждён или содержит недействительные UUID-связи.")) }
        }
        return problems
    }

    static func report(journal: MappingJournal, files: [BackupManifest.File], attachments: [BackupManifest.Attachment],
                       pending: [String], independentProblems: [BackupReport.Problem]) -> BackupReport {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var problems = independentProblems
        for a in attachments {
            guard let file = byPath[a.path] else { problems.append(.init(path: a.path, reason: "Оригинал отсутствует.")); continue }
            if a.byteCount == nil || a.sha256 == nil {
                problems.append(.init(path: a.path, reason: "В записи отсутствуют размер и SHA-256 оригинала."))
            } else if a.byteCount != file.byteCount || a.sha256 != file.sha256 {
                problems.append(.init(path: a.path, reason: "Размер или SHA-256 оригинала не совпадает с записью."))
            }
        }
        for path in pending { problems.append(.init(path: path, reason: "Незавершённая операция сохранена; требуется разбор восстановления.")) }
        let referenced = Set(attachments.map(\.path))
        for file in files where file.path.hasPrefix("photos/") || file.path.hasPrefix("plans/") {
            if !referenced.contains(file.path) && !pending.contains(file.path) {
                problems.append(.init(path: file.path, reason: "Файл вне зафиксированного графа сохранён для восстановления."))
            }
        }
        return BackupReport(problems: problems.sorted { ($0.path, $0.reason) < ($1.path, $1.reason) })
    }
}
