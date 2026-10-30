import Foundation
import zlib

struct ExchangeImportError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Deliberately smaller than the Excel file format limits; shared across ZIP/XML/proposals.
struct ExchangeLimits: Sendable {
    var fileBytes = 32 * 1024 * 1024
    var entries = 256
    var partBytes = 32 * 1024 * 1024
    var expandedBytes = 128 * 1024 * 1024
    var compressionRatio = 1000
    var xmlDepth = 48
    var xmlElements = 2_000_000
    var rows = 100_000
    var cells = 500_000
    var textUTF16 = 32_767
    var sharedStrings = 200_000
}

/// ZIP32 STORE/DEFLATE, no extraction and no writes. APPNOTE 6.3.10 sections 4.3/4.4.
/// Validates both directories, payload extents, descriptors, sizes, raw deflate end and CRC.
struct ExchangeArchive {
    let parts: [String: Data]
    init(url: URL, limits: ExchangeLimits) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() <= limits.fileBytes else { throw ExchangeImportError("Файл XLSX превышает допустимый размер.") }
        try handle.seek(toOffset: 0)
        // A provider may change its file during reading: bound the read independently of stat.
        let data = try handle.read(upToCount: limits.fileBytes + 1) ?? Data()
        guard data.count <= limits.fileBytes else { throw ExchangeImportError("Размер файла изменился.") }
        try self.init(data: data, limits: limits)
    }
    init(data: Data, limits: ExchangeLimits) throws {
        func bad(_ reason: String = "Некорректный или неподдерживаемый ZIP32.") -> ExchangeImportError { ExchangeImportError(reason) }
        guard data.count >= 22, data.count <= limits.fileBytes else { throw bad() }
        // EOCD may have a bounded ZIP comment. Never accept trailing unaccounted bytes.
        var end: Int?
        for p in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if data.le(p, 4) == 0x06054b50, p + 22 + data.le(p + 20, 2) == data.count { end = p; break }
        }
        guard let end, data.le(end + 4, 2) == 0, data.le(end + 6, 2) == 0,
              data.le(end + 8, 2) == data.le(end + 10, 2) else { throw bad() }
        let count = data.le(end + 10, 2), central = data.le(end + 16, 4)
        guard count > 0, count <= limits.entries, central + data.le(end + 12, 4) == end else { throw bad() }
        struct Entry { let name: String; let start: Int; let finish: Int; let payload: Range<Int>; let size: Int; let crc: UInt32; let method: Int }
        var entries: [Entry] = [], names = Set<String>(), position = central, expanded = 0
        func extra(_ start: Int, _ length: Int) throws {
            var p = start
            while p < start + length {
                guard p + 4 <= start + length else { throw bad() }
                let tag = data.le(p, 2), n = data.le(p + 2, 2)
                guard ![0x0001, 0x0017, 0x9901, 0x7075].contains(tag), p + 4 + n <= start + length else { throw bad("ZIP64, шифрование или альтернативное имя ZIP не поддерживается.") }
                p += 4 + n
            }
        }
        for _ in 0..<count {
            try Task.checkCancellation()
            guard position + 46 <= end, data.le(position, 4) == 0x02014b50 else { throw bad() }
            let flags = data.le(position + 8, 2), method = data.le(position + 10, 2)
            let compressed = data.le(position + 20, 4), size = data.le(position + 24, 4)
            let n = data.le(position + 28, 2), x = data.le(position + 30, 2), c = data.le(position + 32, 2)
            guard flags & ~0x080E == 0, [0, 8].contains(method), method == 8 || flags & 6 == 0,
                  data.le(position + 6, 2) <= 20, data.le(position + 34, 2) == 0,
                  data.le(position + 38, 4) >> 16 & 0xF000 != 0xA000,
                  position + 46 + n + x + c <= end,
                  let name = String(data: data.subdata(in: position + 46..<position + 46 + n), encoding: .utf8),
                  BackupArchiveReader.safePath(name), !name.contains("%"),
                  name == name.precomposedStringWithCanonicalMapping,
                  names.insert(name.lowercased()).inserted else { throw bad("Недопустимый путь, повтор, ссылка или шифрование ZIP.") }
            try extra(position + 46 + n, x)
            guard size <= limits.partBytes, size <= max(1, compressed) * limits.compressionRatio,
                  expanded <= limits.expandedBytes - size else { throw bad("Превышен предел распаковки XLSX (возможная ZIP-бомба).") }
            expanded += size
            let start = data.le(position + 42, 4), crc = UInt32(data.le(position + 16, 4))
            guard start + 30 <= central, data.le(start, 4) == 0x04034b50,
                  data.le(start + 4, 2) <= 20, data.le(start + 6, 2) == flags,
                  data.le(start + 8, 2) == method, data.le(start + 26, 2) == n else { throw bad() }
            let lx = data.le(start + 28, 2), payload = start + 30 + n + lx
            guard payload + compressed <= central,
                  data.subdata(in: start + 30..<start + 30 + n) == Data(name.utf8) else { throw bad() }
            try extra(start + 30 + n, lx)
            var finish = payload + compressed
            if flags & 8 != 0 {
                guard finish + 12 <= central else { throw bad() }
                let descriptor = finish + (data.le(finish, 4) == 0x08074b50 ? 4 : 0)
                guard descriptor + 12 <= central, data.le(descriptor, 4) == Int(crc),
                      data.le(descriptor + 4, 4) == compressed, data.le(descriptor + 8, 4) == size else { throw bad() }
                finish = descriptor + 12
                // Local descriptor fields are either zero or the exact central values.
                for (offset, expected) in [(14, Int(crc)), (18, compressed), (22, size)] {
                    guard [0, expected].contains(data.le(start + offset, 4)) else { throw bad() }
                }
            } else {
                guard data.le(start + 14, 4) == Int(crc), data.le(start + 18, 4) == compressed,
                      data.le(start + 22, 4) == size else { throw bad() }
            }
            entries.append(Entry(name: name, start: start, finish: finish, payload: payload..<payload + compressed, size: size, crc: crc, method: method))
            position += 46 + n + x + c
        }
        guard position == end else { throw bad() }
        var cursor = 0
        for e in entries.sorted(by: { $0.start < $1.start }) {
            guard e.start == cursor else { throw bad("Перекрывающиеся или неучтённые записи ZIP.") }; cursor = e.finish
        }
        guard cursor == central else { throw bad() }
        var output: [String: Data] = [:]
        for e in entries {
            try Task.checkCancellation()
            let compressed = data.subdata(in: e.payload)
            let decoded: Data
            if e.method == 0 {
                guard compressed.count == e.size else { throw bad() }; decoded = compressed
            } else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw bad() }
                defer { inflateEnd(&stream) }
                // One sentinel byte detects expansion beyond the declared, pre-bounded size.
                var buffer = [UInt8](repeating: 0, count: e.size + 1)
                let status = compressed.withUnsafeBytes { input in
                    buffer.withUnsafeMutableBytes { target in
                        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(compressed.count)
                        stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(target.count)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == e.size, stream.total_in == compressed.count else { throw bad("Недопустимый поток DEFLATE или размер распаковки.") }
                decoded = Data(buffer.prefix(e.size))
            }
            let crc = decoded.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(decoded.count)) }
            guard UInt32(crc) == e.crc else { throw bad("CRC-32 записи XLSX не совпадает.") }
            output[e.name] = decoded
        }
        parts = output
    }
}
private extension Data {
    func le(_ index: Int, _ count: Int) -> Int {
        guard index >= 0, index + count <= self.count else { return -1 }
        return (0..<count).reduce(0) { $0 | Int(self[index + $1]) << ($1 * 8) }
    }
}
