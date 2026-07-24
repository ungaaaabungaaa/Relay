import Testing
@testable import RelayCore

@Test
func setupIsReadyOnlyWhenEveryRequiredCheckPasses() {
    let state = SetupState(
        codex: .ready,
        tailscale: .ready,
        bridge: .ready,
        watchInstalled: true,
        watchPaired: true,
        remoteAccess: .ready
    )

    #expect(state.isReady)
    #expect(
        !SetupState(
            codex: .ready,
            tailscale: .missing,
            bridge: .ready,
            watchInstalled: true,
            watchPaired: true,
            remoteAccess: .ready
        ).isReady
    )
}
