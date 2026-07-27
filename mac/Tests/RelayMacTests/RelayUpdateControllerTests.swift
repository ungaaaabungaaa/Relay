import Testing
@testable import RelayMac

@MainActor
@Test
func updateControllerPublishesRedactedSparkleStates() {
    let controller = RelayUpdateController(startUpdater: false)
    #expect(controller.state == .unknown)
    controller.recordChecking()
    #expect(controller.state == .checking)
    controller.recordCurrent()
    #expect(controller.state == .current)
    controller.recordAvailable(version: "1.2.3")
    #expect(controller.state == .available(version: "1.2.3"))
    controller.recordFailure(code: 999)
    #expect(controller.state == .failed(.unavailable))
    controller.recordFailure(code: 4_007)
    #expect(controller.state == .unknown)
}
