// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GolfKit",
    platforms: [.iOS("18.2"), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "GolfCore", targets: ["GolfCore"]),
        .library(name: "GolfSync", targets: ["GolfSync"]),
        .library(name: "GolfDesign", targets: ["GolfDesign"]),
    ],
    targets: [
        .target(name: "GolfCore"),
        .target(name: "GolfSync", dependencies: ["GolfCore"]),
        .target(name: "GolfDesign"),
        .testTarget(
            name: "GolfCoreTests",
            dependencies: ["GolfCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GolfSyncTests", dependencies: ["GolfSync", "GolfCore"]),
        .testTarget(name: "GolfDesignTests", dependencies: ["GolfDesign"]),
    ]
)
