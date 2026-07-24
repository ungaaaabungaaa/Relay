// swift-tools-version: 6.2

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
            dependencies: ["RelayCore"]
        ),
        .testTarget(
            name: "RelayMacTests",
            dependencies: ["RelayMac"]
        ),
    ]
)
