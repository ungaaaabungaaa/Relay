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
                "RelayApprovalView.swift",
                "RelayComposeViews.swift",
                "RelayInboxViews.swift",
                "RelayQuestionView.swift",
                "RelayTaskViews.swift",
            ],
            sources: [
                "RelayAPIClient.swift",
                "RelayProtocol.swift",
                "RelayEndpoint.swift",
                "RelayEnvironment.swift",
                "RelayReconnectPolicy.swift",
                "RelayPairingState.swift",
                "RelaySocket.swift",
                "RelayWatchFeature.swift",
                "RelayWatchService.swift",
                "RelayWatchTypes.swift",
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
