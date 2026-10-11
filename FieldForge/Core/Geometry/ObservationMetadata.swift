import Foundation

/// North metadata never performs declination or grid convergence corrections.
enum GeographicReference: String, Codable, Sendable, CaseIterable {
    case magneticNorth, trueNorth, gridNorth, unknown
    // Retained for historical sensor records; simulated north is not physical north.
    case simulatedNorth, unavailable

    static let manualChoices: [Self] = [.magneticNorth, .trueNorth, .gridNorth, .unknown]
}

enum MeasurementSource: String, Codable, Sendable {
    case iPhoneSensor, manualCompass, externalInstrument, simulatorMock
}

enum DipDirectionMeaning: String, Codable, Sendable {
    case downhill, undefined, conventionalDipSide
}
