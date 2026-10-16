import Foundation

enum MeasurementQuality: String, Codable, Sendable {
    case experimental, inclinationOnly, uncertain, invalid, manualUnverified
}

struct Measurement: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var orientation: PlaneOrientation
    var reference: GeographicReference
    var quality: MeasurementQuality
    var sample: SensorSample?
    var notes: String
    var plane = "iPhoneScreen"
    var algorithmVersion = "screen-plane-nwu-v1"
    var source: MeasurementSource
    var directionMeaning: DipDirectionMeaning
    var manualInput: ManualOrientationInput?

    static func process(_ sample: SensorSample, id: UUID = UUID()) -> Measurement {
        let orientation = sample.hasFiniteDiagnostics
            ? PlaneGeometry.calculate(rotation: sample.rotation, hasNorthReference: sample.hasNorthReference)
            : .invalid
        let moving = sample.userAcceleration.length > 0.05 || sample.rotationRate.length > 0.1
        let quality: MeasurementQuality = orientation.status == .invalidInput ? .invalid
            : moving ? .uncertain : orientation.dipDirection == nil ? .inclinationOnly : .experimental
        return Measurement(id: id, timestamp: sample.timestamp, orientation: orientation,
                           reference: sample.geographicReference, quality: quality, sample: sample, notes: "",
                           source: sample.source == .coreMotion ? .iPhoneSensor : .simulatorMock,
                           directionMeaning: orientation.dipDirection == nil ? .undefined : .downhill)
    }

    var isSavable: Bool {
        guard timestamp.timeIntervalSince1970.isFinite else { return false }
        if source == .manualCompass {
            guard sample == nil, let manualInput, manualInput.reference == reference,
                  let result = try? manualInput.validated() else { return false }
            return orientation == result.orientation && directionMeaning == result.meaning
                && quality == .manualUnverified && plane == "geologicalPlane" && algorithmVersion == "manual-entry-v1"
        }
        // External instrument integration is deliberately not implemented.
        guard source == .iPhoneSensor || source == .simulatorMock, let sample,
              source == (sample.source == .coreMotion ? .iPhoneSensor : .simulatorMock),
              manualInput == nil, sample.hasFiniteDiagnostics, timestamp == sample.timestamp,
              quality != .invalid, quality != .uncertain, reference == sample.geographicReference,
              let dip = orientation.dipAngle, dip.isFinite, (0...90).contains(dip) else { return false }
        let expected = Self.process(sample, id: id)
        return Self.matchesPersistedSensorOrientation(orientation, expected.orientation) && quality == expected.quality
            && directionMeaning == expected.directionMeaning
            && plane == expected.plane && algorithmVersion == expected.algorithmVersion
    }
    /// Recomputing legacy diagnostics on another libm/CPU can differ by a few ULPs.
    /// Validate numerical consistency without rewriting original evidence or rounding it.
    private static func matchesPersistedSensorOrientation(_ stored: PlaneOrientation, _ expected: PlaneOrientation) -> Bool {
        func close(_ a: Double?, _ b: Double?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a.isFinite && b.isFinite && abs(a - b) <= 32 * max(1, abs(a), abs(b)).ulp
        }
        guard stored.status == expected.status, close(stored.dipAngle, expected.dipAngle),
              close(stored.dipDirection, expected.dipDirection) else { return false }
        switch (stored.normal, expected.normal) {
        case (nil, nil): return true
        case let (a?, b?): return close(a.x, b.x) && close(a.y, b.y) && close(a.z, b.z)
        default: return false
        }
    }
}
