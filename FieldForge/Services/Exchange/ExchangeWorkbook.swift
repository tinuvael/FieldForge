import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ExchangeWorkbook: Sendable {
    typealias Row = [String: String]
    struct Sheet: Sendable { let columns: [String]; let rows: [Row]; var rowNumbers: [Int] = [] }
    enum DataCell: Hashable, Sendable {
        case text(String), number(String), invalid(String)
    }
    let sheets: [String: Sheet]
    let dataRows: [Int: [Int: DataCell]]
    let dataSheetRowCount: Int
    let productionLayout: Bool
    let documentID: UUID?
    static let spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let documentRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    init(parts: [String: Data], limits: ExchangeLimits = .init()) throws {
        try self.init(paths: Set(parts.keys), limits: limits, streamDataSheet: nil) { path, _ in
            guard let data = parts[path] else { throw ExchangeImportError("Отсутствует часть XLSX: \(path)") }
            return data
        }
    }

    init(regulatoryArchive archive: ExchangeArchive, limits: ExchangeLimits) throws {
        var reader = archive
        try self.init(paths: archive.paths, limits: limits,
                      streamDataSheet: { try reader.streamDataSheet($0) }) { path, worksheet in
            try reader.read(path, worksheet: worksheet)
        }
    }

    private init(paths: Set<String>, limits: ExchangeLimits,
                 streamDataSheet: ((String) throws -> ExchangeWorksheetStream)?,
                 load: @escaping (String, String?) throws -> Data) throws {
        let regulatory = streamDataSheet != nil
        func fail(_ s: String) -> ExchangeImportError { ExchangeImportError(s) }
        let d = Self.documentRelationships
        let officeType = "application/vnd.openxmlformats-officedocument."
        let sheetType = officeType + "spreadsheetml."
        let relationshipType = "application/vnd.openxmlformats-package.relationships+xml"
        let calcChainType = sheetType + "calcChain+xml"
        let printerType = sheetType + "printerSettings"
        let ignoredParts: [(String, String)] = [
            (#"^xl/worksheets/_rels/[^/]+\.xml\.rels$"#, relationshipType),
            (#"^xl/printerSettings/[^/]+\.bin$"#, printerType),
            (#"^xl/drawings/[^/]+\.xml$"#, officeType + "drawing+xml"),
            (#"^xl/drawings/[^/]+\.vml$"#, officeType + "vmlDrawing"),
            (#"^xl/ctrlProps/[^/]+\.xml$"#, "application/vnd.ms-excel.controlproperties+xml")
        ]
        let fixed = Set(["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/sharedStrings.xml", "docProps/core.xml", "docProps/app.xml"])
        var ignored: [String: String] = [:]
        for path in paths {
            if fixed.contains(path) || path.range(of: #"^xl/(worksheets/[^/]+|theme/theme[0-9]+)\.xml$"#, options: .regularExpression) != nil {
                continue
            }
            if regulatory {
                if path == "xl/calcChain.xml" { continue }
                if let (_, type) = ignoredParts.first(where: { path.range(of: $0.0, options: .regularExpression) != nil }) {
                    ignored[path] = type
                    continue
                }
            }
            throw fail("Неподдерживаемая часть XLSX: \(path). Макросы, подключения и внешние ссылки запрещены.")
        }
        func xml(_ path: String, namespace: String, root: String? = nil, worksheet: String? = nil,
                 additionalElements: [String: Set<String>] = [:],
                 start: @escaping ExchangeXML.Start = { _, _, _ in }, end: @escaping ExchangeXML.End = { _, _, _ in }) throws {
            if worksheet == "Data", let streamDataSheet {
                var sheetLimits = limits
                sheetLimits.xmlElements = limits.dataSheetElements
                try ExchangeXML.read(streamDataSheet(path), namespace: namespace, root: root, limits: sheetLimits,
                                     additionalElements: additionalElements, start: start, end: end)
            } else {
                try ExchangeXML.read(load(path, worksheet), namespace: namespace, root: root, limits: limits,
                                     additionalElements: additionalElements, start: start, end: end)
            }
        }
        struct Rel { let type: String; let target: String }
        func rels(_ path: String, base: String, allowed: Set<String>, parent: String? = nil) throws -> [String: Rel] {
            var result: [String: Rel] = [:]
            try xml(path, namespace: Self.relationships, root: "Relationships", start: { name, attrs, ancestors in
                guard ancestors == ["Relationships"], name == "Relationship" else {
                    if ancestors.isEmpty && name == "Relationships" { return }; throw fail("Некорректные связи XLSX.")
                }
                guard let id = attrs["Id"], !id.isEmpty, result[id] == nil, attrs["TargetMode"] == nil || attrs["TargetMode"] == "Internal",
                      let type = attrs["Type"], allowed.contains(type), let raw = attrs["Target"], !raw.contains("%"), !raw.contains("#"), !raw.contains("?") else { throw fail("Внешняя, повторная или неподдерживаемая связь XLSX.") }
                let target: String
                if raw.hasPrefix("/") {
                    target = String(raw.dropFirst())
                } else if let parent, raw.hasPrefix("../") {
                    target = parent + raw.dropFirst(3)
                } else {
                    target = base + raw
                }
                guard BackupArchiveReader.safePath(target), paths.contains(target) else { throw fail("Некорректная цель связи XLSX: \(raw)") }
                result[id] = Rel(type: type, target: target)
            })
            guard Set(result.values.map(\.target)).count == result.count else { throw fail("Неоднозначные цели связей XLSX.") }
            return result
        }
        let root = try rels("_rels/.rels", base: "", allowed: [d + "officeDocument", d + "extended-properties", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"])
        guard root.values.filter({ $0.type == d + "officeDocument" }).map(\.target) == ["xl/workbook.xml"] else { throw fail("Неоднозначная книга XLSX.") }
        let workbookTypes = ["worksheet", "styles", "sharedStrings", "theme"] + (regulatory ? ["calcChain"] : [])
        let relationships = try rels("xl/_rels/workbook.xml.rels", base: "xl/", allowed: Set(workbookTypes.map { d + $0 }))
        for kind in ["styles", "sharedStrings", "calcChain"] {
            guard relationships.values.filter({ $0.type == d + kind }).count <= 1 else {
                throw fail("Повторная связь книги XLSX: \(kind).")
            }
        }
        let referenced = Set(root.values.map(\.target) + relationships.values.map(\.target)).union(["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels"])
        guard paths.subtracting(ignored.keys) == referenced else { throw fail("Неучтённые части пакета XLSX.") }
        var overrides: [String: String] = [:], defaults: [String: String] = [:]
        try xml("[Content_Types].xml", namespace: "http://schemas.openxmlformats.org/package/2006/content-types", root: "Types", start: { name, a, ancestors in
            if ancestors.isEmpty && name == "Types" { return }
            guard ancestors == ["Types"] else { throw fail("Некорректный каталог типов XLSX.") }
            if name == "Override", let p = a["PartName"], p.hasPrefix("/"), let t = a["ContentType"], overrides[p] == nil { overrides[p] = t }
            else if name == "Default", let e = a["Extension"], let t = a["ContentType"], defaults[e] == nil { defaults[e] = t }
            else { throw fail("Повторный или неизвестный тип части XLSX.") }
        })
        var types = Set(["application/xml", "application/vnd.openxmlformats-package.relationships+xml", "application/vnd.openxmlformats-package.core-properties+xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml", "application/vnd.openxmlformats-officedocument.theme+xml"])
        if regulatory { types.formUnion(ignoredParts.map { $0.1 } + [calcChainType]) }
        guard overrides.allSatisfy({ paths.contains(String($0.key.dropFirst())) && types.contains($0.value) }),
              defaults.values.allSatisfy(types.contains) else { throw fail("Неподдерживаемые типы XLSX (макросы/подключения запрещены).") }
        func contentType(_ path: String) -> String? {
            overrides["/" + path] ?? defaults[path.hasSuffix(".rels") ? "rels" : (path as NSString).pathExtension]
        }
        for path in paths where path != "[Content_Types].xml" {
            guard let t = contentType(path), types.contains(t), ignored[path].map({ $0 == t }) ?? true else {
                throw fail("Неизвестный тип части XLSX: \(path)")
            }
        }
        var expectedTypes: [String: String] = [
            d + "officeDocument": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
            d + "worksheet": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
            d + "styles": "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml",
            d + "sharedStrings": "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml",
            d + "theme": "application/vnd.openxmlformats-officedocument.theme+xml",
            d + "extended-properties": "application/vnd.openxmlformats-officedocument.extended-properties+xml",
            "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties": "application/vnd.openxmlformats-package.core-properties+xml"]
        if regulatory { expectedTypes[d + "calcChain"] = calcChainType }
        for rel in Array(root.values) + Array(relationships.values) {
            guard contentType(rel.target) == expectedTypes[rel.type] else { throw fail("Тип части не совпадает с её связью.") }
        }
        let sharedPath = relationships.values.first(where: { $0.type == d + "sharedStrings" })?.target
        var shared: [String]?
        func sharedStrings() throws -> [String] {
            if let shared { return shared }
            guard let sharedPath else { return [] }
            var strings: [String] = [], sharedValue = ""
            try xml(sharedPath, namespace: Self.spreadsheet, root: "sst", start: { name, _, ancestors in
                if regulatory, name == "t", ancestors != ["sst", "si"], ancestors != ["sst", "si", "r"] {
                    throw fail("Некорректный текст shared strings.")
                }
                if name == "si" { guard ancestors == ["sst"] else { throw fail("Некорректные shared strings.") }; sharedValue = "" }
                guard ["sst", "si", "t", "r", "rPr", "b", "i", "u", "sz", "color", "rFont", "family", "charset", "scheme", "vertAlign", "strike", "outline", "shadow", "condense", "extend"].contains(name) else { throw fail("Неподдерживаемая разметка shared strings.") }
            }, end: { name, text, _ in
                if name == "t" { sharedValue += text; guard sharedValue.utf16.count <= limits.textUTF16 else { throw fail("Слишком длинная строка XLSX.") } }
                if name == "si" { guard strings.count < limits.sharedStrings else { throw fail("Слишком много shared strings.") }; strings.append(try Self.unescape(sharedValue)) }
            })
            shared = strings
            return strings
        }
        if !regulatory { _ = try sharedStrings() }
        var sheetPaths: [String: String] = [:], sheetIDs = Set<String>(), sheetOrder: [String] = []
        var filterNames: [Int: String] = [:], filterIndex: Int?
        var officeWorkbookElements: [String: Set<String>] = [
            "http://schemas.openxmlformats.org/markup-compatibility/2006": ["AlternateContent", "Choice", "Fallback"],
            "http://schemas.microsoft.com/office/spreadsheetml/2010/11/ac": ["absPath"],
            "http://schemas.microsoft.com/office/spreadsheetml/2014/revision": ["revisionPtr"],
            "http://schemas.microsoft.com/office/spreadsheetml/2018/calcfeatures": ["calcFeatures", "feature"]
        ]
        let calcFeaturesExtension = "{B58B0392-4F1F-4190-BB64-5DF3571DCE5F}"
        let workbookPropertiesExtension = "{140A7094-0E35-4892-8432-C4D2E57EDEB5}"
        let compatibilityExtension = "{D14903EA-33C4-47F7-8F05-3474C54BE107}"
        var extensions = [calcFeaturesExtension]
        var currentExtension: String?
        if regulatory {
            officeWorkbookElements["http://schemas.microsoft.com/office/spreadsheetml/2010/11/main"] = ["workbookPr"]
            officeWorkbookElements["http://schemas.microsoft.com/office/spreadsheetml/2024/workbookCompatibilityVersion"] = ["version"]
            extensions += [workbookPropertiesExtension, compatibilityExtension]
        }
        try xml("xl/workbook.xml", namespace: Self.spreadsheet, root: "workbook", additionalElements: officeWorkbookElements, start: { name, a, ancestors in
            switch name {
            case "sheet":
                guard ancestors == ["workbook", "sheets"], let name = a["name"], sheetPaths[name] == nil,
                      ["visible", "hidden", "veryHidden"].contains(a["state"] ?? "visible"),
                      let id = a["r:id"], let rel = relationships[id], rel.type == d + "worksheet",
                      let sheetID = a["sheetId"], sheetIDs.insert(sheetID).inserted,
                      !sheetPaths.values.contains(rel.target) else { throw fail("Скрытый лист или неоднозначная идентичность листа XLSX.") }
                let state = a["state"] ?? "visible"
                let requiredState = regulatory && name == RegulatoryDataManifest.sheetName ? "hidden" : "visible"
                if !regulatory || name == "Data" || name == RegulatoryDataManifest.sheetName {
                    guard state == requiredState || requiredState == "hidden" && state == "veryHidden" else {
                        throw fail("Неподдерживаемая схема листов XLSX: неверная видимость листа «\(name)».")
                    }
                }
                sheetPaths[name] = rel.target
                sheetOrder.append(name)
            case "definedNames":
                guard ancestors == ["workbook"] else { throw fail("Некорректный список имён Excel.") }
            case "definedName":
                guard ancestors == ["workbook", "definedNames"], a["name"] == "_xlnm._FilterDatabase",
                      a["hidden"] == "1" || a["hidden"] == "true",
                      let index = a["localSheetId"].flatMap(Int.init), (0..<32).contains(index), filterNames[index] == nil else {
                    throw fail("Допускаются только стандартные имена автофильтров Excel.")
                }
                filterIndex = index
            case "AlternateContent":
                guard ancestors == ["workbook"] else { throw fail("Неподдерживаемое расширение книги XLSX.") }
            case "Choice", "Fallback":
                guard ancestors == ["workbook", "AlternateContent"] else { throw fail("Неподдерживаемое расширение книги XLSX.") }
            case "absPath":
                // Office's save-location metadata is ignored. Never open the path.
                guard ancestors == ["workbook", "AlternateContent", "Choice"] else { throw fail("Неподдерживаемый путь в книге XLSX.") }
            case "revisionPtr":
                guard ancestors == ["workbook"] else { throw fail("Некорректные сведения о сохранении книги XLSX.") }
            case "extLst":
                guard ancestors == ["workbook"] else { throw fail("Неподдерживаемое расширение книги XLSX.") }
            case "ext":
                guard ancestors == ["workbook", "extLst"], let uri = a["uri"]?.uppercased(), extensions.contains(uri) else {
                    throw fail("Неподдерживаемое расширение книги XLSX.")
                }
                currentExtension = uri
            case "workbookPr" where ancestors == ["workbook", "extLst", "ext"] && currentExtension == workbookPropertiesExtension:
                break
            case "version" where ancestors == ["workbook", "extLst", "ext"] && currentExtension == compatibilityExtension:
                break
            case "calcFeatures", "feature":
                let parent = ["workbook", "extLst", "ext"]
                guard currentExtension == calcFeaturesExtension,
                      ancestors == (name == "feature" ? parent + ["calcFeatures"] : parent) else {
                    throw fail("Некорректные сведения о версии Excel.")
                }
            case "externalReferences", "pivotCaches":
                throw fail("Внешние ссылки и сводные таблицы XLSX не поддерживаются.")
            default:
                if ancestors.contains(where: { ["definedNames", "AlternateContent", "extLst"].contains($0) }) {
                    throw fail("Неподдерживаемая структура книги XLSX.")
                }
            }
        }, end: { name, value, _ in
            if name == "ext" { currentExtension = nil }
            if name == "definedName", let index = filterIndex { filterNames[index] = value; filterIndex = nil }
        })
        for (index, formula) in filterNames {
            guard sheetOrder.indices.contains(index) else { throw fail("Автофильтр указывает на отсутствующий лист.") }
            let sheet = sheetOrder[index]
            let quoted = "'" + sheet.replacingOccurrences(of: "'", with: "''") + "'!"
            guard let prefix = [quoted, sheet + "!"].first(where: { formula.hasPrefix($0) }) else {
                throw fail("Автофильтр должен ссылаться на свой лист.")
            }
            let address = String(formula.dropFirst(prefix.count))
            let range = address.replacingOccurrences(of: "$", with: "").split(separator: ":", omittingEmptySubsequences: false)
            guard address.range(of: #"^\$[A-Z]{1,3}\$[1-9][0-9]*(?::\$[A-Z]{1,3}\$[1-9][0-9]*)?$"#, options: .regularExpression) != nil,
                  range.allSatisfy({ Self.address(String($0)) != nil }) else {
                throw fail("Имя автофильтра должно содержать только диапазон ячеек своего листа.")
            }
        }
        guard sheetPaths.count <= 32, Set(sheetPaths.values) == Set(relationships.values.filter { $0.type == d + "worksheet" }.map(\.target)) else { throw fail("Неучтённые листы XLSX.") }
        if regulatory {
            guard sheetPaths["Data"] != nil else {
                throw fail("Неподдерживаемая схема листов XLSX: требуется видимый лист Data с колонками A:AD.")
            }
            sheetPaths = sheetPaths.filter { $0.key == "Data" || $0.key == RegulatoryDataManifest.sheetName }
        }
        var identifier: UUID?
        var seenIdentifier = false
        if regulatory, let core = root.values.first(where: { $0.type.hasSuffix("/core-properties") }) {
            try ExchangeXML.read(load(core.target, nil), namespace: nil, root: "coreProperties", limits: limits, end: { name, value, stack in
                if name == "identifier", stack == ["coreProperties"] {
                    guard !seenIdentifier else { throw fail("Повторный идентификатор книги.") }
                    seenIdentifier = true
                    identifier = UUID(uuidString: value)
                }
            })
        }
        let style = relationships.values.first(where: { $0.type == d + "styles" })
        var numericStyles: [Bool]?
        func styles() throws -> [Bool] {
            if let numericStyles { return numericStyles }
            guard let style else { return [true] }
            var result: [Bool] = []
            var customFormats: [Int: String] = [:]
            var parentFormats: [Int] = []
            try xml(style.target, namespace: Self.spreadsheet, root: "styleSheet", additionalElements: [
                "http://schemas.openxmlformats.org/markup-compatibility/2006": ["AlternateContent", "Choice", "Fallback"],
                "http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac": ["knownFonts"],
                "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main": ["slicerStyles"],
                "http://schemas.microsoft.com/office/spreadsheetml/2010/11/main": ["timelineStyles"]
            ], start: { name, attrs, stack in
                if name == "numFmt", stack == ["styleSheet", "numFmts"] {
                    guard let id = attrs["numFmtId"].flatMap(Int.init), (0...65_535).contains(id),
                          let code = attrs["formatCode"], customFormats.updateValue(code, forKey: id) == nil else {
                        throw fail("Некорректный числовой формат Excel.")
                    }
                }
                if name == "xf", stack == ["styleSheet", "cellStyleXfs"] {
                    parentFormats.append(attrs["numFmtId"].flatMap(Int.init) ?? -1)
                }
                if name == "xf", stack == ["styleSheet", "cellXfs"] {
                    guard let id = attrs["numFmtId"].flatMap(Int.init) else { throw fail("Неизвестный формат ячейки.") }
                    func isPlain(_ id: Int) -> Bool {
                        if let code = customFormats[id] {
                            // Excel conversions can supply an explicit format for
                            // a built-in ID. Validate the explicit format first.
                            return code.range(of: #"^0+(?:[.]0+)?$"#, options: .regularExpression) != nil
                        }
                        return [0, 1, 2, 3, 4, 11, 48].contains(id)
                    }
                    let inherited = attrs["xfId"].flatMap(Int.init)
                    let safeParent = inherited.map { parentFormats.indices.contains($0) && isPlain(parentFormats[$0]) } ?? (attrs["xfId"] == nil)
                    result.append(isPlain(id) && safeParent)
                }
            })
            numericStyles = result
            return result
        }
        var regulatoryRows: [Int: [Int: DataCell]] = [:]
        var dataSheetRowCount = 0
        var productionLayout = false
        var output: [String: Sheet] = [:], otherCells = 0, dataCells = 0, totalRows = 0
        for (sheet, path) in sheetPaths.sorted(by: { $0.key < $1.key }) {
            let regulatoryData = regulatory && sheet == "Data"
            if regulatory {
                let file = (path as NSString).lastPathComponent
                let relPath = (path as NSString).deletingLastPathComponent + "/_rels/" + file + ".rels"
                if paths.contains(relPath) {
                    let printSettings = try rels(relPath, base: "xl/worksheets/", allowed: [d + "printerSettings"], parent: "xl/")
                    guard printSettings.values.allSatisfy({ ignored[$0.target] == printerType }) else {
                        throw fail("Некорректная связь с настройками печати XLSX.")
                    }
                }
            }
            var rows: [Int: [Int: String]] = [:], rowNumbers = Set<Int>(), currentRow: Int?, currentColumn: Int?, cellType = "", cellText = "", cellValue = "", seenValue = false, seenInline = false
            var seenColumns = Set<Int>()
            // XMLParser does not allow nested parsing. Resolve these references
            // after the worksheet parser returns, loading each table only on demand.
            var stringReferences: [Int: [Int: Int]] = [:]
            var styleReferences: [Int: [Int: Int]] = [:]
            var cellIssue: String?
            var styleIndex = 0
            var hasFormula = false
            var merges = Set<String>()
            var hasConditionalFormatting = false
            var firstExtraCell: String?
            var extraColumns = Set<Int>()
            var derivedPlaceholders = Set<Int>()
            var retainedDataCells = 0
            let reportColumns = RegulatoryDataWorkbook.columns.count
            try xml(path, namespace: Self.spreadsheet, root: "worksheet", worksheet: regulatory ? sheet : nil, start: { name, a, ancestors in
                if regulatoryData {
                    if name == "f", currentColumn != nil, ancestors.last == "c" {
                        hasFormula = true
                        cellIssue = "Формулы и их сохранённые результаты не поддерживаются."
                        return
                    }
                    if name == "mergeCells", ancestors == ["worksheet"] { return }
                    if name == "mergeCell", ancestors == ["worksheet", "mergeCells"],
                       let ref = a["ref"], merges.insert(ref).inserted { return }
                    if name == "conditionalFormatting", ancestors == ["worksheet"] {
                        hasConditionalFormatting = true
                        return
                    }
                }
                if ["f", "hyperlinks", "oleObjects", "controls", "extLst", "tableParts", "drawing", "legacyDrawing",
                    "mergeCells", "mergeCell", "dataValidations", "conditionalFormatting"].contains(name) {
                    let cell = currentRow.flatMap { row in currentColumn.map { "\(MappingXLSXExport.column($0 + 1))\(row)" } }
                    let context = regulatory ? "Неподдерживаемая схема листа " : ""
                    throw fail("\(context)\(sheet)\(cell.map { "!" + $0 } ?? ""): формулы, ссылки и дополнительные структуры листа запрещены.")
                }
                if name == "row" {
                    guard ancestors == ["worksheet", "sheetData"], let n = a["r"].flatMap(Int.init), (1...1_048_576).contains(n), rowNumbers.insert(n).inserted else { throw fail("\(sheet): повторная или неверная строка.") }
                    totalRows += 1
                    guard totalRows <= limits.rows else { throw fail("Превышен предел строк XLSX.") }
                    currentRow = n
                    if regulatoryData { dataSheetRowCount += 1 }
                    seenColumns.removeAll(keepingCapacity: true)
                    if !regulatoryData { rows[n] = [:] }
                }
                if name == "c" {
                    guard ancestors == ["worksheet", "sheetData", "row"], let row = currentRow, let address = a["r"], let (column, number) = Self.address(address), number == row, seenColumns.insert(column).inserted else { throw fail("\(sheet): повторная или неверная ячейка.") }
                    if regulatoryData {
                        dataCells += 1
                        guard dataCells <= limits.dataSheetCells else { throw fail("Превышен предел ячеек листа Data.") }
                    } else {
                        otherCells += 1
                        guard otherCells <= limits.cells else { throw fail("Превышен предел ячеек XLSX.") }
                    }
                    currentColumn = column; cellType = a["t"] ?? ""; cellText = ""; cellValue = ""; seenValue = false; seenInline = false
                    cellIssue = nil; hasFormula = false
                    if regulatoryData, column < reportColumns {
                        styleIndex = a["s"].flatMap(Int.init) ?? (a["s"] == nil ? 0 : -1)
                        if a["cm"] != nil || a["vm"] != nil || !["", "n", "s", "inlineStr"].contains(cellType) {
                            cellIssue = "Неподдерживаемый тип Excel (дата, логическое значение или ошибка)."
                        }
                    }
                    guard regulatoryData || ["", "n", "s", "inlineStr"].contains(cellType) else { throw fail("\(sheet)!\(address): тип ячейки не текстовый; возможна потеря точности или преобразование даты.") }
                }
                if currentColumn != nil {
                    guard ["c", "is", "t", "r", "rPr", "b", "i", "u", "sz", "color", "rFont", "family", "charset", "scheme", "vertAlign", "strike", "v"].contains(name) else { throw fail("\(sheet): неподдерживаемое содержимое ячейки.") }
                    if name == "v" { guard !seenValue, ancestors.last == "c" else { throw fail("Неоднозначное значение ячейки.") }; seenValue = true }
                    if name == "is" { guard !seenInline, ancestors.last == "c" else { throw fail("Неоднозначная строка ячейки.") }; seenInline = true }
                    if name == "t" {
                        let inline = ["worksheet", "sheetData", "row", "c", "is"]
                        guard regulatoryData ? ancestors == inline || ancestors == inline + ["r"] : ancestors.contains("is") else {
                            throw fail("Строка вне inlineStr.")
                        }
                    }
                }
            }, end: { name, text, _ in
                if let column = currentColumn, let row = currentRow {
                    if !regulatoryData || column < reportColumns || row <= 4 {
                        if name == "t" { cellText += text }
                        if name == "v" { cellValue += text }
                    }
                    guard cellText.utf16.count <= limits.textUTF16 else { throw fail("Слишком длинный текст ячейки.") }
                }
                if name == "c", let row = currentRow, let col = currentColumn {
                    if regulatoryData {
                        if !text.isEmpty { cellIssue = "Неоднозначное содержимое ячейки."; hasFormula = true }
                        if col >= reportColumns {
                            let populated = hasFormula || seenValue || seenInline || !["", "n"].contains(cellType)
                            if populated {
                                if firstExtraCell == nil { firstExtraCell = RegulatoryDataWorkbook.address(col, row) }
                                extraColumns.insert(col)
                            }
                            if row > 4 {
                                currentColumn = nil
                                return
                            }
                        }
                        if hasFormula || seenValue || seenInline || cellIssue != nil {
                            retainedDataCells += 1
                            guard retainedDataCells <= limits.dataSheetRetainedCells else {
                                throw fail("Превышен предел значимых ячеек листа Data.")
                            }
                        }
                        if row > 4, col == reportColumns - 1, hasFormula, cellType == "str", cellValue == "-" {
                            derivedPlaceholders.insert(row)
                        }
                    }
                    if regulatoryData, let issue = cellIssue, seenValue || seenInline || !["", "n"].contains(cellType) || hasFormula {
                        regulatoryRows[row, default: [:]][col] = .invalid(issue)
                        currentColumn = nil
                        return
                    }
                    let value: String
                    switch cellType {
                    case "s":
                        guard seenValue, !seenInline, let index = Int(cellValue), index >= 0 else {
                            throw fail("Некорректный индекс shared strings.")
                        }
                        stringReferences[row, default: [:]][col] = index
                        currentColumn = nil
                        return
                    case "inlineStr":
                        guard !seenValue else { throw fail("Неоднозначное текстовое значение.") }; value = try Self.unescape(cellText)
                    default:
                        if regulatoryData, seenValue, !seenInline {
                            regulatoryRows[row, default: [:]][col] = .number(cellValue)
                            styleReferences[row, default: [:]][col] = styleIndex
                            currentColumn = nil
                            return
                        }
                        guard !seenValue, !seenInline else { throw fail("\(sheet)!\(MappingXLSXExport.column(col + 1))\(row): числовая/датированная ячейка; восстановить точность нельзя. Сохраните исходные значения как текст.") }; value = ""
                    }
                    if regulatoryData {
                        if !value.isEmpty, row <= 4 || value != "-" {
                            regulatoryRows[row, default: [:]][col] = .text(value)
                        }
                    } else {
                        rows[row]?[col] = value
                    }
                    currentColumn = nil
                }
                if name == "row" { currentRow = nil }
            })
            if !stringReferences.isEmpty {
                let strings = try sharedStrings()
                for (row, references) in stringReferences {
                    try Task.checkCancellation()
                    for (column, index) in references {
                        guard strings.indices.contains(index) else { throw fail("Некорректный индекс shared strings.") }
                        let value = strings[index]
                        if regulatoryData {
                            if !value.isEmpty, row <= 4 || value != "-" {
                                regulatoryRows[row, default: [:]][column] = .text(value)
                            }
                        } else {
                            rows[row]?[column] = value
                        }
                    }
                }
            }
            if !styleReferences.isEmpty {
                let numeric = try styles()
                for (row, references) in styleReferences {
                    try Task.checkCancellation()
                    for (column, index) in references where !numeric.indices.contains(index) || !numeric[index] {
                        regulatoryRows[row]?[column] = .invalid("Числовой формат может преобразовать дату, проценты или единицы.")
                    }
                }
            }
            if regulatoryData {
                let canonicalMerges = Set(EnterpriseGeotechnicalWorkbook.merges)
                if let firstExtraCell {
                    guard RegulatoryDataWorkbook.matchesProductionLayout(regulatoryRows, extraColumns: extraColumns),
                          merges.isSubset(of: RegulatoryDataWorkbook.productionMerges) else {
                        throw fail("Неподдерживаемая схема листа Data: Data!\(firstExtraCell) содержит данные за пределами A:AD.")
                    }
                    productionLayout = true
                    // In this layout the known GSI formula fills template rows with
                    // cached dashes. A lone placeholder formula is not a candidate.
                    for row in derivedPlaceholders {
                        try Task.checkCancellation()
                        if let cells = regulatoryRows[row], cells.count == 1, cells[reportColumns - 1] != nil {
                            regulatoryRows.removeValue(forKey: row)
                        }
                    }
                } else if hasConditionalFormatting || !merges.isSubset(of: canonicalMerges) {
                    throw fail("Неподдерживаемая схема листа Data: дополнительные объединения или условное форматирование.")
                }
                continue
            }
            guard let header = rows.removeValue(forKey: 1), let max = header.keys.max(), max < 256 else { throw fail("\(sheet): отсутствует заголовок.") }
            let columns = (0...max).map { header[$0] ?? "" }
            guard !columns.contains(""), Set(columns).count == columns.count else { throw fail("\(sheet): пустые или повторные колонки.") }
            var values: [Row] = [], numbers: [Int] = []
            for (number, cells) in rows.sorted(by: { $0.key < $1.key }) {
                guard cells.keys.allSatisfy({ $0 <= max || cells[$0] == "" }) else { throw fail("\(sheet): данные за пределами колонок.") }
                if cells.values.allSatisfy(\.isEmpty) { continue }
                numbers.append(number)
                values.append(Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, cells[$0.offset] ?? "") }))
            }
            output[sheet] = Sheet(columns: columns, rows: values, rowNumbers: numbers)
        }
        if !regulatory {
            // Exchange has a closed package contract and still validates every part.
            let alreadyParsed = Set(sheetPaths.values).union(["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/workbook.xml", "xl/sharedStrings.xml"])
            for path in paths.subtracting(alreadyParsed) {
                try ExchangeXML.read(load(path, nil), namespace: nil, limits: limits)
            }
        }
        sheets = output
        dataRows = regulatoryRows
        self.dataSheetRowCount = dataSheetRowCount
        self.productionLayout = productionLayout
        documentID = identifier
    }
    static func address(_ s: String) -> (Int, Int)? {
        var column = 0
        var row = 0
        var readingRow = false
        for byte in s.utf8 {
            switch byte {
            case 65...90 where !readingRow:
                column = column * 26 + Int(byte - 64)
                guard column <= 16_384 else { return nil }
            case 48...57:
                readingRow = true
                row = row * 10 + Int(byte - 48)
                guard row <= 1_048_576 else { return nil }
            default:
                return nil
            }
        }
        guard column > 0, row > 0 else { return nil }
        return (column - 1, row)
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
    let limits: ExchangeLimits; let namespace: String?; let root: String?; let additionalElements: [String: Set<String>]; let start: Start; let end: End
    var stack: [String] = [], texts: [String] = [], elements = 0
    var error: Error?
    init(namespace: String?, root: String?, limits: ExchangeLimits, additionalElements: [String: Set<String>], start: @escaping Start, end: @escaping End) {
        self.namespace = namespace; self.root = root; self.limits = limits; self.additionalElements = additionalElements; self.start = start; self.end = end
    }
    static func read(_ data: Data, namespace: String?, root: String? = nil, limits: ExchangeLimits,
                     additionalElements: [String: Set<String>] = [:], start: @escaping Start = { _, _, _ in },
                     end: @escaping End = { _, _, _ in }) throws {
        // XML keywords are case-sensitive. Reject declarations before handing any
        // bytes to XMLParser. Inspect the encoding declaration without decoding the part.
        let forbidden = ["<!DOCTYPE", "<!ENTITY", "\u{0}"]
        guard data.count <= limits.partBytes, !forbidden.contains(where: { data.range(of: Data($0.utf8)) != nil }) else {
            throw ExchangeImportError("DTD, сущности и кодировки кроме UTF-8 запрещены.")
        }
        try validatePrefix(data.prefix(1024))
        try parse(XMLParser(data: data), namespace: namespace, root: root, limits: limits,
                  additionalElements: additionalElements, start: start, end: end)
    }

    static func read(_ stream: ExchangeWorksheetStream, namespace: String?, root: String?, limits: ExchangeLimits,
                     additionalElements: [String: Set<String>], start: @escaping Start, end: @escaping End) throws {
        try validatePrefix(stream.preparePrefix())
        do {
            try parse(XMLParser(stream: stream), namespace: namespace, root: root, limits: limits,
                      additionalElements: additionalElements, start: start, end: end)
        } catch {
            throw stream.streamError ?? error
        }
        try stream.verifyCompletion()
    }

    private static func validatePrefix(_ prefix: Data) throws {
        let declaration = prefix.starts(with: [0xEF, 0xBB, 0xBF]) ? prefix.dropFirst(3) : prefix
        let whitespace: Set<UInt8> = [9, 10, 13, 32]
        guard declaration.first(where: { !whitespace.contains($0) }) == 0x3C else {
            throw ExchangeImportError("Некорректный XML XLSX или кодировка кроме UTF-8.")
        }
        if declaration.starts(with: "<?xml".utf8), declaration.dropFirst(5).first.map(whitespace.contains) == true {
            guard let close = declaration.range(of: Data("?>".utf8)),
                  let header = String(data: declaration[..<close.upperBound], encoding: .utf8),
                  header.range(of: #"encoding\s*=\s*["'](?![Uu][Tt][Ff]-8["'])"#, options: .regularExpression) == nil else {
                throw ExchangeImportError("Некорректная декларация XML или кодировка кроме UTF-8.")
            }
        }
    }

    private static func parse(_ parser: XMLParser, namespace: String?, root: String?, limits: ExchangeLimits,
                              additionalElements: [String: Set<String>], start: @escaping Start, end: @escaping End) throws {
        let delegate = ExchangeXML(namespace: namespace, root: root, limits: limits, additionalElements: additionalElements, start: start, end: end)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false; parser.shouldReportNamespacePrefixes = true; parser.delegate = delegate
        guard parser.parse(), delegate.error == nil, parser.parserError == nil, delegate.elements > 0, delegate.stack.isEmpty else { throw delegate.error ?? ExchangeImportError("Некорректный XML XLSX.") }
    }
    func checked(_ parser: XMLParser, _ body: () throws -> Void) {
        do { try Task.checkCancellation(); try body() } catch { self.error = error; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        checked(parser) {
            if stack.isEmpty, let root, name != root {
                throw ExchangeImportError("Некорректная структура XLSX: ожидался элемент XML «\(root)».")
            }
            elements += 1
            guard stack.count < limits.xmlDepth, elements <= limits.xmlElements, attributes.count <= 64,
                  attributes.allSatisfy({ $0.key.utf16.count <= 256 && $0.value.utf16.count <= limits.textUTF16 }),
                  namespace == nil || namespaceURI == namespace || additionalElements[namespaceURI ?? ""]?.contains(name) == true else { throw ExchangeImportError("Превышен предел XML или неподдерживаемое пространство имён.") }
            try start(name, attributes, stack); stack.append(name); texts.append("")
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        checked(parser) {
            guard let last = texts.indices.last else { return }
            guard text.utf16.count <= limits.textUTF16 else { throw ExchangeImportError("Превышен предел текста XML.") }
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
    func parser(_ parser: XMLParser, foundComment comment: String) {
        checked(parser) {
            guard comment.utf16.count <= limits.textUTF16 else { throw ExchangeImportError("Превышен предел текста XML.") }
        }
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        checked(parser) {
            guard target.utf16.count + (data?.utf16.count ?? 0) <= limits.textUTF16 else {
                throw ExchangeImportError("Превышен предел текста XML.")
            }
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { error = ExchangeImportError("CDATA в XLSX не поддерживается."); parser.abortParsing() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { error = ExchangeImportError("Внешние сущности запрещены."); parser.abortParsing(); return nil }
}
