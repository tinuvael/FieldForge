import Foundation

/// W1 geometry v1. Local right-handed frame: X right, Y along axis, Z up; metres.
/// References, derivations and renderer mapping: docs/w1-geometry.md.
enum WedgeInput {
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }
    static func azimuth(_ text: String) -> Double? {
        guard let value = number(text), (0...360).contains(value) else { return nil }
        return value == 360 ? 0 : value
    }
}

struct WedgeDimensions: Equatable {
    let width: Double
    let height: Double
    let length: Double
    var archHeight: Double { width / 3 }
    var wallHeight: Double { height - archHeight }
    var scale: Double { max(width, height, length) }

    init(width: Double, height: Double, length: Double) throws {
        guard [width, height, length].allSatisfy({ $0.isFinite && $0 > 0 }), height > width / 3 else {
            throw MappingError.invalid("Введите конечные B, H, L > 0; полная высота H должна быть больше B/3.")
        }
        // Explicit numerical representability guard for the Float renderer, not a field accuracy limit.
        let scale = max(width, height, length)
        guard scale < Double(Float.greatestFiniteMagnitude) / 100,
              min(width, height - width / 3, length) / scale > 1e-8 else {
            throw MappingError.invalid("Размеры или их соотношение выходят за численный диапазон 3D-модели.")
        }
        self.width = width; self.height = height; self.length = length
    }
}

struct WedgeArc {
    let center: Vector3
    let radius: Double
    let start: Double
    let end: Double
    func point(_ angle: Double) -> Vector3 {
        Vector3(x: center.x + radius * cos(angle), y: 0, z: center.z + radius * sin(angle))
    }
    func tangent(_ angle: Double) -> Vector3 { Vector3(x: -sin(angle), y: 0, z: cos(angle)) }
}

struct WedgeMesh {
    let vertices: [Vector3]
    let triangles: [Int32]
}

struct WedgeArch {
    let dimensions: WedgeDimensions
    let arcs: [WedgeArc] // right side -> central -> left side
    var centralRadius: Double { arcs[1].radius }
    var sideRadius: Double { arcs[0].radius }

    init(_ dimensions: WedgeDimensions) {
        self.dimensions = dimensions
        // Solve with dimensionless ratios to avoid squared-dimension overflow.
        let h = 1.0 / 3, a = 0.5, big = 0.692
        let small = (2 * big * h - h * h - a * a) / (2 * (big - a))
        let b = dimensions.width, wall = dimensions.wallHeight
        let theta = atan2(big - h, a - small)
        arcs = [
            WedgeArc(center: .init(x: (a - small) * b, y: 0, z: wall), radius: small * b, start: 0, end: theta),
            WedgeArc(center: .init(x: 0, y: 0, z: dimensions.height - big * b), radius: big * b,
                     start: theta, end: .pi - theta),
            WedgeArc(center: .init(x: -(a - small) * b, y: 0, z: wall), radius: small * b, start: .pi - theta, end: .pi)
        ]
    }
    var section: [Vector3] {
        let a = dimensions.width / 2
        var points = [Vector3(x: -a, y: 0, z: 0), Vector3(x: a, y: 0, z: 0),
                      Vector3(x: a, y: 0, z: dimensions.wallHeight)]
        for arc in arcs {
            for step in 1...32 { points.append(arc.point(arc.start + (arc.end - arc.start) * Double(step) / 32)) }
        }
        return points
    }
    func mesh() -> WedgeMesh {
        let front = section, count = front.count
        let rear = front.map { Vector3(x: $0.x, y: dimensions.length, z: $0.z) }
        let vertices = front + rear + [Vector3(x: 0, y: 0, z: dimensions.wallHeight / 2),
                                      Vector3(x: 0, y: dimensions.length, z: dimensions.wallHeight / 2)]
        var indices: [Int32] = []
        for i in 0..<count {
            let j = (i + 1) % count
            // Closed convex prism, outward normals; end caps are display boundaries only.
            indices += [i, count + j, j, i, count + i, count + j,
                        2 * count, i, j, 2 * count + 1, count + j, count + i].map(Int32.init)
        }
        return WedgeMesh(vertices: vertices, triangles: indices)
    }
}

enum WedgePlaneGeometry {
    /// Upward unit normal from clockwise dip-direction D, dip delta, axis azimuth A.
    /// Horizontal planes need no D; vertical planes require an explicit conventional side.
    static func normal(input: ManualOrientationInput, axis: Double) -> Vector3? {
        guard axis.isFinite, (0..<360).contains(axis), let validated = try? input.validated(),
              let dip = validated.orientation.dipAngle else { return nil }
        if dip == 0 { return .init(x: 0, y: 0, z: 1) }
        guard let direction = validated.orientation.dipDirection else { return nil }
        let d = dip * .pi / 180, angle = (direction - axis) * .pi / 180
        return Vector3(x: sin(d) * sin(angle), y: sin(d) * cos(angle), z: cos(d)).normalized()
    }
    /// Pairwise schematic planes share a display-only origin. Parallel pairs have no unique trace.
    static func intersection(_ a: Vector3, _ b: Vector3) -> Vector3? {
        let cross = a.cross(b)
        return cross.length > 1e-10 ? cross.normalized() : nil
    }
    /// Portrait phone top edge (+device Y) projected horizontally into the existing NWU frame.
    static func axisHeading(sample: SensorSample, now: Date) -> Double? {
        guard sample.source == .coreMotion, sample.hasFiniteDiagnostics, sample.hasNorthReference,
              (0...2).contains(now.timeIntervalSince(sample.timestamp)),
              sample.userAcceleration.length < 0.05, sample.rotationRate.length < 0.1 else { return nil }
        let forward = sample.rotation.deviceToReference(.init(x: 0, y: 1, z: 0))
        guard hypot(forward.x, forward.y) > 0.5 else { return nil }
        return PlaneGeometry.normalizeAzimuth(atan2(-forward.y, forward.x) * 180 / .pi)
    }
}
