// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlasmaDemo",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PlasmaDemo",
            path: "Sources/PlasmaDemo"
        )
    ]
)
