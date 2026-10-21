import SwiftUI

struct MappingRatingsForm: View {
    @Binding var q: BartonQInput
    @Binding var rmr: RMR89Input
    let focus: FocusState<Bool>.Binding
    var body: some View {
        Section("Рейтинги массива") {
            DisclosureGroup("Barton Q") {
                BartonQForm(input: $q, focus: focus)
            }
            DisclosureGroup("RMR89 · исходные данные") {
                RMR89Form(input: $rmr, focus: focus)
            }
        }
    }
}
private struct BartonQForm: View {
    @Binding var input: BartonQInput
    let focus: FocusState<Bool>.Binding
    @State private var sourcesExpanded = false
    @State private var conditionsExpanded = false
    @State private var adjustmentsExpanded = false
    private var evaluation: Result<QEvaluation, Error> { Result { try input.evaluate() } }
    private var missing: [String] { (try? evaluation.get())?.missing ?? [] }
    private func needs(_ destination: QCaptureDestination) -> [String] {
        missing.filter { QCaptureDestination.destination(for: $0) == destination }
    }
    private func title(_ text: String, destination: QCaptureDestination) -> String {
        let count = needs(destination).count
        if count == 0, destination == .sources, case .failure = evaluation {
            return "\(text) · источники обязательны"
        }
        return count == 0 ? text : "\(text) · обязательно: \(count)"
    }
    var body: some View {
        coefficientInputs
        calculationStatus
        DisclosureGroup(isExpanded: $conditionsExpanded) {
            Picker("Участок · Jn", selection: $input.location) {
                Text("Выбрать участок").tag(nil as QLocation?)
                ForEach(QLocation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("qLocation")
            Picker("Контакт Jr / Ja", selection: $input.contact) {
                Text("Выбрать контакт").tag(nil as QContact?)
                ForEach(QContact.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("qContact")
        } label: { Text(title("Условия расчёта", destination: .conditions)) }
        DisclosureGroup(isExpanded: $adjustmentsExpanded) {
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
            if input.jrAdjustment != .none || input.srfAdjustment != .none || !input.correctionEvidence.isEmpty {
                RatingField("Обоснование поправок и геометрии", text: $input.correctionEvidence, id: "qCorrections", focus: focus)
            }
            Text("Jr +1 требует оценки сечения; без контакта не применяется. SRF: подтвердите геометрию, покрытие и влияние зоны по методике.").font(.caption)
        } label: { Text(title("Поправки Jr / SRF", destination: .adjustments)) }
        DisclosureGroup(isExpanded: $sourcesExpanded) {
            Picker("Источник RQD · нужен для расчёта", selection: $input.rqdSource) {
                Text("Не указан").tag(nil as RQDSource?)
                ForEach(RQDSource.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("qRQDSource")
            RatingField("RQD: замер, отчёт, описание", text: $input.rqdEvidence, id: "qRQDEvidence", focus: focus)
            RatingField("Источник оценки · нужен для расчёта", text: $input.assessmentSource, id: "qAssessmentSource", focus: focus)
            RatingField("Автор оценки Q", text: $input.assessor, id: "qAssessor", focus: focus)
            RatingField("Геологическое описание", text: $input.geologicalDescription, id: "qDescription", focus: focus)
            RatingField("Причина отсутствия данных", text: $input.missingReason, id: "qMissingReason", focus: focus)
        } label: { Text(title("Дополнительные параметры", destination: .sources)) }
        DisclosureGroup("Методика") {
            Text("NGI · апрель 2025").font(.subheadline)
            Text("Коэффициенты выбирает инженер; системы J1–J5 не назначают их автоматически. При RQD ≤10% используется 10%; исходное значение сохраняется.").font(.caption)
            Text("Jr и Ja — для наиболее неблагоприятной системы с учётом направления скольжения. Для Jr G штрихи должны совпадать с предполагаемым скольжением. Jw C–F — приближённые оценки; после дренажа или инъекции нужна переоценка. Обледенение не учтено.").font(.caption)
            Text("SRF учитывает напряжения, прочность и время после проходки. Отношения напряжений табл. 3-7 не вычисляются; выдавливание и набухание требуют инженерной оценки.").font(.caption)
            if let evaluation = try? input.evaluate() { QCalculationText(evaluation: evaluation) }
            Link("Методика NGI 2025", destination: URL(string: QMethod.url)!)
            Text("Рекомендации по крепи не рассчитываются.").font(.caption)
        }
    }
    private var coefficientInputs: some View {
        Group {
            RatingField("RQD, %", text: $input.rqd, id: "qRQD", focus: focus, numeric: true)
            ForEach(QParameter.allCases, id: \.self) { parameter in
                QCoefficientForm(parameter: parameter, input: Binding(get: { input[parameter] }, set: { input[parameter] = $0 }), focus: focus)
            }
        }
    }
    private var repairCoefficients: some View {
        Form { coefficientInputs }
            .navigationTitle("Параметры Q").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { focus.wrappedValue = false }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focus.wrappedValue = false } } }
    }
    @ViewBuilder private var calculationStatus: some View {
        switch evaluation {
        case .success(let value):
            if value.result != nil { QCalculationText(evaluation: value, compact: true) }
            else {
                Text("Q не рассчитан · заполните обязательные данные").font(.subheadline).accessibilityIdentifier("qMissingStatus")
                ForEach(QCaptureDestination.allCases, id: \.self) { destination in
                    let items = needs(destination)
                    if !items.isEmpty {
                        if destination == .numbers {
                            NavigationLink { repairCoefficients } label: { missingLabel(destination, items: items) }
                        } else {
                            Button { reveal(destination) } label: { missingLabel(destination, items: items) }
                        }
                    }
                }
            }
        case .failure(let error):
            Label("Q не рассчитан · исправьте ввод или условия", systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("qInvalidStatus")
            Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            NavigationLink("Проверить RQD и коэффициенты") { repairCoefficients }
            Button("Показать условия, поправки и источники") {
                focusedDismissal()
                conditionsExpanded = true; adjustmentsExpanded = true; sourcesExpanded = true
            }
        }
    }
    private func missingLabel(_ destination: QCaptureDestination, items: [String]) -> some View {
        Text("\(destination.title): \(items.joined(separator: ", ")) →")
            .font(.caption).multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading)
    }
    private func focusedDismissal() { focus.wrappedValue = false }
    private func reveal(_ destination: QCaptureDestination) {
        focusedDismissal()
        switch destination {
        case .conditions: conditionsExpanded = true
        case .sources: sourcesExpanded = true
        case .adjustments: adjustmentsExpanded = true
        case .numbers: break
        }
    }

}

/// Routes actual evaluator messages to controls; this never decides calculation validity.
private enum QCaptureDestination: CaseIterable, Hashable {
    case numbers, conditions, sources, adjustments
    var title: String {
        switch self {
        case .numbers: return "Числа и обоснования диапазонов"
        case .conditions: return "Условия классификации"
        case .sources: return "Обязательные источники"
        case .adjustments: return "Данные для поправок"
        }
    }
    static func destination(for missing: String) -> Self {
        if ["RQD", "Jn", "Jr", "Ja", "Jw", "SRF"].contains(missing) || missing.hasPrefix("Обоснование значения диапазона ") { return .numbers }
        if ["Положение выработки для Jn", "Контакт стенок для Jr/Ja"].contains(missing) { return .conditions }
        if ["Среднее расстояние для Jr +1", "Процент снижения SRF", "Обоснование поправок и геометрии выработки"].contains(missing) { return .adjustments }
        return .sources
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
                RatingField("Обоснование значения диапазона", text: $input.evidence, id: "qEvidence-\(parameter.rawValue)", focus: focus)
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
        if let evaluation = try? input.evaluate() {
            QCalculationText(evaluation: evaluation, compact: true)
        } else {
            Text("Недостаточно данных для расчёта").accessibilityIdentifier("qMissingStatus")
            if case .failure(let error) = Result(catching: { try input.evaluate() }) {
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
            Text(result.rockClass?.title ?? "Значение вне опубликованной шкалы классов 0,001…1000")
            if !compact {
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
        Text("Bieniawski · RMR89 (1989)").font(.subheadline)
        Text(RMR89Assessment.unavailable).accessibilityIdentifier("rmrUnavailable")
        Picker("Испытание прочности", selection: $input.strengthTest) {
            Text("Не указано").tag(nil as RMRStrengthTest?)
            ForEach(RMRStrengthTest.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
        RatingField("Прочность, МПа", text: $input.strengthMPa, id: "rmrStrength", focus: focus)
        RatingField("Испытание: источник и применимость UCS / Is(50)", text: $input.strengthEvidence, id: "rmrStrengthEvidence", focus: focus)
        Text("Is(50) сохраняется как результат точечного нагружения с приведением к 50 мм; преобразование в UCS и рейтинги не выполняется.").font(.caption)
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
        Text("Базовый RMR: не рассчитан. RMR с поправкой на ориентацию: не рассчитан.").font(.caption)
        Text("Отсутствуют: \(input.missing.joined(separator: ", "))").font(.caption)
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
extension RMRStrengthTest { var title: String { self == .ucs ? "UCS — одноосное сжатие" : "Is(50) — точечное нагружение" } }
extension RMREngineeringApplication {
    var title: String { switch self { case .tunnelsAndMines: return "Тоннели и горные выработки"; case .foundations: return "Основания"; case .slopes: return "Откосы" } }
}
