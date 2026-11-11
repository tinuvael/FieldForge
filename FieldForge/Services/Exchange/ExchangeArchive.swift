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
    // Regulatory packages can carry large parts that are never inflated.
    var regulatoryDeclaredBytes = 256 * 1024 * 1024
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
/// Indexes every entry and validates its headers and extent. Only requested payloads
/// are decoded and checked for exact output length, end of stream and CRC.
struct ExchangeArchive {
    private struct Entry {
        let start: Int
        let finish: Int
        let payload: Range<Int>
        let size: Int
        let crc: UInt32
        let method: Int
    }
    private let data: Data
    private let entries: [String: Entry]
    private let limits: ExchangeLimits
    private var expanded = 0

    var paths: Set<String> { Set(entries.keys) }

    static func compressedSizeError(_ maximum: Int) -> ExchangeImportError {
        ExchangeImportError("Размер сжатого файла XLSX превышает предел \(maximum) байт.")
    }

    init(data bytes: Data, limits: ExchangeLimits, regulatory: Bool = false) throws {
        // Normalizes the indices of Data slices without making an eager copy.
        let data = Data(bytes)
        guard data.count <= limits.fileBytes else { throw Self.compressedSizeError(limits.fileBytes) }
        guard data.count >= 22 else { throw Self.bad() }
        // EOCD may have a bounded ZIP comment. Never accept trailing unaccounted bytes.
        var end: Int?
        for p in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if data.le(p, 4) == 0x06054b50, p + 22 + data.le(p + 20, 2) == data.count { end = p; break }
        }
        guard let end, data.le(end + 4, 2) == 0, data.le(end + 6, 2) == 0,
              data.le(end + 8, 2) == data.le(end + 10, 2) else { throw Self.bad() }
        let count = data.le(end + 10, 2), central = data.le(end + 16, 4)
        guard count > 0, count <= limits.entries, central + data.le(end + 12, 4) == end else { throw Self.bad() }
        let declaredLimit = regulatory ? limits.regulatoryDeclaredBytes : limits.expandedBytes
        var entries: [String: Entry] = [:], names = Set<String>(), position = central, declared = 0
        func extra(_ start: Int, _ length: Int) throws {
            var p = start
            while p < start + length {
                guard p + 4 <= start + length else { throw Self.bad() }
                let tag = data.le(p, 2), n = data.le(p + 2, 2)
                guard ![0x0001, 0x0017, 0x9901, 0x7075].contains(tag), p + 4 + n <= start + length else { throw Self.bad("ZIP64, шифрование или альтернативное имя ZIP не поддерживается.") }
                p += 4 + n
            }
        }
        for _ in 0..<count {
            try Task.checkCancellation()
            guard position + 46 <= end, data.le(position, 4) == 0x02014b50 else { throw Self.bad() }
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
                  names.insert(name.lowercased()).inserted else { throw Self.bad("Недопустимый путь, повтор, ссылка или шифрование ZIP.") }
            try extra(position + 46 + n, x)
            guard method != 0 || compressed == size else { throw Self.bad() }
            // Keep the ratio check even for entries whose payloads will be skipped.
            guard size <= max(1, compressed) * limits.compressionRatio else {
                throw ExchangeImportError("Коэффициент сжатия части XLSX «\(name)» превышает предел \(limits.compressionRatio):1.")
            }
            guard declared <= declaredLimit - size else {
                throw ExchangeImportError("Суммарный заявленный размер XLSX после распаковки превышает предел \(declaredLimit) байт.")
            }
            declared += size
            let start = data.le(position + 42, 4), crc = UInt32(data.le(position + 16, 4))
            guard start + 30 <= central, data.le(start, 4) == 0x04034b50,
                  data.le(start + 4, 2) <= 20, data.le(start + 6, 2) == flags,
                  data.le(start + 8, 2) == method, data.le(start + 26, 2) == n else { throw Self.bad() }
            let lx = data.le(start + 28, 2), payload = start + 30 + n + lx
            guard payload + compressed <= central,
                  data.subdata(in: start + 30..<start + 30 + n) == Data(name.utf8) else { throw Self.bad() }
            try extra(start + 30 + n, lx)
            var finish = payload + compressed
            if flags & 8 != 0 {
                guard finish + 12 <= central else { throw Self.bad() }
                let descriptor = finish + (data.le(finish, 4) == 0x08074b50 ? 4 : 0)
                guard descriptor + 12 <= central, data.le(descriptor, 4) == Int(crc),
                      data.le(descriptor + 4, 4) == compressed, data.le(descriptor + 8, 4) == size else { throw Self.bad() }
                finish = descriptor + 12
                // Local descriptor fields are either zero or the exact central values.
                for (offset, expected) in [(14, Int(crc)), (18, compressed), (22, size)] {
                    guard [0, expected].contains(data.le(start + offset, 4)) else { throw Self.bad() }
                }
            } else {
                guard data.le(start + 14, 4) == Int(crc), data.le(start + 18, 4) == compressed,
                      data.le(start + 22, 4) == size else { throw Self.bad() }
            }
            entries[name] = Entry(start: start, finish: finish, payload: payload..<payload + compressed, size: size, crc: crc, method: method)
            position += 46 + n + x + c
        }
        guard position == end else { throw Self.bad() }
        var cursor = 0
        for entry in entries.values.sorted(by: { $0.start < $1.start }) {
            guard entry.start == cursor else { throw Self.bad("Перекрывающиеся или неучтённые записи ZIP.") }
            cursor = entry.finish
        }
        guard cursor == central else { throw Self.bad() }
        self.data = data
        self.entries = entries
        self.limits = limits
    }

    mutating func readAll() throws -> [String: Data] {
        var parts: [String: Data] = [:]
        for path in entries.keys.sorted() { parts[path] = try read(path) }
        return parts
    }

    mutating func read(_ path: String, worksheet: String? = nil) throws -> Data {
        try Task.checkCancellation()
        guard let entry = entries[path] else { throw ExchangeImportError("Отсутствует часть XLSX: \(path)") }
        guard entry.size <= limits.partBytes else {
            let part = worksheet.map { "Обязательный лист «\($0)»" } ?? "Часть XLSX «\(path)»"
            throw ExchangeImportError("\(part) превышает предел распаковки: \(entry.size) байт при максимуме \(limits.partBytes).")
        }
        guard expanded <= limits.expandedBytes - entry.size else {
            throw ExchangeImportError("Суммарный размер распаковываемых частей XLSX превышает предел \(limits.expandedBytes) байт.")
        }
        expanded += entry.size
        let decoded = entry.method == 0 ? Data(data[entry.payload]) : try inflatePart(entry, path: path)
        let crc = decoded.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(decoded.count)) }
        guard UInt32(crc) == entry.crc else { throw Self.bad("CRC-32 части XLSX «\(path)» не совпадает.") }
        return decoded
    }

    private func inflatePart(_ entry: Entry, path: String) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Self.bad() }
        defer { inflateEnd(&stream) }
        // Inflate directly into Data. The sentinel detects an overrun even if the
        // advertised size is zero. Chunking bounds work between cancellation checks.
        var decoded = Data(count: entry.size + 1)
        try data.withUnsafeBytes { input in
            try decoded.withUnsafeMutableBytes { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
                    .advanced(by: entry.payload.lowerBound)
                stream.avail_in = uInt(entry.payload.count)
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress!
                while true {
                    try Task.checkCancellation()
                    let remaining = output.count - Int(stream.total_out)
                    guard remaining > 0 else { break }
                    stream.avail_out = uInt(min(remaining, 64 * 1024))
                    let status = inflate(&stream, Z_NO_FLUSH)
                    if status == Z_STREAM_END, stream.total_out == entry.size, stream.total_in == entry.payload.count {
                        return
                    }
                    if status != Z_OK { break }
                }
                throw Self.bad("Некорректный поток DEFLATE или размер распаковки части XLSX «\(path)».")
            }
        }
        decoded.removeLast()
        return decoded
    }

    private static func bad(_ reason: String = "Некорректная или неподдерживаемая структура ZIP32 в XLSX.") -> ExchangeImportError {
        ExchangeImportError(reason)
    }
}
private extension Data {
    func le(_ index: Int, _ count: Int) -> Int {
        guard index >= 0, index + count <= self.count else { return -1 }
        return (0..<count).reduce(0) { $0 | Int(self[index + $1]) << ($1 * 8) }
    }
}
