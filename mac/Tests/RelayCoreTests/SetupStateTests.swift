import Testing
@testable import RelayCore

@Test
func setupIsReadyOnlyWhenEveryRequiredCheckPasses() {
    let state = SetupState(
        codex: .ready,
        account: .ready,
        bridge: .ready,
        watchPaired: true,
        cloud: .ready
    )

    #expect(state.isReady)
    #expect(
        !SetupState(
            codex: .ready,
            account: .missing,
            bridge: .ready,
            watchPaired: true,
            cloud: .ready
        ).isReady
    )
}
