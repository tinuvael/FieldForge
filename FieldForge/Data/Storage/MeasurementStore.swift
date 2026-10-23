import Foundation

protocol MeasurementStore {
    func load() throws -> [Measurement]
    func save(_ measurements: [Measurement]) throws
}

enum StorageError: LocalizedError {
    case unsupportedVersion, invalidRecord, writesBlocked, changedFile, backupConflict
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Версия журнала не поддерживается. Исходный файл сохранён."
        case .invalidRecord: return "Журнал содержит некорректную запись. Исходный файл сохранён."
        case .writesBlocked: return "Запись заблокирована после ошибки чтения журнала."
        case .changedFile: return "Файл журнала изменился. Откройте журнал заново перед записью."
        case .backupConflict: return "Резервная копия Phase 1 отличается от исходного файла. Миграция остановлена."
        }
    }
}

final class FileMeasurementStore: MeasurementStore {
    // Serializes existing synchronous access with read-only backup capture.
    // Recursive because save may invoke load; wire/migration behavior is unchanged.
    static let fileAccess = NSRecursiveLock()
    static let schemaVersion = 2
    struct Envelope: Codable { var schemaVersion: Int; var measurements: [Measurement] }
    private struct Header: Decodable { var schemaVersion: Int }
    private struct LegacyEnvelope: Decodable { var schemaVersion: Int; var measurements: [LegacyMeasurement] }
    /// Exact Phase 1 wire contract. A legacy record always requires real stored diagnostics.
    private struct LegacyMeasurement: Decodable {
        var id: UUID
        var timestamp: Date
        var orientation: PlaneOrientation
        var reference: GeographicReference
        var quality: MeasurementQuality
        var sample: SensorSample
        var notes: String
        var plane: String
        var algorithmVersion: String

        var migrated: Measurement {
            Measurement(id: id, timestamp: timestamp, orientation: orientation, reference: reference,
                        quality: quality, sample: sample, notes: notes, plane: plane,
                        algorithmVersion: algorithmVersion,
                        source: sample.source == .coreMotion ? .iPhoneSensor : .simulatorMock,
                        directionMeaning: orientation.dipDirection == nil ? .undefined : .downhill)
        }
    }
    let url: URL
    var legacyBackupURL: URL { url.appendingPathExtension("phase1-backup") }
    private var hasLoaded = false
    private var writesBlocked = false
    private var loadedBytes: Data?
    private var writeEpoch: UUID?
    /// Accessed only under fileAccess, including every read and mutation below.
    private final class Epochs: @unchecked Sendable { var values: [String: UUID] = [:] }
    private static let epochs = Epochs()
    static func invalidateWriters(at url: URL) {
        fileAccess.lock(); defer { fileAccess.unlock() }
        epochs.values[url.path] = UUID()
    }
    private var currentEpoch: UUID {
        if let value = Self.epochs.values[url.path] { return value }
        let value = UUID(); Self.epochs.values[url.path] = value; return value
    }
    init(url: URL) { self.url = url }

    /// Adopt only a fully validated load result; later saves still compare exact
    /// bytes and the restore epoch before writing. No decoding on MainActor.
    init(opened: OpenedMeasurements) {
        url = opened.source.url
        Self.fileAccess.lock(); defer { Self.fileAccess.unlock() }
        loadedBytes = opened.source.expectedBytes; hasLoaded = true; writeEpoch = currentEpoch
    }

    static func applicationStore() throws -> FileMeasurementStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FieldForge", isDirectory: true)
        return FileMeasurementStore(url: directory.appendingPathComponent("measurements-v1.json"))
    }

    func load() throws -> [Measurement] {
        try load(preservingLegacy: FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(OfflineRestore.marker).path))
    }
    /// Restore never migrates its source bytes. A durable dataset marker retains
    /// this read behavior across launches; ordinary saves still use deployed v2.
    func loadRestored() throws -> [Measurement] { try load(preservingLegacy: true) }
    private func load(preservingLegacy: Bool) throws -> [Measurement] {
        Self.fileAccess.lock(); defer { Self.fileAccess.unlock() }
        do {
            writeEpoch = currentEpoch
            let bytes = try currentBytes()
            guard let bytes else {
                hasLoaded = true; writesBlocked = false; loadedBytes = nil
                return []
            }
            let decoder = JSONDecoder()
            let version = try decoder.decode(Header.self, from: bytes).schemaVersion
            let records: [Measurement]
            switch version {
            case 1:
                records = try decoder.decode(LegacyEnvelope.self, from: bytes).measurements.map(\.migrated)
                try validate(records)
                if preservingLegacy {
                    loadedBytes = bytes; hasLoaded = true; writesBlocked = false
                    return records.sorted { $0.timestamp > $1.timestamp }
                }
                let migratedBytes = try encoded(records)
                // Validate a full round trip before touching either file.
                guard try decoder.decode(Envelope.self, from: migratedBytes).measurements == records else {
                    throw StorageError.invalidRecord
                }
                if FileManager.default.fileExists(atPath: legacyBackupURL.path) {
                    guard try Data(contentsOf: legacyBackupURL) == bytes else { throw StorageError.backupConflict }
                } else {
                    // copyItem refuses to overwrite an existing backup. A partial backup
                    // on I/O failure blocks retry; the original journal stays untouched.
                    try FileManager.default.copyItem(at: url, to: legacyBackupURL)
                }
                guard try Data(contentsOf: legacyBackupURL) == bytes else { throw StorageError.backupConflict }
                guard try currentBytes() == bytes else { throw StorageError.changedFile }
                try migratedBytes.write(to: url, options: .atomic)
                loadedBytes = migratedBytes
            case Self.schemaVersion:
                records = try decoder.decode(Envelope.self, from: bytes).measurements
                try validate(records)
                loadedBytes = bytes
            default: throw StorageError.unsupportedVersion
            }
            hasLoaded = true; writesBlocked = false
            return records.sorted { $0.timestamp > $1.timestamp }
        } catch {
            writesBlocked = true
            throw error
        }
    }
    func save(_ measurements: [Measurement]) throws {
        Self.fileAccess.lock(); defer { Self.fileAccess.unlock() }
        guard !writesBlocked else { throw StorageError.writesBlocked }
        if !hasLoaded { _ = try load() }
        guard writeEpoch == currentEpoch else { throw StorageError.writesBlocked }
        try validate(measurements)
        guard try currentBytes() == loadedBytes else { throw StorageError.changedFile }
        let data = try encoded(measurements)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        loadedBytes = data
    }
    func backupSource() throws -> MeasurementBackupSource {
        Self.fileAccess.lock(); defer { Self.fileAccess.unlock() }
        guard hasLoaded, !writesBlocked, writeEpoch == currentEpoch else { throw StorageError.writesBlocked }
        return MeasurementBackupSource(url: url, expectedBytes: loadedBytes)
    }

    /// Decode deployed versions without triggering migration, backups or live writes.
    static func inspectBackup(_ bytes: Data) throws -> [Measurement] {
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: bytes).schemaVersion
        let records: [Measurement]
        switch version {
        case 1: records = try decoder.decode(LegacyEnvelope.self, from: bytes).measurements.map(\.migrated)
        case schemaVersion: records = try decoder.decode(Envelope.self, from: bytes).measurements
        default: throw StorageError.unsupportedVersion
        }
        guard records.allSatisfy(\.isSavable), Set(records.map(\.id)).count == records.count else { throw StorageError.invalidRecord }
        return records
    }
    private func currentBytes() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    private func encoded(_ measurements: [Measurement]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(schemaVersion: Self.schemaVersion, measurements: measurements))
    }
    private func validate(_ records: [Measurement]) throws {
        guard records.allSatisfy(\.isSavable), Set(records.map(\.id)).count == records.count else {
            throw StorageError.invalidRecord
        }
    }
}

struct OpenedMeasurements: Sendable {
    let records: [Measurement]
    let source: MeasurementBackupSource
}
