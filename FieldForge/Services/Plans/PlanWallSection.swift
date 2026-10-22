import Foundation

/// Historical section compatibility is retained only for validating saved two-wall evidence.
/// Geometry primitives: Ericson (2005), §§5.1.2 and 5.1.9; see docs/two-wall-elevation.md.
enum PlanWallSection {
    private static let epsilon = 1e-8 // Numerical XY coincidence only, in drawing units.
    private static let alignment = cos(Double.pi / 6) // At most 30° local divergence.
    private static func dot(_ a: PlanPoint, _ b: PlanPoint) -> Double { a.x * b.x + a.y * b.y }
    private static func minus(_ a: PlanPoint, _ b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x - b.x, y: a.y - b.y) }
    private static func scaled(_ a: PlanPoint, _ s: Double) -> PlanPoint { PlanPoint(x: a.x * s, y: a.y * s) }
    private static func length(_ a: PlanPoint) -> Double { hypot(a.x, a.y) }
    private static func tangent(_ s: DXFElevationSegment) -> PlanPoint {
        let v = minus(s.b.xy, s.a.xy); return scaled(v, 1 / length(v))
    }
    static func position(_ s: DXFElevationSegment, at point: PlanPoint) -> PlanPoint {
        let t = s.projection(point)!.t
        return PlanPoint(x: s.a.x + t * (s.b.x - s.a.x), y: s.a.y + t * (s.b.y - s.a.y))
    }
    static func elevation(_ z1: Double, _ z2: Double, _ d1: Double, _ d2: Double) -> Double {
        if d1 == 0 { return z1 }; if d2 == 0 { return z2 }
        return (z1 * d2 + z2 * d1) / (d1 + d2)
    }
    /// Independent wall identity, opposed projections and a transverse local section.
    static func compatible(_ a: DXFElevationSegment, _ b: DXFElevationSegment, at p: PlanPoint) -> Bool {
        guard a.wallID != b.wallID, let pa = a.projection(p), let pb = b.projection(p) else { return false }
        let ta = tangent(a), tb = tangent(b)
        guard abs(dot(ta, tb)) >= alignment else { return false }
        let qa = position(a, at: p), qb = position(b, at: p), cross = minus(qb, qa), width = length(cross)
        guard width > epsilon, abs(dot(cross, ta)) <= 0.5 * width,
              abs(dot(cross, tb)) <= 0.5 * width else { return false }
        // On-wall samples are legitimate, but two coincident/overlapping walls are not a width.
        if pa.distance <= epsilon || pb.distance <= epsilon { return true }
        return dot(minus(qa, p), minus(qb, p)) <= -alignment * pa.distance * pb.distance
    }
}
