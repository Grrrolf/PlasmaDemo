// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlasmaDemo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PlasmaDemo", targets: ["PlasmaDemo"])
    ],
    targets: [
        .executableTarget(
            name: "PlasmaDemo",
            path: "Sources/PlasmaDemo"
        )
    ]
)
