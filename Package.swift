// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Chimlo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChimloCore", targets: ["ChimloCore"]),
        .library(name: "ChimloProtocol", targets: ["ChimloProtocol"]),
    ],
    targets: [
        .target(name: "ChimloCore"),
        .target(
            name: "ChimloProtocol",
            dependencies: ["ChimloCore"]
        ),
        .testTarget(
            name: "ChimloCoreTests",
            dependencies: ["ChimloCore"]
        ),
        .testTarget(
            name: "ChimloProtocolTests",
            dependencies: ["ChimloCore", "ChimloProtocol"]
        ),
    ]
)
