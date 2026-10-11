import SwiftUI

extension MeasurementQuality {
    var title: String {
        switch self {
        case .experimental: return "Экспериментальное"
        case .manualUnverified: return "Ручной ввод · точность не проверена"
        case .inclinationOnly: return "Только угол падения"
        case .uncertain: return "Движение — удерживайте телефон"
        case .invalid: return "Недопустимые данные"
        }
    }
    var color: Color {
        switch self {
        case .experimental, .manualUnverified: return Color("AccentColor")
        case .inclinationOnly, .uncertain: return .orange
        case .invalid: return .red
        }
    }
}
extension CalculationStatus {
    var explanation: String {
        switch self {
        case .valid: return "Ориентация рассчитана. Точность ещё не подтверждена."
        case .horizontalAmbiguity: return "Плоскость близка к горизонтальной: направление падения не определено."
        case .verticalAmbiguity: return "Плоскость близка к вертикальной: горизонтальная проекция падения не определена."
        case .referenceUnavailable: return "Надёжной опоры на север нет. Доступен только угол падения."
        case .invalidInput: return "Ориентация или диагностические данные некорректны. Сохранение запрещено."
        }
    }
}
extension GeographicReference {
    var title: String {
        switch self {
        case .magneticNorth: return "Магнитный север"
        case .trueNorth: return "Истинный север"
        case .gridNorth: return "Сеточный север"
        case .unknown: return "Север не указан"
        case .simulatedNorth: return "Условный север · DEMO"
        case .unavailable: return "Север недоступен"
        }
    }
}
extension MeasurementSource {
    var title: String {
        switch self {
        case .iPhoneSensor: return "Датчики iPhone"
        case .manualCompass: return "Ручной ввод · геологический компас"
        case .externalInstrument: return "Внешний прибор"
        case .simulatorMock: return "Симулятор · DEMO"
        }
    }
}
extension Measurement {
    var explanation: String {
        if source != .manualCompass { return orientation.status.explanation }
        switch directionMeaning {
        case .conventionalDipSide: return "Вертикальная плоскость: азимут задаёт выбранную условную сторону падения."
        case .undefined: return "Направление падения не определено. Сохранён только угол."
        case .downhill: return "Ориентация введена вручную. Поправки между видами севера не применяются."
        }
    }
}
extension SensorSource {
    var title: String { self == .coreMotion ? "Датчики iPhone" : "Симулятор · DEMO" }
}
extension MagneticAccuracy {
    var title: String {
        switch self {
        case .high: return "Высокая"
        case .medium: return "Средняя"
        case .low: return "Низкая"
        case .uncalibrated: return "Не выполнена"
        case .notApplicable: return "Не применяется · DEMO"
        }
    }
}
enum MeasurementDateText {
    static func format(_ date: Date, detailed: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = .current
        formatter.dateFormat = detailed ? "d MMMM yyyy, HH:mm:ss" : "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
extension MockCondition {
    var title: String {
        switch self {
        case .normal: return "Обычное измерение"
        case .magneticUnavailable: return "Нет магнитной опоры"
        case .moving: return "Движение телефона"
        case .unavailable: return "Нет датчиков"
        case .invalid: return "Ошибка данных"
        }
    }
}
enum AngleText {
    static func format(_ value: Double?, azimuth: Bool = false) -> String {
        guard var value, value.isFinite else { return "—" }
        if azimuth { value = PlaneGeometry.normalizeAzimuth((value * 10).rounded() / 10) ?? value }
        return String(format: "%.1f°", locale: Locale(identifier: "ru_RU"), value)
    }
}
