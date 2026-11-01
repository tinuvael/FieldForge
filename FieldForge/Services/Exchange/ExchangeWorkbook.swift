import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ExchangeWorkbook: Sendable {
    typealias Row = [String: String]
    struct Sheet: Sendable { let columns: [String]; let rows: [Row] }
    let sheets: [String: Sheet]
    static let spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let documentRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    init(url: URL, limits: ExchangeLimits = .init()) throws {
        try self.init(parts: ExchangeArchive(url: url, limits: limits).parts, limits: limits)
    }
    init(parts: [String: Data], limits: ExchangeLimits = .init()) throws {
        func fail(_ s: String) -> ExchangeImportError { ExchangeImportError(s) }
        let fixed = Set(["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/sharedStrings.xml", "docProps/core.xml", "docProps/app.xml"])
        for path in parts.keys {
            guard fixed.contains(path) || path.range(of: #"^xl/(worksheets/[^/]+|theme/theme[0-9]+)\.xml$"#, options: .regularExpression) != nil else {
                throw fail("Неподдерживаемая часть XLSX: \(path). Макросы, подключения и внешние ссылки запрещены.")
            }
        }
        func xml(_ path: String, namespace: String, start: @escaping ExchangeXML.Start = { _, _, _ in }, end: @escaping ExchangeXML.End = { _, _, _ in }) throws {
            guard let data = parts[path] else { throw fail("Отсутствует часть XLSX: \(path)") }
            try ExchangeXML.read(data, namespace: namespace, limits: limits, start: start, end: end)
        }
        struct Rel { let type: String; let target: String }
        func rels(_ path: String, base: String, allowed: Set<String>) throws -> [String: Rel] {
            var result: [String: Rel] = [:]
            try xml(path, namespace: Self.relationships, start: { name, attrs, ancestors in
                guard ancestors == ["Relationships"], name == "Relationship" else {
                    if ancestors.isEmpty && name == "Relationships" { return }; throw fail("Некорректные связи XLSX.")
                }
                guard let id = attrs["Id"], !id.isEmpty, result[id] == nil, attrs["TargetMode"] == nil || attrs["TargetMode"] == "Internal",
                      let type = attrs["Type"], allowed.contains(type), let raw = attrs["Target"], !raw.contains("%"), !raw.contains("#"), !raw.contains("?") else { throw fail("Внешняя, повторная или неподдерживаемая связь XLSX.") }
                let target = raw.hasPrefix("/") ? String(raw.dropFirst()) : base + raw
                guard BackupArchiveReader.safePath(target), parts[target] != nil else { throw fail("Некорректная цель связи XLSX: \(raw)") }
                result[id] = Rel(type: type, target: target)
            })
            guard Set(result.values.map(\.target)).count == result.count else { throw fail("Неоднозначные цели связей XLSX.") }
            return result
        }
        let d = Self.documentRelationships
        let root = try rels("_rels/.rels", base: "", allowed: [d + "officeDocument", d + "extended-properties", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"])
        guard root.values.filter({ $0.type == d + "officeDocument" }).map(\.target) == ["xl/workbook.xml"] else { throw fail("Неоднозначная книга XLSX.") }
        let relationships = try rels("xl/_rels/workbook.xml.rels", base: "xl/", allowed: Set(["worksheet", "styles", "sharedStrings", "theme"].map { d + $0 }))
        let referenced = Set(root.values.map(\.target) + relationships.values.map(\.target)).union(["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels"])
        guard Set(parts.keys) == referenced else { throw fail("Неучтённые части пакета XLSX.") }
        var overrides: [String: String] = [:], defaults: [String: String] = [:]
        try xml("[Content_Types].xml", namespace: "http://schemas.openxmlformats.org/package/2006/content-types", start: { name, a, ancestors in
            if ancestors.isEmpty && name == "Types" { return }
            guard ancestors == ["Types"] else { throw fail("Некорректный каталог типов XLSX.") }
            if name == "Override", let p = a["PartName"], p.hasPrefix("/"), let t = a["ContentType"], overrides[p] == nil { overrides[p] = t }
            else if name == "Default", let e = a["Extension"], let t = a["ContentType"], defaults[e] == nil { defaults[e] = t }
            else { throw fail("Повторный или неизвестный тип части XLSX.") }
        })
        let types = Set(["application/xml", "application/vnd.openxmlformats-package.relationships+xml", "application/vnd.openxmlformats-package.core-properties+xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml", "application/vnd.openxmlformats-officedocument.theme+xml"])
        guard overrides.allSatisfy({ $0.key.hasPrefix("/") && parts[String($0.key.dropFirst())] != nil && types.contains($0.value) }), defaults.values.allSatisfy(types.contains) else { throw fail("Неподдерживаемые типы XLSX (макросы/подключения запрещены).") }
        for path in parts.keys where path != "[Content_Types].xml" {
            guard let t = overrides["/" + path] ?? defaults[path.hasSuffix(".rels") ? "rels" : (path as NSString).pathExtension], types.contains(t) else { throw fail("Неизвестный тип части \(path)") }
        }
        let expectedTypes: [String: String] = [
            d + "officeDocument": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
            d + "worksheet": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
            d + "styles": "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml",
            d + "sharedStrings": "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml",
            d + "theme": "application/vnd.openxmlformats-officedocument.theme+xml",
            d + "extended-properties": "application/vnd.openxmlformats-officedocument.extended-properties+xml",
            "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties": "application/vnd.openxmlformats-package.core-properties+xml"]
        for rel in Array(root.values) + Array(relationships.values) {
            let actual = overrides["/" + rel.target] ?? defaults[(rel.target as NSString).pathExtension]
            guard actual == expectedTypes[rel.type] else { throw fail("Тип части не совпадает с её связью.") }
        }
        var shared: [String] = [], sharedValue = ""
        if let sharedPath = relationships.values.first(where: { $0.type == d + "sharedStrings" })?.target {
            try xml(sharedPath, namespace: Self.spreadsheet, start: { name, _, ancestors in
                if name == "si" { guard ancestors == ["sst"] else { throw fail("Некорректные shared strings.") }; sharedValue = "" }
                guard ["sst", "si", "t", "r", "rPr", "b", "i", "u", "sz", "color", "rFont", "family", "charset", "scheme", "vertAlign", "strike", "outline", "shadow", "condense", "extend"].contains(name) else { throw fail("Неподдерживаемая разметка shared strings.") }
            }, end: { name, text, _ in
                if name == "t" { sharedValue += text; guard sharedValue.utf16.count <= limits.textUTF16 else { throw fail("Слишком длинная строка XLSX.") } }
                if name == "si" { guard shared.count < limits.sharedStrings else { throw fail("Слишком много shared strings.") }; shared.append(try Self.unescape(sharedValue)) }
            })
        }
        var sheetPaths: [String: String] = [:], sheetIDs = Set<String>()
        try xml("xl/workbook.xml", namespace: Self.spreadsheet, start: { name, a, ancestors in
            if name == "sheet" {
                guard ancestors == ["workbook", "sheets"], let name = a["name"], sheetPaths[name] == nil,
                      let id = a["r:id"], let rel = relationships[id], rel.type == d + "worksheet",
                      let sheetID = a["sheetId"], sheetIDs.insert(sheetID).inserted,
                      !sheetPaths.values.contains(rel.target) else { throw fail("Неоднозначная идентичность листа XLSX.") }
                sheetPaths[name] = rel.target
            }
            if ["externalReferences", "definedNames", "pivotCaches", "extLst"].contains(name) { throw fail("Неподдерживаемые ссылки или расширения книги XLSX.") }
        })
        guard sheetPaths.count <= 32, Set(sheetPaths.values) == Set(relationships.values.filter { $0.type == d + "worksheet" }.map(\.target)) else { throw fail("Неучтённые листы XLSX.") }
        var output: [String: Sheet] = [:], totalCells = 0, totalRows = 0
        for (sheet, path) in sheetPaths.sorted(by: { $0.key < $1.key }) {
            var rows: [Int: [Int: String]] = [:], rowNumbers = Set<Int>(), currentRow: Int?, currentColumn: Int?, cellType = "", cellText = "", cellValue = "", seenValue = false, seenInline = false
            try xml(path, namespace: Self.spreadsheet, start: { name, a, ancestors in
                if ["f", "hyperlinks", "oleObjects", "controls", "extLst", "tableParts", "drawing", "legacyDrawing"].contains(name) { throw fail("\(sheet): формулы (включая кеш), ссылки и встроенные объекты запрещены.") }
                if name == "row" {
                    guard ancestors == ["worksheet", "sheetData"], let n = a["r"].flatMap(Int.init), (1...1_048_576).contains(n), rowNumbers.insert(n).inserted else { throw fail("\(sheet): повторная или неверная строка.") }
                    totalRows += 1; guard totalRows <= limits.rows else { throw fail("Превышен предел строк XLSX.") }; currentRow = n; rows[n] = [:]
                }
                if name == "c" {
                    guard ancestors == ["worksheet", "sheetData", "row"], let row = currentRow, let address = a["r"], let (column, number) = Self.address(address), number == row, rows[row]?[column] == nil else { throw fail("\(sheet): повторная или неверная ячейка.") }
                    totalCells += 1; guard totalCells <= limits.cells else { throw fail("Превышен предел ячеек XLSX.") }
                    currentColumn = column; cellType = a["t"] ?? ""; cellText = ""; cellValue = ""; seenValue = false; seenInline = false
                    guard ["", "n", "s", "inlineStr"].contains(cellType) else { throw fail("\(sheet)!\(address): тип ячейки не текстовый; возможна потеря точности или преобразование даты.") }
                }
                if currentColumn != nil {
                    guard ["c", "is", "t", "r", "rPr", "b", "i", "u", "sz", "color", "rFont", "family", "charset", "scheme", "vertAlign", "strike", "v"].contains(name) else { throw fail("\(sheet): неподдерживаемое содержимое ячейки.") }
                    if name == "v" { guard !seenValue, ancestors.last == "c" else { throw fail("Неоднозначное значение ячейки.") }; seenValue = true }
                    if name == "is" { guard !seenInline, ancestors.last == "c" else { throw fail("Неоднозначная строка ячейки.") }; seenInline = true }
                    if name == "t", !ancestors.contains("is") { throw fail("Строка вне inlineStr.") }
                }
            }, end: { name, text, _ in
                if currentColumn != nil {
                    if name == "t" { cellText += text }
                    if name == "v" { cellValue += text }
                    guard cellText.utf16.count <= limits.textUTF16 else { throw fail("Слишком длинный текст ячейки.") }
                }
                if name == "c", let row = currentRow, let col = currentColumn {
                    let value: String
                    switch cellType {
                    case "s":
                        guard seenValue, !seenInline, let i = Int(cellValue), i >= 0, i < shared.count else { throw fail("Некорректный индекс shared strings.") }; value = shared[i]
                    case "inlineStr":
                        guard !seenValue else { throw fail("Неоднозначное текстовое значение.") }; value = try Self.unescape(cellText)
                    default:
                        guard !seenValue, !seenInline else { throw fail("\(sheet), строка \(row): числовая/датированная ячейка; восстановить точность нельзя. Сохраните исходные значения как текст.") }; value = ""
                    }
                    rows[row]?[col] = value; currentColumn = nil
                }
                if name == "row" { currentRow = nil }
            })
            guard let header = rows.removeValue(forKey: 1), let max = header.keys.max(), max < 256 else { throw fail("\(sheet): отсутствует заголовок.") }
            let columns = (0...max).map { header[$0] ?? "" }
            guard !columns.contains(""), Set(columns).count == columns.count else { throw fail("\(sheet): пустые или повторные колонки.") }
            var values: [Row] = []
            for (_, cells) in rows.sorted(by: { $0.key < $1.key }) {
                guard cells.keys.allSatisfy({ $0 <= max || cells[$0] == "" }) else { throw fail("\(sheet): данные за пределами колонок.") }
                if cells.values.allSatisfy(\.isEmpty) { continue }
                values.append(Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, cells[$0.offset] ?? "") }))
            }
            output[sheet] = Sheet(columns: columns, rows: values)
        }
        // Parse even unused metadata/styles to reject DTD/entities and malformed XML everywhere.
        let alreadyParsed = Set(sheetPaths.values).union(["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/workbook.xml", "xl/sharedStrings.xml"])
        for path in parts.keys where !alreadyParsed.contains(path) {
            let ns = path == "xl/styles.xml" ? Self.spreadsheet : path.hasPrefix("xl/theme/") ? "http://schemas.openxmlformats.org/drawingml/2006/main" : nil
            try ExchangeXML.read(parts[path]!, namespace: ns, limits: limits)
        }
        sheets = output
    }
    static func address(_ s: String) -> (Int, Int)? {
        let a = Array(s.utf8); var p = 0, c = 0
        while p < a.count, (65...90).contains(a[p]) { c = c * 26 + Int(a[p] - 64); p += 1; if c > 16_384 { return nil } }
        guard c > 0, p < a.count, let row = Int(String(decoding: a[p...], as: UTF8.self)), row > 0, row <= 1_048_576 else { return nil }
        return (c - 1, row)
    }
    /// ST_Xstring decoding once, including surrogate pairs and protected literal escapes.
    static func unescape(_ text: String) throws -> String {
        let a = Array(text.utf16); var out: [UInt16] = [], p = 0
        while p < a.count {
            if p + 6 < a.count, a[p] == 95, [88, 120].contains(a[p + 1]), a[p + 6] == 95,
               let code = UInt16(String(decoding: a[p + 2...p + 5], as: UTF16.self), radix: 16) { out.append(code); p += 7 }
            else { out.append(a[p]); p += 1 }
        }
        let value = String(decoding: out, as: UTF16.self)
        guard Array(value.utf16) == out else { throw ExchangeImportError("Некорректная пара Unicode в тексте XLSX.") }; return value
    }
}

/// SAX parser: no DOM, entity resolution, network access or unbounded text accumulation.
private final class ExchangeXML: NSObject, XMLParserDelegate {
    typealias Start = (String, [String: String], [String]) throws -> Void
    typealias End = (String, String, [String]) throws -> Void
    let limits: ExchangeLimits; let namespace: String?; let start: Start; let end: End
    var stack: [String] = [], texts: [String] = [], elements = 0
    var error: Error?
    init(namespace: String?, limits: ExchangeLimits, start: @escaping Start, end: @escaping End) {
        self.namespace = namespace; self.limits = limits; self.start = start; self.end = end
    }
    static func read(_ data: Data, namespace: String?, limits: ExchangeLimits, start: @escaping Start = { _, _, _ in }, end: @escaping End = { _, _, _ in }) throws {
        guard data.count <= limits.partBytes, let raw = String(data: data, encoding: .utf8),
              !raw.localizedCaseInsensitiveContains("<!DOCTYPE"), !raw.localizedCaseInsensitiveContains("<!ENTITY"),
              !raw.contains("\u{0}"), raw.range(of: #"encoding\s*=\s*["'](?!UTF-8["']|utf-8["'])"#, options: .regularExpression) == nil else {
            throw ExchangeImportError("DTD, сущности и кодировки кроме UTF-8 запрещены.")
        }
        let delegate = ExchangeXML(namespace: namespace, limits: limits, start: start, end: end)
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false; parser.shouldReportNamespacePrefixes = true; parser.delegate = delegate
        guard parser.parse(), delegate.error == nil else { throw delegate.error ?? ExchangeImportError("Некорректный XML XLSX.") }
    }
    func checked(_ parser: XMLParser, _ body: () throws -> Void) {
        do { try Task.checkCancellation(); try body() } catch { self.error = error; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        checked(parser) {
            elements += 1
            guard stack.count < limits.xmlDepth, elements <= limits.xmlElements, attributes.count <= 64,
                  attributes.allSatisfy({ $0.key.utf16.count <= 256 && $0.value.utf16.count <= limits.textUTF16 }),
                  namespace == nil || namespaceURI == namespace else { throw ExchangeImportError("Превышен предел XML или неподдерживаемое пространство имён.") }
            try start(name, attributes, stack); stack.append(name); texts.append("")
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        checked(parser) {
            guard let last = texts.indices.last else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !["t", "v"].contains(stack[last]) { return }
            guard texts[last].utf16.count + text.utf16.count <= limits.textUTF16 else { throw ExchangeImportError("Превышен предел текста XML.") }
            texts[last] += text
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        checked(parser) { guard let text = texts.popLast(), stack.popLast() == name else { throw ExchangeImportError("Нарушена структура XML.") }; try end(name, text, stack) }
    }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        if prefix == "r", namespaceURI != String(ExchangeWorkbook.documentRelationships.dropLast()) {
            error = ExchangeImportError("Подмена пространства имён связи XLSX."); parser.abortParsing()
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { error = ExchangeImportError("CDATA в XLSX не поддерживается."); parser.abortParsing() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { error = ExchangeImportError("Внешние сущности запрещены."); parser.abortParsing(); return nil }
}
