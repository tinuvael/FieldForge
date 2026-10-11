import Foundation

protocol MeasurementStore {
    func load() throws -> [Measurement]
    func save(_ measurements: [Measurement]) throws
}

enum StorageError: LocalizedError {
    case unsupportedVersion, invalidRecord
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Версия журнала не поддерживается. Исходный файл сохранён."
        case .invalidRecord: return "Журнал содержит некорректную запись. Исходный файл сохранён."
        }
    }
}

final class FileMeasurementStore: MeasurementStore {
    struct Envelope: Codable { var schemaVersion: Int; var measurements: [Measurement] }
    let url: URL
    init(url: URL) { self.url = url }

    static func applicationStore() throws -> FileMeasurementStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FieldForge", isDirectory: true)
        return FileMeasurementStore(url: directory.appendingPathComponent("measurements-v1.json"))
    }

    func load() throws -> [Measurement] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.schemaVersion == 1 else { throw StorageError.unsupportedVersion }
        try validate(envelope.measurements)
        return envelope.measurements.sorted { $0.timestamp > $1.timestamp }
    }
    func save(_ measurements: [Measurement]) throws {
        try validate(measurements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(schemaVersion: 1, measurements: measurements))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func validate(_ records: [Measurement]) throws {
        guard records.allSatisfy(\.isSavable), Set(records.map(\.id)).count == records.count else {
            throw StorageError.invalidRecord
        }
    }
}
