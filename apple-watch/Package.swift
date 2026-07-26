// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RelayWatchCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "RelayWatchCore", targets: ["RelayWatchCore"]),
    ],
    targets: [
        .target(
            name: "RelayWatchCore",
            path: "RelayWatch",
            exclude: [
                "Assets.xcassets",
                "RelayWatchApp.swift",
                "RelayWatchModel.swift",
                "RelayWatchRootView.swift",
            ],
            sources: [
                "RelayAPIClient.swift",
                "RelayProtocol.swift",
                "WatchIdentity.swift",
            ]
        ),
        .testTarget(
            name: "RelayWatchCoreTests",
            dependencies: ["RelayWatchCore"],
            path: "Tests"
        ),
    ]
)
