import Foundation

enum CalculationStatus: String, Codable, Sendable {
    case valid, horizontalAmbiguity, verticalAmbiguity, referenceUnavailable, invalidInput
}

struct PlaneOrientation: Codable, Equatable, Sendable {
    var dipAngle: Double?
    var dipDirection: Double?
    var status: CalculationStatus
    var normal: Vector3?

    static let invalid = PlaneOrientation(dipAngle: nil, dipDirection: nil,
                                          status: .invalidInput, normal: nil)
}

enum PlaneGeometry {
    /// Prototype singularity guard, not a claim of sensor accuracy.
    static let ambiguityToleranceDegrees = 0.5

    /// Reference: +X north, +Y west, +Z up (right-handed NWU).
    static func calculate(normal: Vector3, hasNorthReference: Bool) -> PlaneOrientation {
        guard let n = normal.normalized() else { return .invalid }
        let dip = atan2(hypot(n.x, n.y), abs(n.z)) * 180 / .pi
        var result = PlaneOrientation(dipAngle: dip, dipDirection: nil, status: .valid, normal: n)
        if dip <= ambiguityToleranceDegrees {
            result.status = .horizontalAmbiguity
        } else if 90 - dip <= ambiguityToleranceDegrees {
            result.status = .verticalAmbiguity
        } else if !hasNorthReference {
            result.status = .referenceUnavailable
        } else {
            // Project down onto the plane. This is invariant under n -> -n.
            let downhill = Vector3.down - n * Vector3.down.dot(n)
            result.dipDirection = normalizeAzimuth(atan2(-downhill.y, downhill.x) * 180 / .pi)
        }
        return result
    }

    static func calculate(rotation: RotationMatrix, hasNorthReference: Bool) -> PlaneOrientation {
        guard rotation.isRotation else { return .invalid }
        return calculate(normal: rotation.deviceToReference(.screenNormal),
                         hasNorthReference: hasNorthReference)
    }

    static func normalizeAzimuth(_ degrees: Double) -> Double? {
        guard degrees.isFinite else { return nil }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : (remainder == 0 ? 0 : remainder)
    }
}
