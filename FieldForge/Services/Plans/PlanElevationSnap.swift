import Foundation

/// Only straight WCS segments with explicit endpoint elevations enter this collection.
struct DXFElevationSegment: Codable, Equatable {
    let a: DXFVertex
    let b: DXFVertex
    let entityType: String
    let handle: String?
    /// Zero-based expanded entity record ordinal (including VERTEX/SEQEND); stable within hashed bytes.
    /// Legacy records without extractionVersion use the original ENTITIES ordinal.
    let entityOrdinal: Int
    let segmentIndex: Int
    var blockPath: [String]? = nil
    var extractionVersion: String? = nil

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
    var unitConfirmedAt: Date? = nil
    /// DXF has no supported vertical-datum declaration. Never borrow the horizon's datum.
    var verticalDatum = "unknown"
    let policy: PlanElevationSnapPolicy

    func validate(plan: MappingPlanReference) throws {
        guard method == Self.version, planID == plan.id, planRevision == plan.version,
              let file = plan.file, planSHA256 == file.sha256,
              metersPerDrawingUnit == PlanElevationSnap.metersPerUnit(plan), unitDeclaration == plan.elevationUnitDeclaration,
              unitConfirmedAt == plan.elevationUnitConfirmation?.confirmedAt,
              verticalDatum == "unknown", policy.valid,
              ["LINE", "POLYLINE", "LWPOLYLINE"].contains(segment.entityType),
              segment.entityOrdinal >= 0, segment.segmentIndex >= 0,
              segment.extractionVersion == nil || segment.extractionVersion == DXFDocument.elevationExtractionVersion,
              segment.blockPath == nil || (segment.blockPath?.isEmpty == false && segment.blockPath!.count <= 8),
              let p = segment.projection(selectedXY), parameter == p.t,
              distanceMeters == p.distance * metersPerDrawingUnit, distanceMeters <= policy.toleranceMeters,
              elevationMeters == p.z * metersPerDrawingUnit, elevationMeters.isFinite else { throw StorageError.invalidRecord }
    }
}

struct PlanElevationResolution: Equatable {
    let candidates: [PlanGeometryElevation]
    let requiresChoice: Bool
    var failureReason: String? = nil
    var nearestDistanceMeters: Double? = nil
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

    /// A later, explicit Z-only declaration does not relabel existing XY in drawing units.
    static func metersPerUnit(_ plan: MappingPlanReference) -> Double? {
        guard let file = plan.file else { return nil }
        guard let confirmation = plan.elevationUnitConfirmation else { return metersPerUnit(file) }
        guard file.units == .unknown, confirmation.confirmedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        switch (confirmation.units, file.insertionUnits) {
        case (.meters, nil), (.meters, 0), (.meters, 6): return 1
        case (.millimeters, nil), (.millimeters, 0), (.millimeters, 4): return 0.001
        default: return nil
        }
    }

    static func resolve(_ point: PlanPoint, document: DXFDocument, plan: MappingPlanReference,
                        policy: PlanElevationSnapPolicy = PlanElevationSnapPolicy()) -> PlanElevationResolution {
        func failure(_ reason: String, distance: Double? = nil) -> PlanElevationResolution {
            PlanElevationResolution(candidates: [], requiresChoice: false, failureReason: reason, nearestDistanceMeters: distance)
        }
        guard policy.valid else { return failure("Некорректный допуск поиска Z.") }
        guard let file = plan.file else { return failure("Нет сохранённого оригинала DXF.") }
        guard document.insertionUnits == file.insertionUnits else { return failure("$INSUNITS не совпадает с сохранёнными метаданными.") }
        guard let factor = metersPerUnit(plan) else {
            return failure(file.units == .unknown || file.unitDeclaration != "userConfirmedAtImport"
                ? "Единицы чертежа не подтверждены. Уточните единицы по исходному файлу."
                : "Подтверждённые единицы противоречат $INSUNITS или не поддерживаются.")
        }
        guard !document.elevationSegments.isEmpty else {
            return failure(document.elevationExclusions.keys.contains(where: { $0.contains("неподдерживаем") || $0.contains("OCS") || $0.contains("bulge") })
                ? "Нет допустимой высотной геометрии: есть неподдерживаемые объекты. См. исключения ниже."
                : "Нет сегментов с явными достоверными Z; 2D-геометрия и подписи отметок не задают высоту.")
        }
        let nearby = document.elevationSegments.compactMap { segment -> PlanGeometryElevation? in
            guard let p = segment.projection(point), p.distance * factor <= policy.toleranceMeters else { return nil }
            return PlanGeometryElevation(planID: plan.id, planRevision: plan.version, planSHA256: file.sha256,
                segment: segment, selectedXY: point, parameter: p.t, distanceMeters: p.distance * factor,
                elevationMeters: p.z * factor, metersPerDrawingUnit: factor, unitDeclaration: plan.elevationUnitDeclaration, unitConfirmedAt: plan.elevationUnitConfirmation?.confirmedAt, policy: policy)
        }.sorted {
            if $0.distanceMeters != $1.distanceMeters { return $0.distanceMeters < $1.distanceMeters }
            if $0.segment.entityOrdinal != $1.segment.entityOrdinal { return $0.segment.entityOrdinal < $1.segment.entityOrdinal }
            return $0.segment.segmentIndex < $1.segment.segmentIndex
        }
        guard let first = nearby.first else {
            let nearest = document.elevationSegments.compactMap { $0.projection(point).map { $0.distance * factor } }.min()
            return failure("Ближайший высотный сегмент дальше допуска \(EngineeringDisplay.number(policy.toleranceMeters)) м.", distance: nearest)
        }
        let similar = nearby.filter { $0.distanceMeters <= first.distanceMeters + policy.similarDistanceMeters }
        let z = similar.map(\.elevationMeters)
        let ambiguous = (z.max()! - z.min()!) > policy.distinctElevationMeters
        return PlanElevationResolution(candidates: ambiguous ? similar : [first], requiresChoice: ambiguous)
    }
}
