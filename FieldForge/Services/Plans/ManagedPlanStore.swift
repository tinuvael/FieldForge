import Foundation
import CryptoKit

enum PlanUnits: String, Codable, CaseIterable {
    case unknown, meters, millimeters
    var coordinateUnits: String { switch self { case .unknown: return "drawing"; case .meters: return "m"; case .millimeters: return "mm" } }
    var label: String { switch self { case .unknown: return "Неизвестно · единицы чертежа"; case .meters: return "Метры"; case .millimeters: return "Миллиметры" } }
}

struct ManagedPlanFile: Codable, Equatable {
    let originalFilename: String
    let sha256: String
    let byteCount: Int
    let importedAt: Date
    let units: PlanUnits
    let crs: String
    let axes: String
    let unitDeclaration: String
    let insertionUnits: Int?
}

/// Immutable UUID filenames. A staged operation survives failed journal writes/restarts;
/// no automatic orphan deletion. Reconciliation only removes redundant operation manifests.
final class ManagedPlanStore {
    let root: URL
    init(root: URL) { self.root = root }
    func fileURL(_ plan: MappingPlanReference) -> URL { root.appendingPathComponent("originals/\(plan.attachmentID.uuidString).dxf") }
    private func operationURL(_ plan: MappingPlanReference) -> URL { root.appendingPathComponent("operations/\(plan.id.uuidString).json") }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func stage(data: Data, filename: String, horizonID: UUID, version: String,
               units: PlanUnits, crs: String, axes: String, frameConfirmation: PlanFrameConfirmation? = nil) throws -> MappingPlanReference {
        let drawing = try DXFDocument.parse(data)
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MappingError.invalid("Укажите версию плана.") }
        let plan = MappingPlanReference(id: UUID(), horizonID: horizonID, attachmentID: UUID(), version: version,
            file: ManagedPlanFile(originalFilename: URL(fileURLWithPath: filename).lastPathComponent,
                sha256: Self.digest(data), byteCount: data.count, importedAt: Date(), units: units,
                crs: crs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : crs,
                axes: axes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : axes,
                unitDeclaration: "userConfirmedAtImport", insertionUnits: drawing.insertionUnits),
            frameConfirmation: frameConfirmation)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("operations"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("originals"), withIntermediateDirectories: true)
        try JSONEncoder().encode(plan).write(to: operationURL(plan), options: .atomic)
        try data.write(to: fileURL(plan), options: .atomic)
        _ = try read(plan)
        return plan
    }
    func read(_ plan: MappingPlanReference) throws -> Data {
        guard let file = plan.file else { throw MappingError.invalid("У старой ссылки нет управляемого файла. Импортируйте DXF.") }
        let url = fileURL(plan)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == file.byteCount, file.byteCount <= 10_000_000 else { throw MappingError.invalid("Размер DXF изменён. Исходные ссылки сохранены.") }
        let data = try Data(contentsOf: url)
        guard Self.digest(data) == file.sha256 else { throw MappingError.invalid("DXF повреждён: SHA-256 не совпадает. Исходные ссылки сохранены.") }
        return data
    }
    func complete(_ plan: MappingPlanReference) {
        // A leftover manifest is harmless and reconciled against the authoritative graph.
        try? FileManager.default.removeItem(at: operationURL(plan))
    }
    func pending() throws -> [MappingPlanReference] {
        let directory = root.appendingPathComponent("operations")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(MappingPlanReference.self, from: Data(contentsOf: $0)) }
    }
}
