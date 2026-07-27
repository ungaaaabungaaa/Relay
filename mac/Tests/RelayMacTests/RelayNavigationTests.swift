import Foundation
import Testing
import RelayCore
@testable import RelayMac

@Test
func relayMenuRootExposesEveryReleaseControl() {
    #expect(
        RelayMenuStructure.root.map(\.rawValue) == [
            "status",
            "actions",
            "connection",
            "maintenance",
            "lifecycle",
        ]
    )
    #expect(
        RelayMenuStructure.root
            .flatMap(\.items)
            .map(\.title) == [
            "Status",
            "Pending Actions",
            "Apple Watch",
            "Workspaces",
            "Relay Cloud",
            "Voice and Transcription",
            "Start at Login",
            "Diagnostics",
            "Updates",
            "About",
            "Emergency Stop",
            "Quit",
        ]
    )
    #expect(!RelayMenuItem.allCases.map(\.title).contains("Open Dashboard"))
}

@Test
func relayMenuPresentationFormatsOnlySafeOperationalText() {
    #expect(
        RelayMenuPresentation.statusRows(
            bridgeState: .running,
            codexStatus: "Ready",
            cloudPhase: .retrying(attempt: 2, delaySeconds: 4),
            activeDeviceCount: 2
        ) == [
            "Bridge running",
            "Codex ready",
            "Relay Cloud retrying in 4s",
            "2 watches",
        ]
    )
    #expect(
        RelayMenuPresentation.pairingExpiryLabel(
            expiresAt: 1_120_000,
            now: Date(timeIntervalSince1970: 1_000)
        ) == "Expires in 2m"
    )
    #expect(
        RelayMenuPresentation.workspaceDisplayName("/Users/relay/Projects")
            == "Projects"
    )

    let diagnostic = RelayMenuPresentation.safeDiagnostic(
        bridgeState: .running,
        cloudPhase: .connected,
        diagnostic: "token=private-value; local security self-test passed"
    )
    #expect(diagnostic.contains("Bridge: running"))
    #expect(diagnostic.contains("Relay Cloud: connected"))
    #expect(diagnostic.contains("[redacted]"))
    #expect(!diagnostic.contains("private-value"))
}
