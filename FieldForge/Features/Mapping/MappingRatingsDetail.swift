import SwiftUI

struct MappingRatingsDetail: View {
    let ratings: MappingRatings?
    var body: some View {
        Section("Рейтинги массива") {
            if let q = ratings?.bartonQ {
                DisclosureGroup("Barton Q · NGI 2025") {
                    Text(q.method).font(.caption).textSelection(.enabled)
                    Text(QMethod.reference).font(.caption)
                    Text("Оценено: \(MeasurementDateText.format(q.assessedAt, detailed: true)) · ревизия \(q.revision)").font(.caption)
                    value("Автор", q.input.assessor); value("Источник оценки", q.input.assessmentSource)
                    value("Исходное геологическое описание", q.input.geologicalDescription)
                    value("RQD исходное, %", q.input.rqd)
                    value("Источник RQD", q.input.rqdSource?.title ?? ""); value("RQD: описание / источник", q.input.rqdEvidence)
                    value("Положение для Jn", q.input.location?.title ?? "")
                    value("Контакт стенок", q.input.contact?.title ?? "")
                    ForEach(QParameter.allCases, id: \.self) { parameter in
                        let input = q.input[parameter]
                        value(parameter.title + " · исходное значение", input.value)
                        value("Способ ввода \(parameter.rawValue)", input.origin == .tableSelection ? "Выбрана табличная величина" : "Ручной ввод в пределах строки")
                        value("Строка \(parameter.rawValue)", QMethod.rows(parameter).first { $0.id == input.category }.map { "\($0.id) · \($0.description)" } ?? "")
                        value("\(parameter.rawValue): описание / источник", input.evidence)
                    }
                    value("Поправка Jr", q.input.jrAdjustment.title)
                    value("Среднее расстояние для Jr, м", q.input.relevantSpacingMeters)
                    value("Поправка SRF", q.input.srfAdjustment.title)
                    value("Снижение SRF, %", q.input.srfReductionPercent)
                    value("Обоснование поправок", q.input.correctionEvidence)
                    value("Причина отсутствия данных", q.input.missingReason)
                    QCalculationText(evaluation: q.evaluation)
                    if q.method == QMethod.fieldVersion && q.input.isFieldPreliminary {
                        Text("Предварительная полевая оценка · документация неполная").font(.caption)
                    }
                    Link("Методика NGI 2025", destination: URL(string: QMethod.url)!)
                }
            } else { Text("Barton Q: исходные данные не вводились. Недостаточно данных для расчёта.") }
            if let rmr = ratings?.rmr89 {
                DisclosureGroup("RMR89 · базовый рейтинг") {
                    Text(rmr.method).font(.caption)
                    Text(RMR89Assessment.reference).font(.caption)
                    Text("Оценено: \(MeasurementDateText.format(rmr.assessedAt, detailed: true)) · ревизия \(rmr.revision)").font(.caption)
                    if let calculation = rmr.calculation, let rating = calculation.value {
                        Text("RMR89 (базовый): \(rating)").font(.headline)
                        Text("Класс массива: \(calculation.rockClass ?? "—")")
                    } else { Text("Базовый RMR: не рассчитан.").accessibilityIdentifier("savedRMRUnavailable") }
                    ForEach(RMR89Parameter.allCases, id: \.self) { parameter in
                        if let selected = rmr.input.basicSelections?[parameter.rawValue],
                           let choice = parameter.choices(test: rmr.input.strengthTest).first(where: { $0.id == selected }) {
                            value(parameter.title, "\(choice.title) · \(choice.rating) балл.")
                        }
                    }
                    value("Испытание прочности", rmr.input.strengthTest?.title ?? "")
                    value("Прочность, МПа", rmr.input.strengthMPa); value("Источник испытания", rmr.input.strengthEvidence)
                    value("RQD исходное, %", rmr.input.rqd); value("Источник RQD", rmr.input.rqdEvidence)
                    value("Расстояние, м", rmr.input.spacingMeters); value("Протяжённость, м", rmr.input.persistenceMeters)
                    value("Раскрытие, мм", rmr.input.apertureMillimeters); value("Шероховатость", rmr.input.roughness)
                    value("Заполнитель", rmr.input.infill); value("Выветрелость", rmr.input.weathering)
                    value("Подземные воды", rmr.input.groundwater); value("Приток, л/мин на 10 м", rmr.input.inflowLitersPerMinutePer10m)
                    value("Давление воды / σ1", rmr.input.waterPressureRatio)
                    value("Инженерное применение", rmr.input.application?.title ?? ""); value("Ориентация", rmr.input.orientationDescription)
                    value("Источник оценки", rmr.input.source); value("Автор", rmr.input.assessor); value("Причина отсутствия данных", rmr.input.missingReason)
                    Text("RMR с поправкой на ориентацию: не рассчитан.")
                    Text("Отсутствуют: \(rmr.missing.joined(separator: ", "))").font(.caption)
                }
            } else { Text("RMR89: исходные данные не вводились.") }
        }
    }
    private func value(_ title: String, _ text: String) -> some View {
        LabeledContent(title, value: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Не указано" : text)
    }
}
