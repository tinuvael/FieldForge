import Foundation

enum SensorSource: String, Codable, Sendable { case coreMotion, simulatorMock }
enum ReferenceFrame: String, Codable, Sendable {
    case magneticNorthZVertical, arbitraryZVertical, simulatedNorthZVertical
}
enum GeographicReference: String, Codable, Sendable { case magneticNorth, simulatedNorth, unavailable }
enum MagneticAccuracy: String, Codable, Sendable { case uncalibrated, low, medium, high, notApplicable }

struct SensorSample: Codable, Equatable, Sendable {
    var timestamp: Date
    var uptime: Double
    var source: SensorSource
    var referenceFrame: ReferenceFrame
    var rotation: RotationMatrix
    var quaternion: Quaternion
    var gravity: Vector3
    var userAcceleration: Vector3
    var rotationRate: Vector3
    var magneticField: Vector3
    var magneticAccuracy: MagneticAccuracy

    var hasFiniteDiagnostics: Bool {
        timestamp.timeIntervalSince1970.isFinite && uptime.isFinite && uptime >= 0
            && rotation.isRotation && quaternion.isValid && gravity.isFinite
            && userAcceleration.isFinite && rotationRate.isFinite && magneticField.isFinite
            && abs(gravity.length - 1) < 0.1
            && (rotation.deviceToReference(gravity) - .down).length < 0.05
    }
    var hasNorthReference: Bool {
        if source == .simulatorMock { return referenceFrame == .simulatedNorthZVertical }
        // Calibration alone cannot certify absence of magnetic interference.
        return referenceFrame == .magneticNorthZVertical && magneticAccuracy == .high
            && (10...100).contains(magneticField.length)
    }
    var geographicReference: GeographicReference {
        guard hasNorthReference else { return .unavailable }
        return source == .simulatorMock ? .simulatedNorth : .magneticNorth
    }
}

enum SensorEvent: Sendable {
    case sample(SensorSample)
    case unavailable(String)
}

@MainActor protocol SensorProvider: AnyObject {
    var onEvent: ((SensorEvent) -> Void)? { get set }
    var information: String { get }
    func start()
    func stop()
}
