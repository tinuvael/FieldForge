import Foundation

/// Bieniawski 1989, Table 4.1 A/C/E; verified against Hoek, Practical Rock
/// Engineering, Rock mass classification, Table 4 (pp. 9–10), accessed 2026-10-21.
/// Explicit published categories, never an Is(50)/UCS conversion or Q correlation.
enum RMR89Parameter: String, CaseIterable {
    case strength, rqd, spacing, persistence, aperture, roughness, infill, weathering, groundwater, overallCondition
    var title: String {
        switch self {
        case .strength: return "Прочность, МПа"
        case .rqd: return "RQD, %"
        case .spacing: return "Расстояние между трещинами, м"
        case .persistence: return "Протяжённость, м"
        case .aperture: return "Раскрытие, мм"
        case .roughness: return "Шероховатость"
        case .infill: return "Заполнитель"
        case .weathering: return "Выветрелость"
        case .groundwater: return "Подземные воды"
        case .overallCondition: return "Состояние в целом · A.4"
        }
    }
    struct Choice: Identifiable {
        let id: String
        let title: String
        let rating: Int
        var range: ClosedRange<Double>? = nil
    }
    func choices(test: RMRStrengthTest?) -> [Choice] {
        func rows(_ labels: [String], _ ratings: [Int], _ ranges: [ClosedRange<Double>]? = nil) -> [Choice] {
            zip(labels.indices, zip(labels, ratings)).map { index, pair in
                Choice(id: "\(rawValue)-\(index)", title: pair.0, rating: pair.1, range: ranges?[index])
            }
        }
        let max = Double.greatestFiniteMagnitude
        switch self {
        case .strength:
            if test == .pointLoadIs50 {
                return [Choice(id: "is50-0", title: ">10", rating: 15, range: Double(10.0).nextUp...max),
                        Choice(id: "is50-1", title: "4–10", rating: 12, range: 4...10),
                        Choice(id: "is50-2", title: "2–4", rating: 7, range: 2...4),
                        Choice(id: "is50-3", title: "1–2", rating: 4, range: 1...2)]
            }
            guard test == .ucs else { return [] }
            return rows([">250", "100–250", "50–100", "25–50", "5–25", "1–5", "<1"], [15, 12, 7, 4, 2, 1, 0],
                        [Double(250.0).nextUp...max, 100...250, 50...100, 25...50, 5...25, 1...5, 0...1.nextDown])
        case .rqd: return rows(["90–100", "75–90", "50–75", "25–50", "<25"], [20, 17, 13, 8, 3], [90...100, 75...90, 50...75, 25...50, 0...25.nextDown])
        case .spacing: return rows([">2", "0,6–2", "0,2–0,6", "0,06–0,2", "<0,06"], [20, 15, 10, 8, 5], [Double(2.0).nextUp...max, 0.6...2, 0.2...0.6, 0.06...0.2, 0...0.06.nextDown])
        case .persistence: return rows(["<1", "1–3", "3–10", "10–20", ">20"], [6, 4, 2, 1, 0], [0...1.nextDown, 1...3, 3...10, 10...20, Double(20.0).nextUp...max])
        case .aperture: return rows(["Нет", "<0,1", "0,1–1", "1–5", ">5"], [6, 5, 4, 1, 0], [0...0, Double.leastNonzeroMagnitude...0.1.nextDown, 0.1...1, 1...5, Double(5.0).nextUp...max])
        case .roughness: return rows(["Очень шероховатая", "Шероховатая", "Слегка шероховатая", "Гладкая", "Зеркала скольжения"], [6, 5, 3, 1, 0])
        case .infill: return rows(["Нет", "Твёрдый <5 мм", "Твёрдый >5 мм", "Мягкий <5 мм", "Мягкий >5 мм"], [6, 4, 2, 2, 0])
        case .weathering: return rows(["Не выветрелые", "Слабо выветрелые", "Умеренно выветрелые", "Сильно выветрелые", "Разложившиеся"], [6, 5, 3, 1, 0])
        case .groundwater: return rows(["Сухо", "Влажно", "Мокро", "Капёж", "Течение"], [15, 10, 7, 4, 0])
        case .overallCondition:
            return rows(["Очень шероховатые; непротяжённые; сомкнутые; невыветрелые",
                         "Слегка шероховатые; раскрытие <1 мм; слабо выветрелые стенки",
                         "Слегка шероховатые; раскрытие <1 мм; сильно выветрелые стенки",
                         "Зеркала скольжения / заполнитель <5 мм / раскрытие 1–5 мм; протяжённые",
                         "Мягкий заполнитель >5 мм / раскрытие >5 мм; протяжённые"], [30, 25, 20, 10, 0])
        }
    }
}

struct RMR89BasicEvaluation: Codable, Equatable {
    let components: [String: Int]
    let missing: [String]
    let value: Int?
    var rockClass: String? { value.flatMap(Self.classification) }
    static func classification(_ value: Int) -> String? {
        switch value {
        case 81...100: return "I — очень хорошее качество"
        case 61...80: return "II — хорошее качество"
        case 41...60: return "III — среднее качество"
        case 21...40: return "IV — плохое качество"
        case 0...20: return "V — очень плохое качество"
        default: return nil
        }
    }
}

extension RMR89Input {
    func basicEvaluation() throws -> RMR89BasicEvaluation {
        try validate()
        let selections = basicSelections ?? [:]
        guard Set(selections.keys).isSubset(of: Set(RMR89Parameter.allCases.map(\.rawValue))) else { throw StorageError.invalidRecord }
        var selected: [RMR89Parameter: RMR89Parameter.Choice] = [:]
        for (key, id) in selections {
            guard let parameter = RMR89Parameter(rawValue: key), let choice = parameter.choices(test: strengthTest).first(where: { $0.id == id }) else { throw StorageError.invalidRecord }
            selected[parameter] = choice
        }
        // If measured values are supplied they must agree with the explicitly chosen band.
        // Shared endpoints in the published ranges remain an explicit operator choice.
        for (parameter, raw) in [(RMR89Parameter.strength, strengthMPa), (.rqd, rqd), (.spacing, spacingMeters), (.persistence, persistenceMeters), (.aperture, apertureMillimeters)] {
            if let number = try RatingNumber.optional(raw, name: parameter.title), let range = selected[parameter]?.range, !range.contains(number) {
                throw MappingError.invalid("\(parameter.title): значение не соответствует выбранной категории.")
            }
        }
        var missing: [String] = [], components: [String: Int] = [:]
        if strengthTest == nil { missing.append("Метод испытания прочности") }
        for parameter in RMR89Parameter.allCases where parameter != .overallCondition {
            if let choice = selected[parameter] { components[parameter.rawValue] = choice.rating }
            else { missing.append(parameter.title) }
        }
        // Table E footnote: gouge can mask roughness; use A.4 directly, never
        // infer an overall rating from unrelated NGI categories or free text.
        if let infill = selected[.infill], infill.id != "infill-0" {
            if infill.id == "infill-2" {
                // A.4 does not give a unique hard-gouge >5 mm category. Do not guess
                // or reuse the E sum in a case its footnote explicitly excludes.
                missing.append("Твёрдый заполнитель >5 мм: требуется уточнение категории A.4")
            } else if let overall = selected[.overallCondition] {
                let expected = infill.id == "infill-4" || selected[.aperture]?.id == "aperture-4" ? "overallCondition-4" : "overallCondition-3"
                guard overall.id == expected else {
                    throw MappingError.invalid("Категория A.4 не соответствует заполнителю / раскрытию. Проверьте полное описание, включая протяжённость.")
                }
                components["condition"] = overall.rating
            } else { missing.append("Состояние в целом · A.4 (влияние заполнителя)") }
        } else if [RMR89Parameter.persistence, .aperture, .roughness, .infill, .weathering].allSatisfy({ selected[$0] != nil }) {
            components["condition"] = [RMR89Parameter.persistence, .aperture, .roughness, .infill, .weathering].compactMap { selected[$0]?.rating }.reduce(0, +)
        }
        let total = ["strength", "rqd", "spacing", "condition", "groundwater"].compactMap { components[$0] }.reduce(0, +)
        return RMR89BasicEvaluation(components: components, missing: missing, value: missing.isEmpty ? total : nil)
    }
}
