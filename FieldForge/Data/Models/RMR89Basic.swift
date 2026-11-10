import Foundation

/// Bieniawski (1989), Table 4.1 A/C (pp. 54–55) and Chart E (p. 58).
enum RMR89Parameter: String, CaseIterable, Sendable {
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
    struct Choice: Identifiable, Sendable {
        let id: String
        let title: String
        let rating: Int
        var range: ClosedRange<Double>? = nil
    }
    func choices(test: RMRStrengthTest?, historical: Bool = false) -> [Choice] {
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
            return rows([historical ? "Очень шероховатые; непротяжённые; сомкнутые; невыветрелые" : "Очень шероховатые; прерывистые; сомкнутые; невыветрелые",
                         "Слегка шероховатые; раскрытие <1 мм; слабо выветрелые стенки",
                         "Слегка шероховатые; раскрытие <1 мм; сильно выветрелые стенки",
                         historical ? "Зеркала скольжения / заполнитель <5 мм / раскрытие 1–5 мм; протяжённые" : "Непрерывные: зеркала скольжения, заполнитель <5 мм или раскрытие 1–5 мм",
                         historical ? "Мягкий заполнитель >5 мм / раскрытие >5 мм; протяжённые" : "Непрерывные: мягкий заполнитель >5 мм или раскрытие >5 мм"], [30, 25, 20, 10, 0])
        }
    }
}

enum RMR89DiscontinuityContinuity: String, Codable, CaseIterable, Sendable {
    case discontinuous, continuous
}

enum RMR89OrientationFavorability: String, Codable, CaseIterable, Sendable {
    case veryFavorable, favorable, fair, unfavorable, veryUnfavorable

    /// Table 4.1 B. Favorability is an explicit interpretation for the stated application.
    func adjustment(for application: RMREngineeringApplication) -> Int {
        let index = Self.allCases.firstIndex(of: self)!
        switch application {
        case .tunnelsAndMines: return [0, -2, -5, -10, -12][index]
        case .foundations: return [0, -2, -7, -15, -25][index]
        case .slopes: return [0, -5, -25, -50, -60][index]
        }
    }
}

struct RMR89BasicEvaluation: Codable, Equatable, Sendable {
    let components: [String: Int]
    let missing: [String]
    let value: Int?
    var orientationAdjustment: Int? = nil
    var adjustedValue: Int? = nil
    var rockClass: String? { value.flatMap(Self.classification) }
    var adjustedRockClass: String? { adjustedValue.flatMap(Self.classification) }
    var orientationStatus: String {
        if let adjustedValue { return adjustedValue < 0 ? "Сумма вне шкалы классов таблицы 4.1 C." : "Рассчитан по таблице 4.1 B." }
        if orientationAdjustment != nil { return "Для итога требуется базовый RMR89." }
        return "Требуются применение, категория ориентации и её обоснование."
    }
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
        try basicEvaluation(requireConfirmedA4: true)
    }

    func v3BasicEvaluation() throws -> RMR89BasicEvaluation {
        try basicEvaluation(requireConfirmedA4: false)
    }

    private func basicEvaluation(requireConfirmedA4: Bool) throws -> RMR89BasicEvaluation {
        let selected = try checkedSelections()
        var missing: [String] = [], components: [String: Int] = [:]
        let strength = try RatingNumber.optional(strengthMPa, name: RMR89Parameter.strength.title)
        if strengthTest == .pointLoadIs50, let strength, strength < 1 {
            missing.append("Is(50) <1 МПа: требуется UCS для оценки прочности")
        } else if let rating = fieldStrength?.rating ?? selected[.strength]?.rating {
            components["strength"] = rating
        } else {
            missing.append(strengthTest == nil ? "Метод испытания прочности" : RMR89Parameter.strength.title)
        }
        try checkGroundwater(selected[.groundwater])
        for parameter in [RMR89Parameter.rqd, .spacing, .groundwater] {
            if let rating = selected[parameter]?.rating { components[parameter.rawValue] = rating }
            else { missing.append(parameter.title) }
        }
        if let overall = selected[.overallCondition] {
            if requireConfirmedA4 {
                let conditionMissing = try checkOverallCondition(overall, selected: selected)
                if conditionMissing.isEmpty { components["condition"] = overall.rating }
                else { missing.append(contentsOf: conditionMissing) }
            } else {
                try checkV3OverallCondition(overall, selected: selected)
                components["condition"] = overall.rating
            }
        } else if let infill = selected[.infill], infill.id != "infill-0" {
            missing.append("Состояние в целом · A.4 (влияние заполнителя)")
        } else {
            let parameters: [RMR89Parameter] = [.persistence, .aperture, .roughness, .infill, .weathering]
            for parameter in parameters {
                if let rating = selected[parameter]?.rating { components[parameter.rawValue] = rating }
                else { missing.append(parameter.title) }
            }
            if parameters.allSatisfy({ selected[$0] != nil }) {
                components["condition"] = parameters.compactMap { selected[$0]?.rating }.reduce(0, +)
            }
        }
        let value = missing.isEmpty ? Self.basicTotal(components) : nil
        let adjustment = application.flatMap { application in
            orientationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : orientationFavorability?.adjustment(for: application)
        }
        return RMR89BasicEvaluation(components: components, missing: missing, value: value,
            orientationAdjustment: adjustment, adjustedValue: value.flatMap { value in adjustment.map { value + $0 } })
    }

    private func checkGroundwater(_ choice: RMR89Parameter.Choice?) throws {
        let maximum = Double.greatestFiniteMagnitude
        // A.5 gives alternative observations of the same row. Zero belongs to the dry row.
        let inflowBands: [ClosedRange<Double>] = [0...0, Double.leastNonzeroMagnitude...10.nextDown, 10...25, 25...125, 125.nextUp...maximum]
        let pressureBands: [ClosedRange<Double>] = [0...0, Double.leastNonzeroMagnitude...0.1.nextDown, 0.1...0.2, 0.2...0.5, 0.5.nextUp...maximum]
        let rows = RMR89Parameter.groundwater.choices(test: nil)
        var compatible = Set(rows.indices)
        for (name, raw, bands) in [("Приток", inflowLitersPerMinutePer10m, inflowBands), ("Отношение давления воды к σ1", waterPressureRatio, pressureBands)] {
            if let number = try RatingNumber.optional(raw, name: name) {
                compatible.formIntersection(bands.indices.filter { bands[$0].contains(number) })
            }
        }
        guard !compatible.isEmpty, choice == nil || compatible.contains(where: { rows[$0].id == choice?.id }) else {
            throw MappingError.invalid("Подземные воды: измерения и выбранная категория A.5 противоречат друг другу.")
        }
    }

    /// Table 4.1 A.4, pp. 54–55. Unknown evidence cannot satisfy a required descriptor.
    private func checkOverallCondition(_ overall: RMR89Parameter.Choice, selected: [RMR89Parameter: RMR89Parameter.Choice]) throws -> [String] {
        let measured = try RatingNumber.optional(apertureMillimeters, name: RMR89Parameter.aperture.title)
        let aperture = measured.map { $0...$0 } ?? selected[.aperture]?.range
        func matchesAperture(_ expected: ClosedRange<Double>) -> Bool? {
            guard let aperture else { return nil }
            if expected.contains(aperture.lowerBound) && expected.contains(aperture.upperBound) { return true }
            return aperture.overlaps(expected) ? nil : false
        }
        func any(_ alternatives: Bool?...) -> Bool? {
            if alternatives.contains(true) { return true }
            return alternatives.contains(nil) ? nil : false
        }
        let continuity = overallConditionContinuity
        let roughness = selected[.roughness]?.id
        let weathering = selected[.weathering]?.id
        let infill = selected[.infill]?.id
        let hasInfill = infill != nil && infill != "infill-0"
        // Section 2.4 defines separation as the distance between the walls. Gouge
        // of known positive thickness conflicts with closure, and >5 mm cannot
        // fit the mandatory <1 mm separation. The 10/0 rows use alternatives.
        let checks: [(String, Bool?)]
        switch overall.rating {
        case 30:
            checks = [("прерывистость", continuity.map { $0 == .discontinuous }),
                      ("очень шероховатые поверхности", roughness.map { $0 == "roughness-0" }),
                      ("отсутствие раскрытия", matchesAperture(0...0)),
                      ("заполнитель при отсутствии раскрытия", !hasInfill),
                      ("невыветрелые стенки", weathering.map { $0 == "weathering-0" })]
        case 25, 20:
            let slightlyWeathered = overall.rating == 25
            checks = [("слегка шероховатые поверхности", roughness.map { $0 == "roughness-2" }),
                      ("раскрытие <1 мм", matchesAperture(0...1.nextDown)),
                      ("заполнитель при отсутствии раскрытия", !hasInfill || aperture?.upperBound != 0),
                      ("заполнитель >5 мм при раскрытии <1 мм", infill != "infill-2" && infill != "infill-4"),
                      (slightlyWeathered ? "слабо выветрелые стенки" : "сильно выветрелые стенки",
                       weathering.map { $0 == (slightlyWeathered ? "weathering-1" : "weathering-3") })]
        case 10:
            let alternative = any(roughness.map { $0 == "roughness-4" },
                                  infill.map { $0 == "infill-1" || $0 == "infill-3" }, matchesAperture(1...5))
            checks = [("непрерывность", continuity.map { $0 == .continuous }),
                      ("зеркала скольжения, заполнитель <5 мм или раскрытие 1–5 мм", alternative)]
        case 0:
            let alternative = any(infill.map { $0 == "infill-4" }, matchesAperture(5.nextUp...Double.greatestFiniteMagnitude))
            checks = [("непрерывность", continuity.map { $0 == .continuous }),
                      ("мягкий заполнитель >5 мм или раскрытие >5 мм", alternative)]
        default: throw StorageError.invalidRecord
        }
        if let conflict = checks.first(where: { $0.1 == false }) {
            throw MappingError.invalid("Состояние A.4: противоречие с выбранной категорией (\(conflict.0)).")
        }
        return checks.compactMap { label, match in match == nil ? "A.4: требуется подтверждение (\(label))" : nil }
    }

    /// Frozen for validating v3 snapshots, which could use unconfirmed A.4 descriptors.
    private func checkV3OverallCondition(_ overall: RMR89Parameter.Choice, selected: [RMR89Parameter: RMR89Parameter.Choice]) throws {
        let measured = try RatingNumber.optional(apertureMillimeters, name: RMR89Parameter.aperture.title)
        let aperture = measured.map { $0...$0 } ?? selected[.aperture]?.range
        let infill = selected[.infill]?.id
        // Unknown evidence leaves the explicit A.4 interpretation to the engineer.
        // Reject only contradictions with the supplied structured evidence.
        let compatible: Bool
        switch overall.rating {
        case 30:
            compatible = aperture?.contains(0) != false && (infill == nil || infill == "infill-0")
                && selected[.roughness].map { $0.id == "roughness-0" } != false
                && selected[.weathering].map { $0.id == "weathering-0" } != false
        case 25, 20:
            compatible = aperture.map { $0.lowerBound < 1 } != false
                && selected[.roughness].map { $0.id == "roughness-2" } != false
                && selected[.weathering].map { $0.id == (overall.rating == 25 ? "weathering-1" : "weathering-3") } != false
        case 10:
            let slickensided = infill == nil || infill == "infill-0" ? selected[.roughness].map { $0.id == "roughness-4" } : false
            let thinGouge = infill.map { $0 == "infill-1" || $0 == "infill-3" }
            compatible = slickensided != false || thinGouge != false || aperture?.overlaps(1...5) != false
        case 0:
            let softThickGouge = infill.map { $0 == "infill-4" }
            compatible = softThickGouge != false || aperture.map { $0.upperBound > 5 } != false
        default: throw StorageError.invalidRecord
        }
        guard compatible else {
            throw MappingError.invalid("Состояние A.4: выбранная категория противоречит данным о трещинах.")
        }
    }

    private func checkedSelections() throws -> [RMR89Parameter: RMR89Parameter.Choice] {
        try validate()
        let selections = basicSelections ?? [:]
        var selected: [RMR89Parameter: RMR89Parameter.Choice] = [:]
        for (key, id) in selections {
            guard let parameter = RMR89Parameter(rawValue: key) else { throw StorageError.invalidRecord }
            guard let choice = parameter.choices(test: strengthTest).first(where: { $0.id == id }) else {
                throw MappingError.invalid("\(parameter.title): категория не поддерживается выбранным методом.")
            }
            selected[parameter] = choice
        }
        // If measured values are supplied they must agree with the explicitly chosen band.
        // Shared endpoints in the published ranges remain an explicit operator choice.
        for (parameter, raw) in [(RMR89Parameter.strength, strengthMPa), (.rqd, rqd), (.spacing, spacingMeters), (.persistence, persistenceMeters), (.aperture, apertureMillimeters)] {
            if let number = try RatingNumber.optional(raw, name: parameter.title), let range = selected[parameter]?.range, !range.contains(number) {
                throw MappingError.invalid("\(parameter.title): значение не соответствует выбранной категории.")
            }
        }
        return selected
    }

    private static func basicTotal(_ components: [String: Int]) -> Int {
        ["strength", "rqd", "spacing", "condition", "groundwater"].compactMap { components[$0] }.reduce(0, +)
    }

    /// The v1/v2 path remains frozen for validating the original saved results.
    func historicalBasicEvaluation() throws -> RMR89BasicEvaluation {
        let selected = try checkedSelections()
        var missing: [String] = [], components: [String: Int] = [:]
        if strengthTest == nil { missing.append("Метод испытания прочности") }
        for parameter in RMR89Parameter.allCases where parameter != .overallCondition {
            if parameter == .strength, strengthTest == .fieldEstimate, let fieldStrength {
                components[parameter.rawValue] = fieldStrength.rating
            } else if let choice = selected[parameter] { components[parameter.rawValue] = choice.rating }
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
        return RMR89BasicEvaluation(components: components, missing: missing, value: missing.isEmpty ? Self.basicTotal(components) : nil)
    }
}
