import Foundation

/// Structural preflight before Codable: bounded nesting/tokens and no duplicate object
/// keys (including escaped spellings). Codable performs the final typed value checks.
struct ExchangeJSON {
    private let bytes: [UInt8]
    private var position = 0
    private var tokens = 0
    static func validate(_ text: String) throws {
        guard text.utf8.count <= 32 * 1024 * 1024 else { throw ExchangeImportError("Исходный JSON слишком велик.") }
        var reader = ExchangeJSON(bytes: Array(text.utf8))
        try reader.value(depth: 0); reader.whitespace()
        guard reader.position == reader.bytes.count else { throw ExchangeImportError("Лишнее содержимое JSON.") }
    }
    private mutating func whitespace() { while position < bytes.count && [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
    private mutating func consume(_ byte: UInt8) throws {
        whitespace()
        guard position < bytes.count, bytes[position] == byte else { throw ExchangeImportError("Нарушена структура JSON.") }
        position += 1
    }
    private mutating func string(key: Bool) throws -> String? {
        whitespace(); let start = position
        try consume(34)
        var escaped = false
        while position < bytes.count {
            let c = bytes[position]; position += 1
            if escaped { escaped = false }
            else if c == 92 { escaped = true }
            else if c == 34 {
                if key {
                    guard position - start <= 32_767 else { throw ExchangeImportError("Ключ JSON слишком длинный.") }
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
                }
                return nil
            }
        }
        throw ExchangeImportError("Незавершённая строка JSON.")
    }
    private mutating func value(depth: Int) throws {
        try Task.checkCancellation()
        tokens += 1; whitespace()
        guard depth < 48, tokens <= 1_000_000, position < bytes.count else { throw ExchangeImportError("Превышен предел сложности JSON.") }
        switch bytes[position] {
        case 123:
            position += 1; whitespace(); var keys = Set<String>()
            if position < bytes.count, bytes[position] == 125 { position += 1; return }
            while true {
                let key = try string(key: true)!
                guard keys.insert(key).inserted else { throw ExchangeImportError("Повторный ключ JSON: \(key). Неоднозначные значения запрещены.") }
                try consume(58); try value(depth: depth + 1); whitespace()
                guard position < bytes.count else { throw ExchangeImportError("Незавершённый объект JSON.") }
                if bytes[position] == 125 { position += 1; break }; try consume(44)
            }
        case 91:
            position += 1; whitespace()
            if position < bytes.count, bytes[position] == 93 { position += 1; return }
            while true {
                try value(depth: depth + 1); whitespace()
                guard position < bytes.count else { throw ExchangeImportError("Незавершённый массив JSON.") }
                if bytes[position] == 93 { position += 1; break }; try consume(44)
            }
        case 34: _ = try string(key: false)
        default:
            let start = position
            while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) { position += 1 }
            guard position > start, position - start <= 128 else { throw ExchangeImportError("Некорректный скаляр JSON.") }
        }
    }
}
