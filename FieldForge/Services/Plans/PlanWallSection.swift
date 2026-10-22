import Foundation

/// Versioned picking heuristics, not a surveyed topology or engineering accuracy claim.
/// Geometry primitives: Ericson (2005), §§5.1.2 and 5.1.9; see docs/two-wall-elevation.md.
enum PlanWallSection {
    private static let epsilon = 1e-8 // Numerical XY coincidence only, in drawing units.
    // Product review guard, not an engineering excavation-width limit or a candidate radius.
    static let maximumAutomaticWidthMeters = 50.0
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
    /// Any intervening wall blocks an automatic cross-section, including other Z levels.
    private static func intersects(_ a: PlanPoint, _ b: PlanPoint, _ s: DXFElevationSegment) -> Bool {
        func cross(_ u: PlanPoint, _ v: PlanPoint) -> Double { u.x * v.y - u.y * v.x }
        let r = minus(b, a), v = minus(s.b.xy, s.a.xy), delta = minus(s.a.xy, a)
        let denominator = cross(r, v)
        if abs(denominator) <= epsilon {
            guard abs(cross(delta, r)) <= epsilon * max(1, length(r)) else { return false }
            let rr = dot(r, r)
            guard rr > 0 else { return false }
            let t1 = dot(delta, r) / rr, t2 = dot(minus(s.b.xy, a), r) / rr
            return max(t1, t2) > epsilon && min(t1, t2) < 1 - epsilon
        }
        let t = cross(delta, v) / denominator, u = cross(delta, r) / denominator
        return t > epsilon && t < 1 - epsilon && u >= -epsilon && u <= 1 + epsilon
    }
    private static func proposal(_ a: DXFElevationSegment, _ b: DXFElevationSegment?, _ point: PlanPoint,
                                 _ plan: MappingPlanReference, _ factor: Double, _ policy: PlanElevationSnapPolicy) -> PlanGeometryElevation {
        let p = a.projection(point)!
        var result = PlanGeometryElevation(planID: plan.id, planRevision: plan.version, planSHA256: plan.file!.sha256,
            segment: a, selectedXY: point, parameter: p.t, distanceMeters: p.distance * factor,
            elevationMeters: b.map { let q = $0.projection(point)!; return elevation(p.z * factor, q.z * factor, p.distance * factor, q.distance * factor) } ?? p.z * factor,
            metersPerDrawingUnit: factor, unitDeclaration: plan.elevationUnitDeclaration,
            unitConfirmedAt: plan.elevationUnitConfirmation?.confirmedAt, policy: policy)
        if let b {
            let q = b.projection(point)!
            result.method = PlanGeometryElevation.twoWallVersion
            result.secondWall = PlanElevationWallSample(segment: b, parameter: q.t, distanceMeters: q.distance * factor, elevationMeters: q.z * factor)
        }
        return result
    }
    /// Optional naming evidence. Never required, and never used to choose an overlapping level.
    private static func hint(_ s: DXFElevationSegment) -> (String, String)? {
        let parts = (s.layer ?? "").uppercased().split(separator: "_").map(String.init)
        guard let i = parts.firstIndex(where: { ["LEFT", "RIGHT"].contains($0) }), i > 0 else { return nil }
        return (parts[..<i].joined(separator: "_"), parts[i])
    }
    private static func matchingHint(_ a: DXFElevationSegment, _ b: DXFElevationSegment) -> Bool? {
        guard let a = hint(a), let b = hint(b) else { return nil }
        return a.0 == b.0 && a.1 != b.1
    }
    /// Check continuation half a local width in both directions. Independent vertex spacing
    /// is handled by reprojecting on each complete source wall, never matching vertex indices.
    private static func supported(_ a: DXFElevationSegment, _ b: DXFElevationSegment, _ p: PlanPoint,
                                  _ index: PlanElevationIndex) -> Bool {
        let width = a.projection(p)!.distance + b.projection(p)!.distance
        var tb = tangent(b); let ta = tangent(a)
        if dot(ta, tb) < 0 { tb = scaled(tb, -1) }
        let sum = PlanPoint(x: ta.x + tb.x, y: ta.y + tb.y), direction = scaled(sum, 1 / length(sum))
        for sign in [-1.0, 1.0] {
            let offset = scaled(direction, sign * width / 2), probe = PlanPoint(x: p.x + offset.x, y: p.y + offset.y)
            guard let aa = index.nearest(probe, wallID: a.wallID), let bb = index.nearest(probe, wallID: b.wallID),
                  compatible(aa, bb, at: probe) else { return false }
            let w = aa.projection(probe)!.distance + bb.projection(probe)!.distance
            guard w >= width / 2, w <= width * 2 else { return false }
            let qa = position(aa, at: probe), qb = position(bb, at: probe)
            if blocked(qa, qb, a, b, index) { return false }
        }
        return true
    }
    private static func blocked(_ qa: PlanPoint, _ qb: PlanPoint, _ a: DXFElevationSegment,
                                _ b: DXFElevationSegment, _ index: PlanElevationIndex) -> Bool {
        index.anyCrossing(qa, qb, excluding: [a.wallID, b.wallID]) { intersects(qa, qb, $0) }
    }
    /// Explicit plan wall picks retain the original location. Confirmation permits overlap
    /// review but never bypasses local transverse/opposite-side geometry validation.
    static func confirmedPair(_ point: PlanPoint, walls: [String], document: DXFDocument,
                              plan: MappingPlanReference) -> PlanGeometryElevation? {
        guard walls.count == 2, let factor = PlanElevationSnap.metersPerUnit(plan),
              plan.file?.insertionUnits == document.insertionUnits,
              let a = document.elevationIndex.nearest(point, wallID: walls[0]),
              let b = document.elevationIndex.nearest(point, wallID: walls[1]),
              compatible(a, b, at: point) else { return nil }
        return proposal(a, b, point, plan, factor, PlanElevationSnapPolicy()).confirmed()
    }
    static func resolve(_ point: PlanPoint, document: DXFDocument, plan: MappingPlanReference,
                        factor: Double, policy: PlanElevationSnapPolicy) -> PlanElevationResolution {
        let index = document.elevationIndex
        var metrics = PlanElevationIndex.QueryMetrics()
        guard let firstID = index.nearest(point, metrics: &metrics) else {
            return PlanElevationResolution(candidates: [], requiresChoice: false, failureReason: "Нет сегментов с явными достоверными Z.")
        }
        let first = index.segments[firstID], nearestDistance = first.projection(point)!.distance * factor
        func walls(within radius: Double) -> [DXFElevationSegment] {
            var seen = Set<String>()
            return index.nearby(point, radius: radius).compactMap {
                let segment = index.segments[$0]
                return seen.insert(segment.wallID).inserted ? segment : nil
            }
        }
        // A wall hit needs no width interpolation. Preserve all distinct coincident levels.
        let onWall = walls(within: min(epsilon, policy.toleranceMeters / factor))
        if !onWall.isEmpty {
            let values = onWall.map { proposal($0, nil, point, plan, factor, policy) }
            let z = values.map(\.elevationMeters)
            let ambiguous = z.max()! - z.min()! > epsilon * factor
            return PlanElevationResolution(candidates: ambiguous ? values : [values[0]], requiresChoice: ambiguous,
                failureReason: ambiguous ? "Совпадающие в плане стены имеют разные Z. Выберите источник." : nil, nearestDistanceMeters: nearestDistance)
        }
        func uniquePosition(_ wall: DXFElevationSegment) -> Bool {
            let radius = wall.projection(point)!.distance + policy.similarDistanceMeters / factor
            return !index.nearby(point, radius: radius).contains {
                let s = index.segments[$0]
                return s.wallID == wall.wallID && abs(s.segmentIndex - wall.segmentIndex) > 1
            }
        }
        func sections(_ local: [DXFElevationSegment]) -> (pairs: [PlanGeometryElevation], automaticIDs: Set<Int>) {
            let distances = local.map { $0.projection(point)!.distance }
            var bins = Array(repeating: [Int](), count: 16), sectors: [Int] = []
            for i in local.indices {
                let q = position(local[i], at: point)
                let angle = atan2(q.y - point.y, q.x - point.x) + .pi
                let sector = min(15, Int(angle / (2 * .pi) * 16))
                sectors.append(sector); bins[sector].append(i)
            }
            var pairs: [PlanGeometryElevation] = [], automaticIDs = Set<Int>()
            var minimumWidth = Double.infinity
            for i in local.indices {
                guard distances[i] <= minimumWidth * 1.5 else { break }
                // Only opposite angular bins can satisfy the existing <=30° opposition
                // test. Extra boundary bins prevent false negatives at sector boundaries.
                for offset in 6...10 {
                    for j in bins[(sectors[i] + offset) % 16] where j > i {
                        if distances[i] + distances[j] > minimumWidth * 1.5 { break }
                        let a = local[i], b = local[j]
                        guard compatible(a, b, at: point) else { continue }
                        let qa = position(a, at: point), qb = position(b, at: point)
                        guard !blocked(qa, qb, a, b, index) else { continue }
                        let value = proposal(a, b, point, plan, factor, policy)
                        let width = distances[i] + distances[j]
                        minimumWidth = min(minimumWidth, width)
                        let extraRails = walls(within: 2 * width).contains { s in
                            s.wallID != a.wallID && s.wallID != b.wallID && abs(dot(tangent(s), tangent(a))) >= alignment
                        }
                        if width * factor <= maximumAutomaticWidthMeters && matchingHint(a, b) != false
                            && (!extraRails || matchingHint(a, b) == true) && uniquePosition(a) && uniquePosition(b)
                            && supported(a, b, point, index) {
                            automaticIDs.insert(pairs.count)
                        }
                        pairs.append(value)
                    }
                }
            }
            return (pairs, automaticIDs)
        }
        // Seed from the exact nearest segment, then expand geometrically. No drawing-wide
        // wall count or fixed distance cutoff participates in automatic acceptance.
        let extent = index.extent(from: point)
        var radius = min(extent, max(epsilon, 2 * first.projection(point)!.distance))
        var local = walls(within: radius), result = sections(local)
        while result.pairs.isEmpty && radius < extent {
            radius = min(extent, max(radius * 2, radius.nextUp))
            local = walls(within: radius); result = sections(local)
        }
        if let width = result.pairs.map({ $0.distanceMeters + $0.secondWall!.distanceMeters }).min() {
            // A competitor can only affect selection within 1.5 section widths;
            // parallel-rail ambiguity uses 2 widths. Query the larger complete halo.
            let completeRadius = 2 * width / factor
            if radius < completeRadius {
                local = walls(within: completeRadius); result = sections(local)
            }
        }
        let pairs = result.pairs, automaticIDs = result.automaticIDs
        if !pairs.isEmpty {
            // Any competing local section requires choice, even when its elevations agree.
            let minimumWidth = pairs.map { $0.distanceMeters + $0.secondWall!.distanceMeters }.min()!
            let competing = pairs.indices.filter { pairs[$0].distanceMeters + pairs[$0].secondWall!.distanceMeters <= minimumWidth * 1.5 }
            let auto = competing.count == 1 && automaticIDs.contains(competing[0])
            return PlanElevationResolution(candidates: competing.map { pairs[$0] }, requiresChoice: !auto,
                failureReason: auto ? nil : "Неоднозначное сечение: подтвердите две стены на плане. Z не определён автоматически.", nearestDistanceMeters: nearestDistance)
        }
        // Single-wall estimate is offered only when one source is genuinely isolated. A failed
        // pair/intersection must not silently degrade to the nearest of several unrelated walls.
        if local.count == 1, nearestDistance <= policy.toleranceMeters {
            return PlanElevationResolution(candidates: [proposal(first, nil, point, plan, factor, policy)], requiresChoice: false,
                failureReason: "Одна стена: приблизительная Z без поперечной интерполяции.", nearestDistanceMeters: nearestDistance)
        }
        let similar = local.filter { $0.projection(point)!.distance * factor <= nearestDistance + policy.similarDistanceMeters }
        if similar.count > 1, nearestDistance <= policy.toleranceMeters {
            return PlanElevationResolution(candidates: similar.map { proposal($0, nil, point, plan, factor, policy) }, requiresChoice: true,
                failureReason: "Пара стен не определена: возможны только отдельные одностенные оценки. Выберите источник явно.", nearestDistanceMeters: nearestDistance)
        }
        return PlanElevationResolution(candidates: [], requiresChoice: false,
            failureReason: "Надёжная пара стен не найдена. Выберите две стены на плане или введите Z вручную.", nearestDistanceMeters: nearestDistance)
    }
}
