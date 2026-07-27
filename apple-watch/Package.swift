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
                "RelayWatchHomeView.swift",
                "RelayPairingViews.swift",
                "RelayApprovalView.swift",
                "RelayAudioRecorder.swift",
                "RelayComposeViews.swift",
                "RelayQuestionView.swift",
                "RelayTaskViews.swift",
                "RelayVoiceView.swift",
                "RelayWatchComponents.swift",
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
                "RelayWatchNavigation.swift",
                "RelayNewTaskFlow.swift",
                "RelayWatchService.swift",
                "RelayWatchStyle.swift",
                "RelayWatchTypes.swift",
                "RelayVoiceLifecycle.swift",
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
