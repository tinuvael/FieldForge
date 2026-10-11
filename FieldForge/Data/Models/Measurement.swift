import Foundation

enum MeasurementQuality: String, Codable, Sendable {
    case experimental, inclinationOnly, uncertain, invalid
}

struct Measurement: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var orientation: PlaneOrientation
    var reference: GeographicReference
    var quality: MeasurementQuality
    var sample: SensorSample
    var notes: String
    var plane = "iPhoneScreen"
    var algorithmVersion = "screen-plane-nwu-v1"

    static func process(_ sample: SensorSample, id: UUID = UUID()) -> Measurement {
        let orientation = sample.hasFiniteDiagnostics
            ? PlaneGeometry.calculate(rotation: sample.rotation, hasNorthReference: sample.hasNorthReference)
            : .invalid
        let moving = sample.userAcceleration.length > 0.05 || sample.rotationRate.length > 0.1
        let quality: MeasurementQuality = orientation.status == .invalidInput ? .invalid
            : moving ? .uncertain : orientation.dipDirection == nil ? .inclinationOnly : .experimental
        return Measurement(id: id, timestamp: sample.timestamp, orientation: orientation,
                           reference: sample.geographicReference, quality: quality, sample: sample, notes: "")
    }

    var isSavable: Bool {
        guard sample.hasFiniteDiagnostics, timestamp == sample.timestamp,
              quality != .invalid, quality != .uncertain, reference == sample.geographicReference,
              let dip = orientation.dipAngle, dip.isFinite, (0...90).contains(dip) else { return false }
        let expected = Self.process(sample, id: id)
        return orientation == expected.orientation && quality == expected.quality
            && plane == expected.plane && algorithmVersion == expected.algorithmVersion
    }
}
