// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caliper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CaliperCore"),
        .executableTarget(name: "CaliperApp", dependencies: ["CaliperCore"]),
        .testTarget(name: "CaliperCoreTests", dependencies: ["CaliperCore"]),
    ]
)
