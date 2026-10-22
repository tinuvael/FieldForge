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
    var layer: String? = nil

    var wallID: String { "\(entityOrdinal):" + (blockPath ?? []).joined(separator: "/") }

    func projection(_ point: PlanPoint) -> (t: Double, distance: Double, z: Double)? {
        guard [a.x, a.y, a.z, b.x, b.y, b.z, point.x, point.y].allSatisfy(\.isFinite) else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y, lengthSquared = dx * dx + dy * dy
        // A vertical/zero-length XY segment has no unique elevation at its XY position.
        guard lengthSquared.isFinite, lengthSquared > 0 else { return nil }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let distance = hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
        let z = a.z + t * (b.z - a.z)
        guard t.isFinite, distance.isFinite, z.isFinite else { return nil }
        return (t, distance, z)
    }
}

/// Application picking policy, not survey accuracy or an engineering risk threshold.
struct PlanElevationSnapPolicy: Codable, Equatable {
    var toleranceMeters = 2.0
    var similarDistanceMeters = 0.1
    var distinctElevationMeters = 0.5
    // Optional fields keep historical schema-8 policy JSON decodable without a migration.
    // toleranceMeters remains the historical single-source limit, not the new search radius.
    var searchRadiusMeters: Double? = nil
    var maximumElevationDifferenceMeters: Double? = nil
    var radius: Double { searchRadiusMeters ?? 25 }
    var levelDifference: Double { maximumElevationDifferenceMeters ?? 25 }
    var valid: Bool {
        [toleranceMeters, similarDistanceMeters, distinctElevationMeters, radius, levelDifference]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct PlanGeometryElevation: Codable, Equatable {
    static let version = "DXF-WCS-XY-segment-projection/1"
    static let twoWallVersion = "DXF-WCS-two-wall-section/1"
    static let nearestVersion = "DXF-WCS-nearest-distinct-polyline-IDW/1"
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

    /// Optional additions preserve schema-8 evidence written by the previous single-segment method.
    var secondWall: PlanElevationWallSample? = nil
    var confirmedByUser: Bool? = nil
    var isTwoWall: Bool { method == Self.twoWallVersion }
    var sourceLabel: String {
        if method == Self.nearestVersion { return "DXF · расчётная отметка" }
        if isTwoWall { return confirmedByUser == true ? "DXF · 2 стены ≈" : "DXF · 2 стены" }
        return "DXF · 1 стена ≈"
    }
    var firstWallElevationMeters: Double { segment.projection(selectedXY)!.z * metersPerDrawingUnit }
    var sourceDetails: String {
        func wall(_ segment: DXFElevationSegment, _ z: Double, _ d: Double) -> String {
            "\(segment.layer ?? "DXF") · #\(segment.handle ?? String(segment.entityOrdinal)): Z \(EngineeringDisplay.number(z, decimals: 3)) м; d \(EngineeringDisplay.number(d, decimals: 3)) м"
        }
        var text = wall(segment, firstWallElevationMeters, distanceMeters)
        if let secondWall { text += "\n" + wall(secondWall.segment, secondWall.elevationMeters, secondWall.distanceMeters) }
        if method == Self.nearestVersion {
            text += secondWall == nil ? "\nПриблизительно по одному сегменту." : "\nПриблизительно по двум ближайшим полилиниям."
        }
        return text + "\n" + (confirmedByUser == true ? "Источники подтверждены пользователем; оценка требует проверки. " : "") + "Высотная система неизвестна."
    }
    func confirmed() -> Self { var copy = self; copy.confirmedByUser = true; return copy }

    func validate(plan: MappingPlanReference) throws {
        guard [Self.version, Self.twoWallVersion, Self.nearestVersion].contains(method), planID == plan.id, planRevision == plan.version,
              let file = plan.file, planSHA256 == file.sha256,
              metersPerDrawingUnit == PlanElevationSnap.metersPerUnit(plan), unitDeclaration == plan.elevationUnitDeclaration,
              unitConfirmedAt == plan.elevationUnitConfirmation?.confirmedAt,
              verticalDatum == "unknown", policy.valid,
              ["LINE", "POLYLINE", "LWPOLYLINE"].contains(segment.entityType),
              segment.entityOrdinal >= 0, segment.segmentIndex >= 0,
              segment.extractionVersion == nil || segment.extractionVersion == DXFDocument.elevationExtractionVersion,
              segment.blockPath == nil || (segment.blockPath?.isEmpty == false && segment.blockPath!.count <= 8),
              let p = segment.projection(selectedXY), parameter == p.t,
              distanceMeters == p.distance * metersPerDrawingUnit,
              elevationMeters.isFinite else { throw StorageError.invalidRecord }
        if method == Self.nearestVersion {
            guard distanceMeters <= policy.radius else { throw StorageError.invalidRecord }
            if let secondWall {
                guard secondWall.valid(at: selectedXY, factor: metersPerDrawingUnit),
                      secondWall.segment.wallID != segment.wallID,
                      secondWall.distanceMeters <= policy.radius,
                      distanceMeters <= secondWall.distanceMeters,
                      abs(p.z * metersPerDrawingUnit - secondWall.elevationMeters) <= policy.levelDifference,
                      elevationMeters == PlanWallSection.elevation(p.z * metersPerDrawingUnit, secondWall.elevationMeters,
                          distanceMeters, secondWall.distanceMeters) else { throw StorageError.invalidRecord }
            } else {
                guard elevationMeters == p.z * metersPerDrawingUnit else { throw StorageError.invalidRecord }
            }
        } else if isTwoWall {
            guard let secondWall, secondWall.valid(at: selectedXY, factor: metersPerDrawingUnit),
                  PlanWallSection.compatible(segment, secondWall.segment, at: selectedXY),
                  elevationMeters == PlanWallSection.elevation(p.z * metersPerDrawingUnit, secondWall.elevationMeters,
                      distanceMeters, secondWall.distanceMeters) else { throw StorageError.invalidRecord }
        } else {
            guard secondWall == nil, distanceMeters <= policy.toleranceMeters,
                  elevationMeters == p.z * metersPerDrawingUnit else { throw StorageError.invalidRecord }
        }
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
    /// Supported declarations are automatic; other headers require an explicit unit choice.
    static func metersPerUnit(_ file: ManagedPlanFile) -> Double? {
        guard file.unitDeclaration == "userConfirmedAtImport" ||
                (file.unitDeclaration == "dxfINSUNITS" && PlanUnits.declared(by: file.insertionUnits) == file.units) else { return nil }
        return unitFactor(file.units, insertionUnits: file.insertionUnits)
    }

    private static func unitFactor(_ units: PlanUnits, insertionUnits: Int?) -> Double? {
        if let declared = PlanUnits.declared(by: insertionUnits), declared != units { return nil }
        switch units { case .meters: return 1; case .millimeters: return 0.001; case .unknown: return nil }
    }

    /// A later, explicit Z-only declaration does not relabel existing XY in drawing units.
    static func metersPerUnit(_ plan: MappingPlanReference) -> Double? {
        guard let file = plan.file else { return nil }
        guard let confirmation = plan.elevationUnitConfirmation else { return metersPerUnit(file) }
        guard file.units == .unknown, confirmation.confirmedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return unitFactor(confirmation.units, insertionUnits: file.insertionUnits)
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
            return failure(file.units == .unknown
                ? "Единицы чертежа не подтверждены. Уточните единицы по исходному файлу."
                : "Подтверждённые единицы противоречат $INSUNITS или не поддерживаются.")
        }
        guard !document.elevationSegments.isEmpty else {
            return failure(document.elevationExclusions.keys.contains(where: { $0.contains("неподдерживаем") || $0.contains("OCS") || $0.contains("bulge") })
                ? "Нет допустимой высотной геометрии: есть неподдерживаемые объекты. См. исключения ниже."
                : "Нет сегментов с явными достоверными Z; 2D-геометрия и подписи отметок не задают высоту.")
        }
        return nearestEstimate(point, document: document, plan: plan, factor: factor, policy: policy)
    }

    /// Bounded BVH disk query. Independent projections, no tangent/topology classification.
    private static func nearestEstimate(_ point: PlanPoint, document: DXFDocument, plan: MappingPlanReference,
                                        factor: Double, policy: PlanElevationSnapPolicy) -> PlanElevationResolution {
        let index = document.elevationIndex
        let nearby = index.nearby(point, radius: policy.radius / factor)
        func unavailable(_ reason: String) -> PlanElevationResolution {
            PlanElevationResolution(candidates: [], requiresChoice: false, failureReason: reason)
        }
        guard let firstID = nearby.first else {
            return unavailable("Нет высотной геометрии рядом. Введите Z в картировании.")
        }
        let first = index.segments[firstID], a = first.projection(point)!
        let second = nearby.first { index.segments[$0].wallID != first.wallID }.map { index.segments[$0] }
        // Check overlaps at each source projection, including self-overlaps of one polyline.
        // A local BVH query also finds a duplicated level whose tap distance is slightly larger.
        for segment in (a.distance == 0 ? [first] : [first, second].compactMap({ $0 })) {
            let projected = PlanWallSection.position(segment, at: point)
            let z = segment.projection(projected)!.z * factor
            let overlap = index.nearby(projected, radius: policy.similarDistanceMeters / factor)
                .compactMap { index.segments[$0].projection(projected).map { $0.z * factor } }
            if let low = (overlap + [z]).min(), let high = (overlap + [z]).max(),
               high - low > policy.distinctElevationMeters {
                return unavailable("Перекрытие DXF с разными Z. Введите Z вручную.")
            }
        }
        // An exact hit uses that segment after overlap validation, without mixing another wall.
        let b = a.distance == 0 ? nil : second?.projection(point)
        if let b, abs(a.z * factor - b.z * factor) > policy.levelDifference {
            return unavailable("Большой перепад Z: возможны разные уровни. Введите Z вручную.")
        }
        // Include equally close competing sources so a third coincident level cannot hide behind ties.
        let limit = (b?.distance ?? a.distance) + policy.similarDistanceMeters / factor
        let elevations = nearby.prefix { index.segments[$0].projection(point)!.distance <= limit }
            .map { index.segments[$0].projection(point)!.z * factor }
        if a.distance > 0, let low = elevations.min(), let high = elevations.max(), high - low > policy.levelDifference {
            return unavailable("Большой перепад Z: возможны разные уровни. Введите Z вручную.")
        }
        let z = b.map { PlanWallSection.elevation(a.z * factor, $0.z * factor, a.distance * factor, $0.distance * factor) } ?? a.z * factor
        guard z.isFinite else { return unavailable("Недопустимая отметка DXF. Введите Z вручную.") }
        var proposal = PlanGeometryElevation(method: PlanGeometryElevation.nearestVersion,
            planID: plan.id, planRevision: plan.version, planSHA256: plan.file!.sha256,
            segment: first, selectedXY: point, parameter: a.t, distanceMeters: a.distance * factor,
            elevationMeters: z, metersPerDrawingUnit: factor, unitDeclaration: plan.elevationUnitDeclaration,
            unitConfirmedAt: plan.elevationUnitConfirmation?.confirmedAt, policy: policy)
        if let b, let second {
            proposal.secondWall = PlanElevationWallSample(segment: second, parameter: b.t,
                distanceMeters: b.distance * factor, elevationMeters: b.z * factor)
        }
        return PlanElevationResolution(candidates: [proposal], requiresChoice: false,
            failureReason: b == nil && a.distance > 0 ? "Приблизительная Z по одному сегменту." : nil,
            nearestDistanceMeters: a.distance * factor)
    }
}

struct PlanElevationWallSample: Codable, Equatable {
    let segment: DXFElevationSegment
    let parameter: Double
    let distanceMeters: Double
    let elevationMeters: Double

    func valid(at point: PlanPoint, factor: Double) -> Bool {
        guard ["LINE", "POLYLINE", "LWPOLYLINE"].contains(segment.entityType),
              segment.entityOrdinal >= 0, segment.segmentIndex >= 0,
              segment.extractionVersion == nil || segment.extractionVersion == DXFDocument.elevationExtractionVersion,
              segment.blockPath == nil || (segment.blockPath?.isEmpty == false && segment.blockPath!.count <= 8),
              let p = segment.projection(point) else { return false }
        return parameter == p.t && distanceMeters == p.distance * factor && elevationMeters == p.z * factor
    }
}
