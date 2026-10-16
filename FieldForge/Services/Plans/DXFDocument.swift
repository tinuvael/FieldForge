import Foundation

struct PlanPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct PlanBounds: Equatable {
    let minX: Double, minY: Double, maxX: Double, maxY: Double
    var center: PlanPoint { PlanPoint(x: minX + (maxX - minX) / 2, y: minY + (maxY - minY) / 2) }
}

/// Display only. Drawing X right/Y up; view X right/Y down, in logical points.
/// fit and its inverse share one Double-precision transform (no device pixel scale).
struct PlanViewport {
    let center: PlanPoint
    let scale: Double
    let width: Double, height: Double
    let pan: PlanPoint
    init(bounds: PlanBounds, width: Double, height: Double, zoom: Double = 1, pan: PlanPoint = PlanPoint(x: 0, y: 0)) {
        center = bounds.center; self.width = width; self.height = height; self.pan = pan
        scale = max(0.000000001, min(max(1, width - 48) / max(1, bounds.maxX - bounds.minX),
                                    max(1, height - 48) / max(1, bounds.maxY - bounds.minY))) * zoom
    }
    func screen(_ p: PlanPoint) -> PlanPoint {
        PlanPoint(x: width / 2 + pan.x + (p.x - center.x) * scale,
                  y: height / 2 + pan.y - (p.y - center.y) * scale)
    }
    func containsScreenPoint(_ p: PlanPoint, margin: Double = 40) -> Bool {
        p.x.isFinite && p.y.isFinite && p.x >= -margin && p.y >= -margin && p.x <= width + margin && p.y <= height + margin
    }
    func drawing(_ p: PlanPoint) -> PlanPoint {
        PlanPoint(x: center.x + (p.x - width / 2 - pan.x) / scale,
                  y: center.y - (p.y - height / 2 - pan.y) / scale)
    }
}

struct DXFDocument {
    let paths: [[PlanPoint]]
    let bounds: PlanBounds
    let insertionUnits: Int?
    let warnings: [String]

    /// Autodesk AutoCAD 2018 ASCII DXF group-code subset; see docs/p2-dxf.md.
    static func parse(_ data: Data) throws -> DXFDocument {
        func invalid(_ message: String) -> MappingError { .invalid("DXF: \(message)") }
        guard data.count <= 10_000_000, !data.contains(0),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            throw invalid("нужен текстовый DXF до 10 МБ; двоичный формат не поддерживается.")
        }
        let source = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        guard lines.count.isMultiple(of: 2), lines.count <= 600_000 else { throw invalid("повреждены пары код/значение или превышен лимит.") }
        struct Pair { let code: Int; let value: String }
        var pairs: [Pair] = []
        for i in stride(from: 0, to: lines.count, by: 2) {
            guard let code = Int(lines[i].trimmingCharacters(in: .whitespaces)), (0...1071).contains(code) else { throw invalid("некорректный код группы.") }
            pairs.append(Pair(code: code, value: lines[i + 1].trimmingCharacters(in: .whitespaces)))
        }
        guard pairs.last?.code == 0, pairs.last?.value == "EOF" else { throw invalid("отсутствует EOF.") }
        var section: String?, sawEntities = false, sawEOF = false
        var entities: [(String, [Pair])] = [], units: Int?
        var hiddenLayers = Set<String>()
        var i = 0
        while i < pairs.count {
            let p = pairs[i]
            if p.code == 999 { i += 1; continue }
            if p.code == 0 && p.value == "SECTION" {
                guard section == nil, i + 1 < pairs.count, pairs[i + 1].code == 2 else { throw invalid("повреждена секция.") }
                section = pairs[i + 1].value
                if section == "ENTITIES" { guard !sawEntities else { throw invalid("повтор ENTITIES.") }; sawEntities = true }
                i += 2; continue
            }
            if p.code == 0 && p.value == "ENDSEC" {
                guard section != nil else { throw invalid("лишний ENDSEC.") }; section = nil; i += 1; continue
            }
            if p.code == 0 && p.value == "EOF" {
                guard section == nil, i == pairs.count - 1 else { throw invalid("незавершённая секция.") }; sawEOF = true
            } else if section == "HEADER", p.code == 9, p.value == "$INSUNITS" {
                guard i + 1 < pairs.count, pairs[i + 1].code == 70, let value = Int(pairs[i + 1].value) else { throw invalid("повреждён INSUNITS.") }
                units = value
            } else if section == "TABLES", p.code == 0, p.value == "LAYER" {
                var end = i + 1
                while end < pairs.count && pairs[end].code != 0 { end += 1 }
                let fields = pairs[(i + 1)..<end]
                guard let name = fields.first(where: { $0.code == 2 })?.value,
                      let flags = Int(fields.first(where: { $0.code == 70 })?.value ?? "0"),
                      let color = Int(fields.first(where: { $0.code == 62 })?.value ?? "7") else { throw invalid("повреждён слой.") }
                if flags & 1 != 0 || color < 0 { hiddenLayers.insert(name) }
                i = end; continue
            } else if section == "ENTITIES" {
                guard p.code == 0 else { throw invalid("ожидался тип объекта.") }
                var end = i + 1
                while end < pairs.count && pairs[end].code != 0 { end += 1 }
                entities.append((p.value, Array(pairs[(i + 1)..<end]))); i = end; continue
            }
            i += 1
        }
        guard sawEntities, sawEOF else { throw invalid("отсутствует ENTITIES.") }
        var paths: [[PlanPoint]] = [], skipped: [String: Int] = [:], notes = Set<String>(), totalVertices = 0
        func skip(_ name: String) { skipped[name, default: 0] += 1 }
        func number(_ fields: [Pair], _ code: Int, default fallback: Double? = nil) throws -> Double {
            let matches = fields.filter { $0.code == code }
            guard matches.count <= 1 else { throw invalid("повтор одиночного кода \(code).") }
            guard let raw = matches.first?.value else {
                if let fallback { return fallback }; throw invalid("нет обязательного кода \(code).")
            }
            guard let result = Double(raw), result.isFinite, abs(result) <= 1e12 else { throw invalid("некорректное число.") }
            return result
        }
        func point(_ f: [Pair]) throws -> PlanPoint { try PlanPoint(x: number(f, 10), y: number(f, 20)) }
        func planar(_ f: [Pair]) throws -> Bool {
            try number(f, 210, default: 0) == 0 && number(f, 220, default: 0) == 0 && number(f, 230, default: 1) == 1
        }
        func append(_ points: [PlanPoint]) throws {
            totalVertices += points.count
            guard points.count >= 2, totalVertices <= 200_000,
                  points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e12 && abs($0.y) <= 1e12 }) else { throw invalid("пустая/слишком большая геометрия.") }
            paths.append(points)
        }
        var e = 0
        while e < entities.count {
            let (kind, f) = entities[e]; e += 1
            // Paper space and non-default OCS are never projected as if they were WCS.
            let layerVisible = !hiddenLayers.contains(f.first(where: { $0.code == 8 })?.value ?? "0")
            let visible = try number(f, 67, default: 0) == 0 && number(f, 60, default: 0) == 0 && layerVisible
            let layout = f.first { $0.code == 410 }?.value
            let inModel = layout == nil || layout == "Model"
            if kind == "POLYLINE" {
                var vertices: [[Pair]] = []
                while e < entities.count && entities[e].0 == "VERTEX" { vertices.append(entities[e].1); e += 1 }
                guard e < entities.count, entities[e].0 == "SEQEND" else { throw invalid("POLYLINE без SEQEND.") }; e += 1
                let flags = try number(f, 70, default: 0)
                guard flags.rounded() == flags, flags >= 0, flags <= 255 else { throw invalid("флаги POLYLINE.") }
                let unsupported = try vertices.contains { try number($0, 42, default: 0) != 0 || number($0, 30, default: 0) != 0 }
                guard visible, inModel, try planar(f), Int(flags) & ~1 == 0, !unsupported else { skip("POLYLINE (3D/OCS/bulge/flags/visibility)"); continue }
                var points = try vertices.map { try point($0) }
                if Int(flags) & 1 != 0, let first = points.first { points.append(first) }
                try append(points)
                continue
            }
            guard ["LINE", "LWPOLYLINE", "ARC", "CIRCLE"].contains(kind) else { skip(kind); continue }
            guard visible, inModel, try planar(f) else { skip("\(kind) (OCS/visibility)"); continue }
            switch kind {
            case "LINE":
                guard try number(f, 30, default: 0) == number(f, 31, default: 0) else { skip("LINE (3D)"); continue }
                try append([point(f), PlanPoint(x: number(f, 11), y: number(f, 21))])
            case "LWPOLYLINE":
                let flags = try number(f, 70, default: 0)
                guard flags.rounded() == flags, flags >= 0, flags <= 129 else { throw invalid("флаги LWPOLYLINE.") }
                guard Int(flags) & ~129 == 0 else { skip("LWPOLYLINE (flags)"); continue }
                if f.contains(where: { $0.code == 42 && Double($0.value) != 0 }) { skip("LWPOLYLINE (bulge)"); continue }
                var vertices: [[Pair]] = []
                for field in f {
                    if field.code == 10 { vertices.append([field]) }
                    else if [20, 40, 41, 42, 91].contains(field.code), !vertices.isEmpty { vertices[vertices.count - 1].append(field) }
                }
                guard try number(f, 90) == Double(vertices.count) else { throw invalid("не совпало число вершин LWPOLYLINE.") }
                var points = try vertices.map { try point($0) }
                if Int(flags) & 1 != 0, let first = points.first { points.append(first) }
                try append(points)
            default:
                let c = try point(f), r = try number(f, 40)
                guard r > 0 else { throw invalid("радиус должен быть положительным.") }
                let start = kind == "CIRCLE" ? 0 : try number(f, 50)
                let end = kind == "CIRCLE" ? 360 : try number(f, 51)
                guard (0...360).contains(start), (0...360).contains(end) else { throw invalid("угол дуги вне 0…360°.") }
                guard kind == "CIRCLE" || start != end else { throw invalid("дуга с совпадающими углами не поддерживается.") }
                var sweep = end - start
                if sweep <= 0 { sweep += 360 }
                let count = max(1, Int(ceil(sweep))) // <=1° display chords, never a survey approximation claim.
                let points = (0...count).map { index -> PlanPoint in
                    let a = (start + sweep * Double(index) / Double(count)) * .pi / 180
                    return PlanPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                }
                try append(points)
            }
            if f.contains(where: { [39, 40, 41, 43].contains($0.code) && Double($0.value) != 0 }), kind == "LINE" || kind == "LWPOLYLINE" {
                notes.insert("Толщина/ширина показана осевой линией.")
            }
        }
        guard let first = paths.first?.first else { throw invalid("нет поддерживаемой 2D-геометрии. BLOCK/INSERT не разворачиваются.") }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for path in paths { for p in path { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        notes.insert("Упрощённый 2D: стили, цвета и привязки не воспроизводятся; скрытые/замороженные слои пропущены. Проверьте исходный план.")
        for key in skipped.keys.sorted() { notes.insert("Пропущено \(key): \(skipped[key]!).") }
        return DXFDocument(paths: paths, bounds: PlanBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
                           insertionUnits: units, warnings: notes.sorted())
    }
}
