import Foundation

/// NGI, Using the Q-system, April 2025. Numerical tables are isolated from UI/sensors.
/// Category IDs refer to appendix tables 2–6; H/H-star retain the two published intervals of table 6 H.
enum QParameter: String, Codable, CaseIterable { case jn, jr, ja, jw, srf }
struct QTableRow: Identifiable {
    let id: String
    let description: String
    let minimum: Double
    let maximum: Double
    let contact: QContact?
    init(_ id: String, _ description: String, _ min: Double, _ max: Double? = nil, contact: QContact? = nil) {
        self.id = id; self.description = description; minimum = min; maximum = max ?? min; self.contact = contact
    }
    var rangeText: String { minimum == maximum ? ElevationInput.text(minimum) : "\(ElevationInput.text(minimum))…\(ElevationInput.text(maximum))" }
}
enum QContact: String, Codable, CaseIterable { case wall, before10cm, noContact }
enum QLocation: String, Codable, CaseIterable {
    case ordinary, intersection, portal
    var multiplier: Double { switch self { case .ordinary: return 1; case .intersection: return 3; case .portal: return 2 } }
}
enum JrAdjustment: String, Codable, CaseIterable { case none, spacingOver3m, fewExposed }
enum SRFAdjustment: String, Codable, CaseIterable { case none, adjacentZone, shallowCrown }
enum RQDSource: String, Codable, CaseIterable { case coreMeasured, fieldEstimate, externalReport }

enum QMethod {
    static let version = "NGI-Q-2025-04/FieldForge-1"
    static let fieldVersion = "NGI-Q-2025-04/FieldForge-field-2"
    static let reference = "NGI (April 2025), Using the Q-system: Rock mass classification and support design; §§2–3, Tables 3-1…3-7, Appendix 1–6, Figure 4-1."
    static let url = "https://www.ngi.no/globalassets/bilder/forskning-og-radgivning/bygg-og-anlegg/q-handbook_2025_english_final.pdf"
    static func rows(_ parameter: QParameter) -> [QTableRow] {
        switch parameter {
        case .jn: return [
            .init("A", "Массивная порода: трещин нет или мало", 0.5, 1),
            .init("B", "Одна система", 2), .init("C", "Одна система и случайные трещины", 3),
            .init("D", "Две системы", 4), .init("E", "Две системы и случайные трещины", 6),
            .init("F", "Три системы", 9), .init("G", "Три системы и случайные трещины", 12),
            .init("H", "Четыре и более систем; интенсивная беспорядочная блочность", 15),
            .init("J", "Раздробленный массив, подобный грунту", 20)]
        case .jr: return [
            .init("A", "Прерывистые трещины / шероховатые ступенчатые", 4),
            .init("B", "Шероховатые волнистые / гладкие ступенчатые", 3),
            .init("C", "Гладкие волнистые / ступенчатые с зеркалами скольжения", 2),
            .init("D", "Волнистые с зеркалами скольжения", 1.5),
            .init("E", "Шероховатые плоские", 1.5), .init("F", "Гладкие плоские", 1),
            .init("G", "Плоские зеркала: штрихи по предполагаемому скольжению", 0.5),
            .init("H", "Мощный глинистый заполнитель исключает контакт стенок", 1, contact: .noContact)]
        case .ja: return [
            .init("A", "Плотно залеченные: твёрдый неразмокающий непроницаемый заполнитель (кварц, эпидот)", 0.75, contact: .wall),
            .init("B", "Неизменённые стенки; только окрашивание", 1, contact: .wall),
            .init("C", "Слабоизменённые; неразмокающие покрытия, песок, бесглинистый материал", 2, contact: .wall),
            .init("D", "Пылеватые/песчанистые глинистые покрытия; мало глины, не размокают", 3, contact: .wall),
            .init("E", "Размокающие/слабые покрытия: каолинит, слюда, хлорит, тальк, гипс, графит; немного набухающих глин", 4, contact: .wall),
            .init("F", "Тонкий песчаный бесглинистый заполнитель", 4, contact: .before10cm),
            .init("G", "Сплошная глина <5 мм: сильно переуплотнённая, неразмокающая", 6, contact: .before10cm),
            .init("H", "Сплошная глина <5 мм: средне/слабопереуплотнённая, размокающая", 8, contact: .before10cm),
            .init("J", "Сплошная набухающая глина <5 мм; оценить долю набухающих частиц", 8, 12, contact: .before10cm),
            .init("K", "Зоны разрушенной/раздробленной породы: сильно переуплотнённые", 6, contact: .noContact),
            .init("L", "Зоны глины/разрушенной породы: средне/слабопереуплотнённые или размокающие", 8, contact: .noContact),
            .init("M", "Зоны глины/разрушенной породы: набухающие; оценить долю частиц", 8, 12, contact: .noContact),
            .init("N", "Мощные сплошные глинистые зоны: сильно переуплотнённые", 10, contact: .noContact),
            .init("O", "Мощные сплошные глинистые зоны: средне/слабопереуплотнённые", 13, contact: .noContact),
            .init("P", "Мощные сплошные набухающие глинистые зоны; оценить долю частиц", 13, 20, contact: .noContact)]
        case .jw: return [
            .init("A", "Сухо / небольшой приток: влажность, отдельные капли", 1),
            .init("B", "Средний приток: частые капли/дождь, местный вынос заполнителя", 0.66),
            .init("C", "Струи / высокое давление в прочной породе без заполнителя", 0.5),
            .init("D", "Большой приток / высокое давление, значительный вынос заполнителя", 0.33),
            .init("E", "Исключительный приток/давление, убывает со временем; вынос материала, возможен вывал", 0.1, 0.2),
            .init("F", "Исключительный приток/давление без заметного убывания; вынос материала, возможен вывал", 0.05, 0.1)]
        case .srf: return [
            .init("A", "Много слабых глинистых/изменённых зон на коротком участке, рыхлое окружение или протяжённая слабая порода; любая глубина", 10),
            .init("B", "Много зон сдвига на коротком участке в прочной бесглинистой породе с разрыхлённым окружением; любая глубина", 7.5),
            .init("C", "Одиночная слабая зона с глиной/изменением или без них; глубина ≤50 м", 5),
            .init("D", "Открытые рыхлые трещины, интенсивная блочность; любая глубина", 5),
            .init("E", "Одиночная слабая зона с глиной/изменением или без них; глубина >50 м", 2.5),
            .init("F", "Массивная прочная порода: низкие напряжения, малая глубина, открытые трещины", 2.5),
            .init("G", "Массивная прочная порода: средние благоприятные напряжения", 1),
            .init("H", "H: высокие напряжения, плотная структура; диапазон 0,5–2 (§3.7.3)", 0.5, 2),
            .init("H-star", "H*: высокие напряжения, диапазон 2–5; оценить ориентацию и анизотропию (§3.7.3)", 2, 5),
            .init("J", "Массивная порода: умеренное шелушение/отслоение спустя >1 часа", 5, 50),
            .init("K", "Массивная порода: отслоение/удары через несколько минут", 50, 200),
            .init("L", "Массивная порода: сильные удары и немедленные динамические деформации", 200, 400),
            .init("M", "Умеренное пластическое выдавливание слабой породы под давлением", 5, 10),
            .init("N", "Сильное пластическое выдавливание слабой породы под давлением", 10, 20),
            .init("O", "Умеренное химическое набухание при участии воды", 5, 10),
            .init("P", "Сильное химическое набухание при участии воды", 10, 15)]
        }
    }
}

/// Original text, table choice and field rationale survive persistence without normalization.
enum QValueOrigin: String, Codable { case tableSelection, manualWithinRow }
struct QCoefficientInput: Codable, Equatable {
    var category: String?
    var value = "" { didSet { origin = .manualWithinRow } }
    var origin = QValueOrigin.manualWithinRow
    var evidence = ""
    mutating func select(_ id: String?, parameter: QParameter) {
        category = id
        // A single-valued table row is an explicit selection; ranges require the assessor's value.
        let row = QMethod.rows(parameter).first { $0.id == id }
        value = row.flatMap { $0.minimum == $0.maximum ? ElevationInput.text($0.minimum) : nil } ?? ""
        origin = row.map { $0.minimum == $0.maximum ? .tableSelection : .manualWithinRow } ?? .manualWithinRow
    }
    func validated(_ parameter: QParameter) throws -> Double? {
        let number = try RatingNumber.optional(value, name: parameter.rawValue)
        guard let category else {
            guard number == nil else { throw MappingError.invalid("\(parameter.rawValue): сначала выберите строку NGI 2025.") }
            return nil
        }
        guard let row = QMethod.rows(parameter).first(where: { $0.id == category }) else { throw StorageError.invalidRecord }
        if let number {
            guard number > 0, (row.minimum...row.maximum).contains(number) else {
                throw MappingError.invalid("\(parameter.rawValue): допустимо \(row.rangeText) для строки \(category).")
            }
        }
        return number
    }
}
enum RatingNumber {
    static func optional(_ text: String, name: String, range: ClosedRange<Double>? = nil) throws -> Double? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let value = try? ElevationInput.meters(text), range.map({ $0.contains(value) }) ?? true else {
            throw MappingError.invalid("\(name): недопустимое число\(range.map { " (\($0.lowerBound)…\($0.upperBound))" } ?? "").")
        }
        return value
    }
}

struct BartonQInput: Codable, Equatable {
    var rqd = ""
    var rqdSource: RQDSource?
    var rqdEvidence = ""
    var jn = QCoefficientInput(), jr = QCoefficientInput(), ja = QCoefficientInput(), jw = QCoefficientInput(), srf = QCoefficientInput()
    var location: QLocation?
    var contact: QContact?
    var jrAdjustment = JrAdjustment.none
    var relevantSpacingMeters = ""
    var srfAdjustment = SRFAdjustment.none
    var srfReductionPercent = ""
    var correctionEvidence = ""
    var assessor = "", assessmentSource = "", geologicalDescription = "", missingReason = ""
    var hasChanges: Bool { self != BartonQInput() }
    subscript(_ parameter: QParameter) -> QCoefficientInput {
        get { switch parameter { case .jn: return jn; case .jr: return jr; case .ja: return ja; case .jw: return jw; case .srf: return srf } }
        set { switch parameter { case .jn: jn = newValue; case .jr: jr = newValue; case .ja: ja = newValue; case .jw: jw = newValue; case .srf: srf = newValue } }
    }
    // Legacy assessment validation remains byte-for-byte equivalent in its decisions.
    func evaluate() throws -> QEvaluation { try evaluate(requireDocumentation: true) }
    var derivedContact: QContact? { QMethod.rows(.ja).first { $0.id == ja.category }?.contact }
    func fieldEvaluation() throws -> QEvaluation { try evaluate(requireDocumentation: false) }
    var isFieldPreliminary: Bool {
        var documented = self
        if documented.contact == nil { documented.contact = derivedContact }
        return (try? documented.evaluate().result) == nil
    }
    private func evaluate(requireDocumentation: Bool) throws -> QEvaluation {
        let contact = self.contact ?? (requireDocumentation ? nil : derivedContact)
        let measured = try RatingNumber.optional(rqd, name: "RQD, %", range: 0...100)
        let n = try jn.validated(.jn), r = try jr.validated(.jr), a = try ja.validated(.ja)
        let w = try jw.validated(.jw), stress = try srf.validated(.srf)
        let spacing = try RatingNumber.optional(relevantSpacingMeters, name: "Расстояние для Jr, м", range: 0...Double.greatestFiniteMagnitude)
        let reduction = try RatingNumber.optional(srfReductionPercent, name: "Снижение SRF, %", range: 25...50)
        if let contact {
            if let row = QMethod.rows(.ja).first(where: { $0.id == ja.category }), row.contact != contact {
                throw MappingError.invalid("Ja не соответствует выбранному контакту стенок.")
            }
            if jr.category != nil && ((jr.category == "H") != (contact == .noContact)) {
                throw MappingError.invalid("Jr: при отсутствии контакта используйте H = 1; при контакте — A–G.")
            }
        }
        if jrAdjustment != .none {
            guard contact != .noContact, jr.category != "H" else { throw MappingError.invalid("Jr +1 неприменим без контакта стенок.") }
            if jrAdjustment == .spacingOver3m, let spacing, spacing <= 3 { throw MappingError.invalid("Jr +1 требует среднего расстояния >3 м.") }
        }
        if srfAdjustment == .adjacentZone, let category = srf.category, !["A", "B", "C", "D", "E"].contains(category) {
            throw MappingError.invalid("Снижение SRF применимо только к строкам A–E: зона влияет, но не пересекает выработку.")
        }
        if srfAdjustment == .shallowCrown, let category = srf.category, category != "F" {
            throw MappingError.invalid("SRF = 5 при покрытии меньше пролёта применимо к строке F.")
        }
        if srfAdjustment != .adjacentZone && reduction != nil { throw MappingError.invalid("Для процента снижения выберите поправку на соседнюю зону.") }
        var missing: [String] = []
        for parameter in QParameter.allCases {
            let coefficient = self[parameter]
            if requireDocumentation, let row = QMethod.rows(parameter).first(where: { $0.id == coefficient.category }), row.minimum != row.maximum,
               coefficient.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("Обоснование значения диапазона \(parameter.rawValue)")
            }
        }
        if measured == nil { missing.append("RQD") }
        if requireDocumentation && rqdSource == nil { missing.append("Источник RQD") }
        for (label, value) in [("Jn", n), ("Jr", r), ("Ja", a), ("Jw", w), ("SRF", stress)] { if value == nil { missing.append(label) } }
        if location == nil { missing.append("Положение выработки для Jn") }
        if contact == nil { missing.append("Контакт стенок для Jr/Ja") }
        if requireDocumentation && assessmentSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Источник оценки") }
        if jrAdjustment == .spacingOver3m && spacing == nil { missing.append("Среднее расстояние для Jr +1") }
        if srfAdjustment == .adjacentZone && reduction == nil { missing.append("Процент снижения SRF") }
        if requireDocumentation && (jrAdjustment != .none || srfAdjustment != .none) && correctionEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Обоснование поправок и геометрии выработки")
        }
        guard missing.isEmpty, let measured, let n, let r, let a, let w, let stress, let location else {
            return QEvaluation(result: nil, missing: missing)
        }
        let usedRQD = max(10, measured)
        let usedJn = n * location.multiplier
        let usedJr = r + (jrAdjustment == .none ? 0 : 1)
        let usedSRF: Double
        switch srfAdjustment {
        case .none: usedSRF = stress
        case .shallowCrown: usedSRF = 5
        case .adjacentZone:
            guard let reduction else { throw StorageError.invalidRecord }
            usedSRF = stress * (1 - reduction / 100)
        }
        guard usedJn > 0, a > 0, usedSRF > 0 else { throw StorageError.invalidRecord }
        let q = (usedRQD / usedJn) * (usedJr / a) * (w / usedSRF)
        guard q.isFinite, q > 0 else { throw StorageError.invalidRecord }
        return QEvaluation(result: QResult(measuredRQD: measured, calculationRQD: usedRQD, jn: usedJn, jr: usedJr,
                                           ja: a, jw: w, srf: usedSRF, value: q, rockClass: QRockClass.classify(q)), missing: [])
    }
}
struct QEvaluation: Codable, Equatable { let result: QResult?; let missing: [String] }
struct QResult: Codable, Equatable {
    let measuredRQD: Double
    let calculationRQD: Double
    let jn: Double, jr: Double, ja: Double, jw: Double, srf: Double
    let value: Double
    let rockClass: QRockClass?
}
/// Figure 4-1, published Q scale 0.001–1000. Shared boundaries assigned to the higher class.
/// Outside the published scale the numerical Q is retained without extrapolating a class.
enum QRockClass: String, Codable {
    case exceptionallyPoor, extremelyPoor, veryPoor, poor, fair, good, veryGood
    static func classify(_ q: Double) -> Self? {
        guard q.isFinite, (0.001...1000).contains(q) else { return nil }
        switch q {
        case ..<0.01: return .exceptionallyPoor
        case ..<0.1: return .extremelyPoor
        case ..<1: return .veryPoor
        case ..<4: return .poor
        case ..<10: return .fair
        case ..<40: return .good
        default: return .veryGood
        }
    }
}
struct BartonQAssessment: Codable, Equatable {
    let method: String
    let revision: Int
    let assessedAt: Date
    let input: BartonQInput
    let evaluation: QEvaluation
    init(input: BartonQInput, now: Date) throws {
        method = QMethod.fieldVersion; revision = 1; assessedAt = now; self.input = input; evaluation = try input.fieldEvaluation()
    }
    func validate() throws {
        guard [QMethod.version, QMethod.fieldVersion].contains(method), revision == 1, assessedAt.timeIntervalSinceReferenceDate.isFinite,
              evaluation == (try method == QMethod.version ? input.evaluate() : input.fieldEvaluation()) else { throw StorageError.invalidRecord }
    }
}

enum RMRStrengthTest: String, Codable, CaseIterable {
    case ucs, pointLoadIs50, fieldEstimate
    var title: String {
        switch self { case .ucs: return "UCS — одноосное сжатие"; case .pointLoadIs50: return "Is(50) — точечное нагружение"; case .fieldEstimate: return "Полевая оценка R0–R6" }
    }
}
enum RMREngineeringApplication: String, Codable, CaseIterable { case tunnelsAndMines, foundations, slopes }
/// Original free-text evidence remains intact; optional explicit selections enable basic-v1.
struct RMR89Input: Codable, Equatable {
    var basicSelections: [String: String]? = nil
    var fieldStrength: FieldStrengthAssessment? = nil
    var jcond76: JCond76Assessment? = nil
    var strengthTest: RMRStrengthTest?
    var strengthMPa = "", strengthEvidence = "", rqd = "", rqdEvidence = "", spacingMeters = ""
    var persistenceMeters = "", apertureMillimeters = "", roughness = "", infill = "", weathering = ""
    var groundwater = "", inflowLitersPerMinutePer10m = "", waterPressureRatio = ""
    var application: RMREngineeringApplication?
    var orientationDescription = "", source = "", assessor = "", missingReason = ""
    var hasChanges: Bool { self != RMR89Input() }
    func validate() throws {
        try fieldStrength?.validate(); try jcond76?.validate()
        guard (fieldStrength == nil || strengthTest == .fieldEstimate),
              strengthTest != .fieldEstimate || (strengthMPa.isEmpty && basicSelections?["strength"] == nil) else {
            throw MappingError.invalid("Выберите один метод прочности: полевая категория или лабораторный результат.")
        }
        for (name, text) in [("Прочность, МПа", strengthMPa), ("Расстояние, м", spacingMeters)] {
            if let number = try RatingNumber.optional(text, name: name), number <= 0 { throw MappingError.invalid("\(name): требуется значение >0.") }
        }
        _ = try RatingNumber.optional(rqd, name: "RMR: RQD, %", range: 0...100)
        for (name, text) in [("Протяжённость, м", persistenceMeters), ("Раскрытие, мм", apertureMillimeters),
                             ("Приток, л/мин на 10 м", inflowLitersPerMinutePer10m), ("Отношение давления воды к σ1", waterPressureRatio)] {
            _ = try RatingNumber.optional(text, name: name, range: 0...Double.greatestFiniteMagnitude)
        }
    }
    var missing: [String] {
        var values = [("Прочность", strengthMPa), ("RQD", rqd), ("Расстояние", spacingMeters),
                      ("Протяжённость", persistenceMeters), ("Раскрытие", apertureMillimeters), ("Шероховатость", roughness),
                      ("Заполнитель", infill), ("Выветрелость", weathering), ("Источник", source), ("Ориентация", orientationDescription)]
        if [groundwater, inflowLitersPerMinutePer10m, waterPressureRatio].allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { values.append(("Подземные воды", "")) }
        var result = values.filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0)
        if strengthTest == nil { result.append("Метод испытания прочности") }
        if application == nil { result.append("Инженерное применение") }
        return result
    }
}
struct RMR89Assessment: Codable, Equatable {
    static let version = "Bieniawski-RMR89/input-only-v1"
    static let calculatedVersion = "Bieniawski-RMR89/basic-categories-v1"
    static let fieldStrengthVersion = "Bieniawski-RMR89/basic-categories-field-strength-v2"
    static let reference = "Bieniawski, Z.T. (1989). Engineering Rock Mass Classifications. Wiley. ISBN 0-471-60172-1."
    let method: String
    let revision: Int
    let assessedAt: Date
    let input: RMR89Input
    let missing: [String]
    let calculation: RMR89BasicEvaluation?
    init(input: RMR89Input, now: Date) throws {
        try input.validate(); revision = 1; assessedAt = now; self.input = input
        calculation = try input.basicSelections == nil && input.strengthTest != .fieldEstimate ? nil : input.basicEvaluation()
        method = input.strengthTest == .fieldEstimate ? Self.fieldStrengthVersion : calculation == nil ? Self.version : Self.calculatedVersion
        missing = calculation?.missing ?? input.missing
    }
    func validate() throws {
        try input.validate()
        guard revision == 1, assessedAt.timeIntervalSinceReferenceDate.isFinite else { throw StorageError.invalidRecord }
        if method == Self.version {
            guard input.strengthTest != .fieldEstimate, calculation == nil, input.basicSelections == nil, missing == input.missing else { throw StorageError.invalidRecord }
        } else {
            guard method == (input.strengthTest == .fieldEstimate ? Self.fieldStrengthVersion : Self.calculatedVersion),
                  input.basicSelections != nil || input.strengthTest == .fieldEstimate,
                  calculation == (try input.basicEvaluation()), missing == calculation?.missing else { throw StorageError.invalidRecord }
        }
    }
}
struct MappingRatings: Codable, Equatable {
    let bartonQ: BartonQAssessment?
    let rmr89: RMR89Assessment?
    var gsi: GSIAssessment? = nil
    func validate() throws { try bartonQ?.validate(); try rmr89?.validate(); try gsi?.validate() }
}
extension MappingDraft {
    func ratings(now: Date) throws -> MappingRatings? {
        guard bartonQ.hasChanges || rmr89.hasChanges || gsi != nil else { return nil }
        return MappingRatings(bartonQ: try bartonQ.hasChanges ? BartonQAssessment(input: bartonQ, now: now) : nil,
                              rmr89: try rmr89.hasChanges ? RMR89Assessment(input: rmr89, now: now) : nil, gsi: gsi)
    }
}

/// Owner-defined field presentation (third iPhone review, 2026-10-21).
/// Separate from published NGI classes and stored Q snapshots. No mechanical conclusion.
enum FieldQCategory: Equatable {
    case veryUnstable, unstable, medium, stable
    init?(q: Double) {
        guard q.isFinite, q >= 0 else { return nil }
        if q < 1 { self = .veryUnstable }
        else if q < 4 { self = .unstable }
        else if q <= 10 { self = .medium }
        else { self = .stable }
    }
    var title: String {
        switch self {
        case .veryUnstable: return "Весьма неустойчивые породы"
        case .unstable: return "Неустойчивые породы"
        case .medium: return "Средней устойчивости"
        case .stable: return "Устойчивые породы"
        }
    }
}

extension QRockClass {
    var title: String {
        switch self {
        case .exceptionallyPoor: return "G · Исключительно плохой (0,001 ≤ Q < 0,01)"
        case .extremelyPoor: return "F · Крайне плохой (0,01 ≤ Q < 0,1)"
        case .veryPoor: return "E · Очень плохой (0,1 ≤ Q < 1)"
        case .poor: return "D · Плохой (1 ≤ Q < 4)"
        case .fair: return "C · Средний (4 ≤ Q < 10)"
        case .good: return "B · Хороший (10 ≤ Q < 40)"
        case .veryGood: return "A · Очень хороший (40 ≤ Q ≤ 1000)"
        }
    }
}
