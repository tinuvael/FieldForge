import Foundation

/// Transient AR-local coordinates, metres; never mine/survey coordinates.
struct DistancePoint: Equatable {
    enum Source: Equatable {
        case lidarDepth, detectedPlane
        var label: String {
            self == .lidarDepth ? "Глубина LiDAR" : "Оценка по плоскости · без LiDAR"
        }
    }
    let position: Vector3
    let source: Source
}

/// In-memory result only; preserve the unrounded value after closing the camera.
struct DistanceResult: Equatable {
    let metres: Double
    let source: DistancePoint.Source
    var text: String { DistanceMath.text(metres) + " · " + source.label }
}

enum DistanceMath {
    /// Euclidean metric in R³ (OpenStax Calculus Vol. 3, 2016, §2.2, Eq. 2.1); no rounding.
    static func metres(from a: Vector3, to b: Vector3) -> Double? {
        guard a.isFinite, b.isFinite else { return nil }
        let distance = (b - a).length
        return distance.isFinite && distance > 0 ? distance : nil
    }

    /// Pinhole back-projection: image +Y down to AR camera +Y up, -Z forward.
    /// Inputs use captured-image pixels and axial depth in metres (ARDepthData).
    static func cameraPoint(u: Double, v: Double, depth: Double,
                            fx: Double, fy: Double, cx: Double, cy: Double) -> Vector3? {
        guard [u, v, depth, fx, fy, cx, cy].allSatisfy(\.isFinite), depth > 0, fx > 0, fy > 0 else { return nil }
        let point = Vector3(x: (u - cx) * depth / fx, y: -(v - cy) * depth / fy, z: -depth)
        return point.isFinite ? point : nil
    }

    static func text(_ metres: Double) -> String {
        EngineeringDisplay.number(metres) + " м"
    }
}

enum DistanceStatus: Equatable, Sendable {
    case starting, ready, noSurface, poorTracking, insufficientFeatures, excessiveMotion
    case interrupted, background, closed, cameraDenied, unsupported, failed
    var message: String {
        switch self {
        case .starting: return "Осмотрите поверхность камерой. Подготовка AR…"
        case .ready: return "Наведите прицел на поверхность"
        case .noSurface: return "Нет надёжной поверхности или глубины. Измените ракурс и попробуйте снова."
        case .poorTracking: return "Положение камеры ненадёжно. Осмотрите поверхность; начните замер заново."
        case .insufficientFeatures: return "Недостаточно деталей или света. Осветите поверхность и измените ракурс."
        case .excessiveMotion: return "Двигайте iPhone медленнее. Начните замер заново."
        case .interrupted: return "Сеанс AR прерван. Выбранные точки сброшены."
        case .background: return "Камера остановлена. После возврата начните замер заново."
        case .closed: return "Камера остановлена"
        case .cameraDenied: return "Нет доступа к камере. Разрешите его в Настройках iOS → FieldForge."
        case .unsupported: return "AR-измерение недоступно на этом устройстве. В Simulator нет камеры AR и LiDAR."
        case .failed: return "Ошибка сеанса AR. Нажмите «Повторить» или закройте инструмент."
        }
    }
    var invalidatesPoints: Bool {
        switch self {
        case .ready, .noSurface: return false
        default: return true
        }
    }
}

struct DistanceSnapshot {
    let status: DistanceStatus
    let point: DistancePoint?

    static func acceptsFrame(timestamp: TimeInterval, sessionStartedAt: TimeInterval, now: TimeInterval) -> Bool {
        [timestamp, sessionStartedAt, now].allSatisfy(\.isFinite)
            && timestamp >= sessionStartedAt && timestamp <= now && now - timestamp < 0.5
    }
}

/// Real ARKit is a boundary adapter. Tests supply snapshots, never simulated LiDAR.
@MainActor protocol DistanceSession: AnyObject {
    func start()
    func pause()
    func snapshot() -> DistanceSnapshot
}

@MainActor final class DistanceMeasurementController {
    private let session: DistanceSession
    private(set) var running = false
    private(set) var status: DistanceStatus = .closed
    private(set) var first: DistancePoint?
    private(set) var second: DistancePoint?
    private(set) var metres: Double?
    private(set) var candidate: DistancePoint?
    private(set) var needsRetake = false

    init(session: DistanceSession) { self.session = session }
    var result: DistanceResult? {
        guard let metres, let first, let second else { return nil }
        let source: DistancePoint.Source = first.source == .lidarDepth && second.source == .lidarDepth ? .lidarDepth : .detectedPlane
        return .init(metres: metres, source: source)
    }
    var canSelect: Bool { running && status == .ready && candidate != nil && metres == nil && !needsRetake }

    func start() {
        guard !running else { return }
        clear(); status = .starting; running = true
        session.start()
    }
    func stop(_ reason: DistanceStatus) {
        if running { session.pause() }
        running = false; clear(); status = reason
    }
    func retake() {
        stop(.closed)
        start()
    }
    func trackingLost(_ reason: DistanceStatus) {
        guard running, reason.invalidatesPoints else { return }
        apply(.init(status: reason, point: nil))
    }
    func refresh() {
        guard running else { return }
        apply(session.snapshot())
    }
    func select() {
        guard running, metres == nil, !needsRetake else { return }
        // Re-query on tap: never select a cached preview or stale AR frame.
        refresh()
        guard canSelect, let candidate else { return }
        if let first {
            guard let distance = DistanceMath.metres(from: first.position, to: candidate.position) else {
                status = .noSurface; self.candidate = nil; return
            }
            second = candidate; metres = distance
        } else { first = candidate }
    }
    private func apply(_ snapshot: DistanceSnapshot) {
        status = snapshot.status
        candidate = snapshot.status == .ready && snapshot.point?.position.isFinite == true ? snapshot.point : nil
        if status == .ready && candidate == nil { status = .noSurface }
        if status.invalidatesPoints {
            // Tracking recovery cannot silently revalidate an earlier pair.
            needsRetake = needsRetake || first != nil
            first = nil; second = nil; metres = nil; candidate = nil
        }
    }
    private func clear() {
        first = nil; second = nil; metres = nil; candidate = nil; needsRetake = false
    }
}

/// Adapter callback identity/lifetime only; independent of ARKit and distance math.
/// An interruption end is accepted only for the interrupted session, never after dismissal.
struct DistanceCallbackLifetime {
    private var sessionID: ObjectIdentifier?
    private var active = false
    private var interrupted = false
    mutating func start(_ identity: ObjectIdentifier) {
        sessionID = identity; active = true; interrupted = false
    }
    func accepts(_ identity: ObjectIdentifier) -> Bool { active && sessionID == identity }
    mutating func interrupt(_ identity: ObjectIdentifier) -> Bool {
        guard accepts(identity) else { return false }
        active = false; interrupted = true; return true
    }
    mutating func endInterruption(_ identity: ObjectIdentifier) -> Bool {
        guard interrupted, sessionID == identity else { return false }
        interrupted = false; return true
    }
    mutating func pause() { active = false }
    mutating func invalidate() { active = false; interrupted = false; sessionID = nil }
}
