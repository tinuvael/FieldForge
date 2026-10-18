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
            DisclosureGroup("RMR") {
                RMR89Form(input: $rmr, focus: focus)
            }
        }
    }
}
private struct BartonQForm: View {
    @Binding var input: BartonQInput
    let focus: FocusState<Bool>.Binding
    var body: some View {
        Text("NGI · апрель 2025").font(.subheadline)
        Text("Оценка текущей точки/интервала. Коэффициенты выбирает инженер; J1–J5 и описания не назначают их автоматически.")
            .font(.caption).foregroundStyle(.secondary)
        RatingField("RQD исходное, %", text: $input.rqd, id: "qRQD", focus: focus)
        Picker("Источник RQD", selection: $input.rqdSource) {
            Text("Не указан").tag(nil as RQDSource?)
            ForEach(RQDSource.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("qRQDSource")
        RatingField("RQD: замер, отчёт, описание", text: $input.rqdEvidence, id: "qRQDEvidence", focus: focus)
        Text("Для Q при RQD ≤10% используется 10%; исходное значение сохраняется. Точность ввода не означает точность оценки.")
            .font(.caption)
        Picker("Положение для Jn", selection: $input.location) {
            Text("Не указано").tag(nil as QLocation?)
            ForEach(QLocation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("qLocation")
        Picker("Контакт стенок Jr / Ja", selection: $input.contact) {
            Text("Не указан").tag(nil as QContact?)
            ForEach(QContact.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("qContact")
        Text("Jr и Ja относятся к наиболее неблагоприятной для сдвига системе в этой точке; её выбор и направление скольжения укажите в обосновании.")
            .font(.caption)
        ForEach(QParameter.allCases, id: \.self) { parameter in
            DisclosureGroup(parameter.title) {
                QCoefficientForm(parameter: parameter, input: Binding(get: { input[parameter] }, set: { input[parameter] = $0 }), focus: focus)
            }
        }
        DisclosureGroup("Особые условия и поправки") {
            Picker("Поправка Jr", selection: $input.jrAdjustment) {
                ForEach(JrAdjustment.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if input.jrAdjustment == .spacingOver3m {
                RatingField("Среднее расстояние, м (>3)", text: $input.relevantSpacingMeters, id: "qJrSpacing", focus: focus)
            }
            Text("Jr +1 требует оценки сечения выработки; поправка не применяется без контакта. Строка Jr G: штрихи должны совпадать с предполагаемым скольжением.").font(.caption)
            Picker("Поправка SRF", selection: $input.srfAdjustment) {
                ForEach(SRFAdjustment.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if input.srfAdjustment == .adjacentZone {
                RatingField("Снижение SRF, % (25…50)", text: $input.srfReductionPercent, id: "qSRFReduction", focus: focus)
            }
            RatingField("Обоснование поправок: геометрия, покрытие, зона", text: $input.correctionEvidence, id: "qCorrections", focus: focus)
            Text("SRF: учитывайте время после проходки, напряжения, прочность и характер деформаций. Отношения напряжений из табл. 3-7 здесь не вычисляются. Для выдавливания и набухания нужна отдельная инженерная оценка. Jw C–F — приближённые оценки; после дренажа/инъекции пересмотрите строку и сохраните обоснование. Обледенение в Jw не учтено.").font(.caption)
        }
        RatingField("Источник оценки Q / документ / условия", text: $input.assessmentSource, id: "qAssessmentSource", focus: focus)
        RatingField("Автор оценки Q", text: $input.assessor, id: "qAssessor", focus: focus)
        RatingField("Исходное геологическое описание Q", text: $input.geologicalDescription, id: "qDescription", focus: focus)
        RatingField("Причина отсутствия данных Q", text: $input.missingReason, id: "qMissingReason", focus: focus)
        QCalculationPreview(input: input)
        Link("Методика NGI 2025", destination: URL(string: QMethod.url)!)
        Text("Результат классифицирует массив; рекомендации по крепи не рассчитываются.").font(.caption)
    }
}
private struct QCoefficientForm: View {
    let parameter: QParameter
    @Binding var input: QCoefficientInput
    let focus: FocusState<Bool>.Binding
    var body: some View {
        Picker("Строка NGI \(parameter.rawValue)", selection: Binding(get: { input.category }, set: { input.select($0, parameter: parameter) })) {
            Text("Не выбрана").tag(nil as String?)
            ForEach(QMethod.rows(parameter)) { row in
                Text("\(row.id) · \(row.description) · \(row.rangeText)").tag(Optional(row.id))
            }
        }.pickerStyle(.navigationLink).accessibilityIdentifier("qCategory-\(parameter.rawValue)")
        if let row = QMethod.rows(parameter).first(where: { $0.id == input.category }) {
            Text("\(row.id) · \(row.description)").font(.caption)
            RatingField("\(parameter.rawValue): \(row.rangeText)", text: $input.value, id: "qValue-\(parameter.rawValue)", focus: focus)
            Text(row.minimum == row.maximum ? "Ручное значение должно совпадать с выбранной строкой." : "Введите оценку в пределах строки; поясните выбор значения диапазона.")
                .font(.caption).foregroundStyle(.secondary)
        }
        RatingField("\(parameter.rawValue): исходное описание / источник / обоснование", text: $input.evidence, id: "qEvidence-\(parameter.rawValue)", focus: focus)
    }
}
struct QCalculationPreview: View {
    let input: BartonQInput
    var body: some View {
        if let evaluation = try? input.evaluate() {
            QCalculationText(evaluation: evaluation)
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
    var body: some View {
        if let result = evaluation.result {
            Text("Q ≈ \(String(format: "%.6g", locale: Locale(identifier: "ru_RU"), result.value))").font(.headline).accessibilityIdentifier("qResult")
            Text(result.rockClass?.title ?? "Значение вне опубликованной шкалы классов 0,001…1000")
            Text("RQD исходное: \(CSVExporter.engineeringNumber(result.measuredRQD))%; в расчёте: \(CSVExporter.engineeringNumber(result.calculationRQD))%")
            Text("Q = (\(CSVExporter.engineeringNumber(result.calculationRQD)) / \(CSVExporter.engineeringNumber(result.jn))) × (\(CSVExporter.engineeringNumber(result.jr)) / \(CSVExporter.engineeringNumber(result.ja))) × (\(CSVExporter.engineeringNumber(result.jw)) / \(CSVExporter.engineeringNumber(result.srf)))")
                .font(.caption).textSelection(.enabled)
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
    init(_ title: String, text: Binding<String>, id: String, focus: FocusState<Bool>.Binding) {
        self.title = title; _text = text; self.id = id; self.focus = focus
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("Не указано", text: $text, axis: .vertical).focused(focus).accessibilityIdentifier(id).accessibilityLabel(title)
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
