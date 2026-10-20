import Foundation

enum MappingExportFormat: String, CaseIterable {
    case csv = "CSV", xlsx = "Excel (.xlsx)", photoPackage = "Фотографии + Excel (.zip)"
}

/// OOXML Transitional workbook over the SAME typed P5.1 value snapshot. No CSV parsing,
/// persistence access, formula generation, rating evaluation or coordinate conversion.
enum MappingXLSXExport {
    static let version = "FieldForge-Mapping-XLSX/1"
    private static let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    static func write(_ snapshot: MappingCSVExport, to url: URL,
                      photoPackageStatus: String? = nil,
                      append: @escaping (Data, FileHandle) throws -> Void = { try $1.write(contentsOf: $0) }) throws {
        try Task.checkCancellation()
        let summary = try summary(snapshot, photoPackageStatus: photoPackageStatus)
        let sheets = [summary] + snapshot.tables
        let archive = try XLSXArchive(url: url, append: append)
        defer { archive.close() }
        func part(_ name: String, _ xml: String) throws { try archive.part(name) { try $0(declaration + xml) } }
        try part("[Content_Types].xml", """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        \(sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())
        </Types>
        """)
        try part("_rels/.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="\(relationships)/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="\(relationships)/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """)
        try part("docProps/core.xml", """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:title>FieldForge — картирование</dc:title><dc:creator>FieldForge</dc:creator>
        <dc:identifier>\(snapshot.id.uuidString)</dc:identifier>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(MappingCSVExport.iso(snapshot.snapshotAt))</dcterms:created>
        </cp:coreProperties>
        """)
        try part("docProps/app.xml", """
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>FieldForge</Application><AppVersion>1.0</AppVersion></Properties>
        """)
        try part("xl/workbook.xml", """
        <workbook xmlns="\(main)" xmlns:r="\(relationships)"><bookViews><workbookView activeTab="0"/></bookViews><sheets>
        \(sheets.enumerated().map { "<sheet name=\"\($0.element.name)\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined())
        </sheets></workbook>
        """)
        try part("xl/_rels/workbook.xml.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"\(relationships)/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())
        <Relationship Id="rIdStyles" Type="\(relationships)/styles" Target="styles.xml"/></Relationships>
        """)
        try part("xl/styles.xml", styles)
        for (index, table) in sheets.enumerated() {
            try Task.checkCancellation()
            guard !table.columns.isEmpty, table.columns.count <= 16_384, table.rows.count < 1_048_576 else {
                throw MappingError.invalid("Таблица превышает ограничения листа Excel.")
            }
            try archive.part("xl/worksheets/sheet\(index + 1).xml") { emit in
                let last = column(table.columns.count) + String(table.rows.count + 1)
                try emit(declaration + """
                <worksheet xmlns="\(main)"><dimension ref="A1:\(last)"/>
                <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>
                <sheetFormatPr defaultRowHeight="30"/><cols>
                """)
                for (i, name) in table.columns.enumerated() {
                    let width = index == 0 ? (i == 0 ? 37 : 105) : columnWidth(name)
                    try emit("<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(width)\" customWidth=\"1\"/>")
                }
                try emit("</cols><sheetData><row r=\"1\" ht=\"36\" customHeight=\"1\">")
                for (i, name) in table.columns.enumerated() {
                    try emit(cell(.text(name), reference: column(i + 1) + "1", style: 1))
                }
                try emit("</row>")
                for (i, row) in table.rows.enumerated() {
                    try Task.checkCancellation()
                    guard row.count == table.columns.count else { throw StorageError.invalidRecord }
                    let r = i + 2
                    try emit("<row r=\"\(r)\"\(index == 0 ? " ht=\"60\" customHeight=\"1\"" : "")>")
                    for (j, value) in row.enumerated() {
                        try emit(cell(value, reference: column(j + 1) + String(r), style: i % 2 == 0 ? 0 : 2))
                    }
                    try emit("</row>")
                }
                try emit("</sheetData>" + (index == 0 ? "" : "<autoFilter ref=\"A1:\(last)\"/>") + "</worksheet>")
            }
        }
        try archive.finish()
        try Task.checkCancellation()
    }

    /// Excel stores at most 15 significant decimal digits. Keep the shortest round-trip
    /// Double spelling as text whenever its significand needs more; do not add rounded helpers.
    static func numericText(_ value: Double) throws -> (value: String, isText: Bool) {
        guard value.isFinite else { throw MappingError.invalid("В выгрузке обнаружено нечисловое значение.") }
        let text = String(value)
        let significand = text.lowercased().split(separator: "e")[0].filter { $0.isNumber }
        let digits = significand.drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" }).count
        // Excel does not support subnormal IEEE values as numeric cells.
        return (text, digits > 15 || (value != 0 && abs(value) < Double.leastNormalMagnitude))
    }

    static func cell(_ value: MappingCSVExport.Cell, reference: String, style: Int) throws -> String {
        let prefix = "<c r=\"\(reference)\" s=\"\(style)\""
        func text(_ string: String) throws -> String {
            guard string.utf16.count <= 32_767 else {
                throw MappingError.invalid("Ячейка \(reference) превышает 32767 символов Excel. Используйте CSV для этих данных.")
            }
            return prefix + " t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(string))</t></is></c>"
        }
        switch value {
        case .text(let string): return try text(string)
        case .timestamp(let date): return try date.map { try text(MappingCSVExport.iso($0)) } ?? (prefix + "/>")
        case .number(let number):
            guard let number else { return prefix + "/>" }
            let encoded = try numericText(number)
            return try encoded.isText ? text(encoded.value) : prefix + " t=\"n\"><v>\(encoded.value)</v></c>"
        case .integer(let number):
            guard let number else { return prefix + "/>" }
            return try String(number).filter(\.isNumber).count > 15 ? text(String(number)) : prefix + " t=\"n\"><v>\(number)</v></c>"
        case .empty: return prefix + "/>"
        }
    }

    /// SpreadsheetML ST_Xstring escaping: preserve control characters and literal _xHHHH_.
    /// XML metacharacters are escaped after protecting source escape-like sequences.
    static func escape(_ text: String) -> String {
        let protected = text.replacingOccurrences(of: "_(?=[xX][0-9a-fA-F]{4}_)", with: "_x005F_", options: .regularExpression)
        return protected.unicodeScalars.map { scalar -> String in
            let v = scalar.value
            if v < 32 && v != 9 && v != 10 || v == 0xFFFE || v == 0xFFFF {
                return String(format: "_x%04X_", v)
            }
            switch scalar {
            case "&": return "&amp;"
            case "<": return "&lt;"
            case ">": return "&gt;"
            case "\"": return "&quot;"
            default: return String(scalar)
            }
        }.joined()
    }

    static func column(_ number: Int) -> String {
        var n = number, result = ""
        while n > 0 { n -= 1; result = String(UnicodeScalar(65 + n % 26)!) + result; n /= 26 }
        return result
    }
    private static func columnWidth(_ name: String) -> Int {
        if name.hasSuffix("_id") { return 39 }
        if name.hasSuffix("_json") || ["notes", "description", "coordinate_provenance"].contains(name) { return 56 }
        if name.hasSuffix("_utc") || name.hasSuffix("_reference_seconds") { return 29 }
        return min(36, max(18, name.count + 3))
    }

    static func summary(_ snapshot: MappingCSVExport, photoPackageStatus: String? = nil) throws -> MappingCSVExport.Table {
        let manifest = try JSONSerialization.jsonObject(with: snapshot.manifest) as? [String: Any] ?? [:]
        func rows(_ name: String) -> [[String: MappingCSVExport.Cell]] {
            guard let table = snapshot.tables.first(where: { $0.name == name }) else { return [] }
            return table.rows.map { Dictionary(uniqueKeysWithValues: zip(table.columns, $0)) }
        }
        func string(_ value: MappingCSVExport.Cell?) -> String? {
            if case .text(let text) = value { return text }; return nil
        }
        func missing(_ value: MappingCSVExport.Cell?) -> Bool {
            switch value { case nil, .empty, .number(nil), .integer(nil), .timestamp(nil): return true; default: return false }
        }
        var table = MappingCSVExport.Table(name: "Сводка", columns: ["Параметр", "Значение"])
        func note(_ key: String, _ value: String) { table.rows.append([.text(key), .text(value)]) }
        func count(_ key: String, _ n: Int) { table.rows.append([.text(key), .integer(n)]) }
        note("Формат", version)
        note("Проект", string(rows("projects").first?["name"]) ?? snapshot.selection.projectID.uuidString)
        note("project_id", snapshot.selection.projectID.uuidString)
        note("Горизонт", snapshot.selection.horizonID.map { id in
            string(rows("horizons").first { string($0["horizon_id"]) == id.uuidString }?["name"]).map { $0 + " (\(id))" } ?? id.uuidString
        } ?? "Все горизонты")
        note("Выработка", snapshot.selection.excavationID.map { id in
            string(rows("excavations").first { string($0["excavation_id"]) == id.uuidString }?["name"]).map { $0 + " (\(id))" } ?? id.uuidString
        } ?? "Все выработки")
        for (label, key) in [("Дата от включительно", "first_day_inclusive"), ("Дата до включительно", "last_day_inclusive"), ("Часовой пояс", "timezone"), ("Начало UTC включительно", "start_inclusive_utc"), ("Конец UTC исключительно", "end_exclusive_utc")] {
            note(label, manifest[key] as? String ?? "")
        }
        note("Снимок / время экспорта UTC", MappingCSVExport.iso(snapshot.snapshotAt))
        table.rows.append([.text("Точные секунды снимка от 2001-01-01 UTC"), .number(snapshot.snapshotAt.timeIntervalSinceReferenceDate)])
        note("export_id", snapshot.id.uuidString)
        let labels = ["projects": "Проекты", "horizons": "Горизонты", "excavations": "Выработки", "excavation_horizons": "Связи выработок и горизонтов", "plans": "Планы", "points": "Точки", "measurements": "Исходные измерения", "joint_sets": "Интерпретированные системы", "interpretation_evidence": "Связи с исходными измерениями", "tectonic_structures": "Тектонические структуры", "assessments": "Оценки", "photos": "Фотографии", "photo_attachments": "Вложения фотографий", "photo_point_contexts": "Исторический контекст фотографий"]
        for data in snapshot.tables { count("\(labels[data.name] ?? data.name) (\(data.name))", data.rows.count) }
        let points = rows("points"), measurements = rows("measurements"), photos = rows("photos")
        let measured = Set(measurements.compactMap { string($0["point_id"]) })
        count("Точки без X/Y", points.filter { missing($0["x"]) || missing($0["y"]) }.count)
        count("Точки без Z", points.filter { missing($0["z_m"]) }.count)
        count("Точки без измерений", points.filter { !measured.contains(string($0["point_id"]) ?? "") }.count)
        count("Неполные ориентации структур", rows("tectonic_structures").filter { missing($0["dip_direction_deg"]) || missing($0["dip_angle_deg"]) }.count)
        count("Q без сохранённого результата", rows("assessments").filter { string($0["kind"]) == "Q" && missing($0["stored_q"]) }.count)
        count("Фото без времени съёмки", photos.filter { missing($0["captured_at_utc"]) }.count)
        count("Фото с неизвестным местом съёмки", photos.filter { string($0["capture_location_basis"]) == "unknownBeforeFirstSave" }.count)
        if let photoPackageStatus {
            note("Статус фотоархива", photoPackageStatus)
            note("Полнота", "Каждое фото перечислено в photo_register. В ZIP включены только оригиналы со статусом verified; остальные имеют причину отсутствия. INCOMPLETE означает неполный пакет.")
            note("Назначение", "Рабочая выгрузка фотографий и картирования, НЕ полная резервная копия: нет DXF, незавершённых импортов и полной истории.")
        } else {
        note("Полнота", "Неполные записи сохранены. Наличие и целостность оригиналов фотографий не проверялись. original_integrity — notChecked; originalsNotIncluded.")
        note("Назначение", "Выгрузка для анализа, НЕ полная резервная копия. Нет оригиналов фото, миниатюр, файлов DXF и полной истории исправлений.")
        }
        note("Точность Excel", "Числа до 15 значащих цифр — числовые ячейки. Более точные Double и большие целые — текст с точным исходным представлением. Очень малые subnormal Double — текст. Приблизительных столбцов нет.")
        note("Исходный текст", "Десятичные строки, UUID, JSON, времена ISO UTC и строки с =, +, -, @ сохранены как текст без защитного CSV-апострофа. Пустые ячейки означают отсутствие значения, не ноль. Формул, макросов и внешних связей нет.")
        note("Единицы", "XY — xy_units (m, mm, drawing), CRS и axes сохранены. Z, высоты, пикетаж, интервалы, spacing, persistence, thickness — м. aperture — мм. Углы падения и направления — градусы.")
        note("Север и координаты", "magnetic/true/grid/unknown сохранены без преобразований. Источник координат, plan_id и версия плана явные. Подземный GPS не предполагается.")
        note("Измерения и диагностика", "Все исходные измерения и их source сохранены. sensor_sample_json: NWU, диагностика устройства g, µT, rad/s. Оригинальные строки углов и direction_meaning сохранены.")
        note("Время", "Отбор только по observedAt актуальной точки в выбранном поясе, включая последний календарный день. ISO UTC — миллисекунды. *_reference_seconds и даты JSON — точные секунды от 2001-01-01T00:00:00Z.")
        note("Версии и связи", "Одна актуальная точка на UUID. revision_id/version идентифицируют версию. photo_point_contexts — историческая связь, не дополнительные точки; unknownBeforeFirstSave не задаёт координаты съёмки. Связанные измерения/фото могут быть вне периода.")
        note("Оценки", "Barton Q, метод, входы, результат и пропуски — как сохранено, без пересчёта. RMR89 — только входы, без рейтинга и класса.")
        note("Приватность", photoPackageStatus == nil ? "EXIF GPS и оригиналы не читаются. Имена файлов, заметки и другие пользовательские строки могут содержать личные сведения." : "Оригиналы переданы без изменения байтов, включая личные EXIF/GPS и сведения об авторе. Координаты EXIF не трактуются как место съёмки в шахте. Санитизированные копии не создаются.")
        note("Столбцы и отношения", "Имена листов и столбцов совпадают с контрактом FieldForge-Mapping-CSV/1, включая *_reference_seconds. Связи по UUID, не по имени файла. JSON содержит полный сохранённый ввод и диагностику.")
        return table
    }

    private static let styles = """
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2"><font><sz val="11"/><color rgb="FF243746"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
    <fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF243746"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F5F7"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}
