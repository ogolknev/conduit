// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Conduit",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Conduit", targets: ["Conduit"])],
    targets: [
        .target(name: "ConduitCore"),
        .executableTarget(name: "Conduit", dependencies: ["ConduitCore"]),
        .testTarget(name: "ConduitCoreTests", dependencies: ["ConduitCore"])
    ]
)
