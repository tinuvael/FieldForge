import Foundation

enum MockCondition: String, CaseIterable, Identifiable {
    case normal, magneticUnavailable, moving, unavailable, invalid
    var id: String { rawValue }
}

@MainActor final class MockSensorProvider: SensorProvider {
    var onEvent: ((SensorEvent) -> Void)?
    let information = "Симулятор: синтетические данные, физических датчиков нет."
    private(set) var isRunning = false
    private var updates: Task<Void, Never>?
    var dip = 45.0
    var direction = 90.0
    var condition = MockCondition.normal

    func start() {
        guard !isRunning else { return }
        isRunning = true; emit()
        updates = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                self?.emit()
            }
        }
    }
    func stop() { isRunning = false; updates?.cancel(); updates = nil }
    func emit() {
        guard isRunning else { return }
        if condition == .unavailable { onEvent?(.unavailable("Демонстрация: датчики недоступны.")); return }
        var sample = Self.sample(dip: dip, direction: direction, timestamp: Date())
        switch condition {
        case .magneticUnavailable: sample.referenceFrame = .arbitraryZVertical
        case .moving: sample.userAcceleration = Vector3(x: 0.3, y: 0, z: 0)
        case .invalid: sample.rotation.row3.z = .nan
        default: break
        }
        onEvent?(.sample(sample))
    }

    static func sample(dip: Double, direction: Double, timestamp: Date) -> SensorSample {
        let d = dip * .pi / 180, a = direction * .pi / 180
        // Synthetic tilted screen. Rows form a right-handed orthonormal basis.
        let normal = Vector3(x: sin(d) * cos(a), y: -sin(d) * sin(a), z: cos(d))
        let row1 = Vector3(x: cos(d) * cos(a), y: -cos(d) * sin(a), z: -sin(d))
        let row2 = normal.cross(row1)
        let matrix = RotationMatrix(row1: row1, row2: row2, row3: normal)
        // Matrix corresponds to Ry(-d) Rz(a); its diagnostic quaternion follows that product.
        let q = Quaternion(x: -sin(d / 2) * sin(a / 2), y: -sin(d / 2) * cos(a / 2),
                           z: cos(d / 2) * sin(a / 2), w: cos(d / 2) * cos(a / 2))
        return SensorSample(timestamp: timestamp, uptime: 0, source: .simulatorMock,
                            referenceFrame: .simulatedNorthZVertical, rotation: matrix, quaternion: q,
                            gravity: matrix.referenceToDevice(.down),
                            userAcceleration: .init(x: 0, y: 0, z: 0), rotationRate: .init(x: 0, y: 0, z: 0),
                            magneticField: .init(x: 0, y: 0, z: 0), magneticAccuracy: .notApplicable)
    }
}
