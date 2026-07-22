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
        .executable(name: "ChimloApp", targets: ["ChimloApp"]),
        .executable(name: "chimlo", targets: ["ChimloCLI"]),
        .executable(name: "chimlo-check", targets: ["ChimloChecks"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        ),
    ],
    targets: [
        .target(name: "ChimloCore"),
        .target(
            name: "ChimloProtocol",
            dependencies: ["ChimloCore"]
        ),
        .executableTarget(
            name: "ChimloApp",
            dependencies: [
                "ChimloCore",
                "ChimloProtocol",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "ChimloCLI",
            dependencies: ["ChimloCore", "ChimloProtocol"]
        ),
        .executableTarget(
            name: "ChimloChecks",
            dependencies: ["ChimloCore", "ChimloProtocol"]
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
