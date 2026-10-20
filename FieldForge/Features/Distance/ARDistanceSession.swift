import ARKit
import SceneKit
import UIKit

/// Camera/depth adapter only. No mapping, orientation, GPS or persistence services.
@MainActor final class ARDistanceSession: NSObject, DistanceSession, ARSessionDelegate {
    let view = ARSCNView(frame: .zero)
    var onInterruption: (() -> Void)?
    var onInterruptionEnded: (() -> Void)?
    var onFailure: (() -> Void)?
    var onTrackingLoss: ((DistanceStatus) -> Void)?
    private var usesDepth = false
    private var active = false
    private var sessionStartedAt: TimeInterval = .infinity
    private let markers = SCNNode()

    override init() {
        super.init()
        view.scene = SCNScene()
        view.scene.rootNode.addChildNode(markers)
        view.automaticallyUpdatesLighting = false
        view.session.delegateQueue = .main
        view.session.delegate = self
    }
    static var supported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }
    func start() {
        guard Self.supported else { return }
        active = true
        sessionStartedAt = ProcessInfo.processInfo.systemUptime
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        usesDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        if usesDepth { configuration.frameSemantics.insert(.sceneDepth) }
        view.isPlaying = true
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    func pause() {
        active = false
        view.session.pause()
        view.isPlaying = false
        render(first: nil, second: nil)
    }
    func snapshot() -> DistanceSnapshot {
        guard active, let frame = view.session.currentFrame,
              DistanceSnapshot.acceptsFrame(timestamp: frame.timestamp, sessionStartedAt: sessionStartedAt,
                                            now: ProcessInfo.processInfo.systemUptime) else {
            return .init(status: .starting, point: nil)
        }
        if let reason = trackingProblem(frame.camera.trackingState) {
            return .init(status: reason, point: nil)
        }
        let point: DistancePoint?
        if usesDepth {
            // Never relabel a visual estimate as LiDAR when depth is missing.
            point = depthPoint(frame)
        } else if let query = view.raycastQuery(from: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                                                allowing: .existingPlaneGeometry, alignment: .any),
                  let hit = view.session.raycast(query).first {
            let p = hit.worldTransform.columns.3
            point = .init(position: .init(x: Double(p.x), y: Double(p.y), z: Double(p.z)), source: .detectedPlane)
        } else { point = nil }
        return .init(status: point == nil ? .noSurface : .ready, point: point)
    }
    private func depthPoint(_ frame: ARFrame) -> DistancePoint? {
        guard let depth = frame.sceneDepth, let confidence = depth.confidenceMap,
              let orientation = view.window?.windowScene?.interfaceOrientation,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        // Undo aspect-fill crop and interface rotation to locate the same aim in depth/image space.
        let imagePoint = CGPoint(x: 0.5, y: 0.5).applying(
            frame.displayTransform(for: orientation, viewportSize: view.bounds.size).inverted())
        guard (0..<1).contains(imagePoint.x), (0..<1).contains(imagePoint.y) else { return nil }
        let map = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0,
              CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height else { return nil }
        let x = min(width - 1, Int(imagePoint.x * CGFloat(width)))
        let y = min(height - 1, Int(imagePoint.y * CGFloat(height)))
        guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(map),
              let confidenceBytes = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let level = confidenceBytes.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence) + x).load(as: UInt8.self)
        guard level == ARConfidenceLevel.high.rawValue else { return nil }
        let d = bytes.advanced(by: y * CVPixelBufferGetBytesPerRow(map) + x * MemoryLayout<Float32>.size).load(as: Float32.self)
        let intrinsics = frame.camera.intrinsics
        let size = frame.camera.imageResolution
        // Use the sampled depth-pixel centre, scaled to captured-image intrinsics.
        guard let camera = DistanceMath.cameraPoint(
            u: (Double(x) + 0.5) * Double(size.width) / Double(width),
            v: (Double(y) + 0.5) * Double(size.height) / Double(height), depth: Double(d),
            fx: Double(intrinsics[0][0]), fy: Double(intrinsics[1][1]),
            cx: Double(intrinsics[2][0]), cy: Double(intrinsics[2][1])) else { return nil }
        let world = frame.camera.transform * SIMD4<Float>(Float(camera.x), Float(camera.y), Float(camera.z), 1)
        let position = Vector3(x: Double(world.x), y: Double(world.y), z: Double(world.z))
        return position.isFinite ? .init(position: position, source: .lidarDepth) : nil
    }
    func render(first: DistancePoint?, second: DistancePoint?) {
        markers.childNodes.forEach { $0.removeFromParentNode() }
        for (index, point) in [first, second].enumerated() {
            guard let point else { continue }
            let sphere = SCNSphere(radius: 0.012)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemCyan
            sphere.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: sphere)
            node.simdPosition = simd(point.position)
            markers.addChildNode(node)
            let text = SCNText(string: "\(index + 1)", extrusionDepth: 0)
            text.font = .boldSystemFont(ofSize: 12)
            text.firstMaterial?.diffuse.contents = UIColor.white
            text.firstMaterial?.lightingModel = .constant
            let label = SCNNode(geometry: text)
            label.scale = SCNVector3(0.003, 0.003, 0.003)
            label.position = SCNVector3(0.015, 0.015, 0)
            label.constraints = [SCNBillboardConstraint()]
            node.addChildNode(label)
        }
        if let first, let second {
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: [SCNVector3(simd(first.position)), SCNVector3(simd(second.position))])],
                                       elements: [SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)])
            geometry.firstMaterial?.diffuse.contents = UIColor.systemCyan
            geometry.firstMaterial?.lightingModel = .constant
            markers.addChildNode(SCNNode(geometry: geometry))
        }
    }
    private func simd(_ v: Vector3) -> SIMD3<Float> { .init(Float(v.x), Float(v.y), Float(v.z)) }
    private func trackingProblem(_ state: ARCamera.TrackingState) -> DistanceStatus? {
        switch state {
        case .normal: return nil
        case .limited(.insufficientFeatures): return .insufficientFeatures
        case .limited(.excessiveMotion): return .excessiveMotion
        case .limited(.initializing): return .starting
        default: return .poorTracking
        }
    }
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        MainActor.assumeIsolated {
            guard active, let reason = trackingProblem(camera.trackingState) else { return }
            onTrackingLoss?(reason)
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { onInterruption?() }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { onInterruptionEnded?() }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { onFailure?() }
    }
}
