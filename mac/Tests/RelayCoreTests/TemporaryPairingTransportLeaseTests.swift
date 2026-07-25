import Testing
@testable import RelayCore

private actor CloseCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

@Test
func temporaryPairingTransportClosesWhenSessionExpires() async throws {
    let counter = CloseCounter()
    let lease = TemporaryPairingTransportLease()

    await lease.start(for: .milliseconds(20)) {
        await counter.increment()
    }
    try await Task.sleep(for: .milliseconds(80))

    #expect(await counter.count == 1)
}

@Test
func temporaryPairingTransportClosesOnlyOnce() async {
    let counter = CloseCounter()
    let lease = TemporaryPairingTransportLease()

    await lease.start(for: .seconds(5)) {
        await counter.increment()
    }
    await lease.finish()
    await lease.finish()

    #expect(await counter.count == 1)
}

@Test
func promotedPairingTransportStaysOpen() async throws {
    let counter = CloseCounter()
    let lease = TemporaryPairingTransportLease()

    await lease.start(for: .milliseconds(20)) {
        await counter.increment()
    }
    await lease.promote()
    try await Task.sleep(for: .milliseconds(80))

    #expect(await counter.count == 0)
}

@Test
func restartingPairingTransportReplacesTheTimerWithoutClosing() async {
    let counter = CloseCounter()
    let lease = TemporaryPairingTransportLease()

    await lease.start(for: .seconds(5)) {
        await counter.increment()
    }
    await lease.start(for: .seconds(5)) {
        await counter.increment()
    }

    #expect(await counter.count == 0)
    await lease.finish()
    #expect(await counter.count == 1)
}
