import Testing
@testable import RelayCore

@Test
func cloudTunnelStatePublishesOpenAndCappedRetrySequence() {
    var state = RelayCloudTunnelState()
    var delays: [Int] = []
    for _ in 0..<7 {
        state.begin()
        delays.append(state.failed(.recoverable)!)
    }
    #expect(delays == [1, 2, 4, 8, 16, 30, 30])
    state.begin()
    #expect(state.phase == .connecting(attempt: 8))
    state.opened()
    #expect(state.phase == .connected)
    state.begin()
    #expect(state.phase == .connecting(attempt: 1))
}

@Test
func cloudTunnelStateStopsRetryingForAuthenticationAndIncompatibility() {
    var state = RelayCloudTunnelState()
    state.begin()
    #expect(state.failed(.authentication) == nil)
    #expect(state.phase == .signedOut)
    state.begin()
    #expect(state.failed(.incompatible) == nil)
    #expect(state.phase == .stopped)
}
