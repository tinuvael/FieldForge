import Foundation
import CryptoKit

/// Read-only v1 ZIP profile: ZIP32, STORE, UTF-8, signed descriptors (APPNOTE 6.3.10).
/// No extraction, filesystem writes, deflate, links, encryption, ZIP64 or ambiguous headers.
final class BackupArchiveReader {
    struct Entry { let path: String; let offset: UInt64; let size: Int; let crc: UInt32 }
    private let handle: FileHandle
    private(set) var entries: [Entry] = []
    private let cancellation: BackupCancellation

    init(url: URL, cancellation: BackupCancellation) throws {
        self.cancellation = cancellation
        handle = try FileHandle(forReadingFrom: url)
        do { try readDirectory() } catch { try? handle.close(); throw error }
    }
    deinit { try? handle.close() }

    static func safePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.contains("\\") && !path.contains(":") &&
            path.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 } &&
            parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private func read(_ offset: UInt64, _ count: Int) throws -> Data {
        try cancellation.check()
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw BackupError.invalid("Обрезанный ZIP.") }
        return data
    }
    private func readDirectory() throws {
        let length = try handle.seekToEnd()
        guard length >= 22, length < UInt64(UInt32.max) else { throw BackupError.invalid("Неподдерживаемый размер ZIP32.") }
        let end = try read(length - 22, 22)
        guard end.le(0, 4) == 0x06054b50, end.le(4, 2) == 0, end.le(6, 2) == 0,
              end.le(8, 2) == end.le(10, 2), end.le(20, 2) == 0 else { throw BackupError.invalid("Некорректный каталог ZIP.") }
        let central = UInt64(end.le(16, 4)), size = UInt64(end.le(12, 4))
        guard central + size == length - 22 else { throw BackupError.invalid("Некорректная граница каталога ZIP.") }
        var position = central, localPosition: UInt64 = 0, names = Set<String>()
        for _ in 0..<end.le(10, 2) {
            let h = try read(position, 46)
            let nameLength = h.le(28, 2), bytes = try read(position + 46, nameLength)
            guard h.le(0, 4) == 0x02014b50, h.le(4, 2) == 20, h.le(6, 2) == 20,
                  h.le(8, 2) == 0x0808, h.le(10, 2) == 0,
                  h.le(20, 4) == h.le(24, 4), h.le(30, 2) == 0, h.le(32, 2) == 0,
                  h.le(34, 2) == 0, h.le(36, 2) == 0, h.le(38, 4) == 0,
                  let path = String(data: bytes, encoding: .utf8), Self.safePath(path),
                  names.insert(path).inserted, UInt64(h.le(42, 4)) == localPosition else {
                throw BackupError.invalid("Недопустимый путь, повтор или формат записи ZIP.")
            }
            let local = try read(localPosition, 30)
            guard local.le(0, 4) == 0x04034b50, local.le(4, 2) == 20, local.le(6, 2) == 0x0808,
                  local.le(8, 2) == 0, local.le(14, 4) == 0, local.le(18, 4) == 0, local.le(22, 4) == 0,
                  local.le(26, 2) == nameLength, local.le(28, 2) == 0,
                  try read(localPosition + 30, nameLength) == bytes else { throw BackupError.invalid("Заголовки ZIP расходятся.") }
            let start = localPosition + 30 + UInt64(nameLength), count = h.le(24, 4)
            guard start + UInt64(count) + 16 <= central else { throw BackupError.invalid("Запись ZIP выходит за границы.") }
            let descriptor = try read(start + UInt64(count), 16), crc = UInt32(h.le(16, 4))
            guard descriptor.le(0, 4) == 0x08074b50, descriptor.le(4, 4) == Int(crc),
                  descriptor.le(8, 4) == count, descriptor.le(12, 4) == count else { throw BackupError.invalid("Некорректный дескриптор ZIP.") }
            entries.append(Entry(path: path, offset: start, size: count, crc: crc))
            localPosition = start + UInt64(count) + 16
            position += 46 + UInt64(nameLength)
            guard position <= length - 22 else { throw BackupError.invalid("Обрезанный каталог ZIP.") }
        }
        guard position == length - 22, localPosition == central else { throw BackupError.invalid("Неучтённые записи ZIP.") }
    }
    func stream(_ entry: Entry, emit: (Data) throws -> Void) throws {
        try handle.seek(toOffset: entry.offset)
        var remaining = entry.size, crc: UInt32 = 0xffffffff
        while remaining > 0 {
            try cancellation.check()
            let chunk = try handle.read(upToCount: min(256 * 1024, remaining)) ?? Data()
            guard !chunk.isEmpty else { throw BackupError.invalid("Обрезанный файл: \(entry.path)") }
            remaining -= chunk.count
            for byte in chunk { crc = Self.crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
            try emit(chunk)
        }
        guard crc ^ 0xffffffff == entry.crc else { throw BackupError.invalid("CRC-32 не совпадает: \(entry.path)") }
    }
    func data(_ path: String, maximum: Int = 256 * 1024 * 1024) throws -> Data {
        guard let entry = entries.first(where: { $0.path == path }), entry.size <= maximum else {
            throw BackupError.invalid("Отсутствует или слишком велик: \(path)")
        }
        var result = Data(); try stream(entry) { result.append($0) }; return result
    }
    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 0 ? 0 : 0xedb88320) }
        return c
    }
}
private extension Data {
    func le(_ index: Int, _ count: Int) -> Int { (0..<count).reduce(0) { $0 | Int(self[index + $1]) << ($1 * 8) } }
}
