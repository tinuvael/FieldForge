// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FieldForgeCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "FieldForgeCore", targets: ["FieldForgeCore"])],
    targets: [
        .target(name: "FieldForgeCore", path: "FieldForge",
                exclude: ["App", "Features", "Resources", "Core/Sensors/CoreMotionSensorProvider.swift"],
                sources: ["Core", "Data", "Services"]),
        .testTarget(name: "FieldForgeCoreTests", dependencies: ["FieldForgeCore"], path: "Tests")
    ]
)
