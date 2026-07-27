import Testing
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
