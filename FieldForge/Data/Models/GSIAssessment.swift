import Foundation

/// Read & Stacey (2009), Table 5.34, Hoek–Brown 2000 / Marinos & Hoek (2000).
/// Category matrix only: curved numerical contours have NOT been digitised.
enum GSIStructure: String, Codable, CaseIterable {
    case massive, blocky, veryBlocky, disturbed, disintegrated, laminatedSheared
    var title: String {
        switch self {
        case .massive: return "Массивный"
        case .blocky: return "Блочный"
        case .veryBlocky: return "Сильно блочный"
        case .disturbed: return "Блочный / нарушенный / с прослоями"
        case .disintegrated: return "Раздробленный"
        case .laminatedSheared: return "Слоистый / рассланцованный"
        }
    }
    var detail: String {
        switch self {
        case .massive: return "Монолитная порода или массив с редкими широко разнесёнными нарушениями."
        case .blocky: return "Ненарушенный массив с хорошо сцепленными кубическими блоками трёх пересекающихся систем."
        case .veryBlocky: return "Частично нарушенный массив со сцепленными многогранными угловатыми блоками четырёх и более систем."
        case .disturbed: return "Складчатый массив с угловатыми блоками многих систем; выдержанные плоскости напластования или сланцеватости."
        case .disintegrated: return "Слабо сцепленные, сильно раздробленные угловатые и округлые обломки."
        case .laminatedSheared: return "Нет блочности из-за близко расположенных слабых плоскостей сланцеватости или сдвига."
        }
    }
}
enum GSISurface: String, Codable, CaseIterable {
    case veryGood, good, fair, poor, veryPoor
    var title: String {
        switch self { case .veryGood: return "Очень хорошее"; case .good: return "Хорошее"; case .fair: return "Среднее"; case .poor: return "Плохое"; case .veryPoor: return "Очень плохое" }
    }
    var detail: String {
        switch self {
        case .veryGood: return "Очень шероховатые, свежие, невыветрелые поверхности."
        case .good: return "Шероховатые, слабо выветрелые поверхности с железистыми пятнами."
        case .fair: return "Гладкие, умеренно выветрелые и изменённые поверхности."
        case .poor: return "Зеркала скольжения, сильное выветривание, плотные покрытия или угловатый заполнитель."
        case .veryPoor: return "Зеркала скольжения, сильное выветривание, мягкие глинистые покрытия или заполнитель."
        }
    }
}
struct GSIChartSelection: Codable, Equatable {
    let structure: GSIStructure
    let surface: GSISurface
    /// Normalised categorical cell centre, not a numerical GSI mapping.
    let x: Double
    let y: Double
    init(structure: GSIStructure, surface: GSISurface) {
        self.structure = structure; self.surface = surface
        x = (Double(GSISurface.allCases.firstIndex(of: surface)!) + 0.5) / 5
        y = (Double(GSIStructure.allCases.firstIndex(of: structure)!) + 0.5) / 6
    }
    var applicable: Bool {
        !(structure == .massive && [.poor, .veryPoor].contains(surface)) &&
        !(structure == .laminatedSheared && [.veryGood, .good].contains(surface))
    }
    func validate() throws {
        guard self == Self(structure: structure, surface: surface), applicable else { throw StorageError.invalidRecord }
    }
}
struct GSIAssessment: Codable, Equatable {
    static let version = "Read-Stacey-2009/table5.34-HoekBrown2000/categorical-explicit-interval-v1"
    static let reference = "Read & Stacey (2009), Guidelines for Open Pit Slope Design, §5.4.4, Table 5.34; Marinos & Hoek (2000)."
    static let chartLimitation = "Это выбор категорий, а не полная диаграмма Read & Stacey, табл. 5.34. Числовые контуры и соответствие точки интервалу GSI не верифицированы; графическое определение GSI недоступно. Диапазон задаёт инженер вручную."
    static let limitation = "GSI может быть неприменим, если разрушение определяет ориентированная слабость, например неблагоприятные протяжённые трещины."
    let selection: GSIChartSelection
    let lower: Double
    let upper: Double
    let finalValue: Double?
    let assessedAt: Date
    var method = Self.version
    func validate() throws {
        try selection.validate()
        guard method == Self.version, lower.isFinite, upper.isFinite,
              (0...100).contains(lower), (lower...100).contains(upper),
              assessedAt.timeIntervalSinceReferenceDate.isFinite else { throw StorageError.invalidRecord }
        guard finalValue.map({ $0.isFinite && (lower...upper).contains($0) }) ?? true else {
            throw MappingError.invalid("Уточнённый GSI должен быть в выбранном диапазоне, включая его границы.")
        }
    }
}
