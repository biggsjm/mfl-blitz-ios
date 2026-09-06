// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MFLCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "MFLCore", targets: ["MFLCore"]),
    ],
    targets: [
        .target(name: "MFLCore"),
        .testTarget(
            name: "MFLCoreTests",
            dependencies: ["MFLCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
