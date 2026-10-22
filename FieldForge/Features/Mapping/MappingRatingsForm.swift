import SwiftUI

struct MappingRatingsForm: View {
    @Binding var q: BartonQInput
    @Binding var rmr: RMR89Input
    @Binding var gsi: GSIAssessment?
    let focus: FocusState<Bool>.Binding
    var body: some View {
        Section("Рейтинги массива") {
            DisclosureGroup("Barton Q") {
                BartonQForm(input: $q, focus: focus)
            }
            DisclosureGroup("RMR89 · базовый рейтинг") {
                RMR89Form(input: $rmr, focus: focus)
            }
            NavigationLink { GSISelectionView(assessment: $gsi) } label: {
                LabeledContent("GSI", value: gsi.map { $0.chartPosition != nil ? "≈ \(Int($0.finalValue!))" : "\(EngineeringDisplay.number($0.lower))–\(EngineeringDisplay.number($0.upper))" } ?? "Оценить")
            }.accessibilityIdentifier("openGSI")
            if let warning = SpacingRQD(q: q, rmr: rmr).warning { Text(warning).font(.caption).foregroundStyle(.orange) }
        }
    }
}
private struct BartonQForm: View {
    @Binding var input: BartonQInput
    let focus: FocusState<Bool>.Binding
    var body: some View {
        RatingField("RQD, %", text: $input.rqd, id: "qRQD", focus: focus, numeric: true)
        ForEach(QParameter.allCases, id: \.self) { parameter in
            QCoefficientForm(parameter: parameter, input: Binding(get: { input[parameter] }, set: { input[parameter] = $0 }), focus: focus)
        }
        Picker("Участок · Jn", selection: $input.location) {
            Text("Выбрать участок").tag(nil as QLocation?)
            ForEach(QLocation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("qLocation")
        QCalculationPreview(input: input)
        NavigationLink("Сведения об оценке") {
            Form {
                Section("Документирование · необязательно для числа Q") {
                    Picker("Источник RQD", selection: $input.rqdSource) {
                        Text("Не указан").tag(nil as RQDSource?)
                        ForEach(RQDSource.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    RatingField("RQD: источник", text: $input.rqdEvidence, id: "qRQDEvidence", focus: focus)
                    RatingField("Источник оценки", text: $input.assessmentSource, id: "qAssessmentSource", focus: focus)
                    RatingField("Автор", text: $input.assessor, id: "qAssessor", focus: focus)
                    RatingField("Геологическое описание", text: $input.geologicalDescription, id: "qDescription", focus: focus)
                    RatingField("Причина отсутствия данных", text: $input.missingReason, id: "qMissingReason", focus: focus)
                    ForEach(QParameter.allCases, id: \.self) { parameter in
                        RatingField("Обоснование \(parameter.rawValue)", text: Binding(get: { input[parameter].evidence }, set: { input[parameter].evidence = $0 }), id: "qEvidence-\(parameter.rawValue)", focus: focus)
                    }
                }
                Section("Поправки · только при применимости по NGI") {
                    Picker("Поправка Jr", selection: $input.jrAdjustment) {
                        ForEach(JrAdjustment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if input.jrAdjustment == .spacingOver3m || !input.relevantSpacingMeters.isEmpty {
                        RatingField("Среднее расстояние, м (>3)", text: $input.relevantSpacingMeters, id: "qJrSpacing", focus: focus, numeric: true)
                    }
                    Picker("Поправка SRF", selection: $input.srfAdjustment) {
                        ForEach(SRFAdjustment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if input.srfAdjustment == .adjacentZone || !input.srfReductionPercent.isEmpty {
                        RatingField("Снижение SRF, % (25…50)", text: $input.srfReductionPercent, id: "qSRFReduction", focus: focus, numeric: true)
                    }
                    RatingField("Обоснование поправок и геометрии", text: $input.correctionEvidence, id: "qCorrections", focus: focus)
                    if input.contact != nil {
                        Picker("Ранее заданный контакт Jr/Ja", selection: $input.contact) {
                            Text("По выбранной категории Ja").tag(nil as QContact?)
                            ForEach(QContact.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                }
                Section("Методика") {
                    Text("Категория по Q — упрощение FieldForge: Q < 1; 1 ≤ Q < 4; 4 ≤ Q ≤ 10; Q > 10. Не подтверждает механическую устойчивость или достаточность крепи.").font(.caption)
                    Text("NGI · апрель 2025. Коэффициенты выбирает инженер. При RQD ≤10% в расчёте используется 10%. Крепь не рассчитывается.").font(.caption)
                    Link("Руководство NGI 2025", destination: URL(string: QMethod.url)!)
                    if let strict = try? input.evaluate(), !strict.missing.isEmpty {
                        Text("Для полной документации: \(strict.missing.joined(separator: ", "))").font(.caption)
                    }
                }
            }.navigationTitle("Сведения об оценке").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct QCoefficientForm: View {
    let parameter: QParameter
    @Binding var input: QCoefficientInput
    let focus: FocusState<Bool>.Binding
    private var row: QTableRow? { QMethod.rows(parameter).first { $0.id == input.category } }
    private var valueText: String {
        do {
            guard let value = try input.validated(parameter) else { return "Указать" }
            return EngineeringDisplay.significant(value)
        } catch { return "Исправить" }
    }
    var body: some View {
        NavigationLink {
            QCoefficientSelection(parameter: parameter, input: $input)
        } label: {
            LabeledContent(parameter.title, value: valueText)
        }.accessibilityIdentifier("qCategory-\(parameter.rawValue)")
        if let row {
            if row.minimum != row.maximum {
                RatingField("\(parameter.rawValue): выберите значение \(row.rangeText)", text: $input.value, id: "qValue-\(parameter.rawValue)", focus: focus, numeric: true)
                HStack {
                    ForEach([row.minimum, row.maximum], id: \.self) { value in
                        Button(EngineeringDisplay.number(value)) { input.value = ElevationInput.text(value) }
                            .buttonStyle(.bordered)
                    }
                    Text("Границы диапазона · выбор инженера").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let contact = row.contact, parameter == .ja {
                Text(contact.title).font(.caption).foregroundStyle(.secondary)
            }
            if case .failure(let error) = Result(catching: { try input.validated(parameter) }) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct QCoefficientSelection: View {
    let parameter: QParameter
    @Binding var input: QCoefficientInput
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        List {
            Button("Не выбрано") { input.select(nil, parameter: parameter); dismiss() }
            ForEach(QMethod.rows(parameter)) { row in
                Button { input.select(row.id, parameter: parameter); dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.description)
                            Text("\(row.id) · \(row.rangeText)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.id == input.category { Image(systemName: "checkmark") }
                    }.padding(.vertical, 4)
                }
            }
            if let row = QMethod.rows(parameter).first(where: { $0.id == input.category }), row.minimum == row.maximum {
                DisclosureGroup("Дополнительно · выбранная категория") {
                    Text(row.description).font(.caption)
                    RatingField("\(parameter.rawValue): \(row.rangeText)", text: $input.value, id: "qValue-\(parameter.rawValue)", focus: $focused, numeric: true)
                    RatingField("Источник / обоснование", text: $input.evidence, id: "qEvidence-\(parameter.rawValue)", focus: $focused)
                }
            }
        }.navigationTitle(parameter.title).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } } }
    }
}

struct QCalculationPreview: View {
    let input: BartonQInput
    var body: some View {
        if let evaluation = try? input.fieldEvaluation() {
            QCalculationText(evaluation: evaluation, compact: true)
            if evaluation.result != nil && input.isFieldPreliminary {
                Text("Предварительная полевая оценка · документация неполная").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Недостаточно данных для расчёта").accessibilityIdentifier("qMissingStatus")
            if case .failure(let error) = Result(catching: { try input.fieldEvaluation() }) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
struct QCalculationText: View {
    let evaluation: QEvaluation
    var compact = false
    var body: some View {
        if let result = evaluation.result {
            Text("Q ≈ \(EngineeringDisplay.significant(result.value))").font(.headline).accessibilityIdentifier("qResult")
            if let category = FieldQCategory(q: result.value) {
                LabeledContent("Категория по Q", value: category.title)
            }
            if !compact {
                Text(result.rockClass?.title ?? "Значение вне опубликованной шкалы классов 0,001…1000")
                Text("RQD исходное: \(EngineeringDisplay.significant(result.measuredRQD))%; в расчёте: \(EngineeringDisplay.significant(result.calculationRQD))%")
                Text("Q = (\(EngineeringDisplay.significant(result.calculationRQD)) / \(EngineeringDisplay.significant(result.jn))) × (\(EngineeringDisplay.significant(result.jr)) / \(EngineeringDisplay.significant(result.ja))) × (\(EngineeringDisplay.significant(result.jw)) / \(EngineeringDisplay.significant(result.srf)))")
                .font(.caption).textSelection(.enabled)
            }
        } else {
            Text("Недостаточно данных для расчёта").accessibilityIdentifier("qMissingStatus")
            Text("Не указано: \(evaluation.missing.joined(separator: ", "))").font(.caption)
        }
    }
}
private struct RMR89Form: View {
    @Binding var input: RMR89Input
    let focus: FocusState<Bool>.Binding
    var body: some View {
        Picker("Метод прочности", selection: Binding(get: { input.strengthTest }, set: {
            guard input.strengthTest != $0 else { return }
            input.strengthTest = $0
            input.fieldStrength = nil
            if $0 == .fieldEstimate { input.strengthMPa = "" }
            if input.basicSelections != nil { input.basicSelections?["strength"] = nil }
        })) {
            Text("Не указано").tag(nil as RMRStrengthTest?)
            ForEach(RMRStrengthTest.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("rmrStrengthBasis")
        ForEach(RMR89Parameter.allCases.filter { $0 != .overallCondition }, id: \.self) { parameter in
            if parameter == .strength && input.strengthTest == .fieldEstimate {
                Picker("Полевая прочность R0–R6", selection: Binding(get: { input.fieldStrength?.grade }, set: {
                    input.fieldStrength = $0.map(FieldStrengthAssessment.init)
                    if input.basicSelections == nil { input.basicSelections = [:] }
                })) {
                    Text("Выберите категорию").tag(nil as FieldStrengthGrade?)
                    ForEach(FieldStrengthGrade.allCases, id: \.self) { grade in
                        Text("\(grade.rawValue) · \(grade.recognition) · \(grade.interval) МПа · \(grade.rating) балл.").tag(Optional(grade))
                    }
                }.accessibilityIdentifier("rmrFieldStrength")
            } else { category(parameter) }
        }
        if let infill = input.basicSelections?["infill"], infill != "infill-0" {
            Text("Заполнитель влияет на шероховатость: выберите общее состояние по A.4.").font(.caption)
            category(.overallCondition)
        }
        if input.strengthTest == .pointLoadIs50 {
            Text("Is(50) <1 МПа: требуется UCS. Пересчёт Is(50) в UCS не выполняется.").font(.caption)
        }
        switch Result(catching: { try input.basicEvaluation() }) {
        case .success(let result):
            if let value = result.value {
                Text("RMR89 (базовый): \(value)").font(.headline).accessibilityIdentifier("rmrBasicResult")
                Text("Класс массива: \(result.rockClass ?? "—")")
            } else { Text("Для расчёта: \(result.missing.joined(separator: ", "))").font(.caption) }
        case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
        }
        Text("RMR с поправкой на ориентацию: не рассчитан.").font(.caption)
        Picker("JCond76 · отдельно от RMR89", selection: Binding(get: { input.jcond76?.category }, set: { input.jcond76 = $0.map(JCond76Assessment.init) })) {
            Text("Не выбран").tag(nil as JCond76Category?)
            ForEach(JCond76Category.allCases, id: \.self) { category in Text("\(category.title) · \(category.rating)").tag(Optional(category)) }
        }.accessibilityIdentifier("rmrJCond76")
        DisclosureGroup("Измеренные значения и сведения об оценке") {
            if input.strengthTest != .fieldEstimate { RatingField("Прочность, МПа", text: $input.strengthMPa, id: "rmrStrength", focus: focus) }
            RatingField("Испытание: источник и применимость UCS / Is(50)", text: $input.strengthEvidence, id: "rmrStrengthEvidence", focus: focus)
            RatingField("RMR: RQD исходное, %", text: $input.rqd, id: "rmrRQD", focus: focus)
            RatingField("RMR: источник RQD", text: $input.rqdEvidence, id: "rmrRQDEvidence", focus: focus)
            RatingField("Расстояние между трещинами, м", text: $input.spacingMeters, id: "rmrSpacing", focus: focus)
            DisclosureGroup("Состояние трещин — исходные данные") {
                RatingField("Протяжённость, м", text: $input.persistenceMeters, id: "rmrPersistence", focus: focus)
                RatingField("Раскрытие, мм", text: $input.apertureMillimeters, id: "rmrAperture", focus: focus)
                RatingField("Шероховатость — описание", text: $input.roughness, id: "rmrRoughness", focus: focus)
                RatingField("Заполнитель — тип, мощность и свойства", text: $input.infill, id: "rmrInfill", focus: focus)
                RatingField("Выветрелость стенок — описание", text: $input.weathering, id: "rmrWeathering", focus: focus)
            }
            RatingField("Подземные воды — описание условий", text: $input.groundwater, id: "rmrWater", focus: focus)
            RatingField("Приток, л/мин на 10 м тоннеля", text: $input.inflowLitersPerMinutePer10m, id: "rmrInflow", focus: focus)
            RatingField("Давление воды / главное напряжение σ1", text: $input.waterPressureRatio, id: "rmrWaterRatio", focus: focus)
            Picker("Инженерное применение", selection: $input.application) {
                Text("Не указано").tag(nil as RMREngineeringApplication?)
                ForEach(RMREngineeringApplication.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            RatingField("Ориентация: простирание, падение, ось и направление проходки, вид севера", text: $input.orientationDescription, id: "rmrOrientation", focus: focus)
            RatingField("Источник оценки RMR", text: $input.source, id: "rmrSource", focus: focus)
            RatingField("Автор оценки RMR", text: $input.assessor, id: "rmrAssessor", focus: focus)
            RatingField("Причина отсутствия данных RMR", text: $input.missingReason, id: "rmrMissingReason", focus: focus)

        }
        DisclosureGroup("Методика RMR89") {
            Text(RMR89Assessment.reference)
            Text("R0–R6 — полевая оценка интервала прочности по таблице 6 регламента, без подстановки точного UCS. JCond76 — Bieniawski (1976), таблица 2 в Hoek, Carter & Diederichs (2013); в базовый RMR89 не добавляется.")
            Link("Источник JCond76 · таблица 2", destination: URL(string: "https://www.rocscience.com/assets/resources/learning/hoek/Quantification-of-the-GSI-Chart-2013.pdf")!)
            Text("Таблицы A, C, E. Предварительный базовый рейтинг: прочность + RQD + расстояние + состояние + вода. Категории выбираются явно; общая граница диапазонов требует выбора инженера. При заполнителе используется A.4 вместо суммы E. Для ровно 5 мм проверьте общее состояние по A.4.")
            Text("Оценка состояния относится к определяющей системе трещин. Шероховатость породы и свойства заполнителя не взаимозаменяемы. Поправки для тоннелей, оснований и склонов не применяются. Рекомендации по крепи и механической устойчивости не рассчитываются.")
        }.font(.caption)
    }
    private func category(_ parameter: RMR89Parameter) -> some View {
        Picker(parameter.title, selection: Binding(get: { input.basicSelections?[parameter.rawValue] ?? "" }, set: { value in
            var selections = input.basicSelections ?? [:]
            selections[parameter.rawValue] = value.isEmpty ? nil : value
            input.basicSelections = selections
        })) {
            Text("Выберите").tag("")
            ForEach(parameter.choices(test: input.strengthTest).filter { parameter != .overallCondition || $0.rating <= 10 }) { choice in
                Text("\(choice.title) · \(choice.rating) балл.").tag(choice.id)
            }
        }.accessibilityIdentifier("rmrCategory-" + parameter.rawValue)
    }

}
private struct RatingField: View {
    let title: String
    @Binding var text: String
    let id: String
    let focus: FocusState<Bool>.Binding
    var numeric = false
    init(_ title: String, text: Binding<String>, id: String, focus: FocusState<Bool>.Binding, numeric: Bool = false) {
        self.title = title; _text = text; self.id = id; self.focus = focus; self.numeric = numeric
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("Не указано", text: $text, axis: .vertical).focused(focus).accessibilityIdentifier(id).accessibilityLabel(title)
                .keyboardType(numeric ? .decimalPad : .default)
        }
    }
}
extension QParameter {
    var title: String {
        switch self {
        case .jn: return "Jn — число систем трещин"
        case .jr: return "Jr — шероховатость трещин"
        case .ja: return "Ja — изменение стенок и заполнитель"
        case .jw: return "Jw — влияние подземных вод"
        case .srf: return "SRF — влияние напряжений"
        }
    }
}
extension QContact {
    var title: String { switch self { case .wall: return "a — контакт стенок"; case .before10cm: return "b — контакт до 10 см сдвига"; case .noContact: return "c — нет контакта при сдвиге" } }
}
extension QLocation {
    var title: String { switch self { case .ordinary: return "Обычный участок · Jn ×1"; case .intersection: return "Пересечение выработок · Jn ×3"; case .portal: return "Портал · Jn ×2" } }
}
extension RQDSource {
    var title: String { switch self { case .coreMeasured: return "Измерено по керну"; case .fieldEstimate: return "Полевая оценка"; case .externalReport: return "Внешний отчёт / ручной ввод" } }
}
extension JrAdjustment {
    var title: String { switch self { case .none: return "Без поправки"; case .spacingOver3m: return "+1: среднее расстояние >3 м"; case .fewExposed: return "+1: мало обнажённых трещин (§3.4.3)" } }
}
extension SRFAdjustment {
    var title: String { switch self { case .none: return "Без поправки"; case .adjacentZone: return "Снижение 25–50%: зона A–E влияет, не пересекает"; case .shallowCrown: return "F: покрытие свода меньше пролёта · SRF = 5" } }
}
extension RMREngineeringApplication {
    var title: String { switch self { case .tunnelsAndMines: return "Тоннели и горные выработки"; case .foundations: return "Основания"; case .slopes: return "Откосы" } }
}
