import SwiftUI
import SceneKit
import simd

struct WedgeScenePlane: Equatable {
    let identifier: String
    let normal: Vector3
}

struct WedgeSceneView: UIViewRepresentable {
    let dimensions: WedgeDimensions
    let planes: [WedgeScenePlane]
    let axisAzimuth: Double?
    final class Coordinator {
        var dimensions: WedgeDimensions?
        var planes: [WedgeScenePlane] = []
        var axis: Double?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .secondarySystemBackground
        view.antialiasingMode = .multisampling4X
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let state = context.coordinator
        guard state.dimensions != dimensions || state.planes != planes || state.axis != axisAzimuth else { return }
        state.dimensions = dimensions; state.planes = planes; state.axis = axisAzimuth
        let scene = SCNScene()
        let arch = WedgeArch(dimensions)
        let mesh = arch.mesh()
        let scale = 10 / dimensions.scale
        // Core (X right, Y forward, Z up) -> SceneKit (X right, Y up, -Z forward).
        func point(_ v: Vector3) -> SCNVector3 { SCNVector3(Float(v.x * scale), Float(v.z * scale), Float(-v.y * scale)) }
        func direction(_ v: Vector3) -> SCNVector3 { SCNVector3(Float(v.x), Float(v.z), Float(-v.y)) }
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        for offset in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let a = mesh.vertices[Int(mesh.triangles[offset])]
            let b = mesh.vertices[Int(mesh.triangles[offset + 1])]
            let c = mesh.vertices[Int(mesh.triangles[offset + 2])]
            // Normalize edges before cross product to keep normals finite at extreme scales.
            guard let ab = (b - a).normalized(), let ac = (c - a).normalized(), let n = ab.cross(ac).normalized() else { continue }
            vertices += [point(a), point(b), point(c)]; normals += Array(repeating: direction(n), count: 3)
        }
        let element = SCNGeometryElement(indices: (0..<vertices.count).map(Int32.init), primitiveType: .triangles)
        let shell = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.16)
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        shell.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: shell))

        func line(_ a: SCNVector3, _ b: SCNVector3, color: UIColor, radius: CGFloat = 0.018) {
            let start = SIMD3<Float>(a.x, a.y, a.z), end = SIMD3<Float>(b.x, b.y, b.z)
            let delta = end - start
            guard simd_length(delta) > 1e-8 else { return }
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
            cylinder.radialSegmentCount = 6
            cylinder.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (start + end) / 2
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            scene.rootNode.addChildNode(node)
        }
        func label(_ text: String, at position: SCNVector3, color: UIColor = .label) {
            let geometry = SCNText(string: text, extrusionDepth: 0)
            geometry.font = .systemFont(ofSize: 0.24, weight: .semibold)
            geometry.flatness = 0.1
            geometry.firstMaterial?.diffuse.contents = color
            geometry.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
        }
        for y in [0.0, dimensions.length] {
            let section = arch.section.map { point(.init(x: $0.x, y: y, z: $0.z)) }
            for i in section.indices { line(section[i], section[(i + 1) % section.count], color: .systemTeal, radius: 0.012) }
        }
        for x in [-dimensions.width / 2, dimensions.width / 2] {
            for z in [0.0, dimensions.wallHeight] {
                line(point(.init(x: x, y: 0, z: z)), point(.init(x: x, y: dimensions.length, z: z)), color: .systemTeal, radius: 0.012)
            }
        }
        line(point(.init(x: 0, y: 0, z: 0)), point(.init(x: 0, y: dimensions.length, z: 0)), color: .systemOrange)
        let axisLabel = axisAzimuth.map { "Y → \($0.formatted(.number.precision(.fractionLength(1))))°" } ?? "Y → ось; азимут не задан"
        label(axisLabel, at: point(.init(x: 0, y: dimensions.length, z: 0)), color: .systemOrange)
        let cue = min(dimensions.width, dimensions.height) * 0.35
        line(point(.init(x: 0, y: 0, z: 0)), point(.init(x: cue, y: 0, z: 0)), color: .systemRed)
        line(point(.init(x: 0, y: 0, z: 0)), point(.init(x: 0, y: 0, z: cue)), color: .systemBlue)
        label("X →", at: point(.init(x: cue, y: 0, z: 0)), color: .systemRed)
        label("Z ↑", at: point(.init(x: 0, y: 0, z: cue)), color: .systemBlue)
        label("B \(DistanceMath.text(dimensions.width))", at: point(.init(x: -dimensions.width / 2, y: 0, z: -cue * 0.4)))
        label("H \(DistanceMath.text(dimensions.height))", at: point(.init(x: dimensions.width / 2, y: 0, z: dimensions.height)))
        label("L \(DistanceMath.text(dimensions.length))", at: point(.init(x: dimensions.width / 2, y: dimensions.length / 2, z: 0)))

        let center = point(.init(x: 0, y: dimensions.length / 2, z: dimensions.height / 2))
        let halfSize = max(dimensions.width, dimensions.height) * 0.8 * scale
        let colors: [UIColor] = [.systemPink, .systemIndigo, .systemYellow]
        for (index, plane) in planes.enumerated() {
            let geometry = SCNPlane(width: CGFloat(2 * halfSize), height: CGFloat(2 * halfSize))
            let m = SCNMaterial()
            m.diffuse.contents = colors[index % colors.count].withAlphaComponent(0.32)
            m.isDoubleSided = true; m.writesToDepthBuffer = false; m.lightingModel = .constant
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            node.position = center
            let n = direction(plane.normal)
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(SIMD3<Float>(n.x, n.y, n.z)))
            scene.rootNode.addChildNode(node)
            let location = node.convertPosition(SCNVector3(Float(-halfSize * 0.9), Float(halfSize * 0.85), 0), to: nil)
            label(plane.identifier, at: location, color: colors[index % colors.count])
        }
        for i in planes.indices {
            for j in planes.indices where j > i {
                guard let trace = WedgePlaneGeometry.intersection(planes[i].normal, planes[j].normal) else { continue }
                let d = direction(trace), extent = Float(halfSize * 0.9)
                line(SCNVector3(center.x - d.x * extent, center.y - d.y * extent, center.z - d.z * extent),
                     SCNVector3(center.x + d.x * extent, center.y + d.y * extent, center.z + d.z * extent), color: .label, radius: 0.013)
            }
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01; camera.camera?.zFar = 200
        camera.position = SCNVector3(center.x + 10, center.y + 7, center.z + 14)
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)
        view.scene = scene; view.pointOfView = camera
        view.defaultCameraController.target = center
        view.defaultCameraController.interactionMode = .orbitTurntable
    }
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { uiView.scene = nil }
}
