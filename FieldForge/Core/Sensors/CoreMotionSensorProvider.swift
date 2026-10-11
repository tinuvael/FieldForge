import CoreMotion
import Foundation

@MainActor final class CoreMotionSensorProvider: SensorProvider {
    var onEvent: ((SensorEvent) -> Void)?
    private let manager = CMMotionManager()
    private var generation: UUID?
    var information: String {
        "Device Motion: \(manager.isDeviceMotionAvailable ? "доступен" : "нет"); "
            + "акселерометр: \(manager.isAccelerometerAvailable ? "есть" : "нет"); "
            + "гироскоп: \(manager.isGyroAvailable ? "есть" : "нет"); "
            + "магнитометр: \(manager.isMagnetometerAvailable ? "есть" : "нет")."
    }

    func start() {
        guard generation == nil else { return }
        guard manager.isDeviceMotionAvailable else {
            onEvent?(.unavailable("Device Motion недоступен. Проверьте доступ к движению в настройках iOS."))
            return
        }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        let reference: ReferenceFrame
        if frames.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical; reference = .magneticNorthZVertical
        } else if frames.contains(.xArbitraryZVertical) {
            frame = .xArbitraryZVertical; reference = .arbitraryZVertical
        } else {
            onEvent?(.unavailable("Нет поддерживаемой вертикальной системы отсчёта."))
            return
        }
        let token = UUID()
        generation = token
        manager.deviceMotionUpdateInterval = 1 / 20
        manager.showsDeviceMovementDisplay = true
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, error in
            let event: SensorEvent
            if let error {
                event = .unavailable("Ошибка Core Motion: \(error.localizedDescription)")
            } else if let motion {
                event = .sample(Self.convert(motion, reference: reference))
            } else {
                event = .unavailable("Core Motion не передал данные.")
            }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.onEvent?(event)
            }
        }
    }

    func stop() { generation = nil; manager.stopDeviceMotionUpdates() }

    nonisolated private static func convert(_ motion: CMDeviceMotion, reference: ReferenceFrame) -> SensorSample {
        let r = motion.attitude.rotationMatrix, q = motion.attitude.quaternion
        let g = motion.gravity, a = motion.userAcceleration, w = motion.rotationRate, b = motion.magneticField
        let accuracy: MagneticAccuracy
        switch b.accuracy {
        case .high: accuracy = .high
        case .medium: accuracy = .medium
        case .low: accuracy = .low
        default: accuracy = .uncalibrated
        }
        return SensorSample(timestamp: Date().addingTimeInterval(motion.timestamp - ProcessInfo.processInfo.systemUptime),
                            uptime: motion.timestamp, source: .coreMotion, referenceFrame: reference,
                            rotation: .init(row1: .init(x: r.m11, y: r.m12, z: r.m13),
                                            row2: .init(x: r.m21, y: r.m22, z: r.m23),
                                            row3: .init(x: r.m31, y: r.m32, z: r.m33)),
                            quaternion: .init(x: q.x, y: q.y, z: q.z, w: q.w),
                            gravity: .init(x: g.x, y: g.y, z: g.z),
                            userAcceleration: .init(x: a.x, y: a.y, z: a.z),
                            rotationRate: .init(x: w.x, y: w.y, z: w.z),
                            magneticField: .init(x: b.field.x, y: b.field.y, z: b.field.z), magneticAccuracy: accuracy)
    }
}
