import Foundation

/// Only straight WCS segments with explicit endpoint elevations enter this collection.
struct DXFElevationSegment: Codable, Equatable {
    let a: DXFVertex
    let b: DXFVertex
    let entityType: String
    let handle: String?
    /// Zero-based ENTITIES record ordinal (including VERTEX/SEQEND); stable within hashed bytes.
    let entityOrdinal: Int
    let segmentIndex: Int

    func projection(_ point: PlanPoint) -> (t: Double, distance: Double, z: Double)? {
        guard [a.x, a.y, a.z, b.x, b.y, b.z, point.x, point.y].allSatisfy(\.isFinite) else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y, lengthSquared = dx * dx + dy * dy
        // A vertical/zero-length XY segment has no unique elevation at its XY position.
        guard lengthSquared.isFinite, lengthSquared > 0 else { return nil }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return (t, hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy)), a.z + t * (b.z - a.z))
    }
}

/// Application picking policy, not survey accuracy or an engineering risk threshold.
struct PlanElevationSnapPolicy: Codable, Equatable {
    var toleranceMeters = 2.0
    var similarDistanceMeters = 0.1
    var distinctElevationMeters = 0.5
    var valid: Bool {
        [toleranceMeters, similarDistanceMeters, distinctElevationMeters].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct PlanGeometryElevation: Codable, Equatable {
    static let version = "DXF-WCS-XY-segment-projection/1"
    var method = Self.version
    let planID: UUID
    let planRevision: String
    let planSHA256: String
    let segment: DXFElevationSegment
    let selectedXY: PlanPoint
    let parameter: Double
    let distanceMeters: Double
    let elevationMeters: Double
    let metersPerDrawingUnit: Double
    let unitDeclaration: String
    /// DXF has no supported vertical-datum declaration. Never borrow the horizon's datum.
    var verticalDatum = "unknown"
    let policy: PlanElevationSnapPolicy

    func validate(plan: MappingPlanReference) throws {
        guard method == Self.version, planID == plan.id, planRevision == plan.version,
              let file = plan.file, planSHA256 == file.sha256,
              metersPerDrawingUnit == PlanElevationSnap.metersPerUnit(file), unitDeclaration == file.unitDeclaration,
              verticalDatum == "unknown", policy.valid,
              ["LINE", "POLYLINE", "LWPOLYLINE"].contains(segment.entityType),
              segment.entityOrdinal >= 0, segment.segmentIndex >= 0,
              let p = segment.projection(selectedXY), parameter == p.t,
              distanceMeters == p.distance * metersPerDrawingUnit, distanceMeters <= policy.toleranceMeters,
              elevationMeters == p.z * metersPerDrawingUnit, elevationMeters.isFinite else { throw StorageError.invalidRecord }
    }
}

struct PlanElevationResolution: Equatable {
    let candidates: [PlanGeometryElevation]
    let requiresChoice: Bool
    var automatic: PlanGeometryElevation? { requiresChoice ? nil : candidates.first }
}

enum PlanElevationSnap {
    /// Confirmed drawing units must agree with a declared INSUNITS value, if any.
    static func metersPerUnit(_ file: ManagedPlanFile) -> Double? {
        guard file.unitDeclaration == "userConfirmedAtImport" else { return nil }
        switch (file.units, file.insertionUnits) {
        case (.meters, nil), (.meters, 0), (.meters, 6): return 1
        case (.millimeters, nil), (.millimeters, 0), (.millimeters, 4): return 0.001
        default: return nil
        }
    }

    static func resolve(_ point: PlanPoint, document: DXFDocument, plan: MappingPlanReference,
                        policy: PlanElevationSnapPolicy = PlanElevationSnapPolicy()) -> PlanElevationResolution {
        guard policy.valid, let file = plan.file, document.insertionUnits == file.insertionUnits,
              let factor = metersPerUnit(file) else { return PlanElevationResolution(candidates: [], requiresChoice: false) }
        let nearby = document.elevationSegments.compactMap { segment -> PlanGeometryElevation? in
            guard let p = segment.projection(point), p.distance * factor <= policy.toleranceMeters else { return nil }
            return PlanGeometryElevation(planID: plan.id, planRevision: plan.version, planSHA256: file.sha256,
                segment: segment, selectedXY: point, parameter: p.t, distanceMeters: p.distance * factor,
                elevationMeters: p.z * factor, metersPerDrawingUnit: factor, unitDeclaration: file.unitDeclaration, policy: policy)
        }.sorted {
            if $0.distanceMeters != $1.distanceMeters { return $0.distanceMeters < $1.distanceMeters }
            if $0.segment.entityOrdinal != $1.segment.entityOrdinal { return $0.segment.entityOrdinal < $1.segment.entityOrdinal }
            return $0.segment.segmentIndex < $1.segment.segmentIndex
        }
        guard let first = nearby.first else { return PlanElevationResolution(candidates: [], requiresChoice: false) }
        let similar = nearby.filter { $0.distanceMeters <= first.distanceMeters + policy.similarDistanceMeters }
        let z = similar.map(\.elevationMeters)
        let ambiguous = (z.max()! - z.min()!) > policy.distinctElevationMeters
        return PlanElevationResolution(candidates: ambiguous ? similar : [first], requiresChoice: ambiguous)
    }
}
