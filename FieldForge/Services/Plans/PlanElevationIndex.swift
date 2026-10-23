import Foundation

/// Immutable XY BVH, built with the loaded document and shared by document copies.
/// Whole segment bounds (not just vertices/centres) participate in every query.
final class PlanElevationIndex: Sendable {
    struct QueryMetrics {
        var visitedNodes = 0
        var projectedSegments = 0
    }
    private struct Box: Sendable {
        let minX: Double, minY: Double, maxX: Double, maxY: Double
        init(_ s: DXFElevationSegment) {
            minX = min(s.a.x, s.b.x); minY = min(s.a.y, s.b.y)
            maxX = max(s.a.x, s.b.x); maxY = max(s.a.y, s.b.y)
        }
        init(_ a: Box, _ b: Box) {
            minX = min(a.minX, b.minX); minY = min(a.minY, b.minY)
            maxX = max(a.maxX, b.maxX); maxY = max(a.maxY, b.maxY)
        }
        init(_ a: PlanPoint, _ b: PlanPoint, padding: Double) {
            minX = min(a.x, b.x) - padding; minY = min(a.y, b.y) - padding
            maxX = max(a.x, b.x) + padding; maxY = max(a.y, b.y) + padding
        }
        func distance(_ p: PlanPoint) -> Double {
            hypot(max(0, max(minX - p.x, p.x - maxX)), max(0, max(minY - p.y, p.y - maxY)))
        }
        func overlaps(_ b: Box) -> Bool {
            minX <= b.maxX && maxX >= b.minX && minY <= b.maxY && maxY >= b.minY
        }
        func farthestDistance(_ p: PlanPoint) -> Double {
            hypot(max(abs(p.x - minX), abs(p.x - maxX)), max(abs(p.y - minY), abs(p.y - maxY)))
        }
    }
    private struct Node: Sendable {
        let box: Box
        let start: Int, end: Int
        let left: Int, right: Int
        var leaf: Bool { left < 0 }
    }
    private struct Tree: Sendable {
        var order: [Int]
        var nodes: [Node] = []
        init(indices: [Int], boxes: [Box]) {
            order = indices
            guard !indices.isEmpty else { return }
            nodes.reserveCapacity(max(1, indices.count / 2))
            _ = build(0, order.count, boxes)
        }
        private mutating func build(_ start: Int, _ end: Int, _ boxes: [Box]) -> Int {
            var box = boxes[order[start]]
            for i in (start + 1)..<end { box = Box(box, boxes[order[i]]) }
            let node = nodes.count
            nodes.append(Node(box: box, start: start, end: end, left: -1, right: -1))
            if end - start > 8 {
                let x = box.maxX - box.minX >= box.maxY - box.minY
                // Total tie order makes the tree independent of Dictionary/hash iteration.
                order[start..<end].sort {
                    let a = boxes[$0], b = boxes[$1]
                    let ca = x ? a.minX / 2 + a.maxX / 2 : a.minY / 2 + a.maxY / 2
                    let cb = x ? b.minX / 2 + b.maxX / 2 : b.minY / 2 + b.maxY / 2
                    return ca == cb ? $0 < $1 : ca < cb
                }
                let middle = start + (end - start) / 2
                let left = build(start, middle, boxes), right = build(middle, end, boxes)
                nodes[node] = Node(box: box, start: start, end: end, left: left, right: right)
            }
            return node
        }
    }
    let segments: [DXFElevationSegment]
    private let tree: Tree
    private let wallSegments: [String: [Int]]
    private let wallTrees: [String: Tree]
    /// Diagnostics for stress tests; payload arrays only, excluding source geometry/string storage.
    var storageBytes: Int {
        func size(_ t: Tree) -> Int { t.nodes.capacity * MemoryLayout<Node>.stride + t.order.capacity * MemoryLayout<Int>.stride }
        return size(tree) + wallTrees.values.reduce(0) { $0 + size($1) }
            + wallSegments.values.reduce(0) { $0 + $1.capacity * MemoryLayout<Int>.stride }
    }
    var segmentCount: Int { tree.order.count }
    init(segments: [DXFElevationSegment]) {
        self.segments = segments
        let valid = segments.indices.filter {
            ["LINE", "POLYLINE", "LWPOLYLINE"].contains(segments[$0].entityType)
                && segments[$0].projection(segments[$0].a.xy) != nil
        }
        let boxes = segments.map(Box.init)
        tree = Tree(indices: valid, boxes: boxes)
        let groups = Dictionary(grouping: valid, by: { segments[$0].wallID })
        wallSegments = groups
        wallTrees = groups.filter { $0.value.count > 8 }.mapValues { Tree(indices: $0, boxes: boxes) }
    }
    func orderedBefore(_ a: Int, _ b: Int) -> Bool {
        let sa = segments[a], sb = segments[b]
        if sa.entityOrdinal != sb.entityOrdinal { return sa.entityOrdinal < sb.entityOrdinal }
        if sa.segmentIndex != sb.segmentIndex { return sa.segmentIndex < sb.segmentIndex }
        if sa.wallID != sb.wallID { return sa.wallID < sb.wallID }
        return a < b
    }
    private func nearest(_ p: PlanPoint, tree: Tree, metrics: inout QueryMetrics) -> Int? {
        guard !tree.nodes.isEmpty, p.x.isFinite, p.y.isFinite else { return nil }
        var best: Int?, distance = Double.infinity
        func visit(_ i: Int) {
            let node = tree.nodes[i]; metrics.visitedNodes += 1
            guard node.box.distance(p) <= distance else { return }
            if node.leaf {
                for n in node.start..<node.end {
                    let id = tree.order[n]; metrics.projectedSegments += 1
                    guard let d = segments[id].projection(p)?.distance else { continue }
                    if d < distance || (d == distance && (best == nil || orderedBefore(id, best!))) { best = id; distance = d }
                }
            } else {
                let a = tree.nodes[node.left].box.distance(p), b = tree.nodes[node.right].box.distance(p)
                if a <= b { visit(node.left); visit(node.right) } else { visit(node.right); visit(node.left) }
            }
        }
        visit(0); return best
    }
    func nearest(_ p: PlanPoint, metrics: inout QueryMetrics) -> Int? { nearest(p, tree: tree, metrics: &metrics) }
    func nearest(_ p: PlanPoint, wallID: String) -> DXFElevationSegment? {
        guard p.x.isFinite, p.y.isFinite else { return nil }
        var metrics = QueryMetrics()
        if let tree = wallTrees[wallID] { return nearest(p, tree: tree, metrics: &metrics).map { segments[$0] } }
        return wallSegments[wallID]?.min {
            let a = segments[$0].projection(p)!.distance, b = segments[$1].projection(p)!.distance
            return a == b ? orderedBefore($0, $1) : a < b
        }.map { segments[$0] }
    }
    /// Exact disk query: BVH box rejection followed by segment distance, with stable ties.
    func nearby(_ p: PlanPoint, radius: Double, metrics: inout QueryMetrics) -> [Int] {
        guard !tree.nodes.isEmpty, p.x.isFinite, p.y.isFinite, radius >= 0 else { return [] }
        var hits: [(Int, Double)] = [], stack = [0]
        while let i = stack.popLast() {
            let node = tree.nodes[i]; metrics.visitedNodes += 1
            guard node.box.distance(p) <= radius else { continue }
            if node.leaf {
                for n in node.start..<node.end {
                    let id = tree.order[n]; metrics.projectedSegments += 1
                    if let d = segments[id].projection(p)?.distance, d <= radius { hits.append((id, d)) }
                }
            } else { stack.append(node.right); stack.append(node.left) }
        }
        hits.sort { $0.1 == $1.1 ? orderedBefore($0.0, $1.0) : $0.1 < $1.1 }
        return hits.map(\.0)
    }
    func nearby(_ p: PlanPoint, radius: Double) -> [Int] {
        var metrics = QueryMetrics(); return nearby(p, radius: radius, metrics: &metrics)
    }
    /// BVH broad phase for a transverse chord; predicate retains the existing exact test.
    func anyCrossing(_ a: PlanPoint, _ b: PlanPoint, excluding: Set<String>,
                     predicate: (DXFElevationSegment) -> Bool) -> Bool {
        guard !tree.nodes.isEmpty else { return false }
        let box = Box(a, b, padding: 1e-8), stackRoot = 0
        var stack = [stackRoot]
        while let i = stack.popLast() {
            let node = tree.nodes[i]
            guard node.box.overlaps(box) else { continue }
            if node.leaf {
                for n in node.start..<node.end {
                    let segment = segments[tree.order[n]]
                    if !excluding.contains(segment.wallID), predicate(segment) { return true }
                }
            } else { stack.append(node.right); stack.append(node.left) }
        }
        return false
    }
    func extent(from point: PlanPoint) -> Double { tree.nodes.first?.box.farthestDistance(point) ?? 0 }
    func segments(on wallID: String) -> [DXFElevationSegment] { (wallSegments[wallID] ?? []).map { segments[$0] } }
}
