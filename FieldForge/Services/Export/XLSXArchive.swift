import Foundation

/// Small, write-only ZIP32 store-method archive for internally named OOXML parts.
/// APPNOTE 6.3.10: UTF-8 names, streaming descriptors, CRC-32, central directory.
/// No reader, compression dependency, ZIP64, source paths or arbitrary archive names.
final class XLSXArchive {
    private struct Entry { let name: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }
    private let handle: FileHandle
    private let append: (Data, FileHandle) throws -> Void
    private var offset: UInt64 = 0
    private var entries: [Entry] = []
    private var closed = false
    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 0 ? 0 : 0xEDB88320) }
        return c
    }
    init(url: URL, append: @escaping (Data, FileHandle) throws -> Void) throws {
        self.append = append
        // The owner creates a fresh UUID directory; never overwrite an existing file.
        guard !FileManager.default.fileExists(atPath: url.path), FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteFileExists) }
        handle = try FileHandle(forWritingTo: url)
    }
    private func emit(_ data: Data) throws {
        try Task.checkCancellation()
        guard offset + UInt64(data.count) < UInt64(UInt32.max) else {
            throw MappingError.invalid("Книга превышает ограничение ZIP32 (4 ГБ). Выберите меньший период.")
        }
        try append(data, handle); offset += UInt64(data.count)
    }
    func part(_ name: String, content: (_ emit: (String) throws -> Void) throws -> Void) throws {
        let encoded = Data(name.utf8), start = UInt32(offset)
        guard encoded.count <= Int(UInt16.max), entries.count < Int(UInt16.max) else { throw StorageError.invalidRecord }
        var header = Data()
        header.zip32(0x04034b50); header.zip16(20); header.zip16(0x0808); header.zip16(0)
        header.zip16(0); header.zip16(0x21); header.zip32(0); header.zip32(0); header.zip32(0)
        header.zip16(UInt16(encoded.count)); header.zip16(0); header.append(encoded)
        try emit(header)
        var crc: UInt32 = 0xFFFFFFFF
        let dataStart = offset
        try content { text in
            let bytes = Data(text.utf8)
            for byte in bytes { crc = Self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            try self.emit(bytes)
        }
        let size = UInt32(offset - dataStart); crc ^= 0xFFFFFFFF
        var descriptor = Data(); descriptor.zip32(0x08074b50); descriptor.zip32(crc); descriptor.zip32(size); descriptor.zip32(size)
        try emit(descriptor)
        entries.append(Entry(name: encoded, crc: crc, size: size, offset: start))
    }
    func finish() throws {
        let centralStart = UInt32(offset)
        for e in entries {
            var data = Data()
            data.zip32(0x02014b50); data.zip16(20); data.zip16(20); data.zip16(0x0808); data.zip16(0)
            data.zip16(0); data.zip16(0x21); data.zip32(e.crc); data.zip32(e.size); data.zip32(e.size)
            data.zip16(UInt16(e.name.count)); data.zip16(0); data.zip16(0); data.zip16(0); data.zip16(0)
            data.zip32(0); data.zip32(e.offset); data.append(e.name)
            try emit(data)
        }
        let centralSize = UInt32(offset) - centralStart
        var end = Data(); end.zip32(0x06054b50); end.zip16(0); end.zip16(0)
        end.zip16(UInt16(entries.count)); end.zip16(UInt16(entries.count)); end.zip32(centralSize); end.zip32(centralStart); end.zip16(0)
        try emit(end)
        try handle.synchronize()
    }
    func close() { if !closed { try? handle.close(); closed = true } }
    deinit { close() }
}

private extension Data {
    mutating func zip16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func zip32(_ value: UInt32) { zip16(UInt16(truncatingIfNeeded: value)); zip16(UInt16(truncatingIfNeeded: value >> 16)) }
}
