// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "RelayCore", targets: ["RelayCore"]),
        .executable(name: "RelayMac", targets: ["RelayMac"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        ),
    ],
    targets: [
        .target(
            name: "RelayCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "RelayCoreTests",
            dependencies: ["RelayCore"]
        ),
        .executableTarget(
            name: "RelayMac",
            dependencies: [
                "RelayCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "RelayMacTests",
            dependencies: ["RelayMac"]
        ),
    ]
)
