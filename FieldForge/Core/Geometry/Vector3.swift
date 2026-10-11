import Foundation

struct Vector3: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let screenNormal = Vector3(x: 0, y: 0, z: 1)
    static let down = Vector3(x: 0, y: 0, z: -1)
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var length: Double { hypot(hypot(x, y), z) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
    func cross(_ other: Self) -> Self {
        Self(x: y * other.z - z * other.y, y: z * other.x - x * other.z,
             z: x * other.y - y * other.x)
    }
    func normalized() -> Self? {
        guard isFinite else { return nil }
        // Scale before taking the norm to avoid overflow/underflow.
        let scale = max(abs(x), abs(y), abs(z))
        guard scale > 0 else { return nil }
        let scaled = Self(x: x / scale, y: y / scale, z: z / scale)
        guard scaled.isFinite, scaled.length > 0 else { return nil }
        return scaled * (1 / scaled.length)
    }
    static func * (v: Self, scalar: Double) -> Self {
        Self(x: v.x * scalar, y: v.y * scalar, z: v.z * scalar)
    }
    static func - (a: Self, b: Self) -> Self {
        Self(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
}

/// Row-major direction cosine matrix: reference coordinates -> device coordinates.
struct RotationMatrix: Codable, Equatable, Sendable {
    var row1: Vector3
    var row2: Vector3
    var row3: Vector3

    static let identity = RotationMatrix(row1: .init(x: 1, y: 0, z: 0),
                                         row2: .init(x: 0, y: 1, z: 0),
                                         row3: .init(x: 0, y: 0, z: 1))
    var isRotation: Bool {
        let rows = [row1, row2, row3]
        return rows.allSatisfy { $0.isFinite && abs($0.length - 1) < 1e-5 }
            && abs(row1.dot(row2)) < 1e-5 && abs(row1.dot(row3)) < 1e-5
            && abs(row2.dot(row3)) < 1e-5
            && abs(row1.dot(row2.cross(row3)) - 1) < 1e-5
    }
    func referenceToDevice(_ v: Vector3) -> Vector3 {
        Vector3(x: row1.dot(v), y: row2.dot(v), z: row3.dot(v))
    }
    func deviceToReference(_ v: Vector3) -> Vector3 {
        // Inverse of an orthonormal rotation is its transpose.
        Vector3(x: row1.x * v.x + row2.x * v.y + row3.x * v.z,
                y: row1.y * v.x + row2.y * v.y + row3.y * v.z,
                z: row1.z * v.x + row2.z * v.y + row3.z * v.z)
    }
    var elements: [Double] {
        [row1.x, row1.y, row1.z, row2.x, row2.y, row2.z, row3.x, row3.y, row3.z]
    }
}

struct Quaternion: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double
    var isValid: Bool {
        [x, y, z, w].allSatisfy(\.isFinite) && abs(hypot(hypot(x, y), hypot(z, w)) - 1) < 1e-4
    }
}
