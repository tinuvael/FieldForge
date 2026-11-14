import Foundation

/// North metadata never performs declination or grid convergence corrections.
enum GeographicReference: String, Codable, Sendable, CaseIterable {
    case magneticNorth, trueNorth, gridNorth, unknown
    // Retained for historical sensor records; simulated north is not physical north.
    case simulatedNorth, unavailable

    static let defaultMeasurementKey = "defaultMeasurementNorthReference"

    static func defaultForNewMeasurement(in preferences: UserDefaults = .standard) -> Self {
        guard let value = preferences.string(forKey: defaultMeasurementKey),
              let reference = Self(rawValue: value), manualChoices.contains(reference) else { return .unknown }
        return reference
    }

    static let manualChoices: [Self] = [.magneticNorth, .trueNorth, .gridNorth, .unknown]
}

enum MeasurementSource: String, Codable, Sendable {
    case iPhoneSensor, manualCompass, externalInstrument, simulatorMock
}

enum DipDirectionMeaning: String, Codable, Sendable {
    case downhill, undefined, conventionalDipSide
}
