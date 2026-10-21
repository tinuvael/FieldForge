import Foundation

/// Presentation only. Never use for persisted inputs, calculations or export serialization.
enum EngineeringDisplay {
    static func number(_ value: Double, decimals: Int = 3) -> String {
        guard value.isFinite else { return "—" }
        // Keep small nonzero quantities visible instead of displaying a rounded zero.
        if value != 0 && abs(value) < pow(10, -Double(decimals)) {
            return significant(value)
        }
        let formatter = base()
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? "—"
    }

    static func orientationInput(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let formatter = base()
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    static func coordinate(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let formatter = base()
        formatter.minimumFractionDigits = 1; formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? "—"
    }

    static func significant(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let formatter = base()
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 4
        if value != 0 && (abs(value) < 0.000001 || abs(value) >= 1_000_000_000) {
            formatter.numberStyle = .scientific
        }
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func angle(_ value: Double?, azimuth: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let displayed = azimuth ? (PlaneGeometry.normalizeAzimuth((value * 10).rounded() / 10) ?? value) : value
        return orientationInput(displayed) + "°"
    }

    private static func base() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        return formatter
    }
}
